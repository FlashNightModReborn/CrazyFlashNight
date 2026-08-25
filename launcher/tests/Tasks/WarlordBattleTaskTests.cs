using System;
using System.IO;
using System.Threading;
using CF7Launcher.Data;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class WarlordBattleTaskTests
    {
        [Fact]
        public void Prepare_ProjectsCardsAsPetIdentityWithoutLegacyUnitType()
        {
            string root = CreateRoot();
            var calibration = new ArenaCalibrationTask(
                root,
                delegate { return false; },
                delegate(string payload) { },
                delegate(int frames) { return 20; });
            var task = new WarlordBattleTask(calibration, BuildPetCatalog());
            JObject request = BuildRequest();
            JObject envelope = BuildEnvelope(request);

            WarlordBattleTask.PreparedBattle prepared;
            JObject result = task.Prepare(envelope, "warlord.panel.1", out prepared);

            Assert.True((bool)result["success"]);
            Assert.NotNull(prepared);
            JObject calibrationCase = (JObject)prepared.CalibrationControl["calibrationCase"];
            JObject attacker = (JObject)calibrationCase["blueRoster"][0];
            JObject defender = (JObject)calibrationCase["redRoster"][0];
            Assert.Equal("pet-red-12", (string)attacker["sourceId"]);
            Assert.Equal(12, (int)attacker["petId"]);
            Assert.Equal("敌人-军阀狙击兵", (string)attacker["identifier"]);
            Assert.Equal("partner", (string)attacker["rosterType"]);
            Assert.Empty((JArray)attacker["strategicPromotions"]);
            Assert.Null(attacker["type"]);
            Assert.Equal(15, (int)defender["petId"]);
            Assert.Equal("observe_only", (string)calibrationCase["authorityContext"]["economyMode"]);
            Assert.Equal("catalog_identifier+strategic_progression_v1",
                (string)calibrationCase["authorityContext"]["petProjectionProfile"]);
            Assert.False((bool)calibrationCase["authorityContext"]["playerPetSnapshotUsed"]);
        }

        [Fact]
        public void Prepare_ProjectsPetsXmlProgressionPrefixAndRejectsDrift()
        {
            string root = CreateRoot();
            var calibration = new ArenaCalibrationTask(
                root,
                delegate { return false; },
                delegate(string payload) { },
                delegate(int frames) { return 20; });
            var task = new WarlordBattleTask(calibration, BuildPetCatalog());
            JObject request = BuildRequest();
            request["state"]["factions"]["red"]["cards"]["12"]["level"] = 10;
            request["state"]["factions"]["red"]["cards"]["12"]["purchasedPromotions"] =
                new JArray("基础训练");

            WarlordBattleTask.PreparedBattle prepared;
            JObject accepted = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);

            Assert.True((bool)accepted["success"]);
            Assert.Equal("基础训练", (string)prepared.CalibrationControl
                ["calibrationCase"]["blueRoster"][0]["strategicPromotions"][0]);
            Assert.True(task.CancelPrepared(prepared, "test_complete"));

            JObject drifted = BuildRequest();
            drifted["state"]["factions"]["red"]["cards"]["12"]["level"] = 25;
            drifted["state"]["factions"]["red"]["cards"]["12"]["purchasedPromotions"] =
                new JArray("强化药剂");
            JObject rejected = task.Prepare(
                BuildEnvelope(drifted), "warlord.panel.1", out prepared);
            Assert.False((bool)rejected["success"]);
            Assert.Contains("progression prefix", (string)rejected["message"]);
        }

        [Fact]
        public void Prepare_RejectsDigestMismatchAndUnknownPetCard()
        {
            string root = CreateRoot();
            var calibration = new ArenaCalibrationTask(
                root,
                delegate { return false; },
                delegate(string payload) { },
                delegate(int frames) { return 20; });
            var task = new WarlordBattleTask(calibration, BuildPetCatalog());
            JObject request = BuildRequest();
            JObject badDigest = BuildEnvelope(request);
            badDigest["inputDigest"] = "sha256:" + new string('0', 64);

            WarlordBattleTask.PreparedBattle prepared;
            JObject digestResult = task.Prepare(badDigest, "warlord.panel.1", out prepared);
            Assert.False((bool)digestResult["success"]);
            Assert.Equal("input_digest_mismatch", (string)digestResult["error"]);
            Assert.Null(prepared);

            JObject unknownRequest = BuildRequest();
            unknownRequest["state"]["pieces"]["pet-red-12"]["cardId"] = 999;
            unknownRequest["state"]["factions"]["red"]["cards"]["999"] =
                new JObject { ["level"] = 1 };
            JObject unknownEnvelope = BuildEnvelope(unknownRequest);
            JObject unknownResult = task.Prepare(
                unknownEnvelope, "warlord.panel.1", out prepared);
            Assert.False((bool)unknownResult["success"]);
            Assert.Contains("pets.xml", (string)unknownResult["message"]);
        }

        [Fact]
        public void Prepare_RejectsOutOfTurnDuplicateMembershipAndFailedAssaultReentry()
        {
            string root = CreateRoot();
            var calibration = new ArenaCalibrationTask(
                root,
                delegate { return false; },
                delegate(string payload) { },
                delegate(int frames) { return 20; });
            var task = new WarlordBattleTask(calibration, BuildPetCatalog());
            WarlordBattleTask.PreparedBattle prepared;

            JObject outOfTurn = BuildRequest();
            outOfTurn["state"]["activeFactionId"] = "blue";
            JObject outOfTurnResult = task.Prepare(
                BuildEnvelope(outOfTurn), "warlord.panel.1", out prepared);
            Assert.False((bool)outOfTurnResult["success"]);
            Assert.Contains("active faction", (string)outOfTurnResult["message"]);

            JObject duplicate = BuildRequest();
            duplicate["state"]["map"]["nodes"]["North-Choke"]["pieceIds"] =
                new JArray("pet-blue-15", "pet-blue-15");
            JObject duplicateResult = task.Prepare(
                BuildEnvelope(duplicate), "warlord.panel.1", out prepared);
            Assert.False((bool)duplicateResult["success"]);
            Assert.Contains("duplicated", (string)duplicateResult["message"]);

            JObject reentry = BuildRequest();
            reentry["state"]["pieces"]["pet-red-12"]["failedAssaultLocks"] =
                new JArray("North-Choke");
            JObject reentryResult = task.Prepare(
                BuildEnvelope(reentry), "warlord.panel.1", out prepared);
            Assert.False((bool)reentryResult["success"]);
            Assert.Contains("failed assault", (string)reentryResult["message"]);
        }

        [Fact]
        public void As2TerminalReceipt_ReopensFrozenStateWithObserveOnlyPetEconomy()
        {
            string root = CreateRoot();
            ArenaCalibrationTask calibration = null;
            calibration = new ArenaCalibrationTask(
                root,
                delegate { return true; },
                delegate(string payload)
                {
                    JObject command = JObject.Parse(payload.TrimEnd('\0'));
                    calibration.HandleFlashResponse(new JObject
                    {
                        ["task"] = "arena_calibration_response",
                        ["callId"] = (int)command["callId"],
                        ["success"] = true,
                        ["status"] = "finished",
                        ["winner"] = "blue",
                        ["frames"] = 180,
                        ["durationMs"] = 6000,
                        ["authorityContext"] = command["authorityContext"].DeepClone(),
                        ["blue"] = new JObject
                        {
                            ["maxHp"] = 2000, ["remainHp"] = 1250, ["aliveCount"] = 1
                        },
                        ["red"] = new JObject
                        {
                            ["maxHp"] = 3000, ["remainHp"] = 0, ["aliveCount"] = 0
                        },
                        ["blueUnitResults"] = new JArray
                        {
                            new JObject
                            {
                                ["sourceId"] = "pet-red-12", ["petId"] = 12,
                                ["identifier"] = "敌人-军阀狙击兵", ["level"] = 1,
                                ["strategicPromotions"] = new JArray(),
                                ["startMaxHp"] = 2000, ["remainHp"] = 1250,
                                ["hpPermille"] = 625, ["alive"] = true,
                                ["resolvedType"] = "敌人-军阀狙击兵"
                            }
                        },
                        ["redUnitResults"] = new JArray
                        {
                            new JObject
                            {
                                ["sourceId"] = "pet-blue-15", ["petId"] = 15,
                                ["identifier"] = "敌人-军阀重装兵", ["level"] = 1,
                                ["strategicPromotions"] = new JArray(),
                                ["startMaxHp"] = 3000, ["remainHp"] = 0,
                                ["hpPermille"] = 0, ["alive"] = false,
                                ["resolvedType"] = "敌人-军阀重装兵"
                            }
                        },
                        ["errors"] = new JArray()
                    }, delegate(string ignored) { });
                },
                delegate(int frames) { return 3000; });
            var task = new WarlordBattleTask(calibration, BuildPetCatalog());
            JObject reopened = null;
            var reopenedEvent = new ManualResetEventSlim(false);
            task.SetResumeOpenHandler(delegate(JObject init)
            {
                reopened = init;
                reopenedEvent.Set();
            });
            JObject request = BuildRequest();
            WarlordBattleTask.PreparedBattle prepared;
            JObject prepare = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);
            Assert.True((bool)prepare["success"]);

            JObject started = task.StartPrepared(prepared);

            Assert.True((bool)started["success"]);
            Assert.True(reopenedEvent.Wait(3000), "AS2 terminal receipt did not reopen Warlord");
            Assert.Equal("phase-c-as2", (string)reopened["mode"]);
            Assert.Equal("as2", (string)reopened["battleAuthority"]);
            Assert.Equal("warlord.as2-battle-request.v1",
                (string)reopened["resume"]["request"]["schema"]);
            JObject receipt = (JObject)reopened["resume"]["receipt"];
            Assert.True(
                (string)receipt["status"] == "accepted",
                "Unexpected AS2 receipt: " + receipt);
            Assert.Equal(625,
                (int)reopened["resume"]["receipt"]["attackerUnits"][0]["hpPermille"]);
            Assert.False((bool)reopened["resume"]["receipt"]
                ["economyObservation"]["writesPlayerState"]);
            Assert.Equal("none", (string)reopened["resume"]["receipt"]
                ["economyObservation"]["settlementPolicy"]);
            Assert.Equal("xml_base_price", (string)reopened["resume"]["receipt"]
                ["economyObservation"]["catalogPriceBasis"]);
            Assert.Equal(8000, (int)reopened["resume"]["receipt"]
                ["economyObservation"]["attacker"]["catalogBaseExposureGold"]);
            Assert.Equal(10000, (int)reopened["resume"]["receipt"]
                ["economyObservation"]["defender"]["catalogBaseLostGold"]);
            Assert.Equal(8, (int)reopened["resume"]["receipt"]
                ["economyObservation"]["attacker"]["strategicExposureGold"]);
            Assert.Equal(60, (int)reopened["resume"]["receipt"]
                ["economyObservation"]["defender"]["strategicLostGold"]);

            var router = new LauncherCommandRouter(
                socketServer: null,
                onSendKey: delegate(System.Windows.Forms.Keys ignored) { },
                onToggleFullscreen: delegate { },
                onToggleLog: delegate { },
                onForceExit: delegate { },
                postToWeb: delegate(string ignored) { });
            using (var host = new PanelHostController(
                delegate(Action pump) { pump(); },
                delegate(Action fire) { fire(); }))
            {
                router.SetPanelHost(host);
                Assert.True(router.TryOpenWarlordResumePanel(reopened));
                Assert.Equal("warlord", host.ActivePanelName);
            }
            Assert.True(task.ConsumeReturnBaseOnFinalClose());
            Assert.False(task.ConsumeReturnBaseOnFinalClose());
        }

        [Fact]
        public void StartPrepared_DisconnectedRestoresKnownNotStartedWithoutReturnBase()
        {
            string root = CreateRoot();
            var calibration = new ArenaCalibrationTask(
                root,
                delegate { return false; },
                delegate(string payload) { },
                delegate(int frames) { return 20; });
            var task = new WarlordBattleTask(calibration, BuildPetCatalog());
            JObject reopened = null;
            task.SetResumeOpenHandler(delegate(JObject init) { reopened = init; });
            WarlordBattleTask.PreparedBattle prepared;
            JObject prepare = task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared);

            JObject started = task.StartPrepared(prepared);

            Assert.True((bool)prepare["success"]);
            Assert.False((bool)started["success"]);
            Assert.NotNull(reopened);
            Assert.Equal("not_started", (string)reopened["resume"]["receipt"]["status"]);
            Assert.False(task.ConsumeReturnBaseOnFinalClose());
        }

        [Fact]
        public void CanonicalDigest_IsIndependentOfObjectInsertionOrder()
        {
            JObject left = JObject.Parse("{\"z\":1,\"nested\":{\"b\":2,\"a\":[3,4]}}");
            JObject right = JObject.Parse("{\"nested\":{\"a\":[3,4],\"b\":2},\"z\":1}");
            Assert.Equal(
                WarlordBattleTask.Sha256OfToken(left),
                WarlordBattleTask.Sha256OfToken(right));
        }

        private static JObject BuildEnvelope(JObject request)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "warlord",
                ["cmd"] = "battle_start",
                ["panelInstanceId"] = "warlord.panel.1",
                ["callId"] = "warlord.call.1",
                ["inputDigest"] = WarlordBattleTask.Sha256OfToken(request),
                ["request"] = request
            };
        }

        private static JObject BuildRequest()
        {
            JObject state = new JObject
            {
                ["schemaVersion"] = 1,
                ["rulesVersion"] = "wargame-demo-v0.1",
                ["gameSeed"] = "warlord-test-seed",
                ["strategicRound"] = 1,
                ["commandSequence"] = 0,
                ["battleOrdinal"] = 0,
                ["phase"] = "FIRST_FACTION_ACTION",
                ["activeFactionId"] = "red",
                ["map"] = new JObject
                {
                    ["nodes"] = new JObject
                    {
                        ["R-Supply"] = new JObject
                        {
                            ["attackWidth"] = 4,
                            ["pieceIds"] = new JArray("pet-red-12")
                        },
                        ["North-Choke"] = new JObject
                        {
                            ["attackWidth"] = 2,
                            ["pieceIds"] = new JArray("pet-blue-15")
                        }
                    },
                    ["edges"] = new JArray
                    {
                        new JObject { ["a"] = "R-Supply", ["b"] = "North-Choke" }
                    }
                },
                ["pieces"] = new JObject
                {
                    ["pet-red-12"] = new JObject
                    {
                        ["pieceId"] = "pet-red-12", ["factionId"] = "red",
                        ["cardId"] = 12, ["nodeId"] = "R-Supply",
                        ["hp"] = 1000, ["maxHp"] = 2000,
                        ["productionGoldValue"] = 8,
                        ["failedAssaultLocks"] = new JArray()
                    },
                    ["pet-blue-15"] = new JObject
                    {
                        ["pieceId"] = "pet-blue-15", ["factionId"] = "blue",
                        ["cardId"] = 15, ["nodeId"] = "North-Choke",
                        ["hp"] = 3000, ["maxHp"] = 3000,
                        ["productionGoldValue"] = 60,
                        ["failedAssaultLocks"] = new JArray()
                    }
                },
                ["factions"] = new JObject
                {
                    ["red"] = new JObject
                    {
                        ["actionPoints"] = 4,
                        ["cards"] = new JObject
                        {
                            ["12"] = new JObject
                            {
                                ["level"] = 1,
                                ["purchasedPromotions"] = new JArray()
                            }
                        }
                    },
                    ["blue"] = new JObject
                    {
                        ["actionPoints"] = 4,
                        ["cards"] = new JObject
                        {
                            ["15"] = new JObject
                            {
                                ["level"] = 1,
                                ["purchasedPromotions"] = new JArray()
                            }
                        }
                    }
                }
            };
            return new JObject
            {
                ["schema"] = "warlord.as2-battle-request.v1",
                ["sessionId"] = "warlord.session.1",
                ["requestId"] = "warlord.request.1",
                ["state"] = state,
                ["command"] = new JObject
                {
                    ["type"] = "MOVE_OR_ATTACK",
                    ["factionId"] = "red",
                    ["pieceIds"] = new JArray("pet-red-12"),
                    ["originNodeId"] = "R-Supply",
                    ["targetNodeId"] = "North-Choke"
                },
                ["clientContext"] = new JObject
                {
                    ["seed"] = "warlord-test-seed",
                    ["preset"] = "standard",
                    ["difficulty"] = "normal",
                    ["mapTheme"] = "desert",
                    ["forceWebglFailure"] = false,
                    ["aiSeenTransitions"] = new JArray()
                }
            };
        }

        private static PetCatalog BuildPetCatalog()
        {
            var catalog = new PetCatalog();
            var sniper = new PetDef
            {
                Id = 12,
                Name = "狙击兵小弟",
                Identifier = "敌人-军阀狙击兵",
                RosterType = "partner",
                Price = 8000
            };
            sniper.Promotions.AddRange(new[] { "基础训练", "强化药剂", "超级血清", "常驻淬毒" });
            catalog.PetsById[12] = sniper;
            var heavy = new PetDef
            {
                Id = 15,
                Name = "重装兵小弟",
                Identifier = "敌人-军阀重装兵",
                RosterType = "partner",
                Price = 10000
            };
            heavy.Promotions.AddRange(new[] { "基础训练", "强化药剂", "超级血清", "常驻淬毒" });
            catalog.PetsById[15] = heavy;
            return catalog;
        }

        private static string CreateRoot()
        {
            string root = Path.Combine(
                Path.GetTempPath(),
                "cf7-warlord-battle-tests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            return root;
        }
    }
}
