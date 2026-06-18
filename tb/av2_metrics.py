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
    input_pixels = width * height
    output_wait_cycles = max(0, total_cycles - output_active_cycles)
    output_utilization = output_active_cycles / total_cycles if total_cycles else 0.0
    cycles_per_bit = total_cycles / bitstream_bits if bitstream_bits else 0.0
    cycles_per_input_pixel = total_cycles / input_pixels if input_pixels else 0.0
    metrics = {
        "codec": "av2",
        "width": width,
        "height": height,
        "frames": 1,
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
    }
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n")
