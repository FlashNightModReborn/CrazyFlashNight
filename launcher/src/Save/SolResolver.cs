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
        Corrupt
    }

    /// <summary>
    /// Result of a slot resolution. WireDecision is the string sent over the
    /// bootstrap_handshake response (launcher → Flash). Kind is the internal
    /// classification used for logs and upstream decision logic.
    /// </summary>
    public sealed class SolResolveResult
    {
        public DecisionKind Kind;
        public string WireDecision;     // "snapshot" / "deleted" / "empty" / "needs_migration" / "corrupt"
        public JObject Snapshot;        // normalizedMydata; non-null when Kind == Snapshot
        public string Source;           // "sol" / "json_shadow" — non-null when Kind == Snapshot
        public string CorruptDetail;    // only for Kind == Corrupt

        public static SolResolveResult NewSnapshot(JObject snap, string source)
        {
            SolResolveResult r = new SolResolveResult();
            r.Kind = DecisionKind.Snapshot;
            r.WireDecision = "snapshot";
            r.Snapshot = snap;
            r.Source = source;
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
        private readonly SolFileLocator _locator;
        private readonly ArchiveTask _archive;

        public SolResolver(SolFileLocator locator, ArchiveTask archive)
        {
            _locator = locator;
            _archive = archive;
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
            bool shadowValid =
                _archive.TryLoadShadowSync(slot, out shadow, out shadowErr)
                && SaveMigrator.ValidateResolvedSnapshot(shadow);
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
                SolParseResult parse = SolParserNative.Parse(solPath);
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
                    return SolResolveResult.NewSnapshot(shadow, "json_shadow");
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
                    return SolResolveResult.NewSnapshot(shadow, "json_shadow");
                return SolResolveResult.NewCorrupt("sol_no_test_field");
            }

            string ver = mydata.Value<string>("version");

            if (ver == "3.0")
            {
                SaveMigrator.MergeTopLevelKeys(mydata, soData);
                if (SaveMigrator.ValidateResolvedSnapshot(mydata))
                    return SolResolveResult.NewSnapshot(mydata, "sol");

                LogManager.Log("[SolResolver] v3.0 structure invalid — shadow freshness check");
                string solTs = mydata.Value<string>("lastSaved");
                if (shadowValid && solTs != null)
                {
                    string shadowTs = shadow.Value<string>("lastSaved");
                    if (shadowTs != null
                        && string.Compare(shadowTs, solTs, StringComparison.Ordinal) >= 0)
                    {
                        return SolResolveResult.NewSnapshot(shadow, "json_shadow");
                    }
                }
                return SolResolveResult.NewCorrupt("v3.0_structure_invalid");
            }

            if (ver == "2.7")
            {
                SaveMigrator.Migrate_2_7_to_3_0(mydata, soData);
                SaveMigrator.MergeTopLevelKeys(mydata, soData);
                if (SaveMigrator.ValidateResolvedSnapshot(mydata))
                    return SolResolveResult.NewSnapshot(mydata, "sol");
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
                    return SolResolveResult.NewSnapshot(shadow, "json_shadow");
                }
            }
            LogManager.Log("[SolResolver] pre-2.7 AS2 sync migration — DeferToFlash");
            return SolResolveResult.NewDeferToFlash();
        }
    }
}
