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

def rtl_geometry():
    return (
        int(os.environ.get("RTL_VISIBLE_WIDTH", "64")),
        int(os.environ.get("RTL_VISIBLE_HEIGHT", "64")),
    )


def rtl_chroma_format_idc():
    return int(os.environ.get("RTL_CHROMA_FORMAT_IDC", "3"))


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


def av2_input_frame():
    expected_len = av2_frame_layout()["length"]
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
    # AV2 luma palette only predicts the luma plane. The current RTL then emits
    # lossless luma coefficients plus lossless chroma BDPCM, so the internal
    # reconstruction is the input frame once the residual path is enabled.
    return data


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
            "tile.intra.uv_mode_idx_dc",
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
    input_data = av2_input_frame()
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
        frame_count=1,
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
    default_max_cycles = max(80000, width * height * 3 * 32 + 20000)
    max_cycles = int(os.environ.get("FRAMEFORGE_RTL_AV2_MAX_CYCLES", str(default_max_cycles)))
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        total_cycles += 1
        state = signal_int(dut, "state_q")
        state_counts[AV2_STATE_NAMES.get(state, f"unknown_{state}")] = (
            state_counts.get(AV2_STATE_NAMES.get(state, f"unknown_{state}"), 0) + 1
        )
        op_valid = signal_int(dut, "op_valid_w")
        pending_push = signal_int(dut, "pending_push_valid_q") == 1
        op_consumed = op_valid == 1 and not pending_push
        if pending_push:
            pending_push_cycles += 1
        if op_consumed:
            entropy_op_cycles += 1
        if int(dut.s_axis_valid.value) == 1 and int(dut.s_axis_ready.value) == 1:
            input_sample_cycles += 1
        if int(dut.s_axis_valid.value) == 1 and int(dut.s_axis_ready.value) == 0:
            increment_counter(pipeline_counts, "input_backpressure")
        if int(dut.m_axis_valid.value) == 1 and int(dut.m_axis_ready.value) == 0:
            increment_counter(pipeline_counts, "output_backpressure")
        if state == AV2_STATE_LEAF:
            phase = signal_int(dut, "phase_q")
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
            if signal_int(dut, "txb_prefetch_started_q") == 1:
                increment_counter(pipeline_counts, "leaf_prefetch_active")
                if signal_int(dut, "txb_prefetch_done_q") == 1:
                    increment_counter(pipeline_counts, "leaf_prefetch_done_wait")
        elif state == AV2_STATE_CHROMA_FETCH:
            phase = signal_int(dut, "phase_q")
            if phase == AV2_PHASE_Y_COEFF:
                increment_counter(pipeline_counts, "fetch_wait_luma")
            elif phase == AV2_PHASE_U_COEFF:
                increment_counter(pipeline_counts, "fetch_wait_u")
            elif phase == AV2_PHASE_V_COEFF:
                increment_counter(pipeline_counts, "fetch_wait_v")
            if signal_int(dut, "chroma_fetch_current_cache_hit_w") == 1:
                increment_counter(pipeline_counts, "fetch_cache_hit_wait")
            if signal_int(dut, "chroma_fetch_req_ready_w") == 1:
                increment_counter(pipeline_counts, "fetch_req_ready_wait")

        if signal_int(dut, "luma_residual_enable_w") == 1:
            increment_counter(pipeline_counts, "luma_residual_enable")
        if signal_int(dut, "chroma_bdpcm_enable_w") == 1:
            increment_counter(pipeline_counts, "chroma_bdpcm_enable")
        luma_residual_active = nested_signal_int(
            dut, "luma_palette_residual_symbolizer.active_q"
        )
        chroma_bdpcm_active = nested_signal_int(dut, "chroma_bdpcm_symbolizer.active_q")
        if luma_residual_active == 1:
            increment_counter(pipeline_counts, "luma_residual_active")
            if signal_int(dut, "luma_residual_op_valid_w") == 1:
                increment_counter(pipeline_counts, "luma_residual_op_valid")
            else:
                increment_counter(pipeline_counts, "luma_residual_op_gap")
        if chroma_bdpcm_active == 1:
            increment_counter(pipeline_counts, "chroma_bdpcm_active")
            if signal_int(dut, "chroma_bdpcm_op_valid_w") == 1:
                increment_counter(pipeline_counts, "chroma_bdpcm_op_valid")
            else:
                increment_counter(pipeline_counts, "chroma_bdpcm_op_gap")
        if (
            state == AV2_STATE_LEAF
            and signal_int(dut, "phase_q") == AV2_PHASE_Y_COEFF
            and signal_int(dut, "palette_luma_residual_zero_w") == 1
        ):
            increment_counter(pipeline_counts, "luma_residual_known_zero")
        if nested_signal_int(dut, "luma_palette_residual_symbolizer.start_op_w") == 1:
            increment_counter(pipeline_counts, "luma_residual_zero_fast_start")
        if state in (AV2_STATE_PARTITION, AV2_STATE_LEAF) and op_consumed:
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
            if phase in (AV2_PHASE_U_COEFF, AV2_PHASE_V_COEFF) and palette_mode:
                coeff_pos = handle_int(dut.chroma_bdpcm_symbolizer.coeff_pos_w)
                record.update(
                    {
                        "chroma_residual_emit_state": handle_int(
                            dut.chroma_bdpcm_symbolizer.emit_state_q
                        ),
                        "chroma_residual_scan": handle_int(
                            dut.chroma_bdpcm_symbolizer.scan_q
                        ),
                        "chroma_residual_coeff_pos": coeff_pos,
                        "chroma_residual_level": handle_int(
                            dut.chroma_bdpcm_symbolizer.level_q[coeff_pos]
                        ),
                        "chroma_residual_hr_avg": handle_int(
                            dut.chroma_bdpcm_symbolizer.hr_avg_q
                        ),
                        "chroma_residual_hr_m": handle_int(
                            dut.chroma_bdpcm_symbolizer.hr_m_w
                        ),
                        "chroma_residual_high_value": handle_int(
                            dut.chroma_bdpcm_symbolizer.current_high_value_w
                        ),
                        "chroma_residual_hr_q": handle_int(
                            dut.chroma_bdpcm_symbolizer.hr_q_w
                        ),
                    }
                )
            trace_records.append(record)
        if int(dut.input_error.value) == 1:
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
            raise AssertionError(f"AV2 RTL rejected the input: {details}")
        if signal_int(dut, "m_axis_valid") == 1 and signal_int(dut, "m_axis_ready") == 1:
            output_active_cycles += 1
        if signal_int(dut, "done") == 1:
            completed = True
            break

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
    recon_path.write_bytes(av2_palette_reconstruction(input_data))
    write_av2_cycle_metrics(
        os.environ.get("FRAMEFORGE_RTL_AV2_METRICS_OUT"),
        width,
        height,
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
