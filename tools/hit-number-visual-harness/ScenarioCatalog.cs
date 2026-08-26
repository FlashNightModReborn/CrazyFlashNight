using System;
using System.Collections.Generic;
using CF7Launcher.Guardian.HitNumbers;

namespace CF7Launcher.Tools.HitNumberVisualHarness
{
    internal sealed class VisualScenario
    {
        internal string Id = string.Empty;
        internal string Title = string.Empty;
        internal string Intent = string.Empty;
        internal double SnapshotSeconds = 2.0;
        internal List<HitNumberSegment> Segments { get; } = new List<HitNumberSegment>();
    }

    internal static class ScenarioCatalog
    {
        private const int Crumble = 1;
        private const int Toxic = 2;
        private const int Execute = 4;
        private const int DamageTypeLabel = 8;
        private const int CrushLabel = 16;
        private const int LifeSteal = 32;
        private const int IsEnemy = 128;
        private const int Shield = 256;

        internal static IReadOnlyList<VisualScenario> BuildReviewScenarios()
        {
            var scenarios = new List<VisualScenario>();

            var s01 = New("S01", "单段基准", "一发子弹、普通伤害；核对字号、描边和锚点。");
            Add(s01, 0, "t0", 512, 360, 1.76, 842, 0, 30, 0);
            scenarios.Add(s01);

            var s02 = New("S02", "4 段联弹", "名义单发、行为拟合四发子弹；四段必须各自可识别。");
            AddBurst(s02, 4, "linked-4", "t0", 512, 360, 1.74, 160, 34, 0.012);
            scenarios.Add(s02);

            var s03 = New("S03", "12 段联弹混伤", "联弹高段数并混入火、毒、吸血；仍需逐段无损。");
            AddBurst(s03, 12, "linked-12", "t0", 512, 365, 1.70, 120, 42, 0.009, true);
            scenarios.Add(s03);

            var s04 = New("S04", "32 段瞬时爆发", "同目标近同帧爆发；比较平衡摘要、总伤累计与逐发矩阵。");
            AddBurst(s04, 32, "burst-32", "t0", 512, 390, 1.65, 72, 31, 0.003, true);
            scenarios.Add(s04);

            var s05 = New("S05", "持续 20 段/秒", "同目标稳定射速；观察新攻击靠近目标、旧攻击等距上移。");
            AddStream(s05, 20, 1.0, "t0", 512, 390, 95, 38, true);
            scenarios.Add(s05);

            var s06 = New("S06", "持续 60 段/秒", "单目标极高 hit；比较默认压缩与三种兼容行为的视觉上限。");
            AddStream(s06, 60, 1.0, "t0", 512, 400, 48, 22, true);
            scenarios.Add(s06);

            var s07 = New("S07", "双近邻目标", "两个目标距离很近，各 12 段；固定栈不得因邻居出现而转向。");
            AddBurst(s07, 12, "left", "left", 445, 380, 1.62, 105, 30, 0.018, true);
            AddBurst(s07, 12, "right", "right", 565, 370, 1.64, 135, 35, 0.017, true, 100);
            scenarios.Add(s07);

            var s08 = New("S08", "六目标怪群", "多目标同时命中；通过目标连线和固定攻击行核对来源归属。");
            for (int target = 0; target < 6; target++)
            {
                float x = 270 + (target % 3) * 240;
                float y = 330 + (target / 3) * 125;
                AddBurst(s08, 6, "mob-" + target, "mob-" + target, x, y,
                    1.58 + target * 0.02, 82 + target * 21, 19, 0.016, true, target * 20);
            }
            scenarios.Add(s08);

            var s09 = New("S09", "屏幕边缘与屏外剔除", "左右边缘各 8 段；另有屏外段必须剔除。");
            AddBurst(s09, 8, "edge-left", "edge-left", 28, 350, 1.62, 110, 24, 0.015, true);
            AddBurst(s09, 8, "edge-right", "edge-right", 996, 350, 1.64, 145, 27, 0.015, true, 30);
            AddBurst(s09, 6, "offscreen", "offscreen", 1280, 340, 1.66, 999, 1, 0.01, true, 60);
            scenarios.Add(s09);

            var s10 = New("S10", "混合语义全集", "MISS、0、护盾、吸血、毒、斩杀、粉碎都参与全局计数。");
            Add(s10, 0, "t0", 512, 390, 1.45, 0, 0, 28, 0, true);
            Add(s10, 1, "t0", 512, 390, 1.50, 0, Shield, 28, 6, false, "", "", 0, 360);
            Add(s10, 2, "t0", 512, 390, 1.55, 164, Toxic, 28, 1);
            Add(s10, 3, "t0", 512, 390, 1.60, 431, DamageTypeLabel, 31, 1, false, "热");
            Add(s10, 4, "t0", 512, 390, 1.65, 988, Execute, 38, 4);
            Add(s10, 5, "t0", 512, 390, 1.70, 372, LifeSteal, 31, 3, false, "", "", 96);
            Add(s10, 6, "t0", 512, 390, 1.75, 525, Crumble, 32, 9);
            Add(s10, 7, "t0", 512, 390, 1.80, 718, CrushLabel, 34, 6, false, "粉碎", "✦");
            scenarios.Add(s10);

            scenarios.Add(BuildThreshold("S11", "全局上限 N-1（23）", 23));
            scenarios.Add(BuildThreshold("S12", "全局上限 N（24）", 24));
            scenarios.Add(BuildThreshold("S13", "全局上限 N+1（25）", 25));

            var s14 = New("S14", "无限制压力：120 段", "不设全局世界行上限，只保留屏外剔除；检查单次 120 段 Burst 的原子摘要。");
            AddBurst(s14, 120, "stress-120", "t0", 512, 435, 1.05, 34, 17, 0.0065, true);
            scenarios.Add(s14);

            var s15 = New(
                "S15",
                "近邻目标交叉攻击",
                "两个近邻目标各有两次交错攻击；同一 Burst 固定成行，并以目标连线明确来源。");
            AddTypedBurst(s15, 6, "left-primary", "left", 438, 390, 1.46,
                118, 17, DamageTypeLabel, 1, "火", 200);
            AddTypedBurst(s15, 4, "right-proc", "right", 586, 378, 1.54,
                72, 9, Toxic | DamageTypeLabel, 6, "冰", 300);
            AddTypedBurst(s15, 5, "right-primary", "right", 586, 378, 1.64,
                164, 21, DamageTypeLabel, 2, "雷", 400);
            AddTypedBurst(s15, 4, "left-proc", "left", 438, 390, 1.72,
                84, 11, Toxic | DamageTypeLabel, 5, "灵", 500);
            scenarios.Add(s15);

            var s16 = New(
                "S16",
                "近邻目标连续交错攻击",
                "两目标连续多轮交错；检查新攻击到达后旧 Burst 是否只做等距纵向位移。");
            s16.SnapshotSeconds = 2.5;
            s16.Segments.AddRange(BuildCausalAttributionVideoStream(3.2));
            scenarios.Add(s16);

            var s17 = New(
                "S17",
                "五位数逐发矩阵",
                "同一联弹含二十个五位数和属性标签；逐项边界不得横向或纵向相交。");
            for (int i = 0; i < 20; i++)
            {
                Add(
                    s17,
                    700 + i,
                    "long-detail",
                    512,
                    400,
                    1.72 + i * 0.002,
                    34031 + i * 137,
                    DamageTypeLabel,
                    28,
                    6,
                    false,
                    "热",
                    string.Empty,
                    0,
                    0,
                    "long-detail-burst",
                    20);
            }
            scenarios.Add(s17);

            var s18 = BuildTotalColorTransitionScenario(
                "S18",
                "总伤当前段颜色闪现",
                "低占比冰伤刚命中：主数字应先显示当前冰色，并保留全部效果与精确数值。",
                1.30);
            scenarios.Add(s18);

            var s19 = BuildTotalColorTransitionScenario(
                "S19",
                "总伤回落主体颜色",
                "同一组输入经过约 300ms：主数字应明显回落到累计贡献占优的火色。",
                1.60);
            scenarios.Add(s19);

            var s20 = New(
                "S20",
                "四模式同源 11 色板",
                "每个目标只有一段 canonical 输入；四模式必须使用同一主色和属性来源色。");
            int[] paletteX = { 150, 390, 630, 870 };
            int[] paletteY = { 190, 345, 500 };
            for (int colorId = 0; colorId < 11; colorId++)
            {
                Add(
                    s20,
                    900 + colorId,
                    "color-" + colorId,
                    paletteX[colorId % paletteX.Length],
                    paletteY[colorId / paletteX.Length],
                    1.90,
                    1200 + colorId * 137,
                    DamageTypeLabel,
                    28,
                    colorId,
                    false,
                    ColorRoleLabel(colorId),
                    string.Empty,
                    0,
                    0,
                    "canonical-color-" + colorId,
                    1);
            }
            scenarios.Add(s20);

            var s21 = New(
                "S21",
                "四模式同源语义全集",
                "单段 canonical 输入同时包含属性、粉碎、毒、溃、斩、吸血与护盾；核对独立颜色和精确值。");
            Add(
                s21,
                1000,
                "semantic-target",
                512,
                390,
                1.90,
                5310,
                Crumble | Toxic | Execute | DamageTypeLabel | CrushLabel |
                    LifeSteal | IsEnemy | Shield,
                28,
                6,
                false,
                "热",
                "✦",
                128,
                256,
                "canonical-semantic",
                1);
            scenarios.Add(s21);

            return scenarios;
        }

