#!/usr/bin/env bash
set -euo pipefail
set +B  # 禁用 brace expansion，防止路径中的 {version} 被展开

# CF7 SFX 自解压安装包构建脚本
# 用法: ./sfx/build-sfx.sh [--version NAME] [--pack-output DIR] [--unity-data DIR]

TOOL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SFX_DIR="$TOOL_ROOT/sfx"

# 内置 Unity _Data 资源路径（工具自带 Assembly-CSharp.dll）
BUILTIN_UNITY_DATA="$TOOL_ROOT/assets/CrazyFlasher7StandAloneStarter_Data"

# 优先从环境变量读取（Electron 用环境变量避免 Windows CreateProcess 转义问题）
# 命令行参数可覆盖
VERSION="${CF7_SFX_VERSION:-update}"
PACK_OUTPUT="${CF7_SFX_PACK_OUTPUT:-}"
UNITY_DATA="${CF7_SFX_UNITY_DATA:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)    VERSION="$2"; shift 2 ;;
    --pack-output) PACK_OUTPUT="$2"; shift 2 ;;
    --unity-data)  UNITY_DATA="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# 净化 VERSION：去除路径分隔符和 .. 防止目录穿越
VERSION="${VERSION//\//}"
VERSION="${VERSION//\\/}"
VERSION="${VERSION//../}"
if [ -z "$VERSION" ]; then
  VERSION="update"
fi

# 自动检测 pack output
if [ -z "$PACK_OUTPUT" ]; then
  # 找最新的 output 子目录
  PACK_OUTPUT=$(ls -dt "$TOOL_ROOT/output/"*/ 2>/dev/null | head -1)
  if [ -z "$PACK_OUTPUT" ]; then
    echo "[X] 未找到打包输出目录。请先运行 npm run pack 或指定 --pack-output。"
    exit 1
  fi
fi

# 未指定外部 Unity _Data 时，自动使用内置资源
if [ -z "$UNITY_DATA" ] && [ -d "$BUILTIN_UNITY_DATA" ]; then
  UNITY_DATA="$BUILTIN_UNITY_DATA"
fi

echo "=== CF7 SFX 构建 ==="
echo "  版本: $VERSION"
echo "  打包产物: $PACK_OUTPUT"
echo "  Unity 数据: ${UNITY_DATA:-（无）}"

# 临时组装目录
STAGING="$TOOL_ROOT/sfx-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/resources"

# 1. 复制打包产物 → resources/
echo "  复制打包产物..."
# cp -a 保留结构，用 /. 后缀避免花括号被 bash brace expansion
cp -a "$PACK_OUTPUT/." "$STAGING/resources/"

