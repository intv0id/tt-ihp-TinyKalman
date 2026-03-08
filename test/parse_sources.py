# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import sys

# Simple YAML parser to extract source files from info.yaml
# Avoids dependencies on external YAML libraries
def parse_sources(filename):
    try:
        with open(filename, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        return []

    in_source_files = False
    sources = []
    for line in lines:
        if line.strip().startswith('source_files:'):
            in_source_files = True
            continue
        if in_source_files:
            stripped = line.strip()
            if stripped.startswith('-'):
                # Remove the leading dash and any surrounding whitespace
                source = stripped[1:].strip()
                # Remove any trailing comments
                source = source.split('#')[0].strip()
                # Remove any surrounding quotes
                source = source.strip('"').strip("'")
                if source:
                    sources.append(source)
            elif not stripped or stripped.startswith('#'):
                continue
            elif line.startswith('  '): # Indented line
                if ':' in line and not stripped.startswith('-'):
                    # New key encountered
                    break
                continue
            else:
                # Out of indentation or new key at root level
                break
    return sources

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    print(" ".join(parse_sources(sys.argv[1])))
