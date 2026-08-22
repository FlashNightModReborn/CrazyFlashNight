using System;
using System.Collections.Generic;
using System.Globalization;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Fire-and-forget 玩家物资/击杀 feed 事件处理器（仿 ToastTask）。
    /// v1 物资 payload 固定使用正整数 magnitude，并显式携带
    /// direction/source/itemKey/operationId；无 v 的旧击杀/获得 payload 保持兼容。
    /// 校验后转发到 NativeHud LootFeedWidget。Native 单渲染端，无 sink 抽象。
    /// 非法 payload 记日志并丢弃（fail-closed，不抛、不回包）。
    /// 注意与地图战利品箱的 LootTask（loot_response 回包）是两个域，命名勿混淆。
    ///
    /// 纸娃娃头像（运行时烘焙路线）：payload.doll 为人形斗士外观元组时，
    /// kind=="kill" 的图标键由 DollPortraitKey 单点派生（纸娃娃-&lt;hex&gt;，覆盖 payload.icon），
    /// 并通知 DollPortraitBakeService 异步烘焙（经 WebView2 dressup 渲染器落盘），
    /// 不阻塞 Handle；烘焙失败/桥不可用一律静默降级为占位图标。
    /// </summary>
    public class LootFeedTask
    {
        private const int MaxNameLength = 64;
        private const int MaxIconLength = 128;
        private const long MaxCount = 9007199254740991L;
        private const int MaxDollFieldLength = 64;
        private const int MaxTierLength = 32;
        private const int MaxOperationIdLength = 96;
        private const int MaxMergeScopeLength = 96;
        private const int MaxReasonLength = 48;
        private const int MaxItemKeyLength = 96;
        private const int MaxSourceLength = 48;
        private const int MaxDedupeEntries = 512;

        private static readonly HashSet<string> AllowedKinds = new HashSet<string>(StringComparer.Ordinal)
        {
            "money", "kpoint", "intel", "material", "item", "equip", "kill"
        };

        private static readonly HashSet<string> AllowedSources = new HashSet<string>(StringComparer.Ordinal)
        {
            "pickup", "level_reward", "quest_reward", "achievement_reward",
            "quest_turn_in", "inventory_discard", "equipment_tuning",
            "loot_box", "npc_shop_purchase", "npc_shop_sale", "kshop_purchase",
            "kshop_claim", "crafting", "consumable_effect", "pet_service",
            "mercenary_service", "reload", "skill_cost", "weapon_cost",
            "item_use", "task_entry", "arena_entry", "arena_reward",
            "base_upgrade", "tavern_purchase", "vehicle_service",
            "gym_training", "appearance_service", "player_revive",
            "cheat", "system_reward", "kill", "unknown"
        };

        private static readonly HashSet<string> AllowedDirections =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "gain", "loss", "neutral"
            };

        private readonly LootFeedWidget _widget;
        private readonly IDollBakeSink _dollBakeSink;
        private readonly object _dedupeLock = new object();
        private readonly Dictionary<string, long> _dedupeCounts =
            new Dictionary<string, long>(StringComparer.Ordinal);
        private readonly Queue<string> _dedupeOrder = new Queue<string>();

        internal int DedupeEntryCountForTest
        {
            get { lock (_dedupeLock) return _dedupeCounts.Count; }
        }

        public LootFeedTask(LootFeedWidget widget, IDollBakeSink dollBakeSink = null)
        {
            if (widget == null) throw new ArgumentNullException("widget");
            _widget = widget;
            _dollBakeSink = dollBakeSink;
        }

        public string Handle(JObject message)
        {
            try
            {
                JObject payload = message["payload"] as JObject;
                string kind, name, source, icon, direction, tier, operationId, mergeScope, reason, itemKey;
                long count;
                int eliteLevel;
                Dictionary<string, string> doll;
                if (!TryParsePayload(
                    payload, out kind, out name, out count, out source, out icon,
                    out eliteLevel, out doll, out direction, out tier,
                    out operationId, out mergeScope, out reason, out itemKey))
                    return null;
                if (!AcceptOnce(operationId, direction, kind, itemKey, tier, count,
                    source, reason, mergeScope))
                    return null;
                // 纸娃娃运行时烘焙：doll 元组有效时图标键单点派生，覆盖/忽略 payload.icon
                if (kind == "kill" && doll != null)
                    icon = DollPortraitKey.Compute(doll);
                _widget.AddEvent(kind, name, count, source, icon, eliteLevel,
                    direction, tier, itemKey);
                if (kind == "kill" && doll != null && _dollBakeSink != null)
                {
                    try { _dollBakeSink.EnsurePortrait(doll, icon); }
                    catch (Exception ex) { LogManager.Log("[LootFeed] doll bake enqueue error: " + ex.Message); }
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[LootFeed] Handle error: " + ex.Message);
            }
            return null; // fire-and-forget，不回复 Flash
        }

        /// <summary>
        /// 纯函数校验/规整 payload（InternalsVisibleTo 单测钩子）。
        /// 非法输入记日志并返回 false；v1 count 超界拒绝，legacy 超界兼容 clamp 到 MaxCount。
        /// 不带 doll 的旧签名：保留给既有调用/测试，等价忽略 doll。
        /// </summary>
        internal static bool TryParsePayload(
            JObject payload,
            out string kind, out string name, out long count, out string source, out string icon)
        {
            int eliteLevel;
            Dictionary<string, string> doll;
            return TryParsePayload(
                payload, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll);
        }

        /// <summary>
        /// 含 doll 元组的完整校验：doll 缺失/非对象/字段非法时 out null（整个 doll 忽略），
        /// 不影响 payload 其余字段的判定。
        /// </summary>
        internal static bool TryParsePayload(
            JObject payload,
            out string kind, out string name, out long count, out string source, out string icon,
            out Dictionary<string, string> doll)
        {
            int eliteLevel;
            return TryParsePayload(
                payload, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll);
        }

        /// <summary>
        /// 完整协议校验。eliteLevel 只对 kill 生效，缺失或非法值按普通敌人 0 降级，
        /// 不让一个可选的视觉/调度提示破坏既有击杀事件。
        /// </summary>
        internal static bool TryParsePayload(
            JObject payload,
            out string kind, out string name, out long count, out string source, out string icon,
            out int eliteLevel, out Dictionary<string, string> doll)
        {
            string direction, tier, operationId, mergeScope, reason;
            return TryParsePayload(
                payload, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll, out direction, out tier,
                out operationId, out mergeScope, out reason);
        }

        /// <summary>
        /// 双向玩家物资协议。旧 payload 缺少 direction 时保持兼容：kill 归一 neutral，
        /// 其余归一 gain；loss 必须使用正数 magnitude，不能借负 count 绕过方向语义。
        /// </summary>
        internal static bool TryParsePayload(
            JObject payload,
            out string kind, out string name, out long count, out string source, out string icon,
            out int eliteLevel, out Dictionary<string, string> doll,
            out string direction, out string tier, out string operationId,
            out string mergeScope, out string reason)
        {
            string itemKey;
            return TryParsePayload(
                payload, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll, out direction, out tier,
                out operationId, out mergeScope, out reason, out itemKey);
        }

        internal static bool TryParsePayload(
            JObject payload,
            out string kind, out string name, out long count, out string source, out string icon,
            out int eliteLevel, out Dictionary<string, string> doll,
            out string direction, out string tier, out string operationId,
            out string mergeScope, out string reason, out string itemKey)
        {
            kind = null; name = null; count = 0; source = null; icon = null;
            eliteLevel = 0; doll = null; direction = null; tier = null;
            operationId = null; mergeScope = null; reason = null;
            itemKey = null;
            if (payload == null)
            {
                LogManager.Log("[LootFeed] missing or non-object payload, dropped");
                return false;
            }

            JToken versionToken = payload["v"];
            bool isVersionOne = false;
            // 只有属性完全缺失才属于 legacy；显式 null 也是畸形版本，不能绕过 v1 必填字段。
            if (versionToken != null)
            {
                int version;
                if (versionToken.Type != JTokenType.Integer
                    || !int.TryParse(versionToken.ToString(), NumberStyles.None,
                        CultureInfo.InvariantCulture, out version)
                    || version != 1)
                {
                    LogManager.Log("[LootFeed] unsupported protocol version, dropped");
                    return false;
                }
                isVersionOne = true;
            }

            string rawKind;
            if (isVersionOne)
            {
                if (!TryReadRequiredBoundedString(payload, "kind", 16, out rawKind))
                    return false;
            }
            else
            {
                rawKind = payload.Value<string>("kind");
            }
            if (string.IsNullOrEmpty(rawKind) || !AllowedKinds.Contains(rawKind))
            {
                LogManager.Log("[LootFeed] invalid kind '" + (rawKind ?? "<null>") + "', dropped");
                return false;
            }

            string rawName;
            if (isVersionOne)
            {
                if (!TryReadRequiredBoundedString(
                        payload, "name", MaxNameLength, out rawName))
                    return false;
            }
            else
            {
                rawName = payload.Value<string>("name");
            }
            if (string.IsNullOrEmpty(rawName) || rawName.Length > MaxNameLength)
            {
                LogManager.Log("[LootFeed] invalid name (len=" + (rawName == null ? -1 : rawName.Length) + "), dropped");
                return false;
            }

            long rawCount;
            if (!TryParsePositiveCount(payload["count"], isVersionOne, out rawCount)) return false;

            string rawSource;
            if (isVersionOne)
            {
                if (!TryReadRequiredBoundedString(
                        payload, "source", MaxSourceLength, out rawSource)
                    || !AllowedSources.Contains(rawSource))
                {
                    LogManager.Log("[LootFeed] invalid v1 source, dropped");
                    return false;
                }
            }
            else
            {
                rawSource = payload.Value<string>("source");
                if (string.IsNullOrEmpty(rawSource) || !AllowedSources.Contains(rawSource))
                    rawSource = "unknown";
            }

            string rawDirection;
            if (isVersionOne)
            {
                if (!TryReadRequiredBoundedString(
                        payload, "direction", 8, out rawDirection))
                    return false;
            }
            else
            {
                rawDirection = payload.Value<string>("direction");
                if (string.IsNullOrEmpty(rawDirection))
                    rawDirection = rawKind == "kill" ? "neutral" : "gain";
            }
            if (!AllowedDirections.Contains(rawDirection)
                || (rawKind == "kill" && rawDirection != "neutral")
                || (rawKind != "kill" && rawDirection == "neutral"))
            {
                LogManager.Log("[LootFeed] invalid direction '" + rawDirection + "', dropped");
                return false;
            }

            string rawIcon;
            if (isVersionOne)
            {
                if (!TryReadOptionalBoundedString(
                        payload, "icon", MaxIconLength, out rawIcon))
                    return false;
            }
            else
            {
                rawIcon = payload.Value<string>("icon");
                if (string.IsNullOrEmpty(rawIcon) || rawIcon.Length > MaxIconLength)
                    rawIcon = null;
            }

            string rawTier, rawOperationId, rawMergeScope, rawReason, rawItemKey;
            if (!TryReadOptionalBoundedString(payload, "tier", MaxTierLength, out rawTier)
                || !TryReadOptionalBoundedString(payload, "operationId", MaxOperationIdLength,
                    out rawOperationId)
                || !TryReadOptionalBoundedString(payload, "mergeScope", MaxMergeScopeLength,
                    out rawMergeScope)
                || !TryReadOptionalBoundedString(payload, "reason", MaxReasonLength,
                    out rawReason)
                || !TryReadOptionalBoundedString(payload, "itemKey", MaxItemKeyLength,
                    out rawItemKey))
                return false;
            if (isVersionOne && (string.IsNullOrEmpty(rawOperationId)
                    || string.IsNullOrEmpty(rawItemKey)))
            {
                LogManager.Log("[LootFeed] v1 operationId/itemKey missing, dropped");
                return false;
            }
            if (string.IsNullOrEmpty(rawItemKey)) rawItemKey = rawName;

            if (rawKind == "kill")
            {
                JToken rankToken = payload["eliteLevel"];
                if (rankToken != null && rankToken.Type != JTokenType.Null)
                {
                    if (rankToken.Type == JTokenType.Integer)
                    {
                        int rawRank;
                        if (int.TryParse(rankToken.ToString(), out rawRank)
                            && rawRank >= 0 && rawRank <= 2)
                            eliteLevel = (int)rawRank;
                        else
                            LogManager.Log("[LootFeed] eliteLevel out of range, defaulted to 0");
                    }
                    else
                    {
                        LogManager.Log("[LootFeed] eliteLevel is not an integer, defaulted to 0");
                    }
                }
            }

            kind = rawKind; name = rawName; count = rawCount; source = rawSource; icon = rawIcon;
            direction = rawDirection; tier = rawTier; operationId = rawOperationId;
            mergeScope = rawMergeScope; reason = rawReason;
            itemKey = rawItemKey;
            doll = ParseDoll(payload["doll"]);
            return true;
        }

        private static bool TryReadOptionalBoundedString(
            JObject payload, string propertyName, int maximumLength, out string result)
        {
            result = null;
            JToken token = payload[propertyName];
            if (token == null || token.Type == JTokenType.Null) return true;
            if (token.Type != JTokenType.String)
            {
                LogManager.Log("[LootFeed] " + propertyName + " is not a string, dropped");
                return false;
            }
            string value = token.Value<string>();
            if (string.IsNullOrEmpty(value)) return true;
            if (value.Length > maximumLength)
            {
                LogManager.Log("[LootFeed] " + propertyName + " overlong, dropped");
                return false;
            }
            result = value;
            return true;
        }

        private static bool TryReadRequiredBoundedString(
            JObject payload, string propertyName, int maximumLength, out string result)
        {
            result = null;
            JToken token = payload[propertyName];
            if (token == null || token.Type != JTokenType.String)
            {
                LogManager.Log("[LootFeed] required " + propertyName + " missing/non-string, dropped");
                return false;
            }
            string value = token.Value<string>();
            if (string.IsNullOrEmpty(value) || value.Length > maximumLength)
            {
                LogManager.Log("[LootFeed] required " + propertyName + " invalid, dropped");
                return false;
            }
            result = value;
            return true;
        }

        private static bool TryParsePositiveCount(
            JToken token, bool rejectOverflow, out long count)
        {
            count = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;

            string digits = token.ToString();
            if (string.IsNullOrEmpty(digits) || digits[0] == '-') return false;
            int firstSignificant = 0;
            while (firstSignificant < digits.Length && digits[firstSignificant] == '0')
                firstSignificant++;
            if (firstSignificant == digits.Length) return false;
            digits = digits.Substring(firstSignificant);

            string maximum = MaxCount.ToString(CultureInfo.InvariantCulture);
            if (digits.Length > maximum.Length
                || (digits.Length == maximum.Length
                    && string.CompareOrdinal(digits, maximum) > 0))
            {
                if (rejectOverflow)
                {
                    LogManager.Log("[LootFeed] v1 count exceeds JavaScript safe integer, dropped");
                    return false;
                }
                count = MaxCount;
                return true;
            }
            return long.TryParse(digits, NumberStyles.None,
                CultureInfo.InvariantCulture, out count) && count > 0;
        }

        private bool AcceptOnce(
            string operationId, string direction, string kind, string name,
            string tier, long count, string source, string reason, string mergeScope)
        {
            if (string.IsNullOrEmpty(operationId)) return true;
            string key = BuildDedupeIdentity(operationId, direction, kind, name, tier,
                source, reason, mergeScope);
            lock (_dedupeLock)
            {
                long priorCount;
                if (_dedupeCounts.TryGetValue(key, out priorCount))
                {
                    if (priorCount != count)
                        LogManager.Log("[LootFeed] conflicting replay for committed effect, dropped");
                    return false;
                }
                _dedupeCounts.Add(key, count);
                _dedupeOrder.Enqueue(key);
                while (_dedupeOrder.Count > MaxDedupeEntries)
                    _dedupeCounts.Remove(_dedupeOrder.Dequeue());
            }
            return true;
        }

        internal static string BuildDedupeIdentity(
            string operationId, string direction, string kind, string name,
            string tier, string source, string reason, string mergeScope)
        {
            return LengthKey(operationId) + LengthKey(direction) + LengthKey(kind)
                + LengthKey(name) + LengthKey(tier) + LengthKey(source)
                + LengthKey(reason) + LengthKey(mergeScope);
        }

        private static string LengthKey(string value)
        {
            value = value ?? string.Empty;
            return value.Length + ":" + value + "|";
        }

        /// <summary>
        /// doll 元组校验（InternalsVisibleTo 单测钩子）：必须是 JObject；
        /// 只读 DollPortraitKey.Fields 白名单字段（多余字段忽略），值必须 string 且 ≤64 字符，
        /// 缺字段按 "" 处理；任何已出现字段非法则整个 doll 忽略（返回 null）。
        /// </summary>
        internal static Dictionary<string, string> ParseDoll(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null) return null;
            JObject obj = token as JObject;
            if (obj == null)
            {
                LogManager.Log("[LootFeed] doll is not an object, ignored");
                return null;
            }
            Dictionary<string, string> tuple =
                new Dictionary<string, string>(StringComparer.Ordinal);
            string[] fields = DollPortraitKey.Fields;
            for (int i = 0; i < fields.Length; i++)
            {
                JToken value = obj[fields[i]];
                if (value == null || value.Type == JTokenType.Null)
                {
                    tuple[fields[i]] = string.Empty;
                    continue;
                }
                if (value.Type != JTokenType.String)
                {
                    LogManager.Log("[LootFeed] doll." + fields[i] + " is not a string, doll ignored");
                    return null;
                }
                string s = value.Value<string>();
                if (s != null && s.Length > MaxDollFieldLength)
                {
                    LogManager.Log("[LootFeed] doll." + fields[i] + " overlong (len=" + s.Length + "), doll ignored");
                    return null;
                }
                tuple[fields[i]] = s ?? string.Empty;
            }
            return tuple;
        }
    }
}
