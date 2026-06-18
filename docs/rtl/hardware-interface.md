# Shared Encoder Hardware Interface

FrameForge encoder top modules expose the same SoC-facing interface for every
codec target. Codec-specific syntax, prediction, and entropy decisions remain
inside `rtl/vvc/` or `rtl/av2/`; the public integration contract is shared.

The current public interface is:

- AXI4-Lite slave for control and status registers.
- AXI4 memory-mapped read master for source pixels.
- AXI4 memory-mapped write master for the encoded bitstream.

The implementation is intentionally conservative. The frame reader issues
single-beat reads and the bitstream writer issues single-beat writes today so
the existing encoder cores can be integrated without a large scheduler rewrite.
Future burst engines should keep the same register map and top-level port
shape while replacing the simple one-sample read and one-word write glue.

## Register Map

All registers are 32-bit little-endian AXI4-Lite words. The shared register
decoder lives in `rtl/common/ff_encoder_axil_regs.sv`.

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | `CONTROL` | W | Bit 0 starts an encode and clears sticky status. Bit 1 clears sticky status without starting. Reads return zero. |
| `0x004` | `STATUS` | R | Bit 0 `busy`, bit 1 sticky `done`, bit 2 sticky `input_error`, bit 3 sticky `axi_error`. |
| `0x008` | `WIDTH` | R/W | Visible frame width in pixels. |
| `0x00c` | `HEIGHT` | R/W | Visible frame height in pixels. |
| `0x010` | `CHROMA_FORMAT_IDC` | R/W | Codec-visible chroma format idc. Current validated values are `1` for 4:2:0 VVC and `3` for 4:4:4 paths. |
| `0x014` | `FRAME_COUNT` | R/W | Number of frames to encode from the programmed source. AV2 currently supports one frame. |
| `0x018` | `SRC_Y_BASE` | R/W | Source plane 0 base address. |
| `0x01c` | `SRC_U_BASE` | R/W | Source plane 1 base address. |
| `0x020` | `SRC_V_BASE` | R/W | Source plane 2 base address. |
| `0x024` | `SRC_Y_STRIDE` | R/W | Source plane 0 stride in bytes. |
| `0x028` | `SRC_U_STRIDE` | R/W | Source plane 1 stride in bytes. |
| `0x02c` | `SRC_V_STRIDE` | R/W | Source plane 2 stride in bytes. |
| `0x030` | `SRC_FRAME_STRIDE` | R/W | Byte distance from one frame to the next frame for multi-frame input. |
| `0x034` | `DST_BITSTREAM_BASE` | R/W | Destination bitstream buffer base address. |
| `0x038` | `DST_BITSTREAM_CAPACITY` | R/W | Destination buffer capacity in bytes. Present in the register map; overflow checking is still basic. |
| `0x03c` | `ENCODED_BYTE_COUNT` | R | Number of encoded bytes written for the most recent encode. |

The current decoder stores only the low 32 bits of source and destination
addresses. `AXI_ADDR_BITS` is already parameterized in RTL so high address
registers can be added without changing the codec cores.

## Source Layout

Source input is planar. Address generation uses:

```text
plane_address = plane_base + frame_index * SRC_FRAME_STRIDE
              + y * plane_stride + x * bytes_per_sample
```

The shared frame reader converts that planar memory layout into each codec's
internal 8x8 block stream. That internal stream is no longer a public top-level
port. VVC keeps its current TU-oriented 4:2:0 order internally; AV2 uses visible
8x8 4:4:4 block packets internally. Testbenches may probe those internal wires
for debugging and output-utilization metrics, but board integration should only
wire the AXI interfaces.

## Bitstream Output

The internal encoder emits bytes. `rtl/common/ff_axi4_bitstream_writer.sv`
packs those bytes into the configured AXI data width and uses `WSTRB` to mark
valid lanes in the final partial word. Software should use
`ENCODED_BYTE_COUNT` to know how many bytes in the destination buffer are part
of the coded stream.

## Current Limitations

- AXI reads are single-beat sample fetches, not burst reads.
- AXI writes are single-beat packed-word writes, not multi-beat bursts.
- AXI IDs, cache/protection/QoS sidebands, interrupts, and descriptor rings are
  not implemented yet.
- Base-address registers are currently 32-bit.
- The AXI4-Lite block accepts full-word writes; byte-lane masking with `WSTRB`
  is reserved for a later cleanup.

These limitations are expected at this stage. They isolate the public SoC
contract first, then leave room to replace the data movers with burst-capable
engines without changing the codec-visible control model.
