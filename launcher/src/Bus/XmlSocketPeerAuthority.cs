using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;

namespace CF7Launcher.Bus
{
    /// <summary>
    /// Authorizes an accepted XMLSocket peer before it can replace the
    /// current Flash connection or advance the connection generation.
    /// </summary>
    internal interface IXmlSocketPeerAuthority
    {
        bool TryAuthorize(
            TcpClient client,
            out string reasonCode);
    }

    internal sealed class DenyAllXmlSocketPeerAuthority
        : IXmlSocketPeerAuthority
    {
        public static readonly DenyAllXmlSocketPeerAuthority
            Instance = new DenyAllXmlSocketPeerAuthority();

        private DenyAllXmlSocketPeerAuthority()
        {
        }

        public bool TryAuthorize(
            TcpClient client,
            out string reasonCode)
        {
            reasonCode = "xml_socket_peer_authority_unavailable";
            return false;
        }
    }

    /// <summary>
    /// Compatibility authority for explicit bus-only/legacy automation
    /// mode. Standard Agent Runtime mode must use exact process authority.
    /// </summary>
    internal sealed class AllowLoopbackXmlSocketPeerAuthority
        : IXmlSocketPeerAuthority
    {
        public static readonly AllowLoopbackXmlSocketPeerAuthority
            Instance =
                new AllowLoopbackXmlSocketPeerAuthority();

        private AllowLoopbackXmlSocketPeerAuthority()
        {
        }

        public bool TryAuthorize(
            TcpClient client,
            out string reasonCode)
        {
            if (!XmlSocketPeerEndpoints.TryRead(
                    client,
                    out _,
                    out IPEndPoint remote)
                || !IPAddress.IsLoopback(remote.Address))
            {
                reasonCode = "xml_socket_peer_not_loopback";
                return false;
            }
            reasonCode = null;
            return true;
        }
    }

    internal sealed record XmlSocketPeerProcessIdentity(
        int ProcessId,
        DateTimeOffset StartTimeUtc,
        string ExecutablePath);

    internal interface IXmlSocketOwnerProcessResolver
    {
        bool TryResolveOwnerProcessId(
            TcpClient acceptedClient,
            out int processId,
            out string reasonCode);
    }

    internal interface IXmlSocketProcessIdentityProbe
    {
        bool TryCapture(
            int processId,
            out XmlSocketPeerProcessIdentity identity);
    }

    internal interface IXmlSocketExpectedProcessIdentityProbe
    {
        bool TryCapture(
            Process process,
            out XmlSocketPeerProcessIdentity identity);
    }

