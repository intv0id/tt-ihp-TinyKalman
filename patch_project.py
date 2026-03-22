import re

with open('src/project.v', 'r') as f:
    content = f.read()

content = content.replace("        .gyro_z(),\n", "")

with open('src/project.v', 'w') as f:
    f.write(content)
