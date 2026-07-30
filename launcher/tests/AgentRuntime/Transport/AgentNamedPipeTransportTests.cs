using System;
using System.Diagnostics;
using System.IO.Pipes;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Transport;
using Microsoft.Win32.SafeHandles;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Transport
{
    public sealed class AgentNamedPipeTransportTests
    {
        private static readonly AgentProcessSecurityIdentity ServerIdentity =
            new AgentProcessSecurityIdentity(
                100,
                DateTimeOffset.Parse("2026-07-30T01:02:03Z"),
                4,
                AgentElevationType.Limited,
                "S-1-5-21-1000");

        [Fact]
        public void PeerVerifier_AcceptsOnlyOsObservedLocalMatchingIdentity()
        {
            var probe = CreateMatchingProbe();
            var verifier = new AgentPipePeerVerifier(
                probe,
                ServerIdentity);
            using var handle = new SafePipeHandle(new IntPtr(123), false);

            AgentPipePeerVerificationResult result = verifier.Verify(handle);

            Assert.True(result.Accepted);
            Assert.Equal("accepted", result.ReasonCode);
            Assert.Equal(200u, result.PeerIdentity.ProcessId);
            Assert.Equal(
                DateTimeOffset.Parse("2026-07-30T02:03:04Z"),
                result.PeerIdentity.ProcessStartTimeUtc);
        }

        [Theory]
        [InlineData("remote", "remote_client_rejected")]
        [InlineData("pid-unavailable", "peer_process_unverifiable")]
        [InlineData("process-stale", "peer_process_stale")]
        [InlineData("user", "peer_user_mismatch")]
        [InlineData("session", "peer_session_mismatch")]
        [InlineData("elevation", "peer_elevation_mismatch")]
        [InlineData("elevation-unknown", "peer_elevation_unverifiable")]
        public void PeerVerifier_FailsClosedOnIdentityMismatch(
            string mutation,
            string expectedReason)
        {
            FakePeerProbe probe = CreateMatchingProbe();
            switch (mutation)
            {
                case "remote":
                    probe.ComputerName = "OTHER-PC";
                    break;
                case "pid-unavailable":
                    probe.ProvideProcessId = false;
                    break;
                case "process-stale":
                    probe.ProvideIdentity = false;
                    break;
                case "user":
                    probe.Identity = Identity(
                        sessionId: 4,
                        elevation: AgentElevationType.Limited,
                        sid: "S-1-5-21-OTHER");
                    break;
                case "session":
                    probe.Identity = Identity(
                        sessionId: 5,
                        elevation: AgentElevationType.Limited);
                    break;
                case "elevation":
                    probe.Identity = Identity(
                        sessionId: 4,
                        elevation: AgentElevationType.Full);
                    break;
                case "elevation-unknown":
                    probe.Identity = Identity(
                        sessionId: 4,
                        elevation: AgentElevationType.Unknown);
                    break;
            }

            var verifier = new AgentPipePeerVerifier(probe, ServerIdentity);
            using var handle = new SafePipeHandle(new IntPtr(123), false);

            AgentPipePeerVerificationResult result = verifier.Verify(handle);

            Assert.False(result.Accepted);
            Assert.Equal(expectedReason, result.ReasonCode);
            Assert.Null(result.PeerIdentity);
        }

        [Fact]
        public void Factory_FreezesCurrentUserAndPreProtocolRemoteRejection()
        {
            string pipeId = AgentRendezvousStore.GenerateOpaqueId();
            using AgentPendingPipeServer pending =
                new AgentNamedPipeServerFactory().Create(pipeId);

            Assert.Equal(
                AgentNamedPipeServerFactory.PipeNamePrefix + pipeId,
                pending.PipeName);
            Assert.True(pending.SecurityContract.CurrentUserOnly);
            Assert.True(pending.SecurityContract.RejectRemoteBeforeProtocol);
            Assert.True(pending.SecurityContract.RequireSameWindowsSession);
            Assert.True(pending.SecurityContract.RequireSameElevationType);
            Assert.Throws<ArgumentException>(
                () => new AgentNamedPipeServerFactory().Create(
                    @"..\arbitrary-path"));
        }

        [Fact]
        public async Task Factory_RejectsPeerBeforeReturningProtocolStream()
        {
            string pipeId = AgentRendezvousStore.GenerateOpaqueId();
            using AgentPendingPipeServer pending =
                new AgentNamedPipeServerFactory().Create(pipeId);
            using var client = new NamedPipeClientStream(
                ".",
                pending.PipeName,
                PipeDirection.InOut,
                PipeOptions.Asynchronous);
            using var timeout = new CancellationTokenSource(
                TimeSpan.FromSeconds(5));

            Task<AgentVerifiedPipeConnection> accepting =
                pending.AcceptVerifiedAsync(
                    new AlwaysRejectVerifier(),
                    timeout.Token);
            await client.ConnectAsync(timeout.Token);

            AgentPipePeerRejectedException rejection =
                await Assert.ThrowsAsync<AgentPipePeerRejectedException>(
                    () => accepting);
            Assert.Equal("remote_client_rejected", rejection.ReasonCode);
        }

        [Fact]
        public async Task WindowsProbe_VerifiesAnActualLocalSameProcessClient()
        {
            Assert.True(
                WindowsAgentPipePeerProbe.TryGetCurrentProcessIdentity(
                    out AgentProcessSecurityIdentity serverIdentity));
            var probe = new WindowsAgentPipePeerProbe();
            var verifier = new AgentPipePeerVerifier(
                probe,
                serverIdentity);
            string pipeId = AgentRendezvousStore.GenerateOpaqueId();
            await using AgentPendingPipeServer pending =
                new AgentNamedPipeServerFactory().Create(pipeId);
            await using var client = new NamedPipeClientStream(
                ".",
                pending.PipeName,
                PipeDirection.InOut,
                PipeOptions.Asynchronous);
            using var timeout = new CancellationTokenSource(
                TimeSpan.FromSeconds(5));

            Task<AgentVerifiedPipeConnection> accepting =
                pending.AcceptVerifiedAsync(verifier, timeout.Token);
            await client.ConnectAsync(timeout.Token);
            AgentVerifiedPipeConnection connection = await accepting;
            await using (connection)
            {

                Assert.Equal(
                    checked((uint)Process.GetCurrentProcess().Id),
                    connection.PeerIdentity.ProcessId);
                Assert.True(client.IsConnected);
            }
        }

        [Theory]
        [InlineData(@"\\machine")]
        [InlineData("machine")]
        [InlineData("MACHINE")]
        [InlineData(".")]
        public void LocalComputerComparison_NormalizesExpectedForms(
            string observed)
        {
            Assert.True(
                AgentPipePeerVerifier.IsLocalComputerName(
                    observed,
                    "machine"));
        }

        private static FakePeerProbe CreateMatchingProbe()
        {
            return new FakePeerProbe
            {
                LocalName = "CF7-PC",
                ComputerName = @"\\CF7-PC",
                ProcessId = 200,
                Identity = Identity(
                    sessionId: 4,
                    elevation: AgentElevationType.Limited)
            };
        }

        private static AgentProcessSecurityIdentity Identity(
            uint sessionId,
            AgentElevationType elevation,
            string sid = "S-1-5-21-1000")
        {
            return new AgentProcessSecurityIdentity(
                200,
                DateTimeOffset.Parse("2026-07-30T02:03:04Z"),
                sessionId,
                elevation,
                sid);
        }

        private sealed class FakePeerProbe : IAgentPipePeerProbe
        {
            public string LocalName;
            public string ComputerName;
            public uint ProcessId;
            public AgentProcessSecurityIdentity Identity;
            public bool ProvideComputerName = true;
            public bool ProvideProcessId = true;
            public bool ProvideIdentity = true;

            public string LocalComputerName { get { return LocalName; } }

            public bool TryGetClientComputerName(
                SafePipeHandle pipeHandle,
                out string computerName)
            {
                computerName = ComputerName;
                return ProvideComputerName;
            }

            public bool TryGetClientProcessId(
                SafePipeHandle pipeHandle,
                out uint processId)
            {
                processId = ProcessId;
                return ProvideProcessId;
            }

            public bool TryGetProcessIdentity(
                uint processId,
                out AgentProcessSecurityIdentity identity)
            {
                identity = Identity;
                return ProvideIdentity;
            }
        }

        private sealed class AlwaysRejectVerifier : IAgentPipePeerVerifier
        {
            public AgentPipePeerVerificationResult Verify(
                SafePipeHandle pipeHandle)
            {
                return AgentPipePeerVerificationResult.Reject(
                    "remote_client_rejected");
            }
        }
    }
}
