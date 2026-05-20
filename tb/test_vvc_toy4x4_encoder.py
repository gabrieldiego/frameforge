import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


SPS_PAYLOAD = bytes(
    [
        0x00,
        0x0B,
        0x02,
        0x00,
        0x80,
        0x00,
        0x42,
        0x44,
        0xEE,
        0xD5,
        0x01,
        0xF4,
        0x46,
        0xE8,
        0x84,
        0x68,
        0x84,
        0x24,
        0x61,
        0x36,
        0x28,
        0xC5,
        0x43,
        0x06,
        0x80,
        0xAB,
        0x8F,
        0xE0,
        0xAC,
        0x10,
        0x20,
    ]
)

PPS_PAYLOAD = bytes(
    [
        0x00,
        0x02,
        0x44,
        0x8A,
        0x42,
        0x00,
        0xC7,
        0xB2,
        0x14,
        0x59,
        0x45,
        0x94,
        0x58,
        0x80,
    ]
)

IDR_PAYLOAD = bytes([0xC4, 0x00, 0x70, 0x80, 0x62, 0xF5, 0xB7, 0xEB, 0xCB, 0x1F, 0x80])
CRA_PAYLOAD = bytes([0xC4, 0x04, 0x78, 0x80, 0x62, 0xF5, 0xB7, 0xEB, 0xCB, 0x1F, 0x80])


def nal_unit(nal_type, payload):
    temporal_id_plus1 = 1
    header = bytes([0x00, (nal_type << 3) | temporal_id_plus1])
    return b"\x00\x00\x00\x01" + header + payload


def expected_stream(frames):
    out = bytearray()
    for frame_idx in range(frames):
        out += nal_unit(15, SPS_PAYLOAD)
        out += nal_unit(16, PPS_PAYLOAD)
        out += nal_unit(9 if frame_idx else 8, CRA_PAYLOAD if frame_idx else IDR_PAYLOAD)
    return bytes(out)


async def collect_stream(dut, frames):
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.frame_count.value = frames
    dut.m_axis_ready.value = 1

    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    dut.start.value = 1
    await RisingEdge(dut.clk)
    await ReadOnly()

    observed = bytearray()
    if dut.m_axis_valid.value == 1:
        observed.append(int(dut.m_axis_data.value))

    for cycle in range(240):
        await RisingEdge(dut.clk)
        if cycle == 0:
            dut.start.value = 0
        await ReadOnly()
        if dut.m_axis_valid.value == 1:
            observed.append(int(dut.m_axis_data.value))
            if dut.m_axis_last.value == 1:
                break

    return bytes(observed)


@cocotb.test()
async def vvc_toy4x4_encoder_generates_software_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    assert await collect_stream(dut, frames=2) == expected_stream(frames=2)
