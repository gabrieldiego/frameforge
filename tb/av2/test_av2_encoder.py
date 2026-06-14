import json
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


def rtl_geometry():
    return (
        int(os.environ.get("RTL_VISIBLE_WIDTH", "64")),
        int(os.environ.get("RTL_VISIBLE_HEIGHT", "64")),
    )


def signal_int(dut, name):
    try:
        return int(getattr(dut, name).value)
    except (AttributeError, ValueError):
        return None


def handle_int(handle):
    try:
        return int(handle.value)
    except (AttributeError, ValueError):
        return None


def av2_rtl_trace_name(state, phase, step, partition_emit_do_split, partition_emit_rect):
    if state == 4:
        if partition_emit_do_split:
            return "tile.partition.do_split"
        if partition_emit_rect:
            return "tile.partition.rect_type"
        return "tile.partition.implied"
    if phase == 0:
        return [
            "tile.intra.use_dpcm_y",
            "tile.intra.y_mode_set_index",
            "tile.intra.y_mode_idx_dc",
            "tile.intra.fsc_mode",
            "tile.intra.use_dpcm_uv",
            "tile.intra.uv_mode_idx_dc",
        ][step] if 0 <= step <= 5 else "tile.unknown"
    if phase == 1:
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
    if name.startswith("tile.intra."):
        return "AV2 v1.0.0 Section 5.20.5.3 intra_frame_mode_info()"
    if name.startswith("tile.coeff."):
        return "AV2 v1.0.0 Sections 5.20.7.24 and 5.20.7.25 transform coefficient syntax"
    return "AV2 v1.0.0 tile entropy syntax"


async def reset_dut(dut):
    width, height = rtl_geometry()
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.visible_width.value = width
    dut.visible_height.value = height
    dut.chroma_format_idc.value = 3
    dut.s_axis_valid.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_encoder(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


@cocotb.test()
async def av2_encoder_emits_black_obu_stream(dut):
    await reset_dut(dut)
    await start_encoder(dut)

    observed = []
    trace_records = []
    completed = False
    max_cycles = int(os.environ.get("FRAMEFORGE_RTL_AV2_MAX_CYCLES", "80000"))
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        state = signal_int(dut, "state_q")
        op_valid = signal_int(dut, "op_valid_w")
        if state == 4 or (state == 5 and op_valid == 1):
            phase = signal_int(dut, "phase_q")
            step = signal_int(dut, "step_q")
            partition_emit_do_split = signal_int(dut, "partition_emit_do_split_w") == 1
            partition_emit_rect = signal_int(dut, "partition_emit_rect_w") == 1
            name = av2_rtl_trace_name(
                state, phase, step, partition_emit_do_split, partition_emit_rect
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
                "op_phase": phase,
                "op_step": step,
                "literal": signal_int(dut, "op_literal_w"),
                "literal_value": signal_int(dut, "op_literal_value_w"),
                "literal_bits": signal_int(dut, "op_literal_bits_w"),
                "fl": signal_int(dut, "op_fl_w"),
                "fh": signal_int(dut, "op_fh_w"),
                "fl_inc": signal_int(dut, "op_fl_inc_w"),
                "fh_inc": signal_int(dut, "op_fh_inc_w"),
            }
            trace_records.append(record)
        if int(dut.input_error.value) == 1:
            raise AssertionError("AV2 RTL rejected the black 4:4:4 input")
        if int(dut.m_axis_valid.value) == 1 and int(dut.m_axis_ready.value) == 1:
            observed.append(int(dut.m_axis_data.value))
            if int(dut.m_axis_last.value) == 1:
                completed = True
                break

    assert completed, "AV2 RTL did not complete an OBU stream"
    assert observed, "AV2 RTL produced an empty OBU stream"

    output_path = Path(
        os.environ.get("FRAMEFORGE_RTL_AV2_ENCODER_OUT", "/tmp/frameforge_av2_rtl.av2")
    )
    recon_path = Path(
        os.environ.get("FRAMEFORGE_RTL_AV2_ENCODER_RECON_OUT", "/tmp/frameforge_av2_rtl_recon.yuv")
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(bytes(observed))
    width, height = rtl_geometry()
    recon_path.write_bytes(bytes(width * height * 3))
    if trace_path := os.environ.get("FRAMEFORGE_RTL_AV2_TRACE_OUT"):
        path = Path(trace_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(record, sort_keys=True) + "\n" for record in trace_records))


@cocotb.test()
async def av2_encoder_waits_for_start(dut):
    await reset_dut(dut)
    await ReadOnly()
    assert int(dut.s_axis_ready.value) == 0
    assert int(dut.m_axis_valid.value) == 0
    assert int(dut.busy.value) == 0

    await RisingEdge(dut.clk)
    await start_encoder(dut)
    await ReadOnly()
    assert int(dut.input_error.value) == 0


@cocotb.test()
async def av2_encoder_reports_invalid_geometry(dut):
    await reset_dut(dut)
    dut.visible_width.value = 0
    await start_encoder(dut)
    await ReadOnly()
    assert int(dut.busy.value) == 0
    assert int(dut.input_error.value) == 1
    assert int(dut.m_axis_valid.value) == 0


@cocotb.test()
async def av2_encoder_reports_non_444_input_format(dut):
    await reset_dut(dut)
    dut.chroma_format_idc.value = 1
    await start_encoder(dut)
    await ReadOnly()
    assert int(dut.busy.value) == 0
    assert int(dut.input_error.value) == 1
    assert int(dut.m_axis_valid.value) == 0