    /// <summary>
    /// Standard-mode authority. The accepted loopback tuple is resolved to
    /// its owning client PID through the Windows TCP owner table, then the
    /// live process is rebound to exact PID/start-time/path to reject PID
    /// reuse and a same-port impostor.
    /// </summary>
    internal sealed class ExactProcessXmlSocketPeerAuthority
        : IXmlSocketPeerAuthority
    {
        // A freshly started Flash projector can exist and own a window before
        // Windows/.NET can return MainModule consistently. Keep admission
        // fail-closed, but absorb that short initialization race before giving
        // up for the whole launch attempt.
        internal const int ExpectedProcessCaptureAttemptLimit = 20;
        private const int ExpectedProcessCaptureRetryDelayMs = 10;

        private readonly object _sync = new object();
        private readonly IXmlSocketOwnerProcessResolver
            _ownerResolver;
        private readonly IXmlSocketProcessIdentityProbe
            _processProbe;
        private readonly IXmlSocketExpectedProcessIdentityProbe
            _expectedProcessProbe;
        private XmlSocketPeerProcessIdentity _expected;
        private long _expectedVersion;

        public ExactProcessXmlSocketPeerAuthority()
            : this(
                new WindowsTcpOwnerProcessResolver(),
                new SystemXmlSocketProcessIdentityProbe(),
                new SystemXmlSocketProcessIdentityProbe())
        {
        }

        internal ExactProcessXmlSocketPeerAuthority(
            IXmlSocketOwnerProcessResolver ownerResolver,
            IXmlSocketProcessIdentityProbe processProbe)
            : this(
                ownerResolver,
                processProbe,
                processProbe
                    as IXmlSocketExpectedProcessIdentityProbe
                    ?? new SystemXmlSocketProcessIdentityProbe())
        {
        }

        internal ExactProcessXmlSocketPeerAuthority(
            IXmlSocketOwnerProcessResolver ownerResolver,
            IXmlSocketProcessIdentityProbe processProbe,
            IXmlSocketExpectedProcessIdentityProbe
                expectedProcessProbe)
        {
            _ownerResolver = ownerResolver
                ?? throw new ArgumentNullException(
                    nameof(ownerResolver));
            _processProbe = processProbe
                ?? throw new ArgumentNullException(
                    nameof(processProbe));
            _expectedProcessProbe = expectedProcessProbe
                ?? throw new ArgumentNullException(
                    nameof(expectedProcessProbe));
        }

        public bool TrySetExpectedProcess(
            Process process,
            out string reasonCode)
        {
            if (process == null)
            {
                reasonCode =
                    "xml_socket_expected_process_unavailable";
                return false;
            }

            XmlSocketPeerProcessIdentity identity = null;
            for (int attempt = 1;
                 attempt <= ExpectedProcessCaptureAttemptLimit;
                 attempt++)
            {
                if (TryCaptureExpectedProcess(
                        process,
                        out identity))
                {
                    SetExpected(identity);
                    reasonCode = null;
                    return true;
                }
                if (attempt < ExpectedProcessCaptureAttemptLimit)
                {
                    System.Threading.Thread.Sleep(
                        ExpectedProcessCaptureRetryDelayMs);
                }
            }

            reasonCode =
                "xml_socket_expected_process_unavailable";
            return false;
        }

        private bool TryCaptureExpectedProcess(
            Process process,
            out XmlSocketPeerProcessIdentity identity)
        {
            identity = null;
            if (!_expectedProcessProbe.TryCapture(
                    process,
                    out XmlSocketPeerProcessIdentity captured)
                || !IsValid(captured)
                || !_processProbe.TryCapture(
                    captured.ProcessId,
                    out XmlSocketPeerProcessIdentity liveIdentity)
                || !SameIdentity(captured, liveIdentity))
            {
                return false;
            }
            try
            {
                if (process.HasExited
                    || process.Id != captured.ProcessId)
                {
                    return false;
                }
            }
            catch
            {
                return false;
            }

            identity = captured;
            return true;
        }

        public void ClearExpectedProcess()
        {
            lock (_sync)
            {
                _expected = null;
                _expectedVersion++;
            }
        }

        internal void SetExpectedForTests(
            XmlSocketPeerProcessIdentity identity)
        {
            SetExpected(identity);
        }

        public bool TryAuthorize(
            TcpClient client,
            out string reasonCode)
        {
            XmlSocketPeerProcessIdentity expected;
            long version;
            lock (_sync)
            {
                expected = _expected;
                version = _expectedVersion;
            }
            if (expected == null)
            {
                reasonCode =
                    "xml_socket_expected_process_unavailable";
                return false;
            }
            if (!_ownerResolver.TryResolveOwnerProcessId(
                    client,
                    out int ownerProcessId,
                    out reasonCode))
            {
                return false;
            }
            if (ownerProcessId != expected.ProcessId
                || !_processProbe.TryCapture(
                    ownerProcessId,
                    out XmlSocketPeerProcessIdentity observed)
                || !SameIdentity(expected, observed))
            {
                reasonCode = "xml_socket_peer_identity_mismatch";
                return false;
            }

            lock (_sync)
            {
                if (version != _expectedVersion
                    || !SameIdentity(_expected, expected))
                {
                    reasonCode =
                        "xml_socket_expected_process_changed";
                    return false;
                }
            }
            reasonCode = null;
            return true;
        }

        private void SetExpected(
            XmlSocketPeerProcessIdentity identity)
        {
            if (!IsValid(identity))
            {
                throw new ArgumentException(
                    "An exact process identity is required.",
                    nameof(identity));
            }
            var frozen = new XmlSocketPeerProcessIdentity(
                identity.ProcessId,
                identity.StartTimeUtc.ToUniversalTime(),
                Path.GetFullPath(identity.ExecutablePath));
            lock (_sync)
            {
                if (SameIdentity(_expected, frozen))
                    return;
                _expected = frozen;
                _expectedVersion++;
            }
        }

        private static bool SameIdentity(
            XmlSocketPeerProcessIdentity left,
            XmlSocketPeerProcessIdentity right)
        {
            return left != null
                && right != null
                && left.ProcessId == right.ProcessId
                && left.StartTimeUtc.UtcDateTime.Ticks
                    == right.StartTimeUtc.UtcDateTime.Ticks
                && string.Equals(
                    Path.GetFullPath(left.ExecutablePath),
                    Path.GetFullPath(right.ExecutablePath),
                    StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsValid(
            XmlSocketPeerProcessIdentity identity)
        {
            return identity != null
                && identity.ProcessId > 0
                && identity.StartTimeUtc != default
                && !string.IsNullOrWhiteSpace(
                    identity.ExecutablePath)
                && Path.IsPathFullyQualified(
                    identity.ExecutablePath);
        }
    }

    internal sealed class SystemXmlSocketProcessIdentityProbe
        : IXmlSocketProcessIdentityProbe,
          IXmlSocketExpectedProcessIdentityProbe
    {
        public bool TryCapture(
            int processId,
            out XmlSocketPeerProcessIdentity identity)
        {
            identity = null;
            try
            {
                using Process process =
                    Process.GetProcessById(processId);
                if (process.HasExited)
                    return false;
                DateTimeOffset startTime =
                    new DateTimeOffset(
                        process.StartTime.ToUniversalTime());
                string path = process.MainModule?.FileName;
                if (string.IsNullOrWhiteSpace(path)
                    || process.HasExited)
                {
                    return false;
                }
                identity =
                    new XmlSocketPeerProcessIdentity(
                        process.Id,
                        startTime,
                        Path.GetFullPath(path));
                return true;
            }
            catch (Exception exception)
                when (exception is ArgumentException
                    || exception is InvalidOperationException
                    || exception is NotSupportedException
                    || exception is NullReferenceException
                    || exception is Win32Exception)
            {
                return false;
            }
        }

        public bool TryCapture(
            Process process,
            out XmlSocketPeerProcessIdentity identity)
        {
            identity = null;
            if (process == null)
                return false;
            try
            {
                // HasExited forces Process to bind an OS process handle
                // before any identity field is read. If that original
                // process exits while its PID is reused, the signaled
                // handle remains tied to the original process.
                if (process.HasExited)
                    return false;
                int processId = process.Id;
                DateTimeOffset startTime =
                    new DateTimeOffset(
                        process.StartTime.ToUniversalTime());
                string path = process.MainModule?.FileName;
                if (string.IsNullOrWhiteSpace(path)
                    || process.HasExited
                    || process.Id != processId)
                {
                    return false;
                }
                identity =
                    new XmlSocketPeerProcessIdentity(
                        processId,
                        startTime,
                        Path.GetFullPath(path));
                return true;
            }
            catch (Exception exception)
                when (exception is ArgumentException
                    || exception is InvalidOperationException
                    || exception is NotSupportedException
                    || exception is NullReferenceException
                    || exception is Win32Exception)
            {
                return false;
            }
        }
    }

    internal sealed class WindowsTcpOwnerProcessResolver
        : IXmlSocketOwnerProcessResolver
    {
        private const int AddressFamilyInterNetwork = 2;
        private const int AddressFamilyInterNetworkV6 = 23;
        private const uint ErrorSuccess = 0;
        private const uint ErrorInsufficientBuffer = 122;
        private const uint TcpStateEstablished = 5;
        private const int MaximumTableBytes = 16 * 1024 * 1024;

        public bool TryResolveOwnerProcessId(
            TcpClient acceptedClient,
            out int processId,
            out string reasonCode)
        {
            processId = 0;
            if (!OperatingSystem.IsWindows())
            {
                reasonCode =
                    "xml_socket_peer_owner_unavailable";
                return false;
            }
            if (!XmlSocketPeerEndpoints.TryRead(
                    acceptedClient,
                    out IPEndPoint server,
                    out IPEndPoint client)
                || !IPAddress.IsLoopback(server.Address)
                || !IPAddress.IsLoopback(client.Address)
                || server.AddressFamily
                    != client.AddressFamily)
            {
                reasonCode = "xml_socket_peer_not_loopback";
                return false;
            }

            List<int> matches;
            if (server.AddressFamily
                == AddressFamily.InterNetwork)
            {
                matches = ReadIpv4Owners(
                    client,
                    server,
                    out reasonCode);
            }
            else if (server.AddressFamily
                == AddressFamily.InterNetworkV6)
            {
                matches = ReadIpv6Owners(
                    client,
                    server,
                    out reasonCode);
            }
            else
            {
                reasonCode =
                    "xml_socket_peer_address_family_unsupported";
                return false;
            }
            if (matches == null)
                return false;
            if (matches.Count != 1)
            {
                reasonCode = matches.Count == 0
                    ? "xml_socket_peer_owner_not_found"
                    : "xml_socket_peer_owner_ambiguous";
                return false;
            }

            processId = matches[0];
            reasonCode = null;
            return true;
        }

        private static List<int> ReadIpv4Owners(
            IPEndPoint client,
            IPEndPoint server,
            out string reasonCode)
        {
            return ReadTable(
                AddressFamilyInterNetwork,
                typeof(MibTcpRowOwnerPid),
                (rowPointer, matches) =>
                {
                    MibTcpRowOwnerPid row =
                        Marshal.PtrToStructure<
                            MibTcpRowOwnerPid>(
                            rowPointer);
                    if (row.State != TcpStateEstablished)
                        return;
                    var localAddress =
                        new IPAddress(row.LocalAddress);
                    var remoteAddress =
                        new IPAddress(row.RemoteAddress);
                    if (localAddress.Equals(client.Address)
                        && remoteAddress.Equals(server.Address)
                        && DecodePort(row.LocalPort)
                            == client.Port
                        && DecodePort(row.RemotePort)
                            == server.Port
                        && row.OwningProcessId > 0
                        && row.OwningProcessId <= int.MaxValue)
                    {
                        matches.Add(
                            checked((int)
                                row.OwningProcessId));
                    }
                },
                out reasonCode);
        }

        private static List<int> ReadIpv6Owners(
            IPEndPoint client,
            IPEndPoint server,
            out string reasonCode)
        {
            return ReadTable(
                AddressFamilyInterNetworkV6,
                typeof(MibTcp6RowOwnerPid),
                (rowPointer, matches) =>
                {
                    MibTcp6RowOwnerPid row =
                        Marshal.PtrToStructure<
                            MibTcp6RowOwnerPid>(
                            rowPointer);
                    if (row.State != TcpStateEstablished
                        || row.LocalAddress == null
                        || row.RemoteAddress == null)
                    {
                        return;
                    }
                    var localAddress = new IPAddress(
                        row.LocalAddress,
                        row.LocalScopeId);
                    var remoteAddress = new IPAddress(
                        row.RemoteAddress,
                        row.RemoteScopeId);
                    if (localAddress.Equals(client.Address)
                        && remoteAddress.Equals(server.Address)
                        && DecodePort(row.LocalPort)
                            == client.Port
                        && DecodePort(row.RemotePort)
                            == server.Port
                        && row.OwningProcessId > 0
                        && row.OwningProcessId <= int.MaxValue)
                    {
                        matches.Add(
                            checked((int)
                                row.OwningProcessId));
                    }
                },
                out reasonCode);
        }

        private static List<int> ReadTable(
            int addressFamily,
            Type rowType,
            Action<IntPtr, List<int>> inspect,
            out string reasonCode)
        {
            IntPtr buffer = IntPtr.Zero;
            try
            {
                int size = 0;
                uint first = GetExtendedTcpTable(
                    IntPtr.Zero,
                    ref size,
                    false,
                    addressFamily,
                    TcpTableClass.OwnerPidAll,
                    0);
                if (first != ErrorInsufficientBuffer
                    && first != ErrorSuccess)
                {
                    reasonCode =
                        "xml_socket_peer_owner_unavailable";
                    return null;
                }
                if (size < sizeof(int)
                    || size > MaximumTableBytes)
                {
                    reasonCode =
                        "xml_socket_peer_owner_unavailable";
                    return null;
                }

                for (int attempt = 0; attempt < 2; attempt++)
                {
                    buffer = Marshal.AllocHGlobal(size);
                    int actualSize = size;
                    uint result = GetExtendedTcpTable(
                        buffer,
                        ref actualSize,
                        false,
                        addressFamily,
                        TcpTableClass.OwnerPidAll,
                        0);
                    if (result == ErrorInsufficientBuffer
                        && attempt == 0
                        && actualSize >= sizeof(int)
                        && actualSize <= MaximumTableBytes)
                    {
                        Marshal.FreeHGlobal(buffer);
                        buffer = IntPtr.Zero;
                        size = actualSize;
                        continue;
                    }
                    if (result != ErrorSuccess)
                    {
                        reasonCode =
                            "xml_socket_peer_owner_unavailable";
                        return null;
                    }

                    int count = Marshal.ReadInt32(buffer);
                    int rowSize = Marshal.SizeOf(rowType);
                    long required = sizeof(int)
                        + checked((long)count * rowSize);
                    if (count < 0
                        || required > actualSize)
                    {
                        reasonCode =
                            "xml_socket_peer_owner_unavailable";
                        return null;
                    }
                    var matches = new List<int>();
                    IntPtr row = IntPtr.Add(
                        buffer,
                        sizeof(int));
                    for (int index = 0;
                        index < count;
                        index++)
                    {
                        inspect(row, matches);
                        row = IntPtr.Add(row, rowSize);
                    }
                    reasonCode = null;
                    return matches;
                }
                reasonCode =
                    "xml_socket_peer_owner_unavailable";
                return null;
            }
            catch
            {
                reasonCode =
                    "xml_socket_peer_owner_unavailable";
                return null;
            }
            finally
            {
                if (buffer != IntPtr.Zero)
                    Marshal.FreeHGlobal(buffer);
            }
        }

        private static int DecodePort(uint encoded)
        {
            return unchecked((ushort)
                IPAddress.NetworkToHostOrder(
                    unchecked((short)
                        (encoded & ushort.MaxValue))));
        }

        private enum TcpTableClass
        {
            OwnerPidAll = 5
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MibTcpRowOwnerPid
        {
            public uint State;
            public uint LocalAddress;
            public uint LocalPort;
            public uint RemoteAddress;
            public uint RemotePort;
            public uint OwningProcessId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MibTcp6RowOwnerPid
        {
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
            public byte[] LocalAddress;
            public uint LocalScopeId;
            public uint LocalPort;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
            public byte[] RemoteAddress;
            public uint RemoteScopeId;
            public uint RemotePort;
            public uint State;
            public uint OwningProcessId;
        }

        [DllImport("iphlpapi.dll", SetLastError = true)]
        private static extern uint GetExtendedTcpTable(
            IntPtr table,
            ref int size,
            [MarshalAs(UnmanagedType.Bool)] bool order,
            int addressFamily,
            TcpTableClass tableClass,
            uint reserved);
    }

    internal static class XmlSocketPeerEndpoints
    {
        public static bool TryRead(
            TcpClient client,
            out IPEndPoint local,
            out IPEndPoint remote)
        {
            local = null;
            remote = null;
            try
            {
                local = client?.Client?.LocalEndPoint
                    as IPEndPoint;
                remote = client?.Client?.RemoteEndPoint
                    as IPEndPoint;
                return local != null && remote != null;
            }
            catch
            {
                local = null;
                remote = null;
                return false;
            }
        }
    }
}
