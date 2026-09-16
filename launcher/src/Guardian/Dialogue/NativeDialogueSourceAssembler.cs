using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Data;

namespace CF7Launcher.Guardian.Dialogue
{
    /// <summary>
    /// wire v2 source book（kind:"source"）的 C# 侧静态源装配器接缝。
    /// 行元素 = 与 inline book lines[] 完全一致的 wire 行形状 JObject
    /// （name/title/text/portrait{kind,key,expression,appearance?}/imageAction/imagePath）。
    /// 宿主 book 的 Line 表示由并行任务定义，本接口只产出 wire 形状；
    /// 若宿主需要强类型行，可在不改动装配语义的前提下收窄签名。
    /// </summary>
    internal interface INativeDialogueSourceAssembler
    {
        /// <summary>
        /// 按 sourceRef 装配行集。成功返回 true 且 rejectReason==null；
        /// 失败返回 false，rejectReason ∈ {unknown_source, source_unavailable,
        /// group_missing, content_drift, empty_source}。
        /// </summary>
        bool TryAssemble(JObject sourceRef, JObject snapshot,
            out List<JObject> lines, out int rowCount, out string rejectReason);
    }

    /// <summary>
    /// npc_dialogue source book 装配器（纯函数式、无会话状态）。
    ///
    /// sourceRef 形状（冻结接缝，M3 纵向切片）：
    ///   { "type":"npc_dialogue", "key":"酒泡氤氲-啤酒", "group":0,
    ///     "contentVersion":"&lt;64hex sha256 小写&gt;", "taskProgress":&lt;int 可选&gt; }
    ///
    /// 取数与过滤：复用 DataCache.GetNpcDialogues() 的解析结果
    /// （Dictionary&lt;NPC名, List&lt;DialogueGroup&gt;&gt;，组保持 XML 声明顺序）。
    /// taskProgress 缺省 = 不过滤（与旧 读取NPC对话 的无进度上下文一致）；
    /// 携带整数时与 AS2 读取NPC对话 逐行同构：TaskRequirement &gt; taskProgress → 跳过，
    /// group 下标作用于过滤后的投影。非整数的 taskProgress 按 0 处理（宁严勿宽，
    /// 绝不因畸形字段放出任务门槛更高的组）。
    ///
    /// 拒绝顺序（越靠前的拒绝越基础）：
    ///   type 缺失/非 "npc_dialogue"      → unknown_source
    ///   DataCache 索引加载失败            → source_unavailable
    ///   contentVersion 缺失/与重算不符    → content_drift（内容身份先于一组一行）
    ///   key 不存在 / group 越界或畸形     → group_missing
    ///   选中组解析后行数为 0              → empty_source
    ///
    /// contentVersion 口径（npc_dialogue 源，确定性：同一解析数据必得同一值）：
    ///   1) 取完整 NPC 对话索引；NPC 名按 StringComparer.Ordinal 升序，
    ///      组与行保持解析顺序；
    ///   2) 规范化序列化为 JSON：
    ///      root = JArray[[ npcName, groups ], ...]
    ///      groups = JArray[{ "taskRequirement":&lt;int&gt;, "lines":JArray }, ...]
    ///      每行 = JObject 固定七键序 id,name,title,char,text,target,imageurl，
    ///      值取解析出的 JToken 深克隆（string 或 null）；
    ///   3) contentVersion = SHA-256(UTF-8(root.ToString(Formatting.None)))
    ///      小写 hex。
    ///   该口径是语义哈希：仅排版变化的 XML 编辑不造成漂移，任何真实内容
    ///   变化都会改变值。宿主可用 ComputeContentVersion 把当前版本告知 AS2。
    ///
    /// 行装配（data 行 → wire 行），与旧 sendLine 出口同构：
    ///   name/title："$PC"→snapshot.playerName、"$PC_TITLE"→snapshot.heroTitle
    ///     （不实现 getHeroTitle 优先链，快照给什么用什么）；"角色名" 哨兵与
    ///     "$PC_CHAR" 在 name/title 中不复刻、原样透传；缺失/非字符串 → ""。
    ///   portrait：Char 按 '#' 切分（base#expr，expr 缺省或空串 → "普通"）。
    ///     base ∈ {"$PC_CHAR","玩家","主角模板"} → 深克隆 snapshot.heroPortrait
    ///     直接使用（kind=doll、appearance 原样），行内显式 #expr 覆盖其
    ///     expression；heroPortrait 缺失/非对象 → 空静态槽（同旧 appearance==null
    ///     分支，保行不拒句）。其余 → {kind:"static",key:base,expression:expr}。
    ///     Char 缺失/空 → {kind:"static",key:"",expression:"普通"}。
    ///   imageurl 三态与 v1 sendLine 同构：非空字符串 "close"→clear，其余非空
    ///     →show+imagePath，空/缺失/非字符串→keep；text 原样不过占位符。
    ///   输入 JObject 不保留引用：heroPortrait 深克隆进输出行，行内容全部物化。
    /// </summary>
    internal sealed class NativeDialogueSourceAssembler : INativeDialogueSourceAssembler
    {
        internal const string ReasonUnknownSource = "unknown_source";
        internal const string ReasonSourceUnavailable = "source_unavailable";
        internal const string ReasonGroupMissing = "group_missing";
        internal const string ReasonContentDrift = "content_drift";
        internal const string ReasonEmptySource = "empty_source";

