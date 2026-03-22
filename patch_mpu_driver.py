import re

with open('src/mpu_driver.v', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if "spi_read_reg_8 spi_read8_inst" in line:
        skip = True

    if skip and ");" in line:
        skip = False
        continue

    if not skip:
        new_lines.append(line)

content = "".join(new_lines)

# Remove read8 declarations
content = re.sub(r'    reg         read8_start;\n    reg  \[7:0\]  read8_addr;\n    wire \[7:0\]  read8_data;\n    wire        read8_busy;\n    wire        read8_done;\n    wire        read8_spi_start;\n    wire \[7:0\]  read8_spi_data_in;\n    wire        read8_spi_cs_n;\n', '', content)

# Fix muxing
content = content.replace("    wire active_read8 = read8_busy || read8_start;\n", "")
content = content.replace("assign spi_start   = active_write ? write_spi_start   : (active_read ? read_spi_start   : (active_read8 ? read8_spi_start : 1'b0));", "assign spi_start   = active_write ? write_spi_start   : (active_read ? read_spi_start   : 1'b0);")
content = content.replace("assign spi_data_in = active_write ? write_spi_data_in : (active_read ? read_spi_data_in : (active_read8 ? read8_spi_data_in : 8'h00));", "assign spi_data_in = active_write ? write_spi_data_in : (active_read ? read_spi_data_in : 8'h00);")
content = content.replace("assign spi_cs_n    = active_write ? write_spi_cs_n    : (active_read ? read_spi_cs_n    : (active_read8 ? read8_spi_cs_n : 1'b1));", "assign spi_cs_n    = active_write ? write_spi_cs_n    : (active_read ? read_spi_cs_n    : 1'b1);")

# Update logic
content = content.replace("            read8_start <= 0;\n", "")
content = content.replace("            read8_addr  <= 0;\n", "")
content = content.replace("""                S_CHECK_WHOAMI: begin
                    read8_addr  <= MPU_WHO_AM_I;
                    read8_start <= 1;
                    state       <= S_CHECK_WAIT;
                end

                S_CHECK_WAIT: begin
                    if (read8_done) begin
                        if (read8_data == 8'h70) begin""", """                S_CHECK_WHOAMI: begin
                    read_addr  <= MPU_WHO_AM_I;
                    read_start <= 1;
                    state       <= S_CHECK_WAIT;
                end

                S_CHECK_WAIT: begin
                    if (read_done) begin
                        if (read_data[15:8] == 8'h70) begin""")

with open('src/mpu_driver.v', 'w') as f:
    f.write(content)
