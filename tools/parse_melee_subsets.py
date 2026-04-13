"""
parse_melee_subsets.py — extract subset metadata from 兵器攻击容器 1连招 XMLs.

# 用途
为 AttackAssetMeta.as 的 MELEE_META 段产出 subset 数据。AI 武器评估的
WeaponDpsEstimator 依据这些聚合量估算兵器 DPS；任何 1连招 资产改了
helper 调用次数 / 子弹威力公式 / 虚空刀 layer 子弹时，必须重跑此脚本。

# 何时重跑
- 改了 flashswf/arts/things0/LIBRARY/容器/兵器攻击容器/平A/兵器攻击容器-XXX1连招.xml
  里的 helper 调用、子弹威力公式 (空手力/N + 刀.power × M)、霰弹值、
  或虚空刀 DOMLayer 内的 onClipEvent(load) shoot
- 新增/删除 1连招 资产（同时更新 ASSETS 列表）

# 运行（在仓库根目录）
    python tools/parse_melee_subsets.py

# 输出
打印 15 条 `=== NAME (file.xml) ===` 块，每块含 0-2 个 subset 行，
格式直接对应 AttackAssetMeta.as 里 m["NAME"].subsets 数组的元素：
    { kind:"blade"|"direct", passiveScope:"weaponOnly"|"wholeBullet"|"none",
      effHitsWeapon:..., effHitsUnarmed:..., judgmentHitCount:..., bulletSpawnCount:... }

# 怎样把输出回写到 AttackAssetMeta.as
逐条复制对应 m["NAME"].subsets[i] 字段（effHits/Counts），
**不要动** totalFrames / stages / firstStageFrames（这些是人工估算，
parser 不解析 timeline 总帧数）。

# 解析规则（与 AttackAssetMeta.as 文件头注释保持同步）
- helper 函数定义 (`function XXX攻击(...){ ... 刀口位置生成子弹 ... }`)
  → kind="blade"，调用一次产 1 个 bullet（运行时再 × 刀_刀口数）
- helper 内 `子弹参数.子弹威力 += 刀.power × lvl × 0.075` → passiveScope="weaponOnly"
  helper 内 `子弹参数.子弹威力 *= 1 + lvl × 0.075` → passiveScope="wholeBullet"
- helper 调用前 7 行内匹配 `子弹威力 = 空手攻击力 / N + 刀属性.power [* M]`
  提取 unarmedDiv=N 和 weaponMult=M（缺省 1.0）
- 直接 `_root.子弹区域shoot传递(子弹属性)` (不在 helper 体内) → kind="direct"
  scope/split/formula 从同一 onClipEvent(load) 块内读
- 虚空刀 DOMLayer 是动画补充判定段（非派生触发），其内的 shoot 算 direct subset

# 编辑后排错
- 若某资产 helper 调用突然多/少了几个 spawnCount，先用
  grep -c "刀口位置生成子弹" 那份 xml 复核 helper 实际调用次数
- 若 effHitsUnarmed 出现 NaN 或 0，多半是 子弹威力 公式格式不匹配
  POWER_FORMULA 正则；新公式形态需要扩展该正则
"""
import re
import os, sys
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8")

ASSETS = ["1", "双刀", "直剑", "刀剑", "狂野", "短兵", "短柄", "迅捷",
          "棍棒", "重斩", "镰刀", "长刀", "长枪", "长柄", "长棍"]

# Resolve via glob to bypass Windows mbcs encoding issues
_HERE = Path(__file__).resolve().parent
BASE = (_HERE.parent / "flashswf" / "arts" / "things0" / "LIBRARY" / "容器"
        / "兵器攻击容器" / "平A")

# Pattern: 子弹威力 = 空手攻击力 / N + 刀属性.power [* M] [+ ...optional]
# Allow either 子弹威力 or 子弹属性.子弹威力 or 子弹参数.子弹威力
POWER_FORMULA = re.compile(
    r"(?:子弹(?:属性|参数)\.)?子弹威力\s*=\s*"
    r"(?:_parent\.)*(?:_parent\.)*空手攻击力\s*/\s*(\d+(?:\.\d+)?)"
    r"\s*\+\s*"
    r"(?:_parent\.)*(?:_parent\.)*刀属性\.power"
    r"(?:\s*\*\s*(\d+(?:\.\d+)?))?"
)

# Helper definition: function NAME(...) { ... }
# Anchor: not preceded by an identifier char, to avoid matching mid-token uses.
HELPER_DEF = re.compile(r"(?:^|[^A-Za-z0-9_])function\s+([\u4e00-\u9fff\w]+)\s*\(", re.MULTILINE)

