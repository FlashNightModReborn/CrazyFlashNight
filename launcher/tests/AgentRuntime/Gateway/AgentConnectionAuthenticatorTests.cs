using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class AgentConnectionAuthenticatorTests
        : IDisposable
    {
        private readonly string _root = Path.Combine(
            Path.GetTempPath(),
            "cf7-connection-auth-tests",
            Guid.NewGuid().ToString("N"));
        private readonly ManualAgentRuntimeClock _clock =
            new ManualAgentRuntimeClock();

        [Theory]
        [InlineData(ClientKind.JsonlCli)]
        [InlineData(ClientKind.McpStdio)]
        public void DeveloperTransportsUsePersistentEnrollmentAndNarrowScope(
            ClientKind clientKind)
        {
            PersistentDeveloperEnrollmentStore store =
                CreateStore();
            DeveloperEnrollment enrollment =
                store.IssueOrRotate(
                    DeveloperClientId,
                    new[]
                    {
                        AgentCapabilitiesV1.GetWindow,
                        AgentCapabilitiesV1.ListWindows,
                        PixelsScopeCapability,
                        "observation.persist"
                    },
                    new[] { PrimaryTargetId },
                    TimeSpan.FromHours(1));
            using AgentConnectionAuthenticator authenticator =
                CreateAuthenticator(store);

            AgentConnectionAuthenticationResult result =
                authenticator.Authenticate(
                    Hello(
                        clientKind,
                        DeveloperClientId,
                        enrollment.CredentialProof,
                        AgentCapabilitiesV1.GetWindow));

            Assert.True(result.Success, result.ReasonCode);
            Assert.Null(result.ReasonCode);
            Assert.Equal(
                AgentPrincipalKind.DeveloperAgent,
                result.Principal.PrincipalKind);
            Assert.Equal(
                AgentSessionMode.DeveloperInteractive,
                result.Principal.SessionMode);
            Assert.Contains(
                AgentCapabilitiesV1.GetWindow,
                result.Principal.AllowedCapabilities);
            Assert.Contains(
                PixelsScopeCapability,
                result.Principal.AllowedCapabilities);
            Assert.Contains(
                "observation.persist",
                result.Principal.AllowedCapabilities);
            Assert.DoesNotContain(
                AgentCapabilitiesV1.ListWindows,
                result.Principal.AllowedCapabilities);
            Assert.DoesNotContain(
                "observe:"
                    + ObservationDataScopesV1.Focus,
                result.Principal.AllowedCapabilities);
            Assert.Equal(
                new[] { AgentCapabilitiesV1.GetWindow },
                result.GrantedCapabilities);
            Assert.Equal(
                new[] { PrimaryTargetId },
                result.Principal.AllowedTargets);
        }

        [Fact]
        public void HelloCannotRequestInternalSecurityScopeButEnrollmentRetainsIt()
        {
            PersistentDeveloperEnrollmentStore store =
                CreateStore();
            DeveloperEnrollment enrollment =
                store.IssueOrRotate(
                    DeveloperClientId,
                    new[]
                    {
                        AgentCapabilitiesV1.GetWindow,
                        PixelsScopeCapability
                    },
                    new[] { PrimaryTargetId },
                    TimeSpan.FromHours(1));
            using AgentConnectionAuthenticator authenticator =
                CreateAuthenticator(store);

            AgentConnectionAuthenticationResult expanded =
                authenticator.Authenticate(
                    Hello(
                        ClientKind.JsonlCli,
                        DeveloperClientId,
                        enrollment.CredentialProof,
                        PixelsScopeCapability));
            Assert.False(expanded.Success);
            Assert.Equal(
                "capability_denied",
                expanded.ReasonCode);

            AgentConnectionAuthenticationResult accepted =
                authenticator.Authenticate(
                    Hello(
                        ClientKind.JsonlCli,
                        DeveloperClientId,
                        enrollment.CredentialProof,
                        AgentCapabilitiesV1.GetWindow));
            Assert.True(accepted.Success, accepted.ReasonCode);
            Assert.Contains(
                PixelsScopeCapability,
                accepted.Principal.AllowedCapabilities);
            Assert.Equal(
                new[] { AgentCapabilitiesV1.GetWindow },
                accepted.GrantedCapabilities);
        }

        [Fact]
        public void DeveloperProofCannotEnterHostOnlyKinds()
        {
            PersistentDeveloperEnrollmentStore store =
                CreateStore();
            DeveloperEnrollment enrollment =
                store.IssueOrRotate(
                    DeveloperClientId,
                    new[] { AgentCapabilitiesV1.GetWindow },
                    new[] { PrimaryTargetId },
                    TimeSpan.FromHours(1));
            using AgentConnectionAuthenticator authenticator =
                CreateAuthenticator(store);

            foreach (ClientKind kind in new[]
            {
                ClientKind.TestHarness,
                ClientKind.WingsInternal
            })
            {
                AgentConnectionAuthenticationResult rejected =
                    authenticator.Authenticate(
                        Hello(
                            kind,
                            DeveloperClientId,
                            enrollment.CredentialProof,
                            AgentCapabilitiesV1.GetWindow));
                Assert.False(rejected.Success);
                Assert.Equal(
                    "authentication_failed",
                    rejected.ReasonCode);
                Assert.DoesNotContain(
                    enrollment.CredentialProof,
                    rejected.ReasonCode,
                    StringComparison.Ordinal);
            }
        }

        [Fact]
        public void UnattendedProofRejectsWrongKindIdProofAndReplay()
        {
            PersistentDeveloperEnrollmentStore store =
                CreateStore();
            using AgentConnectionAuthenticator authenticator =
                CreateAuthenticator(store);
            authenticator.RegisterUnattendedProof(
                RunnerProof,
                UnattendedEvidence(),
                "runner_receipt_gateway_AAAAAA");

            AssertRejected(
                authenticator.Authenticate(
                    Hello(
                        ClientKind.WingsInternal,
                        RunnerClientId,
                        RunnerProof,
                        AgentCapabilitiesV1.GetWindow)));
            AssertRejected(
                authenticator.Authenticate(
                    Hello(
                        ClientKind.TestHarness,
                        WrongClientId,
                        RunnerProof,
                        AgentCapabilitiesV1.GetWindow)));
            AssertRejected(
                authenticator.Authenticate(
                    Hello(
                        ClientKind.TestHarness,
                        RunnerClientId,
                        WrongRunnerProof,
                        AgentCapabilitiesV1.GetWindow)));

            AgentConnectionAuthenticationResult accepted =
                authenticator.Authenticate(
                    Hello(
                        ClientKind.TestHarness,
                        RunnerClientId,
                        RunnerProof,
                        AgentCapabilitiesV1.GetWindow));
            Assert.True(accepted.Success, accepted.ReasonCode);
            Assert.Equal(
                AgentPrincipalKind.UnattendedTestRunner,
                accepted.Principal.PrincipalKind);

            AssertRejected(
                authenticator.Authenticate(
                    Hello(
                        ClientKind.TestHarness,
                        RunnerClientId,
                        RunnerProof,
                        AgentCapabilitiesV1.GetWindow)));
        }

        [Fact]
        public void CapabilityDenialConsumesTheMatchedOneShotProof()
        {
            PersistentDeveloperEnrollmentStore store =
                CreateStore();
            using AgentConnectionAuthenticator authenticator =
                CreateAuthenticator(store);
            authenticator.RegisterUnattendedProof(
                RunnerProof,
                UnattendedEvidence(),
                "runner_receipt_gateway_BBBBBB");

            AgentConnectionAuthenticationResult expanded =
                authenticator.Authenticate(
                    Hello(
                        ClientKind.TestHarness,
                        RunnerClientId,
                        RunnerProof,
                        AgentCapabilitiesV1.SessionShutdown));
            Assert.False(expanded.Success);
            Assert.Equal(
                "capability_denied",
                expanded.ReasonCode);

            AgentConnectionAuthenticationResult narrowed =
                authenticator.Authenticate(
                    Hello(
                        ClientKind.TestHarness,
                        RunnerClientId,
                        RunnerProof,
                        AgentCapabilitiesV1.Click));
            Assert.False(narrowed.Success);
            Assert.Equal(
                "authentication_failed",
                narrowed.ReasonCode);
        }

        [Fact]
        public void RegistrationSnapshotsTargetsAgainstCallerMutation()
        {
            PersistentDeveloperEnrollmentStore store =
                CreateStore();
            using AgentConnectionAuthenticator authenticator =
                CreateAuthenticator(store);
            var targets = new List<string>
            {
                PrimaryTargetId
            };
            UnattendedCredentialEvidence basis =
                UnattendedEvidence();
            var evidence = new UnattendedCredentialEvidence
            {
                ClientInstanceId =
                    basis.ClientInstanceId,
                RunnerPolicyId = basis.RunnerPolicyId,
                RunnerProcessId = basis.RunnerProcessId,
                RunnerProcessStartTimeUtc =
                    basis.RunnerProcessStartTimeUtc,
                RunnerExecutablePath =
                    basis.RunnerExecutablePath,
                RunnerExecutableSha256 =
                    basis.RunnerExecutableSha256,
                RunnerExecutableSize =
                    basis.RunnerExecutableSize,
                RuntimeExecutablePath =
                    basis.RuntimeExecutablePath,
                RequestNonce = basis.RequestNonce,
                BuildIdentity = basis.BuildIdentity,
                PayloadClosure = basis.PayloadClosure,
                SessionId = basis.SessionId,
                AttemptId = basis.AttemptId,
                AttemptGeneration =
                    basis.AttemptGeneration,
                Slot = basis.Slot,
                CanonicalSavePath =
                    basis.CanonicalSavePath,
                RunnerDeadlineMonotonic =
                    basis.RunnerDeadlineMonotonic,
                AllowedCapabilities =
                    basis.AllowedCapabilities,
                AllowedTargets = targets
            };
            authenticator.RegisterUnattendedProof(
                RunnerProof,
                evidence,
                "runner_receipt_gateway_CCCCCC");

            targets.Add(ExpandedTargetId);

            AgentConnectionAuthenticationResult result =
                authenticator.Authenticate(
                    Hello(
                        ClientKind.TestHarness,
                        RunnerClientId,
                        RunnerProof,
                        AgentCapabilitiesV1.GetWindow));

            Assert.True(result.Success, result.ReasonCode);
            Assert.Equal(
                new[] { PrimaryTargetId },
                result.Principal.AllowedTargets);
            Assert.DoesNotContain(
                ExpandedTargetId,
                result.Principal.AllowedTargets);
        }

        [Fact]
        public void WingsConsumesOnlyHostRegisteredPlayerEvidenceOnce()
        {
            PersistentDeveloperEnrollmentStore store =
                CreateStore();
            using AgentConnectionAuthenticator authenticator =
                CreateAuthenticator(store);
            authenticator.RegisterPlayerProof(
                PlayerProof,
                PlayerEvidence());

            AgentConnectionAuthenticationResult wrongKind =
                authenticator.Authenticate(
                    Hello(
                        ClientKind.TestHarness,
                        PlayerClientId,
                        PlayerProof,
                        AgentCapabilitiesV1.GetWindow));
            AssertRejected(wrongKind);

            AgentConnectionAuthenticationResult accepted =
                authenticator.Authenticate(
                    Hello(
                        ClientKind.WingsInternal,
                        PlayerClientId,
                        PlayerProof,
                        AgentCapabilitiesV1.GetWindow));
            Assert.True(accepted.Success, accepted.ReasonCode);
            Assert.Equal(
                AgentPrincipalKind.WingsPersona,
                accepted.Principal.PrincipalKind);
            Assert.Equal(
                AgentSessionMode.PlayerAssist,
                accepted.Principal.SessionMode);
            Assert.Equal(
                SelectedSessionId,
                accepted.Principal.SelectedSessionId);
            Assert.Equal(
                new[] { PrimaryTargetId },
                accepted.Principal.AllowedTargets);
            Assert.Contains(
                WindowMetadataScopeCapability,
                accepted.Principal.AllowedCapabilities);
            Assert.Equal(
                new[] { AgentCapabilitiesV1.GetWindow },
                accepted.GrantedCapabilities);

            AssertRejected(
                authenticator.Authenticate(
                    Hello(
                        ClientKind.WingsInternal,
                        PlayerClientId,
                        PlayerProof,
                        AgentCapabilitiesV1.GetWindow)));
        }

        [Fact]
        public async Task ConcurrentReplayAllowsExactlyOneHostProofConsumer()
        {
            PersistentDeveloperEnrollmentStore store =
                CreateStore();
            using AgentConnectionAuthenticator authenticator =
                CreateAuthenticator(store);
            authenticator.RegisterUnattendedProof(
                RunnerProof,
                UnattendedEvidence(),
                "runner_receipt_gateway_DDDDDD");
            HelloMessage hello = Hello(
                ClientKind.TestHarness,
                RunnerClientId,
                RunnerProof,
                AgentCapabilitiesV1.GetWindow);

            Task<AgentConnectionAuthenticationResult>[] attempts =
                Enumerable.Range(0, 8)
                    .Select(_ => Task.Run(
                        () => authenticator.Authenticate(hello)))
                    .ToArray();
            AgentConnectionAuthenticationResult[] results =
                await Task.WhenAll(attempts);

            Assert.Equal(
                1,
                results.Count(result => result.Success));
            Assert.Equal(
                7,
                results.Count(result =>
                    !result.Success
                    && result.ReasonCode
                        == "authentication_failed"));
        }

        [Fact]
        public void FailedIssueConsumesTemporaryHostVerifierRegistration()
        {
            PersistentDeveloperEnrollmentStore store =
                CreateStore();
            var verifier =
                new HostPrincipalEnrollmentVerifier(store);
            var authority =
                new PrincipalCredentialAuthority(
                    _clock,
                    verifier);
            using var authenticator =
                new AgentConnectionAuthenticator(
                    store,
                    verifier,
                    authority,
                    new AllowingUnattendedBindingAuthority());
            UnattendedCredentialEvidence registered =
                UnattendedEvidence();
            authenticator.RegisterUnattendedProof(
                RunnerProof,
                registered,
                "runner_receipt_gateway_cleanup");
            _clock.Advance(TimeSpan.FromMinutes(1));

            AgentConnectionAuthenticationResult result =
                authenticator.Authenticate(
                    Hello(
                        ClientKind.TestHarness,
                        RunnerClientId,
                        RunnerProof,
                        AgentCapabilitiesV1.GetWindow));

            AssertRejected(result);
            var selected =
                new UnattendedCredentialEvidence
                {
                    ClientInstanceId =
                        registered.ClientInstanceId,
                    RunnerPolicyId =
                        registered.RunnerPolicyId,
                    RunnerProcessId =
                        registered.RunnerProcessId,
                    RunnerProcessStartTimeUtc =
                        registered.RunnerProcessStartTimeUtc,
                    RunnerExecutablePath =
                        registered.RunnerExecutablePath,
                    RunnerExecutableSha256 =
                        registered.RunnerExecutableSha256,
                    RunnerExecutableSize =
                        registered.RunnerExecutableSize,
                    RuntimeExecutablePath =
                        registered.RuntimeExecutablePath,
                    RequestNonce =
                        registered.RequestNonce,
                    BuildIdentity =
                        registered.BuildIdentity,
                    PayloadClosure =
                        registered.PayloadClosure,
                    SessionId =
                        registered.SessionId,
                    AttemptId = registered.AttemptId,
                    AttemptGeneration =
                        registered.AttemptGeneration,
                    Slot = registered.Slot,
                    CanonicalSavePath =
                        registered.CanonicalSavePath,
                    RunnerDeadlineMonotonic =
                        registered
                            .RunnerDeadlineMonotonic,
                    AllowedCapabilities = new[]
                    {
                        AgentCapabilitiesV1.GetWindow,
                        PixelsScopeCapability,
                        "observation.persist"
                    },
                    AllowedTargets =
                        registered.AllowedTargets
                };
            Assert.False(
                verifier.TryVerifyUnattended(
                    selected,
                    out _,
                    out string reasonCode));
            Assert.Equal(
                "unattended_allow_list_evidence_invalid",
                reasonCode);
        }

        [Fact]
        public void HostRegistrationRejectsWildcardTargets()
        {
            PersistentDeveloperEnrollmentStore store =
                CreateStore();
            using AgentConnectionAuthenticator authenticator =
                CreateAuthenticator(store);
            UnattendedCredentialEvidence evidence =
                UnattendedEvidence(new[] { "*" });

            Assert.Throws<ArgumentException>(
                () => authenticator
                    .RegisterUnattendedProof(
                        RunnerProof,
                        evidence,
                        "runner_receipt_gateway_EEEEEE"));
        }

        private AgentConnectionAuthenticator
            CreateAuthenticator(
                PersistentDeveloperEnrollmentStore store)
        {
            var verifier =
                new HostPrincipalEnrollmentVerifier(store);
            var authority =
                new PrincipalCredentialAuthority(
                    _clock,
                    verifier);
            return new AgentConnectionAuthenticator(
                store,
                verifier,
                authority,
                new AllowingUnattendedBindingAuthority());
        }

        private PersistentDeveloperEnrollmentStore CreateStore()
        {
            return new PersistentDeveloperEnrollmentStore(
                _root,
                _clock,
                Path.Combine(_root, "credentials"),
                new NoOpProtection());
        }

        private static HelloMessage Hello(
            ClientKind kind,
            string clientInstanceId,
            string proof,
            params string[] capabilities)
        {
            return new HelloMessage
            {
                ClientKind = kind,
                ClientInstanceId = clientInstanceId,
                CredentialProof = proof,
                RequestedCapabilities =
                    capabilities.ToList(),
                Nonce =
                    "nonce_gateway_auth_AAAAAAAAA",
                ConnectionToken =
                    "ticket_gateway_auth_AAAAAAAA"
            };
        }

        private static UnattendedCredentialEvidence
            UnattendedEvidence(
                IEnumerable<string> targets = null)
        {
            return new UnattendedCredentialEvidence
            {
                ClientInstanceId = RunnerClientId,
                RunnerPolicyId =
                    "cf7_trusted_core_unattended_runner_v2",
                RunnerProcessId = 1234,
                RunnerProcessStartTimeUtc =
                    new DateTimeOffset(
                        2026,
                        7,
                        30,
                        1,
                        2,
                        3,
                        TimeSpan.Zero),
                RunnerExecutablePath =
                    @"C:\game\runtime\Core.exe",
                RunnerExecutableSha256 =
                    new string('b', 64),
                RunnerExecutableSize = 1024,
                RuntimeExecutablePath =
                    @"C:\game\runtime\Core.exe",
                RequestNonce =
                    "nonce_gateway_unattended_AAA",
                BuildIdentity =
                    "build_gateway_AAAAAAAAAAAAA",
                PayloadClosure =
                    "payload_gateway_AAAAAAAAAAA",
                SessionId =
                    "session_gateway_AAAAAAAAAAA",
                AttemptId =
                    "attempt_gateway_AAAAAAAAAAA",
                AttemptGeneration = 7,
                Slot = "cf7_agent_gateway_auth",
                CanonicalSavePath =
                    @"C:\game\saves\cf7_agent_gateway_auth.json",
                RunnerDeadlineMonotonic = 60_000,
                AllowedCapabilities = new[]
                {
                    AgentCapabilitiesV1.GetWindow,
                    AgentCapabilitiesV1.Click,
                    PixelsScopeCapability,
                    "observation.persist"
                },
                AllowedTargets = (targets
                    ?? new[] { PrimaryTargetId })
                    .ToArray()
            };
        }

        private sealed class
            AllowingUnattendedBindingAuthority
            : IUnattendedCredentialBindingAuthority
        {
            public bool TryAuthorizeEvidence(
                UnattendedCredentialEvidence evidence,
                AgentProcessSecurityIdentity peerIdentity,
                out string reasonCode)
            {
                reasonCode = null;
                return true;
            }

            public void BindPrincipal(
                PrincipalCredential principal,
                UnattendedCredentialEvidence evidence)
            {
            }

            public bool IsPrincipalAuthorized(
                PrincipalCredential principal)
            {
                return true;
            }
        }

        private static PlayerAssistCredentialEvidence
            PlayerEvidence()
        {
            return new PlayerAssistCredentialEvidence
            {
                ClientInstanceId = PlayerClientId,
                ConsentReceipt =
                    "consent_gateway_AAAAAAAAAAAA",
                SelectedSessionId = SelectedSessionId,
                AllowedCapabilities = new[]
                {
                    AgentCapabilitiesV1.GetWindow,
                    AgentCapabilitiesV1.ListWindows,
                    WindowMetadataScopeCapability
                },
                AllowedTargets =
                    new[] { PrimaryTargetId },
                RequestedLifetime =
                    TimeSpan.FromMinutes(5)
            };
        }

        private static void AssertRejected(
            AgentConnectionAuthenticationResult result)
        {
            Assert.False(result.Success);
            Assert.Null(result.Principal);
            Assert.Empty(result.GrantedCapabilities);
            Assert.Equal(
                "authentication_failed",
                result.ReasonCode);
            Assert.DoesNotContain(
                RunnerProof,
                result.ReasonCode,
                StringComparison.Ordinal);
            Assert.DoesNotContain(
                PlayerProof,
                result.ReasonCode,
                StringComparison.Ordinal);
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

        private const string DeveloperClientId =
            "client_gateway_developer_AAAA";
        private const string RunnerClientId =
            "client_gateway_runner_AAAAAAA";
        private const string PlayerClientId =
            "client_gateway_player_AAAAAAA";
        private const string WrongClientId =
            "client_gateway_wrong_AAAAAAAAA";
        private const string PrimaryTargetId =
            "target_gateway_flash_AAAAAAAAA";
        private const string ExpandedTargetId =
            "target_gateway_expanded_AAAAAA";
        private const string SelectedSessionId =
            "session_gateway_player_AAAAAAA";
        private const string RunnerProof =
            "proof_gateway_runner_AAAAAAAAAA";
        private const string WrongRunnerProof =
            "proof_gateway_runner_BBBBBBBBBB";
        private const string PlayerProof =
            "proof_gateway_player_AAAAAAAAAA";
        private const string PixelsScopeCapability =
            "observe:" + ObservationDataScopesV1.Pixels;
        private const string WindowMetadataScopeCapability =
            "observe:"
            + ObservationDataScopesV1.WindowMetadata;
    }
}
