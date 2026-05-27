import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


@cocotb.test()
async def syntax_frontend_forwards_raw_symbols_and_stalls_ctu_path(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.raw_symbol_valid.value = 0
    dut.raw_symbol_kind.value = 0
    dut.raw_symbol_data.value = 0
    dut.raw_symbol_last.value = 0
    dut.ctu_valid.value = 1
    dut.ctu_x.value = 0
    dut.ctu_y.value = 0
    dut.ctu_visible_width.value = 16
    dut.ctu_visible_height.value = 16
    dut.ctu_last.value = 1
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await Timer(1, unit="ns")

    assert int(dut.ctu_ready.value) == 0

    dut.raw_symbol_valid.value = 1
    dut.raw_symbol_kind.value = 2
    dut.raw_symbol_data.value = 0x1234
    dut.raw_symbol_last.value = 1
    await Timer(1, unit="ns")

    assert int(dut.raw_symbol_ready.value) == 1
    assert int(dut.m_axis_valid.value) == 1
    assert int(dut.m_axis_kind.value) == 2
    assert int(dut.m_axis_data.value) == 0x1234
    assert int(dut.m_axis_last.value) == 1
