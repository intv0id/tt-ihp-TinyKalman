import re

with open('src/uart_tx.v', 'r') as f:
    content = f.read()

content = content.replace("reg [15:0] clk_cnt; // 16-bit to be safe for low baud rates", "reg [10:0] clk_cnt;")

with open('src/uart_tx.v', 'w') as f:
    f.write(content)