        private static readonly string[] SubFields =
            { "id", "name", "title", "char", "text", "target", "imageurl" };

        private readonly DataCache _cache;

        internal NativeDialogueSourceAssembler(DataCache cache)
        {
            _cache = cache ?? throw new ArgumentNullException(nameof(cache));
        }

        public bool TryAssemble(JObject sourceRef, JObject snapshot,
            out List<JObject> lines, out int rowCount, out string rejectReason)
        {
            lines = null;
            rowCount = 0;
            rejectReason = null;

            if (sourceRef == null || sourceRef.Value<string>("type") != "npc_dialogue")
            {
                rejectReason = ReasonUnknownSource;
                return false;
            }

            Dictionary<string, List<DialogueGroup>> index = _cache.GetNpcDialogues();
            if (index == null)
            {
                rejectReason = ReasonSourceUnavailable;
                return false;
            }

            string expectedVersion = sourceRef.Value<string>("contentVersion");
            if (expectedVersion == null
                || !string.Equals(expectedVersion, ComputeContentVersion(index), StringComparison.Ordinal))
            {
                rejectReason = ReasonContentDrift;
                return false;
            }

            string key = sourceRef.Value<string>("key");
            List<DialogueGroup> all;
            if (key == null || !index.TryGetValue(key, out all))
            {
                rejectReason = ReasonGroupMissing;
                return false;
            }

            // taskProgress：整数 → 与 读取NPC对话 同构过滤（TR > progress 跳过）；
            // 缺省 → 不过滤；非整数 → 按 0（最严，绝不因畸形放出高门槛组）。
            List<DialogueGroup> filtered = all;
            JToken progressToken = sourceRef["taskProgress"];
            if (progressToken != null && progressToken.Type != JTokenType.Null)
            {
                int progress = progressToken.Type == JTokenType.Integer ? progressToken.Value<int>() : 0;
                filtered = new List<DialogueGroup>(all.Count);
                for (int i = 0; i < all.Count; i++)
                {
                    if (all[i].TaskRequirement > progress) continue;
                    filtered.Add(all[i]);
                }
            }

            int groupIndex = 0;
            JToken groupToken = sourceRef["group"];
            if (groupToken != null && groupToken.Type != JTokenType.Null)
            {
                if (groupToken.Type != JTokenType.Integer)
                {
                    rejectReason = ReasonGroupMissing;
                    return false;
                }
                groupIndex = groupToken.Value<int>();
            }
            if (groupIndex < 0 || groupIndex >= filtered.Count)
            {
                rejectReason = ReasonGroupMissing;
                return false;
            }

            JArray rows = filtered[groupIndex].SubDialogues;
            var assembled = new List<JObject>(rows?.Count ?? 0);
            if (rows != null)
            {
                for (int i = 0; i < rows.Count; i++)
                    assembled.Add(AssembleLine(rows[i] as JObject, snapshot));
            }
            if (assembled.Count == 0)
            {
                rejectReason = ReasonEmptySource;
                return false;
            }

            lines = assembled;
            rowCount = assembled.Count;
            return true;
        }

