using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class WarlordDemo2AuthorityTests
    {
        private const string Demo2ScenarioRef = "warlord_demo_02_v1";
        private const string Demo2RulesVersion = "wargame-demo-v0.1.1";
        private const string Demo2MapId = "demo2-thick-x-80";

        private static readonly string[] Demo2FactionIds =
        {
            "player",
            "boss-pact-a",
            "boss-independent",
            "boss-pact-b"
        };

        [Fact]
        public void DefaultCatalog_Demo2UsesVersionedIdentityAndHostOwnedRelations()
        {
            WarlordScenarioAuthorityCatalog catalog =
                WarlordScenarioAuthorityCatalog.CreateDefault();
            WarlordScenarioAuthorityDefinition authority;

            // Demo 2 has no canonical strategic digest yet. A browser digest is
            // deliberately not treated as verified; exact scenario/rules/map IDs
            // are the temporary authority boundary.
            Assert.True(catalog.TryResolve(
                Demo2ScenarioRef,
                Demo2RulesVersion,
                Demo2MapId,
                "sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                out authority));
            Assert.False(authority.HasConfigDigestAuthority);
            Assert.Null(authority.ConfigDigest);
            Assert.Equal(Demo2FactionIds, authority.FactionIds);

            AssertRelation(authority, "player", "boss-pact-a", "hostile");
            AssertRelation(authority, "player", "boss-independent", "hostile");
            AssertRelation(authority, "player", "boss-pact-b", "hostile");
            AssertRelation(authority, "boss-pact-a", "boss-independent", "hostile");
            AssertRelation(authority, "boss-pact-a", "boss-pact-b", "allied");
            AssertRelation(authority, "boss-independent", "boss-pact-b", "hostile");
            foreach (string factionId in Demo2FactionIds)
                AssertRelation(authority, factionId, factionId, "allied");

            Assert.False(catalog.TryResolve(
                Demo2ScenarioRef,
                Demo2RulesVersion,
                "demo2-thick-x-80-drifted",
                null,
                out authority));
            Assert.False(catalog.TryResolve(
                "warlord_demo_02_v2",
                Demo2RulesVersion,
                Demo2MapId,
                null,
                out authority));
        }

        [Fact]
        public void DefaultCatalog_Demo1StillRequiresItsExactDigest()
        {
            WarlordScenarioAuthorityCatalog catalog =
                WarlordScenarioAuthorityCatalog.CreateDefault();
            WarlordScenarioAuthorityDefinition authority;

            Assert.False(catalog.TryResolve(
                "warlord_tutorial_v1",
                Demo2RulesVersion,
                "demo-nine-node",
                "sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                out authority));
            Assert.True(catalog.TryResolve(
                "warlord_tutorial_v1",
                Demo2RulesVersion,
                "demo-nine-node",
                "sha256:9DA8013D3B7D1C1F5C5B27BDA813F1ADC9E2C8C5C80F3680B9FFDF773A9B76B0",
                out authority));
            Assert.True(authority.HasConfigDigestAuthority);
        }

        [Fact]
        public void StageGateAndRouter_AcceptBothVersionedScenariosWithDistinctSeeds()
        {
            Assert.True(WarlordStageTask.IsAllowedScenarioRef(
                WarlordStageTask.AllowedScenarioRef));
            Assert.True(WarlordStageTask.IsAllowedScenarioRef(
                WarlordStageTask.Demo2ScenarioRef));
            Assert.False(WarlordStageTask.IsAllowedScenarioRef(
                "warlord_demo_02_v2"));

            AssertStageInit(
                WarlordStageTask.AllowedScenarioRef,
                "warlord-tutorial-v1-seed-001");
            AssertStageInit(
                WarlordStageTask.Demo2ScenarioRef,
                "warlord-demo2-v1-seed-001");

            int opens = 0;
            var task = new WarlordStageTask(delegate { return true; });
            task.SetOpenHandler(delegate(
                JObject binding,
                JObject playerAvatarPortrait,
                JObject resumeCheckpoint,
                string panelInstanceId,
                Func<bool> executionGate,
                Action<PanelHostController.TrackedOpenOutcome> completed)
            {
                opens++;
                Assert.Equal(Demo2ScenarioRef, (string)binding["scenarioRef"]);
                Assert.Equal(
                    WarlordStageTask.PlayerAvatarPortraitSchema,
                    (string)playerAvatarPortrait["schema"]);
                Assert.Null(resumeCheckpoint);
                Assert.True(executionGate());
                completed(PanelHostController.TrackedOpenOutcome.OpenPosted);
                return true;
            });
            Assert.Null(task.HandleStart(new JObject
            {
                ["task"] = "warlord_stage_start",
                ["payload"] = new JObject
                {
                    ["binding"] = BuildBinding(Demo2ScenarioRef),
                    ["playerAvatarPortrait"] = BuildPlayerAvatarPortrait()
                }
            }));
            Assert.Equal(1, opens);
        }

        [Fact]
        public void ProductData_KeepsDemo1AndDemo2AsSeparateSingleSubStageXmls()
        {
            AssertStageXml(
                "军阀战术演习.xml",
                "warlord_tutorial",
                WarlordStageTask.AllowedScenarioRef);
            AssertStageXml(
                "军阀四方大战役（Slice 6 验收候选）.xml",
                "warlord_demo2",
                WarlordStageTask.Demo2ScenarioRef);

            var list = new XmlDocument();
            list.Load(FindRepositoryFile(
                "data", "stages", "副本任务", "__list__.xml"));
            XmlNodeList entries = list.SelectNodes("/Stages/StageInfo");
            Assert.NotNull(entries);
            Assert.Equal(1, entries.Cast<XmlNode>().Count(node =>
                node.SelectSingleNode("Name")?.InnerText == "军阀战术演习"));
            Assert.Equal(1, entries.Cast<XmlNode>().Count(node =>
                node.SelectSingleNode("Name")?.InnerText
                    == "军阀四方大战役（Slice 6 验收候选）"));
        }

        private static void AssertStageInit(
            string scenarioRef,
            string expectedSeed)
        {
            JObject binding = BuildBinding(scenarioRef);
            JObject init;
            string rejection;
            Assert.True(LauncherCommandRouter.TryBuildWarlordStageInitData(
                binding,
                BuildPlayerAvatarPortrait(),
                out init,
                out rejection));
            Assert.Null(rejection);
            Assert.Equal(expectedSeed, (string)init["seed"]);
            Assert.True(JToken.DeepEquals(binding, init["stageOuterBinding"]));
        }

        private static JObject BuildBinding(string scenarioRef)
        {
            return new JObject
            {
                ["schema"] = WarlordStageTask.BindingSchema,
                ["runId"] = "run.demo2",
                ["subStageId"] = "sub.demo2",
                ["scenarioRef"] = scenarioRef,
                ["callId"] = "call.demo2",
                ["revision"] = 0
            };
        }

        private static JObject BuildPlayerAvatarPortrait()
        {
            return new JObject
            {
                ["schema"] = WarlordStageTask.PlayerAvatarPortraitSchema,
                ["gender"] = "男",
                ["face"] = "男变装-基本脸型",
                ["hair"] = "",
                ["equipment"] = new JObject
                {
                    ["head"] = "", ["body"] = "", ["hand"] = "",
                    ["leg"] = "", ["foot"] = "", ["neck"] = ""
                }
            };
        }

        private static void AssertRelation(
            WarlordScenarioAuthorityDefinition authority,
            string left,
            string right,
            string expected)
        {
            string actual;
            Assert.True(authority.TryGetRelation(left, right, out actual));
            Assert.Equal(expected, actual);
            string reverse;
            Assert.True(authority.TryGetRelation(right, left, out reverse));
            Assert.Equal(expected, reverse);
        }

        private static void AssertStageXml(
            string fileName,
            string expectedSubStageId,
            string expectedScenarioRef)
        {
            var document = new XmlDocument();
            document.Load(FindRepositoryFile(
                "data", "stages", "副本任务", fileName));
            Assert.Equal("GameStage", document.DocumentElement?.Name);
            XmlNodeList subStages = document.SelectNodes("/GameStage/SubStage");
            Assert.NotNull(subStages);
            XmlNode subStage = Assert.Single(subStages.Cast<XmlNode>());
            Assert.Equal(3, subStage.Attributes?.Count);
            Assert.Equal(expectedSubStageId, subStage.Attributes?["id"]?.Value);
            Assert.Equal("Warlord", subStage.Attributes?["driver"]?.Value);
            Assert.Equal(expectedScenarioRef, subStage.Attributes?["scenarioRef"]?.Value);
            Assert.Null(document.SelectSingleNode("/GameStage/TimePools"));
        }

        private static string FindRepositoryFile(params string[] parts)
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string candidate = current.FullName;
                foreach (string part in parts)
                    candidate = Path.Combine(candidate, part);
                if (File.Exists(candidate)) return candidate;
                current = current.Parent;
            }
            throw new FileNotFoundException(
                "Unable to locate repository file: " + string.Join("/", parts));
        }
    }
}
