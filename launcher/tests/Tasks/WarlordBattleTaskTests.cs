using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
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
        private const string FourFactionPlayer = "river.clan~17";
        private const string FourFactionIndependent = "iron-host.north";
        private const string FourFactionAlly = "cedar_pact";
        private const string FourFactionNeutral = "free.city-2";
        private const string Demo2Player = "player";
        private const string Demo2PactA = "boss-pact-a";
        private const string Demo2Independent = "boss-independent";
        private const string Demo2PactB = "boss-pact-b";

        [Theory]
        [InlineData("demo1-attack", false, "absent", false, "none")]
        [InlineData("demo1-defend", false, "absent", true, "none")]
        [InlineData("demo2-troops-attack", true, "absent", false, "none")]
        [InlineData("demo2-troops-defend", true, "absent", true, "none")]
        [InlineData("demo2-avatar-attack", true, "present", false, "blue")]
        [InlineData("demo2-avatar-defend", true, "present", true, "red")]
        [InlineData("demo2-avatar-away-attack", true, "away", false, "none")]
        [InlineData("demo2-avatar-away-defend", true, "away", true, "none")]
        public void ControlWireMatrix_ActualParticipantsOwnControl(
            string caseId, bool demo2, string avatarPlacement, bool reverse,
            string expectedControl)
        {
            JObject request = demo2
                ? BuildDemo2EncounterRequest("d2-independent-01", "hq", 4,
                    "encounter.near", "near", 180)
                : BuildRequest();
            JObject state = (JObject)request["state"];
            string playerPieceId = "pet-red-12";
            if (avatarPlacement != "absent")
            {
                ConfigureTrustedDemo2PlayerAvatarBattle(request);
                if (avatarPlacement == "away")
                {
                    // 现场失败组合：袁望攻击精锐突击兵，主角仍在另一据点。
                    JObject avatar = (JObject)state["pieces"][playerPieceId];
                    string origin = (string)avatar["nodeId"];
                    JObject elite = (JObject)avatar.DeepClone();
                    playerPieceId = "elite-player-82";
                    elite["pieceId"] = playerPieceId;
                    elite["cardId"] = 82;
                    state["pieces"][playerPieceId] = elite;
                    state["factions"][Demo2Player]["cards"]["82"] = new JObject
                    {
                        ["level"] = 1, ["purchasedPromotions"] = new JArray()
                    };
                    state["map"]["nodes"][origin]["pieceIds"] = new JArray(playerPieceId);
                    state["map"]["nodes"]["d2-player-01"] = new JObject
                    {
                        ["pieceIds"] = new JArray("pet-red-12")
                    };
                    avatar["nodeId"] = "d2-player-01";
                    state["commanders"]["commander.player"]["nodeId"] = "d2-player-01";
                    request["command"]["pieceIds"] = new JArray(playerPieceId);
                }
            }
            if (reverse)
            {
                JObject command = (JObject)request["command"];
                string origin = (string)command["originNodeId"];
                command["originNodeId"] = command["targetNodeId"].DeepClone();
                command["targetNodeId"] = origin;
                command["pieceIds"] = new JArray("pet-blue-15");
                command["factionId"] = state["pieces"]["pet-blue-15"]["factionId"].DeepClone();
                state["activeFactionId"] = command["factionId"].DeepClone();
            }

            JObject outbound = null;
            JObject resumed = null;
            using var resumeReady = new ManualResetEventSlim(false);
            var task = new WarlordBattleTask(BuildPetCatalog(), command =>
            {
                outbound = (JObject)command.DeepClone();
                return true;
            });
            task.SetResumeOpenHandler((JObject init) =>
            {
                resumed = init;
                resumeReady.Set();
            });
            JObject result = task.Prepare(BuildEnvelope(request), "warlord.panel.1", out var prepared);
            Assert.True((bool)result["success"], (string)result["message"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);
            Assert.NotNull(outbound);
            Assert.Equal(expectedControl, (string)outbound["encounter"]["playerControlledSide"]);
            int avatars = 0;
            foreach (string side in new[] { "blue", "red" })
                foreach (JObject unit in (JArray)outbound["encounter"][side + "Roster"])
                    if ((string)unit["projectionKind"] == "player_avatar")
                    {
                        avatars++;
                        Assert.Equal(expectedControl, side);
                    }
            Assert.Equal(avatarPlacement == "present" ? 1 : 0, avatars);

            // 可选导出实际 transport payload，交由同轮 Flash 测试直接消费；
            // 不另写一套 AS2 请求样本来代替 Host 输出。
            string fixtureDir = Environment.GetEnvironmentVariable("CF7_WARLORD_WIRE_FIXTURE_DIR");
            if (!string.IsNullOrEmpty(fixtureDir))
            {
                Directory.CreateDirectory(fixtureDir);
                File.WriteAllText(Path.Combine(fixtureDir, caseId + ".json"),
                    outbound.ToString(Formatting.None), new UTF8Encoding(false));
            }
            task.HandleActionEncounterTerminal(BuildCompletedActionTerminal(outbound));
            Assert.True(resumeReady.Wait(3000), "completed encounter did not return to the board");
            Assert.Equal("accepted", (string)resumed["resume"]["receipt"]["status"]);
            Assert.Equal(expectedControl, (string)resumed["resume"]["receipt"]["playerControlledSide"]);
        }

        [Fact]
        public void Prepare_ProjectsCardsAsPetIdentityWithoutLegacyUnitType()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            JObject request = BuildRequest();
            JObject envelope = BuildEnvelope(request);

            WarlordBattleTask.PreparedBattle prepared;
            JObject result = task.Prepare(envelope, "warlord.panel.1", out prepared);

            Assert.True((bool)result["success"]);
            Assert.NotNull(prepared);
            JObject encounterControl = prepared.ActionEncounterControl;
            JObject attacker = (JObject)encounterControl["blueRoster"][0];
            JObject defender = (JObject)encounterControl["redRoster"][0];
            Assert.Equal("warlord.action-encounter-control.v2",
                (string)prepared.ActionEncounterControl["schema"]);
            Assert.Equal("none",
                (string)prepared.ActionEncounterControl["playerControlledSide"]);
            Assert.Equal("pet_projection", (string)attacker["projectionKind"]);
            Assert.Equal("pet-red-12", (string)attacker["sourceId"]);
            Assert.Equal(12, (int)attacker["petId"]);
            Assert.Equal("敌人-军阀狙击兵", (string)attacker["identifier"]);
            Assert.Equal("partner", (string)attacker["rosterType"]);
            Assert.Empty((JArray)attacker["strategicPromotions"]);
            Assert.Null(attacker["type"]);
            Assert.Equal(15, (int)defender["petId"]);
            Assert.Equal("observe_only", (string)encounterControl["authorityContext"]["economyMode"]);
            Assert.Equal("catalog_identifier+strategic_progression_v1",
                (string)encounterControl["authorityContext"]["petProjectionProfile"]);
            Assert.False((bool)encounterControl["authorityContext"]["playerPetSnapshotUsed"]);
            Assert.Equal("wedge", (string)encounterControl["blueFormation"]);
            Assert.Equal("line", (string)encounterControl["redFormation"]);
            Assert.Equal(650, (int)encounterControl["spawnDistance"]);
            Assert.Equal("legacy_v1_default",
                (string)encounterControl["authorityContext"]["encounterProjectionMode"]);
            Assert.Null((string)encounterControl["authorityContext"]["encounterProfileRef"]);
            Assert.Equal("far",
                (string)encounterControl["authorityContext"]["encounterDistanceBand"]);
        }

        [Fact]
        public void Prepare_Demo2ProjectsOnlyTrustedPlayerCommanderAsAvatarAndKeepsEnemyPetProjection()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            JObject request = BuildDemo2EncounterRequest(
                "d2-independent-01",
                "hq",
                4,
                "encounter.near",
                "near",
                180);
            ConfigureTrustedDemo2PlayerAvatarBattle(request);

            WarlordBattleTask.PreparedBattle prepared;
            JObject result = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);

            Assert.True((bool)result["success"], (string)result["message"]);
            JObject control = prepared.ActionEncounterControl;
            Assert.Equal("warlord.action-encounter-control.v2",
                (string)control["schema"]);
            Assert.Equal("blue", (string)control["playerControlledSide"]);
            JObject avatar = (JObject)control["blueRoster"][0];
            Assert.Equal("player_avatar", (string)avatar["projectionKind"]);
            Assert.Equal("commander.player", (string)avatar["commanderId"]);
            Assert.Equal("character.player-avatar", (string)avatar["characterId"]);
            Assert.Equal(Demo2Player, (string)avatar["factionId"]);
            Assert.Equal(500, (int)avatar["hpPermille"]);
            Assert.Null(avatar["petId"]);
            Assert.Null(avatar["identifier"]);
            Assert.Null(avatar["level"]);
            Assert.Null(avatar["strategicPromotions"]);

            JObject enemy = (JObject)control["redRoster"][0];
            Assert.Equal("pet_projection", (string)enemy["projectionKind"]);
            Assert.Equal(113, (int)enemy["petId"]);
            Assert.Equal("敌人-Surveyor", (string)enemy["identifier"]);
            Assert.Equal("partner", (string)enemy["rosterType"]);
            Assert.True(task.CancelPrepared(prepared, "test_complete"));
        }

        [Theory]
        [InlineData(111, "敌人-Itinerant")]
        [InlineData(112, "敌人-Gazer")]
        [InlineData(113, "敌人-Surveyor")]
        public void Prepare_Demo2EnemyCommanderPetIdsRemainCatalogProjections(
            int petId,
            string identifier)
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            JObject request = BuildDemo2EncounterRequest(
                "d2-independent-01", "hq", 4,
                "encounter.near", "near", 180);
            ConfigureTrustedDemo2PlayerAvatarBattle(request);
            request["state"]["pieces"]["pet-blue-15"]["cardId"] = petId;
            request["state"]["factions"][Demo2Independent]["cards"] =
                new JObject
                {
                    [petId.ToString()] = new JObject
                    {
                        ["level"] = 1,
                        ["purchasedPromotions"] = new JArray()
                    }
                };
            ((JObject)request["state"]["commanders"])
                .Property("commander.boss-independent").Remove();

            WarlordBattleTask.PreparedBattle prepared;
            JObject result = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);

            Assert.True((bool)result["success"], (string)result["message"]);
            JObject enemy = (JObject)prepared.ActionEncounterControl["redRoster"][0];
            Assert.Equal("pet_projection", (string)enemy["projectionKind"]);
            Assert.Equal(petId, (int)enemy["petId"]);
            Assert.Equal(identifier, (string)enemy["identifier"]);
            Assert.Null(enemy["commanderId"]);
            Assert.True(task.CancelPrepared(prepared, "test_complete"));
        }

        [Fact]
        public void Prepare_Demo2PlayerAvatarIdentityFailsClosedAgainstWebForgeryOrDowngrade()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            WarlordBattleTask.PreparedBattle prepared;

            JObject forgedPiece = BuildDemo2EncounterRequest(
                "d2-independent-01", "hq", 4,
                "encounter.near", "near", 180);
            ConfigureTrustedDemo2PlayerAvatarBattle(forgedPiece);
            forgedPiece["state"]["pieces"]["pet-red-12"]["projectionKind"] =
                "player_avatar";
            JObject forgedPieceResult = task.Prepare(
                BuildEnvelope(forgedPiece), "warlord.panel.1", out prepared);
            Assert.False((bool)forgedPieceResult["success"]);
            Assert.Contains("may not declare encounter projection identity",
                (string)forgedPieceResult["message"]);

            JObject forgedCharacter = BuildDemo2EncounterRequest(
                "d2-independent-01", "hq", 4,
                "encounter.near", "near", 180);
            ConfigureTrustedDemo2PlayerAvatarBattle(forgedCharacter);
            forgedCharacter["state"]["commanders"]["commander.player"]
                ["characterId"] = "character.web-forged";
            JObject forgedCharacterResult = task.Prepare(
                BuildEnvelope(forgedCharacter), "warlord.panel.1", out prepared);
            Assert.False((bool)forgedCharacterResult["success"]);
            Assert.Contains("does not match Host authority",
                (string)forgedCharacterResult["message"]);

            JObject missingSidecar = BuildDemo2EncounterRequest(
                "d2-independent-01", "hq", 4,
                "encounter.near", "near", 180);
            ConfigureTrustedDemo2PlayerAvatarBattle(missingSidecar);
            ((JObject)missingSidecar["state"]).Property("commanders").Remove();
            JObject missingSidecarResult = task.Prepare(
                BuildEnvelope(missingSidecar), "warlord.panel.1", out prepared);
            Assert.False((bool)missingSidecarResult["success"]);
            Assert.Contains("requires the trusted commander sidecar",
                (string)missingSidecarResult["message"]);
        }

        [Fact]
        public void As2TerminalReceipt_Demo2KeepsAvatarIdentitySeparateFromPetEconomy()
        {
            JObject command = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    command = (JObject)outbound.DeepClone();
                    return true;
                });
            JObject reopened = null;
            var reopenedEvent = new ManualResetEventSlim(false);
            task.SetResumeOpenHandler(delegate(JObject init)
            {
                reopened = init;
                reopenedEvent.Set();
            });
            JObject request = BuildDemo2EncounterRequest(
                "d2-independent-01",
                "hq",
                4,
                "encounter.near",
                "near",
                180);
            ConfigureTrustedDemo2PlayerAvatarBattle(request);

            WarlordBattleTask.PreparedBattle prepared;
            JObject prepare = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);
            Assert.True((bool)prepare["success"], (string)prepare["message"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);
            task.HandleActionEncounterTerminal(BuildCompletedActionTerminal(command));

            Assert.True(reopenedEvent.Wait(3000),
                "Demo2 avatar terminal did not reopen Warlord");
            JObject receipt = (JObject)reopened["resume"]["receipt"];
            Assert.Equal("accepted", (string)receipt["status"]);
            Assert.Equal("blue", (string)receipt["playerControlledSide"]);
            JObject avatar = (JObject)receipt["attackerUnits"][0];
            Assert.Equal("player_avatar", (string)avatar["projectionKind"]);
            Assert.Equal("commander.player", (string)avatar["commanderId"]);
            Assert.Equal("character.player-avatar", (string)avatar["characterId"]);
            Assert.Equal(17, (int)avatar["runtimeLevel"]);
            Assert.Null(avatar["petId"]);

            JObject economy = (JObject)receipt["economyObservation"];
            Assert.False((bool)economy["writesPlayerState"]);
            Assert.Equal(0, (int)economy["attacker"]["catalogBaseExposureGold"]);
            Assert.Equal(0, (int)economy["attacker"]["catalogBaseExposureK"]);
            Assert.False((bool)economy["attacker"]["units"][0]["catalogEligible"]);
            Assert.Equal("player_avatar",
                (string)economy["attacker"]["units"][0]["projectionKind"]);
            Assert.Equal(12000, (int)economy["defender"]["catalogBaseLostK"]);
            Assert.Equal("pet_projection",
                (string)economy["defender"]["units"][0]["projectionKind"]);
        }

        [Fact]
        public void As2TerminalReceipt_Demo2AvatarIdentityDriftFreezesAsUnknown()
        {
            JObject command = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    command = (JObject)outbound.DeepClone();
                    return true;
                });
            JObject reopened = null;
            var reopenedEvent = new ManualResetEventSlim(false);
            task.SetResumeOpenHandler(delegate(JObject init)
            {
                reopened = init;
                reopenedEvent.Set();
            });
            JObject request = BuildDemo2EncounterRequest(
                "d2-independent-01", "hq", 4,
                "encounter.near", "near", 180);
            ConfigureTrustedDemo2PlayerAvatarBattle(request);
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared)["success"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);
            JObject terminal = BuildCompletedActionTerminal(command);
            terminal["payload"]["result"]["blueUnitResults"][0]
                ["characterId"] = "character.as2-drift";

            task.HandleActionEncounterTerminal(terminal);

            Assert.True(reopenedEvent.Wait(3000),
                "avatar identity drift did not reopen frozen Warlord state");
            JObject receipt = (JObject)reopened["resume"]["receipt"];
            Assert.Equal("unknown", (string)receipt["status"]);
            Assert.Equal("receipt_invalid", (string)receipt["error"]);
            Assert.Contains("player avatar identity changed",
                (string)receipt["message"]);
        }

        [Fact]
        public void Prepare_PreservesLegacyBlueAttackWhileActionBlueStillMeansAttacker()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            JObject request = BuildRequest();
            request["state"]["activeFactionId"] = "blue";
            request["command"]["factionId"] = "blue";
            request["command"]["pieceIds"] = new JArray("pet-blue-15");
            request["command"]["originNodeId"] = "North-Choke";
            request["command"]["targetNodeId"] = "R-Supply";

            WarlordBattleTask.PreparedBattle prepared;
            JObject result = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);

            Assert.True((bool)result["success"], (string)result["message"]);
            JObject encounterControl = prepared.ActionEncounterControl;
            Assert.Equal("pet-blue-15", (string)encounterControl["blueRoster"][0]["sourceId"]);
            Assert.Equal("pet-red-12", (string)encounterControl["redRoster"][0]["sourceId"]);
            Assert.Equal("blue", (string)encounterControl["authorityContext"]["attackerFactionId"]);
            Assert.Equal("red", (string)encounterControl["authorityContext"]["defenderFactionId"]);
            Assert.True(task.CancelPrepared(prepared, "test_complete"));
        }

        [Theory]
        [InlineData("R-HQ", "encounter.near", "near", 180)]
        [InlineData("R-Supply", "encounter.medium", "medium", 360)]
        [InlineData("R-Economy", "encounter.medium", "medium", 360)]
        [InlineData("North-Choke", "encounter.far", "far", 650)]
        [InlineData("Center-Command", "encounter.far", "far", 650)]
        [InlineData("South-Depot", "encounter.far", "far", 650)]
        [InlineData("B-Economy", "encounter.medium", "medium", 360)]
        [InlineData("B-Supply", "encounter.medium", "medium", 360)]
        [InlineData("B-HQ", "encounter.near", "near", 180)]
        public void Prepare_ProjectsCanonicalDemo1EncounterForEveryTargetNode(
            string targetNodeId,
            string expectedProfile,
            string expectedBand,
            int expectedDistance)
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            JObject request = BuildRequest();
            SetDemo1EncounterContract(request, targetNodeId);

            WarlordBattleTask.PreparedBattle prepared;
            JObject result = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);

            Assert.True((bool)result["success"], (string)result["message"]);
            JObject encounterControl = prepared.ActionEncounterControl;
            JObject authority = (JObject)encounterControl["authorityContext"];
            Assert.Equal(expectedDistance, (int)encounterControl["spawnDistance"]);
            Assert.Equal("demo1_exact_v1", (string)authority["encounterProjectionMode"]);
            Assert.Equal("demo-nine-node", (string)authority["mapDefinitionId"]);
            Assert.Equal(
                "sha256:9DA8013D3B7D1C1F5C5B27BDA813F1ADC9E2C8C5C80F3680B9FFDF773A9B76B0",
                (string)authority["strategicConfigDigest"]);
            Assert.Equal("demo1-encounter-distance", (string)authority["encounterDefinitionId"]);
            Assert.Equal("warlord.encounter-distance.v1", (string)authority["encounterRulesVersion"]);
            Assert.Equal(
                "sha256:6D94E0ABCA11BE5AE1574219D30E4E8E1E3890293496FB2192E081AB24DFE29E",
                (string)authority["encounterConfigDigest"]);
            Assert.Equal(expectedProfile, (string)authority["encounterProfileRef"]);
            Assert.Equal(expectedBand, (string)authority["encounterDistanceBand"]);
            Assert.Equal(expectedDistance, (int)authority["encounterSpawnDistance"]);
            Assert.True(task.CancelPrepared(prepared, "test_complete"));
        }

        [Theory]
        [InlineData(
            "d2-independent-01", "hq", 4,
            "encounter.near", "near", 180)]
        [InlineData(
            "d2-independent-04", "economy", 3,
            "encounter.medium", "medium", 360)]
        [InlineData(
            "d2-arm-independent-03", "contested-industry", 4,
            "encounter.far", "far", 650)]
        public void Prepare_ProjectsTrustedDemo2TargetEncounterForEveryDistanceBand(
            string targetNodeId,
            string kind,
            int attackWidth,
            string expectedProfile,
            string expectedBand,
            int expectedDistance)
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            JObject request = BuildDemo2EncounterRequest(
                targetNodeId,
                kind,
                attackWidth,
                expectedProfile,
                expectedBand,
                expectedDistance);

            WarlordBattleTask.PreparedBattle prepared;
            JObject result = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);

            Assert.True((bool)result["success"], (string)result["message"]);
            JObject encounterControl = prepared.ActionEncounterControl;
            JObject authority = (JObject)encounterControl["authorityContext"];
            Assert.Equal(expectedDistance, (int)encounterControl["spawnDistance"]);
            Assert.Equal(
                "demo2_target_exact_v1",
                (string)authority["encounterProjectionMode"]);
            Assert.Equal("demo2-thick-x-80", (string)authority["mapDefinitionId"]);
            Assert.Null((string)authority["strategicConfigDigest"]);
            Assert.Equal(
                "demo1-encounter-distance",
                (string)authority["encounterDefinitionId"]);
            Assert.Equal(expectedProfile, (string)authority["encounterProfileRef"]);
            Assert.Equal(expectedBand, (string)authority["encounterDistanceBand"]);
            Assert.Equal(expectedDistance, (int)authority["encounterSpawnDistance"]);
            Assert.Equal(Demo2Player, (string)authority["attackerFactionId"]);
            Assert.Equal(
                Demo2Independent,
                (string)authority["defenderFactionId"]);
            Assert.True(task.CancelPrepared(prepared, "test_complete"));
        }

        [Fact]
        public void Prepare_RejectsDemo2TargetProfileUnknownNodeAndEncounterConfigDrift()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            WarlordBattleTask.PreparedBattle prepared;

            JObject badProfile = BuildDemo2EncounterRequest(
                "d2-independent-01",
                "hq",
                4,
                "encounter.near",
                "near",
                180);
            badProfile["state"]["map"]["nodes"]["d2-independent-01"]
                ["encounterProfileRef"] = "encounter.medium";
            JObject badProfileResult = task.Prepare(
                BuildEnvelope(badProfile), "warlord.panel.1", out prepared);
            Assert.False((bool)badProfileResult["success"]);
            Assert.Contains(
                "Demo2 target node does not match its canonical profile",
                (string)badProfileResult["message"]);

            JObject missingDistance = BuildDemo2EncounterRequest(
                "d2-independent-04",
                "economy",
                3,
                "encounter.medium",
                "medium",
                360);
            ((JObject)missingDistance["state"]["map"]["nodes"]
                ["d2-independent-04"]).Property("spawnDistance").Remove();
            JObject missingDistanceResult = task.Prepare(
                BuildEnvelope(missingDistance), "warlord.panel.1", out prepared);
            Assert.False((bool)missingDistanceResult["success"]);
            Assert.Contains(
                "spawnDistance must be a positive integer",
                (string)missingDistanceResult["message"]);

            JObject unknownNode = BuildDemo2EncounterRequest(
                "d2-arm-independent-03",
                "contested-industry",
                4,
                "encounter.far",
                "far",
                650);
            JObject unknownNodes = (JObject)unknownNode["state"]["map"]["nodes"];
            JToken unknownTarget = unknownNodes["d2-arm-independent-03"];
            unknownNodes["d2-unknown-01"] = unknownTarget;
            unknownNodes.Property("d2-arm-independent-03").Remove();
            unknownNode["state"]["map"]["edges"][0]["b"] = "d2-unknown-01";
            unknownNode["state"]["pieces"]["pet-blue-15"]["nodeId"] =
                "d2-unknown-01";
            unknownNode["command"]["targetNodeId"] = "d2-unknown-01";
            JObject unknownNodeResult = task.Prepare(
                BuildEnvelope(unknownNode), "warlord.panel.1", out prepared);
            Assert.False((bool)unknownNodeResult["success"]);
            Assert.Contains(
                "no supported Demo2 encounter profile",
                (string)unknownNodeResult["message"]);

            JObject badEncounterConfig = BuildDemo2EncounterRequest(
                "d2-independent-01",
                "hq",
                4,
                "encounter.near",
                "near",
                180);
            badEncounterConfig["state"]["encounter"]["configDigest"] =
                "sha256:" + new string('0', 64);
            JObject badEncounterConfigResult = task.Prepare(
                BuildEnvelope(badEncounterConfig),
                "warlord.panel.1",
                out prepared);
            Assert.False((bool)badEncounterConfigResult["success"]);
            Assert.Contains(
                "state.encounter identity is unsupported or incomplete",
                (string)badEncounterConfigResult["message"]);

            JObject missingSidecar = BuildDemo2EncounterRequest(
                "d2-independent-01",
                "hq",
                4,
                "encounter.near",
                "near",
                180);
            ((JObject)missingSidecar["state"]).Property("encounter").Remove();
            JObject missingSidecarResult = task.Prepare(
                BuildEnvelope(missingSidecar), "warlord.panel.1", out prepared);
            Assert.False((bool)missingSidecarResult["success"]);
            Assert.Contains(
                "Demo2 requires the complete state.encounter sidecar",
                (string)missingSidecarResult["message"]);
        }

        [Fact]
        public void Prepare_RejectsEncounterIdentityProfileBandDistanceAndPartialLegacyTamper()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            WarlordBattleTask.PreparedBattle prepared;

            JObject badDigest = BuildRequest();
            SetDemo1EncounterContract(badDigest, "North-Choke");
            badDigest["state"]["encounter"]["configDigest"] =
                "sha256:" + new string('0', 64);
            JObject badDigestResult = task.Prepare(
                BuildEnvelope(badDigest), "warlord.panel.1", out prepared);
            Assert.False((bool)badDigestResult["success"]);
            Assert.Contains("state.encounter identity", (string)badDigestResult["message"]);

            JObject partialSidecar = BuildRequest();
            SetDemo1EncounterContract(partialSidecar, "North-Choke");
            ((JObject)partialSidecar["state"]["encounter"])
                .Property("configDigest").Remove();
            JObject partialSidecarResult = task.Prepare(
                BuildEnvelope(partialSidecar), "warlord.panel.1", out prepared);
            Assert.False((bool)partialSidecarResult["success"]);
            Assert.Contains("unsupported or incomplete", (string)partialSidecarResult["message"]);

            JObject badMap = BuildRequest();
            SetDemo1EncounterContract(badMap, "North-Choke");
            badMap["state"]["mapDefinitionId"] = "spoofed-nine-node";
            JObject badMapResult = task.Prepare(
                BuildEnvelope(badMap), "warlord.panel.1", out prepared);
            Assert.False((bool)badMapResult["success"]);
            Assert.Contains("strategic identity", (string)badMapResult["message"]);

            JObject badProfile = BuildRequest();
            SetDemo1EncounterContract(badProfile, "North-Choke");
            badProfile["state"]["map"]["nodes"]["North-Choke"]["encounterProfileRef"] =
                "encounter.near";
            JObject badProfileResult = task.Prepare(
                BuildEnvelope(badProfile), "warlord.panel.1", out prepared);
            Assert.False((bool)badProfileResult["success"]);
            Assert.Contains("canonical profile", (string)badProfileResult["message"]);

            JObject badBand = BuildRequest();
            SetDemo1EncounterContract(badBand, "North-Choke");
            badBand["state"]["map"]["nodes"]["North-Choke"]["distanceBand"] = "near";
            JObject badBandResult = task.Prepare(
                BuildEnvelope(badBand), "warlord.panel.1", out prepared);
            Assert.False((bool)badBandResult["success"]);
            Assert.Contains("canonical profile", (string)badBandResult["message"]);

            JObject badDistance = BuildRequest();
            SetDemo1EncounterContract(badDistance, "North-Choke");
            badDistance["state"]["map"]["nodes"]["North-Choke"]["spawnDistance"] = 651;
            JObject badDistanceResult = task.Prepare(
                BuildEnvelope(badDistance), "warlord.panel.1", out prepared);
            Assert.False((bool)badDistanceResult["success"]);
            Assert.Contains("canonical profile", (string)badDistanceResult["message"]);

            JObject unknownNode = BuildRequest();
            SetDemo1EncounterContract(unknownNode, "North-Choke");
            unknownNode["state"]["map"]["nodes"]["Unknown-Node"] = new JObject
            {
                ["kind"] = "choke",
                ["attackWidth"] = 2,
                ["encounterProfileRef"] = "encounter.far",
                ["distanceBand"] = "far",
                ["spawnDistance"] = 650,
                ["pieceIds"] = new JArray()
            };
            JObject unknownNodeResult = task.Prepare(
                BuildEnvelope(unknownNode), "warlord.panel.1", out prepared);
            Assert.False((bool)unknownNodeResult["success"]);
            Assert.Contains("unsupported Demo1 encounter node", (string)unknownNodeResult["message"]);

            JObject partialLegacy = BuildRequest();
            partialLegacy["state"]["map"]["nodes"]["North-Choke"]["distanceBand"] = "far";
            JObject partialLegacyResult = task.Prepare(
                BuildEnvelope(partialLegacy), "warlord.panel.1", out prepared);
            Assert.False((bool)partialLegacyResult["success"]);
            Assert.Contains("complete state.encounter sidecar", (string)partialLegacyResult["message"]);
        }

        [Fact]
        public void Prepare_ProjectsUniformOrganizationFormationAndRejectsMixedOrMalformedSidecars()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            WarlordBattleTask.PreparedBattle prepared;

            JObject uniform = BuildRequest();
            AddSecondRedPiece(uniform);
            SetOrganization(
                uniform,
                CommandElement(
                    "ce-red-1", "task_group", "red", "R-Supply", "grid",
                    "pet-red-12", "pet-red-12b"),
                CommandElement(
                    "ce-blue-1", "singleton", "blue", "North-Choke", "line",
                    "pet-blue-15"));
            JObject accepted = task.Prepare(
                BuildEnvelope(uniform), "warlord.panel.1", out prepared);
            Assert.True((bool)accepted["success"], (string)accepted["message"]);
            Assert.Equal("grid", (string)prepared.ActionEncounterControl
                ["blueFormation"]);
            Assert.Equal("line", (string)prepared.ActionEncounterControl
                ["redFormation"]);
            Assert.True(task.CancelPrepared(prepared, "test_complete"));

            JObject mixed = BuildRequest();
            AddSecondRedPiece(mixed);
            SetOrganization(
                mixed,
                CommandElement(
                    "ce-red-1", "singleton", "red", "R-Supply", "line",
                    "pet-red-12"),
                CommandElement(
                    "ce-red-2", "singleton", "red", "R-Supply", "wedge",
                    "pet-red-12b"),
                CommandElement(
                    "ce-blue-1", "singleton", "blue", "North-Choke", "line",
                    "pet-blue-15"));
            JObject mixedResult = task.Prepare(
                BuildEnvelope(mixed), "warlord.panel.1", out prepared);
            Assert.False((bool)mixedResult["success"]);
            Assert.Contains("uniform formation", (string)mixedResult["message"]);

            JObject malformed = BuildRequest();
            SetOrganization(
                malformed,
                CommandElement(
                    "ce-red-1", "singleton", "red", "R-Supply", "line",
                    "pet-red-12"),
                CommandElement(
                    "ce-blue-1", "singleton", "blue", "North-Choke", "line",
                    "pet-blue-15"));
            malformed["state"]["organization"]["memberToElementId"]["pet-red-12"] = "ce-blue-1";
            JObject malformedResult = task.Prepare(
                BuildEnvelope(malformed), "warlord.panel.1", out prepared);
            Assert.False((bool)malformedResult["success"]);
            Assert.Contains("reverse index", (string)malformedResult["message"]);
        }

        [Fact]
        public void Prepare_RejectsPartialCommandElementAndUnsupportedFormation()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            WarlordBattleTask.PreparedBattle prepared;

            JObject partial = BuildRequest();
            AddSecondRedPiece(partial);
            ((JArray)partial["command"]["pieceIds"]).RemoveAt(1);
            SetOrganization(
                partial,
                CommandElement(
                    "ce-red-1", "task_group", "red", "R-Supply", "wedge",
                    "pet-red-12", "pet-red-12b"),
                CommandElement(
                    "ce-blue-1", "singleton", "blue", "North-Choke", "line",
                    "pet-blue-15"));
            JObject partialResult = task.Prepare(
                BuildEnvelope(partial), "warlord.panel.1", out prepared);
            Assert.False((bool)partialResult["success"]);
            Assert.Contains("partial command element", (string)partialResult["message"]);

            JObject unsupported = BuildRequest();
            SetOrganization(
                unsupported,
                CommandElement(
                    "ce-red-1", "singleton", "red", "R-Supply", "diamond",
                    "pet-red-12"),
                CommandElement(
                    "ce-blue-1", "singleton", "blue", "North-Choke", "line",
                    "pet-blue-15"));
            JObject unsupportedResult = task.Prepare(
                BuildEnvelope(unsupported), "warlord.panel.1", out prepared);
            Assert.False((bool)unsupportedResult["success"]);
            Assert.Contains("formationProfileId is unsupported", (string)unsupportedResult["message"]);
        }

        [Fact]
        public void Prepare_ProjectsPetsXmlProgressionPrefixAndRejectsDrift()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            JObject request = BuildRequest();
            request["state"]["factions"]["red"]["cards"]["12"]["level"] = 10;
            request["state"]["factions"]["red"]["cards"]["12"]["purchasedPromotions"] =
                new JArray("基础训练");

            WarlordBattleTask.PreparedBattle prepared;
            JObject accepted = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);

            Assert.True((bool)accepted["success"]);
            Assert.Equal("基础训练", (string)prepared.ActionEncounterControl
                ["blueRoster"][0]["strategicPromotions"][0]);
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
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
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
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
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
        public void Prepare_AcceptsOpaqueFourFactionAuthorityAndKeepsActionSidesStable()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                BuildFourFactionCatalog(),
                delegate(JObject ignored) { return false; });
            JObject request = BuildFourFactionRequest();
            ((JArray)request["state"]["map"]["nodes"]["North-Choke"]["pieceIds"])
                .Add("pet-dead-third-party-15");
            request["state"]["pieces"]["pet-dead-third-party-15"] = new JObject
            {
                ["pieceId"] = "pet-dead-third-party-15",
                ["factionId"] = FourFactionAlly,
                ["cardId"] = 15,
                ["nodeId"] = "North-Choke",
                ["hp"] = 0,
                ["maxHp"] = 3000,
                ["productionGoldValue"] = 60,
                ["failedAssaultLocks"] = new JArray()
            };

            WarlordBattleTask.PreparedBattle prepared;
            JObject result = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);

            Assert.True((bool)result["success"], (string)result["message"]);
            JObject encounterControl = prepared.ActionEncounterControl;
            Assert.Equal("pet-red-12", (string)encounterControl["blueRoster"][0]["sourceId"]);
            Assert.Equal("pet-blue-15", (string)encounterControl["redRoster"][0]["sourceId"]);
            Assert.Equal(FourFactionPlayer,
                (string)encounterControl["authorityContext"]["attackerFactionId"]);
            Assert.Equal(FourFactionIndependent,
                (string)encounterControl["authorityContext"]["defenderFactionId"]);
            Assert.Equal(FourFactionPlayer, (string)prepared.Attackers[0]["factionId"]);
            Assert.Equal(FourFactionIndependent, (string)prepared.Defenders[0]["factionId"]);
            Assert.True(task.CancelPrepared(prepared, "test_complete"));
        }

        [Fact]
        public void Prepare_RejectsUnknownScenarioAndInvalidOpaqueFactionId()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                BuildFourFactionCatalog(),
                delegate(JObject ignored) { return false; });
            WarlordBattleTask.PreparedBattle prepared;

            JObject unknownScenario = BuildFourFactionRequest();
            unknownScenario["state"]["scenarioId"] = "web-invented-scenario";
            JObject unknownResult = task.Prepare(
                BuildEnvelope(unknownScenario), "warlord.panel.1", out prepared);
            Assert.False((bool)unknownResult["success"]);
            Assert.Contains("trusted scenario authority catalog", (string)unknownResult["message"]);

            JObject invalidFaction = BuildFourFactionRequest();
            invalidFaction["command"]["factionId"] = "river:clan";
            invalidFaction["state"]["activeFactionId"] = "river:clan";
            JObject invalidResult = task.Prepare(
                BuildEnvelope(invalidFaction), "warlord.panel.1", out prepared);
            Assert.False((bool)invalidResult["success"]);
            Assert.Contains("command.factionId is invalid", (string)invalidResult["message"]);
        }

        [Fact]
        public void Prepare_RejectsIncompleteAsymmetricOrCatalogDriftedRelations()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                BuildFourFactionCatalog(),
                delegate(JObject ignored) { return false; });
            WarlordBattleTask.PreparedBattle prepared;

            JObject missing = BuildFourFactionRequest();
            ((JObject)missing["state"]["relations"][FourFactionPlayer])
                .Property(FourFactionIndependent).Remove();
            JObject missingResult = task.Prepare(
                BuildEnvelope(missing), "warlord.panel.1", out prepared);
            Assert.False((bool)missingResult["success"]);
            Assert.Contains("state.relations row is incomplete", (string)missingResult["message"]);

            JObject asymmetric = BuildFourFactionRequest();
            asymmetric["state"]["relations"][FourFactionPlayer][FourFactionIndependent] = "neutral";
            JObject asymmetricResult = task.Prepare(
                BuildEnvelope(asymmetric), "warlord.panel.1", out prepared);
            Assert.False((bool)asymmetricResult["success"]);
            Assert.Contains("must be symmetric", (string)asymmetricResult["message"]);

            JObject drifted = BuildFourFactionRequest();
            drifted["state"]["relations"][FourFactionPlayer][FourFactionIndependent] = "neutral";
            drifted["state"]["relations"][FourFactionIndependent][FourFactionPlayer] = "neutral";
            JObject driftedResult = task.Prepare(
                BuildEnvelope(drifted), "warlord.panel.1", out prepared);
            Assert.False((bool)driftedResult["success"]);
            Assert.Contains("trusted scenario authority", (string)driftedResult["message"]);
        }

        [Fact]
        public void Prepare_DerivesOneLivingDefenderAndRejectsMixedOrNonHostileGarrisons()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                BuildFourFactionCatalog(),
                delegate(JObject ignored) { return false; });
            WarlordBattleTask.PreparedBattle prepared;

            JObject mixed = BuildFourFactionRequest();
            ((JArray)mixed["state"]["map"]["nodes"]["North-Choke"]["pieceIds"])
                .Add("pet-third-party-15");
            mixed["state"]["pieces"]["pet-third-party-15"] = new JObject
            {
                ["pieceId"] = "pet-third-party-15",
                ["factionId"] = FourFactionAlly,
                ["cardId"] = 15,
                ["nodeId"] = "North-Choke",
                ["hp"] = 3000,
                ["maxHp"] = 3000,
                ["productionGoldValue"] = 60,
                ["failedAssaultLocks"] = new JArray()
            };
            JObject mixedResult = task.Prepare(
                BuildEnvelope(mixed), "warlord.panel.1", out prepared);
            Assert.False((bool)mixedResult["success"]);
            Assert.Contains("multiple defender factions", (string)mixedResult["message"]);

            JObject allied = BuildFourFactionRequest();
            allied["state"]["pieces"]["pet-blue-15"]["factionId"] = FourFactionAlly;
            JObject alliedResult = task.Prepare(
                BuildEnvelope(allied), "warlord.panel.1", out prepared);
            Assert.False((bool)alliedResult["success"]);
            Assert.Contains("hostile trusted relation", (string)alliedResult["message"]);

            JObject neutral = BuildFourFactionRequest();
            neutral["state"]["pieces"]["pet-blue-15"]["factionId"] = FourFactionNeutral;
            JObject neutralResult = task.Prepare(
                BuildEnvelope(neutral), "warlord.panel.1", out prepared);
            Assert.False((bool)neutralResult["success"]);
            Assert.Contains("hostile trusted relation", (string)neutralResult["message"]);

            JObject unknown = BuildFourFactionRequest();
            unknown["state"]["pieces"]["pet-blue-15"]["factionId"] = "outsider.faction";
            JObject unknownResult = task.Prepare(
                BuildEnvelope(unknown), "warlord.panel.1", out prepared);
            Assert.False((bool)unknownResult["success"]);
            Assert.Contains("outside the trusted scenario authority", (string)unknownResult["message"]);
        }

        [Fact]
        public void As2TerminalReceipt_ReopensFrozenStateWithObserveOnlyPetEconomy()
        {
            JObject command = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    command = (JObject)outbound.DeepClone();
                    return true;
                });
            JObject reopened = null;
            var reopenedEvent = new ManualResetEventSlim(false);
            task.SetResumeOpenHandler(delegate(JObject init)
            {
                reopened = init;
                reopenedEvent.Set();
            });
            JObject request = BuildRequest();
            SetDemo1EncounterContract(request, "R-HQ");
            WarlordBattleTask.PreparedBattle prepared;
            JObject prepare = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);
            Assert.True((bool)prepare["success"]);

            JObject started = task.StartPrepared(prepared);

            Assert.True((bool)started["success"]);
            Assert.Null(reopened);
            Assert.NotNull(command);
            task.HandleActionEncounterTerminal(
                BuildCompletedActionTerminal(command));
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
            Assert.Equal("demo1_exact_v1", (string)receipt["encounterProjectionMode"]);
            Assert.Equal("encounter.near", (string)receipt["encounterProfileRef"]);
            Assert.Equal("near", (string)receipt["encounterDistanceBand"]);
            Assert.Equal(180, (int)receipt["encounterSpawnDistance"]);
            Assert.Equal(180, (int)receipt["requestedSpawnDistance"]);
            Assert.Equal(180, (int)receipt["spawnDistance"]);

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
            Assert.False(task.HasActiveBattle);
        }

        [Fact]
        public void ActionNotStarted_ReopensFrozenStateWithoutAutomaticRetry()
        {
            var commands = new JArray();
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    commands.Add(outbound.DeepClone());
                    return true;
                });
            JObject reopened = null;
            task.SetResumeOpenHandler(delegate(JObject init) { reopened = init; });
            WarlordBattleTask.PreparedBattle prepared;
            JObject prepare = task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared);
            Assert.True((bool)prepare["success"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);
            Assert.Single(commands);
            Assert.Null(reopened);

            JObject first = (JObject)commands[0];
            JObject terminalResponse = JObject.Parse(
                task.HandleActionEncounterTerminal(
                    BuildNotStartedActionTerminal(first)));

            Assert.True((bool)terminalResponse["success"]);
            Assert.Equal("not_started",
                (string)terminalResponse["disposition"]);
            Assert.Single(commands);
            Assert.NotNull(reopened);
            Assert.Equal("not_started",
                (string)reopened["resume"]["receipt"]["status"]);
        }

        [Fact]
        public void ActionUnknownTerminal_RejectsNonNullResultWithoutConsumingBattle()
        {
            JObject command = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    command = (JObject)outbound.DeepClone();
                    return true;
                });
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared)["success"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);

            JObject malformed = BuildNotStartedActionTerminal(command);
            malformed["payload"]["status"] = "unknown";
            malformed["payload"]["reasonCode"] = "action.cleanup-incomplete";
            malformed["payload"]["result"] = new JObject
            {
                ["diagnostic"] = "must-not-cross-the-terminal-contract"
            };
            JObject response = JObject.Parse(
                task.HandleActionEncounterTerminal(malformed));

            Assert.False((bool)response["success"]);
            Assert.Equal("invalid_terminal", (string)response["disposition"]);
            Assert.True(task.HasActiveBattle);
            task.HandleTransportDisconnected();
            Assert.False(task.HasActiveBattle);
        }

        [Fact]
        public void TerminalBeforeDispatchClaim_IsStaleAndCannotConsumePreparedBattle()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return true; });
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared)["success"]);
            var forgedCommand = new JObject
            {
                ["binding"] = prepared.ActionEncounterBinding.DeepClone(),
                ["encounter"] = prepared.ActionEncounterControl.DeepClone()
            };

            JObject terminalResponse = JObject.Parse(
                task.HandleActionEncounterTerminal(
                    BuildCompletedActionTerminal(forgedCommand)));

            Assert.False((bool)terminalResponse["success"]);
            Assert.Equal("stale_terminal", (string)terminalResponse["disposition"]);
            Assert.True(task.HasActiveBattle);
            Assert.True(task.CancelPrepared(prepared, "test_complete"));
        }

        [Fact]
        public void SynchronousCompletedTerminal_WinsOverFalseDispatchReturn()
        {
            WarlordBattleTask task = null;
            JObject reopened = null;
            JObject terminalResponse = null;
            task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    terminalResponse = JObject.Parse(
                        task.HandleActionEncounterTerminal(
                            BuildCompletedActionTerminal(outbound)));
                    return false;
                });
            task.SetResumeOpenHandler(delegate(JObject init) { reopened = init; });
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared)["success"]);

            JObject started = task.StartPrepared(prepared);

            Assert.True((bool)started["success"]);
            Assert.Equal("terminal_completed_synchronously", (string)started["note"]);
            Assert.Equal("completed", (string)terminalResponse["disposition"]);
            Assert.NotNull(reopened);
            Assert.Equal("accepted", (string)reopened["resume"]["receipt"]["status"]);
            Assert.False(task.HasActiveBattle);
        }

        [Fact]
        public void ExactTerminalDuplicateReplaysResume_ChangedProofConflicts()
        {
            JObject command = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    command = (JObject)outbound.DeepClone();
                    return true;
                });
            var resumes = new JArray();
            task.SetResumeOpenHandler(delegate(JObject init)
            {
                resumes.Add(init.DeepClone());
            });
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared)["success"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);
            JObject terminal = BuildCompletedActionTerminal(command);

            JObject accepted = JObject.Parse(task.HandleActionEncounterTerminal(terminal));
            JObject duplicate = JObject.Parse(task.HandleActionEncounterTerminal(
                (JObject)terminal.DeepClone()));
            JObject changed = (JObject)terminal.DeepClone();
            changed["payload"]["result"]["frames"] = 181;
            JObject conflict = JObject.Parse(task.HandleActionEncounterTerminal(changed));

            Assert.True((bool)accepted["success"]);
            Assert.Equal("completed", (string)accepted["disposition"]);
            Assert.True((bool)duplicate["success"]);
            Assert.Equal("duplicate", (string)duplicate["disposition"]);
            Assert.False((bool)conflict["success"]);
            Assert.Equal("terminal_conflict", (string)conflict["disposition"]);
            Assert.Equal(2, resumes.Count);
            Assert.True(JToken.DeepEquals(resumes[0], resumes[1]));
        }

        [Fact]
        public void OldTerminalIsStaleWhileANewerBattleOwnsTheSlot()
        {
            var commands = new JArray();
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    commands.Add(outbound.DeepClone());
                    return true;
                });
            var resumes = new JArray();
            task.SetResumeOpenHandler(delegate(JObject init) { resumes.Add(init.DeepClone()); });

            WarlordBattleTask.PreparedBattle firstPrepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out firstPrepared)["success"]);
            Assert.True((bool)task.StartPrepared(firstPrepared)["success"]);
            JObject firstTerminal = BuildCompletedActionTerminal((JObject)commands[0]);
            Assert.True((bool)JObject.Parse(
                task.HandleActionEncounterTerminal(firstTerminal))["success"]);

            JObject secondRequest = BuildRequest();
            secondRequest["requestId"] = "warlord.request.2";
            WarlordBattleTask.PreparedBattle secondPrepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(secondRequest), "warlord.panel.1", out secondPrepared)["success"]);
            Assert.True((bool)task.StartPrepared(secondPrepared)["success"]);

            JObject stale = JObject.Parse(task.HandleActionEncounterTerminal(
                (JObject)firstTerminal.DeepClone()));

            Assert.False((bool)stale["success"]);
            Assert.Equal("stale_terminal", (string)stale["disposition"]);
            Assert.Single(resumes);
            Assert.True(task.HasActiveBattle);
        }

        [Fact]
        public void As2TerminalReceipt_FormationEchoMismatchFreezesAsUnknown()
        {
            JObject command = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    command = (JObject)outbound.DeepClone();
                    return true;
                });
            JObject reopened = null;
            var reopenedEvent = new ManualResetEventSlim(false);
            task.SetResumeOpenHandler(delegate(JObject init)
            {
                reopened = init;
                reopenedEvent.Set();
            });

            WarlordBattleTask.PreparedBattle prepared;
            JObject accepted = task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared);
            Assert.True((bool)accepted["success"]);
            JObject started = task.StartPrepared(prepared);

            Assert.True((bool)started["success"]);
            task.HandleActionEncounterTerminal(
                BuildCompletedActionTerminal(command, "line", null, null));
            Assert.True(reopenedEvent.Wait(3000), "formation mismatch did not reopen frozen Warlord state");
            JObject receipt = (JObject)reopened["resume"]["receipt"];
            Assert.Equal("unknown", (string)receipt["status"]);
            Assert.Equal("receipt_invalid", (string)receipt["error"]);
            Assert.Contains("formation echo", (string)receipt["message"]);
        }

        [Fact]
        public void InvalidCompletedProof_DerivesUnknownResumeWithoutRewritingTerminal()
        {
            JObject command = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    command = (JObject)outbound.DeepClone();
                    return true;
                });
            var resumes = new JArray();
            task.SetResumeOpenHandler(delegate(JObject init)
            {
                resumes.Add(init.DeepClone());
            });
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared)["success"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);
            JObject terminal = BuildCompletedActionTerminal(
                command, "line", null, null);

            JObject accepted = JObject.Parse(
                task.HandleActionEncounterTerminal(terminal));
            JObject duplicate = JObject.Parse(
                task.HandleActionEncounterTerminal((JObject)terminal.DeepClone()));
            JObject changed = (JObject)terminal.DeepClone();
            changed["payload"]["result"]["frames"] = 181;
            JObject conflict = JObject.Parse(
                task.HandleActionEncounterTerminal(changed));

            Assert.True((bool)accepted["success"]);
            Assert.Equal("completed", (string)accepted["disposition"]);
            Assert.True((bool)duplicate["success"]);
            Assert.Equal("duplicate", (string)duplicate["disposition"]);
            Assert.False((bool)conflict["success"]);
            Assert.Equal("terminal_conflict", (string)conflict["disposition"]);
            Assert.Equal(2, resumes.Count);
            Assert.True(JToken.DeepEquals(resumes[0], resumes[1]));
            Assert.Equal("unknown", (string)resumes[0]["resume"]["receipt"]["status"]);
            Assert.Equal("receipt_invalid",
                (string)resumes[0]["resume"]["receipt"]["error"]);
            Assert.Equal("completed",
                (string)prepared.AcceptedActionTerminal["status"]);
            Assert.Equal("action.completed",
                (string)prepared.AcceptedActionTerminal["reasonCode"]);
            Assert.True(JToken.DeepEquals(
                terminal["payload"], prepared.AcceptedActionTerminal));
        }

        [Fact]
        public void As2TerminalReceipt_SpawnDistanceEchoMismatchFreezesAsUnknown()
        {
            JObject command = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    command = (JObject)outbound.DeepClone();
                    return true;
                });
            JObject reopened = null;
            var reopenedEvent = new ManualResetEventSlim(false);
            task.SetResumeOpenHandler(delegate(JObject init)
            {
                reopened = init;
                reopenedEvent.Set();
            });
            JObject request = BuildRequest();
            SetDemo1EncounterContract(request, "R-HQ");

            WarlordBattleTask.PreparedBattle prepared;
            JObject accepted = task.Prepare(
                BuildEnvelope(request), "warlord.panel.1", out prepared);
            Assert.True((bool)accepted["success"], (string)accepted["message"]);
            JObject started = task.StartPrepared(prepared);

            Assert.True((bool)started["success"]);
            task.HandleActionEncounterTerminal(
                BuildCompletedActionTerminal(command, null, null, null, 360));
            Assert.True(reopenedEvent.Wait(3000), "spawn distance mismatch did not reopen frozen Warlord state");
            JObject receipt = (JObject)reopened["resume"]["receipt"];
            Assert.Equal("unknown", (string)receipt["status"]);
            Assert.Equal("receipt_invalid", (string)receipt["error"]);
            Assert.Contains("spawnDistance echo", (string)receipt["message"]);
            Assert.Equal("encounter.near", (string)receipt["encounterProfileRef"]);
            Assert.Equal("near", (string)receipt["encounterDistanceBand"]);
            Assert.Equal(180, (int)receipt["requestedSpawnDistance"]);
            Assert.Null(receipt["spawnDistance"]);
        }

        [Fact]
        public void AdmissionAck_StopsSameGenerationRetryAndIsIdempotent()
        {
            var sent = new List<JObject>();
            var scheduled = new Queue<Action>();
            int forcedGeneration = -1;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            task.SetActionAdmissionRetryInfrastructureForTests(
                delegate { return (int?)27; },
                delegate(JObject outbound, int generation)
                {
                    Assert.Equal(27, generation);
                    sent.Add((JObject)outbound.DeepClone());
                    return true;
                },
                delegate(Action callback, int delay)
                {
                    Assert.Equal(1000, delay);
                    scheduled.Enqueue(callback);
                    return new CancellationTokenSource();
                },
                delegate(int generation)
                {
                    forcedGeneration = generation;
                    return true;
                });
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared)["success"]);

            JObject started = task.StartPrepared(prepared);

            Assert.True((bool)started["success"]);
            Assert.Equal("awaiting_admission", (string)started["note"]);
            Assert.Single(sent);
            Assert.Single(scheduled);

            scheduled.Dequeue().Invoke();
            Assert.Equal(2, sent.Count);
            Assert.True(JToken.DeepEquals(sent[0], sent[1]));
            Assert.Single(scheduled);

            JObject admission = BuildActionAdmission(sent[0], "accepted", "entering");
            JObject first = JObject.Parse(task.HandleActionEncounterAdmission(admission));
            JObject duplicate = JObject.Parse(task.HandleActionEncounterAdmission(admission));
            Assert.True((bool)first["success"]);
            Assert.Equal("accepted", (string)first["disposition"]);
            Assert.True((bool)duplicate["success"]);
            Assert.Equal("duplicate", (string)duplicate["disposition"]);

            scheduled.Dequeue().Invoke();
            Assert.Equal(2, sent.Count);
            Assert.Equal(-1, forcedGeneration);
        }

        [Fact]
        public void AdmissionRetry_ExhaustionFencesOnlyCapturedGeneration()
        {
            var sent = new List<JObject>();
            var scheduled = new Queue<Action>();
            var forced = new List<int>();
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            task.SetActionAdmissionRetryInfrastructureForTests(
                delegate { return (int?)41; },
                delegate(JObject outbound, int generation)
                {
                    Assert.Equal(41, generation);
                    sent.Add((JObject)outbound.DeepClone());
                    return true;
                },
                delegate(Action callback, int ignoredDelay)
                {
                    scheduled.Enqueue(callback);
                    return new CancellationTokenSource();
                },
                delegate(int generation)
                {
                    forced.Add(generation);
                    return true;
                });
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared)["success"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);

            int callbacks = 0;
            while (scheduled.Count > 0 && callbacks < 8)
            {
                scheduled.Dequeue().Invoke();
                callbacks++;
            }

            Assert.Equal(4, sent.Count);
            Assert.All(sent, item => Assert.True(JToken.DeepEquals(sent[0], item)));
            Assert.Equal(new[] { 41 }, forced);
            Assert.True(task.HasActiveBattle);
        }

        [Fact]
        public void AdmissionRetry_ScheduleFailureImmediatelyFencesCapturedGeneration()
        {
            int sends = 0;
            var forced = new List<int>();
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            task.SetActionAdmissionRetryInfrastructureForTests(
                delegate { return (int?)73; },
                delegate(JObject ignored, int generation)
                {
                    Assert.Equal(73, generation);
                    sends++;
                    return true;
                },
                delegate(Action ignored, int ignoredDelay)
                {
                    throw new InvalidOperationException("timer unavailable");
                },
                delegate(int generation)
                {
                    forced.Add(generation);
                    return true;
                });
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared)["success"]);

            JObject started = task.StartPrepared(prepared);

            Assert.True((bool)started["success"]);
            Assert.Equal("awaiting_admission", (string)started["note"]);
            Assert.Equal(1, sends);
            Assert.Equal(new[] { 73 }, forced);
        }

        [Fact]
        public void AdmissionAck_RejectsWrongBindingWithoutStoppingRetry()
        {
            var scheduled = new Queue<Action>();
            int sends = 0;
            JObject command = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            task.SetActionAdmissionRetryInfrastructureForTests(
                delegate { return (int?)9; },
                delegate(JObject outbound, int ignoredGeneration)
                {
                    sends++;
                    command = (JObject)outbound.DeepClone();
                    return true;
                },
                delegate(Action callback, int ignoredDelay)
                {
                    scheduled.Enqueue(callback);
                    return new CancellationTokenSource();
                },
                delegate(int ignoredGeneration) { return true; });
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared)["success"]);
            task.StartPrepared(prepared);
            JObject wrong = BuildActionAdmission(command, "accepted", "entering");
            wrong["payload"]["binding"]["requestId"] = "warlord.request.other";

            JObject response = JObject.Parse(task.HandleActionEncounterAdmission(wrong));

            Assert.False((bool)response["success"]);
            Assert.Equal("stale_admission", (string)response["disposition"]);
            scheduled.Dequeue().Invoke();
            Assert.Equal(2, sends);
        }

        [Fact]
        public void StartPrepared_DisconnectedRestoresKnownNotStartedWithoutHiddenNavigation()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
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
            Assert.False(task.HasActiveBattle);
        }

        [Fact]
        public void SynchronousNotStarted_QueuesResumeUntilCurrentHostCommandCompletes()
        {
            var queuedUiWork = new Queue<Action>();
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            JObject reopened = null;
            task.SetInvoker(delegate(Action action) { queuedUiWork.Enqueue(action); });
            task.SetResumeOpenHandler(delegate(JObject init)
            {
                reopened = (JObject)init.DeepClone();
            });
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()), "warlord.panel.1", out prepared)["success"]);

            // Action dispatch fails synchronously, just as it can while the exact-close
            // completion is still inside PanelHost's _processing command.
            JObject started = task.StartPrepared(prepared);
            Assert.False((bool)started["success"]);
            Assert.Null(reopened);
            Assert.Single(queuedUiWork);

            queuedUiWork.Dequeue().Invoke();
            Assert.NotNull(reopened);
            Assert.Equal("not_started", (string)reopened["resume"]["receipt"]["status"]);
        }

        [Fact]
        public void StageBattle_PlayerAvatarPortraitIsHostBoundAndSurvivesResume()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return false; });
            JObject reopened = null;
            WarlordBattleTask.PreparedBattle resumedPrepared = null;
            task.SetResumeOpenHandler(delegate(
                JObject init,
                WarlordBattleTask.PreparedBattle resumePrepared)
            {
                reopened = (JObject)init.DeepClone();
                resumedPrepared = resumePrepared;
            });
            JObject portrait = BuildPlayerAvatarPortrait();
            JObject stageBinding = BuildStageBinding();
            WarlordBattleTask.PreparedBattle prepared;

            JObject accepted = task.Prepare(
                BuildEnvelope(BuildRequest()),
                "warlord.panel.1",
                (string)stageBinding["runId"],
                stageBinding,
                portrait,
                out prepared);

            Assert.True((bool)accepted["success"], (string)accepted["message"]);
            Assert.NotNull(prepared);
            Assert.True(task.CancelAndResume(
                prepared,
                "test_cancelled",
                "test cancelled before Action handoff"));
            Assert.NotNull(reopened);
            Assert.True(JToken.DeepEquals(
                portrait,
                reopened["playerAvatarPortrait"]));
            Assert.True(JToken.DeepEquals(
                portrait,
                reopened["resume"]["playerAvatarPortrait"]));
            Assert.Equal("game_stage", (string)reopened["source"]);
            Assert.Equal("stage-v1", (string)reopened["mode"]);
            Assert.True(JToken.DeepEquals(stageBinding, reopened["stageOuterBinding"]));
            Assert.True(JToken.DeepEquals(
                stageBinding,
                reopened["resume"]["stageOuterBinding"]));
            Assert.Equal("warlord.panel.1",
                (string)reopened["stageResumeFromPanelInstanceId"]);
            Assert.Same(prepared, resumedPrepared);
        }

        [Fact]
        public void StageBattle_AcceptedTerminalKeepsOuterResumeAuthority()
        {
            JObject actionCommand = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    actionCommand = (JObject)outbound.DeepClone();
                    return true;
                });
            JObject reopened = null;
            var reopenedEvent = new ManualResetEventSlim(false);
            task.SetResumeOpenHandler(delegate(
                JObject init,
                WarlordBattleTask.PreparedBattle ignored)
            {
                reopened = (JObject)init.DeepClone();
                reopenedEvent.Set();
            });
            JObject stageBinding = BuildStageBinding();
            WarlordBattleTask.PreparedBattle prepared;
            JObject accepted = task.Prepare(
                BuildEnvelope(BuildRequest()),
                "warlord.panel.1",
                (string)stageBinding["runId"],
                stageBinding,
                BuildPlayerAvatarPortrait(),
                out prepared);

            Assert.True((bool)accepted["success"], (string)accepted["message"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);
            task.HandleActionEncounterTerminal(
                BuildCompletedActionTerminal(actionCommand));

            Assert.True(reopenedEvent.Wait(3000));
            Assert.NotNull(reopened);
            Assert.Equal("game_stage", (string)reopened["source"]);
            Assert.True(JToken.DeepEquals(stageBinding, reopened["stageOuterBinding"]));
            Assert.False(task.HasActiveBattle);
        }

        [Fact]
        public void ParentCancellation_ExactClaimIsAbsorbingAndLateTerminalCannotResume()
        {
            JObject actionCommand = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    actionCommand = (JObject)outbound.DeepClone();
                    return true;
            });
            int resumes = 0;
            task.SetResumeOpenHandler(delegate(JObject ignored) { resumes++; });
            JObject stageBinding = BuildStageBinding();
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()),
                "warlord.panel.1",
                (string)stageBinding["runId"],
                stageBinding,
                BuildPlayerAvatarPortrait(),
                out prepared)["success"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);

            JObject cancellation = BuildActionCancellation(
                actionCommand,
                stageBinding,
                "parent_return_base");
            JObject accepted = JObject.Parse(
                task.HandleActionEncounterCancellation(cancellation));
            JObject duplicate = JObject.Parse(
                task.HandleActionEncounterCancellation(
                    (JObject)cancellation.DeepClone()));
            JObject lateTerminal = JObject.Parse(
                task.HandleActionEncounterTerminal(
                    BuildCompletedActionTerminal(actionCommand)));

            Assert.True((bool)accepted["success"]);
            Assert.Equal("cancelled", (string)accepted["disposition"]);
            Assert.True((bool)duplicate["success"]);
            Assert.Equal("duplicate", (string)duplicate["disposition"]);
            Assert.True((bool)lateTerminal["success"]);
            Assert.Equal("cancelled", (string)lateTerminal["disposition"]);
            Assert.Equal(0, resumes);
            Assert.False(task.HasActiveBattle);
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void OuterAndActionCancellation_AreOrderIndependent(
            bool outerFirst)
        {
            JObject actionCommand = null;
            var battle = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    actionCommand = (JObject)outbound.DeepClone();
                    return true;
                });
            var outerSent = new List<JObject>();
            var outer = new WarlordStageTask(delegate(JObject command)
            {
                outerSent.Add((JObject)command.DeepClone());
                return true;
            });
            string panel = null;
            outer.SetOpenHandler(delegate(
                JObject binding,
                JObject portrait,
                JObject resume,
                string panelInstanceId,
                Func<bool> executionGate,
                Action<PanelHostController.TrackedOpenOutcome> completed)
            {
                panel = panelInstanceId;
                Assert.True(executionGate());
                completed(PanelHostController.TrackedOpenOutcome.OpenPosted);
                return true;
            });

            JObject stageBinding = BuildStageBinding();
            outer.HandleStart(BuildStageStart(stageBinding));
            Assert.True(outer.IsPanelReadyForGameplay(panel));
            JObject battleEnvelope = BuildEnvelope(BuildRequest());
            battleEnvelope["panelInstanceId"] = panel;
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)battle.Prepare(
                battleEnvelope,
                panel,
                (string)stageBinding["runId"],
                stageBinding,
                BuildPlayerAvatarPortrait(),
                out prepared)["success"]);
            Assert.True((bool)battle.StartPrepared(prepared)["success"]);

            JObject actionCancellation = BuildActionCancellation(
                actionCommand,
                stageBinding,
                "parent_return_base");
            JObject outerCancellation = BuildStageOuterCancellation(
                stageBinding,
                "stage.parent-return-base");
            if (outerFirst)
            {
                outer.HandleOuterCancellation(outerCancellation);
                Assert.False(outer.IsPanelReadyForGameplay(panel));
                Assert.True(battle.HasActiveBattle);
                Assert.True((bool)JObject.Parse(
                    battle.HandleActionEncounterCancellation(
                        actionCancellation))["success"]);
            }
            else
            {
                Assert.True((bool)JObject.Parse(
                    battle.HandleActionEncounterCancellation(
                        actionCancellation))["success"]);
                Assert.False(battle.HasActiveBattle);
                Assert.True(outer.IsPanelReadyForGameplay(panel));
                outer.HandleOuterCancellation(outerCancellation);
            }

            Assert.False(battle.HasActiveBattle);
            Assert.False(outer.IsPanelReadyForGameplay(panel));
            Assert.Empty(outerSent);
        }

        [Fact]
        public void ParentCancellation_WrongProofCannotReleaseCurrentClaim()
        {
            JObject actionCommand = null;
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    actionCommand = (JObject)outbound.DeepClone();
                    return true;
                });
            JObject stageBinding = BuildStageBinding();
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()),
                "warlord.panel.1",
                (string)stageBinding["runId"],
                stageBinding,
                BuildPlayerAvatarPortrait(),
                out prepared)["success"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);

            JObject wrongDigest = BuildActionCancellation(
                actionCommand,
                stageBinding,
                "stage_exit");
            wrongDigest["payload"]["actionBinding"]["inputDigest"] =
                "sha256:" + new string('0', 64);
            JObject stale = JObject.Parse(
                task.HandleActionEncounterCancellation(wrongDigest));
            Assert.False((bool)stale["success"]);
            Assert.Equal("stale_cancellation", (string)stale["disposition"]);
            Assert.True(task.HasActiveBattle);

            JObject wrongOuter = BuildActionCancellation(
                actionCommand,
                stageBinding,
                "stage_exit");
            wrongOuter["payload"]["stageOuterBinding"]["revision"] = 1;
            JObject conflict = JObject.Parse(
                task.HandleActionEncounterCancellation(wrongOuter));
            Assert.False((bool)conflict["success"]);
            Assert.Equal("cancellation_conflict", (string)conflict["disposition"]);
            Assert.True(task.HasActiveBattle);

            JObject exact = JObject.Parse(
                task.HandleActionEncounterCancellation(
                    BuildActionCancellation(
                        actionCommand,
                        stageBinding,
                        "stage_exit")));
            Assert.True((bool)exact["success"]);
            Assert.False(task.HasActiveBattle);
        }

        [Fact]
        public void ParentCancellation_WinsOverQueuedTerminalResume()
        {
            JObject actionCommand = null;
            var queued = new Queue<Action>();
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject outbound)
                {
                    actionCommand = (JObject)outbound.DeepClone();
                    return true;
                });
            int resumes = 0;
            task.SetInvoker(delegate(Action action) { queued.Enqueue(action); });
            task.SetResumeOpenHandler(delegate(JObject ignored) { resumes++; });
            JObject stageBinding = BuildStageBinding();
            WarlordBattleTask.PreparedBattle prepared;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()),
                "warlord.panel.1",
                (string)stageBinding["runId"],
                stageBinding,
                BuildPlayerAvatarPortrait(),
                out prepared)["success"]);
            Assert.True((bool)task.StartPrepared(prepared)["success"]);
            Assert.True((bool)JObject.Parse(
                task.HandleActionEncounterTerminal(
                    BuildCompletedActionTerminal(actionCommand)))["success"]);
            Assert.Single(queued);

            Assert.True((bool)JObject.Parse(
                task.HandleActionEncounterCancellation(
                    BuildActionCancellation(
                        actionCommand,
                        stageBinding,
                        "parent_restart")))["success"]);
            queued.Dequeue().Invoke();

            Assert.Equal(0, resumes);
            Assert.False(task.HasActiveBattle);
        }

        [Fact]
        public void TransportDisconnect_ReleasesClaimedCorrelationForFreshBattle()
        {
            var task = new WarlordBattleTask(
                BuildPetCatalog(),
                delegate(JObject ignored) { return true; });
            JObject stageBinding = BuildStageBinding();
            WarlordBattleTask.PreparedBattle first;
            Assert.True((bool)task.Prepare(
                BuildEnvelope(BuildRequest()),
                "warlord.panel.1",
                (string)stageBinding["runId"],
                stageBinding,
                BuildPlayerAvatarPortrait(),
                out first)["success"]);
            Assert.True((bool)task.StartPrepared(first)["success"]);
            task.HandleTransportDisconnected();
            Assert.False(task.HasActiveBattle);

            JObject nextBinding = BuildStageBinding();
            nextBinding["runId"] = "outer.run.2";
            nextBinding["subStageId"] = "warlord.substage.2";
            nextBinding["callId"] = "outer.call.2";
            WarlordBattleTask.PreparedBattle second;
            JObject next = task.Prepare(
                BuildEnvelope(BuildRequest()),
                "warlord.panel.1",
                (string)nextBinding["runId"],
                nextBinding,
                BuildPlayerAvatarPortrait(),
                out second);
            Assert.True((bool)next["success"], (string)next["message"]);
            Assert.True(task.CancelPrepared(second, "test_complete"));
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

        private static JObject BuildPlayerAvatarPortrait()
        {
            return new JObject
            {
                ["schema"] = WarlordStageTask.PlayerAvatarPortraitSchema,
                ["gender"] = "男",
                ["face"] = "男变装 基本脸型",
                ["hair"] = "发型-男式-平头",
                ["equipment"] = new JObject
                {
                    ["head"] = "",
                    ["body"] = "",
                    ["hand"] = "",
                    ["leg"] = "",
                    ["foot"] = "",
                    ["neck"] = ""
                }
            };
        }

        private static JObject BuildStageBinding()
        {
            return new JObject
            {
                ["schema"] = WarlordStageTask.BindingSchema,
                ["runId"] = "outer.run.1",
                ["subStageId"] = "warlord.substage.1",
                ["scenarioRef"] = WarlordStageTask.AllowedScenarioRef,
                ["callId"] = "outer.call.1",
                ["revision"] = 0
            };
        }

        private static JObject BuildNotStartedActionTerminal(JObject command)
        {
            JObject binding = (JObject)command["binding"];
            return new JObject
            {
                ["task"] = "warlord_action_encounter_terminal",
                ["payload"] = new JObject
                {
                    ["schema"] = WarlordBattleTask.ActionEncounterTerminalSchema,
                    ["outerRunId"] = binding["outerRunId"].DeepClone(),
                    ["encounterId"] = binding["encounterId"].DeepClone(),
                    ["requestId"] = binding["requestId"].DeepClone(),
                    ["inputDigest"] = binding["inputDigest"].DeepClone(),
                    ["status"] = "not_started",
                    ["reasonCode"] = "action.world-not-started",
                    ["result"] = JValue.CreateNull()
                }
            };
        }

        private static JObject BuildActionAdmission(
            JObject command,
            string disposition,
            string phase)
        {
            return new JObject
            {
                ["task"] = "warlord_action_encounter_admitted",
                ["payload"] = new JObject
                {
                    ["schema"] = WarlordBattleTask.ActionEncounterAdmissionSchema,
                    ["binding"] = command["binding"].DeepClone(),
                    ["disposition"] = disposition,
                    ["phase"] = phase
                }
            };
        }

        private static JObject BuildStageStart(JObject stageBinding)
        {
            return new JObject
            {
                ["task"] = "warlord_stage_start",
                ["payload"] = new JObject
                {
                    ["binding"] = stageBinding.DeepClone(),
                    ["playerAvatarPortrait"] = BuildPlayerAvatarPortrait()
                }
            };
        }

        private static JObject BuildStageOuterCancellation(
            JObject stageBinding,
            string reasonCode)
        {
            return new JObject
            {
                ["task"] = WarlordStageTask.OuterCancellationTaskName,
                ["payload"] = new JObject
                {
                    ["schema"] = WarlordStageTask.OuterCancellationSchema,
                    ["binding"] = stageBinding.DeepClone(),
                    ["reasonCode"] = reasonCode
                }
            };
        }

        private static JObject BuildActionCancellation(
            JObject command,
            JObject stageBinding,
            string reasonCode)
        {
            return new JObject
            {
                ["task"] = "warlord_action_encounter_cancelled",
                ["payload"] = new JObject
                {
                    ["schema"] =
                        WarlordBattleTask.ActionEncounterCancellationSchema,
                    ["actionBinding"] = command["binding"].DeepClone(),
                    ["stageOuterBinding"] = stageBinding.DeepClone(),
                    ["reasonCode"] = reasonCode
                }
            };
        }

        private static JObject BuildCompletedActionTerminal(
            JObject command,
            string blueFormation = null,
            string redFormation = null,
            int? formationSpacing = null,
            int? spawnDistance = null)
        {
            JObject binding = (JObject)command["binding"];
            JObject control = (JObject)command["encounter"];
            var result = new JObject
            {
                ["status"] = "finished",
                ["winner"] = "blue",
                ["frames"] = 180,
                ["durationMs"] = 6000,
                ["batchId"] = (string)control["battleId"],
                ["manifestHash"] = "",
                ["caseHash"] = "",
                ["blueFormation"] = blueFormation ?? (string)control["blueFormation"],
                ["redFormation"] = redFormation ?? (string)control["redFormation"],
                ["formationSpacing"] = formationSpacing ?? (int)control["formationSpacing"],
                ["requestedSpawnDistance"] = (int)control["spawnDistance"],
                ["spawnDistance"] = spawnDistance ?? (int)control["spawnDistance"],
                ["playerControlledSide"] =
                    control["playerControlledSide"].DeepClone(),
                ["authorityContext"] = control["authorityContext"].DeepClone(),
                ["blue"] = new JObject
                {
                    ["maxHp"] = 2000, ["remainHp"] = 1250, ["aliveCount"] = 1
                },
                ["red"] = new JObject
                {
                    ["maxHp"] = 3000, ["remainHp"] = 0, ["aliveCount"] = 0
                },
                ["blueUnitResults"] = BuildCompletedActionUnitResults(
                    (JArray)control["blueRoster"],
                    true),
                ["redUnitResults"] = BuildCompletedActionUnitResults(
                    (JArray)control["redRoster"],
                    false),
                ["errors"] = new JArray()
            };
            return new JObject
            {
                ["task"] = "warlord_action_encounter_terminal",
                ["payload"] = new JObject
                {
                    ["schema"] = WarlordBattleTask.ActionEncounterTerminalSchema,
                    ["outerRunId"] = binding["outerRunId"].DeepClone(),
                    ["encounterId"] = binding["encounterId"].DeepClone(),
                    ["requestId"] = binding["requestId"].DeepClone(),
                    ["inputDigest"] = binding["inputDigest"].DeepClone(),
                    ["status"] = "completed",
                    ["reasonCode"] = "action.completed",
                    ["result"] = result
                }
            };
        }

        private static JArray BuildCompletedActionUnitResults(
            JArray roster,
            bool alive)
        {
            JArray results = new JArray();
            foreach (JObject projected in roster)
            {
                double startMaxHp = alive ? 2000 : 3000;
                double remainHp = alive ? 1250 : 0;
                JObject result = new JObject
                {
                    ["projectionKind"] = projected["projectionKind"].DeepClone(),
                    ["sourceId"] = projected["sourceId"].DeepClone(),
                    ["startMaxHp"] = startMaxHp,
                    ["remainHp"] = remainHp,
                    ["hpPermille"] = alive ? 625 : 0,
                    ["alive"] = alive
                };
                if (string.Equals(
                    projected.Value<string>("projectionKind"),
                    "player_avatar",
                    StringComparison.Ordinal))
                {
                    result["commanderId"] = projected["commanderId"].DeepClone();
                    result["characterId"] = projected["characterId"].DeepClone();
                    result["factionId"] = projected["factionId"].DeepClone();
                    result["runtimeLevel"] = 17;
                }
                else
                {
                    result["petId"] = projected["petId"].DeepClone();
                    result["identifier"] = projected["identifier"].DeepClone();
                    result["level"] = projected["level"].DeepClone();
                    result["strategicPromotions"] =
                        projected["strategicPromotions"].DeepClone();
                    result["strategicPromotionsValid"] = true;
                    result["resolvedType"] = projected["identifier"].DeepClone();
                }
                results.Add(result);
            }
            return results;
        }

        private static void AddSecondRedPiece(JObject request)
        {
            JObject state = (JObject)request["state"];
            ((JArray)state["map"]["nodes"]["R-Supply"]["pieceIds"]).Add("pet-red-12b");
            ((JArray)request["command"]["pieceIds"]).Add("pet-red-12b");
            ((JObject)state["pieces"])["pet-red-12b"] = new JObject
            {
                ["pieceId"] = "pet-red-12b", ["factionId"] = "red",
                ["cardId"] = 12, ["nodeId"] = "R-Supply",
                ["hp"] = 2000, ["maxHp"] = 2000,
                ["productionGoldValue"] = 8,
                ["failedAssaultLocks"] = new JArray()
            };
        }

        private static JObject CommandElement(
            string elementId,
            string kind,
            string factionId,
            string nodeId,
            string formationProfileId,
            params string[] memberIds)
        {
            return new JObject
            {
                ["elementId"] = elementId,
                ["kind"] = kind,
                ["factionId"] = factionId,
                ["nodeId"] = nodeId,
                ["memberIds"] = new JArray(memberIds),
                ["formationProfileId"] = formationProfileId,
                ["taskGroupTemplateId"] = kind == "task_group"
                    ? (JToken)"demo1.mixed-detachment" : JValue.CreateNull(),
                ["createdRound"] = 1,
                ["reorganizedAtCommand"] = 0
            };
        }

        private static void SetOrganization(JObject request, params JObject[] elements)
        {
            JObject commandElements = new JObject();
            JObject memberToElement = new JObject();
            foreach (JObject element in elements)
            {
                string elementId = (string)element["elementId"];
                commandElements[elementId] = element;
                foreach (JToken member in (JArray)element["memberIds"])
                    memberToElement[(string)member] = elementId;
            }
            request["state"]["organization"] = new JObject
            {
                ["definitionId"] = "demo1-organizations",
                ["rulesVersion"] = "warlord.organization.v1",
                ["configDigest"] = "sha256:7FBBFE6B24592A7356B6AC9CACB14D49803FBA2214D8A9FFBD71599211114DA3",
                ["nextCommandElementOrdinal"] = elements.Length + 1,
                ["commandElements"] = commandElements,
                ["memberToElementId"] = memberToElement
            };
        }

        private static void SetDemo1EncounterContract(JObject request, string targetNodeId)
        {
            JObject state = (JObject)request["state"];
            state["rulesVersion"] = "wargame-demo-v0.1.1";
            state["scenarioId"] = "warlord_tutorial_v1";
            state["mapDefinitionId"] = "demo-nine-node";
            state["configDigest"] =
                "sha256:9DA8013D3B7D1C1F5C5B27BDA813F1ADC9E2C8C5C80F3680B9FFDF773A9B76B0";
            state["encounter"] = new JObject
            {
                ["definitionId"] = "demo1-encounter-distance",
                ["rulesVersion"] = "warlord.encounter-distance.v1",
                ["configDigest"] =
                    "sha256:6D94E0ABCA11BE5AE1574219D30E4E8E1E3890293496FB2192E081AB24DFE29E"
            };

            JObject nodes = new JObject();
            AddDemo1EncounterNode(nodes, "R-HQ", "hq", 5, 3, 0, 0, "encounter.near", "near", 180);
            AddDemo1EncounterNode(nodes, "R-Supply", "supply", 4, 3, 0, 0, "encounter.medium", "medium", 360);
            AddDemo1EncounterNode(nodes, "R-Economy", "economy", 3, 3, 0, 0, "encounter.medium", "medium", 360);
            AddDemo1EncounterNode(nodes, "North-Choke", "choke", 4, 2, 0.2, 0, "encounter.far", "far", 650);
            AddDemo1EncounterNode(nodes, "Center-Command", "command", 4, 4, 0, 2, "encounter.far", "far", 650);
            AddDemo1EncounterNode(nodes, "South-Depot", "depot", 3, 3, 0, 0, "encounter.far", "far", 650);
            AddDemo1EncounterNode(nodes, "B-Economy", "economy", 3, 3, 0, 0, "encounter.medium", "medium", 360);
            AddDemo1EncounterNode(nodes, "B-Supply", "supply", 4, 3, 0, 0, "encounter.medium", "medium", 360);
            AddDemo1EncounterNode(nodes, "B-HQ", "hq", 5, 3, 0, 0, "encounter.near", "near", 180);

            string originNodeId = targetNodeId == "R-Supply" ? "North-Choke" : "R-Supply";
            ((JObject)nodes[originNodeId])["pieceIds"] = new JArray("pet-red-12");
            ((JObject)nodes[targetNodeId])["pieceIds"] = new JArray("pet-blue-15");
            state["map"] = new JObject
            {
                ["nodes"] = nodes,
                ["edges"] = new JArray
                {
                    new JObject { ["a"] = originNodeId, ["b"] = targetNodeId }
                }
            };
            state["pieces"]["pet-red-12"]["nodeId"] = originNodeId;
            state["pieces"]["pet-blue-15"]["nodeId"] = targetNodeId;
            request["command"]["originNodeId"] = originNodeId;
            request["command"]["targetNodeId"] = targetNodeId;
        }

        private static JObject BuildDemo2EncounterRequest(
            string targetNodeId,
            string targetKind,
            int targetAttackWidth,
            string targetProfile,
            string targetBand,
            int targetDistance)
        {
            JObject request = BuildRequest();
            JObject state = (JObject)request["state"];
            state["rulesVersion"] = "wargame-demo-v0.1.1";
            state["scenarioId"] = "warlord_demo_02_v1";
            state["mapDefinitionId"] = "demo2-thick-x-80";
            state["configDigest"] =
                "sha256:DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD";
            state["playerFactionId"] = Demo2Player;
            state["activeFactionId"] = Demo2Player;
            state["turnOrder"] = new JArray(
                Demo2Player,
                Demo2PactA,
                Demo2Independent,
                Demo2PactB);
            state["encounter"] = new JObject
            {
                ["definitionId"] = "demo1-encounter-distance",
                ["rulesVersion"] = "warlord.encounter-distance.v1",
                ["configDigest"] =
                    "sha256:6D94E0ABCA11BE5AE1574219D30E4E8E1E3890293496FB2192E081AB24DFE29E"
            };

            const string originNodeId = "d2-player-14";
            state["map"] = new JObject
            {
                ["nodes"] = new JObject
                {
                    [originNodeId] = new JObject
                    {
                        ["kind"] = "logistics",
                        ["attackWidth"] = 3,
                        ["encounterProfileRef"] = "encounter.medium",
                        ["distanceBand"] = "medium",
                        ["spawnDistance"] = 360,
                        ["pieceIds"] = new JArray("pet-red-12")
                    },
                    [targetNodeId] = new JObject
                    {
                        ["kind"] = targetKind,
                        ["attackWidth"] = targetAttackWidth,
                        ["encounterProfileRef"] = targetProfile,
                        ["distanceBand"] = targetBand,
                        ["spawnDistance"] = targetDistance,
                        ["pieceIds"] = new JArray("pet-blue-15")
                    }
                },
                ["edges"] = new JArray
                {
                    new JObject
                    {
                        ["a"] = originNodeId,
                        ["b"] = targetNodeId
                    }
                }
            };

            state["pieces"]["pet-red-12"]["factionId"] = Demo2Player;
            state["pieces"]["pet-red-12"]["nodeId"] = originNodeId;
            state["pieces"]["pet-blue-15"]["factionId"] = Demo2Independent;
            state["pieces"]["pet-blue-15"]["nodeId"] = targetNodeId;
            state["factions"] = new JObject
            {
                [Demo2Player] = new JObject
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
                [Demo2PactA] = new JObject
                {
                    ["actionPoints"] = 4,
                    ["cards"] = new JObject()
                },
                [Demo2Independent] = new JObject
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
                },
                [Demo2PactB] = new JObject
                {
                    ["actionPoints"] = 4,
                    ["cards"] = new JObject()
                }
            };
            state["relations"] = BuildDemo2Relations();
            request["command"]["factionId"] = Demo2Player;
            request["command"]["originNodeId"] = originNodeId;
            request["command"]["targetNodeId"] = targetNodeId;
            return request;
        }

        private static void ConfigureTrustedDemo2PlayerAvatarBattle(JObject request)
        {
            JObject state = (JObject)request["state"];
            JObject playerPiece = (JObject)state["pieces"]["pet-red-12"];
            string playerNodeId = (string)playerPiece["nodeId"];
            playerPiece["cardId"] = 83;
            playerPiece["productionGoldValue"] = 180;
            state["factions"][Demo2Player]["cards"] = new JObject
            {
                ["83"] = new JObject
                {
                    ["level"] = 50,
                    ["purchasedPromotions"] = new JArray()
                }
            };

            JObject enemyPiece = (JObject)state["pieces"]["pet-blue-15"];
            enemyPiece["cardId"] = 113;
            enemyPiece["productionGoldValue"] = 180;
            state["factions"][Demo2Independent]["cards"] = new JObject
            {
                ["113"] = new JObject
                {
                    ["level"] = 1,
                    ["purchasedPromotions"] = new JArray()
                }
            };

            state["commanders"] = new JObject
            {
                ["commander.player"] = new JObject
                {
                    ["commanderId"] = "commander.player",
                    ["characterId"] = "character.player-avatar",
                    ["factionId"] = Demo2Player,
                    ["role"] = "player_avatar",
                    ["cardId"] = 83,
                    ["status"] = "fielded",
                    ["pieceInstanceId"] = "pet-red-12",
                    ["nodeId"] = playerNodeId,
                    ["apContribution"] = 1,
                    ["productionGoldCost"] = 0,
                    ["productionRounds"] = 0,
                    ["remainingProductionRounds"] = 0,
                    ["readyFromRound"] = 1
                },
                ["commander.boss-independent"] = new JObject
                {
                    ["commanderId"] = "commander.boss-independent",
                    ["characterId"] = "character.surveyor",
                    ["factionId"] = Demo2Independent,
                    ["role"] = "boss_unique",
                    ["cardId"] = 113,
                    ["status"] = "fielded",
                    ["pieceInstanceId"] = "pet-blue-15",
                    ["nodeId"] = enemyPiece["nodeId"].DeepClone(),
                    ["apContribution"] = 1,
                    ["productionGoldCost"] = 180,
                    ["productionRounds"] = 4,
                    ["remainingProductionRounds"] = 0,
                    ["readyFromRound"] = 1
                }
            };
        }

        private static JObject BuildDemo2Relations()
        {
            string[] factionIds =
            {
                Demo2Player,
                Demo2PactA,
                Demo2Independent,
                Demo2PactB
            };
            JObject relations = new JObject();
            foreach (string factionId in factionIds)
            {
                relations[factionId] = new JObject
                {
                    [factionId] = "allied"
                };
            }
            SetSymmetricRelation(
                relations, Demo2Player, Demo2PactA, "hostile");
            SetSymmetricRelation(
                relations, Demo2Player, Demo2Independent, "hostile");
            SetSymmetricRelation(
                relations, Demo2Player, Demo2PactB, "hostile");
            SetSymmetricRelation(
                relations, Demo2PactA, Demo2Independent, "hostile");
            SetSymmetricRelation(
                relations, Demo2PactA, Demo2PactB, "allied");
            SetSymmetricRelation(
                relations, Demo2Independent, Demo2PactB, "hostile");
            return relations;
        }

        private static void AddDemo1EncounterNode(
            JObject nodes,
            string nodeId,
            string kind,
            int garrisonCapacity,
            int attackWidth,
            double defenseBonus,
            int nodeAPBonus,
            string encounterProfileRef,
            string distanceBand,
            int spawnDistance)
        {
            nodes[nodeId] = new JObject
            {
                ["kind"] = kind,
                ["garrisonCapacity"] = garrisonCapacity,
                ["attackWidth"] = attackWidth,
                ["defenseBonus"] = defenseBonus,
                ["nodeAPBonus"] = nodeAPBonus,
                ["encounterProfileRef"] = encounterProfileRef,
                ["distanceBand"] = distanceBand,
                ["spawnDistance"] = spawnDistance,
                ["pieceIds"] = new JArray()
            };
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

        private static WarlordScenarioAuthorityCatalog BuildFourFactionCatalog()
        {
            return new WarlordScenarioAuthorityCatalog(
                new[]
                {
                    new WarlordScenarioAuthorityDefinition(
                        "slice4-four-faction",
                        "warlord-strategy-v2",
                        "slice4-authority-map",
                        "sha256:4444444444444444444444444444444444444444444444444444444444444444",
                        new[]
                        {
                            FourFactionPlayer,
                            FourFactionIndependent,
                            FourFactionAlly,
                            FourFactionNeutral
                        },
                        new[]
                        {
                            new WarlordScenarioRelationDefinition(
                                FourFactionPlayer, FourFactionIndependent, "hostile"),
                            new WarlordScenarioRelationDefinition(
                                FourFactionPlayer, FourFactionAlly, "allied"),
                            new WarlordScenarioRelationDefinition(
                                FourFactionPlayer, FourFactionNeutral, "neutral"),
                            new WarlordScenarioRelationDefinition(
                                FourFactionIndependent, FourFactionAlly, "hostile"),
                            new WarlordScenarioRelationDefinition(
                                FourFactionIndependent, FourFactionNeutral, "neutral"),
                            new WarlordScenarioRelationDefinition(
                                FourFactionAlly, FourFactionNeutral, "allied")
                        })
                });
        }

        private static JObject BuildFourFactionRequest()
        {
            JObject request = BuildRequest();
            JObject state = (JObject)request["state"];
            state["rulesVersion"] = "warlord-strategy-v2";
            state["scenarioId"] = "slice4-four-faction";
            state["mapDefinitionId"] = "slice4-authority-map";
            state["configDigest"] =
                "sha256:4444444444444444444444444444444444444444444444444444444444444444";
            state["playerFactionId"] = FourFactionPlayer;
            state["activeFactionId"] = FourFactionPlayer;
            state["turnOrder"] = new JArray(
                FourFactionPlayer,
                FourFactionIndependent,
                FourFactionAlly,
                FourFactionNeutral);

            JObject legacyFactions = (JObject)state["factions"];
            state["factions"] = new JObject
            {
                [FourFactionPlayer] = legacyFactions["red"].DeepClone(),
                [FourFactionIndependent] = legacyFactions["blue"].DeepClone(),
                [FourFactionAlly] = new JObject
                {
                    ["actionPoints"] = 0,
                    ["cards"] = new JObject()
                },
                [FourFactionNeutral] = new JObject
                {
                    ["actionPoints"] = 0,
                    ["cards"] = new JObject()
                }
            };
            state["pieces"]["pet-red-12"]["factionId"] = FourFactionPlayer;
            state["pieces"]["pet-blue-15"]["factionId"] = FourFactionIndependent;
            state["relations"] = BuildFourFactionRelations();
            request["command"]["factionId"] = FourFactionPlayer;
            return request;
        }

        private static JObject BuildFourFactionRelations()
        {
            string[] factionIds =
            {
                FourFactionPlayer,
                FourFactionIndependent,
                FourFactionAlly,
                FourFactionNeutral
            };
            JObject relations = new JObject();
            foreach (string factionId in factionIds)
            {
                relations[factionId] = new JObject
                {
                    [factionId] = "allied"
                };
            }
            SetSymmetricRelation(
                relations, FourFactionPlayer, FourFactionIndependent, "hostile");
            SetSymmetricRelation(
                relations, FourFactionPlayer, FourFactionAlly, "allied");
            SetSymmetricRelation(
                relations, FourFactionPlayer, FourFactionNeutral, "neutral");
            SetSymmetricRelation(
                relations, FourFactionIndependent, FourFactionAlly, "hostile");
            SetSymmetricRelation(
                relations, FourFactionIndependent, FourFactionNeutral, "neutral");
            SetSymmetricRelation(
                relations, FourFactionAlly, FourFactionNeutral, "allied");
            return relations;
        }

        private static void SetSymmetricRelation(
            JObject relations,
            string leftFactionId,
            string rightFactionId,
            string relation)
        {
            relations[leftFactionId][rightFactionId] = relation;
            relations[rightFactionId][leftFactionId] = relation;
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
            catalog.PetsById[82] = new PetDef
            {
                Id = 82, Name = "精锐突击兵", Identifier = "敌人-精锐突击兵",
                RosterType = "partner", Price = 60000
            };
            catalog.PetsById[111] = new PetDef
            {
                Id = 111,
                Name = "吴豫",
                Identifier = "敌人-Itinerant",
                RosterType = "partner",
                KPrice = 12000
            };
            catalog.PetsById[112] = new PetDef
            {
                Id = 112,
                Name = "阎凝儿",
                Identifier = "敌人-Gazer",
                RosterType = "partner",
                KPrice = 12000
            };
            catalog.PetsById[113] = new PetDef
            {
                Id = 113,
                Name = "袁望",
                Identifier = "敌人-Surveyor",
                RosterType = "partner",
                KPrice = 12000
            };
            return catalog;
        }

    }
}
