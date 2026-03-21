import cocotb
from cocotb.triggers import RisingEdge, Timer

async def reset(dut):
    dut.rst_n.value = 0
    dut.clk.value = 0
    await Timer(10, unit="ns")
    dut.rst_n.value = 1
    await Timer(10, unit="ns")

async def generate_clock(dut):
    while True:
        dut.clk.value = 0
        await Timer(50, unit="ns") # 10MHz
        dut.clk.value = 1
        await Timer(50, unit="ns")

async def spi_slave_mock(dut):
    """Mocks the MPU-6500 SPI Slave."""
    while True:
        # Wait for CS low
        while dut.spi_cs_n.value != 0:
            await RisingEdge(dut.clk)

        # Transfer starts
        cmd = 0
        cmd_valid = True

        # Read command (first byte)
        for i in range(8):
            while dut.spi_sclk.value != 0:
                await RisingEdge(dut.clk)
                if dut.spi_cs_n.value != 0:
                    cmd_valid = False
                    break
            if not cmd_valid: break

            try:
                bit = int(dut.spi_mosi.value)
            except ValueError:
                bit = 0
            cmd = (cmd << 1) | bit

            while dut.spi_sclk.value != 1:
                await RisingEdge(dut.clk)
                if dut.spi_cs_n.value != 0:
                    cmd_valid = False
                    break
            if not cmd_valid: break

        if not cmd_valid:
            continue

        if cmd == 0xBB: # ACCEL X
            data = [0x00, 0x00]
        elif cmd == 0xBD: # ACCEL Y
            data = [0x00, 0x00]
        elif cmd == 0xBF: # ACCEL Z
            data = [0x40, 0x00]
        elif cmd == 0xC3: # GYRO X
            data = [0x00, 0x00]
        elif cmd == 0xC5: # GYRO Y
            data = [0x00, 0x00]
        elif cmd == 0xC7: # GYRO Z
            data = [0x00, 0x00]
        elif cmd == 0xF5: # WHO_AM_I
            data = [0x70]
        else:
            data = []

        for byte in data:
            for i in range(8):
                while dut.spi_sclk.value != 1:
                    await RisingEdge(dut.clk)
                    if dut.spi_cs_n.value != 0: break
                if dut.spi_cs_n.value != 0: break

                dut.spi_miso.value = (byte >> (7-i)) & 1

                while dut.spi_sclk.value != 0:
                    await RisingEdge(dut.clk)
                    if dut.spi_cs_n.value != 0: break
            if dut.spi_cs_n.value != 0: break

        while dut.spi_cs_n.value == 0:
            await RisingEdge(dut.clk)

async def read_uart_byte(dut, baud_rate=2000000):
    """Decodes a single byte from the UART TX line."""
    # Calculate bit time in ns (1e9 / 9600 ~= 104166.67 ns)
    bit_time_ns = 1_000_000_000 / baud_rate

    # Wait for Start Bit (Falling Edge)
    while dut.uart_tx_out.value != 0:
        await RisingEdge(dut.clk)

    # Wait 1.5 bit times to sample the middle of bit 0
    await Timer(bit_time_ns * 1.5, unit="ns", round_mode="round")

    byte = 0
    for i in range(8):
        if dut.uart_tx_out.value != 0:
            byte |= (1 << i)
        await Timer(bit_time_ns, unit="ns", round_mode="round")

    return byte

@cocotb.test()
async def test_top_level(dut):
    """Test full system integration."""
    cocotb.start_soon(generate_clock(dut))
    cocotb.start_soon(spi_slave_mock(dut))

    await reset(dut)

    dut._log.info("Waiting for UART output...")

    # Read 6 bytes from the UART stream
    received_bytes = []
    for i in range(6):
        byte = await read_uart_byte(dut)
        received_bytes.append(byte)
        dut._log.info(f"Received UART Byte {i}: {hex(byte)}")

    # 1. Verify Header
    assert received_bytes[0] == 0xDE
    assert received_bytes[1] == 0xAD
    dut._log.info("Header verified!")

    dut._log.info("Test Passed!")
