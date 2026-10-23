#!/usr/bin/env python3
"""Convert an authored SVG into a map XFL skeleton, then stop before CS6 publish."""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONVERTER = ROOT / "tools" / "tesla-map-assets" / "native_vector" / "svg_to_xfl_legacy.py"
PUBLISH_TEMPLATE = ROOT / "flashswf" / "backgrounds" / "gk1_4_BG" / "PublishSettings.xml"
SCRIPT = "_root.贴背景图();"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("svg")
    ap.add_argument("out_dir")
    ap.add_argument("--name", required=True)
    args = ap.parse_args()

    svg = Path(args.svg)
    out = Path(args.out_dir)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    report = subprocess.check_output([
        sys.executable, "-X", "utf8", "-B", str(CONVERTER),
        str(svg), str(out), "--name", args.name,
    ], cwd=ROOT)
    print(report.decode("utf-8", "replace").strip())

    dom_path = out / "DOMDocument.xml"
    dom = dom_path.read_text(encoding="utf-8")
    dom = dom.replace('frameRate="24"', 'frameRate="30"')
    if SCRIPT not in dom:
        # Insert the frame script into the background-bake layer only.
        pattern = re.compile(
            r'(<DOMLayer name="background-bake"[^>]*>\s*<frames>\s*<DOMFrame[^>]*>)(.*?)(</DOMFrame>)',
            re.S,
        )
        m = pattern.search(dom)
        if not m:
            raise SystemExit('background-bake layer not found; author a top-level <g id="background-bake">')
        body = m.group(2)
        script = f"\n              <Actionscript>\n                <script><![CDATA[{SCRIPT}]]></script>\n              </Actionscript>"
        dom = dom[:m.start(2)] + body + script + dom[m.end(2):]
    dom_path.write_text(dom, encoding="utf-8")
    ET.parse(dom_path)

    publish = PUBLISH_TEMPLATE.read_text(encoding="utf-8")
    publish = publish.replace("gk1_4_BG.swf", f"../{args.name}.swf")
    (out / "PublishSettings.xml").write_text(publish, encoding="utf-8")

    swf = out.parent / f"{args.name}.swf"
    print(json.dumps({
        "xfl": str(out / f"{args.name}.xfl"),
        "swf": str(swf),
        "compile": f"powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target '{out / (args.name + '.xfl')}' -PublishOnly -VerifySwf '{swf}' -TimeoutSeconds 240",
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
