#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

if __name__ == "__main__":
    sys.exit(subprocess.call(["node", "--test", str(Path(__file__).with_name("test-tooltip-catalog.cjs"))]))
