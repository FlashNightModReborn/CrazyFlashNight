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
    ///   请求 payload: { dataType: "npc_dialogue"|"merc_bundle"|"enemy_dialogues"|"task_npc_registry"|"map_catalog", key: ..., taskProgress: ... }
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
                case "enemy_dialogues":
                    return QueryEnemyDialogues();
                case "task_npc_registry":
                    return QueryTaskNpcRegistry();
                case "map_catalog":
                    return QueryMapCatalog();
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

        /// <summary>
        /// 地图任务 NPC 注册表查询。返回 { task_npcs:[{name,hotspot}], aliases:[{name,canonical}] }。
        /// AS2 端 MapTaskNpcRegistry.applyFromQuery 启动期消费。
        /// 数据派生自 launcher/web/modules/map-panel-data.js 的 staticAvatars+dynamicAvatars。
        /// 失败 → success:false，AS2 静默降级（任务环 marker 列表为空），不阻塞游戏进入。
        /// </summary>
        private string QueryTaskNpcRegistry()
        {
            JObject data = _cache.GetTaskNpcRegistry();
            if (data == null)
                return BuildError("task_npc_registry unavailable: " + (_cache.GetTaskNpcError() ?? "unknown"));

            return BuildSuccess(data);
        }

        /// <summary>
        /// 地图 hotspot 拓扑目录查询。返回 { groups:[{id,page,label,lockedReason?}], hotspots:[{id,group,frame}] }。
        /// AS2 端 MapPanelCatalog.applyFromCatalogJson 启动期消费。
        /// 数据派生自 launcher/web/modules/map-panel-data.js（build.ps1 Step 1c）。
        /// 失败 → success:false。**与 task_npc_registry 不同：这是导航权威，AS2 boot 收到 false 必须明确报错、
        /// 地图面板不可用，绝不静默降级**（见 asLoader.xml boot / MapPanelService.canNavigateToHotspot）。
        /// </summary>
        private string QueryMapCatalog()
        {
            JObject data = _cache.GetMapCatalog();
            if (data == null)
                return BuildError("map_catalog unavailable: " + (_cache.GetMapCatalogError() ?? "unknown"));

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
