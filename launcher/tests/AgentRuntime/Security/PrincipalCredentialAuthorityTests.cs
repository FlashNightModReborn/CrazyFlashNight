using System;
using System.Collections.Generic;
using System.Linq;
using CF7Launcher.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Security
{
    public sealed class PrincipalCredentialAuthorityTests
    {
        [Fact]
        public void OpaqueIds_UseCsprngSizedBase64UrlValues()
        {
            string[] ids = Enumerable.Range(0, 2048)
                .Select(_ => OpaqueIdGenerator.Create("lease"))
                .ToArray();

            Assert.Equal(ids.Length, ids.Distinct().Count());
            Assert.All(
                ids,
                id => Assert.Matches(
                    "^lease_[A-Za-z0-9_-]{24}$",
                    id));
        }

        [Fact]
        public void DeveloperIssuer_RequiresNeutralEnrollment()
        {
            var verifier = new TestPrincipalEnrollmentVerifier
            {
                AcceptDeveloper = false
            };
            var authority = new PrincipalCredentialAuthority(
                new ManualAgentRuntimeClock(),
                verifier);

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => authority.IssueDeveloper(
                        new DeveloperEnrollmentEvidence
                        {
                            ClientInstanceId = "client-a",
                            EnrollmentReceipt = "client-self-report",
                            AllowedCapabilities = new[] { "observe:pixels" },
                            AllowedTargets = new[] { "flash-a" }
                        }));

            Assert.Equal(
                "developer_enrollment_evidence_invalid",
                error.Message);
        }

        [Fact]
        public void UnattendedIssuer_RequiresImmutableExactAgentSlotBinding()
        {
            var authority = new PrincipalCredentialAuthority(
                new ManualAgentRuntimeClock(),
                new TestPrincipalEnrollmentVerifier());

            Assert.Throws<InvalidOperationException>(
                () => authority.IssueUnattended(
                    new UnattendedCredentialEvidence
                    {
                        ClientInstanceId = "runner-a",
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
                            "nonce_unattended_authority_A",
                        BuildIdentity = "build-a",
                        PayloadClosure = "payload-a",
                        SessionId = "session-a",
                        AttemptId = "attempt-a",
                        AttemptGeneration = 1,
                        Slot = "crazyflasher7_saves",
                        CanonicalSavePath =
                            @"C:\game\saves\crazyflasher7_saves.json",
                        RunnerDeadlineMonotonic = 10000
                    }));

            PrincipalCredential credential = authority.IssueUnattended(
                new UnattendedCredentialEvidence
                {
                    ClientInstanceId = "runner-a",
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
                        "nonce_unattended_authority_A",
                    BuildIdentity = "build-a",
                    PayloadClosure = "payload-a",
                    SessionId = "session-a",
                    AttemptId = "attempt-a",
                    AttemptGeneration = 1,
                    Slot = "cf7_agent_equipment_tuning",
                    CanonicalSavePath =
                        @"C:\game\saves\cf7_agent_equipment_tuning.json",
                    RunnerDeadlineMonotonic = 10000,
                    AllowedCapabilities = new[] { "input.click" },
                    AllowedTargets = new[] { "flash-a" }
                });

            Assert.Equal(
                AgentPrincipalKind.UnattendedTestRunner,
                credential.PrincipalKind);
            Assert.Equal("build-a", credential.BuildIdentity);
            Assert.Equal("attempt-a", credential.AttemptId);
        }

        [Fact]
        public void Rotation_PreservesOpaquePrincipalAndInvalidatesOldCredential()
        {
            var clock = new ManualAgentRuntimeClock();
            var authority = new PrincipalCredentialAuthority(
                clock,
                new TestPrincipalEnrollmentVerifier());
            PrincipalCredential original = IssueDeveloper(authority);

            PrincipalCredential rotated = authority.Rotate(
                original.CredentialId);

            Assert.Equal(
                original.SecurityPrincipalId,
                rotated.SecurityPrincipalId);
            Assert.Equal(2, rotated.Generation);
            Assert.NotEqual(original.CredentialId, rotated.CredentialId);
            Assert.False(authority.TryResolveActive(
                original.CredentialId,
                "client-a",
                out _,
                out string reason));
            Assert.Equal("credential_inactive", reason);
            Assert.True(authority.TryResolveActive(
                rotated.CredentialId,
                "client-a",
                out _,
                out _));
        }

        [Fact]
        public void Resolve_DoesNotPermitClientOwnerSubstitution()
        {
            var authority = new PrincipalCredentialAuthority(
                new ManualAgentRuntimeClock(),
                new TestPrincipalEnrollmentVerifier());
            PrincipalCredential credential = IssueDeveloper(authority);

            bool resolved = authority.TryResolveActive(
                credential.CredentialId,
                "client-b",
                out _,
                out string reason);

            Assert.False(resolved);
            Assert.Equal("credential_owner_mismatch", reason);
        }

        private static PrincipalCredential IssueDeveloper(
            PrincipalCredentialAuthority authority)
        {
            return authority.IssueDeveloper(
                new DeveloperEnrollmentEvidence
                {
                    ClientInstanceId = "client-a",
                    EnrollmentReceipt = "enrollment-a",
                    AllowedCapabilities = new[]
                    {
                        "observe:pixels",
                        "input.click"
                    },
                    AllowedTargets = new[] { "flash-a" },
                    RequestedLifetime = TimeSpan.FromHours(1)
                });
        }
    }
}
