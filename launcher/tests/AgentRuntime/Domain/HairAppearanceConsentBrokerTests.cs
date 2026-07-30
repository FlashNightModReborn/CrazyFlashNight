using System;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Domain
{
    public sealed class HairAppearanceConsentBrokerTests
    {
        [Fact]
        public async Task Consent_IsExactPreviewOneShotAndCappedAtSixtySeconds()
        {
            var clock = new ManualAgentRuntimeClock();
            HairAppearancePreview preview = await CreatePreviewAsync(clock);
            var broker = new HairAppearanceConsentBroker(clock);

            HairAppearanceConsentToken token = broker.IssueForNeutralUi(
                preview,
                "neutral-ui-receipt",
                TimeSpan.FromMinutes(5));

            Assert.Equal(
                clock.UtcNow.AddSeconds(60),
                token.ExpiresAtUtc);
            Assert.Null(broker.TryConsume(token.Token, preview));
            Assert.Equal(
                HairAppearanceReasonCodes.ConsentReplayed,
                broker.TryConsume(token.Token, preview));
        }

        [Fact]
        public async Task Consent_ExpiresByMonotonicClock()
        {
            var clock = new ManualAgentRuntimeClock();
            HairAppearancePreview preview = await CreatePreviewAsync(clock);
            var broker = new HairAppearanceConsentBroker(clock);
            HairAppearanceConsentToken token = broker.IssueForNeutralUi(
                preview,
                "neutral-ui-receipt",
                TimeSpan.FromSeconds(5));
            clock.Advance(TimeSpan.FromSeconds(5));

            Assert.Equal(
                HairAppearanceReasonCodes.ConsentExpired,
                broker.TryConsume(token.Token, preview));
        }

        [Fact]
        public async Task Consent_CannotAuthorizeAnotherPreview()
        {
            var clock = new ManualAgentRuntimeClock();
            HairAppearancePreview first = await CreatePreviewAsync(clock);
            HairAppearancePreview second = await CreatePreviewAsync(clock);
            var broker = new HairAppearanceConsentBroker(clock);
            HairAppearanceConsentToken token = broker.IssueForNeutralUi(
                first,
                "neutral-ui-receipt",
                TimeSpan.FromSeconds(60));

            Assert.Equal(
                HairAppearanceReasonCodes.ConsentMismatch,
                broker.TryConsume(token.Token, second));
            Assert.Null(broker.TryConsume(token.Token, first));
        }

        [Fact]
        public async Task NeutralIssuer_RejectsTamperedPreviewHash()
        {
            var clock = new ManualAgentRuntimeClock();
            HairAppearancePreview valid = await CreatePreviewAsync(clock);
            var tampered = new HairAppearancePreview(
                valid.TransactionId,
                valid.Binding,
                valid.BeforeHair,
                "发型-女式-短发",
                valid.ExpectedRevision,
                valid.ExpectedGeneration,
                valid.ExpectedSnapshotHash,
                valid.PreviewHash,
                valid.CreatedAtUtc);
            var broker = new HairAppearanceConsentBroker(clock);

            Assert.Throws<ArgumentException>(() =>
                broker.IssueForNeutralUi(
                    tampered,
                    "neutral-ui-receipt",
                    TimeSpan.FromSeconds(60)));
        }

        private static async Task<HairAppearancePreview> CreatePreviewAsync(
            ManualAgentRuntimeClock clock)
        {
            var binding = new HairSaveBinding(
                "session-1",
                1,
                "attempt-1",
                1,
                "slot-1",
                "save-1");
            var adapter = new InMemoryHairdresserDomainAdapter(
                binding,
                "光头");
            var store = new InMemoryHairRestorePointStore();
            var consent = new HairAppearanceConsentBroker(clock);
            var service = new HairAppearanceModifierTransaction(
                adapter,
                store,
                consent,
                clock);
            HairInspectResult inspect = await service.InspectAsync(binding);
            HairPreviewResult preview = await service.PreviewAsync(
                new HairPreviewRequest(
                    binding,
                    "发型-男式-平头",
                    inspect.Snapshot.CurrentHair,
                    inspect.Snapshot.Revision,
                    inspect.Snapshot.Generation,
                    inspect.SnapshotHash));
            return preview.Preview;
        }
    }
}
