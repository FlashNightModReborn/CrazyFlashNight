using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Wings;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Wings
{
    public sealed class LoreProjectionTests
    {
        [Fact]
        public void CatalogAndFixturesAreStrictVersionedAssets()
        {
            LoreCatalog catalog = WingsTestFixture.Catalog();
            Assert.Equal(
                "public-companion.v1@88479aee4c",
                catalog.CatalogRevision);
            Assert.Equal(13, catalog.Facts.Count);
            Assert.All(
                catalog.Facts.Values,
                fact => Assert.DoesNotContain(
                    "docs/worldbuilding/",
                    fact.SourceAuthority.Replace('\\', '/'),
                    StringComparison.OrdinalIgnoreCase));

            using JsonDocument schema = JsonDocument.Parse(
                File.ReadAllBytes(Path.Combine(
                    WingsTestFixture.AssetDirectory,
                    "public-companion.v1.schema.json")));
            Assert.False(
                schema.RootElement
                    .GetProperty("additionalProperties")
                    .GetBoolean());
            Assert.Equal(
                1,
                schema.RootElement
                    .GetProperty("properties")
                    .GetProperty("schemaVersion")
                    .GetProperty("const")
                    .GetInt32());

            foreach (string fixture in new[]
                     {
                         "old-save.json",
                         "ng-plus.json",
                         "fully-unlocked-developer.json",
                         "mutually-exclusive-easy.json"
                     })
            {
                Assert.NotNull(WingsTestFixture.Progress(fixture));
            }
        }

        [Fact]
        public void ParserRejectsUnknownDuplicateAndWorldbuildingSource()
        {
            Assert.Throws<InvalidDataException>(
                () => LoreCatalogParser.Parse(
                    Encoding.UTF8.GetBytes(
                        """
                        {"schemaVersion":1,"schemaVersion":1,"catalogId":"public-companion","catalogRevision":"r","publicStoryPhaseIds":["sp_7Qm2vL8aR4nK9xT1cY6uP"],"facts":[]}
                        """)));
            Assert.Throws<InvalidDataException>(
                () => LoreCatalogParser.ParseProgressFixture(
                    Encoding.UTF8.GetBytes(
                        """
                        {"saveBindingId":"sv_3Lq8rV1nP6mT9xC2kH5wZ","saveSignature":"1111111111111111111111111111111111111111111111111111111111111111","saveClass":"legacy","storyPhaseId":"sp_7Qm2vL8aR4nK9xT1cY6uP","progressRevision":"r","progressFlags":[],"branchSelections":{},"revealedFactIds":[],"extra":true}
                        """)));
            Assert.Throws<InvalidDataException>(
                () => new LoreFact(
                    "fact.public.invalid",
                    "docs/worldbuilding/secret.md",
                    LoreCanonClass.GameplayPublic,
                    "r1",
                    "secret",
                    new[] { WingsGuidanceDomain.Task },
                    new[] { "task.overview" },
                    new LoreRevealPredicate(
                        WingsSaveClass.Legacy,
                        Array.Empty<string>(),
                        Array.Empty<string>(),
                        null,
                        false)));
        }

        [Fact]
        public void OldSaveSnapshotIsNarrowAndEasyOnly()
        {
            LoreView view = WingsTestFixture.View("old-save.json");
            Assert.Equal(
                new[]
                {
                    "cue.permission-scope-honesty",
                    "guidance.equipment.held-weapon-properties",
                    "guidance.equipment.inventory-capacity-rule",
                    "guidance.task.difficulty-easy",
                    "guidance.task.visible-state-only",
                    "guidance.ui.shell-hide-indicator"
                },
                WingsTestFixture.FactIds(view));
            Assert.DoesNotContain(
                "guidance.task.difficulty-balanced",
                view.Facts.Keys);
            Assert.DoesNotContain(
                view.Facts.Keys,
                id => id.StartsWith(
                    "context.save.",
                    StringComparison.Ordinal));
        }

        [Fact]
        public void NgPlusAndDeveloperSnapshotsStayIsolated()
        {
            LoreView ng = WingsTestFixture.View("ng-plus.json");
            Assert.Equal(
                new[]
                {
                    "context.save.ng-plus",
                    "cue.permission-scope-honesty",
                    "guidance.equipment.held-weapon-properties",
                    "guidance.equipment.inventory-capacity-rule",
                    "guidance.route.map-click-teleport",
                    "guidance.task.daily-after-metro",
                    "guidance.task.difficulty-balanced",
                    "guidance.task.online-reward-after-rock-park",
                    "guidance.task.visible-state-only",
                    "guidance.ui.hairdresser-catalog-cas",
                    "guidance.ui.shell-hide-indicator"
                },
                WingsTestFixture.FactIds(ng));
            Assert.DoesNotContain(
                "context.save.developer-unlocked",
                ng.Facts.Keys);

            LoreView developer = WingsTestFixture.View(
                "fully-unlocked-developer.json");
            Assert.Contains(
                "context.save.developer-unlocked",
                developer.Facts.Keys);
            Assert.DoesNotContain(
                "context.save.ng-plus",
                developer.Facts.Keys);
            Assert.DoesNotContain(
                "guidance.task.difficulty-easy",
                developer.Facts.Keys);
        }

        [Fact]
        public void MutuallyExclusiveBranchNeverProjectsBothFacts()
        {
            foreach (string fixture in new[]
                     {
                         "old-save.json",
                         "ng-plus.json",
                         "fully-unlocked-developer.json",
                         "mutually-exclusive-easy.json"
                     })
            {
                LoreView view = WingsTestFixture.View(fixture);
                int branchFacts = view.Facts.Keys.Count(
                    id => id == "guidance.task.difficulty-easy"
                        || id == "guidance.task.difficulty-balanced");
                Assert.Equal(1, branchFacts);
            }
        }

        [Fact]
        public void ViewIdBindsSaveAndAllConsumersRejectCrossViewReuse()
        {
            LoreView first = WingsTestFixture.View();
            LoreView rebound = WingsTestFixture.ReboundView(
                first,
                "sv_4Cx8mN1qT6vK9rL2pD7hF",
                new string('B', 64));
            Assert.Equal(
                WingsTestFixture.FactIds(first),
                WingsTestFixture.FactIds(rebound));
            Assert.Equal(first.FactSetHash, rebound.FactSetHash);
            Assert.NotEqual(first.LoreViewId, rebound.LoreViewId);

            var cache = new LoreBoundCache<string>();
            cache.Put(first, "reply.task-overview", "first");
            Assert.True(cache.TryGet(
                first,
                "reply.task-overview",
                out string value));
            Assert.Equal("first", value);
            Assert.False(cache.TryGet(
                rebound,
                "reply.task-overview",
                out _));

            LoreModelInput input =
                new LoreModelInputBuilder().Build(
                    first,
                    WingsGuidanceDomain.Task,
                    "task.overview",
                    WingsTestFixture.VisibleContext(
                        WingsGuidanceDomain.Task));
            Assert.Equal(first.LoreViewId, input.LoreViewId);
            Assert.Equal(
                first.Progress.SaveBindingId,
                input.SaveBindingId);
            Assert.Single(input.Facts);
        }

        [Fact]
        public void NonPublicOpaquePhaseProjectsAnEmptyBoundView()
        {
            LoreProgressSnapshot old =
                WingsTestFixture.Progress("ng-plus.json");
            var hidden = new LoreProgressSnapshot(
                old.SaveBindingId,
                old.SaveSignature,
                old.SaveClass,
                "sp_1Qw7eR3tY9uI5oP2aS8dF",
                "hidden-r8",
                old.ProgressFlags,
                old.BranchSelections,
                old.RevealedFactIds);
            LoreView view = new LoreProjectionService().Project(
                WingsTestFixture.Catalog(),
                hidden);
            Assert.False(view.PublicCompanionEligible);
            Assert.Empty(view.Facts);
            Assert.Matches("^[A-Za-z0-9_-]{43}$", view.LoreViewId);
        }

        [Fact]
        public void VisibleContextIsStructuredAndDomainBound()
        {
            Assert.Throws<ArgumentException>(
                () => new WingsVisibleGuidanceContext(
                    WingsGuidanceDomain.Task,
                    "context.test.v1",
                    new System.Collections.Generic
                        .Dictionary<string, string>
                        {
                            ["player.health-inference"] = "anxious"
                        }));
            LoreView view = WingsTestFixture.View();
            Assert.Throws<ArgumentException>(
                () => new LoreModelInputBuilder().Build(
                    view,
                    WingsGuidanceDomain.Route,
                    "route.map",
                    WingsTestFixture.VisibleContext(
                        WingsGuidanceDomain.Task)));
        }
    }
}
