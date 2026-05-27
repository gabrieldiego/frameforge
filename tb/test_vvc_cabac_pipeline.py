import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


SYMBOL_BIN_EP = 0
SYMBOL_BIN_TRM = 1
SYMBOL_BIN_CTX = 2


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.clear.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_kind.value = SYMBOL_BIN_EP
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_pipeline(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


def pack_ctx(bit, ctx_id=0, lps=4, mps=0):
    return (bit & 1) | ((ctx_id & 0x1F) << 8) | ((lps & 0x1FF) << 16) | ((mps & 1) << 25)


async def drive_symbols_and_collect(dut, symbols, max_cycles=512):
    observed = []
    index = 0
    dut.s_axis_valid.value = 0

    for _ in range(max_cycles):
        if index < len(symbols) and int(dut.s_axis_ready.value) == 1:
            kind, data = symbols[index]
            dut.s_axis_valid.value = 1
            dut.s_axis_kind.value = kind
            dut.s_axis_data.value = data
            dut.s_axis_last.value = index == len(symbols) - 1
        else:
            dut.s_axis_valid.value = 0
            dut.s_axis_last.value = 0

        await ReadOnly()

        if int(dut.s_axis_valid.value) == 1 and int(dut.s_axis_ready.value) == 1:
            index += 1

        if int(dut.m_axis_valid.value) == 1 and int(dut.m_axis_ready.value) == 1:
            observed.append(int(dut.m_axis_data.value))
            if int(dut.m_axis_last.value) == 1:
                return bytes(observed)

        await Timer(1, unit="ps")
        await RisingEdge(dut.clk)

    raise AssertionError("CABAC pipeline did not finish")


@cocotb.test()
async def cabac_pipeline_accepts_symbols_and_emits_bytes(dut):
    await reset_dut(dut)
    await start_pipeline(dut)
    symbols = [(SYMBOL_BIN_EP, i & 1) for i in range(40)]
    symbols.append((SYMBOL_BIN_TRM, 1))
    observed = await drive_symbols_and_collect(dut, symbols)
    assert observed != b""


@cocotb.test()
async def cabac_pipeline_accepts_context_symbols(dut):
    await reset_dut(dut)
    await start_pipeline(dut)
    symbols = [
        (SYMBOL_BIN_CTX, pack_ctx(0, ctx_id=0)),
        (SYMBOL_BIN_CTX, pack_ctx(1, ctx_id=1)),
        (SYMBOL_BIN_CTX, pack_ctx(0, ctx_id=8)),
    ]
    symbols.extend((SYMBOL_BIN_EP, i & 1) for i in range(32))
    symbols.append((SYMBOL_BIN_TRM, 1))
    observed = await drive_symbols_and_collect(dut, symbols)
    assert observed != b""
