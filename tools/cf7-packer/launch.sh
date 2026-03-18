#!/usr/bin/env bash
set -euo pipefail

TOOL_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$TOOL_ROOT"

ELECTRON_VER="35.7.5"
ELECTRON_MAIN="$TOOL_ROOT/packages/web/dist/electron/main.cjs"

# 平台检测
case "$(uname -s)" in
  Darwin*)
    if [ "$(uname -m)" = "arm64" ]; then
      PLATFORM="darwin-arm64"
    else
      PLATFORM="darwin-x64"
    fi
    ELECTRON_BIN_NAME="Electron.app/Contents/MacOS/Electron"
    ;;
  *)
    PLATFORM="linux-x64"
    ELECTRON_BIN_NAME="electron"
    ;;
esac

CACHE_DIR="${TMPDIR:-/tmp}/cf7-electron-v${ELECTRON_VER}"
CACHE_EXE="$CACHE_DIR/dist/$ELECTRON_BIN_NAME"
NPM_EXE="$TOOL_ROOT/node_modules/electron/dist/$ELECTRON_BIN_NAME"
MIRROR_URL="https://cdn.npmmirror.com/binaries/electron/v${ELECTRON_VER}/electron-v${ELECTRON_VER}-${PLATFORM}.zip"
GITHUB_URL="https://github.com/electron/electron/releases/download/v${ELECTRON_VER}/electron-v${ELECTRON_VER}-${PLATFORM}.zip"

# ═══ 阶段 1: npm 依赖 + 构建产物 ═══
node scripts/ensure-runtime.mjs

# ═══ 阶段 2: 探测 Electron 二进制 ═══
ELECTRON_EXE=""
ELECTRON_DIST=""

if [ -f "$CACHE_EXE" ]; then
  echo "[OK] Electron: TEMP 缓存"
  ELECTRON_EXE="$CACHE_EXE"
  ELECTRON_DIST="$CACHE_DIR/dist"
elif [ -f "$NPM_EXE" ]; then
  echo "[OK] Electron: node_modules"
  ELECTRON_EXE="$NPM_EXE"
  ELECTRON_DIST="$TOOL_ROOT/node_modules/electron/dist"
else
  # ═══ 阶段 3: 下载 ═══
  echo "[!] 未找到 Electron v${ELECTRON_VER}，开始下载..."
  mkdir -p "$CACHE_DIR"
  ZIP_PATH="$CACHE_DIR/electron.zip"

  download_ok=false

  # 策略 1: curl + 镜像
  if [ "$download_ok" = false ] && command -v curl &>/dev/null; then
    echo "    [1/4] curl + npmmirror 镜像..."
    if curl -fSL --connect-timeout 15 --max-time 300 --retry 2 -o "$ZIP_PATH" "$MIRROR_URL" 2>/dev/null; then
      download_ok=true
    else
      rm -f "$ZIP_PATH"
    fi
  fi

  # 策略 2: curl + GitHub
  if [ "$download_ok" = false ] && command -v curl &>/dev/null; then
    echo "    [2/4] curl + GitHub..."
    if curl -fSL --connect-timeout 15 --max-time 300 --retry 2 -o "$ZIP_PATH" "$GITHUB_URL" 2>/dev/null; then
      download_ok=true
    else
      rm -f "$ZIP_PATH"
    fi
  fi

  # 策略 3: wget + 镜像
  if [ "$download_ok" = false ] && command -v wget &>/dev/null; then
    echo "    [3/4] wget + npmmirror 镜像..."
    if wget -q --timeout=15 --tries=2 -O "$ZIP_PATH" "$MIRROR_URL" 2>/dev/null; then
      download_ok=true
    else
      rm -f "$ZIP_PATH"
    fi
  fi

  # 策略 4: node install.js（配合 .npmrc 镜像设置）
  if [ "$download_ok" = false ]; then
    INSTALL_JS="$TOOL_ROOT/node_modules/electron/install.js"
    if [ -f "$INSTALL_JS" ]; then
      echo "    [4/4] node electron/install.js..."
      # 清除代理环境变量，让 .npmrc 的 electron_mirror 生效
      env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY \
        node "$INSTALL_JS" 2>/dev/null && true
      if [ -f "$NPM_EXE" ]; then
        ELECTRON_EXE="$NPM_EXE"
        ELECTRON_DIST="$TOOL_ROOT/node_modules/electron/dist"
      fi
    fi
  fi

  # 从 zip 解压
  if [ "$download_ok" = true ] && [ -f "$ZIP_PATH" ]; then
    echo "    解压中..."
    mkdir -p "$CACHE_DIR/dist"
    unzip -qo "$ZIP_PATH" -d "$CACHE_DIR/dist"
    if [ -f "$CACHE_EXE" ]; then
      chmod +x "$CACHE_EXE"
      ELECTRON_EXE="$CACHE_EXE"
      ELECTRON_DIST="$CACHE_DIR/dist"
      echo "[OK] Electron v${ELECTRON_VER} 已就绪。"
    else
      rm -f "$ZIP_PATH"
    fi
  fi

  # 所有策略耗尽
  if [ -z "$ELECTRON_EXE" ]; then
    echo ""
    echo "[X] 所有下载方式均失败。"
    echo ""
    echo "    请手动下载以下任一链接:"
    echo "      镜像: $MIRROR_URL"
    echo "      官方: $GITHUB_URL"
    echo ""
    echo "    下载后解压到:"
    echo "      $CACHE_DIR/dist/"
    echo ""
    echo "    然后重新运行 ./launch.sh"
    exit 1
  fi
fi

# ═══ 阶段 4: 启动 ═══
if [ ! -f "$ELECTRON_MAIN" ]; then
  echo "[X] 主进程产物缺失: $ELECTRON_MAIN"
  exit 1
fi

export ELECTRON_OVERRIDE_DIST_PATH="$ELECTRON_DIST"
unset ELECTRON_RUN_AS_NODE 2>/dev/null || true

echo "启动 CF7 发行打包工具..."
"$ELECTRON_EXE" "$ELECTRON_MAIN"