        private static VisualScenario BuildTotalColorTransitionScenario(
            string id,
            string title,
            string intent,
            double snapshotSeconds)
        {
            VisualScenario scenario = New(id, title, intent);
            scenario.SnapshotSeconds = snapshotSeconds;
            Add(scenario, 800, "color-target", 512, 390, 1.00,
                1200, DamageTypeLabel | LifeSteal, 28, 1, false, "热", "", 90);
            Add(scenario, 801, "color-target", 512, 390, 1.04,
                1100, DamageTypeLabel | Shield, 28, 1, false, "热", "", 0, 180);
            Add(scenario, 802, "color-target", 512, 390, 1.08,
                1000, Toxic, 28, 1);
            Add(scenario, 803, "color-target", 512, 390, 1.30,
                240, DamageTypeLabel | CrushLabel, 28, 6, false, "冰", "✦");
            return scenario;
        }

        internal static IReadOnlyList<HitNumberSegment> BuildVideoStream(double durationSeconds)
        {
            var scenario = New("V01", "持续混伤", "视频输入");
            int sequence = 0;
            const int hitsPerSecond = 60;
            int count = (int)Math.Ceiling(durationSeconds * hitsPerSecond);
            for (int i = 0; i < count; i++)
            {
                double time = i / (double)hitsPerSecond;
                string target = time < durationSeconds * 0.55 ? "boss" : (i % 4 == 0 ? "add" : "boss");
                float x = target == "boss" ? 530f : 760f;
                float y = target == "boss" ? 410f : 365f;
                int damage = 68 + ((i * 47) % 390);
                int flags = FlagsFor(i);
                int color = ColorFor(i);
                string label = (flags & DamageTypeLabel) != 0 ? LabelFor(color) : string.Empty;
                string emoji = (flags & CrushLabel) != 0 ? "✦" : string.Empty;
                scenario.Segments.Add(new HitNumberSegment
                {
                    Sequence = sequence++,
                    BurstId = "stream-" + (i / 4),
                    ExpectedBurstHitCount = 4,
                    TargetId = target,
                    TargetX = x,
                    TargetY = y,
                    ArrivalSeconds = time,
                    Damage = damage,
                    Packed = HitNumberPacking.Create(flags, i % 53 == 0, 27 + (i % 7 == 0 ? 7 : 0), color),
                    EffectText = label,
                    EffectEmoji = emoji,
                    LifeSteal = (flags & LifeSteal) != 0 ? damage * 0.2f : 0f,
                    ShieldAbsorb = (flags & Shield) != 0 ? damage * 0.55f : 0f
                });
            }
            return scenario.Segments;
        }

