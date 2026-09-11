// SaveSettlementInboxRegressionTests — synthetic regression fixture for the
// 2026-09-11 tester incident shape (worker 06-save-regression). The fixture is
// anonymized and minimal on purpose: it is NOT the real player save and must
// not be presented as real-save E2E evidence.
//
// Real-shape facts reproduced here (verified via runtime sol_parser on the
// supplied SOL, see tmp/focus-recovery-20260912/tester-settlement-manifest.json):
//  - pending v1 settlement persists in `prepared` with remainingCount == 0 and
//    manifest/remainingManifest/receipts as AMF0 empty objects {}
//  - ext.rewardInbox is still v1 with three unclaimed legacy batches,
//    supplyKeys, committed receipts and activeClaimRoot == null
//  - C# only repairs known-empty arrays; v1 inbox and non-empty malformed
//    containers must pass through untouched for AS2-side authority
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class SaveSettlementInboxRegressionTests
    {
        private const string SLOT = "cf7_regress_settlement";
        private const string SWF = @"E:\game\fake.swf";
        private const string FAKE_SOL = @"E:\game\fake.swf\cf7_regress_settlement.sol";

        // ─────────────── test doubles (same contract as SolResolverTests) ────

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
            public JObject LastData;

            public bool TrySeedShadowSync(string slot, JObject data, out string targetPath, out string error)
            {
                Calls++;
                LastData = data != null ? (JObject)data.DeepClone() : null;
                targetPath = @"E:\shadow\slot.json";
                error = null;
                return true;
            }
        }

        private sealed class StubParser : ISolParser
        {
            public int ReturnCode = SolParseResult.RC_OK;
            public JObject Data;

            public SolParseResult Parse(string path)
            {
                return new SolParseResult { ReturnCode = ReturnCode, Data = Data };
            }
        }

        // ─────────────── synthetic fixture ───────────────

        /// <summary>
        /// Minimal valid v3.0 mydata carrying the incident shape:
        /// prepared pending settlement with remainingCount 0 + empty-object
        /// array fields, and a v1 rewardInbox with three unclaimed batches.
        /// </summary>
        private static JObject IncidentMydata()
        {
            JObject md = new JObject();
            md["version"] = "3.0";
            md["lastSaved"] = "2026-09-11 23:51:53";

            JArray s0 = new JArray();
            s0.Add("回归角色甲"); s0.Add("男"); s0.Add(1000); s0.Add(100); s0.Add(500);
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
            inv["背包"] = new JObject();
            inv["装备栏"] = new JObject();
            inv["药剂栏"] = new JObject();
            inv["仓库"] = new JObject();
            inv["战备箱"] = new JObject();
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
            JArray petInfo = new JArray();
            for (int i = 0; i < 5; i++) petInfo.Add(new JArray());
            pets["宠物信息"] = petInfo;
            pets["宠物领养限制"] = 5;
            md["pets"] = pets;

            JObject shop = new JObject();
            // AMF0 empty-object shapes, as found inside the real SOL.
            shop["商城已购买物品"] = new JObject();
            shop["商城购物车"] = new JObject();
            md["shop"] = shop;

            JObject report = new JObject();
            report["v"] = 1;
            report["runId"] = "run.synthetic.1";
            report["stageName"] = "合成撤退关";
            report["difficulty"] = "简单";
            report["outcome"] = "retreat";
            report["activeFrames"] = 100;
            report["totalKills"] = 2;
            report["omittedKillTypes"] = 0;
            report["totalItemGains"] = 10;
            report["totalItemLosses"] = 1;
            report["omittedItemFlowTypes"] = 0;
            report["rewardRollOmissions"] = 0;
            report["kills"] = new JObject();      // AMF0 empty-object shape
            report["itemFlows"] = new JObject();  // AMF0 empty-object shape

            JObject pending = new JObject();
            pending["v"] = 1;
            pending["settlementId"] = "stage.settlement.3";
            pending["runId"] = "run.synthetic.1";
            pending["runRevision"] = 1;
            pending["state"] = "prepared";
            pending["outcome"] = "retreat";
            pending["life"] = "alive";
            pending["capacity"] = 8;
            pending["report"] = report;
            pending["manifest"] = new JObject();
            pending["remainingManifest"] = new JObject();
            pending["remainingCount"] = 0;
            pending["receipts"] = new JObject();
            pending["deliverAfterSettlement"] = false;

            JObject store = new JObject();
            store["v"] = 1;
            store["nextSeq"] = 4;
            store["pending"] = pending;
            store["lastTerminal"] = JObject.Parse(
                "{'v':1,'settlementId':'stage.settlement.2','terminalState':'claimed'}");

            JObject inbox = new JObject();
            inbox["v"] = 1;
            inbox["sequence"] = 5;
            inbox["authorityRevision"] = 13;
            inbox["batches"] = JArray.Parse(@"[
                {'batchId':'open.3','sourceKind':'item_use','sourceItemName':'材料盒子',
                 'openOperationId':'itemuse.synthetic.1',
                 'entries':[{'entryId':'open.3.e1','itemName':'普通hp药剂','quantity':1,'remaining':1}]},
                {'batchId':'open.4','sourceKind':'item_use','sourceItemName':'强化石大盒',
                 'openOperationId':'itemuse.synthetic.2',
                 'entries':[{'entryId':'open.4.e1','itemName':'强化石','quantity':200,'remaining':200}]},
                {'batchId':'supply.5','sourceKind':'online_supply','sourceItemName':'在线补给包·Ⅰ',
                 'openOperationId':'online_supply:synthetic',
                 'entries':[{'entryId':'supply.5.e1','itemName':'在线补给包·Ⅰ','quantity':1,'remaining':1}]}]");
            inbox["receipts"] = JArray.Parse("[{'kind':'consume','status':'committed'}]");
            inbox["migrations"] = new JObject();
            inbox["supplyKeys"] = JArray.Parse("['online_supply:synthetic']");
            inbox["activeClaimRoot"] = JValue.CreateNull();
            inbox["claimRootTerminal"] = JValue.CreateNull();

            JObject ext = new JObject();
            ext["stageSettlement"] = store;
            ext["rewardInbox"] = inbox;
            md["ext"] = ext;
            return md;
        }

        /// <summary>Wrap mydata in an soData shell with dual-written mirrors.</summary>
        private static JObject IncidentSoData()
        {
            JObject md = IncidentMydata();
            JObject so = new JObject();
            so["test"] = md;
            so["tasks_to_do"] = md["tasks"]["tasks_to_do"].DeepClone();
            so["tasks_finished"] = md["tasks"]["tasks_finished"].DeepClone();
            so["task_chains_progress"] = md["tasks"]["task_chains_progress"].DeepClone();
            so["战宠"] = md["pets"]["宠物信息"].DeepClone();
            so["宠物领养限制"] = 5;
            so["商城已购买物品"] = md["shop"]["商城已购买物品"].DeepClone();
            so["商城购物车"] = md["shop"]["商城购物车"].DeepClone();
            return so;
        }

        private static SolResolver Resolver(StubLocator locator, StubArchive archive,
            StubParser parser, StubShadowWriter writer)
        {
            return new SolResolver(locator, archive, parser, writer);
        }

        // ─────────────── tests ───────────────

        [Fact]
        public void IncidentShape_SolSource_PendingEmptiesNormalizedAndInboxUntouched()
        {
            var locator = new StubLocator { Result = FAKE_SOL };
            var archive = new StubArchive();
            var parser = new StubParser { Data = IncidentSoData() };
            var writer = new StubShadowWriter();

            SolResolveResult r = Resolver(locator, archive, parser, writer).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("sol", r.Source);
            Assert.True(SaveMigrator.ValidateResolvedSnapshot(r.Snapshot));

            JObject pending = r.Snapshot["ext"]["stageSettlement"]["pending"] as JObject;
            Assert.NotNull(pending);
            Assert.Equal("prepared", pending.Value<string>("state"));
            Assert.Equal(0, pending.Value<int>("remainingCount"));
            Assert.Empty((JArray)pending["manifest"]);
            Assert.Empty((JArray)pending["remainingManifest"]);
            Assert.Empty((JArray)pending["receipts"]);
            Assert.Empty((JArray)pending["report"]["kills"]);
            Assert.Empty((JArray)pending["report"]["itemFlows"]);

            // v1 inbox is AS2 authority — C# must not migrate or normalize it.
            JObject inbox = r.Snapshot["ext"]["rewardInbox"] as JObject;
            Assert.NotNull(inbox);
            Assert.Equal(1, inbox.Value<int>("v"));
            Assert.Equal(3, ((JArray)inbox["batches"]).Count);
            Assert.Equal("open.4", inbox["batches"][1].Value<string>("batchId"));
            Assert.Equal(200, inbox["batches"][1]["entries"][0].Value<int>("remaining"));
            Assert.Equal(JTokenType.Null, inbox["activeClaimRoot"].Type);
            Assert.Equal(1, ((JArray)inbox["supplyKeys"]).Count);

            Assert.Equal(1, writer.Calls);
            Assert.Equal("stage.settlement.3",
                writer.LastData["ext"]["stageSettlement"]["pending"].Value<string>("settlementId"));
        }

        [Fact]
        public void IncidentShape_ShadowSource_SameNormalizationApplied()
        {
            var locator = new StubLocator { Result = null };
            var archive = new StubArchive { Shadow = IncidentMydata() };
            var parser = new StubParser();
            var writer = new StubShadowWriter();

            SolResolveResult r = Resolver(locator, archive, parser, writer).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            Assert.Equal("json_shadow", r.Source);
            Assert.Empty((JArray)r.Snapshot["ext"]["stageSettlement"]["pending"]["manifest"]);
            Assert.Equal(0, writer.Calls); // shadow source never re-seeds itself
        }

        [Fact]
        public void IncidentShape_MalformedPendingContainer_PreservedForAs2FailClosed()
        {
            JObject so = IncidentSoData();
            JObject pending = so["test"]["ext"]["stageSettlement"]["pending"] as JObject;
            pending["manifest"] = JObject.Parse("{'slot':0}"); // non-empty: real corruption

            var locator = new StubLocator { Result = FAKE_SOL };
            var archive = new StubArchive();
            var parser = new StubParser { Data = so };
            var writer = new StubShadowWriter();

            SolResolveResult r = Resolver(locator, archive, parser, writer).Resolve(SLOT, SWF);

            // ext is outside ValidateResolvedSnapshot's 28-field contract: the
            // resolver still hands the snapshot to AS2, which fail-closes on
            // decode. C# must preserve the evidence byte-for-byte.
            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            JObject manifest = r.Snapshot["ext"]["stageSettlement"]["pending"]["manifest"] as JObject;
            Assert.NotNull(manifest);
            Assert.Equal(0, manifest.Value<int>("slot"));
        }

        [Fact]
        public void IncidentShape_V1InboxEmptyContainers_NeverFabricatedByCSharp()
        {
            JObject so = IncidentSoData();
            JObject inbox = so["test"]["ext"]["rewardInbox"] as JObject;
            inbox["batches"] = new JObject();   // v1 empty-object: AS2's problem, not C#'s
            inbox["supplyKeys"] = new JObject();

            var locator = new StubLocator { Result = FAKE_SOL };
            var archive = new StubArchive();
            var parser = new StubParser { Data = so };
            var writer = new StubShadowWriter();

            SolResolveResult r = Resolver(locator, archive, parser, writer).Resolve(SLOT, SWF);

            Assert.Equal(DecisionKind.Snapshot, r.Kind);
            JObject resolvedInbox = r.Snapshot["ext"]["rewardInbox"] as JObject;
            Assert.IsType<JObject>(resolvedInbox["batches"]);
            Assert.IsType<JObject>(resolvedInbox["supplyKeys"]);
            Assert.Equal(1, resolvedInbox.Value<int>("v"));
        }
    }
}
