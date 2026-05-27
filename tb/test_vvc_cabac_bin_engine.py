import cocotb
from cocotb.triggers import Timer


CABAC_BIN_EP = 0
CABAC_BIN_TRM = 1
CABAC_BIN_CTX = 2


async def settle():
    await Timer(1, unit="ns")


def drive_state(dut, *, kind, bit, low=0, range_=510, bits_left=23, lps=4, mps=0):
    dut.bin_kind.value = kind
    dut.bin_value.value = bit
    dut.ctx_lps.value = lps
    dut.ctx_mps.value = mps
    dut.low_in.value = low
    dut.range_in.value = range_
    dut.bits_left_in.value = bits_left


@cocotb.test()
async def bypass_bins_shift_low_and_consume_one_bit(dut):
    drive_state(dut, kind=CABAC_BIN_EP, bit=0)
    await settle()
    assert int(dut.low_out.value) == 0
    assert int(dut.range_out.value) == 510
    assert int(dut.bits_left_out.value) == 22
    assert int(dut.write_out.value) == 0

    drive_state(dut, kind=CABAC_BIN_EP, bit=1)
    await settle()
    assert int(dut.low_out.value) == 510
    assert int(dut.range_out.value) == 510
    assert int(dut.bits_left_out.value) == 22
    assert int(dut.write_out.value) == 0


@cocotb.test()
async def terminating_one_moves_to_final_range(dut):
    drive_state(dut, kind=CABAC_BIN_TRM, bit=1)
    await settle()
    assert int(dut.low_out.value) == 65024
    assert int(dut.range_out.value) == 256
    assert int(dut.bits_left_out.value) == 16
    assert int(dut.write_out.value) == 0


@cocotb.test()
async def context_mps_and_lps_paths_match_expected_renorm(dut):
    drive_state(dut, kind=CABAC_BIN_CTX, bit=0, lps=146, mps=0)
    await settle()
    assert int(dut.low_out.value) == 0
    assert int(dut.range_out.value) == 364
    assert int(dut.bits_left_out.value) == 23
    assert int(dut.write_out.value) == 0

    drive_state(dut, kind=CABAC_BIN_CTX, bit=1, lps=146, mps=0)
    await settle()
    assert int(dut.low_out.value) == 728
    assert int(dut.range_out.value) == 292
    assert int(dut.bits_left_out.value) == 22
    assert int(dut.write_out.value) == 0