        internal static IReadOnlyList<HitNumberSegment> BuildCausalAttributionVideoStream(
            double durationSeconds)
        {
            var scenario = New("V02", "近邻目标交叉攻击", "动态归因视频输入");
            int cycle = 0;
            for (double start = 0.18; start < durationSeconds; start += 0.82)
            {
                int sequenceOffset = cycle * 100;
                AddTypedBurst(
                    scenario,
                    6,
                    "left-primary-" + cycle,
                    "left",
                    438,
                    390,
                    start,
                    118 + cycle * 3,
                    17,
                    DamageTypeLabel,
                    1,
                    "火",
                    sequenceOffset);
                AddTypedBurst(
                    scenario,
                    4,
                    "right-proc-" + cycle,
                    "right",
                    586,
                    378,
                    start + 0.14,
                    72 + cycle * 2,
                    9,
                    Toxic | DamageTypeLabel,
                    6,
                    "冰",
                    sequenceOffset + 20);
                AddTypedBurst(
                    scenario,
                    5,
                    "right-primary-" + cycle,
                    "right",
                    586,
                    378,
                    start + 0.29,
                    164 + cycle * 4,
                    21,
                    DamageTypeLabel,
                    2,
                    "雷",
                    sequenceOffset + 40);
                AddTypedBurst(
                    scenario,
                    4,
                    "left-proc-" + cycle,
                    "left",
                    438,
                    390,
                    start + 0.44,
                    84 + cycle * 3,
                    11,
                    Toxic | DamageTypeLabel,
                    5,
                    "灵",
                    sequenceOffset + 60);
                cycle++;
            }
            return scenario.Segments;
        }

