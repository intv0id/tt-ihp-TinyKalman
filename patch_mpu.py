import re

with open('src/mpu_driver.v', 'r') as f:
    content = f.read()

content = content.replace("reg [31:0] timer;", "reg [20:0] timer;")
content = content.replace("wire [31:0] delay_100ms = INIT_WAIT_100MS;", "wire [20:0] delay_100ms = INIT_WAIT_100MS;")
content = content.replace("wire [31:0] delay_200ms = INIT_WAIT_200MS;", "wire [20:0] delay_200ms = INIT_WAIT_200MS;")
content = content.replace("wire [31:0] delay_between_reads = 20;", "wire [20:0] delay_between_reads = 20;")

with open('src/mpu_driver.v', 'w') as f:
    f.write(content)
