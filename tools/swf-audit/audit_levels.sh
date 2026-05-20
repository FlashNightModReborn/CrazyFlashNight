#!/usr/bin/env bash
# 审计 flashswf/levels 各地图：是否有名为"背景"的实例（决定能否被 贴背景图 烤进位图）
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"   # 仓库根 = tools/swf-audit/ 上两级
LEVELS="$ROOT/flashswf/levels"
WORK="$ROOT/tmp/bg-audit"
EXTRACT="$WORK/extract"
rm -rf "$EXTRACT"; mkdir -p "$EXTRACT"

# 判断一个 DOMSymbolInstance 行里的实例名（name 属性，区分大小写，排除 libraryItemName）
inst_has() {  # $1 = dir, $2 = instance name
  grep -rlE "DOMSymbolInstance[^>]*[^a-zA-Z]name=\"$2\"" "$1" 2>/dev/null
}

printf "%-26s | %-6s | %-9s | %-9s | %s\n" "地图" "来源" "背景实例" "deadbody" "判定"
printf -- "---------------------------------------------------------------------------------------\n"

for swf in "$LEVELS"/*.swf; do
  base=$(basename "$swf" .swf)
  src=""; kind=""
  if [ -d "$LEVELS/$base" ]; then
    src="$LEVELS/$base"; kind="DIR"
  elif [ -f "$LEVELS/$base.fla" ]; then
    src="$EXTRACT/$base"; kind="FLA"
    mkdir -p "$src"
    unzip -oq "$LEVELS/$base.fla" "DOMDocument.xml" "LIBRARY/*" -d "$src" 2>/dev/null
  else
    kind="SWF"
    # ffdec 反编译为 xfl
    src="$EXTRACT/$base"
    mkdir -p "$src"
    "$ROOT/tools/ffdec/ffdec.bat" -format "xfl" -export "all" "$src" "$swf" >/dev/null 2>&1
  fi

  bgfiles=$(inst_has "$src" "背景")
  ddfiles=$(inst_has "$src" "deadbody")
  bglayer=$(grep -rlE "DOMLayer name=\"背景\"" "$src" 2>/dev/null | head -1)

  has_bg="无"; [ -n "$bgfiles" ] && has_bg="有"
  has_dd="无"; [ -n "$ddfiles" ] && has_dd="有"

  # 判定：deadbody 所在符号文件里是否同时含背景实例
  verdict="?"
  if [ -n "$ddfiles" ] && [ -n "$bgfiles" ]; then
    same=""
    for f in $ddfiles; do
      for g in $bgfiles; do [ "$f" = "$g" ] && same="$f"; done
    done
    if [ -n "$same" ]; then verdict="就绪(同符号)"; else verdict="背景实例存在但不同符号-需查"; fi
  elif [ -n "$ddfiles" ] && [ -z "$bgfiles" ]; then
    if [ -n "$bglayer" ]; then verdict="需施工(有背景图层无实例)"; else verdict="需施工(无背景)"; fi
  elif [ -z "$ddfiles" ]; then
    verdict="非标准结构-需查"
  fi

  printf "%-26s | %-6s | %-9s | %-9s | %s\n" "$base" "$kind" "$has_bg" "$has_dd" "$verdict"
done
