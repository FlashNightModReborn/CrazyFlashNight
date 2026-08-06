using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using CF7Launcher.Bus;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Bus
{
    public sealed class XmlSocketPeerAuthorityTests
    {
        [Fact]
        public void UnauthorizedPeerCannotReplaceOrDispatch()
        {
            var authority = new MutablePeerAuthority();
            var router = new MessageRouter();
            int dispatchCount = 0;
            router.RegisterSync(
                "authority_probe",
                delegate(JObject message)
                {
                    Interlocked.Increment(ref dispatchCount);
                    return "{\"ok\":true}";
                });

            using var server =
                new XmlSocketServer(router, authority);
            int readyCount = 0;
            int disconnectedCount = 0;
            server.OnClientReady +=
                delegate
                {
                    Interlocked.Increment(ref readyCount);
                };
            server.OnClientDisconnected +=
                delegate
                {
                    Interlocked.Increment(
                        ref disconnectedCount);
                };

            int port = ProbeFreePort();
            Assert.True(server.Start(port));
            using var authorized = new TcpClient();
            authorized.Connect(IPAddress.Loopback, port);
            Assert.True(
                SpinWait.SpinUntil(
                    delegate { return server.HasClient; },
                    TimeSpan.FromSeconds(2)));

            SendProbe(authorized);
            Assert.True(
                SpinWait.SpinUntil(
                    delegate
                    {
                        return Volatile.Read(
                                ref dispatchCount) == 1
                            && Volatile.Read(
                                ref readyCount) == 1;
                    },
                    TimeSpan.FromSeconds(2)));
            int authorizedGeneration =
                server.CurrentGeneration;

            authority.Allow = false;
            using (var unauthorized = new TcpClient())
            {
                unauthorized.Connect(
                    IPAddress.Loopback,
                    port);
                try
                {
                    SendProbe(unauthorized);
                }
                catch (IOException)
                {
                }
                catch (SocketException)
                {
                }
                catch (ObjectDisposedException)
                {
                }

                Assert.True(
                    SpinWait.SpinUntil(
                        delegate
                        {
                            return authority.AttemptCount >= 2;
                        },
                        TimeSpan.FromSeconds(2)));
            }

            Assert.Equal(
                authorizedGeneration,
                server.CurrentGeneration);
            Assert.True(server.HasClient);
            Assert.True(server.IsClientReady);
            Assert.Equal(
                1,
                Volatile.Read(ref readyCount));
            Assert.Equal(
                0,
                Volatile.Read(
                    ref disconnectedCount));
            Assert.Equal(
                1,
                Volatile.Read(ref dispatchCount));

            SendProbe(authorized);
            Assert.True(
                SpinWait.SpinUntil(
                    delegate
                    {
                        return Volatile.Read(
                            ref dispatchCount) == 2;
                    },
                    TimeSpan.FromSeconds(2)));
            Assert.Equal(
                authorizedGeneration,
                server.CurrentGeneration);
            Assert.Equal(
                1,
                Volatile.Read(ref readyCount));
            Assert.Equal(
                0,
                Volatile.Read(
                    ref disconnectedCount));
        }

        [Fact]
        public void ExactAuthorityRejectsPidReuseIdentity()
        {
            string flashPath =
                Path.GetFullPath("flash-player.exe");
            DateTimeOffset start =
                DateTimeOffset.UtcNow;
            var expected =
                new XmlSocketPeerProcessIdentity(
                    4123,
                    start,
                    flashPath);
            var resolver = new FakeOwnerResolver
            {
                ProcessId = expected.ProcessId
            };
            var probe = new FakeProcessProbe
            {
                Identity = expected
            };
            var authority =
                new ExactProcessXmlSocketPeerAuthority(
                    resolver,
                    probe);
            authority.SetExpectedForTests(expected);

            Assert.True(
                authority.TryAuthorize(
                    new TcpClient(),
                    out string acceptedReason),
                acceptedReason);

            probe.Identity =
                expected with
                {
                    StartTimeUtc =
                        start.AddMilliseconds(1)
                };

            Assert.False(
                authority.TryAuthorize(
                    new TcpClient(),
                    out string rejectedReason));
            Assert.Equal(
                "xml_socket_peer_identity_mismatch",
                rejectedReason);
        }

        [Fact]
        public void ExactAuthorityFailsClosedWithoutExpectedProcess()
        {
            var authority =
                new ExactProcessXmlSocketPeerAuthority(
                    new FakeOwnerResolver
                    {
                        ProcessId = 4123
                    },
                    new FakeProcessProbe
                    {
                        Identity =
                            new XmlSocketPeerProcessIdentity(
                                4123,
                                DateTimeOffset.UtcNow,
                                Path.GetFullPath(
                                    "flash-player.exe"))
                    });

            Assert.False(
                authority.TryAuthorize(
                    new TcpClient(),
                    out string reason));
            Assert.Equal(
                "xml_socket_expected_process_unavailable",
                reason);
        }

        [Fact]
        public void SetExpectedRejectsIdentityChangedAfterProcessCapture()
        {
            using Process process =
                Process.GetCurrentProcess();
            string flashPath =
                Path.GetFullPath("flash-player.exe");
            DateTimeOffset start =
                DateTimeOffset.UtcNow;
            var captured =
                new XmlSocketPeerProcessIdentity(
                    process.Id,
                    start,
                    flashPath);
            var authority =
                new ExactProcessXmlSocketPeerAuthority(
                    new FakeOwnerResolver
                    {
                        ProcessId = process.Id
                    },
                    new FakeProcessProbe
                    {
                        Identity =
                            captured with
                            {
                                StartTimeUtc =
                                    start.AddMilliseconds(1)
                            }
                    },
                    new FakeExpectedProcessProbe
                    {
                        Identity = captured
                    });

            Assert.False(
                authority.TrySetExpectedProcess(
                    process,
                    out string reason));
            Assert.Equal(
                "xml_socket_expected_process_unavailable",
                reason);
            Assert.False(
                authority.TryAuthorize(
                    new TcpClient(),
                    out string authorizationReason));
            Assert.Equal(
                "xml_socket_expected_process_unavailable",
                authorizationReason);
        }

        [Fact]
        public void SetExpectedRetriesTransientProcessIdentityCapture()
        {
            using Process process =
                Process.GetCurrentProcess();
            var identity =
                new XmlSocketPeerProcessIdentity(
                    process.Id,
                    new DateTimeOffset(
                        process.StartTime.ToUniversalTime()),
                    process.MainModule.FileName);
            var expectedProbe =
                new SequencedExpectedProcessProbe(
                    failuresBeforeSuccess: 1,
                    identity);
            var liveProbe =
                new SequencedProcessProbe(
                    failuresBeforeSuccess: 1,
                    identity);
            var authority =
                new ExactProcessXmlSocketPeerAuthority(
                    new FakeOwnerResolver
                    {
                        ProcessId = process.Id
                    },
                    liveProbe,
                    expectedProbe);

            Assert.True(
                authority.TrySetExpectedProcess(
                    process,
                    out string reason),
                reason);
            Assert.Equal(3, expectedProbe.AttemptCount);
            Assert.Equal(2, liveProbe.AttemptCount);
            Assert.True(
                authority.TryAuthorize(
                    new TcpClient(),
                    out string authorizationReason),
                authorizationReason);
        }

        [Fact]
        public void SetExpectedRetryRemainsBoundedAndFailClosed()
        {
            using Process process =
                Process.GetCurrentProcess();
            var expectedProbe =
                new SequencedExpectedProcessProbe(
                    failuresBeforeSuccess: int.MaxValue,
                    identity: null);
            var authority =
                new ExactProcessXmlSocketPeerAuthority(
                    new FakeOwnerResolver
                    {
                        ProcessId = process.Id
                    },
                    new FakeProcessProbe(),
                    expectedProbe);

            Assert.False(
                authority.TrySetExpectedProcess(
                    process,
                    out string reason));
            Assert.Equal(
                "xml_socket_expected_process_unavailable",
                reason);
            Assert.Equal(
                ExactProcessXmlSocketPeerAuthority
                    .ExpectedProcessCaptureAttemptLimit,
                expectedProbe.AttemptCount);
            Assert.False(
                authority.TryAuthorize(
                    new TcpClient(),
                    out string authorizationReason));
            Assert.Equal(
                "xml_socket_expected_process_unavailable",
                authorizationReason);
        }

        [Fact]
        public void SystemProbeArmsFreshWindowsChildProcess()
        {
            string commandProcessor =
                Environment.GetEnvironmentVariable("ComSpec");
            if (string.IsNullOrWhiteSpace(commandProcessor))
            {
                commandProcessor = Path.Combine(
                    Environment.SystemDirectory,
                    "cmd.exe");
            }
            Assert.True(File.Exists(commandProcessor));

            var startInfo = new ProcessStartInfo
            {
                FileName = commandProcessor,
                Arguments =
                    "/d /s /c \"ping -n 30 127.0.0.1 > nul\"",
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using Process process = Process.Start(startInfo);
            Assert.NotNull(process);
            try
            {
                var authority =
                    new ExactProcessXmlSocketPeerAuthority();

                Assert.True(
                    authority.TrySetExpectedProcess(
                        process,
                        out string reason),
                    reason);
                Assert.Null(reason);
            }
            finally
            {
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill(entireProcessTree: true);
                        process.WaitForExit(2000);
                    }
                }
                catch
                {
                }
            }
        }

        [Fact]
        public void WindowsResolverFindsIpv4ClientOwner()
        {
            AssertOwnerResolution(
                IPAddress.Loopback);
        }

        [Fact]
        public void WindowsResolverFindsIpv6ClientOwner()
        {
            if (!Socket.OSSupportsIPv6)
                return;
            AssertOwnerResolution(
                IPAddress.IPv6Loopback);
        }

        private static void AssertOwnerResolution(
            IPAddress address)
        {
            using var listener =
                new TcpListener(address, 0);
            listener.Start();
            int port =
                ((IPEndPoint)
                    listener.LocalEndpoint).Port;
            using var client =
                new TcpClient(
                    address.AddressFamily);
            client.Connect(address, port);
            using TcpClient accepted =
                listener.AcceptTcpClient();

            var resolver =
                new WindowsTcpOwnerProcessResolver();
            Assert.True(
                resolver.TryResolveOwnerProcessId(
                    accepted,
                    out int ownerProcessId,
                    out string reason),
                reason);
            Assert.Equal(
                Environment.ProcessId,
                ownerProcessId);
        }

        private static void SendProbe(
            TcpClient client)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(
                "{\"task\":\"authority_probe\"}\0");
            NetworkStream stream =
                client.GetStream();
            stream.Write(bytes, 0, bytes.Length);
            stream.Flush();
        }

        private static int ProbeFreePort()
        {
            using var listener =
                new TcpListener(
                    IPAddress.Loopback,
                    0);
            listener.Start();
            return ((IPEndPoint)
                listener.LocalEndpoint).Port;
        }

        private sealed class MutablePeerAuthority
            : IXmlSocketPeerAuthority
        {
            private int _allow = 1;
            private int _attemptCount;

            public bool Allow
            {
                set
                {
                    Volatile.Write(
                        ref _allow,
                        value ? 1 : 0);
                }
            }

            public int AttemptCount
            {
                get
                {
                    return Volatile.Read(
                        ref _attemptCount);
                }
            }

            public bool TryAuthorize(
                TcpClient client,
                out string reasonCode)
            {
                Interlocked.Increment(
                    ref _attemptCount);
                if (Volatile.Read(ref _allow) == 1)
                {
                    reasonCode = null;
                    return true;
                }
                reasonCode = "test_peer_denied";
                return false;
            }
        }

        private sealed class FakeOwnerResolver
            : IXmlSocketOwnerProcessResolver
        {
            public int ProcessId { get; set; }

            public bool TryResolveOwnerProcessId(
                TcpClient acceptedClient,
                out int processId,
                out string reasonCode)
            {
                processId = ProcessId;
                reasonCode = null;
                return true;
            }
        }

        private sealed class FakeProcessProbe
            : IXmlSocketProcessIdentityProbe
        {
            public XmlSocketPeerProcessIdentity
                Identity { get; set; }

            public bool TryCapture(
                int processId,
                out XmlSocketPeerProcessIdentity identity)
            {
                identity = Identity;
                return identity != null;
            }
        }

        private sealed class FakeExpectedProcessProbe
            : IXmlSocketExpectedProcessIdentityProbe
        {
            public XmlSocketPeerProcessIdentity
                Identity { get; set; }

            public bool TryCapture(
                Process process,
                out XmlSocketPeerProcessIdentity identity)
            {
                identity = Identity;
                return identity != null;
            }
        }

        private sealed class SequencedProcessProbe
            : IXmlSocketProcessIdentityProbe
        {
            private int _failuresRemaining;
            private readonly XmlSocketPeerProcessIdentity
                _identity;

            public SequencedProcessProbe(
                int failuresBeforeSuccess,
                XmlSocketPeerProcessIdentity identity)
            {
                _failuresRemaining = failuresBeforeSuccess;
                _identity = identity;
            }

            public int AttemptCount { get; private set; }

            public bool TryCapture(
                int processId,
                out XmlSocketPeerProcessIdentity identity)
            {
                AttemptCount++;
                if (_failuresRemaining > 0)
                {
                    _failuresRemaining--;
                    identity = null;
                    return false;
                }
                identity = _identity;
                return identity != null;
            }
        }

        private sealed class SequencedExpectedProcessProbe
            : IXmlSocketExpectedProcessIdentityProbe
        {
            private int _failuresRemaining;
            private readonly XmlSocketPeerProcessIdentity
                _identity;

            public SequencedExpectedProcessProbe(
                int failuresBeforeSuccess,
                XmlSocketPeerProcessIdentity identity)
            {
                _failuresRemaining = failuresBeforeSuccess;
                _identity = identity;
            }

            public int AttemptCount { get; private set; }

            public bool TryCapture(
                Process process,
                out XmlSocketPeerProcessIdentity identity)
            {
                AttemptCount++;
                if (_failuresRemaining > 0)
                {
                    _failuresRemaining--;
                    identity = null;
                    return false;
                }
                identity = _identity;
                return identity != null;
            }
        }
    }
}