        private static VisualScenario BuildThreshold(string id, string title, int count)
        {
            var scenario = New(id, title,
                "以建议默认上限 24 为视觉阈值样本；每个 Burst 都是一发独立攻击，裁剪必须保持攻击原子性。");
            for (int i = 0; i < count; i++)
            {
                int color = ColorFor(i);
                int flags = FlagsFor(i);
                Add(
                    scenario,
                    i,
                    "t0",
                    512,
                    395,
                    1.42 + i * 0.018,
                    80 + ((i * 31) % 127),
                    flags,
                    27 + (i % 9 == 0 ? 7 : 0),
                    color,
                    false,
                    (flags & DamageTypeLabel) != 0 ? LabelFor(color) : string.Empty,
                    (flags & CrushLabel) != 0 ? "✦" : string.Empty,
                    (flags & LifeSteal) != 0 ? 30 + i : 0,
                    (flags & Shield) != 0 ? 70 + i * 2 : 0,
                    "threshold-attack-" + i,
                    1);
            }
            return scenario;
        }

        private static VisualScenario New(string id, string title, string intent)
        {
            return new VisualScenario { Id = id, Title = title, Intent = intent };
        }

        private static void AddStream(
            VisualScenario scenario,
            int count,
            double windowSeconds,
            string targetId,
            float x,
            float y,
            int baseDamage,
            int spread,
            bool mixed)
        {
            for (int i = 0; i < count; i++)
            {
                double arrival = scenario.SnapshotSeconds - windowSeconds +
                    (i + 0.5) * windowSeconds / count;
                Add(scenario, i, targetId, x, y, arrival,
                    baseDamage + ((i * 37) % Math.Max(1, spread)),
                    mixed ? FlagsFor(i) : 0,
                    27 + (i % 9 == 0 ? 7 : 0),
                    mixed ? ColorFor(i) : 0,
                    false,
                    mixed ? LabelFor(ColorFor(i)) : string.Empty,
                    mixed && (FlagsFor(i) & CrushLabel) != 0 ? "✦" : string.Empty,
                    mixed && (FlagsFor(i) & LifeSteal) != 0 ? 34 : 0,
                    mixed && (FlagsFor(i) & Shield) != 0 ? 86 : 0,
                    "stream-" + (i / 3),
                    3);
            }
        }

