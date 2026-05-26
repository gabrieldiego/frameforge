from cocotb.triggers import Timer
import cocotb


async def check_partition(dut, width, height, coded_width, coded_height, root_split, leaf_count):
    dut.visible_width.value = width
    dut.visible_height.value = height
    await Timer(1, unit="ns")

    assert int(dut.coded_width.value) == coded_width
    assert int(dut.coded_height.value) == coded_height
    assert int(dut.root_quad_split.value) == root_split
    assert int(dut.luma_leaf_count.value) == leaf_count


@cocotb.test()
async def luma_partition_matches_software_geometry_plan(dut):
    await check_partition(dut, 4, 4, 8, 8, 0, 1)
    await check_partition(dut, 16, 16, 16, 16, 0, 1)
    await check_partition(dut, 32, 16, 32, 16, 0, 1)
    await check_partition(dut, 64, 24, 64, 24, 1, 4)
    await check_partition(dut, 32, 32, 32, 32, 0, 1)
    await check_partition(dut, 64, 64, 64, 64, 1, 4)