# 2. 复制 Unity _Data（如果提供）
if [ -n "$UNITY_DATA" ] && [ -d "$UNITY_DATA" ]; then
  echo "  复制 Unity 数据..."
  mkdir -p "$STAGING/CrazyFlasher7StandAloneStarter_Data"
  cp -r "$UNITY_DATA"/* "$STAGING/CrazyFlasher7StandAloneStarter_Data/"
fi

# 3. 复制安装脚本
# 检测平台决定安装脚本
BUILD_OS="$(uname -s)"
case "$BUILD_OS" in
  MINGW*|MSYS*|CYGWIN*)
    # 给 install.ps1 加 UTF-8 BOM（PowerShell 需要 BOM 才能正确识别 UTF-8）
    printf '\xef\xbb\xbf' > "$STAGING/install.ps1"
    cat "$SFX_DIR/install.ps1" >> "$STAGING/install.ps1"
    cp "$SFX_DIR/bootstrap.bat" "$STAGING/"
    BUILD_MODE="windows"
    ;;
  *)
    cp "$SFX_DIR/install-unix.sh" "$STAGING/"
    chmod +x "$STAGING/install-unix.sh"
    BUILD_MODE="unix"
    ;;
esac
echo "  构建模式: $BUILD_MODE"

# 4. 统计
FILE_COUNT=$(find "$STAGING" -type f | wc -l | tr -d ' ')
echo "  总文件数: $FILE_COUNT"

if [ "$BUILD_MODE" = "windows" ]; then
  # ── Windows: 7z SFX ──

  # 5. 定位 7z（优先 PATH，再 fallback 硬编码路径）
  SEVENZIP=""
  SFX_MODULE=""
  SEVENZIP=$(which 7z 2>/dev/null || true)
  if [ -n "$SEVENZIP" ]; then
    # 从 PATH 找到的 7z，尝试定位同目录下的 7z.sfx
    SFX_MODULE="$(dirname "$SEVENZIP")/7z.sfx"
    if [ ! -f "$SFX_MODULE" ]; then SFX_MODULE=""; fi
  else
    for base in "/c/Program Files/7-Zip" "/c/Program Files (x86)/7-Zip" \
                "C:/Program Files/7-Zip" "C:/Program Files (x86)/7-Zip"; do
      if [ -f "$base/7z.exe" ]; then
        SEVENZIP="$base/7z.exe"
        SFX_MODULE="$base/7z.sfx"
        break
      fi
    done
  fi
  if [ -z "$SEVENZIP" ]; then
    echo "[X] 未找到 7-Zip。请安装 7-Zip。"
    rm -rf "$STAGING"
    exit 1
  fi
  echo "  7z: $SEVENZIP"

  # 6. 压缩（带进度）
  OUTPUT_DIR="$TOOL_ROOT/output/CF7_${VERSION}"
  mkdir -p "$OUTPUT_DIR"
  ARCHIVE="$OUTPUT_DIR/data.7z"
  rm -f "$ARCHIVE"
  echo "  压缩中（这可能需要几分钟）..."
  (cd "$STAGING" && "$SEVENZIP" a -t7z -mx=5 -r -bsp1 "$ARCHIVE" .)

  # 6b. 如果 7z.sfx 模块存在，生成真正的单文件自解压 exe
  if [ -n "$SFX_MODULE" ] && [ -f "$SFX_MODULE" ]; then
    SFX_EXE="$OUTPUT_DIR/CF7_${VERSION}_Setup.exe"
    echo "  拼接 SFX 自解压包..."
    cat "$SFX_MODULE" "$SFX_DIR/sfx-config.txt" "$ARCHIVE" > "$SFX_EXE"
    echo "  SFX: $SFX_EXE"
  fi

  # 7. 生成安装 bat（用于无 SFX 模块时的 data.7z 分发）
  cat > "$OUTPUT_DIR/安装更新.bat" << 'BATEOF'
@echo off
chcp 65001 >nul 2>&1
title 闪客快打7 更新安装
echo.
echo  ===========================================
echo    闪客快打7重置计划 - 更新安装程序
echo  ===========================================
echo.

set "SCRIPT_DIR=%~dp0"
set "ARCHIVE=%SCRIPT_DIR%data.7z"
set "EXTRACT_DIR=%TEMP%\cf7-update-%RANDOM%"

if not exist "%ARCHIVE%" (
    echo [X] 找不到 data.7z，请确保安装更新.bat与data.7z在同一目录。
    echo.
    pause
    exit /b 1
)

REM 查找 7z
set "SEVENZIP="
if exist "C:\Program Files\7-Zip\7z.exe" set "SEVENZIP=C:\Program Files\7-Zip\7z.exe"
if exist "C:\Program Files (x86)\7-Zip\7z.exe" set "SEVENZIP=C:\Program Files (x86)\7-Zip\7z.exe"

if not defined SEVENZIP (
    echo [X] 未检测到 7-Zip。本安装包使用 7z 格式压缩，需要 7-Zip 解压。
    echo.
    echo     请安装 7-Zip 后重试:
    echo     https://www.7-zip.org/
    echo.
    pause
    exit /b 1
)

echo  正在解压更新文件...
echo.
"%SEVENZIP%" x "%ARCHIVE%" -o"%EXTRACT_DIR%" -y -bsp1
if errorlevel 1 (
    echo.
    echo [X] 解压失败。
    echo.
    pause
    exit /b 1
)
echo.

:run_install
if exist "%EXTRACT_DIR%\bootstrap.bat" (
    call "%EXTRACT_DIR%\bootstrap.bat"
) else if exist "%EXTRACT_DIR%\install.ps1" (
    powershell.exe -ExecutionPolicy Bypass -File "%EXTRACT_DIR%\install.ps1"
) else (
    echo [X] 解压目录中未找到安装脚本。
    echo     路径: %EXTRACT_DIR%
    echo.
    pause
    exit /b 1
)

REM 清理临时文件
echo.
echo  正在清理临时文件...
rmdir /s /q "%EXTRACT_DIR%" 2>nul
echo  清理完成。
echo.
pause
BATEOF

  # 转换 bat 为 CRLF 行尾
  sed -i 's/$/\r/' "$OUTPUT_DIR/安装更新.bat"
  echo "  输出: $OUTPUT_DIR/"
  OUTPUT_EXE="$OUTPUT_DIR"

else
  # ── Linux/macOS: makeself 或 tar.gz + shell wrapper ──

  OUTPUT_EXE="$TOOL_ROOT/output/CF7_${VERSION}.sh"
  mkdir -p "$(dirname "$OUTPUT_EXE")"

  MAKESELF=$(which makeself 2>/dev/null || true)
  if [ -n "$MAKESELF" ]; then
    echo "  使用 makeself 生成自解压脚本..."
    "$MAKESELF" --gzip "$STAGING" "$OUTPUT_EXE" "CF7 $VERSION Update" ./install-unix.sh
  else
    echo "  makeself 未安装，使用 tar + shell wrapper..."
    ARCHIVE="$TOOL_ROOT/sfx-staging.tar.gz"
    (cd "$STAGING" && tar czf "$ARCHIVE" .)

    cat > "$OUTPUT_EXE" << 'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
TMPDIR=$(mktemp -d)
ARCHIVE_START=$(awk '/^__ARCHIVE_BELOW__$/{print NR + 1; exit 0;}' "$0")
tail -n +"$ARCHIVE_START" "$0" | tar xzf - -C "$TMPDIR"
(cd "$TMPDIR" && bash install-unix.sh)
rm -rf "$TMPDIR"
exit 0
__ARCHIVE_BELOW__
WRAPPER
    cat "$ARCHIVE" >> "$OUTPUT_EXE"
    chmod +x "$OUTPUT_EXE"
    rm -f "$ARCHIVE"
  fi
fi

# 清理 staging
rm -rf "$STAGING"

OUTPUT_SIZE=$(du -sh "$OUTPUT_EXE" 2>/dev/null | cut -f1 || echo "?")
echo ""
echo "[OK] 构建完成: $OUTPUT_EXE ($OUTPUT_SIZE)"
