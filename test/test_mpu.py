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

    # Wait for S_RST_DELAY (state 3)
    while dut.state.value != 3:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_RST_DELAY (Wait 100ms)")
    assert dut.spi_cs_n.value == 1

    # Wait for S_WAKE_1 (state 4)
    while dut.state.value != 4:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_WAKE_1 (Write 0x01 to PWR_MGMT_1)")

    # Wait for S_WAKE_DELAY (state 6)
    while dut.state.value != 6:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_WAKE_DELAY (Wait 200ms)")
    assert dut.spi_cs_n.value == 1

    # Wait for S_CHECK_WHOAMI (state 7)
    while dut.state.value != 7:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_CHECK_WHOAMI")

    # Wait for Address write to finish and S_CHECK_WAIT to trigger dummy read
    while dut.state.value != 8:
        await RisingEdge(dut.clk)

    while dut.spi_inst.state.value == 0:
        await RisingEdge(dut.clk)

    # Now it sends 0x75 (WHO_AM_I address). Wait for it to finish.
    while dut.spi_inst.done.value == 0:
        await RisingEdge(dut.clk)

    # Wait for spi_master to start the dummy byte (read payload)
    while dut.spi_inst.state.value == 0:
        await RisingEdge(dut.clk)

    # Now it is reading. Feed 0x70 on MISO.
    bits = [0, 1, 1, 1, 0, 0, 0, 0]
    for b in bits:
        # Wait for falling edge of SCLK
        while dut.spi_sclk.value == 1:
            await RisingEdge(dut.clk)
        dut.spi_miso.value = b
        # Wait for rising edge of SCLK
        while dut.spi_sclk.value == 0:
            await RisingEdge(dut.clk)

    # Wait for S_IDLE (state 9)
    while dut.state.value != 9:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_IDLE")
    assert dut.spi_cs_n.value == 1

    # Wait for S_READ_START (state 10)
    while dut.state.value != 10:
        await RisingEdge(dut.clk)

    dut._log.info("Entered S_READ_START")

    for i in range(6):
        dut._log.info(f"Reading register pair {i}")

        # Wait for S_READ_WAIT (state 11)
        while dut.state.value != 11:
            await RisingEdge(dut.clk)

        # The submodule is now active, we need to inject MISO at the right time
        # Let's just set MISO statically for now to something distinct.
        # We need `temp_h` and `spi_data_out` to read correctly.
        # It's easier to toggle MISO based on spi_cs_n because the logic is deeply nested.
        # Just hardcode a value for the transaction.
        dut.spi_miso.value = 1

        # Wait for it to finish the read
        # S_READ_WAIT goes back to S_READ_START or S_UPDATE
        while dut.state.value == 11:
            await RisingEdge(dut.clk)

        assert dut.spi_cs_n.value == 1

    # Wait for valid signal (S_UPDATE)
    while dut.valid.value == 0:
        await RisingEdge(dut.clk)

    dut._log.info("Valid signal received")

    # Check values
    # If MISO was 1 constantly, we read 0xFFFF.
    assert dut.accel_x.value == 0xFFFF
    assert dut.accel_y.value == 0xFFFF
    assert dut.accel_z.value == 0xFFFF
    assert dut.gyro_x.value == 0xFFFF
    assert dut.gyro_y.value == 0xFFFF
    assert dut.gyro_z.value == 0xFFFF

    dut._log.info("Test passed!")
