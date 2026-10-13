using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Data;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// data_query async handler：Flash 按需查询 NPC 对话 / 佣兵配置等非战斗数据。
    /// 数据从项目 XML 文件解析，由 DataCache 延迟加载并缓存。
    /// NPC 日常对话在返回前叠加按存档的 Agent 覆盖层（AgentDialogueOverrides），返回结构逐字不变。
    ///
    /// 协议：
    ///   请求 payload: { dataType: "npc_dialogue"|"merc_bundle"|"enemy_dialogues", key: ..., taskProgress: ... }
    ///   响应: { success: true, task: "data_query", result: ... }
    ///      或 { success: false, task: "data_query", error: "..." }
    /// </summary>
    public class DataQueryTask
    {
        private readonly DataCache _cache;
        private readonly AgentDialogueOverrides _overrides;

        public DataQueryTask(DataCache cache) : this(cache, null)
        {
        }

        /// <summary>overrides 只为测试注入；缺省按 DataCache 的项目根构造，覆盖层缓存本身是进程级共享的。</summary>
        internal DataQueryTask(DataCache cache, AgentDialogueOverrides overrides)
        {
            _cache = cache;
            _overrides = overrides ?? new AgentDialogueOverrides(cache != null ? cache.ProjectRoot : null);
        }

        public void HandleAsync(JObject message, Action<string> respond)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    string result = Process(message);
                    respond(result);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[DataQueryTask] Exception: " + ex);
                    respond(BuildError("data_query exception: " + ex.Message));
                }
            });
        }

        private string Process(JObject message)
        {
            JObject payload = message.Value<JObject>("payload");
            if (payload == null)
                return BuildError("missing payload");

            string dataType = payload.Value<string>("dataType");
            if (dataType == null)
                return BuildError("missing dataType");

            switch (dataType)
            {
                case "npc_dialogue":
                    return QueryNpcDialogue(payload);
                case "merc_bundle":
                    return QueryMercBundle();
                case "enemy_dialogues":
                    return QueryEnemyDialogues();
                default:
                    return BuildError("unknown dataType: " + dataType);
            }
        }

        /// <summary>
        /// NPC 对话查询。
        /// 数据加载失败 → success:false（Flash 走 legacy fallback）。
        /// NPC 不存在或无匹配条目 → success:true, result:[]（匹配 legacy 正常行为）。
        /// </summary>
        private string QueryNpcDialogue(JObject payload)
        {
            string npcName = payload.Value<string>("key");
            int taskProgress = payload.Value<int>("taskProgress");

            Dictionary<string, List<DialogueGroup>> index = _cache.GetNpcDialogues();

            // 数据加载失败（缓存了错误状态）→ Flash 走 fallback
            if (index == null)
                return BuildError("NPC data unavailable: " + (_cache.GetNpcError() ?? "unknown"));

            // 按存档的 Agent 对话覆盖层（阶段四 G4-4）：在 base 之后、TaskRequirement 过滤之前套用。
            // 只读当前绑定槽位的增量文件，返回的是新字典（base 缓存永不被就地修改）；
            // 未绑定槽位或该存档没有覆盖层文件时原样返回 base，行为与现状逐字一致。
            index = _overrides.Apply(CF7Launcher.RagTerminal.AgentSaveContext.CurrentSlotKey, index);

            // NPC 不存在 → success:true, result:[]
            List<DialogueGroup> groups;
            if (npcName == null || !index.TryGetValue(npcName, out groups))
                return BuildSuccess(new JArray());

            // 过滤：TaskRequirement > taskProgress → 跳过
            JArray result = new JArray();
            for (int i = 0; i < groups.Count; i++)
            {
                DialogueGroup g = groups[i];
                if (g.TaskRequirement > taskProgress) continue;
                result.Add(g.SubDialogues);
            }
            return BuildSuccess(result);
        }

        private string QueryMercBundle()
        {
            JObject bundle = _cache.GetMercBundle();

            // 数据加载失败（缓存了错误状态）→ Flash 走 fallback
            if (bundle == null)
                return BuildError("merc_bundle unavailable: " + (_cache.GetMercError() ?? "unknown"));

            return BuildSuccess(bundle);
        }

        /// <summary>
        /// 非人形佣兵对话查询。返回全量数据（按身份分组）。
        /// </summary>
        private string QueryEnemyDialogues()
        {
            JObject data = _cache.GetEnemyDialogues();
            if (data == null)
                return BuildError("enemy_dialogues unavailable: " + (_cache.GetEnemyDlgError() ?? "unknown"));

            return BuildSuccess(data);
        }


        /// <summary>成功响应。DataQueryTask 内部私有辅助方法。</summary>
        private static string BuildSuccess(JToken result)
        {
            JObject obj = new JObject();
            obj["success"] = true;
            obj["task"] = "data_query";
            obj["result"] = result;
            return obj.ToString(Formatting.None);
        }

        /// <summary>错误响应。DataQueryTask 内部私有辅助方法。</summary>
        private static string BuildError(string error)
        {
            JObject obj = new JObject();
            obj["success"] = false;
            obj["task"] = "data_query";
            obj["error"] = error;
            return obj.ToString(Formatting.None);
        }
    }
}
