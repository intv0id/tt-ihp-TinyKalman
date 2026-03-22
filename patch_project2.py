import re

with open('src/project.v', 'r') as f:
    content = f.read()

# Replace CORDIC inputs with mux
content = content.replace("    reg signed [15:0] cordic_x, cordic_y;", "    wire signed [15:0] cordic_x = (state == S_CALC_ROLL) ? (accel_z >>> 1) : mag_yz;\n    wire signed [15:0] cordic_y = (state == S_CALC_ROLL) ? (accel_y >>> 1) : -accel_x_scaled;")

# Remove register assignments for CORDIC
content = content.replace("            cordic_x <= 0;\n", "")
content = content.replace("            cordic_y <= 0;\n", "")
content = content.replace("                    cordic_x <= accel_z >>> 1;\n", "")
content = content.replace("                    cordic_y <= accel_y >>> 1;\n", "")
content = content.replace("                    cordic_x <= mag_yz;\n", "")
content = content.replace("                    cordic_y <= -accel_x_scaled;\n", "")

# Replace Kalman inputs with direct assignments
content = content.replace("    reg signed [15:0] kalman_rate_roll, kalman_angle_m_roll;", "    wire signed [15:0] kalman_rate_roll = gyro_x;\n    wire signed [15:0] kalman_angle_m_roll = roll_m;")
content = content.replace("    reg signed [15:0] kalman_rate_pitch, kalman_angle_m_pitch;", "    wire signed [15:0] kalman_rate_pitch = gyro_y;\n    wire signed [15:0] kalman_angle_m_pitch = pitch_m;")

# Remove register assignments for Kalman
content = content.replace("            kalman_rate_roll <= 0;\n", "")
content = content.replace("            kalman_angle_m_roll <= 0;\n", "")
content = content.replace("            kalman_rate_pitch <= 0;\n", "")
content = content.replace("            kalman_angle_m_pitch <= 0;\n", "")

content = content.replace("""                    kalman_rate_roll <= gyro_x;
                    kalman_angle_m_roll <= roll_m;

                    kalman_rate_pitch <= gyro_y;
                    kalman_angle_m_pitch <= pitch_m;""", "")

# Replace UART data with mux
content = content.replace("    reg [7:0] uart_data;\n", "")
content = content.replace("            uart_data <= 0;\n", "")

uart_mux = """
    wire [7:0] uart_data;
    assign uart_data = (uart_cnt == 0) ? 8'hDE :
                       (uart_cnt == 1) ? 8'hAD :
                       (uart_cnt == 2) ? roll_est[15:8] :
                       (uart_cnt == 3) ? roll_est[7:0] :
                       (uart_cnt == 4) ? pitch_est[15:8] :
                       pitch_est[7:0];
"""
content = content.replace("    reg uart_start;\n", uart_mux + "    reg uart_start;\n")

# Remove register assignments for UART data
content = content.replace("""                        case (uart_cnt)
                            0: uart_data <= 8'hDE; // Header
                            1: uart_data <= 8'hAD;
                            2: uart_data <= roll_est[15:8];
                            3: uart_data <= roll_est[7:0];
                            4: uart_data <= pitch_est[15:8];
                            5: uart_data <= pitch_est[7:0];
                        endcase""", "")

with open('src/project.v', 'w') as f:
    f.write(content)
