import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.raw_symbol_valid.value = 0
    dut.raw_symbol_kind.value = 0
    dut.raw_symbol_data.value = 0
    dut.raw_symbol_last.value = 0
    dut.ctu_valid.value = 0
    dut.ctu_x.value = 0
    dut.ctu_y.value = 0
    dut.ctu_visible_width.value = 16
    dut.ctu_visible_height.value = 16
    dut.ctu_luma_dc_abs_level.value = 0
    dut.ctu_luma_dc_negative.value = 0
    dut.ctu_luma_only.value = 1
    dut.ctu_last.value = 1
    dut.m_axis_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def send_raw_symbol(dut, kind, data, last):
    dut.raw_symbol_valid.value = 1
    dut.raw_symbol_kind.value = kind
    dut.raw_symbol_data.value = data
    dut.raw_symbol_last.value = last
    for _ in range(16):
        await ReadOnly()
        if int(dut.raw_symbol_ready.value) == 1:
            await RisingEdge(dut.clk)
            dut.raw_symbol_valid.value = 0
            dut.raw_symbol_last.value = 0
            return
        await RisingEdge(dut.clk)
    assert False, f"raw symbol not accepted: kind={kind:#x}"


async def collect_output_symbols(dut, target_count, max_cycles=64):
    observed = []
    for _ in range(max_cycles):
        await ReadOnly()
        if int(dut.m_axis_valid.value) == 1:
            observed.append(
                (
                    int(dut.m_axis_kind.value),
                    int(dut.m_axis_data.value),
                    int(dut.m_axis_last.value),
                )
            )
        await RisingEdge(dut.clk)
        if len(observed) >= target_count:
            return observed
    return observed


@cocotb.test()
async def syntax_frontend_forwards_raw_symbols(dut):
    await reset(dut)

    dut.raw_symbol_valid.value = 1
    dut.raw_symbol_kind.value = 2
    dut.raw_symbol_data.value = 0x1234
    dut.raw_symbol_last.value = 1
    await ReadOnly()
    assert int(dut.raw_symbol_ready.value) == 1
    await RisingEdge(dut.clk)
    dut.raw_symbol_valid.value = 0
    await Timer(1, unit="ps")

    assert int(dut.ctu_ready.value) == 0
    assert int(dut.m_axis_valid.value) == 1
    assert int(dut.m_axis_kind.value) == 2
    assert int(dut.m_axis_data.value) == 0x1234
    assert int(dut.m_axis_last.value) == 1


@cocotb.test()
async def syntax_frontend_rejects_ctu_parameter_path(dut):
    await reset(dut)

    dut.ctu_valid.value = 1
    await Timer(1, unit="ns")

    assert int(dut.ctu_ready.value) == 0
    assert int(dut.m_axis_valid.value) == 0


@cocotb.test()
async def syntax_frontend_expands_palette_start_from_prediction_mode(dut):
    await reset(dut)

    dut.raw_symbol_valid.value = 1
    dut.raw_symbol_kind.value = 0x81
    dut.raw_symbol_data.value = (1 << 24) | (1 << 16)
    dut.raw_symbol_last.value = 0
    await ReadOnly()
    assert int(dut.raw_symbol_ready.value) == 1
    await RisingEdge(dut.clk)
    dut.raw_symbol_valid.value = 0
    await Timer(1, unit="ps")

    observed = []
    for _ in range(8):
        await ReadOnly()
        if int(dut.m_axis_valid.value) == 1:
            observed.append((int(dut.m_axis_kind.value), int(dut.m_axis_data.value)))
        await RisingEdge(dut.clk)
        if len(observed) == 2:
            break

    assert observed[0] == (2, 1 | (42 << 8))
    assert observed[1][0] == 4


@cocotb.test()
async def syntax_frontend_terminates_single_entry_palette_index_tail(dut):
    await reset(dut)

    await send_raw_symbol(dut, 0x81, (1 << 24) | (1 << 16), 0)
    observed = await collect_output_symbols(dut, 2)
    assert observed[0] == (2, 1 | (42 << 8), 0)
    assert observed[1][0] == 4

    await send_raw_symbol(dut, 0x82, 0x12, 0)
    await send_raw_symbol(dut, 0x84, 0x34, 0)
    await send_raw_symbol(dut, 0x85, 0x56, 0)
    await collect_output_symbols(dut, 4)

    await send_raw_symbol(dut, 0x83, 0, 1)
    observed = await collect_output_symbols(dut, 1)
    assert observed == [(1, 1, 1)]


@cocotb.test()
async def syntax_frontend_emits_palette_predictor_run_after_first_cu(dut):
    await reset(dut)

    await send_raw_symbol(dut, 0x81, (1 << 24) | (1 << 16), 0)
    observed = await collect_output_symbols(dut, 2)
    assert observed[0] == (2, 1 | (42 << 8), 0), observed
    assert observed[1] == (4, (2 << 6) | 2, 0), observed
    await send_raw_symbol(dut, 0x82, 0x12, 0)
    await send_raw_symbol(dut, 0x84, 0x34, 0)
    await send_raw_symbol(dut, 0x85, 0x56, 0)
    await collect_output_symbols(dut, 4)

    await send_raw_symbol(dut, 0x81, (1 << 24) | (1 << 16), 0)
    observed = await collect_output_symbols(dut, 3)
    assert observed[0] == (2, 1 | (42 << 8), 0), observed
    assert observed[1] == (4, (2 << 6) | 2, 0), observed
    assert observed[2] == (4, 1, 0), observed
