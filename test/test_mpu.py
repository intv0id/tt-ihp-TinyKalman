import cocotb
from cocotb.triggers import RisingEdge, Timer

async def reset(dut):
    dut.rst_n.value = 0
    dut.clk.value = 0
    await Timer(10, units="ns")
    dut.rst_n.value = 1
    await Timer(10, units="ns")

async def generate_clock(dut):
    while True:
        dut.clk.value = 0
        await Timer(50, units="ns") # 10MHz
        dut.clk.value = 1
        await Timer(50, units="ns")

@cocotb.test()
async def test_mpu_init_and_read(dut):
    """Test MPU initialization and data reading sequence."""

    # Start clock
    cocotb.start_soon(generate_clock(dut))

    # Set initial inputs
    dut.spi_miso.value = 0

    # Reset
    await reset(dut)

    dut._log.info("Waiting for Initialization S_RST_1")

    # Wait for S_RST_1 (state 1)
    while dut.state.value != 1:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_RST_1 (Write 0x80 to PWR_MGMT_1)")

    # Wait for transaction to complete (S_RST_1 -> S_RST_2_WAIT)
    while dut.state.value != 4:
        await RisingEdge(dut.clk)

    # Wait for S_RST_DELAY (state 5)
    while dut.state.value != 5:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_RST_DELAY (Wait 100ms)")
    assert dut.spi_cs_n.value == 1

    # Wait for S_WAKE_1 (state 6)
    while dut.state.value != 6:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_WAKE_1 (Write 0x01 to PWR_MGMT_1)")

    # Wait for S_WAKE_DELAY (state 10)
    while dut.state.value != 10:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_WAKE_DELAY (Wait 200ms)")
    assert dut.spi_cs_n.value == 1

    # Wait for S_IDLE (state 11)
    while dut.state.value != 11:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_IDLE")
    assert dut.spi_cs_n.value == 1

    # Wait for S_READ_START (state 12)
    while dut.state.value != 12:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_READ_START")

    for i in range(6):
        dut._log.info(f"Reading register pair {i}")

        # Wait for S_READ_H (state 15)
        while dut.state.value != 15:
            await RisingEdge(dut.clk)

        dut.spi_miso.value = 1 # Dummy value for high byte (0xFF)

        # Wait for S_READ_L (state 17)
        while dut.state.value != 17:
            await RisingEdge(dut.clk)

        dut.spi_miso.value = 0 # Dummy value for low byte (0x00)

        # Wait for CS to deassert (S_READ_NEXT)
        while dut.state.value != 19:
            await RisingEdge(dut.clk)

        assert dut.spi_cs_n.value == 1

    # Wait for valid signal (S_UPDATE)
    while dut.valid.value == 0:
        await RisingEdge(dut.clk)

    dut._log.info("Valid signal received")

    # Check values
    # If MISO was 1 for High and 0 for Low, we read 0xFF00.
    assert dut.accel_x.value == 0xFF00
    assert dut.accel_y.value == 0xFF00
    assert dut.accel_z.value == 0xFF00
    assert dut.gyro_x.value == 0xFF00
    assert dut.gyro_y.value == 0xFF00
    assert dut.gyro_z.value == 0xFF00

    dut._log.info("Test passed!")
