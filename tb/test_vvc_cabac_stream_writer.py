import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


CABAC_BIN_EP = 0
CABAC_BIN_TRM = 1
CABAC_BIN_CTX = 2


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.clear.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_kind.value = CABAC_BIN_EP
    dut.s_axis_bin.value = 0
    dut.s_axis_ctx_valid.value = 0
    dut.s_axis_ctx_id.value = 0
    dut.s_axis_lps.value = 4
    dut.s_axis_mps.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_writer(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


async def drive_bins_and_collect(dut, bins, backpressure=False, max_cycles=256):
    observed = []
    held = None
    index = 0
    dut.s_axis_valid.value = 0

    for cycle in range(max_cycles):
        dut.m_axis_ready.value = 0 if backpressure and (cycle % 4 == 2) else 1
        if index < len(bins) and int(dut.s_axis_ready.value) == 1:
            if len(bins[index]) == 2:
                kind, bit = bins[index]
                lps = 4
                mps = 0
            else:
                kind, bit, lps, mps = bins[index]
            dut.s_axis_valid.value = 1
            dut.s_axis_kind.value = kind
            dut.s_axis_bin.value = bit
            dut.s_axis_ctx_valid.value = 0
            dut.s_axis_ctx_id.value = 0
            dut.s_axis_lps.value = lps
            dut.s_axis_mps.value = mps
            dut.s_axis_last.value = index == len(bins) - 1
        else:
            dut.s_axis_valid.value = 0
            dut.s_axis_last.value = 0

        await ReadOnly()

        if int(dut.s_axis_valid.value) == 1 and int(dut.s_axis_ready.value) == 1:
            index += 1

        if int(dut.m_axis_valid.value) == 1:
            current = (int(dut.m_axis_data.value), int(dut.m_axis_last.value))
            if int(dut.m_axis_ready.value) == 0:
                if held is None:
                    held = current
                else:
                    assert current == held
            else:
                observed.append(current[0])
                held = None
                if current[1] == 1:
                    return bytes(observed)
        await Timer(1, unit="ps")
        await RisingEdge(dut.clk)

    raise AssertionError("stream writer did not finish")


@cocotb.test()
async def cabac_stream_writer_emits_bytes_without_backpressure(dut):
    await reset_dut(dut)
    await start_writer(dut)
    bins = [(CABAC_BIN_EP, i & 1) for i in range(40)] + [(CABAC_BIN_TRM, 1)]
    observed = await drive_bins_and_collect(dut, bins)
    assert observed != b""
    assert int(dut.done.value) in (0, 1)


@cocotb.test()
async def cabac_stream_writer_holds_byte_until_ready(dut):
    bins = [(CABAC_BIN_EP, (i >> 1) & 1) for i in range(48)] + [(CABAC_BIN_TRM, 1)]

    await reset_dut(dut)
    await start_writer(dut)
    stalled = await drive_bins_and_collect(dut, bins, backpressure=True)

    await Timer(1, unit="ps")
    await reset_dut(dut)
    await start_writer(dut)
    unstalled = await drive_bins_and_collect(dut, bins, backpressure=False)

    assert stalled == unstalled


@cocotb.test()
async def cabac_stream_writer_accepts_context_bins(dut):
    await reset_dut(dut)
    await start_writer(dut)
    bins = [
        (CABAC_BIN_CTX, 0, 4, 0),
        (CABAC_BIN_CTX, 1, 17, 0),
        (CABAC_BIN_CTX, 0, 8, 1),
        (CABAC_BIN_CTX, 1, 33, 1),
    ]
    bins.extend((CABAC_BIN_EP, i & 1) for i in range(32))
    bins.append((CABAC_BIN_TRM, 1))
    observed = await drive_bins_and_collect(dut, bins, backpressure=True)
    assert observed != b""
