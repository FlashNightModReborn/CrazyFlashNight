using System;
using CF7Launcher.AgentRuntime.Security;
using Xunit;
using SessionMode =
    CF7Launcher.AgentRuntime.Contracts.SessionMode;

namespace CF7Launcher.Tests.AgentRuntime.Security
{
    public sealed class ObservationGrantBrokerTests
    {
        [Fact]
        public void Issue_RejectsHumanOnlySecuritySurfaceEvenWithWideCredential()
        {
            var setup = CreatePlayerSetup();
            setup.Targets.Set(
                "session-a",
                "consent-ui",
                AgentTargetSafetyKind.HumanOnlySecuritySurface);

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Issue(
                        Request(
                            setup.Credential,
                            new ObservationTargetScope
                            {
                                TargetId = "consent-ui"
                            })));

            Assert.Equal(
                "human_only_security_surface",
                error.Message);
        }

        [Fact]
        public void TryAuthorize_RevokesWhenHostReclassifiesTargetAsHumanOnly()
        {
            var setup = CreatePlayerSetup();
            ObservationGrant grant = setup.Broker.Issue(
                Request(
                    setup.Credential,
                    new ObservationTargetScope
                    {
                        TargetId = "flash-a"
                    }));

            setup.Targets.Set(
                "session-a",
                "flash-a",
                AgentTargetSafetyKind.HumanOnlySecuritySurface);

            Assert.False(setup.Broker.TryAuthorize(
                grant.ObservationGrantId,
                "wings-client",
                setup.Credential.SecurityPrincipalId,
                "session-a",
                "flash-a",
                "pixels",
                out _,
                out string reason));
            Assert.Equal("human_only_security_surface", reason);
            Assert.Equal(ObservationGrantState.Revoked, grant.State);
        }

        [Fact]
        public void Grant_IsIndependentScopedAndExpiresMonotonically()
        {
            var setup = CreatePlayerSetup();
            ObservationGrant grant = setup.Broker.Issue(
                Request(
                    setup.Credential,
                    new ObservationTargetScope
                    {
                        TargetId = "flash-a"
                    }));

            Assert.True(setup.Broker.TryAuthorize(
                grant.ObservationGrantId,
                "wings-client",
                setup.Credential.SecurityPrincipalId,
                "session-a",
                "flash-a",
                "pixels",
                out _,
                out _));
            Assert.False(setup.Broker.TryAuthorize(
                grant.ObservationGrantId,
                "other-client",
                setup.Credential.SecurityPrincipalId,
                "session-a",
                "flash-a",
                "pixels",
                out _,
                out string ownerReason));
            Assert.Equal(
                "observation_grant_owner_mismatch",
                ownerReason);

            setup.Clock.Advance(TimeSpan.FromMinutes(6));

            Assert.False(setup.Broker.TryAuthorize(
                grant.ObservationGrantId,
                "wings-client",
                setup.Credential.SecurityPrincipalId,
                "session-a",
                "flash-a",
                "pixels",
                out _,
                out string expiryReason));
            Assert.Equal(
                "observation_grant_expired",
                expiryReason);
        }

        [Fact]
        public void PersistenceAndExportRequireSeparateCapabilities()
        {
            var setup = CreatePlayerSetup();
            ObservationGrantRequest request = Request(
                setup.Credential,
                new ObservationTargetScope
                {
                    TargetId = "flash-a"
                });
            request = new ObservationGrantRequest
            {
                CredentialId = request.CredentialId,
                ClientInstanceId = request.ClientInstanceId,
                SessionId = request.SessionId,
                Targets = request.Targets,
                DataScopes = request.DataScopes,
                ConsentReceipt = request.ConsentReceipt,
                AllowPersistence = true
            };

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Issue(request));

