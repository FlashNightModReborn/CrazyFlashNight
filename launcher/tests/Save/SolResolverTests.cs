// SolResolver 决议树矩阵测试。
// 矩阵对齐 SolResolver.Resolve（SolResolver.cs:107-245）真实语义，不预设"应然"行为。
// 关键事实：
//  - Rust parse 失败 → 直接 DeferToFlash（不 fallback shadow、不比时间戳）
//  - SOL 缺失 + shadow 无 → Empty（不是 MissingBoth）
//  - v3.0 结构合法 + shadow 同秒/更新 → 优先 json_shadow
//  - v3.0 validate 失败 + shadow 同秒 → 可取代（>=）
//  - pre-2.7 + shadow 同秒 → DeferToFlash（>，严格大于才覆盖）

using Newtonsoft.Json.Linq;
using CF7Launcher.Save;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class SolResolverTests
    {
        private const string SLOT = "testSlot";
        private const string SWF = @"E:\game\fake.swf";
        private const string FAKE_SOL_PATH = @"E:\game\fake.swf\savePath.sol";

        // ─────────────── test doubles ───────────────

        private sealed class StubLocator : ISolFileLocator
        {
            public string Result;
            public string FindSolFile(string slot, string swfPath) { return Result; }
        }

        private sealed class StubArchive : IArchiveStateProbe
        {
            public bool Tombstoned;
            public JObject Shadow;
            public string ShadowErr;

            public bool IsTombstoned(string slot) { return Tombstoned; }

            public bool TryLoadShadowSync(string slot, out JObject data, out string error)
            {
                data = Shadow;
                error = ShadowErr;
                return Shadow != null && ShadowErr == null;
            }
        }

        private sealed class StubShadowWriter : IArchiveShadowWriter
        {
            public int Calls;
            public bool ReturnValue = true;
            public string Error;
            public string TargetPath = @"E:\shadow\slot.json";
            public JObject LastData;
            public string LastSlot;

            public bool TrySeedShadowSync(string slot, JObject data, out string targetPath, out string error)
            {
                Calls++;
                LastSlot = slot;
                LastData = data != null ? (JObject)data.DeepClone() : null;
                targetPath = TargetPath;
                error = Error;
                return ReturnValue;
            }
        }

        private sealed class StubParser : ISolParser
        {
            public int ReturnCode = SolParseResult.RC_OK;
            public JObject Data;

            public SolParseResult Parse(string path)
            {
                SolParseResult r = new SolParseResult();
                r.ReturnCode = ReturnCode;
                r.Data = Data;
                return r;
            }
        }

        // ─────────────── fixture helpers ───────────────

        /// <summary>构造一个通过 ValidateResolvedSnapshot 的 3.0 快照。</summary>
        private static JObject ValidMydata(string lastSaved)
        {
            JObject md = new JObject();
            md["version"] = "3.0";
            md["lastSaved"] = lastSaved;

            JArray s0 = new JArray();
            s0.Add("名"); s0.Add("男"); s0.Add(1000); s0.Add(10); s0.Add(500);
            s0.Add(170); s0.Add(5); s0.Add("无"); s0.Add(10000); s0.Add(0);
            s0.Add(new JArray()); s0.Add(0); s0.Add(new JArray()); s0.Add("");
            md["0"] = s0;

            JArray s1 = new JArray();
            for (int i = 0; i < 28; i++) s1.Add(0);
            md["1"] = s1;
            md["2"] = JValue.CreateNull();
            md["3"] = 0;

            JArray s4 = new JArray(); s4.Add(new JArray()); s4.Add(0);
            md["4"] = s4;
            md["5"] = new JArray();
            md["6"] = JValue.CreateNull();

            JArray s7 = new JArray();
            for (int i = 0; i < 5; i++) s7.Add(0);
            md["7"] = s7;

            JObject inv = new JObject();
            inv["背包"] = new JArray();
            inv["装备栏"] = new JObject();
            inv["药剂栏"] = new JArray();
            inv["仓库"] = new JArray();
            inv["战备箱"] = new JArray();
            md["inventory"] = inv;

            JObject col = new JObject();
            col["材料"] = new JObject();
            col["情报"] = new JObject();
            md["collection"] = col;
            md["infrastructure"] = new JObject();

            JObject tasks = new JObject();
            tasks["tasks_to_do"] = new JArray();
            tasks["tasks_finished"] = new JObject();
            tasks["task_chains_progress"] = new JObject();
            md["tasks"] = tasks;

            JObject pets = new JObject();
            JArray pi = new JArray();
            for (int i = 0; i < 5; i++) pi.Add(new JArray());
            pets["宠物信息"] = pi;
            pets["宠物领养限制"] = 5;
            md["pets"] = pets;

            JObject shop = new JObject();
            shop["商城已购买物品"] = new JArray();
            shop["商城购物车"] = new JArray();
            md["shop"] = shop;

            return md;
        }

        /// <summary>v3.0 SOL (包含 test 字段)。</summary>
        private static JObject SoData_V3_Valid(string lastSaved)
        {
            JObject so = new JObject();
            so["test"] = ValidMydata(lastSaved);
            return so;
        }

        /// <summary>v3.0 SOL，但 test 字段结构不通过 validate（缺 inventory）。</summary>
        private static JObject SoData_V3_Invalid(string lastSaved)
        {
            JObject so = new JObject();
            JObject md = ValidMydata(lastSaved);
            md.Remove("inventory");
            so["test"] = md;
            return so;
        }

        /// <summary>v2.7 SOL 带顶层 pets/shop 镜像（Migrate_2_7_to_3_0 可收缩）。</summary>
        private static JObject SoData_V27()
        {
            JObject so = new JObject();
            JObject md = new JObject();
            md["version"] = "2.7";
            so["test"] = md;
            so["tasks_to_do"] = new JArray();
            so["tasks_finished"] = new JObject();
            so["task_chains_progress"] = new JObject();
            JArray pets = new JArray();
            for (int i = 0; i < 5; i++) pets.Add(new JArray());
            so["战宠"] = pets;
            so["宠物领养限制"] = 5;
            so["商城已购买物品"] = new JArray();
            so["商城购物车"] = new JArray();
            // 注入必填 slot 以通过 validate
            JObject mdRef = (JObject)so["test"];
            JObject seed = ValidMydata("2099-01-01 00:00:00");
            foreach (JProperty p in seed.Properties())
            {
                if (p.Name == "version") continue;
                if (p.Name == "tasks" || p.Name == "pets" || p.Name == "shop") continue;
                mdRef[p.Name] = p.Value.DeepClone();
            }
            return so;
        }

        private static JObject SoData_V27_WithNullLegacyMain()
        {
            JObject so = SoData_V27();
            ((JObject)so["test"])["3"] = JValue.CreateNull();
            return so;
        }

        /// <summary>pre-2.7 SOL（没有 version）。</summary>
        private static JObject SoData_Pre27(string lastSaved)
        {
            JObject so = new JObject();
            JObject md = new JObject();
            md["lastSaved"] = lastSaved;
            so["test"] = md;
            return so;
        }

        private static SolResolver MakeResolver(StubLocator loc, StubArchive arch, StubParser parser, StubShadowWriter writer = null)
        {
            return new SolResolver(loc, arch, parser, writer);
        }

        // ─────────────── 决议矩阵（16 行） ───────────────

        [Fact]
        public void Row1_Tombstoned_Deleted()
        {
            var loc = new StubLocator();
            var arch = new StubArchive { Tombstoned = true };
            var parser = new StubParser();

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Deleted, r.Kind);
            Assert.Equal("deleted", r.WireDecision);
        }

        [Fact]
        public void Row2_NoSol_ShadowValid_JsonShadow()
        {
            var loc = new StubLocator { Result = null };
            var arch = new StubArchive { Shadow = ValidMydata("2026-01-01 00:00:00") };
            var parser = new StubParser();

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("json_shadow", r.Source);
        }

        [Fact]
        public void Row3_NoSol_NoShadow_Empty()
        {
            var loc = new StubLocator { Result = null };
            var arch = new StubArchive { Shadow = null, ShadowErr = "not_found" };
            var parser = new StubParser();

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Empty, r.Kind);
            Assert.Equal("empty", r.WireDecision);
        }

        [Fact]
        public void Row4_SolExists_RustParseFails_DeferToFlash()
        {
            // 关键断言：即使 shadow 有效，Rust parse 失败也不 fallback shadow
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive { Shadow = ValidMydata("2099-12-31 23:59:59") };
            var parser = new StubParser { ReturnCode = SolParseResult.RC_PARSE_ERROR, Data = null };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.DeferToFlash, r.Kind);
            Assert.Equal("needs_migration", r.WireDecision);
        }

        [Fact]
        public void Row4b_SolExists_RustRcNotFound_Race_ShadowValid_JsonShadow()
        {
            // locator 找到了路径，但 parse 时文件消失（启动抖动 race）。
            // SolResolver.cs:142-147 把 RC_NOT_FOUND 独立成"SOL 消失"分支，
            // 不走 DeferToFlash，而是 fallback 到 "SOL 缺失" 逻辑。
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive { Shadow = ValidMydata("2026-01-01 00:00:00") };
            var parser = new StubParser { ReturnCode = SolParseResult.RC_NOT_FOUND, Data = null };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("json_shadow", r.Source);
        }

        [Fact]
        public void Row4c_SolExists_RustRcNotFound_Race_NoShadow_Empty()
        {
            // Race + shadow 也不存在 → Empty（不是 DeferToFlash！）
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive { Shadow = null, ShadowErr = "not_found" };
            var parser = new StubParser { ReturnCode = SolParseResult.RC_NOT_FOUND, Data = null };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Empty, r.Kind);
        }

        [Fact]
        public void Row5_SolDeletedFlag_Deleted()
        {
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive();
            JObject so = new JObject();
            so["_deleted"] = true;
            so["test"] = ValidMydata("2026-01-01 00:00:00");
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Deleted, r.Kind);
        }

        [Fact]
        public void Row6_SolNoTestField_ShadowValid_JsonShadow()
        {
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive { Shadow = ValidMydata("2026-02-02 00:00:00") };
            JObject so = new JObject();
            so["version"] = "3.0";
            // 没有 test 字段
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("json_shadow", r.Source);
        }

        [Fact]
        public void Row7_SolNoTestField_NoShadow_Corrupt()
        {
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive { Shadow = null, ShadowErr = "not_found" };
            JObject so = new JObject();
            so["version"] = "3.0";
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Corrupt, r.Kind);
            Assert.Equal("sol_no_test_field", r.CorruptDetail);
        }

        [Fact]
        public void Row8_V3Valid_ShadowNewerOrEqual_PrefersJsonShadow()
        {
            // 关键断言：v3.0 结构合法时，同秒/更新的 shadow 才是启动期权威
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            JObject freshShadow = ValidMydata("2020-01-01 00:00:00");
            ((JArray)freshShadow["0"])[0] = "shadow_name";
            var arch = new StubArchive { Shadow = freshShadow };
            var writer = new StubShadowWriter();
            JObject so = SoData_V3_Valid("2020-01-01 00:00:00");
            ((JArray)((JObject)so["test"])["0"])[0] = "sol_name";
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser, writer).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("json_shadow", r.Source);
            Assert.Equal("shadow_name", r.Snapshot["0"][0].Value<string>());
            Assert.Equal(0, writer.Calls);
        }

        [Fact]
        public void Row8b_V3Valid_ShadowOlder_TrustSol()
        {
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            JObject oldShadow = ValidMydata("2019-12-31 23:59:59");
            ((JArray)oldShadow["0"])[0] = "shadow_name";
            var arch = new StubArchive { Shadow = oldShadow };
            var writer = new StubShadowWriter();
            JObject so = SoData_V3_Valid("2020-01-01 00:00:00");
            ((JArray)((JObject)so["test"])["0"])[0] = "sol_name";
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser, writer).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("sol", r.Source);
            Assert.Equal("sol_name", r.Snapshot["0"][0].Value<string>());
            Assert.Equal(1, writer.Calls);
            Assert.Equal(SLOT, writer.LastSlot);
            Assert.Equal("sol_name", writer.LastData["0"][0].Value<string>());
        }

        [Fact]
        public void Row9_V3Invalid_ShadowNewerOrEqual_JsonShadow()
        {
            // v3.0 结构非法（缺 inventory），shadow lastSaved >= SOL lastSaved → shadow
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive { Shadow = ValidMydata("2026-02-02 12:00:00") };
            JObject so = SoData_V3_Invalid("2026-02-02 12:00:00");  // 同秒
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("json_shadow", r.Source);
        }

        [Fact]
        public void Row10_V3Invalid_ShadowOlderOrMissing_Corrupt()
        {
            // v3.0 结构非法 + shadow 旧 → Corrupt
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive { Shadow = ValidMydata("2020-01-01 00:00:00") };
            JObject so = SoData_V3_Invalid("2026-02-02 12:00:00");
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Corrupt, r.Kind);
            Assert.Equal("v3.0_structure_invalid", r.CorruptDetail);
        }

        [Fact]
        public void Row11_V27_MigrationSucceeds_SolSnapshot()
        {
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive();
            var writer = new StubShadowWriter();
            JObject so = SoData_V27();
            // V27 的 test 字段有足够字段，Migrate_2_7_to_3_0 + MergeTopLevelKeys 应通过 validate
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser, writer).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("sol", r.Source);
            Assert.Equal("3.0", r.Snapshot.Value<string>("version"));
            Assert.Equal(1, writer.Calls);
        }

        [Fact]
        public void Row11b_V27_NullLegacyMain_MigrationDefaultsToZero_SeedsShadow()
        {
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive();
            var writer = new StubShadowWriter();
            JObject so = SoData_V27_WithNullLegacyMain();
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser, writer).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("sol", r.Source);
            Assert.Equal(0, r.Snapshot["3"].Value<int>());
            Assert.Equal(0, r.Snapshot["tasks"]["task_chains_progress"]["主线"].Value<int>());
            Assert.Equal(1, writer.Calls);
        }

        [Fact]
        public void Row11c_V3Valid_SeedFailure_KeepsSnapshotDecision()
        {
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive();
            var writer = new StubShadowWriter { ReturnValue = false, Error = "disk_full" };
            JObject so = SoData_V3_Valid("2020-01-01 00:00:00");
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser, writer).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("sol", r.Source);
            Assert.Equal(1, writer.Calls);
        }

        [Fact]
        public void Row12_V27_MigrationFails_DeferToFlash()
        {
            // v2.7 但 test 字段缺 slot 导致 validate 失败 → DeferToFlash
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive();
            JObject so = new JObject();
            JObject md = new JObject();
            md["version"] = "2.7";
            // 刻意留空，必然 validate 失败
            so["test"] = md;
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.DeferToFlash, r.Kind);
        }

        [Fact]
        public void Row13_Pre27_NoLastSaved_DeferToFlash()
        {
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive();
            JObject so = new JObject();
            JObject md = new JObject();
            // 无 version, 无 lastSaved
            so["test"] = md;
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.DeferToFlash, r.Kind);
        }

        [Fact]
        public void Row14_Pre27_ShadowStrictlyNewer_JsonShadow()
        {
            // pre-2.7: shadow 严格更新（>）才覆盖
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive { Shadow = ValidMydata("2026-02-02 12:00:01") };
            JObject so = SoData_Pre27("2026-02-02 12:00:00");
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("json_shadow", r.Source);
        }

        [Fact]
        public void Row15_Pre27_ShadowSameSecond_DeferToFlash()
        {
            // pre-2.7: shadow 同秒（>=）不够，必须严格 > → DeferToFlash
            // 与 v3.0 分支的 >= 形成分殊（见 SolResolver.cs:230-236 注释）
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive { Shadow = ValidMydata("2026-02-02 12:00:00") };
            JObject so = SoData_Pre27("2026-02-02 12:00:00");
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.DeferToFlash, r.Kind);
        }

        [Fact]
        public void Row16_Pre27_NoShadow_DeferToFlash()
        {
            var loc = new StubLocator { Result = FAKE_SOL_PATH };
            var arch = new StubArchive { Shadow = null, ShadowErr = "not_found" };
            JObject so = SoData_Pre27("2026-02-02 12:00:00");
            var parser = new StubParser { Data = so };

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.DeferToFlash, r.Kind);
        }

        // ─────────────── C2-β: Repairable 决议 ───────────────
        // 前提: C2-α 已在 launcher 启动期 inline 跑过自动修复 (高置信度 fix/clear/drop/rename),
        // 这里的扫描是兜底, 检测残留 manual_required / preserve_placeholder 类 fffd.

        [Fact]
        public void Repairable_ShadowWithL0Fffd_ReturnsRepairableWithReport()
        {
            // 角色名 L0 fffd: C2-α 不会动 → 必须由 bootstrap 卡片人工处理.
            JObject shadow = ValidMydata("2026-02-02 12:00:00");
            shadow["0"][0] = "玩家�";  // L0 manual

            var loc = new StubLocator { Result = null };
            var arch = new StubArchive { Shadow = shadow };
            var parser = new StubParser();

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Repairable, r.Kind);
            Assert.Equal("repairable", r.WireDecision);
            Assert.Equal("json_shadow", r.Source);
            Assert.NotNull(r.Snapshot);
            Assert.NotNull(r.CorruptionReport);
            Assert.Equal(1, (int)r.CorruptionReport["totalFffd"]);
            Assert.Equal(1, (int)r.CorruptionReport["byLayer"]["L0"]);
            Assert.Equal(0, (int)r.CorruptionReport["byLayer"]["L1"]);

            JArray items = (JArray)r.CorruptionReport["items"];
            Assert.Single(items);
            JObject it0 = (JObject)items[0];
            Assert.Equal("L0", (string)it0["layer"]);
            Assert.Equal("value", (string)it0["spot"]);
            JArray path = (JArray)it0["path"];
            Assert.Equal(2, path.Count);
            Assert.Equal("0", (string)path[0]);
            Assert.Equal("0", (string)path[1]);
        }

        [Fact]
        public void Repairable_ShadowMixedLayers_ReportCountsByLayer()
        {
            // 同一 snapshot 含多种残留 fffd, 校验 byLayer 累加.
            JObject shadow = ValidMydata("2026-02-02 12:00:00");
            shadow["0"][0] = "玩家�";                              // L0 自由文本

            JObject equip = new JObject();
            equip["上装装备"] = new JObject();
            equip["上装装备"]["name"] = "黑色�夫装";              // L1 mod / item
            equip["上装装备"]["value"] = new JObject();
            equip["上装装备"]["value"]["mods"] = new JArray();
            equip["上装装备"]["value"]["level"] = 1;
            shadow["inventory"]["装备栏"] = equip;

            var loc = new StubLocator { Result = null };
            var arch = new StubArchive { Shadow = shadow };
            var parser = new StubParser();

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Repairable, r.Kind);
            Assert.Equal(2, (int)r.CorruptionReport["totalFffd"]);
            Assert.Equal(1, (int)r.CorruptionReport["byLayer"]["L0"]);
            Assert.Equal(1, (int)r.CorruptionReport["byLayer"]["L1"]);
        }

        [Fact]
        public void Repairable_CleanShadow_StaysSnapshot()
        {
            // 干净 shadow → 不应被误判为 Repairable.
            var loc = new StubLocator { Result = null };
            var arch = new StubArchive { Shadow = ValidMydata("2026-02-02 12:00:00") };
            var parser = new StubParser();

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Null(r.CorruptionReport);
        }

        [Fact]
        public void Repairable_ObjectKeyFffd_SpotIsKey()
        {
            // 装备槽位 key 损坏 (e.g. '上装装备' → '上�装备') C2-α 走 Manual fallback,
            // SolResolver 应识别为 Repairable + items[0].spot=="key".
            JObject shadow = ValidMydata("2026-02-02 12:00:00");
            JObject equip = new JObject();
            JObject slotVal = new JObject();
            slotVal["name"] = "黑色功夫装";
            slotVal["value"] = new JObject();
            slotVal["value"]["mods"] = new JArray();
            slotVal["value"]["level"] = 1;
            equip["上�装备"] = slotVal;
            shadow["inventory"]["装备栏"] = equip;

            var loc = new StubLocator { Result = null };
            var arch = new StubArchive { Shadow = shadow };
            var parser = new StubParser();

            var r = MakeResolver(loc, arch, parser).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Repairable, r.Kind);
            JArray items = (JArray)r.CorruptionReport["items"];
            Assert.Single(items);
            Assert.Equal("key", (string)((JObject)items[0])["spot"]);
        }
    }
}
