// CF7:ME SOL resolver — orchestrates SOL parse + shadow read + migration +
// validation, returning a SolResolveResult that GameLaunchFlow embeds in the
// bootstrap_handshake response. C# 5 syntax.

using System;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    public enum DecisionKind
    {
        Snapshot,
        Deleted,
        Empty,
        NeedsMigration,     // pre-2.7 / 2.7 C# migration failed → defer to AS2
        DeferToFlash,       // Rust parse failed → wire reuses NeedsMigration
        Corrupt,
        // C2-β: snapshot 已 normalize/validate 通过, 但仍残留 U+FFFD 字符 (C2-α 的高置信度
        // 自动修复未能闭环, 剩 manual_required / preserve_placeholder 类). 走 bootstrap 修复
        // 卡片协议 (saveDecision="repairable"), 由用户在卡片上做决策后 launcher push
        // task=repair_resolved 给 AS2.
        Repairable
    }

    /// <summary>
    /// Result of a slot resolution. WireDecision is the string sent over the
    /// bootstrap_handshake response (launcher → Flash). Kind is the internal
    /// classification used for logs and upstream decision logic.
    /// </summary>
    public sealed class SolResolveResult
    {
        public DecisionKind Kind;
        public string WireDecision;     // "snapshot" / "deleted" / "empty" / "needs_migration" / "corrupt" / "repairable"
        public JObject Snapshot;        // normalizedMydata; non-null when Kind == Snapshot 或 Repairable
        public string Source;           // "sol" / "json_shadow" — non-null when Kind == Snapshot 或 Repairable
        public string CorruptDetail;    // only for Kind == Corrupt
        // Repairable 时携带的 wire 报告: { totalFffd, byLayer:{L0,L1,L2,L3}, items:[{path,broken,layer,kind,spot}] }.
        // 用于 BootstrapPanel 修复卡片初始展示; 卡片打开后会再发 cmd=repair_detect 拉一次完整 plan (含候选).
        public JObject CorruptionReport;

        public static SolResolveResult NewSnapshot(JObject snap, string source)
        {
            SolResolveResult r = new SolResolveResult();
            r.Kind = DecisionKind.Snapshot;
            r.WireDecision = "snapshot";
            r.Snapshot = snap;
            r.Source = source;
            return r;
        }

        public static SolResolveResult NewRepairable(JObject snap, string source, JObject corruptionReport)
        {
            SolResolveResult r = new SolResolveResult();
            r.Kind = DecisionKind.Repairable;
            r.WireDecision = "repairable";
            r.Snapshot = snap;
            r.Source = source;
            r.CorruptionReport = corruptionReport;
            return r;
        }

        public static SolResolveResult NewDeleted()
        {
            SolResolveResult r = new SolResolveResult();
            r.Kind = DecisionKind.Deleted;
            r.WireDecision = "deleted";
            return r;
        }

        public static SolResolveResult NewEmpty()
        {
            SolResolveResult r = new SolResolveResult();
            r.Kind = DecisionKind.Empty;
            r.WireDecision = "empty";
            return r;
        }

        public static SolResolveResult NewNeedsMigration()
        {
            SolResolveResult r = new SolResolveResult();
            r.Kind = DecisionKind.NeedsMigration;
            r.WireDecision = "needs_migration";
            return r;
        }

        public static SolResolveResult NewDeferToFlash()
        {
            SolResolveResult r = new SolResolveResult();
            r.Kind = DecisionKind.DeferToFlash;
            r.WireDecision = "needs_migration";  // same wire literal; log distinguishes
            return r;
        }

        public static SolResolveResult NewCorrupt(string detail)
        {
            SolResolveResult r = new SolResolveResult();
            r.Kind = DecisionKind.Corrupt;
            r.WireDecision = "corrupt";
            r.CorruptDetail = detail;
            return r;
        }

        public static SolResolveResult CorruptFromException(Exception ex)
        {
            return NewCorrupt("exception: " + ex.GetType().Name + ": " + ex.Message);
        }
    }

    /// <summary>
    /// Resolver: lock-free, invoked from StartGame (outside GameLaunchFlow
    /// state lock). Uses ArchiveTask sync APIs for tombstone / shadow reads.
    /// </summary>
    public class SolResolver
    {
        private readonly ISolFileLocator _locator;
        private readonly IArchiveStateProbe _archive;
        private readonly ISolParser _parser;
        private readonly IArchiveShadowWriter _shadowWriter;

        public SolResolver(ISolFileLocator locator, IArchiveStateProbe archive, ISolParser parser, IArchiveShadowWriter shadowWriter = null)
        {
            _locator = locator;
            _archive = archive;
            _parser = parser;
            _shadowWriter = shadowWriter;
        }

        public SolResolveResult Resolve(string slot, string swfPath)
        {
            // 1. Launcher tombstone → deleted (short-circuit)
            if (_archive.IsTombstoned(slot))
            {
                LogManager.Log("[SolResolver] tombstoned slot=" + slot);
                return SolResolveResult.NewDeleted();
            }

            // 2. Preload shadow for all branches that may need it
            JObject shadow;
            string shadowErr;
            bool shadowLoaded = _archive.TryLoadShadowSync(slot, out shadow, out shadowErr);
            if (shadowLoaded && shadow != null)
            {
                SaveMigrator.NormalizeResolvedSnapshot(shadow);
            }
            bool shadowValid = shadowLoaded && SaveMigrator.ValidateResolvedSnapshot(shadow);
            if (!shadowValid && shadow != null)
            {
                LogManager.Log("[SolResolver] shadow present but invalid (validator rejected)");
            }
            else if (shadow == null && shadowErr != null && shadowErr != "not_found")
            {
                LogManager.Log("[SolResolver] shadow read error: " + shadowErr);
            }

            // 3. Locate + parse SOL
            string solPath = _locator.FindSolFile(slot, swfPath);
            bool solExists = (solPath != null);
            JObject soData = null;
            if (solExists)
            {
                SolParseResult parse = _parser.Parse(solPath);
                if (parse.ReturnCode == SolParserNative.RC_OK)
                {
                    soData = parse.Data;
                }
                else if (parse.ReturnCode == SolParserNative.RC_NOT_FOUND)
                {
                    // Race: existed at Find time, gone now. Treat as no SOL.
                    solExists = false;
                    LogManager.Log("[SolResolver] SOL disappeared between find and parse: " + solPath);
                }
                else
                {
                    LogManager.Log("[SolResolver] SOL parse failed rc=" + parse.ReturnCode
                        + " err=" + (parse.Error != null ? parse.Error : "n/a"));
                }
            }

            // 4. SOL missing
            if (!solExists)
            {
                if (shadowValid)
                    return NewSnapshotResult(slot, shadow, "json_shadow");
                return SolResolveResult.NewEmpty();
            }

            // 5. SOL exists but Rust parse failed → DeferToFlash (not shadow!)
            if (soData == null)
            {
                LogManager.Log("[SolResolver] DeferToFlash: rust parse failed path=" + solPath);
                return SolResolveResult.NewDeferToFlash();
            }

            // 6. Parsed soData — honor _deleted / version / validate
            JToken deletedToken = soData["_deleted"];
            if (deletedToken != null
                && deletedToken.Type == JTokenType.Boolean
                && deletedToken.Value<bool>())
            {
                return SolResolveResult.NewDeleted();
            }

            JObject mydata = soData["test"] as JObject;
            if (mydata == null)
            {
                LogManager.Log("[SolResolver] soData has no `test` key — structural anomaly");
                if (shadowValid)
                    return NewSnapshotResult(slot, shadow, "json_shadow");
                return SolResolveResult.NewCorrupt("sol_no_test_field");
            }

            string ver = mydata.Value<string>("version");

            if (ver == "3.0")
            {
                SaveMigrator.MergeTopLevelKeys(mydata, soData);
                SaveMigrator.NormalizeResolvedSnapshot(mydata);
                if (SaveMigrator.ValidateResolvedSnapshot(mydata))
                {
                    if (shadowValid)
                    {
                        string validSolTs = mydata.Value<string>("lastSaved");
                        string shadowTs = shadow.Value<string>("lastSaved");
                        if (validSolTs != null
                            && shadowTs != null
                            && string.Compare(shadowTs, validSolTs, StringComparison.Ordinal) >= 0)
                        {
                            LogManager.Log("[SolResolver] v3.0 shadow newer-or-equal than SOL — prefer json_shadow");
                            return NewSnapshotResult(slot, shadow, "json_shadow");
                        }
                    }
                    return NewSnapshotResult(slot, mydata, "sol");
                }

                LogManager.Log("[SolResolver] v3.0 structure invalid — shadow freshness check");
                string solTs = mydata.Value<string>("lastSaved");
                if (shadowValid && solTs != null)
                {
                    string shadowTs = shadow.Value<string>("lastSaved");
                    if (shadowTs != null
                        && string.Compare(shadowTs, solTs, StringComparison.Ordinal) >= 0)
                    {
                        return NewSnapshotResult(slot, shadow, "json_shadow");
                    }
                }
                return SolResolveResult.NewCorrupt("v3.0_structure_invalid");
            }

            if (ver == "2.7")
            {
                SaveMigrator.Migrate_2_7_to_3_0(mydata, soData);
                SaveMigrator.MergeTopLevelKeys(mydata, soData);
                if (SaveMigrator.ValidateResolvedSnapshot(mydata))
                    return NewSnapshotResult(slot, mydata, "sol");
                LogManager.Log("[SolResolver] v2.7 C# migration failed — DeferToFlash");
                return SolResolveResult.NewDeferToFlash();
            }

            // pre-2.7: only shadow-freshness path is viable; otherwise DeferToFlash.
            string pre27Ts = mydata.Value<string>("lastSaved");
            if (pre27Ts == null)
            {
                LogManager.Log("[SolResolver] pre-2.7 SOL without lastSaved — DeferToFlash");
                return SolResolveResult.NewDeferToFlash();
            }
            if (shadowValid)
            {
                string shadowTs = shadow.Value<string>("lastSaved");
                // pre-2.7 分支刻意用 `>`（严格大于），与 v3.0 分支的 `>=` 分殊：
                //   - v3.0 分支：SOL 结构已被 validator 判异常 → SOL 本身可疑
                //     → 同秒 shadow 亦可取代（`>=`）。
                //   - pre-2.7 分支：SOL 结构合法只是版本旧 → SOL 本身无嫌疑
                //     → shadow 必须严格更新才值得覆盖（`>`）。
                // lastSaved 是秒级精度；同秒歧义下保守让 AS2 再跑一次 pre-2.7 → 3.0
                // 迁移，比错误地用旧 shadow 覆盖更新的 SOL 安全。
                if (shadowTs != null
                    && string.Compare(shadowTs, pre27Ts, StringComparison.Ordinal) > 0)
                {
                    return NewSnapshotResult(slot, shadow, "json_shadow");
                }
            }
            LogManager.Log("[SolResolver] pre-2.7 AS2 sync migration — DeferToFlash");
            return SolResolveResult.NewDeferToFlash();
        }

        private SolResolveResult NewSnapshotResult(string slot, JObject snapshot, string source)
        {
            if (string.Equals(source, "sol", StringComparison.Ordinal))
            {
                string targetPath = null;
                string error = null;
                bool seeded = false;

                if (_shadowWriter != null)
                {
                    try
                    {
                        seeded = _shadowWriter.TrySeedShadowSync(slot, snapshot, out targetPath, out error);
                    }
                    catch (Exception ex)
                    {
                        error = ex.GetType().Name + ": " + ex.Message;
                    }
                }
                else
                {
                    error = "no_shadow_writer";
                }

                LogManager.Log("[SolResolver] snapshot source=sol slot=" + slot
                    + " seedAuthority=" + seeded
                    + " target=" + (targetPath ?? "n/a")
                    + (error != null ? " error=" + error : string.Empty));
            }
            else
            {
                LogManager.Log("[SolResolver] snapshot source=" + source
                    + " slot=" + slot + " seedAuthority=false");
            }

            // C2-β: C2-α 已在 launcher 启动期对 saves/{slot}.json inline 自动修复过高置信度 fffd
            // (fix_value/clear_value/drop_value/rename_key); 这里 snapshot 是 SolResolver 选出来的
            // 权威拷贝 (json_shadow 或 sol). 再扫一次, 如果还有残留 fffd 必为 manual_required /
            // preserve_placeholder 类, 必须由 bootstrap 卡片 + 用户决策才能闭环.
            //   注意: 即便 source=sol 也扫 — 自动修复只动 shadow, 这里的 sol 路径表示
            //         shadow 缺失或更旧, snapshot 来自 SOL 反序列化, 仍可能携带历史 fffd.
            JObject report = null;
            try
            {
                SaveCorruptionReport scan = SaveCorruptionScanner.Scan(snapshot);
                if (scan.Total > 0)
                {
                    report = BuildCorruptionReportJson(scan);
                    LogManager.Log("[SolResolver] repairable slot=" + slot
                        + " source=" + source
                        + " fffd=" + scan.Total
                        + " byLayer=L0:" + scan.L0 + ",L1:" + scan.L1 + ",L2:" + scan.L2 + ",L3:" + scan.L3);
                    return SolResolveResult.NewRepairable(snapshot, source, report);
                }
            }
            catch (Exception ex)
            {
                // 扫描异常 → 退化为普通 Snapshot, 让 AS2 兜底 (C4) 处理. 不阻断启动.
                LogManager.Log("[SolResolver] corruption scan failed slot=" + slot
                    + " ex=" + ex.GetType().Name + ": " + ex.Message);
            }

            return SolResolveResult.NewSnapshot(snapshot, source);
        }

        /// <summary>
        /// 把 SaveCorruptionReport 序列化为 wire JSON. 字段稳定:
        ///   { totalFffd, byLayer:{L0,L1,L2,L3},
        ///     items:[ { path:["a","b"], broken:"...", layer:"L1", kind:"Item", spot:"value"|"key" } ] }
        /// 不携带候选 — 候选由后续 cmd=repair_detect 拉取 (依赖 RepairDictionary, SolResolver 不持有).
        /// </summary>
        internal static JObject BuildCorruptionReportJson(SaveCorruptionReport scan)
        {
            JObject root = new JObject();
            root["totalFffd"] = scan.Total;

            JObject byLayer = new JObject();
            byLayer["L0"] = scan.L0;
            byLayer["L1"] = scan.L1;
            byLayer["L2"] = scan.L2;
            byLayer["L3"] = scan.L3;
            root["byLayer"] = byLayer;

            JArray items = new JArray();
            for (int i = 0; i < scan.Items.Count; i++)
            {
                SaveCorruptionItem it = scan.Items[i];
                JObject obj = new JObject();
                JArray pathArr = new JArray();
                for (int p = 0; p < it.PathSegments.Length; p++) pathArr.Add(it.PathSegments[p]);
                obj["path"] = pathArr;
                obj["broken"] = it.BrokenString;
                obj["layer"] = it.Rule.Layer.ToString();
                obj["kind"] = it.Rule.Kind.ToString();
                obj["spot"] = (it.Spot == SaveCorruptionSpot.Key) ? "key" : "value";
                items.Add(obj);
            }
            root["items"] = items;
            return root;
        }
    }
}
