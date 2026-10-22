"""独立 CF6 教学关生成入口（r10 起）：委托 tools/cf6-tutorial/assemble.py。

r9 占位实现（借用 gk1_1_BG.swf 练习场背景 + 两只 2 级僵尸）已被用户明确判定不合格，
原件与现行 tutorial 产物归档在 tools/cf6-tutorial/archive/r9-placeholder/（含 SHA-256）。
本入口不再写 generated/tutorial-map.json / tutorial.manifest.json；新产物为
flashswf/backgrounds/cf6/CF6_Tutorial_BG/ 原生 XFL 源和 tools/cf6-tutorial/ 下的
环境片段、地图片段与 provenance manifest。只装配源，不调用 CS6、不生成 SWF。

    python -X utf8 -B tools/cf6-map-runtime/build-tutorial.py
    python -X utf8 -B tools/cf6-map-runtime/build-tutorial.py --check
"""
from pathlib import Path
import importlib.util
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "cf6_tutorial_assemble", ROOT / "tools/cf6-tutorial/assemble.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

if __name__ == "__main__":
    sys.exit(module.main())
