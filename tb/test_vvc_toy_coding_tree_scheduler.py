from cocotb.triggers import Timer
import cocotb


BODY_8X8_GENERATED = 0
BODY_16X16_FALLBACK = 1
BODY_32X32_FALLBACK = 2
BODY_CAPACITY_GRID = 3


async def check_geometry(dut, width, height, coded_width, coded_height, body_kind):
    dut.visible_width.value = width
    dut.visible_height.value = height
    await Timer(1, unit="ns")

    assert int(dut.coded_width.value) == coded_width
    assert int(dut.coded_height.value) == coded_height
    assert int(dut.body_kind.value) == body_kind
    assert int(dut.uses_capacity_tu_grid.value) == (body_kind == BODY_CAPACITY_GRID)

    expected_tus = ((width + 3) // 4) * ((height + 3) // 4)
    assert int(dut.luma_tu_count.value) == expected_tus
    assert int(dut.capacity_tu_grid_bit_len.value) == 16 + (expected_tus * 13)


@cocotb.test()
async def coding_tree_scheduler_selects_local_body_kind(dut):
    await check_geometry(dut, 4, 4, 8, 8, BODY_8X8_GENERATED)
    await check_geometry(dut, 8, 8, 8, 8, BODY_8X8_GENERATED)
    await check_geometry(dut, 16, 16, 16, 16, BODY_16X16_FALLBACK)
    await check_geometry(dut, 4, 16, 16, 16, BODY_16X16_FALLBACK)
    await check_geometry(dut, 32, 32, 32, 32, BODY_32X32_FALLBACK)
    await check_geometry(dut, 32, 16, 32, 32, BODY_32X32_FALLBACK)
    await check_geometry(dut, 16, 32, 32, 32, BODY_32X32_FALLBACK)
    await check_geometry(dut, 64, 64, 64, 64, BODY_CAPACITY_GRID)
