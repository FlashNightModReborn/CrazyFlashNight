using System;
using System.Diagnostics;
using System.IO;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Transport;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class
        LauncherUnattendedCredentialBootstrapTests
    {
        private const string ClientId =
            "client_unattended_host_AAAA";
        private const string Slot =
            "cf7_agent_equipment_tuning";
        private const string AttemptId =
            "attempt_unattended_host_AAA";
        private const string SessionId =
            "session_unattended_host_AAA";
        private const string TargetId =
            "target_unattended_host_AAAA";
        private const string Nonce =
            "nonce_unattended_host_AAAAA";
        private static readonly string Build =
            new string('a', 64);
        private static readonly string Payload =
            new string('b', 64);
        private static readonly string RunnerExecutableHash =
            new string('d', 64);
        private static readonly DateTimeOffset RunnerStart =
            new DateTimeOffset(
                2026,
                7,
                30,
                0,
                0,
                0,
                TimeSpan.Zero);

        [Fact]
        public void PublishedEvidenceRejectsEveryRunnerAndAttemptDrift()
        {
            UnattendedCredentialEvidence published =
                Evidence();
            UnattendedCredentialEvidence[] mismatches =
            {
                Evidence(
                    attemptId:
                        "attempt_unattended_host_BBB"),
                Evidence(attemptGeneration: 8),
                Evidence(
                    slot:
                        "cf7_agent_character_build"),
                Evidence(
                    canonicalSavePath:
                        @"C:\arbitrary\save.json"),
                Evidence(
                    buildIdentity:
                        new string('e', 64)),
                Evidence(
                    payloadClosure:
                        new string('f', 64)),
                Evidence(runnerProcessId: 4321),
                Evidence(runnerStartTickDelta: 1),
                Evidence(
                    runnerExecutablePath:
                        @"C:\runtime\other.exe"),
                Evidence(
                    runnerExecutableSha256:
                        new string('1', 64)),
                Evidence(runnerExecutableSize: 2),
                Evidence(
                    runtimeExecutablePath:
                        @"C:\arbitrary\Core.exe"),
                Evidence(
                    requestNonce:
                        "nonce_unattended_host_BBBBB"),
                Evidence(
                    allowedTargets:
                        new[]
                        {
                            "target_unattended_host_BBBB"
                        })
            };

            Assert.True(
                LauncherUnattendedCredentialBootstrap
                    .EvidenceMatchesPublished(
                        published,
                        published));
            Assert.All(
                mismatches,
                mismatch => Assert.False(
                    LauncherUnattendedCredentialBootstrap
                        .EvidenceMatchesPublished(
                            mismatch,
                            published)));
        }

        [Fact]
        public void PipePeerMustBeTheLiveExactRunnerIncarnation()
        {
            using Process process =
                Process.GetCurrentProcess();
            process.Refresh();
            string path = Path.GetFullPath(
                Environment.ProcessPath);
            DateTimeOffset start =
                process.StartTime.ToUniversalTime();
            UnattendedCredentialEvidence evidence =
                Evidence(
                    runnerProcessId:
                        checked((uint)process.Id),
                    runnerStart: start,
                    runnerExecutablePath: path);
            AgentProcessSecurityIdentity exact =
                Peer(
                    evidence.RunnerProcessId,
                    evidence.RunnerProcessStartTimeUtc,
                    evidence.RunnerExecutablePath,
                    evidence.RunnerExecutableSha256);

            Assert.True(
                LauncherUnattendedCredentialBootstrap
                    .PeerMatchesEvidence(
                        exact,
                        evidence));
            Assert.False(
                LauncherUnattendedCredentialBootstrap
                    .PeerMatchesEvidence(
                        Peer(
                            evidence.RunnerProcessId,
                            evidence
                                .RunnerProcessStartTimeUtc
                                .AddTicks(1),
                            evidence.RunnerExecutablePath,
                            evidence.RunnerExecutableSha256),
                        evidence));
            Assert.False(
                LauncherUnattendedCredentialBootstrap
                    .PeerMatchesEvidence(
                        Peer(
                            evidence.RunnerProcessId,
                            evidence.RunnerProcessStartTimeUtc,
                            @"C:\runtime\other.exe",
                            evidence.RunnerExecutableSha256),
                        evidence));
        }

        [Fact]
        public void GuardianMustBeDirectChildOfExactRequestedRunner()
        {
            Assert.True(
                LauncherUnattendedCredentialBootstrap
                    .DirectParentMatchesRunner(
                        1234,
                        () => 1234));
            Assert.False(
                LauncherUnattendedCredentialBootstrap
                    .DirectParentMatchesRunner(
                        1234,
                        () => 4321));
            Assert.False(
                LauncherUnattendedCredentialBootstrap
                    .DirectParentMatchesRunner(
                        1234,
                        () => throw new InvalidOperationException()));
        }

        private static UnattendedCredentialEvidence
            Evidence(
                string attemptId = AttemptId,
                ulong attemptGeneration = 7,
                string slot = Slot,
                string canonicalSavePath =
                    @"C:\game\saves\cf7_agent_equipment_tuning.json",
                string buildIdentity = null,
                string payloadClosure = null,
                uint runnerProcessId = 1234,
                DateTimeOffset? runnerStart = null,
                long runnerStartTickDelta = 0,
                string runnerExecutablePath =
                    @"C:\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe",
                string runnerExecutableSha256 = null,
                long runnerExecutableSize = 1024,
                string runtimeExecutablePath =
                    @"C:\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe",
                string requestNonce = Nonce,
                string[] allowedTargets = null)
        {
            return new UnattendedCredentialEvidence
            {
                ClientInstanceId = ClientId,
                RunnerPolicyId =
                    "cf7_trusted_core_unattended_runner_v2",
                RunnerProcessId = runnerProcessId,
                RunnerProcessStartTimeUtc =
                    (runnerStart ?? RunnerStart)
                    .AddTicks(
                        runnerStartTickDelta),
                RunnerExecutablePath =
                    runnerExecutablePath,
                RunnerExecutableSha256 =
                    runnerExecutableSha256
                    ?? RunnerExecutableHash,
                RunnerExecutableSize =
                    runnerExecutableSize,
                RuntimeExecutablePath =
                    runtimeExecutablePath,
                RequestNonce = requestNonce,
                BuildIdentity =
                    buildIdentity ?? Build,
                PayloadClosure =
                    payloadClosure ?? Payload,
                SessionId = SessionId,
                AttemptId = attemptId,
                AttemptGeneration =
                    attemptGeneration,
                Slot = slot,
                CanonicalSavePath =
                    canonicalSavePath,
                RunnerDeadlineMonotonic =
                    300_000,
                AllowedCapabilities = new[]
                {
                    AgentCapabilitiesV1
                        .SessionStatus
                },
                AllowedTargets =
                    allowedTargets
                    ?? new[] { TargetId }
            };
        }

        private static AgentProcessSecurityIdentity Peer(
            uint processId,
            DateTimeOffset processStart,
            string executablePath,
            string executableSha256)
        {
            return new AgentProcessSecurityIdentity(
                processId,
                processStart,
                1,
                AgentElevationType.Default,
                "S-1-5-21-test",
                executablePath,
                executableSha256);
        }
    }
}
