with open('test/Makefile', 'r') as f:
    content = f.read()

content = content.replace(" spi_read_reg_8.v", "")

with open('test/Makefile', 'w') as f:
    f.write(content)
