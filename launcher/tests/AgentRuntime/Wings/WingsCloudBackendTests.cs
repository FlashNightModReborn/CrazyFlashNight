using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Wings;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Wings
{
    public sealed class WingsCloudBackendTests
    {
        private const string ProviderId = "cloud.reference";

        private static readonly string[] RequiredFields =
        {
            OptionalCloudWingsBackend.LoreBindingField,
            OptionalCloudWingsBackend.LoreFactSetField,
            OptionalCloudWingsBackend.GuidanceIntentField
        };

        [Fact]
        public async Task MissingEgressGrantNeverCallsProvider()
        {
            Setup setup = CreateSetup(null);
            WingsBackendResult result =
                await setup.Backend.GenerateAsync(
                    setup.Request,
                    null,
                    RequiredFields);

            Assert.Equal(0, setup.Provider.CallCount);
            Assert.Equal(
                WingsBackendSource.OfflineReference,
                result.Source);
            Assert.Equal(
                "cloud_data_egress_not_authorized",
                result.FallbackReasonCode);
            Assert.Equal(0, result.PenaltyDelta);
            Assert.Equal(
                "任务建议只依据当前存档已经公开的进度和当前可见任务上下文；未显示的任务不会被当作已经接取。",
                result.Output.Text);
        }

        [Fact]
        public async Task InvalidDisclosureShapeFailsClosedOffline()
        {
            LoreView view = WingsTestFixture.View();
            TrustedDataEgressGrant grant =
                Grant(view, RequiredFields);
            Setup setup = CreateSetup(grant);
            WingsBackendResult result =
                await setup.Backend.GenerateAsync(
                    setup.Request,
                    grant.ReceiptId,
                    new[] { "raw.audit-ledger" });
            Assert.Equal(0, setup.Provider.CallCount);
            Assert.Equal(
                "cloud_disclosure_fields_invalid",
                result.FallbackReasonCode);
            Assert.Equal(0, result.PenaltyDelta);
        }

        [Fact]
        public async Task ExactProviderFieldsAndViewAreMandatory()
        {
            Setup baseSetup = CreateSetup(null);
            TrustedDataEgressGrant wrongProvider = Grant(
                baseSetup.View,
                RequiredFields,
                providerId: "cloud.other");
            Setup providerMismatch = CreateSetup(wrongProvider);
            WingsBackendResult first =
                await providerMismatch.Backend.GenerateAsync(
                    providerMismatch.Request,
                    wrongProvider.ReceiptId,
                    RequiredFields);
            Assert.Equal(0, providerMismatch.Provider.CallCount);
            Assert.Equal(
                "cloud_data_egress_not_authorized",
                first.FallbackReasonCode);

            TrustedDataEgressGrant narrow = Grant(
                baseSetup.View,
                RequiredFields);
            Setup fieldMismatch = CreateSetup(narrow);
            string[] broader = RequiredFields
                .Append(
                    OptionalCloudWingsBackend.VisibleContextField)
                .ToArray();
            WingsBackendResult second =
                await fieldMismatch.Backend.GenerateAsync(
                    fieldMismatch.Request,
                    narrow.ReceiptId,
                    broader);
            Assert.Equal(0, fieldMismatch.Provider.CallCount);
            Assert.Equal(
                "cloud_data_egress_not_authorized",
                second.FallbackReasonCode);

            LoreView otherView = WingsTestFixture.ReboundView(
                baseSetup.View,
                "sv_7Lm2qR8cV4nK1xT9pD5hF");
            TrustedDataEgressGrant crossView = Grant(
                otherView,
                RequiredFields);
            Setup viewMismatch = CreateSetup(crossView);
            WingsBackendResult third =
                await viewMismatch.Backend.GenerateAsync(
                    viewMismatch.Request,
                    crossView.ReceiptId,
                    RequiredFields);
            Assert.Equal(0, viewMismatch.Provider.CallCount);
            Assert.Equal(
                "cloud_data_egress_not_authorized",
                third.FallbackReasonCode);
        }

        [Fact]
        public async Task ExpiredGrantFallsBackWithoutPenalty()
        {
            LoreView view = WingsTestFixture.View();
            TrustedDataEgressGrant expired = Grant(
                view,
                RequiredFields,
                expiresAt: WingsTestFixture.Now);
            Setup setup = CreateSetup(expired);

            WingsBackendResult result =
                await setup.Backend.GenerateAsync(
                    setup.Request,
                    expired.ReceiptId,
                    RequiredFields);
            Assert.Equal(0, setup.Provider.CallCount);
            Assert.Equal(0, result.PenaltyDelta);
            Assert.Equal(
                WingsBackendSource.OfflineReference,
                result.Source);
        }

        [Fact]
        public async Task ValidGrantExposesOnlyDisclosedFields()
        {
            LoreView view = WingsTestFixture.View();
            string[] fields = RequiredFields
                .Append(
                    OptionalCloudWingsBackend.VisibleContextField)
                .ToArray();
            TrustedDataEgressGrant grant = Grant(view, fields);
            Setup setup = CreateSetup(grant);

            WingsBackendResult result =
                await setup.Backend.GenerateAsync(
                    setup.Request,
                    grant.ReceiptId,
                    fields);

            Assert.Equal(1, setup.Provider.CallCount);
            Assert.Equal(
                WingsBackendSource.CloudProvider,
                result.Source);
            Assert.Equal(ProviderId, result.ProviderId);
            Assert.Equal(
                fields.OrderBy(value => value, StringComparer.Ordinal),
                result.DisclosedFieldKeys);
            Assert.Equal(
                fields.OrderBy(value => value, StringComparer.Ordinal),
                setup.Provider.LastRequest.DisclosedFields.Keys);
            Assert.Contains(
                "\"task.visible-state\":\"available\"",
                setup.Provider.LastRequest
                    .DisclosedFields[
                        OptionalCloudWingsBackend
                            .VisibleContextField],
                StringComparison.Ordinal);
            Assert.Equal(0, result.PenaltyDelta);
        }

        [Fact]
        public async Task ProviderFaultFallsBackToReferenceOracle()
        {
            LoreView view = WingsTestFixture.View();
            TrustedDataEgressGrant grant =
                Grant(view, RequiredFields);
            Setup setup = CreateSetup(
                grant,
                new InvalidOperationException("provider down"));

            WingsBackendResult result =
                await setup.Backend.GenerateAsync(
                    setup.Request,
                    grant.ReceiptId,
                    RequiredFields);
            Assert.Equal(1, setup.Provider.CallCount);
            Assert.Equal(
                WingsBackendSource.OfflineReference,
                result.Source);
            Assert.Equal(
                "cloud_provider_failed",
                result.FallbackReasonCode);
            Assert.Equal(0, result.PenaltyDelta);
            Assert.Equal(
                "任务建议只依据当前存档已经公开的进度和当前可见任务上下文；未显示的任务不会被当作已经接取。",
                result.Output.Text);
        }

        [Fact]
        public async Task UngroundedCloudTextIsRejectedThenFallsBack()
        {
            LoreView view = WingsTestFixture.View();
            TrustedDataEgressGrant grant =
                Grant(view, RequiredFields);
            WingsFactClaim claim = WingsTestFixture.Claim(
                view,
                "guidance.task.visible-state-only");
            var badDraft = new WingsDraftOutput(
                view.Progress.SaveBindingId,
                view.LoreViewId,
                WingsOutputPurpose.Guidance,
                view.Facts[claim.FactId].Statement
                    + "\n模型自行添加的承诺。",
                new[] { claim });
            Setup setup = CreateSetup(
                grant,
                cloudDraft: badDraft);

            WingsBackendResult result =
                await setup.Backend.GenerateAsync(
                    setup.Request,
                    grant.ReceiptId,
                    RequiredFields);
            Assert.Equal(1, setup.Provider.CallCount);
            Assert.Equal(
                WingsBackendSource.OfflineReference,
                result.Source);
            Assert.StartsWith(
                "cloud_output_rejected:",
                result.FallbackReasonCode,
                StringComparison.Ordinal);
            Assert.DoesNotContain(
                "承诺",
                result.Output.Text,
                StringComparison.Ordinal);
            Assert.Equal(0, result.PenaltyDelta);
        }

        private static Setup CreateSetup(
            TrustedDataEgressGrant grant,
            Exception providerException = null,
            WingsDraftOutput cloudDraft = null)
        {
            LoreView view = WingsTestFixture.View();
            WingsGuidanceRequest request =
                WingsGuidanceRequest.ForGuidance(
                    WingsTestFixture.SessionId,
                    view,
                    WingsGuidanceDomain.Task,
                    "task.overview",
                    WingsTestFixture.VisibleContext(
                        WingsGuidanceDomain.Task));
            var offline = new DeterministicOfflineWingsBackend(
                utcNow: () => WingsTestFixture.Now);
            WingsOutputCheckContext context =
                new WingsOutputCheckContext(
                    WingsTestFixture.SessionId,
                    view,
                    WingsGuidanceDomain.Task,
                    "task.overview",
                    WingsTestFixture.Now);
            WingsDraftOutput validDraft =
                WingsCanonicalDraftFactory.Guidance(
                    context,
                    new[]
                    {
                        WingsTestFixture.Claim(
                            view,
                            "guidance.task.visible-state-only")
                    });
            var provider = new StubCloudProvider(
                cloudDraft ?? validDraft,
                providerException);
            var backend = new OptionalCloudWingsBackend(
                offline,
                provider,
                new StubGrantAuthority(grant),
                utcNow: () => WingsTestFixture.Now);
            return new Setup(
                view,
                request,
                provider,
                backend);
        }

        private static TrustedDataEgressGrant Grant(
            LoreView view,
            IEnumerable<string> fields,
            string providerId = ProviderId,
            DateTimeOffset? expiresAt = null)
        {
            return new TrustedDataEgressGrant(
                WingsTestFixture.EgressReceiptId,
                WingsTestFixture.SessionId,
                view.Progress.SaveBindingId,
                view.LoreViewId,
                providerId,
                fields,
                WingsTestFixture.Now.AddMinutes(-1),
                expiresAt ?? WingsTestFixture.Now.AddMinutes(10));
        }

        private sealed class Setup
        {
            public Setup(
                LoreView view,
                WingsGuidanceRequest request,
                StubCloudProvider provider,
                OptionalCloudWingsBackend backend)
            {
                View = view;
                Request = request;
                Provider = provider;
                Backend = backend;
            }

            public LoreView View { get; }
            public WingsGuidanceRequest Request { get; }
            public StubCloudProvider Provider { get; }
            public OptionalCloudWingsBackend Backend { get; }
        }

        private sealed class StubGrantAuthority
            : IDataEgressGrantAuthority
        {
            private readonly TrustedDataEgressGrant _grant;

            public StubGrantAuthority(TrustedDataEgressGrant grant)
            {
                _grant = grant;
            }

            public bool TryResolve(
                string receiptId,
                out TrustedDataEgressGrant grant,
                out string reasonCode)
            {
                grant = string.Equals(
                    receiptId,
                    _grant?.ReceiptId,
                    StringComparison.Ordinal)
                        ? _grant
                        : null;
                reasonCode = grant == null ? "not_found" : null;
                return grant != null;
            }
        }

        private sealed class StubCloudProvider
            : IWingsCloudProvider
        {
            private readonly WingsDraftOutput _draft;
            private readonly Exception _exception;

            public StubCloudProvider(
                WingsDraftOutput draft,
                Exception exception)
            {
                _draft = draft;
                _exception = exception;
            }

            public string ProviderId => WingsCloudBackendTests.ProviderId;
            public int CallCount { get; private set; }
            public WingsCloudProviderRequest LastRequest { get; private set; }

            public Task<WingsDraftOutput> GenerateAsync(
                WingsCloudProviderRequest request,
                CancellationToken cancellationToken)
            {
                CallCount++;
                LastRequest = request;
                if (_exception != null)
                {
                    return Task.FromException<WingsDraftOutput>(
                        _exception);
                }
                return Task.FromResult(_draft);
            }
        }
    }
}
