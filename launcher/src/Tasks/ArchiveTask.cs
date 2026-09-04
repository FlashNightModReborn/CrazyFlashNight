using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Runtime.ExceptionServices;
using System.Text;
using System.Text.RegularExpressions;
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
    /// 顺序模型（R3a）：所有 archive 操作进入进程内单 FIFO executor（全局单消费者）。
    /// XmlSocket 单 read loop 按到达顺序调用 <see cref="HandleAsync"/>，executor 严格按
    /// 入队顺序逐条执行，shadow/load/delete/reset/list/load_raw 不会互相超车；
    /// 同步入口（<see cref="TrySeedShadowSync"/> seed/repair、<see cref="ResetSlotSync"/>
    /// rebuild 重建）同样排队过门并阻塞等待，保证同槽操作按到达顺序生效。
    /// tombstone 检查、一致性基线比较、物理写入、accepted-state（_prevSnapshots）更新
    /// 在同一 _lock 临界区内完成；普通 shadow / seed / userEdit / repair 一律不清
    /// tombstone，只有显式 reset / ResetSlotSync（recreate）能撤销墓碑。
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
        private readonly SaveSlotCatalog _slotCatalog;
        private readonly RebuildBackupStore _rebuildBackups;

        // R3a 顺序门：全局单 FIFO 消费者。入队顺序 == HandleAsync 调用顺序 == 消息到达顺序。
        private readonly BlockingCollection<Action> _opQueue = new BlockingCollection<Action>();
        private readonly Thread _opThread;

        /// <summary>
        /// 测试钩子：shadow 通过校验、进入写入临界区之前触发（在 FIFO 线程上）。
        /// 用于强制"后到消息先完成"的乱序条件，验证顺序门。生产环境恒为 null。
        /// </summary>
        internal Action<string> ShadowWriteGateForTests;

        /// <summary>saves 目录路径（供 BootstrapMessageHandler 读取）。</summary>
        public string SavesDir { get { return _savesDir; } }
        public SaveSlotCatalog SlotCatalog { get { return _slotCatalog; } }
        public RebuildBackupStore RebuildBackups { get { return _rebuildBackups; } }

        /// <summary>
        /// 同步读 shadow JSON。SolResolver 专用。
        /// 与 HandleShadow 写操作共享 <c>_lock</c>，保证读到的要么是写前、要么是写后完整数据。
        /// 不触碰 <c>_prevSnapshots</c>（一致性基线只在写入成功后的 _lock 临界区内更新）。
        /// tombstone 判定独立，调用方应先调 <see cref="IsTombstoned"/>。
        /// </summary>
        public bool TryLoadShadowSync(string slot, out JObject data, out string error)
        {
            data = null;
            error = null;
            string exact;
            if (!SaveSlotKey.TryValidateExisting(slot, out exact))
            {
                error = "invalid_slot_key";
                return false;
            }
            string path = Path.Combine(_savesDir, exact + ".json");
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

        /// <summary>
        /// seed / repair 同步写 shadow。经 FIFO 顺序门排队（与 bus 消息同一顺序门），
        /// tombstone 检查、原子写入、一致性基线更新在同一 _lock 临界区完成。
        /// seed/repair 不清 tombstone：被删槽位只有显式 reset / recreate 才能复活。
        /// </summary>
        public bool TrySeedShadowSync(string slot, JObject data, out string targetPath, out string error)
        {
            targetPath = null;
            error = null;
            if (data == null)
            {
                error = "missing data";
                return false;
            }

            string safeName;
            if (!SaveSlotKey.TryValidateExisting(slot, out safeName))
            {
                error = "invalid_slot_key";
                return false;
            }
            string json = data.ToString(Formatting.None);
            string acceptedPath = null;
            string rejectedError = null;
            bool accepted = RunOnFifo(delegate
            {
                lock (_lock)
                {
                    string path;
                    string writeError;
                    if (!TryWriteShadowAtomicLocked(safeName, json, out path, out writeError))
                    {
                        rejectedError = writeError;
                        return false;
                    }
                    // 写入已被接受：同一临界区内更新 accepted-state 基线。
                    // 克隆快照：调用方仍持有 data 所有权，可能继续复用/修改。
                    _prevSnapshots[safeName] = data.DeepClone() as JObject;
                    acceptedPath = path;
                    return true;
                }
            });
            if (!accepted)
            {
                error = rejectedError;
                return false;
            }

            targetPath = acceptedPath;
            LogManager.Log("[ArchiveTask] seed shadow saved: slot=" + safeName + " path=" + targetPath);
            return true;
        }

        /// <summary>
        /// 原子写 shadow（调用方必须已持有 _lock，且通常已在 FIFO 顺序门上）。
        /// tombstone 存在即拒绝（slot_tombstoned），任何非 recreate 路径都不得清除墓碑。
        /// </summary>
        private bool TryWriteShadowAtomicLocked(string safeName, string data, out string targetPath, out string error)
        {
            targetPath = Path.Combine(_savesDir, safeName + ".json");
            error = null;
            string tmpPath = targetPath + ".tmp";
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            if (File.Exists(tombPath))
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

        /// <summary>
        /// 墓碑检查。SolResolver 专用，语义对齐 HandleLoad 的 tombstone 判定。
        /// </summary>
        public bool IsTombstoned(string slot)
        {
            string safe;
            if (!SaveSlotKey.TryValidateExisting(slot, out safe))
                return false;
            string tombPath = Path.Combine(_savesDir, safe + ".tombstone");
            lock (_lock)
            {
                return File.Exists(tombPath);
            }
        }

        public bool SlotExistsSync(string slot)
        {
            string exact;
            if (!SaveSlotKey.TryValidateExisting(slot, out exact))
                throw new ArgumentException("invalid slot key", "slot");
            bool physicalExists;
            lock (_lock)
            {
                physicalExists = File.Exists(Path.Combine(_savesDir, exact + ".json"))
                    || File.Exists(Path.Combine(_savesDir, exact + ".tombstone"));
            }
            if (physicalExists)
                return true;

            // AS2 remains the save authority, so a successful local flush may
            // outlive the best-effort shadow projection. Durable Host metadata
            // is therefore also a known slot identity for the next bootstrap.
            return _slotCatalog.ReadAll().ContainsKey(exact);
        }

        /// <summary>
        /// Synchronous exact-slot reset used only after a verified rebuild backup.
        /// Clears launcher shadow/tombstone only and fails closed on any residue.
        /// 经 FIFO 顺序门排队：不能越过已入队的 shadow/delete 等先达操作。
        /// 这是显式 recreate 路径，允许撤销 tombstone。
        /// </summary>
        public void ResetSlotSync(string slot)
        {
            string safeName;
            if (!SaveSlotKey.TryValidateExisting(slot, out safeName))
                throw new ArgumentException("invalid slot key", "slot");
            string jsonPath = Path.Combine(_savesDir, safeName + ".json");
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            RunOnFifo(delegate
            {
                lock (_lock)
                {
                    Exception firstFailure = null;
                    try { if (File.Exists(jsonPath)) File.Delete(jsonPath); }
                    catch (Exception ex)
                    {
                        firstFailure = ex;
                        LogManager.Log("[ArchiveTask] reset(sync) delete json failed: " + ex.Message);
                    }

                    try { if (File.Exists(tombPath)) File.Delete(tombPath); }
                    catch (Exception ex)
                    {
                        if (firstFailure == null) firstFailure = ex;
                        LogManager.Log("[ArchiveTask] reset(sync) delete tombstone failed: " + ex.Message);
                    }

                    bool jsonRemains = File.Exists(jsonPath);
                    bool tombstoneRemains = File.Exists(tombPath);
                    if (firstFailure != null || jsonRemains || tombstoneRemains)
                    {
                        throw new IOException(
                            "reset_slot_failed:" + safeName
                            + ":jsonRemains=" + jsonRemains
                            + ":tombstoneRemains=" + tombstoneRemains,
                            firstFailure);
                    }

                    // 物理移除成功：同一临界区内清 accepted-state 基线。
                    _prevSnapshots.Remove(safeName);
                }
            });

            LogManager.Log("[ArchiveTask] reset(sync) slot=" + safeName);
        }

        // 一致性校验基线（accepted-state）：每个 slot 上一份"已接受"的 shadow 快照。
        // R3a：只在写入成功且被接受后更新，且与 tombstone 检查 / 物理写入同一 _lock
        // 临界区；失败或被拒候选不得污染基线。所有访问都在 _lock 下进行。
        private readonly Dictionary<string, JObject> _prevSnapshots = new Dictionary<string, JObject>();

        // INV-4: save discovery admits exact safe ASCII stems only and excludes
        // hidden metadata, backup, repair, and other internal JSON files.
        private static readonly Regex SlotJsonRegex =
            new Regex(@"^[^.][^.]*\.json$", RegexOptions.Compiled);
        private static readonly Regex SlotTombstoneRegex =
            new Regex(@"^[^.][^.]*\.tombstone$", RegexOptions.Compiled);

        public ArchiveTask(string projectRoot)
        {
            _savesDir = Path.Combine(projectRoot, "saves");
            if (!Directory.Exists(_savesDir))
            {
                Directory.CreateDirectory(_savesDir);
                LogManager.Log("[ArchiveTask] Created saves directory: " + _savesDir);
            }
            _slotCatalog = new SaveSlotCatalog(_savesDir);
            _rebuildBackups = new RebuildBackupStore(_savesDir);

            // R3a 顺序门：全局单消费者 FIFO。archive 吞吐远不是瓶颈，优先正确性；
            // 以后确有 per-slot 并行需求再分片。
            _opThread = new Thread(OpLoop);
            _opThread.IsBackground = true;
            _opThread.Name = "ArchiveTask-FIFO";
            _opThread.Start();
        }

        /// <summary>FIFO 消费者主循环：严格按入队顺序逐条执行 archive 操作。</summary>
        private void OpLoop()
        {
            foreach (Action op in _opQueue.GetConsumingEnumerable())
            {
                try
                {
                    op();
                }
                catch (Exception ex)
                {
                    // 兜底：单个 op 自身的 try/catch 正常已覆盖，绝不让消费者线程死亡。
                    LogManager.Log("[ArchiveTask] FIFO op exception: " + ex);
                }
            }
        }

        /// <summary>
        /// 同步入口（seed/repair/reset）经同一 FIFO 顺序门执行并阻塞等待结果。
        /// 与 bus 消息保证同一到达顺序；FIFO 线程内可重入直连（防御性，当前无此路径）。
        /// </summary>
        private T RunOnFifo<T>(Func<T> op)
        {
            if (Thread.CurrentThread == _opThread)
                return op();

            using (ManualResetEventSlim done = new ManualResetEventSlim(false))
            {
                T result = default(T);
                Exception failure = null;
                _opQueue.Add(delegate
                {
                    try { result = op(); }
                    catch (Exception ex) { failure = ex; }
                    finally { done.Set(); }
                });
                done.Wait();
                if (failure != null)
                    ExceptionDispatchInfo.Capture(failure).Throw();
                return result;
            }
        }

        /// <summary>void 版 <see cref="RunOnFifo{T}"/>（reset 等无返回值同步入口）。</summary>
        private void RunOnFifo(Action op)
        {
            RunOnFifo(delegate
            {
                op();
                return true;
            });
        }

        /// <summary>
        /// bus 入口：消息按到达顺序入队，FIFO 消费者逐条处理。
        /// 替换原 ThreadPool.QueueUserWorkItem（完成顺序乱序，最后完成者覆写 slot）。
        /// </summary>
        public void HandleAsync(JObject message, Action<string> respond)
        {
            _opQueue.Add(delegate
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
                catch { return BuildError("shadow_invalid_json"); }
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
            if (dataObj == null)
                return BuildError("shadow_invalid_json");

            string safeName;
            if (!SaveSlotKey.TryValidateExisting(slot, out safeName))
                return BuildError("invalid_slot_key");
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            // Phase 2a userEdit 守卫：用户态编辑/导入（BootstrapMessageHandler 注入 userEdit:true）
            bool userEdit = payload["userEdit"] != null && (bool)payload["userEdit"];
            if (userEdit && dataObj != null)
            {
                // schema 结构校验
                string schemaErr;
                if (!ValidateSchemaStructure(dataObj, out schemaErr))
                    return BuildError(schemaErr);

                // 覆写 lastSaved 为本地时间（与 SaveManager.packTimestamp() 格式一致）
                dataObj["lastSaved"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
                data = dataObj.ToString(Formatting.None);

                LogManager.Log("[ArchiveTask] userEdit shadow: " + safeName);
            }

            SaveMigrator.NormalizeResolvedSnapshot(dataObj);
            if (!SaveMigrator.ValidateResolvedSnapshot(dataObj))
            {
                LogManager.Log("[ArchiveTask] rejected invalid shadow: " + safeName);
                return BuildError("shadow_snapshot_invalid");
            }
            data = dataObj.ToString(Formatting.None);

            // 测试钩子：写入临界区前（FIFO 线程上），用于强制乱序完成条件。
            Action<string> gate = ShadowWriteGateForTests;
            if (gate != null) gate(safeName);

            // R3a 临界区：tombstone 检查、版本/一致性比较、物理写入、accepted-state
            // 更新在同一 _lock 内完成。普通 shadow 与 userEdit 一律不清 tombstone——
            // 只有显式 reset / recreate 能撤销墓碑；写失败或被拒不得污染基线。
            JArray warnings = null;
            string writeError = null;
            string writtenPath = null;
            bool accepted = false;
            lock (_lock)
            {
                if (File.Exists(tombPath))
                {
                    writeError = "slot_tombstoned";
                }
                else
                {
                    warnings = ComputeConsistencyWarnings(safeName, dataObj);
                    if (TryWriteShadowAtomicLocked(safeName, data, out writtenPath, out writeError))
                    {
                        _prevSnapshots[safeName] = dataObj;
                        accepted = true;
                    }
                }
            }
            if (!accepted)
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
        /// 对比候选 shadow 与上一份已接受快照，检测异常变化。
        /// 返回 warning 列表（null = 首次无对比基准；空 = 正常）。
        /// R3a：只读基线、不更新——_prevSnapshots 只在写入成功且被接受后由调用方
        /// 在同一 _lock 临界区内更新。调用方必须已持有 _lock。
        /// </summary>
        private JArray ComputeConsistencyWarnings(string slot, JObject current)
        {
            JObject prev;
            _prevSnapshots.TryGetValue(slot, out prev);

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

            string safeName;
            if (!SaveSlotKey.TryValidateExisting(slot, out safeName))
                return BuildError("invalid_slot_key");
            string targetPath = Path.Combine(_savesDir, safeName + ".json");
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");
            string data;
            lock (_lock)
            {
                // tombstoned 优先判定：即便 .json 存在（inconsistent），也不加载，交给 Flash preload 走自清流程
                if (File.Exists(tombPath))
                    return BuildError("tombstoned: " + safeName);

                if (!File.Exists(targetPath))
                    return BuildError("slot not found: " + safeName);

                data = File.ReadAllText(targetPath, Encoding.UTF8);
            }

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

            string safeName;
            if (!SaveSlotKey.TryValidateExisting(slot, out safeName))
                return BuildError("invalid_slot_key");
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
            IDictionary<string, string> displayNames = _slotCatalog.ReadAll();
            var slotNames = new HashSet<string>(
                displayNames.Keys,
                StringComparer.Ordinal);
            if (Directory.Exists(_savesDir))
            {
                // Merge physical shadows, tombstones, and durable Host catalog
                // identities. The resolver remains responsible for deciding
                // whether the matching AS2 SOL is snapshot/empty/corrupt.
                foreach (string f in Directory.GetFiles(_savesDir, "*.json"))
                {
                    string name = Path.GetFileName(f);
                    if (!SlotJsonRegex.IsMatch(name)) continue;
                    string slot = Path.GetFileNameWithoutExtension(f);
                    if (SaveSlotKey.IsValidExisting(slot)) slotNames.Add(slot);
                }
                foreach (string f in Directory.GetFiles(_savesDir, "*.tombstone"))
                {
                    string name = Path.GetFileName(f);
                    if (!SlotTombstoneRegex.IsMatch(name)) continue;
                    string slot = Path.GetFileNameWithoutExtension(f);
                    if (SaveSlotKey.IsValidExisting(slot)) slotNames.Add(slot);
                }
            }

            foreach (string slot in slotNames)
            {
                slots.Add(BuildListEntry(slot, displayNames));
            }

            JObject result = new JObject();
            result["success"] = true;
            result["task"] = "archive";
            result["slots"] = slots;
            return result.ToString(Formatting.None);
        }

        private JObject BuildListEntry(
            string slot,
            IDictionary<string, string> displayNames)
        {
            string jsonPath = Path.Combine(_savesDir, slot + ".json");
            string tombPath = Path.Combine(_savesDir, slot + ".tombstone");
            bool hasJson = File.Exists(jsonPath);
            bool hasTomb = File.Exists(tombPath);

            JObject entry = new JObject();
            entry["slotKey"] = slot;
            entry["slot"] = slot;
            // 不变式 4：.json 与 .tombstone 并存 == tombstoned（语义同 inconsistent，用单独字段区分 UX 表现）
            entry["tombstoned"] = hasTomb;
            entry["inconsistent"] = hasJson && hasTomb;

            bool corrupt = false;
            string mainProgress = null;
            string characterName = null;
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
                    SaveMigrator.NormalizeResolvedSnapshot(data);
                    if (!SaveMigrator.ValidateResolvedSnapshot(data))
                    {
                        corrupt = true;
                    }
                    characterName = DeriveCharacterName(data);
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
            entry["characterName"] = characterName != null ? (JToken)characterName : JValue.CreateNull();
            entry["displayName"] = _slotCatalog.ResolveDisplayName(
                slot,
                characterName,
                displayNames);
            return entry;
        }

        private static string DeriveCharacterName(JObject data)
        {
            JArray player = data.Value<JArray>("0");
            if (player == null) return null;
            string name = SafeStr(player, 0);
            return string.IsNullOrWhiteSpace(name) ? null : name;
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
            string exact;
            if (!SaveSlotKey.TryValidateExisting(slot, out exact))
                throw new ArgumentException("invalid slot key", "slot");
            return exact;
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

            string safeName;
            if (!SaveSlotKey.TryValidateExisting(slot, out safeName))
                return BuildError("invalid_slot_key");
            string jsonPath = Path.Combine(_savesDir, safeName + ".json");
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            // reset 表示彻底移除 Launcher 对该身份的全部认知；与 delete
            // 保留 tombstone + 展示名以便玩家辨认/重建的语义不同。
            // 先校验并移除 catalog，避免物理文件已删却留下 catalog-only 幽灵槽位。
            string catalogError;
            if (!_slotCatalog.TryRemoveDisplayName(safeName, out catalogError))
                return BuildError("slot_catalog_reset_failed:" + catalogError);

            Exception deleteError = null;
            lock (_lock)
            {
                try { if (File.Exists(jsonPath)) File.Delete(jsonPath); }
                catch (Exception ex)
                {
                    deleteError = ex;
                    LogManager.Log("[ArchiveTask] reset delete json failed: " + ex.Message);
                }

                try { if (File.Exists(tombPath)) File.Delete(tombPath); }
                catch (Exception ex)
                {
                    if (deleteError == null) deleteError = ex;
                    LogManager.Log("[ArchiveTask] reset delete tombstone failed: " + ex.Message);
                }

                if (deleteError == null)
                {
                    // 物理移除成功：同一临界区内清 accepted-state 基线。
                    _prevSnapshots.Remove(safeName);
                }
            }

            if (deleteError != null)
                return BuildError("slot_reset_delete_failed:" + deleteError.GetType().Name);

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

            string safeName;
            if (!SaveSlotKey.TryValidateExisting(slot, out safeName))
                return BuildError("invalid_slot_key");
            string jsonPath = Path.Combine(_savesDir, safeName + ".json");
            string tombPath = Path.Combine(_savesDir, safeName + ".tombstone");

            string rawData;
            bool tombstoned;
            lock (_lock)
            {
                if (!File.Exists(jsonPath))
                    return BuildError("slot not found: " + safeName);

                rawData = File.ReadAllText(jsonPath, Encoding.UTF8);
                tombstoned = File.Exists(tombPath);
            }
            bool corrupt = false;
            try { JObject.Parse(rawData); }
            catch { corrupt = true; }

            JObject result = new JObject();
            result["success"] = true;
            result["task"] = "archive";
            result["slot"] = safeName;
            result["data"] = rawData;
            result["tombstoned"] = tombstoned;
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
