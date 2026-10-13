using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.Guardian;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>
    /// 按存档的 NPC 日常对话覆盖层（AI 聊天终端阶段四 G4-4）。
    ///
    /// 落点 data/rag/agent_saves/&lt;slotKey&gt;/dialogue_overrides.json，由后端按存档原子写出，宿主只读，键名冻结：
    ///   - action "replace"：按 (NPC 名, base_dialogue_id) 在基础组列表里定位一组，整组替换它的 SubDialogues；
    ///     TaskRequirement 与 GroupId 沿用被替换的那一组。
    ///   - action "append"：在该 NPC 组列表末尾追加一个新组，GroupId 取条目的 group_id（后端已分配，形如 agent_1），
    ///     TaskRequirement 固定 0（始终可用）；同 group_id 已存在（重复应用 / 后端改写同一条目）时按 (NPC 名, group_id)
    ///     定位并整组替换，不追加出重复组。
    /// 数组按顺序应用，后应用的赢。NPC 名匹配 &lt;Dialogues&gt;&lt;Name&gt; 原文（大小写敏感、不归一化），
    /// 因为游戏查询用的 key 就是它。
    ///
    /// 失败口径（fail-closed）：文件不存在＝该存档没有增量，静默跳过；文件存在但解析失败＝记 error 并当作没有覆盖层
    /// （保留基础数据，绝不拿半份数据糊过去，也绝不抛到查询路径让 NPC 没有对话）；定位不到或条目畸形＝记警告跳过该条，
    /// 不丢整份覆盖层，也不让基础数据加载失败。
    ///
    /// 缓存与 base 严格隔离：DataCache 的 base 索引是进程级缓存且加载失败也永不复位，这里只按
    /// (projectRoot, slotKey, 文件 LastWriteTimeUtc + Length) 缓存覆盖层的解析结果，绝不触碰 base 缓存；
    /// 合并返回新字典并对被改动的组做深拷贝，base 字典与其中的 JArray 永不被就地修改。
    /// </summary>
    public sealed class AgentDialogueOverrides
    {
        /// <summary>覆盖层文件名（与后端写盘同名，命名冻结，不得改）。</summary>
        internal const string OverlayFileName = "dialogue_overrides.json";

        /// <summary>单文件条目上限；超出部分忽略并记警告。</summary>
        internal const int MaxEntriesPerFile = 200;

        private static readonly IReadOnlyList<OverrideEntry> NoEntries = new OverrideEntry[0];

        // 进程级共享缓存：DataQueryTask.HandleAsync 在 ThreadPool 中执行，同一存档的并发查询必须命中同一份解析结果。
        // 键含 projectRoot，于是测试用的临时根与真实根互不干扰；Invalidate() 整体清掉（换槽位 / 收到刷新信号）。
        private static readonly ConcurrentDictionary<string, CacheEntry> Cache =
            new ConcurrentDictionary<string, CacheEntry>(StringComparer.Ordinal);
        private static readonly object ParseGate = new object();

        private readonly string _projectRoot;

        public AgentDialogueOverrides(string projectRoot)
        {
            _projectRoot = projectRoot;
        }

        /// <summary>
        /// 把当前存档的覆盖层应用到 base 索引，返回合并后的新字典。
        /// base 为 null（基础数据加载失败）原样返回 null；未绑定槽位或该存档没有覆盖层时原样返回 base（不拷贝、零开销）。
        /// </summary>
        public Dictionary<string, List<DialogueGroup>> Apply(
            string slotKey, Dictionary<string, List<DialogueGroup>> baseIndex)
        {
            if (baseIndex == null) return null;
            try
            {
                IReadOnlyList<OverrideEntry> entries = LoadEntries(slotKey);
                if (entries == null || entries.Count == 0) return baseIndex;
                return Merge(baseIndex, entries, slotKey);
            }
            catch (Exception ex)
            {
                // 覆盖层永远不能让 NPC 没有对话：任何意外都退回基础数据。
                LogManager.Log("[AgentDialogueOverrides] ERROR apply failed slot=" + (slotKey ?? "") + ": " + ex);
                return baseIndex;
            }
        }

        /// <summary>显式失效：换槽位或收到后端刷新信号时清掉覆盖层缓存，下次查询按文件当前指纹重读。</summary>
        public static void Invalidate()
        {
            Cache.Clear();
        }

        /// <summary>测试可观测：当前缓存了几个 (projectRoot, slotKey) 的解析结果。</summary>
        internal static int CachedSlotCount { get { return Cache.Count; } }

        /// <summary>
        /// 覆盖层文件绝对路径。槽位为空或非槽位键形态时返回 null——不派生路径，
        /// 与任务覆盖层同一口径（绑定与写盘两侧只接受同一形态）。
        /// </summary>
        internal string OverlayPath(string slotKey)
        {
            string valid;
            if (string.IsNullOrEmpty(_projectRoot)
                || !SaveSlotKey.TryValidateExisting(slotKey ?? "", out valid))
                return null;
            return Path.Combine(_projectRoot, "data", "rag", "agent_saves", valid, OverlayFileName);
        }

        private string CacheKey(string slotKey)
        {
            return _projectRoot + "\n" + slotKey;
        }

        /// <summary>按文件指纹取解析结果；文件没变直接用缓存，变了才重读。null＝没有可用覆盖层。</summary>
        private IReadOnlyList<OverrideEntry> LoadEntries(string slotKey)
        {
            string path = OverlayPath(slotKey);
            if (path == null) return null;

            DateTime stampUtc;
            long length;
            try
            {
                FileInfo info = new FileInfo(path);
                // 文件不存在＝正常：该存档没有增量，静默跳过（不记 error）。
                if (!info.Exists) return null;
                stampUtc = info.LastWriteTimeUtc;
                length = info.Length;
            }
            catch (Exception ex)
            {
                LogManager.Log("[AgentDialogueOverrides] stat failed slot=" + slotKey + ": " + ex.Message);
                return null;
            }

            string cacheKey = CacheKey(slotKey);
            CacheEntry cached;
            if (Cache.TryGetValue(cacheKey, out cached) && cached.StampUtc == stampUtc && cached.Length == length)
                return cached.Entries;

            lock (ParseGate)
            {
                if (Cache.TryGetValue(cacheKey, out cached) && cached.StampUtc == stampUtc && cached.Length == length)
                    return cached.Entries;
                IReadOnlyList<OverrideEntry> entries = ParseOverlayFile(path, slotKey);
                // 解析失败也按指纹缓存：同一份坏文件不会在每次查询时重解析、重复报错。
                Cache[cacheKey] = new CacheEntry(stampUtc, length, entries);
                return entries;
            }
        }

        private static IReadOnlyList<OverrideEntry> ParseOverlayFile(string path, string slotKey)
        {
            JObject document;
            try
            {
                document = JObject.Parse(File.ReadAllText(path));
            }
            catch (Exception ex)
            {
                LogManager.Log("[AgentDialogueOverrides] ERROR parse failed slot=" + slotKey
                    + " path=" + path + ": " + ex.Message);
                return null;
            }

            JToken overridesToken = document["overrides"];
            if (overridesToken == null || overridesToken.Type == JTokenType.Null)
                return NoEntries;

            JArray array = overridesToken as JArray;
            if (array == null)
            {
                LogManager.Log("[AgentDialogueOverrides] ERROR overrides 不是数组 slot=" + slotKey
                    + " path=" + path + " type=" + overridesToken.Type);
                return null;
            }

            int limit = Math.Min(array.Count, MaxEntriesPerFile);
            if (array.Count > MaxEntriesPerFile)
                LogManager.Log("[AgentDialogueOverrides] 条目超上限 slot=" + slotKey
                    + " count=" + array.Count + " limit=" + MaxEntriesPerFile + "（超出部分已忽略）");

            List<OverrideEntry> entries = new List<OverrideEntry>(limit);
            for (int i = 0; i < limit; i++)
            {
                OverrideEntry entry = ParseEntry(array[i], i, slotKey);
                if (entry != null) entries.Add(entry);
            }
            return entries;
        }

        /// <summary>解析并校验一条覆盖条目；畸形条目记警告后返回 null（只跳过该条）。</summary>
        private static OverrideEntry ParseEntry(JToken token, int index, string slotKey)
        {
            JObject source = token as JObject;
            if (source == null)
            {
                Warn(index, slotKey, "条目不是对象");
                return null;
            }

            string npc = StringField(source, "npc");
            if (string.IsNullOrEmpty(npc))
            {
                Warn(index, slotKey, "缺少 npc");
                return null;
            }

            string action = StringField(source, "action");
            bool append = string.Equals(action, "append", StringComparison.Ordinal);
            if (!append && !string.Equals(action, "replace", StringComparison.Ordinal))
            {
                Warn(index, slotKey, "action 不是 replace/append：" + (action ?? "<null>") + " npc=" + npc);
                return null;
            }

            // replace 用基础组 id 定位，append 用后端分配的 group_id；两者都必须是 JSON 字符串。
            string groupId = StringField(source, append ? "group_id" : "base_dialogue_id");
            if (string.IsNullOrEmpty(groupId))
            {
                Warn(index, slotKey, (append ? "append 缺少 group_id" : "replace 缺少 base_dialogue_id")
                    + " npc=" + npc);
                return null;
            }

            JArray rawSubs = source["subdialogues"] as JArray;
            if (rawSubs == null)
            {
                Warn(index, slotKey, "subdialogues 不是数组 npc=" + npc);
                return null;
            }

            JArray subs = new JArray();
            for (int i = 0; i < rawSubs.Count; i++)
            {
                JObject sub = NormalizeSubDialogue(rawSubs[i] as JObject);
                if (sub == null)
                {
                    Warn(index, slotKey, "第 " + i + " 句不是对象或缺 Text，已跳过 npc=" + npc);
                    continue;
                }
                subs.Add(sub);
            }
            if (subs.Count == 0)
            {
                // 一句可用台词都没有：整条跳过，不把基础组替换成空对话。
                Warn(index, slotKey, "没有可用台词，整条跳过 npc=" + npc);
                return null;
            }

            return new OverrideEntry(append, npc, groupId, subs);
        }

        /// <summary>
        /// 覆盖层台词归一化成 XmlDataLoader 的同形输出（id/name/title/char/text/target/imageurl 全小写）：
        /// AS2 的 _root.组装单次对话 读的就是这套小写字段，而本次设计前提是 AS2 零改动、返回结构逐字不变。
        /// 后端写的是 PascalCase（Name/Title/Char/Text），两种大小写都接受；缺 Text 返回 null 由调用方丢弃。
        /// char 缺失时给空串而不是 null，因为 AS2 会直接对它 split("#")。
        /// </summary>
        private static JObject NormalizeSubDialogue(JObject source)
        {
            if (source == null) return null;
            string text = StringField(source, "Text") ?? StringField(source, "text");
            if (string.IsNullOrEmpty(text)) return null;

            JObject sub = new JObject();
            sub["id"] = StringField(source, "Id") ?? StringField(source, "id") ?? "";
            sub["name"] = StringField(source, "Name") ?? StringField(source, "name") ?? "";
            sub["title"] = StringField(source, "Title") ?? StringField(source, "title") ?? "";
            sub["char"] = StringField(source, "Char") ?? StringField(source, "char") ?? "";
            sub["text"] = text;
            sub["target"] = OptionalField(source, "Target", "target");
            sub["imageurl"] = OptionalField(source, "ImageUrl", "imageurl");
            return sub;
        }

        /// <summary>target / imageurl 与基础数据同口径：字段不存在时输出 null。</summary>
        private static JToken OptionalField(JObject source, string pascalName, string lowerName)
        {
            string value = StringField(source, pascalName) ?? StringField(source, lowerName);
            return value != null ? (JToken)value : JValue.CreateNull();
        }

        /// <summary>只接受 JSON 字符串；缺字段、null 或其他类型一律视为缺失，不把数字或对象误当 id / 台词。</summary>
        private static string StringField(JObject source, string name)
        {
            JToken token = source[name];
            return token != null && token.Type == JTokenType.String ? (string)token : null;
        }

        private static void Warn(int index, string slotKey, string reason)
        {
            LogManager.Log("[AgentDialogueOverrides] 跳过条目 slot=" + slotKey
                + " index=" + index + " reason=" + reason);
        }

        /// <summary>
        /// 按顺序应用条目，后应用的赢。base 是进程级缓存：只有被覆盖层触及的 NPC 才 copy-on-write 它的组列表，
        /// 被改动的组一律是新对象、台词是新克隆，base 字典里的对象永不被就地修改。
        /// </summary>
        private static Dictionary<string, List<DialogueGroup>> Merge(
            Dictionary<string, List<DialogueGroup>> baseIndex,
            IReadOnlyList<OverrideEntry> entries, string slotKey)
        {
            Dictionary<string, List<DialogueGroup>> merged =
                new Dictionary<string, List<DialogueGroup>>(baseIndex.Count + entries.Count, StringComparer.Ordinal);
            foreach (KeyValuePair<string, List<DialogueGroup>> pair in baseIndex)
                merged[pair.Key] = pair.Value;

            // 已经与 base 脱钩（复制过组列表）的 NPC，避免重复拷贝。
            HashSet<string> detached = new HashSet<string>(StringComparer.Ordinal);

            for (int i = 0; i < entries.Count; i++)
            {
                OverrideEntry entry = entries[i];
                List<DialogueGroup> groups;
                merged.TryGetValue(entry.Npc, out groups);

                if (!entry.Append)
                {
                    if (groups == null)
                    {
                        LogManager.Log("[AgentDialogueOverrides] replace 跳过：NPC 不在基础数据 slot=" + slotKey
                            + " npc=" + entry.Npc + " base_dialogue_id=" + entry.GroupId);
                        continue;
                    }
                    int index = IndexOfGroupId(groups, entry.GroupId);
                    if (index < 0)
                    {
                        LogManager.Log("[AgentDialogueOverrides] replace 跳过：组 id 不存在 slot=" + slotKey
                            + " npc=" + entry.Npc + " base_dialogue_id=" + entry.GroupId);
                        continue;
                    }
                    groups = Detach(merged, detached, entry.Npc, groups);
                    DialogueGroup target = groups[index];
                    groups[index] = new DialogueGroup
                    {
                        // 门控与组 id 沿用被替换的那一组，只换台词。
                        TaskRequirement = target != null ? target.TaskRequirement : 0,
                        GroupId = target != null ? target.GroupId : entry.GroupId,
                        SubDialogues = (JArray)entry.SubDialogues.DeepClone()
                    };
                    continue;
                }

                if (groups == null)
                {
                    // 基础数据里没有这个 NPC：建一个只含覆盖层组的条目，不影响任何其他 NPC 的查询结果。
                    groups = new List<DialogueGroup>();
                    merged[entry.Npc] = groups;
                    detached.Add(entry.Npc);
                }
                else
                {
                    groups = Detach(merged, detached, entry.Npc, groups);
                }

                int existing = IndexOfGroupId(groups, entry.GroupId);
                DialogueGroup appended = new DialogueGroup
                {
                    // 新增组始终可用（TaskRequirement 0）；命中既有 group_id 时沿用它的门控，与 replace 同口径。
                    TaskRequirement = existing >= 0 && groups[existing] != null ? groups[existing].TaskRequirement : 0,
                    GroupId = entry.GroupId,
                    SubDialogues = (JArray)entry.SubDialogues.DeepClone()
                };
                if (existing >= 0) groups[existing] = appended;
                else groups.Add(appended);
            }

            return merged;
        }

        private static List<DialogueGroup> Detach(
            Dictionary<string, List<DialogueGroup>> merged, HashSet<string> detached,
            string npc, List<DialogueGroup> groups)
        {
            if (detached.Contains(npc)) return groups;
            List<DialogueGroup> copy = new List<DialogueGroup>(groups);
            merged[npc] = copy;
            detached.Add(npc);
            return copy;
        }

        /// <summary>组 id 精确匹配（ordinal）。基础组 id 是纯数字串，append 组是 agent_&lt;n&gt;，两者不会相撞。</summary>
        private static int IndexOfGroupId(List<DialogueGroup> groups, string groupId)
        {
            for (int i = 0; i < groups.Count; i++)
            {
                DialogueGroup group = groups[i];
                if (group != null && string.Equals(group.GroupId, groupId, StringComparison.Ordinal))
                    return i;
            }
            return -1;
        }

        /// <summary>缓存条目：文件指纹 + 解析结果（不可变，可跨查询共享；合并时再克隆台词）。</summary>
        private sealed class CacheEntry
        {
            internal readonly DateTime StampUtc;
            internal readonly long Length;
            internal readonly IReadOnlyList<OverrideEntry> Entries;

            internal CacheEntry(DateTime stampUtc, long length, IReadOnlyList<OverrideEntry> entries)
            {
                StampUtc = stampUtc;
                Length = length;
                Entries = entries;
            }
        }

        /// <summary>一条已校验、已归一化的覆盖条目。</summary>
        private sealed class OverrideEntry
        {
            internal readonly bool Append;
            internal readonly string Npc;
            internal readonly string GroupId;
            internal readonly JArray SubDialogues;

            internal OverrideEntry(bool append, string npc, string groupId, JArray subDialogues)
            {
                Append = append;
                Npc = npc;
                GroupId = groupId;
                SubDialogues = subDialogues;
            }
        }
    }
}
