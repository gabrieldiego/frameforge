from cocotb.triggers import Timer
import cocotb


BODY_8X8_GENERATED = 0
BODY_16X16_FALLBACK = 1


def cabac_bytes(dut):
    bit_len = int(dut.cabac_bit_len.value)
    value = int(dut.cabac_bits.value)
    if bit_len == 0:
        return b""
    return value.to_bytes((bit_len + 7) // 8, byteorder="big")


@cocotb.test()
async def cabac_body_generates_8x8_black_payload(dut):
    dut.body_kind.value = BODY_8X8_GENERATED
    dut.luma_rem.value = 16
    dut.chroma_rem.value = 6
    await Timer(1, unit="ns")

    assert int(dut.supported.value) == 1
    assert int(dut.cabac_bit_len.value) == 56
    assert cabac_bytes(dut).hex() == "8062f5b7ebcb1f"


@cocotb.test()
async def cabac_body_generates_16x16_fallback_payload(dut):
    dut.body_kind.value = BODY_16X16_FALLBACK
    dut.luma_rem.value = 16
    dut.chroma_rem.value = 6
    await Timer(1, unit="ns")

    assert int(dut.supported.value) == 1
    assert int(dut.cabac_bit_len.value) > 56
    assert cabac_bytes(dut) != b""
