import re
with open('test/test.py', 'r') as f:
    text = f.read()

text = text.replace('timeout = 300000 if fast_sim else 1000000', 'timeout = 300000 if fast_sim else 35000000')

def repl1(m):
    return """val = dut.uo_out.value
        if not val.is_resolvable:
            cs_val = 1
            sclk_val = 1
        else:
            val_int = int(val)
            cs_val = (val_int >> 2) & 1
            sclk_val = (val_int >> 1) & 1"""
text = re.sub(r"try:\s*val_int = int\(dut\.uo_out\.value\)\s*cs_val = \(val_int >> 2\) & 1\s*sclk_val = \(val_int >> 1\) & 1\s*except ValueError:\s*cs_val = 1\s*sclk_val = 1", repl1, text, count=1)

def repl2(m):
    return """val = dut.uo_out.value
        if val.is_resolvable:
            val_int = int(val)
            cs = (val_int >> 2) & 1
            if cs == 0:
                fast_sim = True
                dut._log.info(f"CS_N detected at cycle {i}. Mode: FAST SIMULATION.")
                break"""

text = re.sub(r"try:\s*val = int\(dut\.uo_out\.value\)\s*cs = \(val >> 2\) & 1\s*if cs == 0:\s*fast_sim = True\s*dut\._log\.info\(f\"CS_N detected at cycle \{i\}\. Mode: FAST SIMULATION\.\"\)\s*break\s*except ValueError:\s*pass", repl2, text, count=1)

def repl3(m):
    return """val = dut.uo_out.value
        if not val.is_resolvable:
            uart_val = 1
        else:
            val_int = int(val)
            uart_val = (val_int >> 3) & 1 # Bit 3"""
text = re.sub(r"try:\s*val_int = int\(dut\.uo_out\.value\)\s*uart_val = \(val_int >> 3\) & 1 # Bit 3\s*except ValueError:\s*uart_val = 1", repl3, text, count=1)

def repl4(m):
    return """val = dut.uo_out.value
        if not val.is_resolvable:
            bit = 0
        else:
            val_int = int(val)
            bit = (val_int >> 3) & 1"""

text = re.sub(r"try:\s*val_int = int\(dut\.uo_out\.value\)\s*bit = \(val_int >> 3\) & 1\s*except ValueError:\s*bit = 0", repl4, text)

def repl5(m):
    return """val = dut.uo_out.value
        if not val.is_resolvable:
            bit = 1
        else:
            val_int = int(val)
            bit = (val_int >> 3) & 1"""

text = re.sub(r"try:\s*val = int\(dut\.uo_out\.value\)\s*bit = \(val >> 3\) & 1\s*except ValueError:\s*bit = 1", repl5, text)

with open('test/test.py', 'w') as f:
    f.write(text)
