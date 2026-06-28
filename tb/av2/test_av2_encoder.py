import json
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge
from av2_metrics import (
    AV2_PHASE_INTRABC,
    AV2_PHASE_INTRA,
    AV2_PHASE_PALETTE_HEADER,
    AV2_PHASE_PALETTE_MAP,
    AV2_PHASE_U_COEFF,
    AV2_PHASE_V_COEFF,
    AV2_PHASE_Y_COEFF,
    AV2_STATE_CHROMA_FETCH,
    AV2_STATE_LEAF,
    AV2_STATE_NAMES,
    AV2_STATE_PARTITION,
    write_av2_cycle_metrics,
)
from block_waveform import BlockWaveformWriter, block_state
from encoder_axi import (
    AXI_DST_BASE,
    REG_ENCODED_BYTE_COUNT,
    REG_STATUS,
    STATUS_AXI_ERROR,
    STATUS_INPUT_ERROR,
    STATUS_DONE,
    axi_read_memory_model,
    axi_write_memory_model,
    axil_read,
    planar_memory_image,
    program_encoder_control,
    read_output_bytes,
    reset_axi_memory_signals,
    reset_axil_signals,
    start_encoder_via_axil,
)

AV2_BLOCK_WAVEFORM_BLOCKS = [
    "axi_reader",
    "input_fifo",
    "palette_analyzer",
    "av2_core",
    "luma_residual",
    "chroma_residual",
    "entropy_coder",
    "axi_writer",
]
AV2_STATE_NAMES_INV = {name: state for state, name in AV2_STATE_NAMES.items()}
AV2_ANALYZER_STATE_NAMES = {
    0: "idle",
    1: "read",
    2: "block_init",
    3: "collect_packet",
    4: "pad",
    5: "sort",
    6: "store_colors",
    7: "map",
    8: "next_block",
    9: "drain_chroma",
    10: "done",
}
AV2_RESIDUAL_EMIT_STATE_NAMES = {
    0: "skip",
    1: "eob",
    2: "eob_extra_bit",
    3: "eob_extra_literal",
    4: "base_scan",
    5: "br",
    6: "dc_base",
    7: "sign_scan",
    8: "hr_cmax_zeros",
    9: "hr_exp_prefix",
    10: "hr_exp_value",
    11: "hr_q_zeros",
    12: "hr_one",
    13: "hr_low_bits",
    14: "hr_pack",
}


def rtl_geometry():
    return (
        int(os.environ.get("RTL_VISIBLE_WIDTH", "64")),
        int(os.environ.get("RTL_VISIBLE_HEIGHT", "64")),
    )


def rtl_chroma_format_idc():
    return int(os.environ.get("RTL_CHROMA_FORMAT_IDC", "3"))


def rtl_frame_count():
    frames = int(os.environ.get("FRAMEFORGE_RTL_AV2_ENCODER_FRAMES", "1"))
    assert frames >= 1, f"AV2 RTL frame count must be positive, got {frames}"
    return frames


def av2_frame_layout():
    width, height = rtl_geometry()
    chroma_format = rtl_chroma_format_idc()
    area = width * height
    if chroma_format == 1:
        chroma_width = width // 2
        chroma_height = height // 2
        chroma_area = chroma_width * chroma_height
        return {
            "area": area,
            "chroma_area": chroma_area,
            "length": area + 2 * chroma_area,
            "src_u_base": area,
            "src_v_base": area + chroma_area,
            "src_y_stride": width,
            "src_u_stride": chroma_width,
            "src_v_stride": chroma_width,
            "src_frame_stride": area + 2 * chroma_area,
        }
    return {
        "area": area,
        "chroma_area": area,
        "length": area * 3,
        "src_u_base": area,
        "src_v_base": area * 2,
        "src_y_stride": width,
        "src_u_stride": width,
        "src_v_stride": width,
        "src_frame_stride": area * 3,
    }


def signal_int(dut, name):
    try:
        return int(getattr(dut, name).value)
    except (AttributeError, ValueError):
        return None


def nested_signal_int(dut, path):
    handle = dut
    try:
        for name in path.split("."):
            handle = getattr(handle, name)
        return int(handle.value)
    except (AttributeError, ValueError):
        return None


def increment_counter(counters, name, value=1):
    counters[name] = counters.get(name, 0) + value


def handle_int(handle):
    try:
        return int(handle.value)
    except (AttributeError, ValueError):
        return None


def av2_input_stream():
    expected_len = av2_frame_layout()["length"] * rtl_frame_count()
    input_path = os.environ.get("FRAMEFORGE_RTL_AV2_ENCODER_INPUT")
    if input_path:
        data = Path(input_path).read_bytes()
        assert len(data) == expected_len, (
            f"AV2 RTL input length mismatch: expected {expected_len}, got {len(data)}"
        )
        return data
    return bytes(expected_len)


def av2_palette_reconstruction(data):
    expected_len = av2_frame_layout()["length"]
    assert len(data) == expected_len
    if rtl_chroma_format_idc() == 1:
        return av2_lossy_420_reconstruction(data)
    # AV2 luma palette only predicts the luma plane. The current 4:4:4 RTL then
    # emits lossless luma coefficients plus lossless chroma BDPCM, so the
    # internal reconstruction is the input frame once the residual path is
    # enabled.
    return data


def av2_stream_reconstruction(data):
    frame_len = av2_frame_layout()["length"]
    frames = rtl_frame_count()
    assert len(data) == frame_len * frames
    return b"".join(
        av2_palette_reconstruction(data[index * frame_len : (index + 1) * frame_len])
        for index in range(frames)
    )


