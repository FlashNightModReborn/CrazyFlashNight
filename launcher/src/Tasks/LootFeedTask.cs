using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Fire-and-forget loot feed 事件处理器（仿 ToastTask）。
    /// 接收 Flash 发来的 {"task":"loot","payload":{kind,name,count,source,icon,eliteLevel?,doll?}}
    /// 并转发到 NativeHud LootFeedWidget。Native 单渲染端，无 sink 抽象。
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
        private const long MaxCount = 99999;
        private const int MaxDollFieldLength = 64;

        private static readonly HashSet<string> AllowedKinds = new HashSet<string>(StringComparer.Ordinal)
        {
            "money", "kpoint", "intel", "item", "equip", "kill"
        };

        private static readonly HashSet<string> AllowedSources = new HashSet<string>(StringComparer.Ordinal)
        {
            "pickup", "level_reward", "quest_reward", "loot_box", "kill", "unknown"
        };

        private readonly LootFeedWidget _widget;
        private readonly IDollBakeSink _dollBakeSink;

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
                string kind, name, source, icon;
                long count;
                int eliteLevel;
                Dictionary<string, string> doll;
                if (!TryParsePayload(
                    payload, out kind, out name, out count, out source, out icon,
                    out eliteLevel, out doll))
                    return null;
                // 纸娃娃运行时烘焙：doll 元组有效时图标键单点派生，覆盖/忽略 payload.icon
                if (kind == "kill" && doll != null)
                    icon = DollPortraitKey.Compute(doll);
                _widget.AddEvent(kind, name, count, source, icon, eliteLevel);
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
        /// 非法输入记日志并返回 false；count 越界 clamp 到 (0, MaxCount]。
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
            kind = null; name = null; count = 0; source = null; icon = null;
            eliteLevel = 0; doll = null;
            if (payload == null)
            {
                LogManager.Log("[LootFeed] missing or non-object payload, dropped");
                return false;
            }

            string rawKind = payload.Value<string>("kind");
            if (string.IsNullOrEmpty(rawKind) || !AllowedKinds.Contains(rawKind))
            {
                LogManager.Log("[LootFeed] invalid kind '" + (rawKind ?? "<null>") + "', dropped");
                return false;
            }

            string rawName = payload.Value<string>("name");
            if (string.IsNullOrEmpty(rawName) || rawName.Length > MaxNameLength)
            {
                LogManager.Log("[LootFeed] invalid name (len=" + (rawName == null ? -1 : rawName.Length) + "), dropped");
                return false;
            }

            long rawCount = payload.Value<long?>("count") ?? 0;
            if (rawCount <= 0) return false;
            if (rawCount > MaxCount) rawCount = MaxCount;

            string rawSource = payload.Value<string>("source");
            if (string.IsNullOrEmpty(rawSource) || !AllowedSources.Contains(rawSource))
                rawSource = "unknown";

            string rawIcon = payload.Value<string>("icon");
            if (string.IsNullOrEmpty(rawIcon) || rawIcon.Length > MaxIconLength)
                rawIcon = null;

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
            doll = ParseDoll(payload["doll"]);
            return true;
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
