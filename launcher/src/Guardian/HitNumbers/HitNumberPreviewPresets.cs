using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal readonly struct HitNumberPreviewTarget
    {
        internal HitNumberPreviewTarget(string id, string label, float x, float y, bool isAlly)
        {
            Id = id;
            Label = label;
            X = x;
            Y = y;
            IsAlly = isAlly;
        }

        internal string Id { get; }
        internal string Label { get; }
        internal float X { get; }
        internal float Y { get; }
        internal bool IsAlly { get; }
    }

    internal sealed class HitNumberPreviewPreset
    {
        internal HitNumberPreviewPreset(
            string id,
            string label,
            string description,
            int durationMs,
            int representativeTimeMs)
        {
            Id = id;
            Label = label;
            Description = description;
            DurationMs = durationMs;
            RepresentativeTimeMs = representativeTimeMs;
        }

        internal string Id { get; }
        internal string Label { get; }
        internal string Description { get; }
        internal int DurationMs { get; }
        internal int RepresentativeTimeMs { get; }
    }

    /// <summary>
    /// 设置页实时伤害数字沙盒与离线工具共用的确定性弹幕预设目录。
    /// 全部输入通过生产 HitNumberBatchParser 的 11 字段线协议送入独立 HitNumberRuntime，
    /// 保证设置预览与真实战斗管线永不分叉。
    /// </summary>
    internal static class HitNumberPreviewPresets
    {
        private const int Crumble = 1;
        private const int Toxic = 2;
        private const int Execute = 4;
        private const int DamageTypeLabel = 8;
        private const int CrushLabel = 16;
        private const int LifeSteal = 32;
        private const int IsEnemy = 128;
        private const int Shield = 256;
        private const int AllyHealPacked = 4194304;
        private const int EnemyHealPacked = 4194432;

        private static readonly HitNumberPreviewPreset[] OrderedCatalog =
        {
            new HitNumberPreviewPreset(
                "light",
                "常规连射",
                "单发与 4 段联弹混伤，含暴击、属性、护盾与吸血",
                3600,
                1450),
            new HitNumberPreviewPreset(
                "barrage",
                "高密弹幕",
                "持续 60 段/秒高频爆发，最直观对比模式聚合与行数上限",
                4000,
                1850),
            new HitNumberPreviewPreset(
                "crowd",
                "多目标混战",
                "近邻多目标交叉受击，对照目标归属与指向标记",
                3600,
                1700),
            new HitNumberPreviewPreset(
                "healing",
                "伤害与治疗",
                "持续治疗窗口、敌方回血与同屏伤害混流",
                4400,
                1800)
        };

        private static readonly Dictionary<string, HitNumberPreviewPreset> ById = BuildIndex();

        internal static IReadOnlyList<HitNumberPreviewPreset> Catalog => OrderedCatalog;

        internal static bool TryGet(string id, out HitNumberPreviewPreset preset)
        {
            if (string.IsNullOrEmpty(id))
            {
                preset = null;
                return false;
            }
            return ById.TryGetValue(id, out preset);
        }

        internal static void FillTargets(string presetId, double nowSeconds, List<HitNumberPreviewTarget> destination)
        {
            destination.Clear();
            switch (presetId)
            {
                case "light":
                    destination.Add(new HitNumberPreviewTarget("dummy-center", "靶标", 512f, 405f, false));
                    break;
                case "barrage":
                    destination.Add(new HitNumberPreviewTarget("boss", "重甲目标", 470f, 422f, false));
                    destination.Add(new HitNumberPreviewTarget("add", "侧翼目标", 748f, 376f, false));
                    break;
                case "crowd":
                    destination.Add(new HitNumberPreviewTarget("left", "左目标", 380f, 404f, false));
                    destination.Add(new HitNumberPreviewTarget("mid", "中目标", 536f, 434f, false));
                    destination.Add(new HitNumberPreviewTarget("right", "右目标", 674f, 384f, false));
                    break;
                case "healing":
                    for (int i = 0; i < 3; i++)
                    {
                        float x = (float)(340 + i * 172 + Math.Sin(nowSeconds * 1.6 + i) * 14);
                        float y = 402f + (i % 2) * 32f;
                        destination.Add(new HitNumberPreviewTarget(
                            "actor-" + i,
                            i == 2 ? "敌方回血" : "友方单位",
                            x,
                            y,
                            i != 2));
                    }
                    break;
            }
        }

        /// <summary>
        /// 生成指定 60Hz 仿真刻的生产 wire 批负载（空字符串表示该帧无新增命中）。
        /// </summary>
        internal static string BuildTickPayload(string presetId, int tickIndex, int simulationFps)
        {
            if (tickIndex < 0 || simulationFps <= 0) return string.Empty;
            double now = tickIndex / (double)simulationFps;
            switch (presetId)
            {
                case "light":
                    return BuildLightTick(tickIndex);
                case "barrage":
                    return BuildBarrageTick(tickIndex);
                case "crowd":
                    return BuildCrowdTick(tickIndex);
                case "healing":
                    return BuildHealingTick(tickIndex, now);
                default:
                    return string.Empty;
            }
        }

        private static string BuildLightTick(int tick)
        {
            var sb = new StringBuilder(192);
            // 每 0.75s（45 帧）触发一组典型攻击：单发重击 / 4 段联弹 / 属性混伤 / 处决暴击
            int cycle = tick / 45;
            int offset = tick % 45;
            switch (cycle % 4)
            {
                case 0:
                    if (offset == 2)
                        AppendDamage(sb, 842, 512f, 405f, 0, false, 30, 0, "", "", 0f, 0f, "dummy-center", "light-s-" + cycle, 1);
                    else if (offset == 18)
                        AppendDamage(sb, 1460, 512f, 405f, DamageTypeLabel | CrushLabel, false, 34, 2, "雷", "✦", 0f, 0f, "dummy-center", "light-c-" + cycle, 1);
                    break;
                case 1:
                    if (offset >= 2 && offset <= 5)
                    {
                        int seg = offset - 2;
                        int dmg = 175 + seg * 38;
                        int flags = seg == 2 ? (DamageTypeLabel | LifeSteal) : DamageTypeLabel;
                        AppendDamage(sb, dmg, 512f, 405f, flags, false, 28, 1, "火", "",
                            (flags & LifeSteal) != 0 ? 48f : 0f, 0f, "dummy-center", "light-b4-" + cycle, 4);
                    }
                    break;
                case 2:
                    if (offset == 2)
                        AppendDamage(sb, 0, 512f, 405f, Shield, false, 28, 6, "", "", 0f, 320f, "dummy-center", "light-sh-" + cycle, 1);
                    else if (offset == 14)
                        AppendDamage(sb, 368, 512f, 405f, Toxic | DamageTypeLabel, false, 28, 6, "冰", "", 0f, 0f, "dummy-center", "light-tx-" + cycle, 1);
                    else if (offset == 26)
                        AppendDamage(sb, 0, 512f, 405f, 0, true, 28, 0, "", "", 0f, 0f, "dummy-center", "light-ms-" + cycle, 1);
                    break;
                default:
                    if (offset >= 2 && offset <= 7)
                    {
                        int seg = offset - 2;
                        int color = seg % 2 == 0 ? 5 : 9;
                        int flags = seg == 5 ? (Execute | Crumble) : DamageTypeLabel;
                        AppendDamage(sb, seg == 5 ? 1288 : 196 + seg * 29, 512f, 405f, flags, false,
                            seg == 5 ? 36 : 28, color, seg == 5 ? "" : (color == 5 ? "灵" : "穿"),
                            "", 0f, 0f, "dummy-center", "light-b6-" + cycle, 6);
                    }
                    break;
            }
            return sb.ToString();
        }

        private static string BuildBarrageTick(int tick)
        {
            // 前 3.5 秒（210 帧）保持 60 段/秒高密输出，尾段 0.5 秒留自然淡出余韵
            if (tick < 1 || tick > 210) return string.Empty;
            var sb = new StringBuilder(192);
            int i = tick - 1;
            bool secondary = tick > 95 && (i % 4 == 0);
            string targetId = secondary ? "add" : "boss";
            float x = secondary ? 748f : 470f;
            float y = secondary ? 376f : 422f;
            int damage = 78 + ((i * 47) % 390);
            int flags = FlagsFor(i);
            int color = ColorFor(i);
            string label = (flags & DamageTypeLabel) != 0 ? LabelFor(color) : string.Empty;
            string emoji = (flags & CrushLabel) != 0 ? "✦" : string.Empty;
            bool isMiss = i % 43 == 0;
            int fontSize = 27 + (i % 7 == 0 ? 7 : 0);
            AppendDamage(
                sb,
                isMiss ? 0 : damage,
                x,
                y,
                flags,
                isMiss,
                fontSize,
                color,
                label,
                emoji,
                (flags & LifeSteal) != 0 ? damage * 0.22f : 0f,
                (flags & Shield) != 0 ? damage * 0.5f : 0f,
                targetId,
                "barrage-" + (i / 4),
                4);
            return sb.ToString();
        }

        private static string BuildCrowdTick(int tick)
        {
            var sb = new StringBuilder(256);
            int cycle = tick / 48;
            int offset = tick % 48;
            if (offset >= 2 && offset <= 7)
            {
                int seg = offset - 2;
                AppendDamage(sb, 134 + seg * 19 + cycle * 7, 380f, 404f, DamageTypeLabel, false, 28, 1, "火", "",
                    0f, 0f, "left", "crowd-l1-" + cycle, 6);
            }
            if (offset >= 10 && offset <= 13)
            {
                int seg = offset - 10;
                AppendDamage(sb, 92 + seg * 14, 674f, 384f, Toxic | DamageTypeLabel, false, 28, 6, "冰", "",
                    0f, 0f, "right", "crowd-r1-" + cycle, 4);
            }
            if (offset >= 18 && offset <= 22)
            {
                int seg = offset - 18;
                AppendDamage(sb, 168 + seg * 23, 536f, 434f, DamageTypeLabel | (seg == 4 ? CrushLabel : 0), false,
                    seg == 4 ? 33 : 28, 2, "雷", seg == 4 ? "✦" : "",
                    0f, 0f, "mid", "crowd-m1-" + cycle, 5);
            }
            if (offset >= 28 && offset <= 32)
            {
                int seg = offset - 28;
                AppendDamage(sb, 112 + seg * 16, 674f, 384f, DamageTypeLabel | LifeSteal, false, 28, 5, "灵", "",
                    28f, 0f, "right", "crowd-r2-" + cycle, 5);
            }
            if (offset >= 35 && offset <= 38)
            {
                int seg = offset - 35;
                AppendDamage(sb, 98 + seg * 15, 380f, 404f, Shield | DamageTypeLabel, false, 28, 9, "穿", "",
                    0f, 110f, "left", "crowd-l2-" + cycle, 4);
            }
            return sb.ToString();
        }

        private static string BuildHealingTick(int tick, double now)
        {
            if (tick < 2 || tick > 216) return string.Empty;
            var sb = new StringBuilder(256);
            // 30Hz 治疗流（每 2 个 60Hz tick 发一包）+ 同屏伤害穿插
            for (int target = 0; target < 3; target++)
            {
                float x = (float)(340 + target * 172 + Math.Sin(now * 1.6 + target) * 14);
                float y = 402f + (target % 2) * 32f;
                if (tick % 2 == 0)
                {
                    AppendHeal(sb, target == 2 ? 567.3056 : 70.6112, x, y, target == 2, "heal-" + target);
                }
                if (tick % 18 == target * 6 + 2)
                {
                    int color = target == 2 ? 1 : (target == 1 ? 2 : 6);
                    AppendDamage(sb, 145 + target * 86, x, y, DamageTypeLabel, false, 28, color, LabelFor(color), "",
                        0f, 0f, "actor-" + target, "hm-" + target + "-" + tick, 1);
                }
            }
            return sb.ToString();
        }

        private static void AppendDamage(
            StringBuilder sb,
            int damage,
            float x,
            float y,
            int flags,
            bool isMiss,
            int fontSize,
            int colorId,
            string effectText,
            string effectEmoji,
            float lifeSteal,
            float shieldAbsorb,
            string targetId,
            string burstId,
            int expectedBurstHitCount)
        {
            if (sb.Length > 0) sb.Append(';');
            int packed = HitNumberPacking.Create(flags, isMiss, fontSize, colorId);
            sb.Append(damage.ToString(CultureInfo.InvariantCulture)).Append('|')
                .Append(x.ToString("0.##", CultureInfo.InvariantCulture)).Append('|')
                .Append(y.ToString("0.##", CultureInfo.InvariantCulture)).Append('|')
                .Append(packed.ToString(CultureInfo.InvariantCulture)).Append('|')
                .Append(effectText ?? string.Empty).Append('|')
                .Append(effectEmoji ?? string.Empty).Append('|')
                .Append(lifeSteal.ToString("0.##", CultureInfo.InvariantCulture)).Append('|')
                .Append(shieldAbsorb.ToString("0.##", CultureInfo.InvariantCulture)).Append('|')
                .Append(targetId).Append('|')
                .Append(burstId).Append('|')
                .Append(Math.Max(1, expectedBurstHitCount).ToString(CultureInfo.InvariantCulture));
        }

        private static void AppendHeal(
            StringBuilder sb,
            double amount,
            float x,
            float y,
            bool isEnemy,
            string targetId)
        {
            if (sb.Length > 0) sb.Append(';');
            sb.Append(amount.ToString("0.####", CultureInfo.InvariantCulture)).Append('|')
                .Append(x.ToString("0.##", CultureInfo.InvariantCulture)).Append('|')
                .Append(y.ToString("0.##", CultureInfo.InvariantCulture)).Append('|')
                .Append((isEnemy ? EnemyHealPacked : AllyHealPacked).ToString(CultureInfo.InvariantCulture))
                .Append("|||0|0|")
                .Append(targetId)
                .Append("||1");
        }

        private static int FlagsFor(int index)
        {
            switch (index % 8)
            {
                case 0: return DamageTypeLabel;
                case 1: return Toxic | DamageTypeLabel;
                case 2: return LifeSteal | DamageTypeLabel;
                case 3: return Shield | DamageTypeLabel;
                case 4: return CrushLabel | DamageTypeLabel;
                case 5: return Crumble;
                case 6: return Execute | DamageTypeLabel;
                default: return 0;
            }
        }

        private static int ColorFor(int index)
        {
            int[] palette = { 0, 1, 2, 6, 5, 4, 3, 9, 10 };
            return palette[index % palette.Length];
        }

        private static string LabelFor(int colorId)
        {
            switch (colorId)
            {
                case 1: return "火";
                case 2: return "雷";
                case 3: return "蚀";
                case 4: return "暗";
                case 5: return "灵";
                case 6: return "冰";
                case 9: return "穿";
                case 10: return "光";
                default: return "热";
            }
        }

        private static Dictionary<string, HitNumberPreviewPreset> BuildIndex()
        {
            var map = new Dictionary<string, HitNumberPreviewPreset>(OrderedCatalog.Length, StringComparer.Ordinal);
            for (int i = 0; i < OrderedCatalog.Length; i++)
                map[OrderedCatalog[i].Id] = OrderedCatalog[i];
            return map;
        }
    }
}
