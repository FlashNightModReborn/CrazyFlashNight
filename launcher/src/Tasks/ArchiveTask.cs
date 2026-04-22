using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.Save;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// archive async handler：Flash 存盘后将 mydata JSON 副本推送到 Launcher 落盘。
    /// shadow 既是运行中冗余副本，也是启动期与 SOL 比时间戳的候选快照。
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
    public class ArchiveTask : CF7Launcher.Save.IArchiveStateProbe, CF7Launcher.Save.IArchiveShadowWriter
    {
        private readonly string _savesDir;
        private readonly object _lock = new object();

        /// <summary>saves 目录路径（供 BootstrapMessageHandler 读取）。</summary>
        public string SavesDir { get { return _savesDir; } }

        /// <summary>
        /// 同步读 shadow JSON。SolResolver 专用。
        /// 与 HandleShadow 写操作共享 <c>_lock</c>，保证读到的要么是写前、要么是写后完整数据。
        /// 不触碰 <c>_prevSnapshots</c>（避免与 consistency diff 的异步计算交叉）。
        /// tombstone 判定独立，调用方应先调 <see cref="IsTombstoned"/>。
        /// </summary>
        public bool TryLoadShadowSync(string slot, out JObject data, out string error)
        {
            data = null;
            error = null;
            string safe = SanitizeSlotName(slot);
            string path = Path.Combine(_savesDir, safe + ".json");
            lock (_lock)
            {
                if (!File.Exists(path))
                {
                    error = "not_found";
                    return false;
                }
                try
                {
                    string content = File.ReadAllText(path, Encoding.UTF8);
                    data = JObject.Parse(content);
                    return true;
                }
                catch (Exception ex)
                {
                    error = ex.Message;
                    return false;
                }
            }
        }

        public bool TrySeedShadowSync(string slot, JObject data, out string targetPath, out string error)
        {
            targetPath = null;
            error = null;
            if (data == null)
            {
                error = "missing data";
                return false;
            }

            string safeName = SanitizeSlotName(slot);
            string json = data.ToString(Formatting.None);
            if (!TryWriteShadowAtomic(safeName, json, false, out targetPath, out error))
                return false;

            lock (_prevSnapshots)
            {
                _prevSnapshots[safeName] = data.DeepClone() as JObject;
            }

            LogManager.Log("[ArchiveTask] seed shadow saved: slot=" + safeName + " path=" + targetPath);
            return true;
        }

        /// <summary>
        /// 墓碑检查。SolResolver 专用，语义对齐 HandleLoad 的 tombstone 判定。
        /// </summary>
        private bool TryWriteShadowAtomic(string safeName, string data, bool clearTombstone, out string targetPath, out string error)
        {
            targetPath = Path.Combine(_savesDir, safeName + ".json");
            error = null;
            string tmpPath = targetPath + ".tmp";
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            lock (_lock)
            {
                if (!clearTombstone && File.Exists(tombPath))
                {
                    error = "slot_tombstoned";
                    return false;
                }

                try
                {
                    File.WriteAllText(tmpPath, data, new UTF8Encoding(false));
                    if (File.Exists(targetPath))
                        File.Delete(targetPath);
                    File.Move(tmpPath, targetPath);

                    if (clearTombstone && File.Exists(tombPath))
                    {
                        File.Delete(tombPath);
                        LogManager.Log("[ArchiveTask] Shadow cleared tombstone: " + safeName);
                    }

                    return true;
                }
                catch (Exception ex)
                {
                    try
                    {
                        if (File.Exists(tmpPath))
                            File.Delete(tmpPath);
                    }
                    catch { }

                    error = ex.Message;
                    return false;
                }
            }
        }

        public bool IsTombstoned(string slot)
        {
            string safe = SanitizeSlotName(slot);
            string tombPath = Path.Combine(_savesDir, safe + ".tombstone");
            lock (_lock)
            {
                return File.Exists(tombPath);
            }
        }

        /// <summary>
        /// Synchronous variant of reset used by launcher-controlled "fresh start"
        /// flows before Flash boots. Clears launcher shadow/tombstone only.
        /// </summary>
        public void ResetSlotSync(string slot)
        {
            string safeName = SanitizeSlotName(slot);
            string jsonPath = Path.Combine(_savesDir, safeName + ".json");
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            lock (_lock)
            {
                try { if (File.Exists(jsonPath)) File.Delete(jsonPath); }
                catch (Exception ex) { LogManager.Log("[ArchiveTask] reset(sync) delete json failed: " + ex.Message); }

                try { if (File.Exists(tombPath)) File.Delete(tombPath); }
                catch (Exception ex) { LogManager.Log("[ArchiveTask] reset(sync) delete tombstone failed: " + ex.Message); }
            }

            lock (_prevSnapshots)
            {
                _prevSnapshots.Remove(safeName);
            }

            LogManager.Log("[ArchiveTask] reset(sync) slot=" + safeName);
        }

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
                case "delete":
                    return HandleDelete(payload);
                case "list":
                    return HandleList();
                case "reset":
                    return HandleReset(payload);
                case "load_raw":
                    return HandleLoadRaw(payload);
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
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            // Phase 2a userEdit 守卫：用户态编辑/导入（BootstrapMessageHandler 注入 userEdit:true）
            bool userEdit = payload["userEdit"] != null && (bool)payload["userEdit"];
            if (userEdit && dataObj != null)
            {
                // schema 结构校验
                string schemaErr;
                if (!ValidateSchemaStructure(dataObj, out schemaErr))
                    return BuildError(schemaErr);

                // tombstone 守卫：用户态不可通过 shadow 清除 tombstone
                if (File.Exists(tombPath))
                    return BuildError("slot_tombstoned");

                // 覆写 lastSaved 为本地时间（与 SaveManager.packTimestamp() 格式一致）
                dataObj["lastSaved"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
                data = dataObj.ToString(Formatting.None);

                LogManager.Log("[ArchiveTask] userEdit shadow: " + safeName);
            }

            // 一致性校验
            JArray warnings = null;
            if (dataObj != null)
            {
                warnings = RunConsistencyCheck(safeName, dataObj);
            }

            string writeError;
            string writtenPath;
            if (!TryWriteShadowAtomic(safeName, data, true, out writtenPath, out writeError))
                return BuildError(writeError ?? "shadow write failed");

            LogManager.Log("[ArchiveTask] Shadow saved: " + safeName + " (" + data.Length + " chars) path=" + writtenPath);

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
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            // tombstoned 优先判定：即便 .json 存在（inconsistent），也不加载，交给 Flash preload 走自清流程
            if (File.Exists(tombPath))
                return BuildError("tombstoned: " + safeName);

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

        // ==================== delete ====================

        private string HandleDelete(JObject payload)
        {
            string slot = payload.Value<string>("slot");
            if (string.IsNullOrEmpty(slot))
                return BuildError("missing slot");

            string safeName = SanitizeSlotName(slot);
            string jsonPath = Path.Combine(_savesDir, safeName + ".json");
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");
            string tombTmp = tombPath + ".tmp";

            // 原子写 .tombstone：先写 .tmp 再 rename；完成后删 .json（若存在）
            // 失败即抛到 HandleAsync 的 catch，不进入 "部分删" 状态
            lock (_lock)
            {
                string stamp = DateTime.UtcNow.ToString("o");
                File.WriteAllText(tombTmp, "{\"deletedAt\":\"" + stamp + "\"}",
                    new System.Text.UTF8Encoding(false));
                if (File.Exists(tombPath))
                    File.Delete(tombPath);
                File.Move(tombTmp, tombPath);

                if (File.Exists(jsonPath))
                    File.Delete(jsonPath);

                LogManager.Log("[ArchiveTask] Tombstoned: " + safeName);
            }

            JObject result = new JObject();
            result["success"] = true;
            result["task"] = "archive";
            result["slot"] = safeName;
            result["tombstoned"] = true;
            return result.ToString(Formatting.None);
        }

        // ==================== list ====================

        private string HandleList()
        {
            JArray slots = new JArray();
            if (Directory.Exists(_savesDir))
            {
                // 合并 *.json 与 *.tombstone 的槽位名：tombstone-only 槽位也要列出
                var slotNames = new HashSet<string>(StringComparer.Ordinal);
                foreach (string f in Directory.GetFiles(_savesDir, "*.json"))
                    slotNames.Add(Path.GetFileNameWithoutExtension(f));
                foreach (string f in Directory.GetFiles(_savesDir, "*.tombstone"))
                    slotNames.Add(Path.GetFileNameWithoutExtension(f));

                foreach (string slot in slotNames)
                {
                    slots.Add(BuildListEntry(slot));
                }
            }

            JObject result = new JObject();
            result["success"] = true;
            result["task"] = "archive";
            result["slots"] = slots;
            return result.ToString(Formatting.None);
        }

        private JObject BuildListEntry(string slot)
        {
            string jsonPath = Path.Combine(_savesDir, slot + ".json");
            string tombPath = Path.Combine(_savesDir, slot + ".tombstone");
            bool hasJson = File.Exists(jsonPath);
            bool hasTomb = File.Exists(tombPath);

            JObject entry = new JObject();
            entry["slot"] = slot;
            // 不变式 4：.json 与 .tombstone 并存 == tombstoned（语义同 inconsistent，用单独字段区分 UX 表现）
            entry["tombstoned"] = hasTomb;
            entry["inconsistent"] = hasJson && hasTomb;

            bool corrupt = false;
            string mainProgress = null;
            long size = 0;
            string lastModified = null;

            if (hasJson)
            {
                FileInfo fi = new FileInfo(jsonPath);
                size = fi.Length;
                lastModified = fi.LastWriteTimeUtc.ToString("o");
                try
                {
                    string text = File.ReadAllText(jsonPath, Encoding.UTF8);
                    JObject data = JObject.Parse(text);
                    mainProgress = DeriveMainProgress(data);
                }
                catch (Exception ex)
                {
                    corrupt = true;
                    LogManager.Log("[ArchiveTask] List: " + slot + " JSON parse failed: " + ex.Message);
                }
            }

            entry["corrupt"] = corrupt;
            entry["size"] = size;
            entry["lastModified"] = lastModified != null ? (JToken)lastModified : JValue.CreateNull();
            entry["mainProgress"] = mainProgress != null ? (JToken)mainProgress : JValue.CreateNull();
            return entry;
        }

        /// <summary>
        /// 从 mydata 结构中抽取主线进度展示串。
        /// 结构参考 SaveManager.as:206："角色名=" + raw[0][0] + " 等级=" + raw[0][3]。
        /// 解析失败返回 null。
        /// </summary>
        private static string DeriveMainProgress(JObject data)
        {
            JArray player = data.Value<JArray>("0");
            if (player == null || player.Count < 4) return null;
            string name = SafeStr(player, 0);
            double level = SafeNum(player, 3);
            if (name == null || double.IsNaN(level)) return null;
            return name + " Lv." + ((int)level);
        }

        // ==================== 工具方法 ====================

        public static string SanitizeSlotName(string slot)
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

        // ==================== reset (Phase 2a) ====================

        /// <summary>
        /// 清理 launcher 侧副本：同时删 .json + .tombstone + 清一致性快照。
        /// 注意：不清除 Flash 侧 SOL，下次启动可能从 SOL 回填。
        /// </summary>
        private string HandleReset(JObject payload)
        {
            string slot = payload.Value<string>("slot");
            if (string.IsNullOrEmpty(slot))
                return BuildError("missing slot");

            string safeName = SanitizeSlotName(slot);
            string jsonPath = Path.Combine(_savesDir, safeName + ".json");
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            lock (_lock)
            {
                try { if (File.Exists(jsonPath)) File.Delete(jsonPath); }
                catch (Exception ex) { LogManager.Log("[ArchiveTask] reset delete json failed: " + ex.Message); }

                try { if (File.Exists(tombPath)) File.Delete(tombPath); }
                catch (Exception ex) { LogManager.Log("[ArchiveTask] reset delete tombstone failed: " + ex.Message); }
            }

            lock (_prevSnapshots)
            {
                _prevSnapshots.Remove(safeName);
            }

            LogManager.Log("[ArchiveTask] reset slot=" + safeName);

            JObject result = new JObject();
            result["success"] = true;
            result["task"] = "archive";
            result["slot"] = safeName;
            result["reset"] = true;
            return result.ToString(Formatting.None);
        }

        // ==================== load_raw (Phase 2a) ====================

        /// <summary>
        /// 绕过 tombstone 检查直接读取 .json 原始内容（供 editor 查看 inconsistent/corrupt slot）。
        /// </summary>
        private string HandleLoadRaw(JObject payload)
        {
            string slot = payload.Value<string>("slot");
            if (string.IsNullOrEmpty(slot))
                return BuildError("missing slot");

            string safeName = SanitizeSlotName(slot);
            string jsonPath = Path.Combine(_savesDir, safeName + ".json");
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            if (!File.Exists(jsonPath))
                return BuildError("slot not found: " + safeName);

            string rawData = File.ReadAllText(jsonPath, Encoding.UTF8);
            bool corrupt = false;
            try { JObject.Parse(rawData); }
            catch { corrupt = true; }

            JObject result = new JObject();
            result["success"] = true;
            result["task"] = "archive";
            result["slot"] = safeName;
            result["data"] = rawData;
            result["tombstoned"] = File.Exists(tombPath);
            result["corrupt"] = corrupt;
            return result.ToString(Formatting.None);
        }

        // ==================== schema 结构校验 (Phase 2a) ====================

        /// <summary>
        /// 结构校验：保留基础 schema 早检，并对 tasks/pets/shop 做类型归一化。
        /// 不做数值范围校验（那是前端白名单的职责）。
        /// </summary>
        public static bool ValidateSchemaStructure(JObject data, out string error)
        {
            error = null;
            if (data == null) { error = "missing_data"; return false; }
            string ver = data.Value<string>("version");
            if (ver != "3.0") { error = "schema_version_mismatch"; return false; }
            JArray arr0 = data.Value<JArray>("0");
            if (arr0 == null || arr0.Count < 14) { error = "schema_player_array_invalid"; return false; }
            JArray arr1 = data.Value<JArray>("1");
            if (arr1 == null || arr1.Count < 28) { error = "schema_equip_array_invalid"; return false; }
            if (data["lastSaved"] == null) { error = "schema_missing_lastSaved"; return false; }
            SaveMigrator.NormalizeResolvedSnapshot(data);
            if (!SaveMigrator.ValidateResolvedSnapshot(data))
            {
                error = "schema_structure_invalid";
                return false;
            }
            return true;
        }

        // ==================== 工具方法 ====================

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
