import json
from pathlib import Path

AV2_STATE_NAMES = {
    0: "idle",
    1: "tile_start",
    2: "input_read",
    3: "seq_load",
    4: "seq_write",
    5: "load_block",
    6: "partition",
    7: "palette_query",
    8: "leaf",
    9: "finish_init",
    10: "finish_push",
    11: "chroma_fetch",
    12: "carry_read",
    13: "carry_write",
    14: "payload_prefix",
    15: "output_prep",
    16: "output_valid",
    17: "output_payload_wait",
    18: "output_payload_load",
}
AV2_STATE_PARTITION = 6
AV2_STATE_LEAF = 8
AV2_STATE_CHROMA_FETCH = 11
AV2_PHASE_INTRA = 0
AV2_PHASE_PALETTE_HEADER = 1
AV2_PHASE_PALETTE_MAP = 2
AV2_PHASE_Y_COEFF = 3
AV2_PHASE_U_COEFF = 4
AV2_PHASE_V_COEFF = 5
AV2_PHASE_INTRABC = 6


def write_av2_cycle_metrics(
    path,
    width,
    height,
    frames,
    observed_bytes,
    total_cycles,
    output_active_cycles,
    state_counts,
    leaf_phase_counts,
    pipeline_counts,
    pending_push_cycles,
    entropy_op_cycles,
    input_sample_cycles,
):
    if not path:
        return
    bitstream_bits = observed_bytes * 8
    input_pixels = width * height * frames
    output_wait_cycles = max(0, total_cycles - output_active_cycles)
    output_utilization = output_active_cycles / total_cycles if total_cycles else 0.0
    cycles_per_bit = total_cycles / bitstream_bits if bitstream_bits else 0.0
    cycles_per_input_pixel = total_cycles / input_pixels if input_pixels else 0.0
    input_read_cycles = int(state_counts.get("input_read", 0))
    leaf_cycles = int(state_counts.get("leaf", 0))
    carry_write_cycles = int(state_counts.get("carry_write", 0))
    reader_sample_accept = int(pipeline_counts.get("reader_sample_accept", 0))
    reader_backpressure = int(pipeline_counts.get("reader_backpressure", 0))
    core_sample_accept = int(pipeline_counts.get("core_sample_accept", 0))
    input_backpressure = int(pipeline_counts.get("input_backpressure", 0))
    input_fifo_nonempty = int(pipeline_counts.get("input_fifo_nonempty", 0))
    input_fifo_full = int(pipeline_counts.get("input_fifo_full", 0))
    axi_write_accept = int(pipeline_counts.get("axi_write_beat_accept", 0))
    axi_write_backpressure = int(pipeline_counts.get("axi_write_backpressure", 0))
    chroma_bdpcm_active = int(pipeline_counts.get("chroma_bdpcm_active", 0))
    chroma_bdpcm_op_valid = int(pipeline_counts.get("chroma_bdpcm_op_valid", 0))
    chroma_bdpcm_txb_done = int(pipeline_counts.get("chroma_bdpcm_txb_done", 0))
    chroma_bdpcm_zero_fast_start = int(
        pipeline_counts.get("chroma_bdpcm_zero_fast_start", 0)
    )
    luma_residual_active = int(pipeline_counts.get("luma_residual_active", 0))
    luma_residual_op_valid = int(pipeline_counts.get("luma_residual_op_valid", 0))
    leaf_prefetch_active = int(pipeline_counts.get("leaf_prefetch_active", 0))
    leaf_prefetch_done_wait = int(pipeline_counts.get("leaf_prefetch_done_wait", 0))
    block_utilization = {
        "frame_reader_sample_utilization": (
            reader_sample_accept / input_read_cycles if input_read_cycles else 0.0
        ),
        "frame_reader_to_fifo_utilization": (
            reader_sample_accept / (reader_sample_accept + reader_backpressure)
            if (reader_sample_accept + reader_backpressure)
            else 0.0
        ),
        "input_fifo_core_utilization": (
            core_sample_accept / (core_sample_accept + input_backpressure)
            if (core_sample_accept + input_backpressure)
            else 0.0
        ),
        "input_fifo_nonempty_rate": (
            input_fifo_nonempty / total_cycles if total_cycles else 0.0
        ),
        "input_fifo_full_rate": (
            input_fifo_full / total_cycles if total_cycles else 0.0
        ),
        "axi_write_beat_utilization": (
            axi_write_accept / (axi_write_accept + axi_write_backpressure)
            if (axi_write_accept + axi_write_backpressure)
            else 0.0
        ),
        "axi_write_bus_utilization": (
            axi_write_accept / total_cycles if total_cycles else 0.0
        ),
        "entropy_leaf_op_utilization": (
            entropy_op_cycles / leaf_cycles if leaf_cycles else 0.0
        ),
        "luma_residual_op_utilization": (
            luma_residual_op_valid / luma_residual_active
            if luma_residual_active
            else 0.0
        ),
        "chroma_bdpcm_op_utilization": (
            chroma_bdpcm_op_valid / chroma_bdpcm_active
            if chroma_bdpcm_active
            else 0.0
        ),
        "chroma_bdpcm_zero_fast_rate": (
            chroma_bdpcm_zero_fast_start / chroma_bdpcm_txb_done
            if chroma_bdpcm_txb_done
            else 0.0
        ),
        "prefetch_useful_utilization": (
            (leaf_prefetch_active - leaf_prefetch_done_wait) / leaf_prefetch_active
            if leaf_prefetch_active
            else 0.0
        ),
        "carry_payload_utilization": (
            observed_bytes / carry_write_cycles if carry_write_cycles else 0.0
        ),
        "final_output_utilization": output_utilization,
    }
    metrics = {
        "codec": "av2",
        "width": width,
        "height": height,
        "frames": frames,
        "bitstream_bytes": observed_bytes,
        "bitstream_bits": bitstream_bits,
        "input_pixels": input_pixels,
        "total_cycles": total_cycles,
        "output_active_cycles": output_active_cycles,
        "output_wait_cycles": output_wait_cycles,
        "output_utilization": output_utilization,
        "output_bubble_rate": 1.0 - output_utilization,
        "cycles_per_bit": cycles_per_bit,
        "cycles_per_input_pixel": cycles_per_input_pixel,
        "state_cycles": state_counts,
        "leaf_phase_cycles": leaf_phase_counts,
        "pipeline_cycles": pipeline_counts,
        "pending_push_cycles": pending_push_cycles,
        "entropy_op_cycles": entropy_op_cycles,
        "input_sample_cycles": input_sample_cycles,
        "block_utilization": block_utilization,
    }
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n")
