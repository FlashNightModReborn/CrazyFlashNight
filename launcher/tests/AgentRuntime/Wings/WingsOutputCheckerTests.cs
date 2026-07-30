using System;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Wings;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Wings
{
    public sealed class WingsOutputCheckerTests
    {
        [Fact]
        public void ExactFactSetProvenancePasses()
        {
            LoreView view = WingsTestFixture.View();
            WingsOutputCheckContext context = GuidanceContext(view);
            WingsDraftOutput draft =
                WingsCanonicalDraftFactory.Guidance(
                    context,
                    new[]
                    {
                        WingsTestFixture.Claim(
                            view,
                            "guidance.task.visible-state-only")
                    });
            WingsCheckedOutput result =
                new WingsOutputChecker().Check(draft, context);

            Assert.True(result.Accepted, result.ReasonCode);
            LoreFactProvenance provenance =
                Assert.Single(result.Provenance);
            Assert.Equal(
                "guidance.task.visible-state-only",
                provenance.FactId);
            Assert.Equal("F1", provenance.SourceRevision);
        }

        [Fact]
        public void CrossViewAndOutOfViewClaimsFailClosed()
        {
            LoreView view = WingsTestFixture.View();
            WingsOutputCheckContext original =
                GuidanceContext(view);
            WingsDraftOutput draft =
                WingsCanonicalDraftFactory.Guidance(
                    original,
                    new[]
                    {
                        WingsTestFixture.Claim(
                            view,
                            "guidance.task.visible-state-only")
                    });
            LoreView rebound = WingsTestFixture.ReboundView(
                view,
                "sv_9Jm4qX7cV2nL8rT1kP5dB");
            WingsCheckedOutput crossView =
                new WingsOutputChecker().Check(
                    draft,
                    GuidanceContext(rebound));
            Assert.False(crossView.Accepted);
            Assert.Equal(
                "lore_view_binding_mismatch",
                crossView.ReasonCode);

            var forbidden = new WingsDraftOutput(
                view.Progress.SaveBindingId,
                view.LoreViewId,
                WingsOutputPurpose.Guidance,
                "简单模式的任务 K 点奖励沿用原版节奏。",
                new[]
                {
                    new WingsFactClaim(
                        "guidance.task.difficulty-easy",
                        "88479aee4c")
                });
            WingsCheckedOutput outOfView =
                new WingsOutputChecker().Check(
                    forbidden,
                    new WingsOutputCheckContext(
                        WingsTestFixture.SessionId,
                        view,
                        WingsGuidanceDomain.Task,
                        "task.rewards",
                        WingsTestFixture.Now));
            Assert.False(outOfView.Accepted);
            Assert.Equal(
                "fact_not_in_lore_view",
                outOfView.ReasonCode);
        }

        [Fact]
        public void RevisionMismatchAndUnstructuredExtraTextAreRejected()
        {
            LoreView view = WingsTestFixture.View();
            WingsOutputCheckContext context = GuidanceContext(view);
            var badRevision = new WingsDraftOutput(
                view.Progress.SaveBindingId,
                view.LoreViewId,
                WingsOutputPurpose.Guidance,
                view.Facts["guidance.task.visible-state-only"]
                    .Statement,
                new[]
                {
                    new WingsFactClaim(
                        "guidance.task.visible-state-only",
                        "stale")
                });
            WingsCheckedOutput revision =
                new WingsOutputChecker().Check(
                    badRevision,
                    context);
            Assert.Equal(
                "fact_source_revision_mismatch",
                revision.ReasonCode);

            WingsFactClaim claim = WingsTestFixture.Claim(
                view,
                "guidance.task.visible-state-only");
            var extraText = new WingsDraftOutput(
                view.Progress.SaveBindingId,
                view.LoreViewId,
                WingsOutputPurpose.Guidance,
                view.Facts[claim.FactId].Statement
                    + "\n未在 catalog 中的断言。",
                new[] { claim });
            WingsCheckedOutput ungrounded =
                new WingsOutputChecker().Check(
                    extraText,
                    context);
            Assert.Equal(
                "noncanonical_or_ungrounded_text",
                ungrounded.ReasonCode);
        }

        [Fact]
        public void PresentationCueCannotMasqueradeAsGameplayFact()
        {
            LoreView view = WingsTestFixture.View();
            LoreFact cue =
                view.Facts["cue.permission-scope-honesty"];
            var draft = new WingsDraftOutput(
                view.Progress.SaveBindingId,
                view.LoreViewId,
                WingsOutputPurpose.Guidance,
                cue.Statement,
                new[]
                {
                    new WingsFactClaim(
                        cue.FactId,
                        cue.SourceRevision)
                });
            WingsCheckedOutput output =
                new WingsOutputChecker().Check(
                    draft,
                    new WingsOutputCheckContext(
                        WingsTestFixture.SessionId,
                        view,
                        WingsGuidanceDomain.Ui,
                        "cue.permission",
                        WingsTestFixture.Now));
            Assert.False(output.Accepted);
            Assert.Equal(
                "fact_canon_class_mismatch",
                output.ReasonCode);
        }

        [Fact]
        public void PermissionFactsMustBeNeutralFreshAndExactlyBound()
        {
            LoreView view = WingsTestFixture.View();
            TrustedNeutralPermissionFacts wrongSession =
                WingsTestFixture.Permission(
                    view,
                    WingsTestFixture.OtherSessionId);
            var context = new WingsOutputCheckContext(
                WingsTestFixture.SessionId,
                view,
                null,
                null,
                WingsTestFixture.Now,
                wrongSession);
            WingsDraftOutput draft =
                WingsCanonicalDraftFactory.Authorization(
                    context,
                    wrongSession.ReceiptId,
                    Array.Empty<WingsFactClaim>());
            WingsCheckedOutput output =
                new WingsOutputChecker().Check(draft, context);
            Assert.False(output.Accepted);
            Assert.Equal(
                "permission_facts_invalid_or_expired",
                output.ReasonCode);
        }

        [Fact]
        public void ResultTemplatePreservesFiveOutcomeSemantics()
        {
            LoreView view = WingsTestFixture.View();
            foreach (ActionOutcome outcome
                in Enum.GetValues<ActionOutcome>())
            {
                TrustedActionResultFacts facts =
                    WingsTestFixture.ActionResult(view, outcome);
                var context = new WingsOutputCheckContext(
                    WingsTestFixture.SessionId,
                    view,
                    null,
                    null,
                    WingsTestFixture.Now,
                    actionResultFacts: facts);
                WingsDraftOutput draft =
                    WingsCanonicalDraftFactory.ActionResult(
                        context,
                        facts.ReceiptId);
                WingsCheckedOutput output =
                    new WingsOutputChecker().Check(
                        draft,
                        context);
                Assert.True(output.Accepted, output.ReasonCode);
                Assert.StartsWith(
                    "执行结果：",
                    output.Text,
                    StringComparison.Ordinal);
            }
        }

        private static WingsOutputCheckContext GuidanceContext(
            LoreView view)
        {
            return new WingsOutputCheckContext(
                WingsTestFixture.SessionId,
                view,
                WingsGuidanceDomain.Task,
                "task.overview",
                WingsTestFixture.Now);
        }
    }
}
