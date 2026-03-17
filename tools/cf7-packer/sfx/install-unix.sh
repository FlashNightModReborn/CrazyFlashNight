#!/usr/bin/env bash
set -euo pipefail

# CF7 更新安装脚本 (Linux/macOS)

STEAM_APP_ID="2402310"
GAME_DIR_NAME="CRAZYFLASHER7StandAloneStarter"

echo ""
echo "  ==========================================="
echo "    闪客快打7重置计划 - 更新安装程序"
echo "  ==========================================="
echo ""

# ── 定位 Steam 库 ──
find_game_path() {
  local libraries=()

  # 常见 Steam 安装路径
  local candidates=(
    "$HOME/.steam/steam"
    "$HOME/.local/share/Steam"
    "$HOME/Library/Application Support/Steam"  # macOS
    "/opt/steam"
  )

  for dir in "${candidates[@]}"; do
    if [ -d "$dir" ]; then
      libraries+=("$dir")
      # 解析 libraryfolders.vdf
      local vdf="$dir/steamapps/libraryfolders.vdf"
      if [ -f "$vdf" ]; then
        while IFS= read -r line; do
          if [[ "$line" =~ \"path\"[[:space:]]+\"(.+)\" ]]; then
            local lib="${BASH_REMATCH[1]}"
            lib="${lib//\\\\/\/}"
            [ "$lib" != "$dir" ] && libraries+=("$lib")
          fi
        done < "$vdf"
      fi
    fi
  done

  for lib in "${libraries[@]}"; do
    local manifest="$lib/steamapps/appmanifest_$STEAM_APP_ID.acf"
    if [ -f "$manifest" ]; then
      local gamePath="$lib/steamapps/common/$GAME_DIR_NAME"
      if [ -d "$gamePath" ]; then
        echo "$gamePath"
        return 0
      fi
    fi
  done
  return 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAME_PATH=""

echo "  扫描 Steam 库..."
GAME_PATH=$(find_game_path) || true

if [ -z "$GAME_PATH" ]; then
  echo "  未能自动找到游戏目录。"
  echo ""
  read -r -p "  请输入 $GAME_DIR_NAME 的完整路径: " GAME_PATH
  if [ -z "$GAME_PATH" ] || [ ! -d "$GAME_PATH" ]; then
    echo "  [X] 路径无效，已取消。"
    exit 1
  fi
fi

echo "  找到游戏目录: $GAME_PATH"

# ── 验证 ──
if [ ! -d "$GAME_PATH/resources" ]; then
  echo "  [!] 目录中未找到 resources/"
  read -r -p "  仍然继续？(y/N) " confirm
  [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && exit 1
fi

# ── 确认 ──
echo ""
echo "  即将更新: $GAME_PATH"
read -r -p "  确认开始？(Y/n) " confirm
[ "$confirm" = "n" ] || [ "$confirm" = "N" ] && exit 1

# ── 安装 ──
if [ -d "$SCRIPT_DIR/resources" ]; then
  echo "  正在更新 resources/ ..."
  cp -rf "$SCRIPT_DIR/resources/"* "$GAME_PATH/resources/"
  echo "  resources/ 更新完成"
fi

if [ -d "$SCRIPT_DIR/CrazyFlasher7StandAloneStarter_Data" ]; then
  echo "  正在更新 _Data/ ..."
  cp -rf "$SCRIPT_DIR/CrazyFlasher7StandAloneStarter_Data/"* "$GAME_PATH/CrazyFlasher7StandAloneStarter_Data/"
  echo "  _Data/ 更新完成"
fi

echo ""
echo "  [OK] 安装完成！"
echo ""
