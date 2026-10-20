"""Compatibility entry; the shared portrait pipeline owns this effect."""
from pathlib import Path
import runpy
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
pipeline = runpy.run_path(str(ROOT / "tools/build-dialogue-portrait-postprocess.py"))
if __name__ == "__main__":
    pipeline["build"]("前治安官（无线电）", "--check" in sys.argv)
