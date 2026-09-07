#!/usr/bin/env python3
"""Retired publisher: map pictures must enter the shared C# candidate workflow."""
import sys

message = "旧地图头像发布器已退役，不再覆写生产 JS。请打开地图内容工作台 → 素材库 / 导入 → 从发布元件提取；按真实元件与源摘要生成候选，再统一应用。"
print(message)
raise SystemExit(0 if any(arg in ("--help", "-h") for arg in sys.argv[1:]) else 2)
