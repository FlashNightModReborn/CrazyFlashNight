#!/usr/bin/env bash
set -euo pipefail

TOOL_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$TOOL_ROOT"

node scripts/ensure-runtime.mjs

ELECTRON_MAIN="$TOOL_ROOT/packages/web/dist/electron/main.cjs"
ELECTRON_BIN="$TOOL_ROOT/node_modules/.bin/electron"

if [ ! -f "$ELECTRON_BIN" ]; then
  echo "[X] 未找到 Electron 可执行入口，请重新运行 npm install。"
  exit 1
fi

if [ ! -f "$ELECTRON_MAIN" ]; then
  echo "[X] 主进程产物缺失，请检查构建日志。"
  exit 1
fi

echo "启动 CF7 发行打包工具..."
"$ELECTRON_BIN" "$ELECTRON_MAIN"
