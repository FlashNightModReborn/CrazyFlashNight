// ════════════════════════════════════════════════════════════════════════════
// arena-factions.js — 竞技场势力卡【手作】元数据（策划填，非自动生成）
//
// 用途：堕落/爬升模式每势力一张卡，此文件覆盖自动派生的默认值，让策划手工标定难度/经济/叙事。
// 消费：launcher/web/modules/arena-panel.js 的 factionMeta()/wavesForScale()/buildFallenCards()。
// 缺省语义：某势力未列、或字段为 null → 全部回退派生值（roster levelMax / roster 规模猜波数）。
//
// 字段：
//   displayName : 叙事名（默认=势力键名）。
//   benchLevel  : ★对标等级 = 等效挑战等级。廉价非人形怪远弱于同级人形 merc，原始怪物等级会"难度低奖励高"。
//                 奖金/押金按 benchLevel 而非原始 levelMax 算。null=暂回退 levelMax（偏高，待策划下调）。
//                 长期与 data/enemy_properties 的 <战力系数>（不填=1）联动：未标 benchLevel 时可由
//                 Σ(刷怪等级×战力系数) 自动推导（派生器待接，见 tools/derive-arena-meta-teams.js）。
//   scale       : 规模档 small|large|coalition → 爬升波数上限 5|10|15（叙事：小势力/大势力/联军势力）。
//                 null=按 roster 单位数猜（<6小 / <12大 / ≥12联军）。下方种子是自动猜值，请按叙事改。
//   enabled     : false=该势力不出卡（剔除误分类/不想做的势力）。默认 true。
//   units       : 兵种白名单 ["兵种N",...]，预留——填了则只采样这些（去跨势力污染）。null=用派生 roster 全池。
//
// 种子由 2026-06-14 的 arena-meta-rosters.js 派生（18 张卡的势力）。注释里的「派生:」是当前回退基准值，
// 仅供参考；策划应：①核 lore 改 displayName/scale ②标 benchLevel（关键）③去污染填 units ④禁用误分类势力。
// ════════════════════════════════════════════════════════════════════════════
(function () {
    if (typeof window === "undefined") return;
    window.ArenaFactions = {
        version: 1,
        note: "手作竞技场势力卡元数据；缺省回退派生值。改此文件后无需重派生，刷新 web 即生效。",
        factions: {
            // ── 低段（派生 levelMax ≤ 50）──
            "军阀势力":   { displayName: "军阀势力", benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位19 等级17-50
            "摇滚公园":   { displayName: "摇滚公园", benchLevel: null, scale: "large",     enabled: true, units: null }, // 派生: 单位6  等级10-50
            "波斯军":     { displayName: "波斯军",   benchLevel: null, scale: "large",     enabled: true, units: null }, // 派生: 单位6  等级20-59
            "不死军团":   { displayName: "不死军团", benchLevel: null, scale: "small",     enabled: true, units: null }, // 派生: 单位5  等级35-59

            // ── 中段（派生 levelMax = 60）──
            "虫群":       { displayName: "虫群",     benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位20 等级41-60
            "堕落城":     { displayName: "堕落城",   benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位19 等级15-60 ⚠跨势力污染重，建议填 units
            "方舟":       { displayName: "方舟",     benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位66 等级30-60
            "黑铁会":     { displayName: "黑铁会",   benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位32 等级16-60
            "狂野玫瑰":   { displayName: "狂野玫瑰", benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位27 等级20-60
            "忍者":       { displayName: "忍者",     benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位40 等级1-60
            "日本军":     { displayName: "日本军",   benchLevel: null, scale: "large",     enabled: true, units: null }, // 派生: 单位9  等级10-60
            "天网":       { displayName: "天网",     benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位91 等级24-60 ⚠含错分的方舟无人机
            "亡灵/僵尸":  { displayName: "亡灵/僵尸", benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位126 等级1-60 ⚠catch-all 杂烩，建议填 units
            "雪山":       { displayName: "雪山",     benchLevel: null, scale: "large",     enabled: true, units: null }, // 派生: 单位7  等级20-60

            // ── 高段（派生 levelMax = 100）──
            "凤凰眷属":   { displayName: "凤凰眷属", benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位20 等级60-100
            "魔神":       { displayName: "魔神",     benchLevel: null, scale: "large",     enabled: true, units: null }, // 派生: 单位10 等级60-100
            "铁血":       { displayName: "铁血",     benchLevel: null, scale: "coalition", enabled: true, units: null }, // 派生: 单位25 等级20-100
            "异形":       { displayName: "异形",     benchLevel: null, scale: "coalition", enabled: true, units: null }  // 派生: 单位79 等级25-100
        }
    };
})();
