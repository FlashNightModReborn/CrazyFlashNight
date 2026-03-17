#!/usr/bin/env bash
set -euo pipefail

TOOL_ROOT="$(cd "$(dirname "$0")" && pwd)"
ELECTRON_CACHE="${TMPDIR:-/tmp}/cf7-electron-full"
ELECTRON_ZIP="$ELECTRON_CACHE/electron.zip"
ELECTRON_MAIN="$TOOL_ROOT/packages/web/dist/electron/main.cjs"
RENDERER_HTML="$TOOL_ROOT/packages/web/dist/renderer/index.html"

# ── 检测平台与架构 ──
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin)
    case "$ARCH" in
      arm64) ELECTRON_PLATFORM="darwin-arm64" ;;
      *)     ELECTRON_PLATFORM="darwin-x64" ;;
    esac
    ELECTRON_DIR="$ELECTRON_CACHE/dist/Electron.app/Contents/MacOS"
    ELECTRON_EXE="$ELECTRON_DIR/Electron"
    ;;
  Linux)
    ELECTRON_PLATFORM="linux-x64"
    ELECTRON_DIR="$ELECTRON_CACHE/dist"
    ELECTRON_EXE="$ELECTRON_DIR/electron"
    ;;
  *)
    echo "[X] 不支持的操作系统: $OS（Windows 请使用 launch.bat）"
    exit 1
    ;;
esac

ELECTRON_VERSION="v33.4.0"
ELECTRON_URL="https://cdn.npmmirror.com/binaries/electron/${ELECTRON_VERSION}/electron-${ELECTRON_VERSION}-${ELECTRON_PLATFORM}.zip"

# ── 0. 检查 node_modules ──
if [ ! -d "$TOOL_ROOT/node_modules" ]; then
  echo "[!] 首次运行，安装依赖..."
  (cd "$TOOL_ROOT" && npm install)
  echo "[OK] 依赖安装完成。"
fi

# ── 1. 下载 Electron ──
if [ ! -f "$ELECTRON_EXE" ]; then
  echo "[!] Electron 未安装，正在下载..."
  echo "    平台: $ELECTRON_PLATFORM"
  echo "    来源: cdn.npmmirror.com"

  mkdir -p "$ELECTRON_CACHE"

  # 清理残留
  [ -f "$ELECTRON_ZIP" ] && rm -f "$ELECTRON_ZIP"
  [ -d "$ELECTRON_CACHE/dist" ] && rm -rf "$ELECTRON_CACHE/dist"

  echo "    下载中...（约 110MB）"
  # 对国内 CDN 绕过代理（代理会严重拖慢速度甚至中断）
  curl -L --noproxy cdn.npmmirror.com --progress-bar --retry 3 --retry-delay 5 -o "$ELECTRON_ZIP" "$ELECTRON_URL"

  if [ ! -f "$ELECTRON_ZIP" ]; then
    echo "[X] 下载失败，请检查网络后重试。"
    exit 1
  fi

  echo "    解压中..."
  mkdir -p "$ELECTRON_CACHE/dist"
  unzip -q "$ELECTRON_ZIP" -d "$ELECTRON_CACHE/dist"

  if [ ! -f "$ELECTRON_EXE" ]; then
    echo "[X] Electron 安装失败。"
    rm -f "$ELECTRON_ZIP"
    rm -rf "$ELECTRON_CACHE/dist"
    exit 1
  fi

  # macOS 需要去除隔离属性
  if [ "$OS" = "Darwin" ]; then
    xattr -cr "$ELECTRON_CACHE/dist/Electron.app" 2>/dev/null || true
  fi

  echo "[OK] Electron 已就绪。"
fi

# ── 2. 构建渲染器 ──
if [ ! -f "$RENDERER_HTML" ]; then
  echo "[!] 渲染器未构建，正在构建..."
  (cd "$TOOL_ROOT" && npx vite build packages/web)
fi

if [ ! -f "$RENDERER_HTML" ]; then
  echo "[X] 渲染器构建失败。"
  exit 1
fi

# ── 3. 构建主进程 ──
if [ ! -f "$ELECTRON_MAIN" ]; then
  echo "[!] 主进程未打包，正在构建..."
  (cd "$TOOL_ROOT" && npx esbuild packages/web/src/electron/main.ts \
    --bundle --platform=node --format=cjs \
    --outfile=packages/web/dist/electron/main.cjs \
    --external:electron \
    --banner:js="const __import_meta_url = require('url').pathToFileURL(__filename).href;" \
    --define:import.meta.url=__import_meta_url)
fi

if [ ! -f "$ELECTRON_MAIN" ]; then
  echo "[X] 主进程打包失败。"
  exit 1
fi

# ── 4. 复制 preload 脚本 ──
PRELOAD_SRC="$TOOL_ROOT/packages/web/src/electron/preload.js"
PRELOAD_DST="$TOOL_ROOT/packages/web/dist/electron/preload.js"
if [ -f "$PRELOAD_SRC" ] && [ ! -f "$PRELOAD_DST" ]; then
  cp "$PRELOAD_SRC" "$PRELOAD_DST"
fi

# ── 5. 启动 ──
echo "启动 CF7 发行打包工具..."
"$ELECTRON_EXE" "$ELECTRON_MAIN"