            Assert.Equal("retention_grant_required", error.Message);
        }

        [Fact]
        public void Issue_RejectsDataScopeOutsideFrozenV1Registry()
        {
            var setup = CreatePlayerSetup();
            ObservationGrantRequest request = Request(
                setup.Credential,
                new ObservationTargetScope
                {
                    TargetId = "flash-a"
                });
            request = new ObservationGrantRequest
            {
                CredentialId = request.CredentialId,
                ClientInstanceId = request.ClientInstanceId,
                SessionId = request.SessionId,
                Targets = request.Targets,
                DataScopes = new[] { "frame" },
                ConsentReceipt = request.ConsentReceipt
            };

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Issue(request));

            Assert.Equal("data_scope_denied", error.Message);
        }

        [Fact]
        public void PlayerGrantRequiresExactTrustedIssuerReceipt()
        {
            var setup = CreatePlayerSetup();
            ObservationGrantRequest forged = Request(
                setup.Credential,
                new ObservationTargetScope
                {
                    TargetId = "flash-a"
                });
            forged = new ObservationGrantRequest
            {
                CredentialId = forged.CredentialId,
                ClientInstanceId =
                    forged.ClientInstanceId,
                SessionId = forged.SessionId,
                Targets = forged.Targets,
                DataScopes = forged.DataScopes,
                RequestedLifetime =
                    forged.RequestedLifetime,
                ConsentReceipt =
                    "forged-player-consent",
                AllowEphemeralKeyframes = true
            };

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Issue(forged));
            Assert.Equal(
                "observation_consent_invalid",
                error.Message);

            ObservationGrant legitimate =
                setup.Broker.Issue(
                    Request(
                        setup.Credential,
                        new ObservationTargetScope
                        {
                            TargetId = "flash-a"
                        }));
            Assert.Equal(
                setup.Credential.IssuerReceipt,
                legitimate.ConsentReceipt);
        }

        [Fact]
        public void
            PlayerGrantRejectsCrossSessionAndExpiredCredential()
        {
            var setup = CreatePlayerSetup();
            setup.Targets.Set(
                "session-b",
                "flash-b");
            ObservationGrantRequest crossSession =
                Request(
                    setup.Credential,
                    new ObservationTargetScope
                    {
                        TargetId = "flash-b"
                    });
            crossSession = new ObservationGrantRequest
            {
                CredentialId =
                    crossSession.CredentialId,
                ClientInstanceId =
                    crossSession.ClientInstanceId,
                SessionId = "session-b",
                Targets = crossSession.Targets,
                DataScopes = crossSession.DataScopes,
                RequestedLifetime =
                    crossSession.RequestedLifetime,
                ConsentReceipt =
                    setup.Credential.IssuerReceipt
            };
            InvalidOperationException sessionError =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Issue(
                        crossSession));
            Assert.Equal(
                "session_scope_mismatch",
                sessionError.Message);

            setup.Clock.Advance(
                TimeSpan.FromMinutes(16));
            InvalidOperationException expired =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Issue(
                        Request(
                            setup.Credential,
                            new ObservationTargetScope
                            {
                                TargetId = "flash-a"
                            })));
            Assert.Equal(
                "credential_expired",
                expired.Message);
        }

        [Fact]
        public void
            UnattendedSessionRejectsNewAndPreviouslyIssuedWingsGrant()
        {
            var setup = CreatePlayerSetup();
            ObservationGrant existing = setup.Broker.Issue(
                Request(
                    setup.Credential,
                    new ObservationTargetScope
                    {
                        TargetId = "flash-a"
                    }));

            setup.Targets.SetSessionMode(
                "session-a",
                SessionMode.UnattendedTest);

            Assert.False(setup.Broker.TryAuthorize(
                existing.ObservationGrantId,
                "wings-client",
                setup.Credential.SecurityPrincipalId,
                "session-a",
                "flash-a",
                "pixels",
                out _,
                out string authorizeReason));
            Assert.Equal("session_mismatch", authorizeReason);
            Assert.Equal(
                ObservationGrantState.Revoked,
                existing.State);

            InvalidOperationException issueError =
                Assert.Throws<InvalidOperationException>(
                    () => setup.Broker.Issue(
                        Request(
                            setup.Credential,
                            new ObservationTargetScope
                            {
                                TargetId = "flash-a"
                            })));
            Assert.Equal("session_mismatch", issueError.Message);
        }

        private static ObservationGrantRequest Request(
            PrincipalCredential credential,
            ObservationTargetScope target)
        {
            return new ObservationGrantRequest
            {
                CredentialId = credential.CredentialId,
                ClientInstanceId = "wings-client",
                SessionId = "session-a",
                Targets = new[] { target },
                DataScopes = new[] { "pixels" },
                RequestedLifetime = TimeSpan.FromMinutes(10),
                ConsentReceipt =
                    credential.IssuerReceipt,
                AllowEphemeralKeyframes = true
            };
        }

        private static (
            ManualAgentRuntimeClock Clock,
            PrincipalCredential Credential,
            MutableAgentTargetAuthority Targets,
            ObservationGrantBroker Broker) CreatePlayerSetup()
        {
            var clock = new ManualAgentRuntimeClock();
            var authority = new PrincipalCredentialAuthority(
                clock,
                new TestPrincipalEnrollmentVerifier());
            var targets = new MutableAgentTargetAuthority();
            targets.Set("session-a", "flash-a");
            PrincipalCredential credential =
                authority.IssuePlayerAssist(
                    new PlayerAssistCredentialEvidence
                    {
                        ClientInstanceId = "wings-client",
                        ConsentReceipt = "enrollment-consent",
                        SelectedSessionId = "session-a",
                        AllowedCapabilities = new[]
                        {
                            "observe:pixels"
                        },
                        AllowedTargets = new[] { "*" }
                    });
            return (
                clock,
                credential,
                targets,
                new ObservationGrantBroker(
                    clock,
                    authority,
                    targets));
        }
    }
}
