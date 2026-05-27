import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


@cocotb.test()
async def context_model_initializes_and_updates(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.reset_contexts.value = 0
    dut.query_ctx_id.value = 0
    dut.query_range.value = 510
    dut.update_valid.value = 0
    dut.update_ctx_id.value = 0
    dut.update_bin.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await Timer(1, unit="ns")

    first_lps = int(dut.query_lps.value)
    first_mps = int(dut.query_mps.value)
    assert 0 < first_lps < 510
    assert first_mps in (0, 1)
    assert int(dut.query_bank_id.value) == 0

    dut.update_valid.value = 1
    dut.update_ctx_id.value = 0
    dut.update_bin.value = 1
    await RisingEdge(dut.clk)
    dut.update_valid.value = 0
    await Timer(1, unit="ns")

    updated_lps = int(dut.query_lps.value)
    updated_mps = int(dut.query_mps.value)
    assert 0 < updated_lps < 510
    assert updated_mps in (0, 1)
    assert (updated_lps, updated_mps) != (first_lps, first_mps)
