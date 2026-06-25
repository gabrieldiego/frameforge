from cocotb.triggers import RisingEdge

REG_CONTROL = 0x000
REG_STATUS = 0x004
REG_WIDTH = 0x008
REG_HEIGHT = 0x00C
REG_CHROMA_FORMAT = 0x010
REG_FRAME_COUNT = 0x014
REG_SRC_Y_BASE = 0x018
REG_SRC_U_BASE = 0x01C
REG_SRC_V_BASE = 0x020
REG_SRC_Y_STRIDE = 0x024
REG_SRC_U_STRIDE = 0x028
REG_SRC_V_STRIDE = 0x02C
REG_SRC_FRAME_STRIDE = 0x030
REG_DST_BITSTREAM_BASE = 0x034
REG_DST_BITSTREAM_CAPACITY = 0x038
REG_ENCODED_BYTE_COUNT = 0x03C

STATUS_BUSY = 1 << 0
STATUS_DONE = 1 << 1
STATUS_INPUT_ERROR = 1 << 2
STATUS_AXI_ERROR = 1 << 3

AXI_DST_BASE = 0x100000
AXI_DATA_BYTES = 16


def planar_memory_image(data):
    return {index: value for index, value in enumerate(data)}


def read_output_bytes(memory, length, base=AXI_DST_BASE):
    return bytes(memory.get(base + index, 0) for index in range(length))


async def axil_write(dut, addr, data):
    dut.s_axil_awaddr.value = addr
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value = data
    dut.s_axil_wstrb.value = 0xF
    dut.s_axil_wvalid.value = 1
    while True:
        await RisingEdge(dut.clk)
        aw_done = int(dut.s_axil_awready.value) == 1
        w_done = int(dut.s_axil_wready.value) == 1
        if aw_done:
            dut.s_axil_awvalid.value = 0
        if w_done:
            dut.s_axil_wvalid.value = 0
        if aw_done and w_done:
            break
    dut.s_axil_bready.value = 1
    while int(dut.s_axil_bvalid.value) != 1:
        await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.s_axil_bready.value = 0


async def axil_read(dut, addr):
    dut.s_axil_araddr.value = addr
    dut.s_axil_arvalid.value = 1
    while True:
        await RisingEdge(dut.clk)
        if int(dut.s_axil_arready.value) == 1:
            dut.s_axil_arvalid.value = 0
            break
    dut.s_axil_rready.value = 1
    while int(dut.s_axil_rvalid.value) != 1:
        await RisingEdge(dut.clk)
    value = int(dut.s_axil_rdata.value)
    await RisingEdge(dut.clk)
    dut.s_axil_rready.value = 0
    return value


async def program_encoder_control(
    dut,
    *,
    width,
    height,
    chroma_format,
    frame_count,
    src_y_base,
    src_u_base,
    src_v_base,
    src_y_stride,
    src_u_stride,
    src_v_stride,
    src_frame_stride,
    dst_base=AXI_DST_BASE,
    dst_capacity=1 << 20,
):
    await axil_write(dut, REG_CONTROL, 0x2)
    await axil_write(dut, REG_WIDTH, width)
    await axil_write(dut, REG_HEIGHT, height)
    await axil_write(dut, REG_CHROMA_FORMAT, chroma_format)
    await axil_write(dut, REG_FRAME_COUNT, frame_count)
    await axil_write(dut, REG_SRC_Y_BASE, src_y_base)
    await axil_write(dut, REG_SRC_U_BASE, src_u_base)
    await axil_write(dut, REG_SRC_V_BASE, src_v_base)
    await axil_write(dut, REG_SRC_Y_STRIDE, src_y_stride)
    await axil_write(dut, REG_SRC_U_STRIDE, src_u_stride)
    await axil_write(dut, REG_SRC_V_STRIDE, src_v_stride)
    await axil_write(dut, REG_SRC_FRAME_STRIDE, src_frame_stride)
    await axil_write(dut, REG_DST_BITSTREAM_BASE, dst_base)
    await axil_write(dut, REG_DST_BITSTREAM_CAPACITY, dst_capacity)


