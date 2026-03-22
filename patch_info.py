with open('info.yaml', 'r') as f:
    content = f.read()

content = content.replace("    - \"spi_read_reg_8.v\"\n", "")

with open('info.yaml', 'w') as f:
    f.write(content)
