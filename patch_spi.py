import re

for filename in ['src/spi_read_reg_16.v', 'src/spi_write_reg.v']:
    with open(filename, 'r') as f:
        content = f.read()

    content = content.replace("reg [15:0] timer;", "reg [9:0] timer;")

    with open(filename, 'w') as f:
        f.write(content)
