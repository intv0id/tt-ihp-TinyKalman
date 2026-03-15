import serial
import struct
import argparse
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from collections import deque

def read_data(ser, max_len=100):
    header = b'\xde\xad'
    roll_data = deque(maxlen=max_len)
    pitch_data = deque(maxlen=max_len)

    print("Waiting for data...")
    while ser.is_open:
        # Align to header
        b1 = ser.read(1)
        if not b1:
            print("Serial port timed out or disconnected.")
            break
        if b1 == b'\xde':
            b2 = ser.read(1)
            if not b2:
                print("Serial port timed out or disconnected.")
                break
            if b2 == b'\xad':
                data = ser.read(4)
                if len(data) == 4:
                    roll, pitch = struct.unpack('>hh', data)
                    # Convert to degrees
                    roll_deg = roll * (180.0 / 32768.0)
                    pitch_deg = pitch * (180.0 / 32768.0)
                    print(f"Received Roll: {roll_deg:.2f}, Pitch: {pitch_deg:.2f}")
                    yield roll_deg, pitch_deg
                else:
                    print("Incomplete data packet received")
            else:
                pass # print(f"Unexpected byte after 0xde: {b2}")
        elif b1 != b'':
            pass # print(f"Unexpected byte: {b1}")

def update(frame, ser, roll_data, pitch_data, line_roll, line_pitch, max_len):
    try:
        roll, pitch = frame
        roll_data.append(roll)
        pitch_data.append(pitch)

        x_data = list(range(len(roll_data)))

        line_roll.set_data(x_data, list(roll_data))
        line_pitch.set_data(x_data, list(pitch_data))

        ax = line_roll.axes
        ax.set_xlim(0, max_len)
        ax.set_ylim(-180, 180)

    except StopIteration:
        pass
    except Exception as e:
        print(f"Error reading: {e}")

    return line_roll, line_pitch

def main():
    parser = argparse.ArgumentParser(description='Live plot roll and pitch from FT232')
    parser.add_argument('--port', type=str, default='/dev/ttyUSB0', help='Serial port')
    parser.add_argument('--baud', type=int, default=9600, help='Baud rate')
    parser.add_argument('--samples', type=int, default=100, help='Number of samples to show')
    args = parser.parse_args()

    try:
        ser = serial.Serial(args.port, args.baud, timeout=1)
        print(f"Connected to {args.port} at {args.baud} baud")
    except Exception as e:
        print(f"Failed to connect: {e}")
        return

    fig, ax = plt.subplots()
    ax.set_title("Live Roll and Pitch")
    ax.set_xlabel("Samples")
    ax.set_ylabel("Degrees")

    roll_data = deque(maxlen=args.samples)
    pitch_data = deque(maxlen=args.samples)

    line_roll, = ax.plot([], [], label="Roll", color='b')
    line_pitch, = ax.plot([], [], label="Pitch", color='r')
    ax.legend()

    data_gen = read_data(ser, args.samples)

    ani = animation.FuncAnimation(
        fig, update, frames=data_gen,
        fargs=(ser, roll_data, pitch_data, line_roll, line_pitch, args.samples),
        interval=50, blit=True, save_count=100
    )

    plt.show()

if __name__ == '__main__':
    main()