        private static void AddBurst(
            VisualScenario scenario,
            int count,
            string burstId,
            string targetId,
            float x,
            float y,
            double firstArrival,
            int baseDamage,
            int spread,
            double interval,
            bool mixed = false,
            int sequenceOffset = 0)
        {
            for (int i = 0; i < count; i++)
            {
                int color = mixed ? ColorFor(i) : 0;
                int flags = mixed ? FlagsFor(i) : 0;
                Add(scenario, sequenceOffset + i, targetId, x, y,
                    firstArrival + i * interval,
                    baseDamage + ((i * 47) % Math.Max(1, spread)),
                    flags,
                    27 + (i % 11 == 0 ? 8 : 0),
                    color,
                    false,
                    (flags & DamageTypeLabel) != 0 ? LabelFor(color) : string.Empty,
                    (flags & CrushLabel) != 0 ? "✦" : string.Empty,
                    (flags & LifeSteal) != 0 ? 32 + i : 0,
                    (flags & Shield) != 0 ? 75 + i * 2 : 0,
                    burstId,
                    count);
            }
        }

        private static void AddTypedBurst(
            VisualScenario scenario,
            int count,
            string burstId,
            string targetId,
            float x,
            float y,
            double firstArrival,
            int baseDamage,
            int spread,
            int flags,
            int colorId,
            string label,
            int sequenceOffset)
        {
            for (int i = 0; i < count; i++)
            {
                Add(
                    scenario,
                    sequenceOffset + i,
                    targetId,
                    x,
                    y,
                    firstArrival + i * 0.012,
                    baseDamage + ((i * 13) % Math.Max(1, spread)),
                    flags,
                    27 + (i == 0 ? 5 : 0),
                    colorId,
                    false,
                    label,
                    string.Empty,
                    0,
                    0,
                    burstId,
                    count);
            }
        }

        private static void Add(
            VisualScenario scenario,
            int sequence,
            string targetId,
            float x,
            float y,
            double arrival,
            int damage,
            int flags,
            int fontSize,
            int colorId,
            bool miss = false,
            string effectText = "",
            string effectEmoji = "",
            float lifeSteal = 0,
            float shieldAbsorb = 0,
            string burstId = "",
            int expectedBurstHitCount = 0)
        {
            scenario.Segments.Add(new HitNumberSegment
            {
                Sequence = sequence,
                BurstId = burstId,
                ExpectedBurstHitCount = expectedBurstHitCount,
                TargetId = targetId,
                TargetX = x,
                TargetY = y,
                ArrivalSeconds = arrival,
                Damage = damage,
                Packed = HitNumberPacking.Create(flags, miss, fontSize, colorId),
                EffectText = effectText,
                EffectEmoji = effectEmoji,
                LifeSteal = lifeSteal,
                ShieldAbsorb = shieldAbsorb
            });
        }

        private static int FlagsFor(int index)
        {
            int flags = 0;
            if (index % 7 == 1) flags |= Toxic;
            if (index % 13 == 2) flags |= DamageTypeLabel;
            if (index % 17 == 3) flags |= LifeSteal;
            if (index % 19 == 4) flags |= Shield;
            if (index % 23 == 5) flags |= Crumble;
            if (index % 29 == 6) flags |= CrushLabel;
            if (index % 47 == 7) flags |= Execute | IsEnemy;
            return flags;
        }

        private static int ColorFor(int index)
        {
            int[] colors = { 0, 1, 2, 6, 5, 9, 10, 4 };
            return colors[index % colors.Length];
        }

        private static string LabelFor(int colorId)
        {
            return colorId switch
            {
                1 => "火",
                2 => "雷",
                4 => "蚀",
                5 => "灵",
                6 => "冰",
                9 => "爆",
                10 => "光",
                _ => "物"
            };
        }

        private static string ColorRoleLabel(int colorId)
        {
            string[] labels =
            {
                "白", "红", "黄", "暗绛", "紫", "浅紫",
                "蓝", "暗红", "暗黄", "粉红", "浅黄"
            };
            return colorId >= 0 && colorId < labels.Length
                ? labels[colorId]
                : "白";
        }
    }
}
