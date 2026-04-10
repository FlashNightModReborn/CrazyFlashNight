using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// archive async handler：Flash 存盘后将 mydata JSON 副本推送到 Launcher 落盘。
    /// SOL 仍是权威源，Launcher 仅做 shadow 备份。
    ///
    /// 内置一致性校验：每次 shadow 与上一次做语义级 diff，检测异常变化。
    ///
    /// 协议：
    ///   请求 payload: { op: "shadow", slot: "savePath", data: {mydata} }
    ///                 { op: "load",   slot: "savePath" }
    ///                 { op: "list" }
    ///   响应: { success: true, task: "archive", ... }
    ///      或 { success: false, task: "archive", error: "..." }
    /// </summary>
    public class ArchiveTask
    {
        private readonly string _savesDir;
        private readonly object _lock = new object();

        // 一致性校验：每个 slot 的上一次 shadow 快照
        private readonly Dictionary<string, JObject> _prevSnapshots = new Dictionary<string, JObject>();

        public ArchiveTask(string projectRoot)
        {
            _savesDir = Path.Combine(projectRoot, "saves");
            if (!Directory.Exists(_savesDir))
            {
                Directory.CreateDirectory(_savesDir);
                LogManager.Log("[ArchiveTask] Created saves directory: " + _savesDir);
            }
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
                    LogManager.Log("[ArchiveTask] Exception: " + ex);
                    respond(BuildError("archive exception: " + ex.Message));
                }
            });
        }

        private string Process(JObject message)
        {
            JObject payload = message.Value<JObject>("payload");
            if (payload == null)
                return BuildError("missing payload");

            string op = payload.Value<string>("op");
            if (op == null)
                return BuildError("missing op");

            switch (op)
            {
                case "shadow":
                    return HandleShadow(payload);
                case "load":
                    return HandleLoad(payload);
                case "list":
                    return HandleList();
                default:
                    return BuildError("unknown op: " + op);
            }
        }

        // ==================== shadow ====================

        private string HandleShadow(JObject payload)
        {
            string slot = payload.Value<string>("slot");
            if (string.IsNullOrEmpty(slot))
                return BuildError("missing slot");

            // data 可能是 JSON 对象或字符串
            JToken dataToken = payload["data"];
            if (dataToken == null)
                return BuildError("missing data");

            string data;
            JObject dataObj = null;
            if (dataToken.Type == JTokenType.String)
            {
                data = dataToken.Value<string>();
                try { dataObj = JObject.Parse(data); }
                catch { /* 非 JSON 字符串，跳过校验 */ }
            }
            else if (dataToken.Type == JTokenType.Object)
            {
                dataObj = (JObject)dataToken;
                data = dataObj.ToString(Formatting.None);
            }
            else
            {
                data = dataToken.ToString(Formatting.None);
            }

            if (string.IsNullOrEmpty(data))
                return BuildError("missing data");

            string safeName = SanitizeSlotName(slot);
            string targetPath = Path.Combine(_savesDir, safeName + ".json");
            string tmpPath = targetPath + ".tmp";

            // 一致性校验
            JArray warnings = null;
            if (dataObj != null)
            {
                warnings = RunConsistencyCheck(safeName, dataObj);
            }

            lock (_lock)
            {
                // 原子写入：先写 .tmp 再 rename，防断电半写
                File.WriteAllText(tmpPath, data, Encoding.UTF8);

                // Windows 上 File.Move 不允许目标已存在，先删再移
                if (File.Exists(targetPath))
                    File.Delete(targetPath);
                File.Move(tmpPath, targetPath);
            }

            LogManager.Log("[ArchiveTask] Shadow saved: " + safeName + " (" + data.Length + " chars)");

            JObject result = new JObject();
            result["success"] = true;
            result["task"] = "archive";
            result["slot"] = safeName;
            result["size"] = data.Length;
            if (warnings != null && warnings.Count > 0)
            {
                result["warnings"] = warnings;
                LogManager.Log("[ArchiveTask] Consistency warnings for " + safeName + ": " + warnings.ToString(Formatting.None));
            }
            return result.ToString(Formatting.None);
        }

        // ==================== 一致性校验 ====================

        /// <summary>
        /// 对比当前 shadow 与上一次 shadow，检测异常变化。
        /// 返回 warning 列表（空 = 正常）。
        /// </summary>
        private JArray RunConsistencyCheck(string slot, JObject current)
        {
            JObject prev;
            lock (_prevSnapshots)
            {
                _prevSnapshots.TryGetValue(slot, out prev);
                _prevSnapshots[slot] = current;
            }

            if (prev == null)
                return null; // 首次 shadow，无对比基准

            JArray warnings = new JArray();

            // 版本不应降级
            CheckStringNotRegressed(prev, current, "version", warnings);

            // 主角数据 mydata[0]
            JArray prevPlayer = prev.Value<JArray>("0");
            JArray curPlayer = current.Value<JArray>("0");

            if (prevPlayer != null && curPlayer != null)
            {
                // [0] 角色名不应变化（同一存档）
                string prevName = SafeStr(prevPlayer, 0);
                string curName = SafeStr(curPlayer, 0);
                if (prevName != null && curName != null && prevName != curName)
                {
                    warnings.Add("角色名变化: " + prevName + " -> " + curName);
                }

                // [3] 等级不应倒退
                CheckNumNotDecreased(prevPlayer, curPlayer, 3, "等级", warnings);

                // [2] 金钱不应变负
                double curMoney = SafeNum(curPlayer, 2);
                if (curMoney < 0)
                {
                    warnings.Add("金钱为负: " + curMoney);
                }
            }

            // 版本字段存在性
            if (current["version"] == null)
            {
                warnings.Add("缺少 version 字段");
            }

            return warnings;
        }

        private static void CheckStringNotRegressed(JObject prev, JObject current, string key, JArray warnings)
        {
            string pv = prev.Value<string>(key);
            string cv = current.Value<string>(key);
            if (pv != null && cv != null)
            {
                if (string.Compare(cv, pv, StringComparison.Ordinal) < 0)
                {
                    warnings.Add(key + " 降级: " + pv + " -> " + cv);
                }
            }
        }

        private static void CheckNumNotDecreased(JArray prev, JArray current, int index, string label, JArray warnings)
        {
            double pv = SafeNum(prev, index);
            double cv = SafeNum(current, index);
            if (!double.IsNaN(pv) && !double.IsNaN(cv) && cv < pv)
            {
                warnings.Add(label + " 倒退: " + pv + " -> " + cv);
            }
        }

        private static double SafeNum(JArray arr, int index)
        {
            if (arr == null || index >= arr.Count)
                return double.NaN;
            JToken t = arr[index];
            if (t == null || t.Type == JTokenType.Null)
                return double.NaN;
            try { return t.Value<double>(); }
            catch { return double.NaN; }
        }

        private static string SafeStr(JArray arr, int index)
        {
            if (arr == null || index >= arr.Count)
                return null;
            JToken t = arr[index];
            if (t == null || t.Type == JTokenType.Null)
                return null;
            return t.ToString();
        }

        // ==================== load ====================

        private string HandleLoad(JObject payload)
        {
            string slot = payload.Value<string>("slot");
            if (string.IsNullOrEmpty(slot))
                return BuildError("missing slot");

            string safeName = SanitizeSlotName(slot);
            string targetPath = Path.Combine(_savesDir, safeName + ".json");

            if (!File.Exists(targetPath))
                return BuildError("slot not found: " + safeName);

            string data = File.ReadAllText(targetPath, Encoding.UTF8);

            JObject result = new JObject();
            result["success"] = true;
            result["task"] = "archive";
            result["slot"] = safeName;
            result["data"] = data;
            return result.ToString(Formatting.None);
        }

        // ==================== list ====================

        private string HandleList()
        {
            JArray slots = new JArray();
            if (Directory.Exists(_savesDir))
            {
                string[] files = Directory.GetFiles(_savesDir, "*.json");
                for (int i = 0; i < files.Length; i++)
                {
                    FileInfo fi = new FileInfo(files[i]);
                    JObject entry = new JObject();
                    entry["slot"] = Path.GetFileNameWithoutExtension(fi.Name);
                    entry["size"] = fi.Length;
                    entry["lastModified"] = fi.LastWriteTimeUtc.ToString("o");
                    slots.Add(entry);
                }
            }

            JObject result = new JObject();
            result["success"] = true;
            result["task"] = "archive";
            result["slots"] = slots;
            return result.ToString(Formatting.None);
        }

        // ==================== 工具方法 ====================

        private static string SanitizeSlotName(string slot)
        {
            if (string.IsNullOrEmpty(slot))
                return "default";

            StringBuilder sb = new StringBuilder(slot.Length);
            for (int i = 0; i < slot.Length; i++)
            {
                char c = slot[i];
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_' || c == '-')
                {
                    sb.Append(c);
                }
                else
                {
                    sb.Append('_');
                }
            }

            string result = sb.ToString();
            if (result.Length == 0)
                return "default";
            return result;
        }

        private static string BuildError(string error)
        {
            JObject obj = new JObject();
            obj["success"] = false;
            obj["task"] = "archive";
            obj["error"] = error;
            return obj.ToString(Formatting.None);
        }
    }
}