# Inside helper body, look for: 子弹参数.霰弹值 = N;  (helper-default split)
HELPER_SPLIT = re.compile(r"子弹参数\.霰弹值\s*=\s*(\d+)")

# Inside helper body, look for passive scope:
#   weaponOnly: 子弹参数.子弹威力 += _parent.刀属性.power * ... * 0.075
#   wholeBullet: 子弹参数.子弹威力 *= 1 + ... * 0.075
HELPER_SCOPE_WEAPON_ONLY = re.compile(
    r"子弹参数\.子弹威力\s*\+=\s*[^;]*刀属性\.power[^;]*0\.075"
)
HELPER_SCOPE_WHOLE_BULLET = re.compile(
    r"子弹参数\.子弹威力\s*\*=\s*1\s*\+[^;]*0\.075"
)

# Helper invocation: NAME(arg1, arg2, ...) — only on non-definition lines.
# Direct spawn: _root.子弹区域shoot传递(子弹属性);
DIRECT_SHOOT = re.compile(r"_root\.子弹区域shoot传递\s*\(")

# Inside onClipEvent(load) blocks for direct shoot:
#   子弹属性.霰弹值 = N
#   子弹属性.子弹威力 = ... formula ...
#   passive scope: 子弹属性.子弹威力 += / *=
DIRECT_SPLIT = re.compile(r"子弹属性\.霰弹值\s*=\s*(\d+)")
DIRECT_SCOPE_WEAPON_ONLY = re.compile(
    r"子弹属性\.子弹威力\s*\+=\s*[^;]*刀属性\.power[^;]*0\.075"
)
DIRECT_SCOPE_WHOLE_BULLET = re.compile(
    r"子弹属性\.子弹威力\s*\*=\s*1\s*\+[^;]*0\.075"
)


def find_helper_bodies(text):
    """Return dict: helper_name -> (body_text, default_split, scope, is_blade)."""
    out = {}
    # Find each `function NAME(...)` and extract body until matching `}`.
    for m in HELPER_DEF.finditer(text):
        name = m.group(1)
        # Find body via brace matching from first `{` after the signature.
        i = text.find("{", m.end())
        if i < 0:
            continue
        depth = 0
        j = i
        while j < len(text):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = text[i:j+1]
        # Default split (if helper sets 子弹参数.霰弹值 itself)
        sm = HELPER_SPLIT.search(body)
        default_split = int(sm.group(1)) if sm else 1
        # Scope
        if HELPER_SCOPE_WHOLE_BULLET.search(body):
            scope = "wholeBullet"
        elif HELPER_SCOPE_WEAPON_ONLY.search(body):
            scope = "weaponOnly"
        else:
            scope = "none"
        # Is blade? (calls 刀口位置生成子弹)
        is_blade = "刀口位置生成子弹" in body
        out[name] = {
            "body": body,
            "default_split": default_split,
            "scope": scope,
            "is_blade": is_blade,
        }
    return out


def find_helper_calls(text, helpers):
    """Yield (helper_name, line_no, formula_match) for each helper invocation outside the def."""
    lines = text.split("\n")
    # Build set of definition line numbers to skip
    def_lines = set()
    for m in HELPER_DEF.finditer(text):
        def_lines.add(text[:m.start()].count("\n") + 1)
    for ln_idx, line in enumerate(lines, 1):
        if ln_idx in def_lines:
            continue
        for name in helpers:
            # Match name(... but not function name(
            if re.search(rf"(?<!function ){re.escape(name)}\s*\(", line):
                # Look upward (within ~6 lines) for the most recent power formula
                formula = None
                for back in range(ln_idx - 1, max(0, ln_idx - 8), -1):
                    fm = POWER_FORMULA.search(lines[back - 1])
                    if fm:
                        formula = fm
                        break
                yield (name, ln_idx, formula)
                break  # one helper per line


