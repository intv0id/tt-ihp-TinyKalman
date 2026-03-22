# Micropython script to read from MPU6500
# Author: Gemini
# Description: This script reads the accelerometer and gyroscope data from an MPU6500 sensor using SPI.

import machine
import time
import ustruct

# MPU6500 registers
PWR_MGMT_1 = 0x6B
ACCEL_XOUT_H = 0x3B
ACCEL_XOUT_L = 0x3C
ACCEL_YOUT_H = 0x3D
ACCEL_YOUT_L = 0x3E
ACCEL_ZOUT_H = 0x3F
ACCEL_ZOUT_L = 0x40
GYRO_XOUT_H = 0x43
GYRO_XOUT_L = 0x44
GYRO_YOUT_H = 0x45
GYRO_YOUT_L = 0x46
GYRO_ZOUT_H = 0x47
GYRO_ZOUT_L = 0x48
WHO_AM_I = 0x75

# SPI configuration for Raspberry Pi Pico
# SCK: GP2
# MOSI: GP3
# MISO: GP4
# CS: GP5
spi = machine.SPI(0, baudrate=200000, polarity=1, phase=1, sck=machine.Pin(2), mosi=machine.Pin(3), miso=machine.Pin(4))
cs = machine.Pin(5, machine.Pin.OUT)

def read_register(reg):
    """Reads a byte from the specified register."""
    cs.value(0)
    # Set the read bit (MSB) for the register address
    addr = reg | 0x80
    spi.write(bytes([addr]))
    data = spi.read(1)
    cs.value(1)
    return data[0]

def read_register_16(reg_h):
    """Reads a 16-bit value from two consecutive registers."""
    cs.value(0)
    # Set the read bit for the high byte register address
    addr_h = reg_h | 0x80
    spi.write(bytes([addr_h]))
    # Read two bytes (high and low)
    data = spi.read(2)
    cs.value(1)
    # Combine the high and low bytes into a single signed 16-bit integer
    return ustruct.unpack('>h', data)[0]


def write_register(reg, value):
    """Writes a byte to the specified register."""
    cs.value(0)
    # The write operation does not require setting the MSB
    spi.write(bytes([reg, value]))
    cs.value(1)

def init_mpu6500():
    """Initializes the MPU6500 sensor."""
    # Reset the device
    write_register(PWR_MGMT_1, 0x80)
    time.sleep_ms(100)
    
    # Wake up the device and set clock source to gyroscope
    write_register(PWR_MGMT_1, 0x01)
    time.sleep_ms(200)

    # Check the WHO_AM_I register
    who_am_i = read_register(WHO_AM_I)
    if who_am_i != 0x70:
        print("Error: MPU6500 not found. WHO_AM_I: 0x{:02X}".format(who_am_i))
        return False
    
    print("MPU6500 found successfully.")
    return True

def read_sensor_data():
    """Reads and returns accelerometer and gyroscope data."""
    accel_x = read_register_16(ACCEL_XOUT_H)
    accel_y = read_register_16(ACCEL_YOUT_H)
    accel_z = read_register_16(ACCEL_ZOUT_H)
    
    gyro_x = read_register_16(GYRO_XOUT_H)
    gyro_y = read_register_16(GYRO_YOUT_H)
    gyro_z = read_register_16(GYRO_ZOUT_H)
    
    return {
        "accel": (accel_x, accel_y, accel_z),
        "gyro": (gyro_x, gyro_y, gyro_z)
    }

def main():
    if not init_mpu6500():
        return

    while True:
        data = read_sensor_data()
        print("Accel: X={:6d}, Y={:6d}, Z={:6d} | Gyro: X={:6d}, Y={:6d}, Z={:6d}".format(
            data["accel"][0], data["accel"][1], data["accel"][2],
            data["gyro"][0], data["gyro"][1], data["gyro"][2]
        ))
        time.sleep_ms(500)

if __name__ == "__main__":
    main()
