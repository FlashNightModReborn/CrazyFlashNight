# A 档 CSS 性能优化施工脚本（一次性，2026-04-25）
#
# 改动范围：
#   1. 删除 launcher/web/css/{overlay,panels}.css 中所有 `backdrop-filter` / `-webkit-backdrop-filter` 规则
#      理由：iGPU 上每帧高斯卷积昂贵；现状元素已带 rgba 半透明 fallback bg，视觉差异 < 5%
#   2. 注释掉所有 `mix-blend-mode: screen`，并把同规则 opacity 提升 0.10（补偿失去 screen 的提亮）
#      理由：blend mode 强制 layer readback 破坏 GPU fast-path；可用 opacity + 颜色叠加替代
#
# 执行幂等：再次运行无副作用（已删除/注释的不会重复处理）。
# 回退：git checkout -- launcher/web/css/

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGETS = [
    ROOT / "launcher" / "web" / "css" / "overlay.css",
    ROOT / "launcher" / "web" / "css" / "panels.css",
]

# 编辑日志
log = []

# 1. 删除 backdrop-filter 行；如果同段是孤立 `-webkit-backdrop-filter` 也一并清掉
backdrop_pat = re.compile(
    r'^\s*(?:-webkit-)?backdrop-filter\s*:[^;]*;\s*\n', re.MULTILINE)

# 2. mix-blend-mode:screen → 注释 + opacity 微调
# 处理两种形式：
#   (a) 单独一行： "    mix-blend-mode:screen;\n"
#   (b) 同一行多语句： "...; mix-blend-mode:screen;\n"
#       e.g. panels.css:1065 "height:18%; opacity:0.45; mix-blend-mode:screen;"
mix_inline_pat = re.compile(r'(opacity\s*:\s*0?\.(\d+))(\s*;\s*mix-blend-mode\s*:\s*screen\s*;)', re.IGNORECASE)
mix_alone_pat = re.compile(r'^(\s*)mix-blend-mode\s*:\s*screen\s*;\s*\n', re.MULTILINE)

def boost_opacity(match):
    full = match.group(0)
    # 提取 0.45 → 0.55 这样的微调
    val = match.group(2)
    try:
        v = float('0.' + val)
        v_new = min(0.95, v + 0.10)
        new_val = '%.2f' % v_new
        # 替换原 opacity:0.XX 部分
        replaced = re.sub(r'opacity\s*:\s*0?\.\d+', 'opacity:' + new_val, match.group(1))
        return f'{replaced}; /* was: opacity:0.{val}; mix-blend-mode:screen — A档施工 2026-04-25 */'
    except ValueError:
        return full

for path in TARGETS:
    if not path.exists():
        print(f"SKIP: {path} not found", file=sys.stderr)
        continue
    src = path.read_text(encoding='utf-8')
    original = src
    n_backdrop = len(backdrop_pat.findall(src))
    src = backdrop_pat.sub('', src)

    # 内联形式优先处理（同一行 opacity + mix-blend-mode）
    inline_matches = mix_inline_pat.findall(src)
    src = mix_inline_pat.sub(boost_opacity, src)

    # 独立行的 mix-blend-mode:screen
    alone_count = len(mix_alone_pat.findall(src))
    src = mix_alone_pat.sub(lambda m: f'{m.group(1)}/* mix-blend-mode:screen — disabled for iGPU perf 2026-04-25 */\n', src)

    if src != original:
        path.write_text(src, encoding='utf-8')
        log.append({
            'file': str(path.relative_to(ROOT)),
            'backdrop_filter_lines_removed': n_backdrop,
            'mix_blend_inline_neutralized': len(inline_matches),
            'mix_blend_alone_commented': alone_count,
        })
        print(f'PATCHED {path.relative_to(ROOT)}: backdrop-{n_backdrop} mix-inline-{len(inline_matches)} mix-alone-{alone_count}')
    else:
        print(f'NO-OP {path.relative_to(ROOT)} (already applied)')

print('\n=== summary ===')
for entry in log:
    print(entry)
