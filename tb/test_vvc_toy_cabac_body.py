from cocotb.triggers import Timer
import cocotb


BODY_GENERATED = 0


def cabac_bytes(dut):
    bit_len = int(dut.cabac_bit_len.value)
    value = int(dut.cabac_bits.value)
    if bit_len == 0:
        return b""
    return value.to_bytes((bit_len + 7) // 8, byteorder="big")


@cocotb.test()
async def cabac_body_generates_8x8_black_payload(dut):
    dut.body_kind.value = BODY_GENERATED
    dut.coded_width.value = 8
    dut.coded_height.value = 8
    dut.luma_rem.value = 16
    dut.chroma_rem.value = 6
    await Timer(1, unit="ns")

    assert int(dut.supported.value) == 1
    assert int(dut.cabac_bit_len.value) == 56
    assert cabac_bytes(dut).hex() == "8062f5b7ebcb1f"


@cocotb.test()
async def cabac_body_generates_16x16_generated_payload(dut):
    dut.body_kind.value = BODY_GENERATED
    dut.coded_width.value = 16
    dut.coded_height.value = 16
    dut.luma_rem.value = 16
    dut.chroma_rem.value = 6
    await Timer(1, unit="ns")

    assert int(dut.supported.value) == 1
    assert int(dut.cabac_bit_len.value) > 56
    assert cabac_bytes(dut) != b""


@cocotb.test()
async def cabac_body_generates_32x32_block_payload(dut):
    dut.body_kind.value = BODY_GENERATED
    dut.coded_width.value = 32
    dut.coded_height.value = 32
    dut.luma_rem.value = 16
    dut.chroma_rem.value = 6
    await Timer(1, unit="ns")

    assert int(dut.supported.value) == 1
    bit_len = int(dut.cabac_bit_len.value)
    payload = cabac_bytes(dut)
    assert bit_len == 403
    assert payload.hex() == (
        "00020410208104082041020810408204102081040820410208104082041020810408204102081040820410208104082041023e"
    )


@cocotb.test()
async def cabac_body_generates_64x64_partition_payload(dut):
    dut.body_kind.value = BODY_GENERATED
    dut.coded_width.value = 64
    dut.coded_height.value = 64
    dut.luma_rem.value = 16
    dut.chroma_rem.value = 6
    await Timer(1, unit="ns")

    assert int(dut.supported.value) == 1
    assert int(dut.cabac_bit_len.value) > 403
    assert cabac_bytes(dut) != b""
