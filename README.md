# Kalman Filter on TinyTapeout

[![gds](https://github.com/intv0id/tt-ihp-TinyKalman/actions/workflows/gds.yaml/badge.svg?branch=main)](https://github.com/intv0id/tt-ihp-TinyKalman/actions/workflows/gds.yaml)
[![docs](https://github.com/intv0id/tt-ihp-TinyKalman/actions/workflows/docs.yaml/badge.svg?branch=main)](https://github.com/intv0id/tt-ihp-TinyKalman/actions/workflows/docs.yaml)
[![test](https://github.com/intv0id/tt-ihp-TinyKalman/actions/workflows/test.yaml/badge.svg?branch=main)](https://github.com/intv0id/tt-ihp-TinyKalman/actions/workflows/test.yaml)
[![fpga](https://github.com/intv0id/tt-ihp-TinyKalman/actions/workflows/fpga.yaml/badge.svg?branch=main)](https://github.com/intv0id/tt-ihp-TinyKalman/actions/workflows/fpga.yaml)

This project implements a simplified Kalman Filter for MPU-6500 sensor fusion on TinyTapeout ASIC and FPGA.

## Features

- **Sensor Interface**: SPI Master for MPU-6500 (Accelerometer + Gyroscope).
- **Angle Calculation**: CORDIC-based `atan2` calculation for Roll and Pitch from accelerometer data.
- **Sensor Fusion**: Steady-state Kalman Filter (Complementary Filter) to fuse Gyroscope rate with Accelerometer angle.
- **Output**: UART Serial output (9600 baud) streaming Roll, Pitch.

## Algorithm Details

### 1. Angle Estimation (CORDIC)

Roll ($\phi$) and Pitch ($\theta$) angles are calculated from the accelerometer vector using an iterative **CORDIC** (COordinate Rotation DIgital Computer) algorithm in vectoring mode. This calculates `atan2(y, x)` efficiently without multipliers.

- **Roll**: $\phi = \text{atan2}(a_y, a_z)$
- **Pitch**: $\theta = \text{atan2}(-a_x, \sqrt{a_y^2 + a_z^2})$

_Note: In this implementation, the Pitch calculation uses a simplified approximation where the magnitude output from the Roll CORDIC is used as the denominator._

### 2. Sensor Fusion (Complementary / Kalman Filter)

The design uses a steady-state 1D Kalman Filter (mathematically equivalent to a Complementary Filter) for both Roll and Pitch axes. This fuses the noisy but stable accelerometer angle with the precise but drifting gyroscope rate.

**Equations:**

1.  **Prediction (Gyro Integration):**
    $$ \theta*{pred}[k] = \theta*{est}[k-1] + (\text{GyroRate} \times \Delta t) $$
    _Implemented as:_ `pred_angle = angle_out + (rate >>> 6)`

2.  **Update (Accelerometer Correction):**
    $$ \theta*{est}[k] = \theta*{pred}[k] + K \times (\theta*{acc}[k] - \theta*{pred}[k]) $$
    _Implemented as:_ `angle_out = pred_angle + ((angle_m - pred_angle) >>> 6)`

- **Gain ($K$):** The Kalman Gain is fixed at $1/64$ (`>>> 6`), balancing responsiveness and noise rejection for a standard 100Hz IMU loop.
- **Time Step ($\Delta t$):** The rate shift factor (`>>> 6`) implicitly handles the scaling for the time step and gyro sensitivity.

## Pinout

| Pin         | Function | Description                           |
| ----------- | -------- | ------------------------------------- |
| `ui_in[0]`  | **MISO** | SPI Master In Slave Out (from Sensor) |
| `uo_out[0]` | **MOSI** | SPI Master Out Slave In (to Sensor)   |
| `uo_out[1]` | **SCLK** | SPI Clock                             |
| `uo_out[2]` | **CS_N** | SPI Chip Select (Active Low)          |
| `uo_out[3]` | **TX**   | UART Transmit (to PC)                 |
| `clk`       | **CLK**  | System Clock (10MHz default)          |
| `rst_n`     | **RST**  | Reset (Active Low)                    |

## Data Format

The device outputs a continuous stream of 8-byte packets at 9600 baud.

| Byte | Value             |
| ---- | ----------------- |
| 0    | `0xDE` (Header)   |
| 1    | `0xAD` (Header)   |
| 2    | Roll (High Byte)  |
| 3    | Roll (Low Byte)   |
| 4    | Pitch (High Byte) |
| 5    | Pitch (Low Byte)  |

Angles are 16-bit signed integers. Scale: `32768 = 180 degrees`.

## Hardware Setup

To test the design on real hardware, you can use the [FPGA ASIC simulator breakout](https://tinytapeout.com/guides/fpga-breakout/) with an MPU-6500 sensor module and an FT232 serial probe.

The default configuration assumes a 10MHz system clock.

**Wiring Instructions:**

*   **FPGA Breakout `ui_in[0]` (MISO)** -> **MPU6500 ADO**
*   **FPGA Breakout `uo_out[0]` (MOSI)** -> **MPU6500 SDA**
*   **FPGA Breakout `uo_out[1]` (SCLK)** -> **MPU6500 SCL**
*   **FPGA Breakout `uo_out[2]` (CS_N)** -> **MPU6500 NCS**
*   **FPGA Breakout `uo_out[3]` (TX)**   -> **FT232 RX**
*   **FPGA Breakout GND**               -> **MPU6500 GND** & **FT232 GND**
*   **FPGA Breakout VCC**               -> **MPU6500 VCC** & **FT232 VCC** (make sure voltage levels are compatible, usually 3.3V)

**Running on the FPGA Breakout:**
1. Download the `fpga_bitstream` artifact from the latest passing GitHub Action run.
2. Extract the archive. You should find a `.bin` file inside (e.g., `tt_um_kalman.bin`).
3. Connect the TinyTapeout demoboard to your Mac.
4. Clone the `tt-support-tools` repository:
   ```bash
   git clone https://github.com/TinyTapeout/tt-support-tools.git tt
   pip install -r tt/requirements.txt
   ```
5. Use the `tt_fpga.py` script to upload the bitstream. Ensure you specify the correct serial port for your Mac (typically `/dev/cu.usbmodem*`):
   ```bash
   ./tt/tt_fpga.py configure --port /dev/cu.usbmodem<your_port_number> --upload --name path/to/extracted/tt_um_kalman.bin --set-default --clockrate 10000000
   ```

## Simulation

To run the testbench (using Cocotb):

```bash
cd test
make
```

## License

Apache 2.0