        /// <summary>
        /// npc_dialogue 源的内容版本：完整索引的规范化序列化 SHA-256（小写 hex）。
        /// 口径见类注；index 为 null 时抛 ArgumentNullException（调用方先判
        /// source_unavailable）。
        /// </summary>
        internal static string ComputeContentVersion(
            Dictionary<string, List<DialogueGroup>> index)
        {
            if (index == null) throw new ArgumentNullException(nameof(index));

            var names = new List<string>(index.Keys);
            names.Sort(StringComparer.Ordinal);

            var root = new JArray();
            foreach (string name in names)
            {
                var groups = new JArray();
                foreach (DialogueGroup group in index[name])
                {
                    var groupLines = new JArray();
                    if (group.SubDialogues != null)
                    {
                        foreach (JToken token in group.SubDialogues)
                        {
                            JObject sub = token as JObject;
                            var canonical = new JObject();
                            foreach (string field in SubFields)
                                canonical[field] = sub?[field]?.DeepClone() ?? JValue.CreateNull();
                            groupLines.Add(canonical);
                        }
                    }
                    groups.Add(new JObject
                    {
                        ["taskRequirement"] = group.TaskRequirement,
                        ["lines"] = groupLines
                    });
                }
                root.Add(new JArray { name, groups });
            }

            byte[] bytes = Encoding.UTF8.GetBytes(root.ToString(Formatting.None));
            using (SHA256 sha = SHA256.Create())
                return Convert.ToHexString(sha.ComputeHash(bytes)).ToLowerInvariant();
        }

        private static JObject AssembleLine(JObject row, JObject snapshot)
        {
            var line = new JObject();
            line["name"] = ResolveSpeakerToken(row?["name"], snapshot);
            line["title"] = ResolveSpeakerToken(row?["title"], snapshot);
            line["text"] = StringOf(row?["text"]);
            line["portrait"] = BuildPortrait(row?["char"], snapshot);

            string image = row?["imageurl"]?.Type == JTokenType.String
                ? row["imageurl"].Value<string>() : null;
            if (string.IsNullOrEmpty(image))
            {
                line["imageAction"] = "keep";
                line["imagePath"] = "";
            }
            else if (image == "close")
            {
                line["imageAction"] = "clear";
                line["imagePath"] = "";
            }
            else
            {
                line["imageAction"] = "show";
                line["imagePath"] = image;
            }
            return line;
        }

        /// <summary>name/title 占位符：仅 $PC/$PC_TITLE 走快照，其余原样透传。</summary>
        private static string ResolveSpeakerToken(JToken token, JObject snapshot)
        {
            string s = StringOf(token);
            if (s == "$PC") return snapshot?.Value<string>("playerName") ?? "";
            if (s == "$PC_TITLE") return snapshot?.Value<string>("heroTitle") ?? "";
            return s;
        }

        /// <summary>
        /// char 字段 → portrait。hero 占位直接用 snapshot.heroPortrait（深克隆），
        /// 行内 #expr 显式给出时覆盖其 expression；快照缺 expression 时补 "普通"。
        /// heroPortrait 缺席 → 空静态槽（对齐旧 appearance==null 的保行语义）。
        /// </summary>
        private static JObject BuildPortrait(JToken charToken, JObject snapshot)
        {
            string charField = StringOf(charToken);
            string[] parts = charField.Split('#');
            string charBase = parts[0];
            string explicitExpr = parts.Length > 1 ? parts[1] : null;
            string expression = string.IsNullOrEmpty(explicitExpr) ? "普通" : explicitExpr;

            if (charBase == "$PC_CHAR" || charBase == "玩家" || charBase == "主角模板")
            {
                JObject hero = snapshot?["heroPortrait"] as JObject;
                if (hero == null)
                {
                    return new JObject
                    {
                        ["kind"] = "static", ["key"] = "", ["expression"] = expression
                    };
                }
                var portrait = (JObject)hero.DeepClone();
                if (!string.IsNullOrEmpty(explicitExpr))
                    portrait["expression"] = explicitExpr;
                else if (StringOf(portrait["expression"]).Length == 0)
                    portrait["expression"] = "普通";
                return portrait;
            }

            return new JObject
            {
                ["kind"] = "static", ["key"] = charBase, ["expression"] = expression
            };
        }

        /// <summary>
        /// 字符串字段物化。XmlDataLoader 会把缺失子元素写成 String 型 null 值
        /// （JValue Type=String / Value=null），与 Null 型一并归一为 ""。
        /// </summary>
        private static string StringOf(JToken token)
        {
            if (token?.Type != JTokenType.String) return "";
            return token.Value<string>() ?? "";
        }
    }
}
