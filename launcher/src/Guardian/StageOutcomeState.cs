using System;
using System.Collections.Generic;
using System.Globalization;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// AS2 StageRunSession 的只读原生投影。生死、胜负、复活币和奖励状态均由
    /// AS2 决定；此类型只做严格协议校验和展示派生。
    /// </summary>
    public sealed class StageOutcomeState
    {
        private static readonly HashSet<string> Outcomes =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "active", "victory", "failure", "retreat"
            };

        private static readonly HashSet<string> Lives =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "alive", "dead", "reviving"
            };

        private static readonly HashSet<string> Settlements =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "none", "prepared", "web_active", "rewards_pending",
                "claimed", "abandoned", "error"
            };

        public string RunId { get; private set; }
        public int Revision { get; private set; }
        public string StageName { get; private set; }
        public string Difficulty { get; private set; }
        public string Outcome { get; private set; }
        public string Life { get; private set; }
        public long ActiveFrames { get; private set; }
        public long ReviveCoins { get; private set; }
        public bool ReviveAllowed { get; private set; }
        public string ReviveBlockedReason { get; private set; }
        public bool CanReturnBase { get; private set; }
        public string Settlement { get; private set; }
        public int RemainingRewards { get; private set; }

        public bool ShouldDisplay
        {
            get
            {
                if (Settlement == "rewards_pending") return true;
                if (Settlement != "none") return false;
                if (Life == "dead" || Life == "reviving") return true;
                return Outcome == "victory" || Outcome == "failure";
            }
        }

        public static bool TryParseMessage(
            JObject message,
            out StageOutcomeState state,
            out string error)
        {
            state = null;
            error = "invalid_message";
            if (!HasExactKeys(message, "task", "payload")
                || message.Value<string>("task") != "stage_outcome")
                return false;

            JObject payload = message["payload"] as JObject;
            if (!HasExactKeys(payload,
                    "v", "runId", "revision", "stageName", "difficulty",
                    "outcome", "life", "activeFrames", "reviveCoins",
                    "reviveAllowed", "reviveBlockedReason", "canReturnBase",
                    "settlement", "remainingRewards"))
                return false;

            int version;
            int revision;
            int remainingRewards;
            long activeFrames;
            long reviveCoins;
            string runId;
            string stageName;
            string difficulty;
            string outcome;
            string life;
            string blocked;
            string settlement;
            bool reviveAllowed;
            bool canReturnBase;
            if (!TryReadInt(payload["v"], 1, 1, out version)
                || !TryReadOpaque(payload["runId"], 96, out runId)
                || !TryReadInt(payload["revision"], 1, int.MaxValue, out revision)
                || !TryReadText(payload["stageName"], 96, false, out stageName)
                || !TryReadText(payload["difficulty"], 48, false, out difficulty)
                || !TryReadEnum(payload["outcome"], Outcomes, out outcome)
                || !TryReadEnum(payload["life"], Lives, out life)
                || !TryReadLong(payload["activeFrames"], 0, 9007199254740991L,
                    out activeFrames)
                || !TryReadLong(payload["reviveCoins"], 0, 9007199254740991L,
                    out reviveCoins)
                || !TryReadBool(payload["reviveAllowed"], out reviveAllowed)
                || !TryReadText(payload["reviveBlockedReason"], 48, true, out blocked)
                || !TryReadBool(payload["canReturnBase"], out canReturnBase)
                || !TryReadEnum(payload["settlement"], Settlements, out settlement)
                || !TryReadInt(payload["remainingRewards"], 0, 64,
                    out remainingRewards))
                return false;

            if (reviveAllowed && (life != "dead" || reviveCoins < 1
                    || !string.IsNullOrEmpty(blocked)))
                return false;
            if (life != "dead" && reviveAllowed) return false;
            // rewards_pending 也承载“零奖励但行动报告尚未成功显示”的可恢复状态；
            // 是否终结由 AS2 LootContainerService 决定，Host 不能按数量代签。
            // 但该状态只能出现在正规返回已开始之后：生产端此时已把 active
            // 归一成 retreat，并撤销再次返回能力。拒绝跨字段矛盾，避免伪快照
            // 把一个仍可返回的活跃关卡投影成可恢复结算。
            if (settlement == "rewards_pending"
                    && (outcome == "active" || canReturnBase))
                return false;
            if ((settlement == "claimed" || settlement == "abandoned")
                    && remainingRewards != 0)
                return false;

            state = new StageOutcomeState
            {
                RunId = runId,
                Revision = revision,
                StageName = stageName,
                Difficulty = difficulty,
                Outcome = outcome,
                Life = life,
                ActiveFrames = activeFrames,
                ReviveCoins = reviveCoins,
                ReviveAllowed = reviveAllowed,
                ReviveBlockedReason = blocked,
                CanReturnBase = canReturnBase,
                Settlement = settlement,
                RemainingRewards = remainingRewards
            };
            error = null;
            return true;
        }

        public static string FormatActiveTime(long activeFrames)
        {
            if (activeFrames < 0) activeFrames = 0;
            long totalSeconds = activeFrames / 30L;
            long hours = totalSeconds / 3600L;
            long minutes = (totalSeconds % 3600L) / 60L;
            long seconds = totalSeconds % 60L;
            long hundredths = activeFrames % 30L * 100L / 30L;
            return hours > 0
                ? string.Format("{0:00}:{1:00}:{2:00}.{3:00}",
                    hours, minutes, seconds, hundredths)
                : string.Format("{0:00}:{1:00}.{2:00}",
                    minutes, seconds, hundredths);
        }

        /// <summary>
        /// 原生复活决策栏使用的有界中文计数。低于一万保留精确值；更大值按
        /// 万/亿/万亿压缩到至多一位小数，避免复活币存量挤掉相邻动作。
        /// </summary>
        public static string FormatCompactCount(long value)
        {
            if (value < 0) value = 0;
            if (value < 10000L)
                return value.ToString(CultureInfo.InvariantCulture);
            if (value < 100000000L)
                return FormatCompactUnit(value, 10000L, "万");
            if (value < 1000000000000L)
                return FormatCompactUnit(value, 100000000L, "亿");
            return FormatCompactUnit(value, 1000000000000L, "万亿");
        }

        private static string FormatCompactUnit(long value, long divisor, string suffix)
        {
            decimal scaled = (decimal)value / divisor;
            return scaled.ToString("0.#", CultureInfo.InvariantCulture) + suffix;
        }

        private static bool TryReadOpaque(JToken token, int maxLength, out string value)
        {
            value = token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
            if (string.IsNullOrEmpty(value) || value.Length > maxLength) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                bool allowed = (c >= 'A' && c <= 'Z')
                    || (c >= 'a' && c <= 'z')
                    || (c >= '0' && c <= '9')
                    || c == '.' || c == '_' || c == '~' || c == '-' || c == ':';
                if (!allowed) return false;
            }
            return true;
        }

        private static bool TryReadText(
            JToken token, int maxLength, bool allowEmpty, out string value)
        {
            value = token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
            if (value == null || value.Length > maxLength
                    || (!allowEmpty && value.Length == 0))
                return false;
            for (int i = 0; i < value.Length; i++)
                if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool TryReadEnum(
            JToken token, HashSet<string> allowed, out string value)
        {
            value = token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
            return value != null && allowed.Contains(value);
        }

        private static bool TryReadBool(JToken token, out bool value)
        {
            value = false;
            if (token == null || token.Type != JTokenType.Boolean) return false;
            value = token.Value<bool>();
            return true;
        }

        private static bool TryReadInt(JToken token, int min, int max, out int value)
        {
            value = 0;
            long candidate;
            if (!TryReadLong(token, min, max, out candidate)) return false;
            value = (int)candidate;
            return true;
        }

        private static bool TryReadLong(JToken token, long min, long max, out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { value = token.Value<long>(); }
            catch { return false; }
            return value >= min && value <= max;
        }

        private static bool HasExactKeys(JObject value, params string[] expected)
        {
            if (value == null || value.Count != expected.Length) return false;
            for (int i = 0; i < expected.Length; i++)
                if (value.Property(expected[i]) == null) return false;
            return true;
        }
    }
}