def find_direct_shoots(text):
    """For each _root.子弹区域shoot传递, walk back to find onClipEvent block and extract split/scope/formula."""
    lines = text.split("\n")
    results = []
    for ln_idx, line in enumerate(lines, 1):
        if "_root.子弹区域shoot传递" not in line:
            continue
        # Walk back to find the enclosing onClipEvent(load){ scope (~120 lines)
        block_start = max(0, ln_idx - 120)
        block = "\n".join(lines[block_start:ln_idx])
        # Skip if inside helper function (heuristic: check if a `function XXX(` appears
        # between block_start and ln_idx without a closing balance).
        # Simpler: count `function ` definitions; if any, check if its `}` came before us.
        # Robust approach: assume direct shoots are NOT inside helper bodies (already handled).
        # We rely on later split-by-helper to confirm.
        sm = DIRECT_SPLIT.search(block)
        split = int(sm.group(1)) if sm else 1
        if DIRECT_SCOPE_WHOLE_BULLET.search(block):
            scope = "wholeBullet"
        elif DIRECT_SCOPE_WEAPON_ONLY.search(block):
            scope = "weaponOnly"
        else:
            scope = "none"
        fm = POWER_FORMULA.search(block)
        unarmed_div = float(fm.group(1)) if fm else 5.0
        weapon_mult = float(fm.group(2)) if (fm and fm.group(2)) else 1.0
        results.append({
            "line": ln_idx,
            "split": split,
            "scope": scope,
            "unarmedDiv": unarmed_div,
            "weaponMult": weapon_mult,
        })
    return results


def is_in_helper(text, line_no, helper_def_ranges):
    """Check if line_no falls inside any helper body."""
    return any(s <= line_no <= e for (s, e) in helper_def_ranges)


def find_helper_ranges(text):
    """Return list of (start_line, end_line) for each helper body."""
    ranges = []
    for m in HELPER_DEF.finditer(text):
        start_line = text[:m.start()].count("\n") + 1
        i = text.find("{", m.end())
        if i < 0:
            continue
        depth = 0
        j = i
        while j < len(text):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        end_line = text[:j].count("\n") + 1
        ranges.append((start_line, end_line))
    return ranges


def aggregate(asset_name, text):
    helpers = find_helper_bodies(text)
    helper_ranges = find_helper_ranges(text)

    # Bucket: (kind, scope) -> {effHitsWeapon, effHitsUnarmed, judgmentHitCount, bulletSpawnCount}
    buckets = {}

    def bump(kind, scope, weapon_mult, unarmed_div, split):
        key = (kind, scope)
        b = buckets.setdefault(key, {
            "effHitsWeapon": 0.0,
            "effHitsUnarmed": 0.0,
            "judgmentHitCount": 0,
            "bulletSpawnCount": 0,
        })
        b["effHitsWeapon"] += weapon_mult * split
        b["effHitsUnarmed"] += split / unarmed_div
        b["judgmentHitCount"] += split
        b["bulletSpawnCount"] += 1

    # 1. Helper calls (blade path)
    for name, ln, formula in find_helper_calls(text, helpers):
        h = helpers[name]
        if not h["is_blade"]:
            continue  # non-blade helper → unhandled; skip
        if formula is None:
            unarmed_div, weapon_mult = 5.0, 1.0  # safe defaults
        else:
            unarmed_div = float(formula.group(1))
            weapon_mult = float(formula.group(2)) if formula.group(2) else 1.0
        split = h["default_split"]
        bump("blade", h["scope"], weapon_mult, unarmed_div, split)

    # 2. Direct shoots (NOT inside helper bodies)
    for ds in find_direct_shoots(text):
        if is_in_helper(text, ds["line"], helper_ranges):
            continue  # belongs to helper body, not a real direct subset
        bump("direct", ds["scope"], ds["weaponMult"], ds["unarmedDiv"], ds["split"])

    return buckets


def fmt_subset(kind, scope, b):
    return ('{ kind:"%s", passiveScope:"%s", '
            'effHitsWeapon:%.4f, effHitsUnarmed:%.4f, '
            'judgmentHitCount:%d, bulletSpawnCount:%d }') % (
        kind, scope,
        b["effHitsWeapon"], b["effHitsUnarmed"],
        b["judgmentHitCount"], b["bulletSpawnCount"])


def main():
    print("# Auto-generated melee subsets (raw aggregation)\n")
    # Build name -> path map by enumerating BASE
    by_name = {}
    for entry in BASE.iterdir():
        n = entry.name
        if not n.endswith("1连招.xml"):
            continue
        # 兵器攻击容器-XXX1连招.xml -> XXX (or "" for the unnamed baseline 1连招)
        stem = n[len("兵器攻击容器-"):-len("1连招.xml")]
        by_name[stem] = entry
    for name in ASSETS:
        # Special: "1" resolves to bare "1连招.xml" with stem ""
        key = "" if name == "1" else name
        path = by_name.get(key)
        if path is None:
            print(f'# MISSING: {name} (looked for stem={key!r})')
            continue
        text = path.read_text(encoding="utf-8")
        buckets = aggregate(name, text)
        print(f'=== {name} ({path.name}) ===')
        if not buckets:
            print("    (no subsets found)")
        for (kind, scope), b in sorted(buckets.items()):
            print("    " + fmt_subset(kind, scope, b))
        print()


if __name__ == "__main__":
    main()
