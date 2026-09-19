"""钛合金61式防具加权标定复算（离线，只读生产数据，不写物品/存档/AS2/SWF）。

标定结论（2026-09-19，issue #62，经济权威确认）：
  数值模型 M=3（K点购买1层 + 高价1层 + 40级以上浮动1层；该套装无合成获取路径）；
  价格模型 E=1（高价1层），G=1，H=1；
  金币价沿用公式值 187200 的整十万取整 200000（+6.8%）；K点实售 6000 ≈ 公式 6075（-1.2%）。

公式来源（最高权威工作簿，防具/装备价格页；防具公式族已注册（records/armor-balance-plan.xml
为唯一人工源），本脚本保留为独立复算 oracle，不生成也不手工维护 runtime <balance>）：
  平衡总分 P = lv*20 + weight*10；加权总分 Q = P * 1.25^M
  当前总分 O = 防御*2 + 半额(HP) + 半额(MP) + 半额(伤害*3+刀枪*3) + 刀枪超额 + 半额(空手*4) + 法抗合计
    半额(v) = v（v < Q*0.5）否则 v + 2*(v - Q*0.5)；刀枪超额：刀枪*3 > Q*0.25 时加 2*(刀枪*3 - Q*0.25)
  法抗上限：均值 S = 10 + lv*0.2；最高 T = 25 + lv*0.2
  金币 J = lv*2600 * 1.6^E * G * 1.6^(H-1)；K点 K = lv*90 * 1.5^E * 1.6^(H-1)

用法（仓库根，Python 3 标准库）：
  python -X utf8 -B tools/cf7-balance-tool/models/ti61/armor_balance.py           # 打印并写报告
  python -X utf8 -B tools/cf7-balance-tool/models/ti61/armor_balance.py --check   # 只复算比对，不写文件
  python -X utf8 -B tools/cf7-balance-tool/models/ti61/armor_balance.py --selftest # 工作簿自带示例回归
数值漂移导致 --check 失败时，标定结论视为过期，须重新审计后再更新本文件头部记录。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
ARMOR_XML = ROOT / "data/items/防具_40+级.xml"
KSHOP_JSON = ROOT / "data/kshop/A兵团官方周边直营店.json"

PIECES = ["钛合金61式头部装甲", "钛合金61式胸甲", "钛合金61式手甲", "钛合金61式腿甲", "钛合金61式装甲鞋"]
LEVEL = 45
M = 3        # 数值加权层数：K点购买1 + 高价1 + 40级以上浮动1
E = 1        # 价格加权层数：高价1
G, H = 1, 1  # 种类系数 / 伤害类型系数
ADOPTED_GOLD = 200000        # 经济权威确认的取整值
FIT_LO, FIT_HI = 0.95, 1.05  # O≈Q 通过带
PRICE_BAND = 0.05            # K点售价相对公式值的容差


def half(v, q):
    return v if v < q * 0.5 else v + 2 * (v - q * 0.5)


def score(defence, hp, mp, damage, gunblade, punch, resist, weight, lv, m):
    p = lv * 20 + weight * 10
    q = p * 1.25 ** m
    o = defence * 2 + half(hp, q) + half(mp, q) + half(damage * 3 + gunblade * 3, q)
    if gunblade * 3 > q * 0.25:
        o += 2 * (gunblade * 3 - q * 0.25)
    o += half(punch * 4, q) + resist
    return p, q, o


def gold_price(lv, e, g, h):
    return lv * 2600 * 1.6 ** e * g * 1.6 ** (h - 1)


def kpoint_price(lv, e, h):
    return lv * 90 * 1.5 ** e * 1.6 ** (h - 1)


def read_pieces():
    xml = ARMOR_XML.read_text(encoding="utf-8")
    blocks = xml.split("<item>")
    kshop = {e["item"]: int(e["price"]) for e in json.loads(KSHOP_JSON.read_text(encoding="utf-8"))}
    out = []
    for name in PIECES:
        blk = next((b for b in blocks if f"<name>{name}</name>" in b), None)
        if blk is None:
            raise SystemExit(f"未找到物品：{name}")

        def num(tag, default=0.0):
            m = re.search(f"<{tag}>([^<]*)</{tag}>", blk)
            return float(m.group(1)) if m else default

        md = re.search(r"<magicdefence>(.*?)</magicdefence>", blk, re.S)
        resist = sum(float(v) for v in re.findall(r">(\d+(?:\.\d+)?)<", md.group(1))) if md else 0.0
        out.append({
            "name": name, "weight": num("weight"), "defence": num("defence"),
            "hp": num("hp"), "mp": num("mp"), "damage": num("damage"),
            "gunblade": num("gunblade"), "punch": num("punch"),
            "resist": resist, "price": num("price"),
            "kpoint": kshop.get(name),
        })
    return out


def audit(pieces):
    rows, failures = [], []
    j = gold_price(LEVEL, E, G, H)
    k = kpoint_price(LEVEL, E, H)
    cap_s, cap_t = 10 + LEVEL * 0.2, 25 + LEVEL * 0.2
    for it in pieces:
        p, q, o = score(it["defence"], it["hp"], it["mp"], it["damage"], it["gunblade"],
                        it["punch"], it["resist"], it["weight"], LEVEL, M)
        ratio = o / q
        ok = FIT_LO <= ratio <= FIT_HI
        if not ok:
            failures.append(f"{it['name']}: O/Q={ratio:.3f} 超出 [{FIT_LO}, {FIT_HI}]，M={M} 标定过期")
        if it["price"] != ADOPTED_GOLD:
            failures.append(f"{it['name']}: price={it['price']:.0f} ≠ 确认取整值 {ADOPTED_GOLD}")
        if it["kpoint"] is None or abs(it["kpoint"] / k - 1) > PRICE_BAND:
            failures.append(f"{it['name']}: K点售价 {it['kpoint']} 与公式值 {k:.0f} 偏差超 {PRICE_BAND:.0%}")
        if it["resist"] > cap_t:
            failures.append(f"{it['name']}: 法抗合计 {it['resist']:.0f} 超最高上限 T={cap_t:.0f}")
        rows.append((it["name"].replace("钛合金61式", ""), int(it["weight"]), int(p), round(q, 1),
                     round(o, 1), round(ratio, 3), int(it["price"]), it["kpoint"]))
    return rows, failures, j, k, cap_s, cap_t


def render(rows, failures, j, k, cap_s, cap_t):
    lines = [
        "# 钛合金61式防具加权标定复算", "",
        f"- 标定：M={M}（K点购买1+高价1+40级浮动1）；E={E}（高价1），G={G}，H={H}",
        f"- 金币公式值 J={j:.0f}，确认取整值 {ADOPTED_GOLD}（{ADOPTED_GOLD / j - 1:+.1%}）；K点公式值 K={k:.0f}",
        f"- 法抗上限：均值 S={cap_s:.0f}，最高 T={cap_t:.0f}", "",
        "| 部件 | 重量 | 平衡总分P | 加权总分Q | 当前总分O | O/Q | 金币price | K点售价 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    lines += [f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} | {r[6]} | {r[7]} |" for r in rows]
    lines += ["", f"**结论**：{'全部通过' if not failures else '存在漂移'}"]
    lines += [f"- {f}" for f in failures]
    return "\n".join(lines) + "\n"


def selftest():
    # 工作簿自带示例回归：92上身(lv28,w8,M=1) O=Q=800；61头盔(lv33,w10,M=1) O=960≈Q=950
    _, q1, o1 = score(200, 100, 100, 60, 0, 0, 20, 8, 28, 1)
    assert (q1, o1) == (800, 800), (q1, o1)
    _, q2, o2 = score(230, 130, 50, 100, 0, 0, 20, 10, 33, 1)
    assert (q2, o2) == (950, 960), (q2, o2)
    # 装备价格页防具示例：lv5 E=1 → J=20800，K=675；lv32 E=1 → J=133120，K=4320
    assert gold_price(5, 1, 1, 1) == 20800 and kpoint_price(5, 1, 1) == 675
    assert gold_price(32, 1, 1, 1) == 133120 and kpoint_price(32, 1, 1) == 4320
    print("selftest OK：公式实现与工作簿自带示例一致")


def main():
    args = set(sys.argv[1:])
    if "--selftest" in args:
        selftest()
        return
    check = "--check" in args
    out_dir = ROOT / "tmp/ti61-armor-balance"
    if "--out" in sys.argv:
        out_dir = Path(sys.argv[sys.argv.index("--out") + 1])
    rows, failures, j, k, cap_s, cap_t = audit(read_pieces())
    report = render(rows, failures, j, k, cap_s, cap_t)
    if check:
        old = out_dir / "report.md"
        if old.exists() and old.read_text(encoding="utf-8") != report:
            failures.append("报告内容与既有输出漂移（输入或结论已变化）")
        if failures:
            print("\n".join(failures))
            raise SystemExit(1)
        print("armor_balance --check OK：M=3 / E=1 标定与当前生产数据一致")
        return
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "report.md").write_text(report, encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
