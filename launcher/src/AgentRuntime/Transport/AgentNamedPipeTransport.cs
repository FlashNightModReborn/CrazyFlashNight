using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace CF7Launcher.AgentRuntime.Transport
{
    internal enum AgentElevationType
    {
        Unknown = 0,
        Default = 1,
        Full = 2,
        Limited = 3
    }

    internal sealed class AgentProcessSecurityIdentity
    {
        public uint ProcessId { get; private set; }
        public DateTimeOffset ProcessStartTimeUtc { get; private set; }
        public uint WindowsSessionId { get; private set; }
        public AgentElevationType ElevationType { get; private set; }
        public string UserSid { get; private set; }
        public string ExecutablePath { get; private set; }
        public string ExecutableSha256 { get; private set; }

        public AgentProcessSecurityIdentity(
            uint processId,
            DateTimeOffset processStartTimeUtc,
            uint windowsSessionId,
            AgentElevationType elevationType,
            string userSid,
            string executablePath = null,
            string executableSha256 = null)
        {
            if (processId == 0)
                throw new ArgumentOutOfRangeException(nameof(processId));
            if (string.IsNullOrWhiteSpace(userSid))
                throw new ArgumentException("A user SID is required.", nameof(userSid));

            ProcessId = processId;
            ProcessStartTimeUtc = processStartTimeUtc.ToUniversalTime();
            WindowsSessionId = windowsSessionId;
            ElevationType = elevationType;
            UserSid = userSid;
            ExecutablePath = executablePath;
            ExecutableSha256 = executableSha256;
        }
    }

    internal interface IAgentPipePeerProbe
    {
        string LocalComputerName { get; }

        bool TryGetClientComputerName(
            SafePipeHandle pipeHandle,
            out string computerName);

        bool TryGetClientProcessId(
            SafePipeHandle pipeHandle,
            out uint processId);

        bool TryGetProcessIdentity(
            uint processId,
            out AgentProcessSecurityIdentity identity);
    }

    internal sealed class AgentPipePeerVerificationResult
    {
        public bool Accepted { get; private set; }
        public string ReasonCode { get; private set; }
        public AgentProcessSecurityIdentity PeerIdentity { get; private set; }

        private AgentPipePeerVerificationResult(
            bool accepted,
            string reasonCode,
            AgentProcessSecurityIdentity peerIdentity)
        {
            Accepted = accepted;
            ReasonCode = reasonCode;
            PeerIdentity = peerIdentity;
        }

        public static AgentPipePeerVerificationResult Accept(
            AgentProcessSecurityIdentity peerIdentity)
        {
            return new AgentPipePeerVerificationResult(
                true,
                "accepted",
                peerIdentity ?? throw new ArgumentNullException(nameof(peerIdentity)));
        }

        public static AgentPipePeerVerificationResult Reject(string reasonCode)
        {
            if (string.IsNullOrWhiteSpace(reasonCode))
                throw new ArgumentException(
                    "A rejection reason is required.",
                    nameof(reasonCode));
            return new AgentPipePeerVerificationResult(false, reasonCode, null);
        }
    }

    internal interface IAgentPipePeerVerifier
    {
        AgentPipePeerVerificationResult Verify(SafePipeHandle pipeHandle);
    }

    /// <summary>
    /// Verifies the OS-observed peer before exposing the connected stream to
    /// protocol code. Hello fields are never used as process identity.
    /// </summary>
    internal sealed class AgentPipePeerVerifier : IAgentPipePeerVerifier
    {
        private readonly IAgentPipePeerProbe _probe;
        private readonly AgentProcessSecurityIdentity _serverIdentity;

        public AgentPipePeerVerifier(
            IAgentPipePeerProbe probe,
            AgentProcessSecurityIdentity serverIdentity)
        {
            _probe = probe ?? throw new ArgumentNullException(nameof(probe));
            _serverIdentity = serverIdentity
                ?? throw new ArgumentNullException(nameof(serverIdentity));
        }

        public AgentPipePeerVerificationResult Verify(SafePipeHandle pipeHandle)
        {
            if (pipeHandle == null || pipeHandle.IsInvalid || pipeHandle.IsClosed)
                return AgentPipePeerVerificationResult.Reject("pipe_handle_invalid");

            if (!_probe.TryGetClientComputerName(
                    pipeHandle,
                    out string computerName))
                return AgentPipePeerVerificationResult.Reject(
                    "peer_computer_unverifiable");
            if (!IsLocalComputerName(computerName, _probe.LocalComputerName))
                return AgentPipePeerVerificationResult.Reject(
                    "remote_client_rejected");

            if (!_probe.TryGetClientProcessId(pipeHandle, out uint processId)
                || processId == 0)
                return AgentPipePeerVerificationResult.Reject(
                    "peer_process_unverifiable");
            if (!_probe.TryGetProcessIdentity(processId, out AgentProcessSecurityIdentity peer)
                || peer == null
                || peer.ProcessId != processId)
                return AgentPipePeerVerificationResult.Reject(
                    "peer_process_stale");

            if (!string.Equals(
                    peer.UserSid,
                    _serverIdentity.UserSid,
                    StringComparison.Ordinal))
                return AgentPipePeerVerificationResult.Reject(
                    "peer_user_mismatch");
            if (peer.WindowsSessionId != _serverIdentity.WindowsSessionId)
                return AgentPipePeerVerificationResult.Reject(
                    "peer_session_mismatch");
            if (peer.ElevationType == AgentElevationType.Unknown
                || _serverIdentity.ElevationType == AgentElevationType.Unknown)
                return AgentPipePeerVerificationResult.Reject(
                    "peer_elevation_unverifiable");
            if (peer.ElevationType != _serverIdentity.ElevationType)
                return AgentPipePeerVerificationResult.Reject(
                    "peer_elevation_mismatch");

            return AgentPipePeerVerificationResult.Accept(peer);
        }

        internal static bool IsLocalComputerName(
            string observedName,
            string localComputerName)
        {
            string observed = NormalizeComputerName(observedName);
            string local = NormalizeComputerName(localComputerName);
            return observed.Length != 0
                && local.Length != 0
                && (string.Equals(observed, local, StringComparison.OrdinalIgnoreCase)
                    || string.Equals(observed, ".", StringComparison.Ordinal));
        }

        private static string NormalizeComputerName(string value)
        {
            return (value ?? string.Empty).Trim().TrimStart('\\');
        }
    }

    internal sealed class WindowsAgentPipePeerProbe : IAgentPipePeerProbe
    {
        private const uint ProcessQueryLimitedInformation = 0x1000;
        private const uint TokenQuery = 0x0008;
        private const int TokenElevationTypeInformationClass = 18;
        private const int ErrorMoreData = 234;
        private const int ErrorPipeLocal = 229;

        public string LocalComputerName { get { return Environment.MachineName; } }

        public bool TryGetClientComputerName(
            SafePipeHandle pipeHandle,
            out string computerName)
        {
            computerName = null;
            int capacity = 256;
            while (capacity <= 32768)
            {
                var buffer = new StringBuilder(capacity);
                if (GetNamedPipeClientComputerName(
                        pipeHandle,
                        buffer,
                        checked((uint)buffer.Capacity)))
                {
                    computerName = buffer.ToString();
                    return !string.IsNullOrWhiteSpace(computerName);
                }

                int error = Marshal.GetLastWin32Error();
                // Windows intentionally reports ERROR_PIPE_LOCAL instead of a
                // computer name for a local-only connection. That error is the
                // positive local-machine proof required by this verifier.
                if (error == ErrorPipeLocal)
                {
                    computerName = LocalComputerName;
                    return true;
                }
                if (error != ErrorMoreData)
                    return false;
                capacity *= 2;
            }
            return false;
        }

        public bool TryGetClientProcessId(
            SafePipeHandle pipeHandle,
            out uint processId)
        {
            return GetNamedPipeClientProcessId(pipeHandle, out processId)
                && processId != 0;
        }

        public bool TryGetProcessIdentity(
            uint processId,
            out AgentProcessSecurityIdentity identity)
        {
            identity = null;
            using SafeProcessHandle processHandle = OpenProcess(
                ProcessQueryLimitedInformation,
                false,
                processId);
            if (processHandle == null || processHandle.IsInvalid)
                return false;
            if (!ProcessIdToSessionId(processId, out uint sessionId))
                return false;
            if (!GetProcessTimes(
                    processHandle,
                    out FileTime creation,
                    out FileTime ignoredExit,
                    out FileTime ignoredKernel,
                    out FileTime ignoredUser))
                return false;
            var executablePathBuffer =
                new StringBuilder(32768);
            uint executablePathLength =
                checked((uint)executablePathBuffer.Capacity);
            if (!QueryFullProcessImageName(
                    processHandle,
                    0,
                    executablePathBuffer,
                    ref executablePathLength)
                || executablePathLength == 0)
            {
                return false;
            }
            string executablePath = Path.GetFullPath(
                executablePathBuffer.ToString());
            string executableSha256;
            try
            {
                using FileStream executable =
                    new FileStream(
                        executablePath,
                        FileMode.Open,
                        FileAccess.Read,
                        FileShare.Read
                            | FileShare.Delete);
                executableSha256 =
                    Convert.ToHexString(
                        SHA256.HashData(executable))
                        .ToLowerInvariant();
            }
            catch
            {
                return false;
            }
            if (!OpenProcessToken(
                    processHandle,
                    TokenQuery,
                    out SafeAccessTokenHandle tokenHandle))
                return false;

            using (tokenHandle)
            {
                int elevationRaw = 0;
                if (!GetTokenInformation(
                        tokenHandle,
                        TokenElevationTypeInformationClass,
                        ref elevationRaw,
                        sizeof(int),
                        out int returnedLength)
                    || returnedLength != sizeof(int))
                    return false;

                string sid;
                using (var identityView =
                    new WindowsIdentity(tokenHandle.DangerousGetHandle()))
                {
                    sid = identityView.User == null
                        ? null
                        : identityView.User.Value;
                }
                if (string.IsNullOrWhiteSpace(sid))
                    return false;

                long fileTime = unchecked(
                    ((long)creation.HighDateTime << 32)
                    | creation.LowDateTime);
                DateTimeOffset startTimeUtc =
                    new DateTimeOffset(DateTime.FromFileTimeUtc(fileTime));
                AgentElevationType elevationType =
                    Enum.IsDefined(typeof(AgentElevationType), elevationRaw)
                        ? (AgentElevationType)elevationRaw
                        : AgentElevationType.Unknown;

                identity = new AgentProcessSecurityIdentity(
                    processId,
                    startTimeUtc,
                    sessionId,
                    elevationType,
                    sid,
                    executablePath,
                    executableSha256);
                return true;
            }
        }

        public static bool TryGetCurrentProcessIdentity(
            out AgentProcessSecurityIdentity identity)
        {
            using Process current = Process.GetCurrentProcess();
            return new WindowsAgentPipePeerProbe().TryGetProcessIdentity(
                checked((uint)current.Id),
                out identity);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileTime
        {
            public uint LowDateTime;
            public uint HighDateTime;
        }

        [DllImport(
            "kernel32.dll",
            EntryPoint = "GetNamedPipeClientComputerNameW",
            CharSet = CharSet.Unicode,
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetNamedPipeClientComputerName(
            SafePipeHandle pipeHandle,
            StringBuilder clientComputerName,
            uint clientComputerNameLength);

        [DllImport(
            "kernel32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetNamedPipeClientProcessId(
            SafePipeHandle pipeHandle,
            out uint clientProcessId);

        [DllImport(
            "kernel32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        private static extern SafeProcessHandle OpenProcess(
            uint desiredAccess,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
            uint processId);

        [DllImport(
            "kernel32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ProcessIdToSessionId(
            uint processId,
            out uint sessionId);

        [DllImport(
            "kernel32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetProcessTimes(
            SafeProcessHandle processHandle,
            out FileTime creationTime,
            out FileTime exitTime,
            out FileTime kernelTime,
            out FileTime userTime);

        [DllImport(
            "kernel32.dll",
            EntryPoint = "QueryFullProcessImageNameW",
            CharSet = CharSet.Unicode,
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageName(
            SafeProcessHandle processHandle,
            uint flags,
            StringBuilder executablePath,
            ref uint executablePathLength);

        [DllImport(
            "advapi32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(
            SafeProcessHandle processHandle,
            uint desiredAccess,
            out SafeAccessTokenHandle tokenHandle);

        [DllImport(
            "advapi32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetTokenInformation(
            SafeAccessTokenHandle tokenHandle,
            int tokenInformationClass,
            ref int tokenInformation,
            int tokenInformationLength,
            out int returnLength);
    }

    internal sealed class AgentNamedPipeSecurityContract
    {
        public bool CurrentUserOnly { get { return true; } }
        public bool RejectRemoteBeforeProtocol { get { return true; } }
        public bool RequireSameWindowsSession { get { return true; } }
        public bool RequireSameElevationType { get { return true; } }
    }

    internal sealed class AgentPipePeerRejectedException : IOException
    {
        public string ReasonCode { get; private set; }

        public AgentPipePeerRejectedException(string reasonCode)
            : base("The named-pipe peer was rejected: " + reasonCode)
        {
            ReasonCode = reasonCode;
        }
    }

    internal sealed class AgentVerifiedPipeConnection : IDisposable, IAsyncDisposable
    {
        private NamedPipeServerStream _stream;

        public Stream Stream
        {
            get
            {
                return _stream
                    ?? throw new ObjectDisposedException(
                        nameof(AgentVerifiedPipeConnection));
            }
        }

        public AgentProcessSecurityIdentity PeerIdentity { get; private set; }

        internal AgentVerifiedPipeConnection(
            NamedPipeServerStream stream,
            AgentProcessSecurityIdentity peerIdentity)
        {
            _stream = stream ?? throw new ArgumentNullException(nameof(stream));
            PeerIdentity = peerIdentity
                ?? throw new ArgumentNullException(nameof(peerIdentity));
        }

        public void Dispose()
        {
            NamedPipeServerStream stream =
                Interlocked.Exchange(ref _stream, null);
            if (stream != null) stream.Dispose();
        }

        public async ValueTask DisposeAsync()
        {
            NamedPipeServerStream stream =
                Interlocked.Exchange(ref _stream, null);
            if (stream != null)
                await stream.DisposeAsync().ConfigureAwait(false);
        }
    }

    internal sealed class AgentPendingPipeServer : IDisposable, IAsyncDisposable
    {
        private NamedPipeServerStream _server;
        private int _acceptStarted;

        public string PipeName { get; private set; }
        public AgentNamedPipeSecurityContract SecurityContract { get; private set; }

        internal AgentPendingPipeServer(
            string pipeName,
            NamedPipeServerStream server)
        {
            PipeName = pipeName;
            _server = server;
            SecurityContract = new AgentNamedPipeSecurityContract();
        }

        public async Task<AgentVerifiedPipeConnection> AcceptVerifiedAsync(
            IAgentPipePeerVerifier verifier,
            CancellationToken cancellationToken)
        {
            if (verifier == null)
                throw new ArgumentNullException(nameof(verifier));
            if (Interlocked.Exchange(ref _acceptStarted, 1) != 0)
                throw new InvalidOperationException(
                    "A pending named-pipe server can only accept once.");

            NamedPipeServerStream server = _server
                ?? throw new ObjectDisposedException(
                    nameof(AgentPendingPipeServer));
            try
            {
                await server.WaitForConnectionAsync(
                    cancellationToken).ConfigureAwait(false);
                AgentPipePeerVerificationResult result =
                    verifier.Verify(server.SafePipeHandle);
                if (!result.Accepted)
                    throw new AgentPipePeerRejectedException(result.ReasonCode);

                _server = null;
                return new AgentVerifiedPipeConnection(
                    server,
                    result.PeerIdentity);
            }
            catch
            {
                Dispose();
                throw;
            }
        }

        public void Dispose()
        {
            NamedPipeServerStream server =
                Interlocked.Exchange(ref _server, null);
            if (server != null) server.Dispose();
        }

        public async ValueTask DisposeAsync()
        {
            NamedPipeServerStream server =
                Interlocked.Exchange(ref _server, null);
            if (server != null)
                await server.DisposeAsync().ConfigureAwait(false);
        }
    }

    internal sealed class AgentNamedPipeServerFactory
    {
        internal const string PipeNamePrefix = "CF7FlashNight.AgentRuntime.v1.";
        private const int BufferSize = 64 * 1024;

        public AgentPendingPipeServer Create(string pipeId)
        {
            ValidateOpaquePipeId(pipeId);
            string pipeName = PipeNamePrefix + pipeId;
            var server = new NamedPipeServerStream(
                pipeName,
                PipeDirection.InOut,
                NamedPipeServerStream.MaxAllowedServerInstances,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly,
                BufferSize,
                BufferSize);
            return new AgentPendingPipeServer(pipeName, server);
        }

        internal static void ValidateOpaquePipeId(string pipeId)
        {
            if (string.IsNullOrWhiteSpace(pipeId)
                || pipeId.Length < 22
                || pipeId.Length > 86)
                throw new ArgumentException(
                    "The pipe id must be a 128-bit-or-stronger opaque id.",
                    nameof(pipeId));

            for (int index = 0; index < pipeId.Length; index++)
            {
                char value = pipeId[index];
                bool allowed =
                    (value >= 'a' && value <= 'z')
                    || (value >= 'A' && value <= 'Z')
                    || (value >= '0' && value <= '9')
                    || value == '-'
                    || value == '_';
                if (!allowed)
                    throw new ArgumentException(
                        "The pipe id contains a non-opaque-name character.",
                        nameof(pipeId));
            }
        }
    }
}
