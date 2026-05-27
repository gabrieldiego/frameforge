import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


@cocotb.test()
async def symbol_binarizer_maps_context_symbol_to_bin(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.s_axis_valid.value = 0
    dut.s_axis_kind.value = 0
    dut.s_axis_data.value = 0
    dut.s_axis_last.value = 0
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    dut.s_axis_valid.value = 1
    dut.s_axis_kind.value = 2
    dut.s_axis_data.value = 1 | (7 << 8) | (33 << 16) | (1 << 25)
    dut.s_axis_last.value = 1
    await RisingEdge(dut.clk)
    dut.s_axis_valid.value = 0
    await Timer(1, unit="ns")

    assert int(dut.m_axis_valid.value) == 1
    assert int(dut.m_axis_kind.value) == 2
    assert int(dut.m_axis_bin.value) == 1
    assert int(dut.m_axis_ctx_valid.value) == 1
    assert int(dut.m_axis_ctx_id.value) == 7
    assert int(dut.m_axis_lps.value) == 33
    assert int(dut.m_axis_mps.value) == 1
    assert int(dut.m_axis_last.value) == 1
