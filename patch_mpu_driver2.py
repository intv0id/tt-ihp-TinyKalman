import re

with open('src/mpu_driver.v', 'r') as f:
    content = f.read()

content = content.replace("    output reg  signed [15:0] gyro_z,\n", "")
content = content.replace("            gyro_z      <= 0;\n", "")
content = content.replace("                            5: gyro_z  <= read_data;\n", "")
content = content.replace("wire [7:0] REG_ADDRS [0:5];", "wire [7:0] REG_ADDRS [0:4];")
content = content.replace("assign REG_ADDRS[5] = 8'h47; // GYRO_ZOUT_H\n", "")
content = content.replace("                        if (read_idx == 5) begin", "                        if (read_idx == 4) begin")

with open('src/mpu_driver.v', 'w') as f:
    f.write(content)
