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
    ///
    /// 协议：
    ///   请求 payload: { dataType: "npc_dialogue"|"merc_bundle", key: ..., taskProgress: ... }
    ///   响应: { success: true, task: "data_query", result: ... }
    ///      或 { success: false, task: "data_query", error: "..." }
    /// </summary>
    public class DataQueryTask
    {
        private readonly DataCache _cache;

        public DataQueryTask(DataCache cache)
        {
            _cache = cache;
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
                default:
                    return BuildError("unknown dataType: " + dataType);
            }
        }

        /// <summary>
        /// NPC 对话查询。
        /// NPC 不存在或无匹配条目时返回 success:true, result:[]（匹配 legacy 行为）。
        /// </summary>
        private string QueryNpcDialogue(JObject payload)
        {
            string npcName = payload.Value<string>("key");
            int taskProgress = payload.Value<int>("taskProgress");

            Dictionary<string, List<DialogueGroup>> index = _cache.GetNpcDialogues();

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
            return BuildSuccess(bundle);
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
