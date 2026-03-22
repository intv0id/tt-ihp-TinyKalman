# MPU-6500 MicroPython Driver for Raspberry Pi Pico

This document provides instructions on how to set up and run the `mpu_query.py` script on a Raspberry Pi Pico to interface with an MPU-6500 inertial measurement unit (IMU).

## 1. Hardware Setup

### Required Components
- Raspberry Pi Pico with MicroPython installed.
- MPU-6500 breakout board.
- Breadboard and jumper wires.

### Pin Mapping (Pico to MPU-6500)

Connect the Raspberry Pi Pico to the MPU-6500 module as follows:

| Raspberry Pi Pico Pin | MPU-6500 Pin | Description              |
| --------------------- | ------------ | ------------------------ |
| GP2 (SPI0 SCK)        | SCL/SCK      | SPI Clock                |
| GP3 (SPI0 TX)         | SDA/SDI/MOSI | SPI Data Out (Controller In) |
| GP4 (SPI0 RX)         | SDO/MISO     | SPI Data In (Controller Out)  |
| GP5                   | CS/nCS       | Chip Select (Active Low) |
| 3V3(OUT) (Pin 36)     | VCC          | 3.3V Power               |
| GND (Pin 38)          | GND          | Ground                   |

**Note:** The MPU-6500 is a 3.3V device. Ensure you are using a 3.3V logic level and power supply.

## 2. Software Setup

### Installing MicroPython on Raspberry Pi Pico

If your Pico does not have MicroPython installed, follow these steps:
1.  Download the latest MicroPython UF2 file for the Raspberry Pi Pico from the [official MicroPython website](https://micropython.org/download/RPI_PICO/).
2.  Press and hold the `BOOTSEL` button on your Pico while plugging it into your computer's USB port.
3.  The Pico will mount as a mass storage device named `RPI-RP2`.
4.  Drag and drop the downloaded `.uf2` file onto the `RPI-RP2` drive.
5.  The Pico will automatically reboot and will now be running MicroPython.

### Running the Script

1.  **Connect to the Pico:** Use a serial terminal application like `minicom` (Linux/macOS) or PuTTY (Windows), or an IDE like Thonny, which is specifically designed for MicroPython. The serial device is typically `/dev/ttyACM0` on Linux or `COM3` on Windows. The baud rate is 115200.

2.  **Using Thonny IDE (Recommended for Beginners):**
    *   Download and install [Thonny](https://thonny.org/).
    *   Open Thonny and go to `Run` -> `Select interpreter...`.
    *   Choose `MicroPython (Raspberry Pi Pico)` as the interpreter and select the correct serial port.
    *   Open the `mpu_query.py` script in Thonny.
    *   Click the "Run" button (or press F5). The script will be uploaded to the Pico and executed.

3.  **Using `rshell` (Command-Line):**
    *   Install `rshell`: `pip install rshell`
    *   Connect to the Pico: `rshell -p /dev/ttyACM0` (replace with your port).
    *   Navigate to the `prototype` directory on your local machine.
    *   Copy the script to the Pico's filesystem: `cp mpu_query.py /pyboard/`
    *   To run the script, enter the REPL (`repl`) and import the script: `import mpu_query`

## 3. Expected Output

Once the script is running, you should see output in your serial terminal similar to this, updated every half-second:

```
MPU6500 found successfully.
Accel: X=  -512, Y=  1024, Z= 16250 | Gyro: X=   -30, Y=    55, Z=   -10
Accel: X=  -510, Y=  1022, Z= 16255 | Gyro: X=   -31, Y=    54, Z=   -12
...
```

The values are the raw 16-bit signed integers from the sensor's registers.