def av2_round_div(value, divisor):
    assert divisor > 0
    if value >= 0:
        return (value + divisor // 2) // divisor
    return -((-value + divisor // 2) // divisor)


def av2_quantize_to_step(value, step):
    return av2_round_div(value, step) * step


def av2_lossy_420_predictor(recon_plane, plane_width, tile_x, tile_y, x0, y0):
    have_left = x0 > tile_x
    have_top = y0 > tile_y
    if not have_left and not have_top:
        return 128
    total = 0
    count = 0
    if have_top:
        top_base = (y0 - 1) * plane_width
        for x in range(x0, x0 + 4):
            total += recon_plane[top_base + x]
            count += 1
    if have_left:
        for y in range(y0, y0 + 4):
            total += recon_plane[y * plane_width + x0 - 1]
            count += 1
    return (total + count // 2) // count


def av2_lossy_420_fill_txb(source_plane, recon_plane, plane_width, plane_height, tile_x, tile_y, x0, y0):
    predictor = av2_lossy_420_predictor(recon_plane, plane_width, tile_x, tile_y, x0, y0)
    total = 0
    for local_y in range(4):
        y = y0 + local_y
        if y >= plane_height:
            continue
        row_base = y * plane_width
        for local_x in range(4):
            x = x0 + local_x
            if x < plane_width:
                total += source_plane[row_base + x] - predictor
    average = av2_round_div(total, 16)
    delta = max(-255, min(255, av2_quantize_to_step(average, 8)))
    sample = max(0, min(255, predictor + delta))
    for local_y in range(4):
        y = y0 + local_y
        if y >= plane_height:
            continue
        row_base = y * plane_width
        for local_x in range(4):
            x = x0 + local_x
            if x < plane_width:
                recon_plane[row_base + x] = sample


def av2_lossy_420_reconstruction(data):
    width, height = rtl_geometry()
    layout = av2_frame_layout()
    area = layout["area"]
    chroma_area = layout["chroma_area"]
    chroma_width = width // 2
    chroma_height = height // 2
    y_source = data[:area]
    u_source = data[layout["src_u_base"] : layout["src_u_base"] + chroma_area]
    v_source = data[layout["src_v_base"] : layout["src_v_base"] + chroma_area]
    y_recon = bytearray(area)
    u_recon = bytearray(chroma_area)
    v_recon = bytearray(chroma_area)

    for tile_y in range(0, height, 64):
        tile_h = min(64, height - tile_y)
        for tile_x in range(0, width, 64):
            tile_w = min(64, width - tile_x)
            for y0 in range(tile_y, tile_y + tile_h, 8):
                for x0 in range(tile_x, tile_x + tile_w, 8):
                    for dy in (0, 4):
                        for dx in (0, 4):
                            av2_lossy_420_fill_txb(
                                y_source,
                                y_recon,
                                width,
                                height,
                                tile_x,
                                tile_y,
                                x0 + dx,
                                y0 + dy,
                            )
                    chroma_tile_x = tile_x // 2
                    chroma_tile_y = tile_y // 2
                    cx0 = x0 // 2
                    cy0 = y0 // 2
                    av2_lossy_420_fill_txb(
                        u_source,
                        u_recon,
                        chroma_width,
                        chroma_height,
                        chroma_tile_x,
                        chroma_tile_y,
                        cx0,
                        cy0,
                    )
                    av2_lossy_420_fill_txb(
                        v_source,
                        v_recon,
                        chroma_width,
                        chroma_height,
                        chroma_tile_x,
                        chroma_tile_y,
                        cx0,
                        cy0,
                    )

    return bytes(y_recon + u_recon + v_recon)


def av2_rtl_input_stream(data):
    width, height = rtl_geometry()
    layout = av2_frame_layout()
    expected_len = layout["length"]
    assert len(data) == expected_len
    area = layout["area"]
    chroma_area = layout["chroma_area"]
    y_plane = data[:area]
    u_plane = data[layout["src_u_base"] : layout["src_u_base"] + chroma_area]
    v_plane = data[layout["src_v_base"] : layout["src_v_base"] + chroma_area]
    stream = bytearray()
    # The AV2 top module accepts visible 8x8 block packets in 64x64
    # superblock/tile order: 64 Y samples followed by U/V samples for the
    # configured chroma format. This avoids a full-frame input buffer in RTL
    # while keeping the public block packet shape aligned with VVC.
    for tile_y in range(0, height, 64):
        tile_h = min(64, height - tile_y)
        for tile_x in range(0, width, 64):
            tile_w = min(64, width - tile_x)
            for y0 in range(tile_y, tile_y + tile_h, 8):
                for x0 in range(tile_x, tile_x + tile_w, 8):
                    for local_y in range(8):
                        row_start = (y0 + local_y) * width + x0
                        stream.extend(y_plane[row_start : row_start + 8])
                    if rtl_chroma_format_idc() == 1:
                        chroma_width = width // 2
                        for plane in (u_plane, v_plane):
                            for local_y in range(4):
                                row_start = ((y0 // 2) + local_y) * chroma_width + (x0 // 2)
                                stream.extend(plane[row_start : row_start + 4])
                    else:
                        for plane in (u_plane, v_plane):
                            for local_y in range(8):
                                row_start = (y0 + local_y) * width + x0
                                stream.extend(plane[row_start : row_start + 8])
    return bytes(stream)


def av2_rtl_trace_name(
    state,
    phase,
    step,
    partition_emit_do_split,
    partition_emit_rect,
    palette_mode,
    leaf_luma_mode,
    palette_row,
    palette_col,
    palette_cache_size,
):
    if state == AV2_STATE_PARTITION:
        if partition_emit_do_split:
            return "tile.partition.do_split"
        if partition_emit_rect:
            return "tile.partition.rect_type"
        return "tile.partition.implied"
    if phase == AV2_PHASE_INTRABC:
        return [
            "tile.intrabc.use_intrabc",
            "tile.intrabc.skip_txfm",
            "tile.intrabc.mode",
            "tile.intrabc.drl_idx",
            "tile.intrabc.drl_idx",
            "tile.intrabc.drl_idx",
        ][step] if 0 <= step <= 5 else "tile.unknown"
    if phase == AV2_PHASE_INTRA:
        if step == 1 and leaf_luma_mode in (1, 2):
            return "tile.intra.dpcm_mode_y"
        if step == 2:
            if leaf_luma_mode == 1:
                return "tile.intra.y_mode_idx_v"
            if leaf_luma_mode == 2:
                return "tile.intra.y_mode_idx_h"
            return "tile.intra.y_mode_idx_dc"
        return [
            "tile.intra.use_dpcm_y",
            "tile.intra.y_mode_set_index",
            "tile.intra.y_mode_idx_dc",
            "tile.intra.fsc_mode",
            "tile.intra.use_dpcm_uv",
            "tile.intra.dpcm_uv_horz" if palette_mode else "tile.intra.uv_mode_idx_dc",
        ][step] if 0 <= step <= 5 else "tile.unknown"
    if phase == AV2_PHASE_PALETTE_HEADER:
        color_first_step = 2 + (palette_cache_size or 0)
        if step == 0:
            return "tile.palette.y_mode_present"
        if step == 1:
            return "tile.palette.y_size_minus2"
        if step < color_first_step:
            return "tile.palette.y_color_cache"
        if step == color_first_step:
            return "tile.palette.y_color_first"
        if step == color_first_step + 1:
            return "tile.palette.y_delta_bits_minus_min"
        return "tile.palette.y_color_delta_minus1"
    if phase == AV2_PHASE_PALETTE_MAP:
        if step == 0:
            return "tile.palette.y_direction"
        if step == 1:
            return "tile.palette.y_identity_row_flag"
        if palette_row == 0 and palette_col == 0:
            return "tile.palette.y_color_index_first"
        return "tile.palette.y_color_index"
    if phase == AV2_PHASE_Y_COEFF:
        if palette_mode:
            return "tile.coeff.y.txb_all_zero_tx4x4_ctx1"
        return [
            "tile.coeff.y.txb_nonzero",
            "tile.coeff.y.eob_pt_tx4x4_eob1",
            "tile.coeff.y.dc_base_lf_eob_ctx0",
            "tile.coeff.y.dc_low_range_lf_ctx0",
            "tile.coeff.y.dc_sign_negative",
            "tile.coeff.y.dc_high_range_prefix",
            "tile.coeff.y.dc_high_range_suffix0",
            "tile.coeff.y.dc_high_range_suffix1",
            "tile.coeff.y.dc_high_range_suffix2",
        ][step] if 0 <= step <= 8 else "tile.unknown"
    if phase in (AV2_PHASE_U_COEFF, AV2_PHASE_V_COEFF):
        plane = "u" if phase == AV2_PHASE_U_COEFF else "v"
        suffix = [
            "txb_nonzero",
            "eob_pt_tx4x4_eob1",
            "dc_base_lf_eob_ctx0",
            "dc_sign_negative",
            "dc_high_range_prefix",
            "dc_high_range_suffix0",
            "dc_high_range_suffix1",
            "dc_high_range_suffix2",
        ][step] if 0 <= step <= 7 else "unknown"
        return f"tile.coeff.{plane}.{suffix}"
    return [
        "tile.coeff.uv.txb_nonzero",
        "tile.coeff.uv.eob_pt_tx4x4_eob1",
        "tile.coeff.uv.dc_base_lf_eob_ctx0",
        "tile.coeff.uv.dc_sign_negative",
        "tile.coeff.uv.dc_high_range_prefix",
        "tile.coeff.uv.dc_high_range_suffix0",
        "tile.coeff.uv.dc_high_range_suffix1",
        "tile.coeff.uv.dc_high_range_suffix2",
    ][step] if 0 <= step <= 7 else "tile.unknown"


def av2_trace_spec(name):
    if name.startswith("tile.partition."):
        return "AV2 v1.0.0 Section 5.20.3.2 partition()"
    if name.startswith("tile.intrabc."):
        return "AV2 v1.0.0 Sections 5.20.5.1 and 5.20.5.3 intra block copy syntax"
    if name.startswith("tile.intra."):
        return "AV2 v1.0.0 Sections 5.20.5.5 and 5.20.5.6 intra mode syntax"
    if name.startswith("tile.palette."):
        return "AV2 v1.0.0 Sections 5.20.8.1 and 5.20.8.4 palette syntax"
    if name.startswith("tile.coeff."):
        return "AV2 v1.0.0 Sections 5.20.7.23, 5.20.7.24, and 5.20.7.27 residual coefficient syntax"
    return "AV2 v1.0.0 tile entropy syntax"


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    reset_axil_signals(dut)
    reset_axi_memory_signals(dut)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_encoder(dut):
    await start_encoder_via_axil(dut)


@cocotb.test()
async def av2_encoder_emits_obu_stream(dut):
    await reset_dut(dut)
    input_data = av2_input_stream()
    frames = rtl_frame_count()
    width, height = rtl_geometry()
    layout = av2_frame_layout()
    axi_memory = planar_memory_image(input_data)
    cocotb.start_soon(axi_read_memory_model(dut, axi_memory))
    cocotb.start_soon(axi_write_memory_model(dut, axi_memory))
    await program_encoder_control(
        dut,
        width=width,
        height=height,
        chroma_format=rtl_chroma_format_idc(),
        frame_count=frames,
        src_y_base=0,
        src_u_base=layout["src_u_base"],
        src_v_base=layout["src_v_base"],
        src_y_stride=layout["src_y_stride"],
        src_u_stride=layout["src_u_stride"],
        src_v_stride=layout["src_v_stride"],
        src_frame_stride=layout["src_frame_stride"],
    )
    await start_encoder(dut)

    observed = []
    packet_trace_path = os.environ.get("FRAMEFORGE_RTL_AV2_PACKET_TRACE_OUT")
    packet_trace_records = []
    carry_trace_path = os.environ.get("FRAMEFORGE_RTL_AV2_CARRY_TRACE_OUT")
    carry_trace_records = []
    trace_enabled = bool(os.environ.get("FRAMEFORGE_RTL_AV2_TRACE_OUT"))
    trace_records = []
    completed = False
    total_cycles = 0
    output_active_cycles = 0
    pending_push_cycles = 0
    entropy_op_cycles = 0
    input_sample_cycles = 0
    state_counts = {name: 0 for name in AV2_STATE_NAMES.values()}
    leaf_phase_counts = {}
    pipeline_counts = {}
    block_waveform = BlockWaveformWriter(
        os.environ.get("FRAMEFORGE_RTL_AV2_BLOCK_WAVEFORM_OUT"),
        AV2_BLOCK_WAVEFORM_BLOCKS,
        os.environ.get("FRAMEFORGE_RTL_AV2_BLOCK_WAVEFORM_JSON_OUT"),
    )
    block_waveform_closed = False

    def close_block_waveform():
        nonlocal block_waveform_closed
        if not block_waveform_closed:
            block_waveform.close()
            block_waveform_closed = True

    def optional_handle(path):
        handle = dut
        try:
            for name in path.split("."):
                handle = getattr(handle, name)
            return handle
        except AttributeError:
            return None

    state_h = dut.state_q
    phase_h = dut.phase_q
    op_valid_h = dut.op_valid_w
    pending_push_valid_h = dut.pending_push_valid_q
    reader_axis_valid_h = dut.reader_axis_valid
    reader_axis_ready_h = dut.reader_axis_ready
    packet_axis_valid_h = dut.packet_axis_valid
    packet_axis_ready_h = dut.packet_axis_ready
    analyzer_state_h = dut.palette_analyzer.state_q
    analyzer_done_h = dut.palette_analyzer.done
    m_axis_valid_h = dut.m_axis_valid
    m_axis_ready_h = dut.m_axis_ready
    m_axis_count_h = dut.m_axis_count
    m_axi_rvalid_h = dut.m_axi_rvalid
    m_axi_rready_h = dut.m_axi_rready
    m_axi_wvalid_h = dut.m_axi_wvalid
    m_axi_wready_h = dut.m_axi_wready
    input_fifo_level_h = dut.input_fifo_level_w
    frame_reader_cache_hit_h = optional_handle("frame_reader.cache_hit_w")
    frame_reader_current_read_h = optional_handle("frame_reader.current_read_request_w")
    frame_reader_advance_read_h = optional_handle("frame_reader.advance_read_request_w")
    txb_prefetch_started_h = dut.txb_prefetch_started_q
    txb_prefetch_done_h = dut.txb_prefetch_done_q
    chroma_fetch_current_cache_hit_h = dut.chroma_fetch_current_cache_hit_w
    chroma_fetch_req_ready_h = dut.chroma_fetch_req_ready_w
    lossy_420_mode_h = dut.lossy_420_mode_q
    luma_residual_enable_h = optional_handle("luma_residual_enable_w")
    chroma_bdpcm_enable_h = optional_handle("chroma_bdpcm_enable_w")
    palette_luma_residual_active_h = dut.luma_palette_residual_symbolizer.active_q
    lossy420_luma_residual_active_h = dut.lossy420_luma_residual_symbolizer.active_q
    palette_luma_residual_emit_state_h = dut.luma_palette_residual_symbolizer.emit_state_q
    lossy420_luma_residual_emit_state_h = dut.lossy420_luma_residual_symbolizer.emit_state_q
    luma_residual_op_valid_h = dut.luma_residual_op_valid_w
    palette_luma_residual_start_op_h = dut.luma_palette_residual_symbolizer.start_op_w
    palette_luma_residual_zero_h = dut.palette_luma_residual_known_zero_w
    lossy420_luma_residual_zero_h = dut.lossy420_luma_known_zero_w
    palette_chroma_bdpcm_active_h = dut.chroma_bdpcm_symbolizer.active_q
    lossy420_chroma_bdpcm_active_h = dut.lossy420_chroma_bdpcm_symbolizer.active_q
    palette_chroma_bdpcm_emit_state_h = dut.chroma_bdpcm_symbolizer.emit_state_q
    lossy420_chroma_bdpcm_emit_state_h = dut.lossy420_chroma_bdpcm_symbolizer.emit_state_q
    chroma_bdpcm_op_valid_h = dut.chroma_bdpcm_op_valid_w
    chroma_bdpcm_start_op_h = dut.chroma_bdpcm_symbolizer.start_op_w
    chroma_bdpcm_txb_done_h = dut.chroma_bdpcm_txb_done_w
    chroma_bdpcm_txb_nonzero_h = dut.chroma_bdpcm_txb_nonzero_w
    input_error_h = dut.input_error
    done_h = dut.done

    def hot_int(handle):
        return int(handle.value)

    def optional_hot_int(handle):
        return None if handle is None else int(handle.value)

    def luma_residual_active_value():
        if hot_int(lossy_420_mode_h) == 1:
            return hot_int(lossy420_luma_residual_active_h)
        return hot_int(palette_luma_residual_active_h)

    def chroma_residual_active_value():
        if hot_int(lossy_420_mode_h) == 1:
            return hot_int(lossy420_chroma_bdpcm_active_h)
        return hot_int(palette_chroma_bdpcm_active_h)

    def luma_residual_start_value():
        if hot_int(lossy_420_mode_h) == 1:
            return 0
        return hot_int(palette_luma_residual_start_op_h)

    def luma_residual_emit_state_value():
        if hot_int(lossy_420_mode_h) == 1:
            return hot_int(lossy420_luma_residual_emit_state_h)
        return hot_int(palette_luma_residual_emit_state_h)

    def chroma_residual_emit_state_value():
        if hot_int(lossy_420_mode_h) == 1:
            return hot_int(lossy420_chroma_bdpcm_emit_state_h)
        return hot_int(palette_chroma_bdpcm_emit_state_h)

    def luma_residual_zero_value():
        if hot_int(lossy_420_mode_h) == 1:
            return hot_int(lossy420_luma_residual_zero_h)
        return hot_int(palette_luma_residual_zero_h)

    default_max_cycles = max(80000, width * height * 3 * 32 + 20000)
    max_cycles = int(os.environ.get("FRAMEFORGE_RTL_AV2_MAX_CYCLES", str(default_max_cycles)))
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        total_cycles += 1
        state = hot_int(state_h)
        state_counts[AV2_STATE_NAMES.get(state, f"unknown_{state}")] = (
            state_counts.get(AV2_STATE_NAMES.get(state, f"unknown_{state}"), 0) + 1
        )
        op_valid = hot_int(op_valid_h)
        pending_push = hot_int(pending_push_valid_h) == 1
        op_consumed = op_valid == 1 and not pending_push
        if pending_push:
            pending_push_cycles += 1
        if op_consumed:
            entropy_op_cycles += 1
        reader_axis_valid = hot_int(reader_axis_valid_h)
        reader_axis_ready = hot_int(reader_axis_ready_h)
        packet_axis_valid = hot_int(packet_axis_valid_h)
        packet_axis_ready = hot_int(packet_axis_ready_h)
        analyzer_state = hot_int(analyzer_state_h)
        increment_counter(
            pipeline_counts,
            f"palette_analyzer_state_{AV2_ANALYZER_STATE_NAMES.get(analyzer_state, f'unknown_{analyzer_state}')}",
        )
        m_axis_valid = hot_int(m_axis_valid_h)
        m_axis_ready = hot_int(m_axis_ready_h)
        m_axi_rvalid = hot_int(m_axi_rvalid_h)
        m_axi_rready = hot_int(m_axi_rready_h)
        m_axi_wvalid = hot_int(m_axi_wvalid_h)
        m_axi_wready = hot_int(m_axi_wready_h)
        input_fifo_level = hot_int(input_fifo_level_h)
        block_waveform.sample(
            total_cycles - 1,
            {
                "axi_reader": block_state(
                    m_axi_rvalid,
                    m_axi_rready,
                    reader_axis_valid,
                    reader_axis_ready,
                ),
                "input_fifo": block_state(
                    reader_axis_valid,
                    reader_axis_ready,
                    packet_axis_valid,
                    packet_axis_ready,
                ),
                "palette_analyzer": block_state(
                    packet_axis_valid,
                    packet_axis_ready,
                    hot_int(analyzer_done_h),
                    1,
                ),
                "av2_core": block_state(
                    packet_axis_valid,
                    packet_axis_ready,
                    op_valid,
                    0 if pending_push else 1,
                ),
                "luma_residual": block_state(
                    optional_hot_int(luma_residual_enable_h),
                    0 if luma_residual_active_value() else 1,
                    hot_int(luma_residual_op_valid_h),
                    0 if pending_push else 1,
                ),
                "chroma_residual": block_state(
                    optional_hot_int(chroma_bdpcm_enable_h),
                    0 if chroma_residual_active_value() else 1,
                    hot_int(chroma_bdpcm_op_valid_h),
                    0 if pending_push else 1,
                ),
                "entropy_coder": block_state(
                    op_valid,
                    0 if pending_push else 1,
                    m_axis_valid,
                    m_axis_ready,
                ),
                "axi_writer": block_state(
                    m_axis_valid,
                    m_axis_ready,
                    m_axi_wvalid,
                    m_axi_wready,
                ),
            },
        )
        if reader_axis_valid == 1 and reader_axis_ready == 1:
            increment_counter(pipeline_counts, "reader_sample_accept")
        if optional_hot_int(frame_reader_cache_hit_h) == 1:
            increment_counter(pipeline_counts, "frame_reader_cache_hit_visible")
        if optional_hot_int(frame_reader_current_read_h) == 1:
            increment_counter(pipeline_counts, "frame_reader_current_read_request")
        if optional_hot_int(frame_reader_advance_read_h) == 1:
            increment_counter(pipeline_counts, "frame_reader_advance_read_request")
        if reader_axis_valid == 1 and reader_axis_ready == 0:
            increment_counter(pipeline_counts, "reader_backpressure")
        if packet_axis_valid == 1 and packet_axis_ready == 1:
            input_sample_cycles += 1
            increment_counter(pipeline_counts, "core_sample_accept")
        if packet_axis_valid == 1 and packet_axis_ready == 0:
            increment_counter(pipeline_counts, "input_backpressure")
        if input_fifo_level != 0:
            increment_counter(pipeline_counts, "input_fifo_nonempty")
        if input_fifo_level >= 16:
            increment_counter(pipeline_counts, "input_fifo_full")
        if m_axis_valid == 1 and m_axis_ready == 0:
            increment_counter(pipeline_counts, "output_backpressure")
        if m_axi_wvalid == 1 and m_axi_wready == 1:
            increment_counter(pipeline_counts, "axi_write_beat_accept")
        if m_axi_wvalid == 1 and m_axi_wready == 0:
            increment_counter(pipeline_counts, "axi_write_backpressure")
        if state == AV2_STATE_LEAF:
            phase = hot_int(phase_h)
            phase_name = {
                AV2_PHASE_INTRA: "intra",
                AV2_PHASE_PALETTE_HEADER: "palette_header",
                AV2_PHASE_PALETTE_MAP: "palette_map",
                AV2_PHASE_Y_COEFF: "y_coeff",
                AV2_PHASE_U_COEFF: "u_coeff",
                AV2_PHASE_V_COEFF: "v_coeff",
                AV2_PHASE_INTRABC: "intrabc",
            }.get(phase, f"unknown_{phase}")
            increment_counter(leaf_phase_counts, phase_name)
            if pending_push:
                increment_counter(pipeline_counts, "leaf_pending_push")
            elif op_valid == 1:
                increment_counter(pipeline_counts, f"leaf_entropy_op_{phase_name}")
            else:
                increment_counter(pipeline_counts, f"leaf_entropy_gap_{phase_name}")
            if hot_int(txb_prefetch_started_h) == 1:
                increment_counter(pipeline_counts, "leaf_prefetch_active")
                if hot_int(txb_prefetch_done_h) == 1:
                    increment_counter(pipeline_counts, "leaf_prefetch_done_wait")
        elif state == AV2_STATE_CHROMA_FETCH:
            phase = hot_int(phase_h)
            if phase == AV2_PHASE_Y_COEFF:
                increment_counter(pipeline_counts, "fetch_wait_luma")
            elif phase == AV2_PHASE_U_COEFF:
                increment_counter(pipeline_counts, "fetch_wait_u")
            elif phase == AV2_PHASE_V_COEFF:
                increment_counter(pipeline_counts, "fetch_wait_v")
            if hot_int(chroma_fetch_current_cache_hit_h) == 1:
                increment_counter(pipeline_counts, "fetch_cache_hit_wait")
            if hot_int(chroma_fetch_req_ready_h) == 1:
                increment_counter(pipeline_counts, "fetch_req_ready_wait")

        if optional_hot_int(luma_residual_enable_h) == 1:
            increment_counter(pipeline_counts, "luma_residual_enable")
        if optional_hot_int(chroma_bdpcm_enable_h) == 1:
            increment_counter(pipeline_counts, "chroma_bdpcm_enable")
        luma_residual_active = luma_residual_active_value()
        chroma_bdpcm_active = chroma_residual_active_value()
        if luma_residual_active == 1:
            increment_counter(pipeline_counts, "luma_residual_active")
            luma_emit_state = luma_residual_emit_state_value()
            increment_counter(
                pipeline_counts,
                "luma_residual_emit_state_"
                + AV2_RESIDUAL_EMIT_STATE_NAMES.get(
                    luma_emit_state, f"unknown_{luma_emit_state}"
                ),
            )
            if hot_int(luma_residual_op_valid_h) == 1:
                increment_counter(pipeline_counts, "luma_residual_op_valid")
            else:
                increment_counter(pipeline_counts, "luma_residual_op_gap")
        if chroma_bdpcm_active == 1:
            increment_counter(pipeline_counts, "chroma_bdpcm_active")
            chroma_emit_state = chroma_residual_emit_state_value()
            increment_counter(
                pipeline_counts,
                "chroma_bdpcm_emit_state_"
                + AV2_RESIDUAL_EMIT_STATE_NAMES.get(
                    chroma_emit_state, f"unknown_{chroma_emit_state}"
                ),
            )
            if hot_int(chroma_bdpcm_op_valid_h) == 1:
                increment_counter(pipeline_counts, "chroma_bdpcm_op_valid")
            else:
                increment_counter(pipeline_counts, "chroma_bdpcm_op_gap")
        if hot_int(chroma_bdpcm_start_op_h) == 1 and hot_int(lossy_420_mode_h) == 0:
            increment_counter(pipeline_counts, "chroma_bdpcm_zero_fast_start")
        if (
            state == AV2_STATE_LEAF
            and hot_int(phase_h) in (AV2_PHASE_U_COEFF, AV2_PHASE_V_COEFF)
            and hot_int(chroma_bdpcm_txb_done_h) == 1
        ):
            increment_counter(pipeline_counts, "chroma_bdpcm_txb_done")
            if hot_int(chroma_bdpcm_txb_nonzero_h) == 0:
                increment_counter(pipeline_counts, "chroma_bdpcm_zero_txb_done")
        if (
            state == AV2_STATE_LEAF
            and hot_int(phase_h) == AV2_PHASE_Y_COEFF
            and luma_residual_zero_value() == 1
        ):
            increment_counter(pipeline_counts, "luma_residual_known_zero")
        if luma_residual_start_value() == 1:
            increment_counter(pipeline_counts, "luma_residual_zero_fast_start")
        if trace_enabled and state in (AV2_STATE_PARTITION, AV2_STATE_LEAF) and op_consumed:
            phase = signal_int(dut, "phase_q")
            step = signal_int(dut, "step_q")
            partition_emit_do_split = signal_int(dut, "partition_emit_do_split_w") == 1
            partition_emit_rect = signal_int(dut, "partition_emit_rect_w") == 1
            palette_mode = signal_int(dut, "palette_mode_q") == 1
            leaf_luma_mode = signal_int(dut, "leaf_luma_mode_q")
            palette_row = signal_int(dut, "palette_row_q")
            palette_col = signal_int(dut, "palette_col_q")
            palette_cache_size = signal_int(dut, "palette_cache_size_w")
            name = av2_rtl_trace_name(
                state,
                phase,
                step,
                partition_emit_do_split,
                partition_emit_rect,
                palette_mode,
                leaf_luma_mode,
                palette_row,
                palette_col,
                palette_cache_size,
            )
            record = {
                "codec": "av2",
                "source": "rtl",
                "phase": "tile_entropy",
                "name": name,
                "spec": av2_trace_spec(name),
                "block_row_mi": signal_int(dut, "block_row_mi_q"),
                "block_col_mi": signal_int(dut, "block_col_mi_q"),
                "block_w_mi": signal_int(dut, "block_w_mi_q"),
                "block_h_mi": signal_int(dut, "block_h_mi_q"),
                "partition": signal_int(dut, "partition_q"),
                "chosen_partition": signal_int(dut, "chosen_partition_w"),
                "forced_valid": signal_int(dut, "forced_valid_w"),
                "forced_partition": signal_int(dut, "forced_partition_w"),
                "allowed_none": signal_int(dut, "allowed_none_w"),
                "allowed_horz": signal_int(dut, "allowed_horz_w"),
                "allowed_vert": signal_int(dut, "allowed_vert_w"),
                "has_rows": signal_int(dut, "has_rows_w"),
                "has_cols": signal_int(dut, "has_cols_w"),
                "partition_raw_ctx": signal_int(dut, "partition_raw_ctx_w"),
                "partition_left_shift": signal_int(dut, "partition_left_shift_w"),
                "partition_above_shift": signal_int(dut, "partition_above_shift_w"),
                "partition_left_ctx": handle_int(
                    dut.partition_left_q[signal_int(dut, "block_row_mi_q")]
                ),
                "partition_above_ctx": handle_int(
                    dut.partition_above_q[signal_int(dut, "block_col_mi_q")]
                ),
                "txb_index": signal_int(dut, "txb_index_q"),
                "txb_local_row": signal_int(dut, "txb_local_row_q"),
                "txb_local_col": signal_int(dut, "txb_local_col_q"),
                "palette_mode": signal_int(dut, "palette_mode_q"),
                "leaf_luma_mode": leaf_luma_mode,
                "palette_row": palette_row,
                "palette_col": palette_col,
                "palette_cache_size": palette_cache_size,
                "op_phase": phase,
                "op_step": step,
                "literal": handle_int(dut.entropy_coder.op_literal_w),
                "literal_value": handle_int(dut.entropy_coder.op_literal_value_w),
                "literal_bits": handle_int(dut.entropy_coder.op_literal_bits_w),
                "fl": handle_int(dut.entropy_coder.op_fl_w),
                "fh": handle_int(dut.entropy_coder.op_fh_w),
                "fl_inc": handle_int(dut.entropy_coder.op_fl_inc_w),
                "fh_inc": handle_int(dut.entropy_coder.op_fh_inc_w),
            }
            if phase == AV2_PHASE_Y_COEFF and palette_mode:
                coeff_pos = handle_int(dut.luma_palette_residual_symbolizer.coeff_pos_w)
                record.update(
                    {
                        "luma_residual_emit_state": handle_int(
                            dut.luma_palette_residual_symbolizer.emit_state_q
                        ),
                        "luma_residual_scan": handle_int(
                            dut.luma_palette_residual_symbolizer.scan_q
                        ),
                        "luma_residual_coeff_pos": coeff_pos,
                        "luma_residual_level": handle_int(
                            dut.luma_palette_residual_symbolizer.level_q[coeff_pos]
                        ),
                        "luma_residual_coeff_ctx": handle_int(
                            dut.luma_palette_residual_symbolizer.coeff_ctx_q[coeff_pos]
                        ),
                        "luma_residual_br_ctx": handle_int(
                            dut.luma_palette_residual_symbolizer.br_ctx_q[coeff_pos]
                        ),
                    }
                )
            lossy_420_mode = signal_int(dut, "lossy_420_mode_q") == 1
            if phase == AV2_PHASE_Y_COEFF and lossy_420_mode:
                luma_symbolizer = dut.lossy420_luma_residual_symbolizer
                coeff_pos = nested_signal_int(
                    dut, "lossy420_luma_residual_symbolizer.coeff_pos_w"
                )
                if coeff_pos is not None:
                    record.update(
                        {
                            "luma_residual_emit_state": handle_int(
                                luma_symbolizer.emit_state_q
                            ),
                            "luma_residual_scan": handle_int(luma_symbolizer.scan_q),
                            "luma_residual_coeff_pos": coeff_pos,
                            "luma_residual_level": handle_int(
                                luma_symbolizer.level_q[coeff_pos]
                            ),
                            "luma_residual_hr_avg": handle_int(
                                luma_symbolizer.hr_avg_q
                            ),
                            "luma_residual_hr_m": handle_int(luma_symbolizer.hr_m_w),
                            "luma_residual_high_value": handle_int(
                                luma_symbolizer.current_high_value_w
                            ),
                            "luma_residual_hr_q": handle_int(luma_symbolizer.hr_q_w),
                        }
                    )
                else:
                    record.update(
                        {
                            "luma_residual_emit_state": nested_signal_int(
                                dut, "lossy420_luma_residual_symbolizer.emit_state_q"
                            ),
                            "luma_residual_level": nested_signal_int(
                                dut, "lossy420_luma_residual_symbolizer.level_q"
                            ),
                            "luma_residual_high_value": nested_signal_int(
                                dut, "lossy420_luma_residual_symbolizer.high_value_w"
                            ),
                            "luma_residual_hr_q": nested_signal_int(
                                dut, "lossy420_luma_residual_symbolizer.hr_q_w"
                            ),
                        }
                    )
                record.update(
                    {
                        "luma_fetch_txb_samples": signal_int(
                            dut, "luma_fetch_txb_samples_w"
                        ),
                        "lossy420_luma_predictor": signal_int(
                            dut, "lossy420_luma_predictor_w"
                        ),
                        "lossy420_luma_delta": signal_int(
                            dut, "lossy420_luma_delta_w"
                        ),
                        "lossy420_luma_known_zero": signal_int(
                            dut, "lossy420_luma_known_zero_w"
                        ),
                    }
                )
            if phase in (AV2_PHASE_U_COEFF, AV2_PHASE_V_COEFF) and (palette_mode or lossy_420_mode):
                chroma_symbolizer = (
                    dut.lossy420_chroma_bdpcm_symbolizer
                    if lossy_420_mode
                    else dut.chroma_bdpcm_symbolizer
                )
                chroma_path = (
                    "lossy420_chroma_bdpcm_symbolizer"
                    if lossy_420_mode
                    else "chroma_bdpcm_symbolizer"
                )
                coeff_pos = nested_signal_int(dut, f"{chroma_path}.coeff_pos_w")
                if coeff_pos is not None:
                    record.update(
                        {
                            "chroma_residual_emit_state": handle_int(
                                chroma_symbolizer.emit_state_q
                            ),
                            "chroma_residual_scan": handle_int(
                                chroma_symbolizer.scan_q
                            ),
                            "chroma_residual_coeff_pos": coeff_pos,
                            "chroma_residual_level": handle_int(
                                chroma_symbolizer.level_q[coeff_pos]
                            ),
                            "chroma_residual_hr_avg": handle_int(
                                chroma_symbolizer.hr_avg_q
                            ),
                            "chroma_residual_hr_m": handle_int(
                                chroma_symbolizer.hr_m_w
                            ),
                            "chroma_residual_high_value": handle_int(
                                chroma_symbolizer.current_high_value_w
                            ),
                            "chroma_residual_hr_q": handle_int(
                                chroma_symbolizer.hr_q_w
                            ),
                        }
                    )
                else:
                    record.update(
                        {
                            "chroma_residual_emit_state": nested_signal_int(
                                dut, f"{chroma_path}.emit_state_q"
                            ),
                            "chroma_residual_level": nested_signal_int(
                                dut, f"{chroma_path}.level_q"
                            ),
                            "chroma_residual_high_value": nested_signal_int(
                                dut, f"{chroma_path}.high_value_w"
                            ),
                            "chroma_residual_hr_q": nested_signal_int(
                                dut, f"{chroma_path}.hr_q_w"
                            ),
                        }
                    )
            if phase in (AV2_PHASE_U_COEFF, AV2_PHASE_V_COEFF):
                record.update(
                    {
                        "chroma_fetch_txb_samples": signal_int(dut, "chroma_fetch_txb_samples_w"),
                        "chroma_bdpcm_txb_samples": signal_int(dut, "chroma_bdpcm_txb_samples_w"),
                        "luma_fetch_u_txb_samples": nested_signal_int(
                            dut, "palette_analyzer.luma_fetch_u_txb_samples"
                        ),
                        "luma_fetch_v_txb_samples": nested_signal_int(
                            dut, "palette_analyzer.luma_fetch_v_txb_samples"
                        ),
                        "sample_store_u_row": nested_signal_int(
                            dut, "palette_analyzer.sample_store_u_row_w"
                        ),
                        "sample_store_v_row": nested_signal_int(
                            dut, "palette_analyzer.sample_store_v_row_w"
                        ),
                        "analyzer_luma_fetch_step": nested_signal_int(
                            dut, "palette_analyzer.luma_fetch_step_q"
                        ),
                        "analyzer_luma_fetch_capture_step": nested_signal_int(
                            dut, "palette_analyzer.luma_fetch_capture_step_q"
                        ),
                        "chroma_fetch_start": signal_int(dut, "chroma_fetch_start_w"),
                        "chroma_fetch_done": signal_int(dut, "chroma_fetch_done_w"),
                        "chroma_fetch_req_cross_phase": signal_int(
                            dut, "chroma_fetch_req_cross_phase_w"
                        ),
                        "chroma_fetch_req_next_txb": signal_int(
                            dut, "chroma_fetch_req_next_txb_w"
                        ),
                        "chroma_fetch_req_row_mi": signal_int(
                            dut, "chroma_fetch_req_row_mi_w"
                        ),
                        "chroma_fetch_req_col_mi": signal_int(
                            dut, "chroma_fetch_req_col_mi_w"
                        ),
                        "chroma_fetch_req_plane_v": signal_int(
                            dut, "chroma_fetch_req_plane_v_w"
                        ),
                        "txb_prefetch_started": signal_int(
                            dut, "txb_prefetch_started_q"
                        ),
                        "txb_prefetch_done": signal_int(dut, "txb_prefetch_done_q"),
                        "txb_prefetch_chroma": signal_int(
                            dut, "txb_prefetch_chroma_q"
                        ),
                        "txb_prefetch_plane_v": signal_int(
                            dut, "txb_prefetch_plane_v_q"
                        ),
                        "lossy420_chroma_delta": signal_int(dut, "lossy420_chroma_delta_w"),
                        "lossy420_chroma_known_zero": signal_int(
                            dut, "lossy420_chroma_known_zero_w"
                        ),
                    }
                )
            trace_records.append(record)
        if trace_enabled and signal_int(dut, "luma_fetch_completed_w") == 1:
            trace_records.append(
                {
                    "phase": "rtl_fetch",
                    "source": "rtl",
                    "kind": "luma_fetch_completed",
                    "cycle": total_cycles,
                    "tile_index": signal_int(dut, "tile_index_q"),
                    "block_row_mi": signal_int(dut, "block_row_mi_q"),
                    "block_col_mi": signal_int(dut, "block_col_mi_q"),
                    "txb_index": signal_int(dut, "txb_index_q"),
                    "txb_local_row": signal_int(dut, "txb_local_row_q"),
                    "txb_local_col": signal_int(dut, "txb_local_col_q"),
                    "luma_fetch_cache_index": signal_int(dut, "luma_fetch_cache_index_w"),
                    "luma_fetch_txb_samples": signal_int(dut, "luma_fetch_txb_samples_w"),
                    "luma_fetch_u_txb_samples": nested_signal_int(
                        dut, "palette_analyzer.luma_fetch_u_txb_samples"
                    ),
                    "luma_fetch_v_txb_samples": nested_signal_int(
                        dut, "palette_analyzer.luma_fetch_v_txb_samples"
                    ),
                }
            )
        if trace_enabled and signal_int(dut, "chroma_fetch_completed_u_w") == 1:
            trace_records.append(
                {
                    "phase": "rtl_fetch",
                    "source": "rtl",
                    "kind": "chroma_fetch_completed_u",
                    "cycle": total_cycles,
                    "tile_index": signal_int(dut, "tile_index_q"),
                    "block_row_mi": signal_int(dut, "block_row_mi_q"),
                    "block_col_mi": signal_int(dut, "block_col_mi_q"),
                    "txb_index": signal_int(dut, "txb_index_q"),
                    "txb_local_row": signal_int(dut, "txb_local_row_q"),
                    "txb_local_col": signal_int(dut, "txb_local_col_q"),
                    "chroma_fetch_cache_index": signal_int(dut, "chroma_fetch_cache_index_w"),
                    "chroma_fetch_txb_samples": signal_int(dut, "chroma_fetch_txb_samples_w"),
                    "chroma_fetch_v_txb_samples": nested_signal_int(
                        dut, "palette_analyzer.chroma_fetch_v_txb_samples"
                    ),
                    "chroma_fetch_v_predictor_samples": nested_signal_int(
                        dut, "palette_analyzer.chroma_fetch_v_predictor_samples"
                    ),
                }
            )
        if (
            trace_enabled
            and nested_signal_int(dut, "palette_analyzer.packet_chroma_done_w") == 1
        ):
            chroma_h = nested_signal_int(dut, "palette_analyzer.chroma_h_sad_q")
            chroma_v = nested_signal_int(dut, "palette_analyzer.chroma_v_sad_q")
            packet_h = nested_signal_int(dut, "palette_analyzer.packet_chroma_h_sad_w")
            packet_v = nested_signal_int(dut, "palette_analyzer.packet_chroma_v_sad_w")
            block_id = nested_signal_int(dut, "palette_analyzer.block_id_q")
            h_score = None if chroma_h is None or packet_h is None else chroma_h + packet_h
            v_score = None if chroma_v is None or packet_v is None else chroma_v + packet_v
            trace_records.append(
                {
                    "phase": "palette_analyzer",
                    "source": "rtl",
                    "kind": "chroma_bdpcm_direction",
                    "cycle": total_cycles,
                    "block_id": block_id,
                    "block_row_mi": signal_int(dut, "block_row_mi_q"),
                    "block_col_mi": signal_int(dut, "block_col_mi_q"),
                    "analyzer_block_row": None if block_id is None else block_id >> 3,
                    "analyzer_block_col": None if block_id is None else block_id & 7,
                    "h_score": h_score,
                    "v_score": v_score,
                    "choose_horz": None if h_score is None or v_score is None else h_score <= v_score,
                }
            )
        if hot_int(input_error_h) == 1:
            details = {
                "state": signal_int(dut, "state_q"),
                "s_axis_ready": signal_int(dut, "s_axis_ready"),
                "s_axis_valid": signal_int(dut, "s_axis_valid"),
                "s_axis_last": signal_int(dut, "s_axis_last"),
                "analyzer_state": handle_int(dut.palette_analyzer.state_q),
                "analyzer_done": handle_int(dut.palette_analyzer.done),
                "analyzer_unsupported": handle_int(dut.palette_analyzer.unsupported),
                "analyzer_sample_ready": handle_int(dut.palette_analyzer.sample_ready),
                "analyzer_sample_index": handle_int(dut.palette_analyzer.sample_index_q),
                "analyzer_area": handle_int(dut.palette_analyzer.area_q),
                "analyzer_frame_samples": handle_int(dut.palette_analyzer.frame_samples_q),
                "analyzer_block_id": handle_int(dut.palette_analyzer.block_id_q),
                "analyzer_block_sample": handle_int(dut.palette_analyzer.block_sample_q),
            }
            close_block_waveform()
            raise AssertionError(f"AV2 RTL rejected the input: {details}")
        if m_axis_valid == 1 and m_axis_ready == 1:
            output_active_cycles += hot_int(m_axis_count_h)
            if packet_trace_path:
                packet_trace_records.append(
                    {
                        "cycle": total_cycles,
                        "state": AV2_STATE_NAMES.get(state, f"unknown_{state}"),
                        "stream_index": signal_int(dut, "stream_index_q"),
                        "tile_payload_start": signal_int(dut, "tile_payload_start_w"),
                        "payload_addr": signal_int(dut, "output_payload_addr_w"),
                        "payload_read_word_addr": signal_int(
                            dut, "payload_read_word_addr_q"
                        ),
                        "payload_read_data": signal_int(dut, "payload_read_data_w"),
                        "m_axis_count": hot_int(m_axis_count_h),
                        "m_axis_data": signal_int(dut, "m_axis_data"),
                    }
                )
        if carry_trace_path and state == AV2_STATE_NAMES_INV.get("carry_write", -1):
            carry_trace_records.append(
                {
                    "cycle": total_cycles,
                    "tile_index": signal_int(dut, "tile_index_q"),
                    "payload_len": signal_int(dut, "payload_len_q"),
                    "payload_tile_start": signal_int(dut, "payload_tile_start_w"),
                    "carry_index": signal_int(dut, "carry_index_q"),
                    "carry": signal_int(dut, "carry_q"),
                    "precarry_read_addr": signal_int(dut, "precarry_read_addr_q"),
                    "precarry_read_data": signal_int(dut, "precarry_read_data_q"),
                    "carry_sum": signal_int(dut, "carry_sum_w"),
                    "payload_write_valid": signal_int(dut, "payload_write_valid_w"),
                    "payload_write_addr": signal_int(dut, "payload_write_addr_w"),
                    "payload_write_data": signal_int(dut, "payload_write_data_w"),
                }
            )
        if hot_int(done_h) == 1:
            completed = True
            break

    close_block_waveform()
    if not completed:
        details = {
            "state": signal_int(dut, "state_q"),
            "phase": signal_int(dut, "phase_q"),
            "step": signal_int(dut, "step_q"),
            "block_row_mi": signal_int(dut, "block_row_mi_q"),
            "block_col_mi": signal_int(dut, "block_col_mi_q"),
            "block_w_mi": signal_int(dut, "block_w_mi_q"),
            "block_h_mi": signal_int(dut, "block_h_mi_q"),
            "palette_row": signal_int(dut, "palette_row_q"),
            "palette_col": signal_int(dut, "palette_col_q"),
            "txb_index": signal_int(dut, "txb_index_q"),
            "txb_prefetch_started": signal_int(dut, "txb_prefetch_started_q"),
            "txb_prefetch_done": signal_int(dut, "txb_prefetch_done_q"),
            "txb_prefetch_chroma": signal_int(dut, "txb_prefetch_chroma_q"),
            "txb_fetch_done": signal_int(dut, "txb_fetch_done_w"),
            "luma_fetch_start": signal_int(dut, "luma_fetch_start_w"),
            "chroma_fetch_start": signal_int(dut, "chroma_fetch_start_w"),
            "luma_fetch_done": signal_int(dut, "luma_fetch_done_w"),
            "chroma_fetch_done": signal_int(dut, "chroma_fetch_done_w"),
            "precarry_len": signal_int(dut, "precarry_len_q"),
            "tile_len": signal_int(dut, "tile_len_q"),
            "stream_index": signal_int(dut, "stream_index_q"),
            "observed_bytes": len(observed),
            "analyzer_state": handle_int(dut.palette_analyzer.state_q),
            "analyzer_done": handle_int(dut.palette_analyzer.done),
            "analyzer_sample_index": handle_int(dut.palette_analyzer.sample_index_q),
            "analyzer_frame_samples": handle_int(dut.palette_analyzer.frame_samples_q),
            "analyzer_block_id": handle_int(dut.palette_analyzer.block_id_q),
            "analyzer_block_sample": handle_int(dut.palette_analyzer.block_sample_q),
            "analyzer_collected_count": handle_int(dut.palette_analyzer.collected_count_q),
            "analyzer_target_palette_size": handle_int(dut.palette_analyzer.target_palette_size_q),
            "analyzer_candidate": handle_int(dut.palette_analyzer.candidate_q),
            "analyzer_fetch_active": handle_int(dut.palette_analyzer.fetch_active_q),
            "analyzer_fetch_start_q": handle_int(dut.palette_analyzer.fetch_start_q),
            "analyzer_fetch_step": handle_int(dut.palette_analyzer.fetch_step_q),
            "analyzer_fetch_pending": handle_int(dut.palette_analyzer.fetch_read_pending_q),
            "analyzer_fetch_row": handle_int(dut.palette_analyzer.fetch_txb_row_mi_q),
            "analyzer_fetch_col": handle_int(dut.palette_analyzer.fetch_txb_col_mi_q),
            "analyzer_fetch_plane_v": handle_int(dut.palette_analyzer.fetch_plane_v_q),
            "analyzer_luma_fetch_active": handle_int(dut.palette_analyzer.luma_fetch_active_q),
            "analyzer_luma_fetch_start_q": handle_int(dut.palette_analyzer.luma_fetch_start_q),
            "analyzer_luma_fetch_step": handle_int(dut.palette_analyzer.luma_fetch_step_q),
            "analyzer_luma_fetch_pending": handle_int(
                dut.palette_analyzer.luma_fetch_read_pending_q
            ),
            "analyzer_luma_fetch_row": handle_int(dut.palette_analyzer.luma_fetch_txb_row_mi_q),
            "analyzer_luma_fetch_col": handle_int(dut.palette_analyzer.luma_fetch_txb_col_mi_q),
        }
        raise AssertionError(f"AV2 RTL did not complete an OBU stream: {details}")
    await RisingEdge(dut.clk)
    status = await axil_read(dut, REG_STATUS)
    assert status & STATUS_DONE, f"AXI-Lite STATUS did not report done: 0x{status:08x}"
    assert not (status & STATUS_INPUT_ERROR), f"AXI-Lite STATUS reported input error: 0x{status:08x}"
    assert not (status & STATUS_AXI_ERROR), f"AXI-Lite STATUS reported AXI error: 0x{status:08x}"
    observed_len = await axil_read(dut, REG_ENCODED_BYTE_COUNT)
    observed = list(read_output_bytes(axi_memory, observed_len))
    assert observed, "AV2 RTL produced an empty OBU stream"
    output_path = Path(
        os.environ.get("FRAMEFORGE_RTL_AV2_ENCODER_OUT", "/tmp/frameforge_av2_rtl.av2")
    )
    recon_path = Path(
        os.environ.get("FRAMEFORGE_RTL_AV2_ENCODER_RECON_OUT", "/tmp/frameforge_av2_rtl_recon.yuv")
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(bytes(observed))
    recon_path.write_bytes(av2_stream_reconstruction(input_data))
    write_av2_cycle_metrics(
        os.environ.get("FRAMEFORGE_RTL_AV2_METRICS_OUT"),
        width,
        height,
        frames,
        len(observed),
        total_cycles,
        output_active_cycles,
        state_counts,
        leaf_phase_counts,
        pipeline_counts,
        pending_push_cycles,
        entropy_op_cycles,
        input_sample_cycles,
    )
    if trace_path := os.environ.get("FRAMEFORGE_RTL_AV2_TRACE_OUT"):
        path = Path(trace_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(record, sort_keys=True) + "\n" for record in trace_records))
    if packet_trace_path:
        path = Path(packet_trace_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "".join(json.dumps(record, sort_keys=True) + "\n" for record in packet_trace_records)
        )
    if carry_trace_path:
        path = Path(carry_trace_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "".join(json.dumps(record, sort_keys=True) + "\n" for record in carry_trace_records)
        )


@cocotb.test()
async def av2_encoder_waits_for_start(dut):
    await reset_dut(dut)
    width, height = rtl_geometry()
    layout = av2_frame_layout()
    await program_encoder_control(
        dut,
        width=width,
        height=height,
        chroma_format=rtl_chroma_format_idc(),
        frame_count=1,
        src_y_base=0,
        src_u_base=layout["src_u_base"],
        src_v_base=layout["src_v_base"],
        src_y_stride=layout["src_y_stride"],
        src_u_stride=layout["src_u_stride"],
        src_v_stride=layout["src_v_stride"],
        src_frame_stride=layout["src_frame_stride"],
    )
    await ReadOnly()
    assert int(dut.s_axis_ready.value) == 0
    assert int(dut.m_axis_valid.value) == 0
    await RisingEdge(dut.clk)
    assert (await axil_read(dut, REG_STATUS)) == 0

    await start_encoder(dut)
    status = await axil_read(dut, REG_STATUS)
    assert not (status & STATUS_INPUT_ERROR), f"unexpected input error: 0x{status:08x}"


@cocotb.test()
async def av2_encoder_reports_invalid_geometry(dut):
    await reset_dut(dut)
    await program_encoder_control(
        dut,
        width=0,
        height=64,
        chroma_format=3,
        frame_count=1,
        src_y_base=0,
        src_u_base=4096,
        src_v_base=8192,
        src_y_stride=64,
        src_u_stride=64,
        src_v_stride=64,
        src_frame_stride=12288,
    )
    await start_encoder(dut)
    status = await axil_read(dut, REG_STATUS)
    assert status & STATUS_INPUT_ERROR, f"missing input error: 0x{status:08x}"
    assert int(dut.m_axis_valid.value) == 0


@cocotb.test()
async def av2_encoder_reports_unsupported_422_input_format(dut):
    await reset_dut(dut)
    await program_encoder_control(
        dut,
        width=64,
        height=64,
        chroma_format=2,
        frame_count=1,
        src_y_base=0,
        src_u_base=4096,
        src_v_base=5120,
        src_y_stride=64,
        src_u_stride=32,
        src_v_stride=32,
        src_frame_stride=6144,
    )
    await start_encoder(dut)
    status = await axil_read(dut, REG_STATUS)
    assert status & STATUS_INPUT_ERROR, f"missing input error: 0x{status:08x}"
    assert int(dut.m_axis_valid.value) == 0
