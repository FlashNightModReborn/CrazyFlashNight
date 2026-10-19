using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using CF7Launcher.Data;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 任务插话上下文组装（《协议》4.2 / P4 G4）。
    ///
    /// 只读既有任务目录与当前影子存档，不让后端反查游戏任务表：
    /// - 任务前：upcoming = 本任务；completed = next_task_id 指向本任务的已完成任务，
    ///   没有显式配对时退回“同 chain 的前一个且已完成”；歧义或找不到就省略，不猜。
    /// - 任务后：completed = 本任务（outcome 用目标拼）；upcoming = 本任务 next_task_id 指向的任务。
    ///
    /// 读不到存档、槽位为空、id 非法或目录缺本任务 → 返回 null（调用方 fail-closed）。
    /// </summary>
    internal static class DialogueTaskContext
    {
        internal static JObject Build(MapTaskCatalog catalog, JObject save, string taskId, string kind)
        {
            if (catalog == null || save == null) return null;
            string id = (taskId ?? "").Trim();
            if (id.Length < 1 || id.Length > 32) return null;
            var task = catalog.Tasks[id] as JObject;
            if (task == null) return null;
            JObject tasks = SaveTasks(save);
            if (tasks == null) return null;
            JObject finished = tasks["tasks_finished"] as JObject;
            if (finished == null) finished = new JObject();

            JObject current = Segment(catalog, task, kind == "task_post");
            if (current == null) return null;

            var context = new JObject();
            if (string.Equals(kind, "task_post", StringComparison.Ordinal))
            {
                context["completed"] = current;
                string nextId = NextTaskId(task);
                if (nextId.Length > 0 && catalog.Tasks[nextId] is JObject next)
                {
                    JObject upcoming = Segment(catalog, next, false);
                    if (upcoming != null) context["upcoming"] = upcoming;
                }
            }
            else if (string.Equals(kind, "task_pre", StringComparison.Ordinal))
            {
                context["upcoming"] = current;
                JObject previous = FindPredecessor(catalog, task, id, finished);
                if (previous != null)
                {
                    JObject completed = Segment(catalog, previous, true);
                    if (completed != null) context["completed"] = completed;
                }
            }
            else
            {
                return null;
            }
            return context;
        }

        /// <summary>存档任务区：优先 mydata.tasks（影子存档），兼容 tasks 直接在根上的旧形状。</summary>
        private static JObject SaveTasks(JObject save)
        {
            var mydata = save["mydata"] as JObject;
            JObject bundle = (mydata ?? save)["tasks"] as JObject;
            if (bundle == null && mydata != null) bundle = save["tasks"] as JObject;
            return bundle;
        }

        /// <summary>一段任务摘要；task_id 不是整数（目录不应出现）时整段作废。</summary>
        private static JObject Segment(MapTaskCatalog catalog, JObject task, bool completed)
        {
            int? id = TaskIdOf(task);
            if (!id.HasValue) return null;
            var objectives = Objectives(catalog, task);
            var segment = new JObject
            {
                ["task_id"] = id.Value,
                ["title"] = catalog.Title(task),
                ["npc"] = NpcOf(task, completed),
                ["objectives"] = objectives,
                ["rewards"] = Rewards(catalog, task)
            };
            // 已完成任务的“玩家完成了什么”：没有额外完成详情，就用目标本身拼。
            string outcome = string.Join("；", objectives.ToObject<string[]>());
            if (completed && outcome.Length > 0) segment["outcome"] = outcome;
            return segment;
        }

        private static int? TaskIdOf(JObject task)
        {
            JToken token = task != null ? task["id"] : null;
            if (token == null) return null;
            if (token.Type == JTokenType.Integer) return token.Value<int>();
            int parsed;
            return int.TryParse(token.ToString(), out parsed) ? parsed : (int?)null;
        }

        /// <summary>NPC：已完成用 finish_npc，将完成用 get_npc；缺失回退另一个。</summary>
        private static string NpcOf(JObject task, bool completed)
        {
            string primary = (task.Value<string>(completed ? "finish_npc" : "get_npc") ?? "").Trim();
            if (primary.Length > 0) return primary;
            return (task.Value<string>(completed ? "get_npc" : "finish_npc") ?? "").Trim();
        }

        /// <summary>目标 = finish_requirements + finish_submit_items + finish_contain_items（去重、限量）。</summary>
        private static JArray Objectives(MapTaskCatalog catalog, JObject task)
        {
            var list = new JArray();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            AddStrings(catalog, list, seen, task["finish_requirements"], 32);
            AddStrings(catalog, list, seen, task["finish_submit_items"], 32);
            AddStrings(catalog, list, seen, task["finish_contain_items"], 32);
            return list;
        }

        private static JArray Rewards(MapTaskCatalog catalog, JObject task)
        {
            var list = new JArray();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            AddStrings(catalog, list, seen, task["rewards"], 32);
            return list;
        }

        private static void AddStrings(MapTaskCatalog catalog, JArray target, HashSet<string> seen,
            JToken source, int limit)
        {
            var array = source as JArray;
            if (array == null) return;
            for (int i = 0; i < array.Count && target.Count < limit; i++)
            {
                if (array[i].Type != JTokenType.String) continue;
                string text = Deref(catalog, (string)array[i]);
                if (text.Length == 0 || !seen.Add(text)) continue;
                target.Add(text);
            }
        }

        /// <summary>文本键（以 $ 开头）用任务文本表解引用；解不到就保留原串。</summary>
        private static string Deref(MapTaskCatalog catalog, string raw)
        {
            string text = (raw ?? "").Trim();
            if (text.Length == 0) return "";
            if (text[0] != '$') return text;
            JToken resolved = catalog.Texts[text];
            if (resolved != null && resolved.Type == JTokenType.String)
            {
                string value = ((string)resolved).Trim();
                if (value.Length > 0) return value;
            }
            return text;
        }

        /// <summary>任务前对话的“上一个任务”：显式 next_task_id 优先，其次同 chain 前一号；歧义取 null。</summary>
        private static JObject FindPredecessor(MapTaskCatalog catalog, JObject current,
            string currentId, JObject finished)
        {
            var explicitMatches = new List<string>();
            foreach (var property in catalog.Tasks.Properties())
            {
                if (!(property.Value is JObject candidate)) continue;
                if (!string.Equals(NextTaskId(candidate), currentId, StringComparison.Ordinal)) continue;
                if (IsFinished(finished, property.Name)) explicitMatches.Add(property.Name);
            }
            if (explicitMatches.Count == 1) return catalog.Tasks[explicitMatches[0]] as JObject;
            if (explicitMatches.Count > 1) return null;

            string chain = current.Value<string>("chain") ?? "";
            string[] parts = chain.Split('#');
            int sequence;
            if (parts.Length != 2 || !int.TryParse(parts[1], out sequence) || sequence <= 1) return null;
            string previousChain = parts[0] + "#" + (sequence - 1);
            string matchedId = null;
            int matched = 0;
            foreach (var property in catalog.Tasks.Properties())
            {
                if (!(property.Value is JObject candidate)) continue;
                if (!string.Equals(candidate.Value<string>("chain"), previousChain, StringComparison.Ordinal)) continue;
                if (!IsFinished(finished, property.Name)) continue;
                matchedId = property.Name;
                matched++;
            }
            return matched == 1 ? catalog.Tasks[matchedId] as JObject : null;
        }

        private static bool IsFinished(JObject finished, string taskId)
        {
            JToken token = finished[taskId];
            if (token == null || token.Type == JTokenType.Null) return false;
            if (token.Type == JTokenType.Integer) return token.Value<long>() >= 1;
            if (token.Type == JTokenType.Boolean) return token.Value<bool>();
            return true;
        }

        /// <summary>next_task_id：整数或数字字符串才认，其它一律视为没有配对。</summary>
        private static string NextTaskId(JObject task)
        {
            JToken token = task != null ? task["next_task_id"] : null;
            if (token == null || token.Type == JTokenType.Null) return "";
            if (token.Type == JTokenType.Integer)
                return token.Value<long>().ToString(System.Globalization.CultureInfo.InvariantCulture);
            if (token.Type == JTokenType.String)
            {
                string text = ((string)token).Trim();
                long parsed;
                return long.TryParse(text, out parsed)
                    ? parsed.ToString(System.Globalization.CultureInfo.InvariantCulture) : "";
            }
            return "";
        }
    }
}
