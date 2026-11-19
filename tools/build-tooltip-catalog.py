#!/usr/bin/env python3
"""Compatibility entry for existing release commands. All projections share the shipped compiler."""
from pathlib import Path
import subprocess
import sys

if __name__ == "__main__":
    sys.exit(subprocess.call(["node", str(Path(__file__).with_name("tooltip-catalog.cjs")), *sys.argv[1:]]))
