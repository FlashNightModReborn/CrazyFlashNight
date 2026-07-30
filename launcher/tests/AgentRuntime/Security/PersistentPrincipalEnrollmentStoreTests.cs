using System;
using System.IO;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Transport;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Security
{
    public sealed class PersistentPrincipalEnrollmentStoreTests
        : IDisposable
    {
        private readonly string _root = Path.Combine(
            Path.GetTempPath(),
            "cf7-enrollment-tests",
            Guid.NewGuid().ToString("N"));
        private readonly ManualAgentRuntimeClock _clock =
            new ManualAgentRuntimeClock();

        [Fact]
        public void StoredProofAuthenticatesOnlyExactClientAndScope()
        {
            var store = CreateStore();
            DeveloperEnrollment enrollment =
                store.IssueOrRotate(
                    ClientId,
                    new[]
                    {
                        AgentCapabilitiesV1.ListWindows,
                        AgentCapabilitiesV1.GetWindow
                    },
                    new[] { TargetId },
                    TimeSpan.FromHours(1));

            Assert.True(
                store.TryAuthenticate(
                    ClientId,
                    enrollment.CredentialProof,
                    new[] { AgentCapabilitiesV1.GetWindow },
                    out var evidence,
                    out var reason),
                reason);
            Assert.Equal(
                enrollment.EnrollmentReceipt,
                evidence.EnrollmentReceipt);
            Assert.False(
                store.TryAuthenticate(
                    ClientId,
                    enrollment.CredentialProof,
                    new[] { AgentCapabilitiesV1.Click },
                    out _,
                    out reason));
            Assert.Equal("capability_denied", reason);
            Assert.False(
                store.TryAuthenticate(
                    OtherClientId,
                    enrollment.CredentialProof,
                    new[] { AgentCapabilitiesV1.GetWindow },
                    out _,
                    out reason));
            Assert.Equal("authentication_failed", reason);
        }

        [Fact]
        public void RotationAndRevocationInvalidateOldProof()
        {
            var store = CreateStore();
            DeveloperEnrollment first =
                store.IssueOrRotate(
                    ClientId,
                    new[] { AgentCapabilitiesV1.GetWindow },
                    new[] { TargetId },
                    TimeSpan.FromHours(1));
            DeveloperEnrollment second =
                store.IssueOrRotate(
                    ClientId,
                    new[] { AgentCapabilitiesV1.GetWindow },
                    new[] { TargetId },
                    TimeSpan.FromHours(1));

            Assert.False(
                store.TryAuthenticate(
                    ClientId,
                    first.CredentialProof,
                    new[] { AgentCapabilitiesV1.GetWindow },
                    out _,
                    out var oldReason));
            Assert.Equal("authentication_failed", oldReason);
            Assert.True(
                store.TryAuthenticate(
                    ClientId,
                    second.CredentialProof,
                    new[] { AgentCapabilitiesV1.GetWindow },
                    out _,
                    out _));
            Assert.True(store.Revoke(ClientId));
            Assert.False(
                store.TryAuthenticate(
                    ClientId,
                    second.CredentialProof,
                    new[] { AgentCapabilitiesV1.GetWindow },
                    out _,
                    out var revokedReason));
            Assert.Equal(
                "authentication_failed",
                revokedReason);
        }

        [Fact]
        public void HostVerifierConsumesTrustedPlayerReceiptOnce()
        {
            var store = CreateStore();
            var verifier =
                new HostPrincipalEnrollmentVerifier(store);
            var evidence = new PlayerAssistCredentialEvidence
            {
                ClientInstanceId = ClientId,
                ConsentReceipt =
                    "consent_aaaaaaaaaaaaaaaaaaaa",
                SelectedSessionId =
                    "session_aaaaaaaaaaaaaaaaaaaa",
                AllowedCapabilities = new[]
                {
                    AgentCapabilitiesV1.GetWindow
                },
                AllowedTargets = new[] { TargetId }
            };
            verifier.RegisterPlayerConsent(evidence);

            Assert.True(
                verifier.TryVerifyPlayerAssist(
                    evidence,
                    out var authorization,
                    out var reason),
                reason);
            Assert.Contains(
                AgentCapabilitiesV1.GetWindow,
                authorization.AllowedCapabilities);
            Assert.False(
                verifier.TryVerifyPlayerAssist(
                    evidence,
                    out _,
                    out reason));
            Assert.Equal(
                "player_consent_evidence_invalid",
                reason);
        }

        private PersistentDeveloperEnrollmentStore CreateStore()
        {
            return new PersistentDeveloperEnrollmentStore(
                _root,
                _clock,
                Path.Combine(_root, "credentials"),
                new NoOpProtection());
        }

        public void Dispose()
        {
            if (Directory.Exists(_root))
                Directory.Delete(_root, true);
        }

        private sealed class NoOpProtection
            : IAgentRendezvousFileProtection
        {
            public void ProtectDirectory(string path)
            {
            }

            public void ProtectFile(string path)
            {
            }
        }

        private const string ClientId =
            "client_enrollment_aaaaaaaa";
        private const string OtherClientId =
            "client_enrollment_bbbbbbbb";
        private const string TargetId =
            "target_enrollment_aaaaaaaa";
    }
}
