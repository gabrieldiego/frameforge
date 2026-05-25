from cocotb.triggers import Timer
import cocotb


BODY_GENERATED = 0


async def check_geometry(dut, width, height, coded_width, coded_height):
    dut.visible_width.value = width
    dut.visible_height.value = height
    await Timer(1, unit="ns")

    assert int(dut.coded_width.value) == coded_width
    assert int(dut.coded_height.value) == coded_height
    assert int(dut.body_kind.value) == BODY_GENERATED


@cocotb.test()
async def coding_tree_scheduler_selects_local_body_kind(dut):
    await check_geometry(dut, 4, 4, 8, 8)
    await check_geometry(dut, 8, 8, 8, 8)
    await check_geometry(dut, 16, 16, 16, 16)
    await check_geometry(dut, 4, 16, 16, 16)
    await check_geometry(dut, 32, 32, 32, 32)
    await check_geometry(dut, 32, 16, 32, 32)
    await check_geometry(dut, 16, 32, 32, 32)
    await check_geometry(dut, 64, 64, 64, 64)
    await check_geometry(dut, 64, 32, 64, 32)
    await check_geometry(dut, 32, 64, 32, 64)
