using System;
using System.Globalization;
using System.IO;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>
    /// 任务前插话「临时新增奖励」的按存档覆盖层：唯一写入点与形状校验点。
    ///
    /// 文件落 data/rag/agent_saves/&lt;slotKey&gt;/task_reward_overrides.json（该目录整体 gitignore）。
    /// 同一 task_id 整条覆盖（后写赢）、不累加；原有任务 JSON 与存档格式都不修改。
    /// 额度公式的权威在后端工具，Host 只做归属与结构硬校验，额度依据原样入覆盖层供审计。
    /// </summary>
    internal sealed class TaskRewardOverrideStore
    {
        internal const string FileName = "task_reward_overrides.json";
        internal const int MaxExtraRewards = 2;
        private const int MaxQuantity = 9999;
        private const int MaxNameLength = 64;

        private readonly string _root;
        private readonly Func<string> _slotKey;

        internal TaskRewardOverrideStore(string root, Func<string> slotKey)
        {
            _root = root ?? throw new ArgumentNullException(nameof(root));
            _slotKey = slotKey ?? (() => null);
        }

        /// <summary>与后端写盘、AS2 TaskOverlayLoader 同名的按存档相对路径；未绑定槽位返回 null。</summary>
        internal static string SourceFor(string slotKey) =>
            string.IsNullOrEmpty(slotKey) ? null : "data/rag/agent_saves/" + slotKey + "/" + FileName;

        /// <summary>把 action 载荷归一化成覆盖层条目；不合法返回 null 并给出 error。</summary>
        internal static JObject Normalize(JObject action, string expectedTaskId, out string error)
        {
            error = "";
            if (action == null) { error = "malformed_action"; return null; }
            string actionId = action.Value<string>("action_id") ?? "";
            string taskId = TaskIdOf(action["task_id"]);
            if (actionId.Length == 0 || taskId.Length == 0
                || !string.Equals(taskId, expectedTaskId, StringComparison.Ordinal))
            {
                error = "malformed_action";
                return null;
            }

            JArray extra = action["extra_rewards"] as JArray;
            if (extra == null || extra.Count < 1 || extra.Count > MaxExtraRewards)
            {
                error = "invalid_extra_rewards";
                return null;
            }
            var rewards = new JArray();
            foreach (JToken token in extra)
            {
                if (token.Type != JTokenType.String || !ValidReward((string)token))
                {
                    error = "invalid_extra_rewards";
                    return null;
                }
                rewards.Add((string)token);
            }

            int cap = PositiveInt(action["额度上限"]);
            JObject basis = action["额度依据"] as JObject;
            if (cap < 1 || basis == null) { error = "invalid_cap"; return null; }

            return new JObject
            {
                ["task_id"] = taskId,
                ["extra_rewards"] = rewards,
                ["额度上限"] = cap,
                ["额度依据"] = basis.DeepClone(),
                ["action_id"] = actionId
            };
        }

        /// <summary>把临时新增奖励追加到任务对象 rewards（同源投影用）；原有条目不动，最多两条。</summary>
        internal static void AppendExtraRewards(JObject task, JObject entry)
        {
            if (task == null || entry == null) return;
            JArray extra = entry["extra_rewards"] as JArray;
            if (extra == null || extra.Count == 0) return;
            JArray rewards = task["rewards"] is JArray existing
                ? (JArray)existing.DeepClone() : new JArray();
            for (int i = 0; i < extra.Count && i < MaxExtraRewards; i++)
                if (extra[i].Type == JTokenType.String) rewards.Add(extra[i].DeepClone());
            task["rewards"] = rewards;
        }

        /// <summary>按 task_id 覆盖式原子写盘；返回相对路径供 Host 通知 AS2 重载。</summary>
        internal bool TryApply(JObject entry, out string relativePath, out string error)
        {
            relativePath = null;
            error = "";
            string slot = _slotKey();
            relativePath = SourceFor(slot);
            if (relativePath == null) { error = "no_slot"; return false; }
            string taskId = entry.Value<string>("task_id") ?? "";
            if (taskId.Length == 0) { error = "malformed_action"; return false; }

            string full;
            try { full = MapProjectFiles.Resolve(_root, relativePath); }
            catch (Exception ex)
            {
                error = "path_rejected";
                CF7Launcher.Guardian.LogManager.Log("[TaskRewardOverride] path rejected: " + ex.Message);
                return false;
            }

            var overlay = new JObject();
            try
            {
                // 文件存在但解析不净＝fail-closed，绝不拿半份数据覆盖已有覆盖层。
                if (File.Exists(full)) overlay = MapProjectFiles.Json(File.ReadAllBytes(full));
            }
            catch (Exception ex)
            {
                error = "overlay_corrupt";
                CF7Launcher.Guardian.LogManager.Log("[TaskRewardOverride] overlay read failed: " + ex.Message);
                return false;
            }
            overlay[taskId] = entry.DeepClone();
            string json = overlay.ToString(Formatting.None);
            string temp = full + ".tmp-" + Guid.NewGuid().ToString("N");
            try
            {
                string directory = Path.GetDirectoryName(full);
                if (!Directory.Exists(directory)) Directory.CreateDirectory(directory);
                File.WriteAllText(temp, json, new UTF8Encoding(false));
                File.Move(temp, full, true);
                return true;
            }
            catch (Exception ex)
            {
                error = "write_failed";
                CF7Launcher.Guardian.LogManager.Log("[TaskRewardOverride] write failed: " + ex.Message);
                return false;
            }
            finally
            {
                try { if (File.Exists(temp)) File.Delete(temp); } catch (Exception) { }
            }
        }

        private static string TaskIdOf(JToken token)
        {
            if (token == null) return "";
            if (token.Type == JTokenType.Integer)
                return token.Value<long>().ToString(CultureInfo.InvariantCulture);
            return token.Type == JTokenType.String ? ((string)token).Trim() : "";
        }

        private static int PositiveInt(JToken token)
        {
            if (token == null) return 0;
            if (token.Type == JTokenType.Integer)
            {
                long value = token.Value<long>();
                return value > 0 && value <= int.MaxValue ? (int)value : 0;
            }
            if (token.Type != JTokenType.String) return 0;
            return int.TryParse(((string)token).Trim(), NumberStyles.None,
                CultureInfo.InvariantCulture, out int parsed) ? parsed : 0;
        }

        /// <summary>只允许「名称#正整数」；不含 ## 语法，名称无控制字符，数量有上限。</summary>
        private static bool ValidReward(string text)
        {
            if (string.IsNullOrEmpty(text) || text.Length > MaxNameLength + 8) return false;
            int hash = text.IndexOf('#');
            if (hash < 1 || hash != text.LastIndexOf('#')) return false;
            string name = text.Substring(0, hash);
            string quantity = text.Substring(hash + 1);
            if (name.Length > MaxNameLength || name.Trim().Length == 0) return false;
            foreach (char c in name) if (char.IsControl(c)) return false;
            return int.TryParse(quantity, NumberStyles.None, CultureInfo.InvariantCulture, out int count)
                && count > 0 && count <= MaxQuantity;
        }
    }
}