async def start_encoder_via_axil(dut):
    await axil_write(dut, REG_CONTROL, 0x1)


def reset_axil_signals(dut):
    dut.s_axil_awaddr.value = 0
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wdata.value = 0
    dut.s_axil_wstrb.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_araddr.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0


def reset_axi_memory_signals(dut):
    dut.m_axi_arready.value = 0
    dut.m_axi_rvalid.value = 0
    dut.m_axi_rdata.value = 0
    dut.m_axi_rresp.value = 0
    dut.m_axi_rlast.value = 0
    dut.m_axi_awready.value = 0
    dut.m_axi_wready.value = 0
    dut.m_axi_bvalid.value = 0
    dut.m_axi_bresp.value = 0


async def axi_read_memory_model(dut, memory):
    dut.m_axi_arready.value = 1
    dut.m_axi_rvalid.value = 0
    dut.m_axi_rdata.value = 0
    dut.m_axi_rresp.value = 0
    dut.m_axi_rlast.value = 0
    pending = None
    while True:
        await RisingEdge(dut.clk)
        if int(dut.m_axi_rvalid.value) == 1 and int(dut.m_axi_rready.value) == 1:
            dut.m_axi_rvalid.value = 0
            dut.m_axi_rlast.value = 0
        if pending is not None and int(dut.m_axi_rvalid.value) == 0:
            addr, size, beat, beats = pending
            word = 0
            for offset in range(size):
                word |= memory.get(addr + offset, 0) << (8 * offset)
            dut.m_axi_rdata.value = word
            dut.m_axi_rresp.value = 0
            dut.m_axi_rlast.value = 1 if beat == beats - 1 else 0
            dut.m_axi_rvalid.value = 1
            if beat == beats - 1:
                pending = None
            else:
                pending = (addr + size, size, beat + 1, beats)
        if int(dut.m_axi_arvalid.value) == 1 and int(dut.m_axi_arready.value) == 1:
            pending = (
                int(dut.m_axi_araddr.value),
                1 << int(dut.m_axi_arsize.value),
                0,
                int(dut.m_axi_arlen.value) + 1,
            )


async def axi_write_memory_model(dut, memory, data_bytes=AXI_DATA_BYTES):
    dut.m_axi_awready.value = 1
    dut.m_axi_wready.value = 1
    dut.m_axi_bvalid.value = 0
    dut.m_axi_bresp.value = 0
    pending_addr = None
    pending_beats = 0
    pending_size = data_bytes
    while True:
        await RisingEdge(dut.clk)
        if int(dut.m_axi_bvalid.value) == 1 and int(dut.m_axi_bready.value) == 1:
            dut.m_axi_bvalid.value = 0
        if int(dut.m_axi_awvalid.value) == 1 and int(dut.m_axi_awready.value) == 1:
            pending_addr = int(dut.m_axi_awaddr.value)
            pending_beats = int(dut.m_axi_awlen.value) + 1
            pending_size = 1 << int(dut.m_axi_awsize.value)
        if int(dut.m_axi_wvalid.value) == 1 and int(dut.m_axi_wready.value) == 1:
            assert pending_addr is not None, "AXI write data arrived without an address"
            strobe = int(dut.m_axi_wstrb.value)
            data_bits = dut.m_axi_wdata.value.binstr
            data_width = len(data_bits)
            for byte in range(pending_size):
                if strobe & (1 << byte):
                    lane_lsb = data_width - (8 * (byte + 1))
                    lane_msb = data_width - (8 * byte)
                    lane_bits = data_bits[lane_lsb:lane_msb]
                    if any(bit not in "01" for bit in lane_bits):
                        raise ValueError(
                            f"AXI write byte lane {byte} is strobed but unknown: {lane_bits}"
                        )
                    memory[pending_addr + byte] = int(lane_bits, 2)
            pending_addr += pending_size
            pending_beats -= 1
            if int(dut.m_axi_wlast.value) == 1:
                assert pending_beats == 0, "AXI write burst ended before AWLEN beats"
                pending_addr = None
                dut.m_axi_bvalid.value = 1
