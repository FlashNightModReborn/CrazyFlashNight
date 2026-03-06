import { useMemo, useState } from "react";
import rawBaseline from "../../../../baseline/baseline-extracted.json";

type TierCategory = "weapons" | "armor" | "melee" | "explosives" | "monsters" | "potions";

interface TierItem {
  name: string;
  level: number;
  keyMetric: number;
  keyLabel: string;
}

interface TierGroup {
  level: number;
  items: TierItem[];
  avgMetric: number;
}

const TIER_CATEGORIES: Array<{ value: TierCategory; label: string }> = [
  { value: "weapons", label: "枪械" },
  { value: "armor", label: "防具" },
  { value: "melee", label: "近战" },
  { value: "explosives", label: "爆炸类" },
  { value: "monsters", label: "怪物" },
  { value: "potions", label: "药剂" },
];

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const baseline = rawBaseline as Record<string, any[]>;

function extractTierItems(category: TierCategory): TierItem[] {
  const rows = baseline[category];
  if (!Array.isArray(rows)) return [];

  const items: TierItem[] = [];
  for (const row of rows) {
    const inp = row.input ?? {};
    const cached = row.cached ?? {};

    let level: number;
    let name: string;
    let keyMetric: number;
    let keyLabel: string;

    switch (category) {
      case "weapons":
        level = inp["限制等级"];
        name = inp["具体武器"] ?? `row${row._row}`;
        keyMetric = cached["平均dps"] ?? 0;
        keyLabel = "平均DPS";
        break;
      case "armor":
        level = inp["限制等级"];
        name = inp["具体装备"] ?? `row${row._row}`;
        keyMetric = cached["当前总分"] ?? 0;
        keyLabel = "总分";
        break;
      case "melee":
        level = inp["限制等级"];
        name = inp["C"] ?? `row${row._row}`;
        keyMetric = cached["推荐锋利度"] ?? 0;
        keyLabel = "推荐锋利度";
        break;
      case "explosives":
        level = inp["限制等级"];
        name = inp["C"] ?? `row${row._row}`;
        keyMetric = cached["推荐单发威力"] ?? 0;
        keyLabel = "推荐威力";
        break;
      case "monsters":
        level = inp["阶段"];
        name = inp["C"] ?? `row${row._row}`;
        keyMetric = cached["HP最大值"] ?? cached["HP最小值"] ?? 0;
        keyLabel = "HP MAX";
        break;
      case "potions":
        level = inp["玩家等级"];
        name = inp["C"] ?? `row${row._row}`;
        keyMetric = cached["当前数值"] ?? 0;
        keyLabel = "当前数值";
        break;
    }

    if (typeof level !== "number" || !Number.isFinite(level)) continue;
    if (typeof keyMetric !== "number" || !Number.isFinite(keyMetric)) continue;

    items.push({ name: String(name), level, keyMetric, keyLabel });
  }

  return items;
}

function groupByLevel(items: TierItem[]): TierGroup[] {
  const map = new Map<number, TierItem[]>();
  for (const item of items) {
    const list = map.get(item.level);
    if (list) list.push(item);
    else map.set(item.level, [item]);
  }

  const groups: TierGroup[] = [];
  for (const [level, list] of map) {
    list.sort((a, b) => b.keyMetric - a.keyMetric);
    const avg = list.reduce((s, i) => s + i.keyMetric, 0) / list.length;
    groups.push({ level, items: list, avgMetric: avg });
  }

  groups.sort((a, b) => a.level - b.level);
  return groups;
}

function formatNum(v: number): string {
  if (Number.isInteger(v)) return v.toLocaleString("zh-CN");
  return v.toLocaleString("zh-CN", { maximumFractionDigits: 1 });
}

export function TierView() {
  const [category, setCategory] = useState<TierCategory>("weapons");

  const groups = useMemo(() => {
    const items = extractTierItems(category);
    return groupByLevel(items);
  }, [category]);

  const levelLabel = category === "monsters" ? "阶段" : "等级";
  const metricLabel = groups[0]?.items[0]?.keyLabel ?? "数值";

  return (
    <section className="detail-section">
      <div className="detail-section-header">
        <h4>分级总览</h4>
      </div>
      <div className="formula-bar-engine">
        <select
          className="formula-bar-select"
          value={category}
          onChange={(e) => setCategory(e.currentTarget.value as TierCategory)}
        >
          {TIER_CATEGORIES.map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
      </div>

      {groups.length === 0 ? (
        <div className="empty-state">该分类无有效数据</div>
      ) : (
        <div className="tier-view-groups">
          {groups.map((group) => (
            <div className="tier-view-group" key={group.level}>
              <div className="tier-view-group-header">
                <span className="tier-view-level">
                  {levelLabel} {group.level}
                </span>
                <span className="tier-view-avg">
                  平均{metricLabel}: {formatNum(group.avgMetric)}
                </span>
                <span className="tier-view-count">{group.items.length} 项</span>
              </div>
              <div className="tier-view-items">
                {group.items.map((item, i) => (
                  <div className="tier-view-item" key={`${item.name}-${i}`}>
                    <span className="tier-view-item-name">{item.name}</span>
                    <span className="tier-view-item-metric">
                      {formatNum(item.keyMetric)}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
