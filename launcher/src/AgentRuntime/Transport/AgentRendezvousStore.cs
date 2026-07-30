using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace CF7Launcher.AgentRuntime.Transport
{
    internal interface IAgentRendezvousClock
    {
        DateTimeOffset UtcNow { get; }
    }

    internal sealed class SystemAgentRendezvousClock : IAgentRendezvousClock
    {
        public DateTimeOffset UtcNow { get { return DateTimeOffset.UtcNow; } }
    }

    internal interface IAgentRendezvousProcessProbe
    {
        bool IsExactProcessAlive(
            int processId,
            DateTimeOffset expectedStartTimeUtc);
    }

    internal sealed class SystemAgentRendezvousProcessProbe
        : IAgentRendezvousProcessProbe
    {
        public bool IsExactProcessAlive(
            int processId,
            DateTimeOffset expectedStartTimeUtc)
        {
            try
            {
                using Process process = Process.GetProcessById(processId);
                if (process.HasExited) return false;
                DateTimeOffset actual =
                    new DateTimeOffset(process.StartTime.ToUniversalTime());
                return actual.UtcDateTime.Ticks
                    == expectedStartTimeUtc.UtcDateTime.Ticks;
            }
            catch (ArgumentException)
            {
                return false;
            }
            catch (InvalidOperationException)
            {
                return false;
            }
            catch (Win32Exception)
            {
                return false;
            }
            catch (NotSupportedException)
            {
                return false;
            }
        }
    }

    internal interface IAgentRendezvousFileProtection
    {
        void ProtectDirectory(string path);
        void ProtectFile(string path);
    }

    internal sealed class WindowsCurrentUserRendezvousFileProtection
        : IAgentRendezvousFileProtection
    {
        private readonly SecurityIdentifier _currentUserSid;

        public WindowsCurrentUserRendezvousFileProtection()
        {
            using WindowsIdentity identity = WindowsIdentity.GetCurrent();
            _currentUserSid = identity.User
                ?? throw new InvalidOperationException(
                    "The current Windows logon SID is unavailable.");
        }

        public void ProtectDirectory(string path)
        {
            var security = new DirectorySecurity();
            security.SetOwner(_currentUserSid);
            security.SetAccessRuleProtection(true, false);
            security.AddAccessRule(new FileSystemAccessRule(
                _currentUserSid,
                FileSystemRights.FullControl,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None,
                AccessControlType.Allow));
            new DirectoryInfo(path).SetAccessControl(security);
        }

        public void ProtectFile(string path)
        {
            var security = new FileSecurity();
            security.SetOwner(_currentUserSid);
            security.SetAccessRuleProtection(true, false);
            security.AddAccessRule(new FileSystemAccessRule(
                _currentUserSid,
                FileSystemRights.FullControl,
                AccessControlType.Allow));
            new FileInfo(path).SetAccessControl(security);
        }
    }

    internal sealed class AgentRendezvousOwner
    {
        public string PipeId { get; private set; }
        public int LauncherProcessId { get; private set; }
        public DateTimeOffset LauncherStartTimeUtc { get; private set; }
        public string LifecycleId { get; private set; }
        public string RuntimeQualificationState { get; private set; }

        public AgentRendezvousOwner(
            string pipeId,
            int launcherProcessId,
            DateTimeOffset launcherStartTimeUtc,
            string lifecycleId,
            string runtimeQualificationState)
        {
            AgentNamedPipeServerFactory.ValidateOpaquePipeId(pipeId);
            if (launcherProcessId <= 0)
                throw new ArgumentOutOfRangeException(
                    nameof(launcherProcessId));
            ValidateOpaqueId(lifecycleId, nameof(lifecycleId));
            ValidateRuntimeQualificationState(runtimeQualificationState);

            PipeId = pipeId;
            LauncherProcessId = launcherProcessId;
            LauncherStartTimeUtc = launcherStartTimeUtc.ToUniversalTime();
            LifecycleId = lifecycleId;
            RuntimeQualificationState = runtimeQualificationState;
        }

        internal static void ValidateRuntimeQualificationState(string value)
        {
            if (value == "formal_runtime"
                || value == "isolated_candidate"
                || value == "unqualified_dev")
                return;
            throw new ArgumentException(
                "The runtime qualification state is not recognized.",
                nameof(value));
        }

        internal static void ValidateOpaqueId(string value, string parameterName)
        {
            if (string.IsNullOrWhiteSpace(value)
                || value.Length < 22
                || value.Length > 128)
                throw new ArgumentException(
                    "An opaque 128-bit-or-stronger id is required.",
                    parameterName);
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                bool allowed =
                    (character >= 'a' && character <= 'z')
                    || (character >= 'A' && character <= 'Z')
                    || (character >= '0' && character <= '9')
                    || character == '-'
                    || character == '_';
                if (!allowed)
                    throw new ArgumentException(
                        "The opaque id contains an invalid character.",
                        parameterName);
            }
        }
    }

    internal sealed class AgentRendezvousDocument
    {
        public int ProtocolMinMajor { get; private set; }
        public int ProtocolMaxMajor { get; private set; }
        public string PipeId { get; private set; }
        public int LauncherProcessId { get; private set; }
        public DateTimeOffset LauncherStartTimeUtc { get; private set; }
        public string LifecycleId { get; private set; }
        public string RuntimeQualificationState { get; private set; }
        public DateTimeOffset TicketExpiresUtc { get; private set; }
        public string ConnectionTicket { get; private set; }

        internal AgentRendezvousDocument(
            int protocolMinMajor,
            int protocolMaxMajor,
            string pipeId,
            int launcherProcessId,
            DateTimeOffset launcherStartTimeUtc,
            string lifecycleId,
            string runtimeQualificationState,
            DateTimeOffset ticketExpiresUtc,
            string connectionTicket)
        {
            ProtocolMinMajor = protocolMinMajor;
            ProtocolMaxMajor = protocolMaxMajor;
            PipeId = pipeId;
            LauncherProcessId = launcherProcessId;
            LauncherStartTimeUtc = launcherStartTimeUtc.ToUniversalTime();
            LifecycleId = lifecycleId;
            RuntimeQualificationState = runtimeQualificationState;
            TicketExpiresUtc = ticketExpiresUtc.ToUniversalTime();
            ConnectionTicket = connectionTicket;
        }
    }

    internal static class AgentRendezvousPath
    {
        public static string ComputeProjectRootHash(string projectRoot)
        {
            if (string.IsNullOrWhiteSpace(projectRoot))
                throw new ArgumentException(
                    "A project root is required.",
                    nameof(projectRoot));

            string normalized = Path.GetFullPath(projectRoot)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                .Replace(Path.AltDirectorySeparatorChar, Path.DirectorySeparatorChar)
                .ToUpperInvariant();
            byte[] digest = SHA256.HashData(Encoding.UTF8.GetBytes(normalized));
            return Convert.ToHexString(digest).ToLowerInvariant();
        }

        public static string Resolve(
            string projectRoot,
            string localAppDataOverride = null)
        {
            string localAppData = string.IsNullOrWhiteSpace(localAppDataOverride)
                ? Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData)
                : Path.GetFullPath(localAppDataOverride);
            if (string.IsNullOrWhiteSpace(localAppData))
                throw new InvalidOperationException(
                    "LOCALAPPDATA is unavailable.");

            return Path.Combine(
                localAppData,
                "CF7FlashNight",
                "agent-runtime",
                "v1",
                ComputeProjectRootHash(projectRoot),
                "rendezvous.json");
        }
    }

    internal sealed class AgentRendezvousStore : IDisposable
    {
        internal const int ProtocolMajor = 1;
        internal static readonly TimeSpan MaximumTicketTtl =
            TimeSpan.FromSeconds(30);

        private static readonly HashSet<string> DocumentPropertyNames =
            new HashSet<string>(
                new[]
                {
                    "protocolMinMajor",
                    "protocolMaxMajor",
                    "pipeId",
                    "launcherProcessId",
                    "launcherStartTimeUtc",
                    "lifecycleId",
                    "runtimeQualificationState",
                    "ticketExpiresUtc",
                    "connectionTicket"
                },
                StringComparer.Ordinal);
        private static readonly JsonSerializerOptions SerializerOptions =
            new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                WriteIndented = false
            };

        private readonly object _gate = new object();
        private readonly IAgentRendezvousClock _clock;
        private readonly IAgentRendezvousProcessProbe _processProbe;
        private readonly IAgentRendezvousFileProtection _fileProtection;
        private readonly string _path;

        private AgentRendezvousOwner _ownedRegistration;
        private bool _disposed;

        public string Path { get { return _path; } }

        public AgentRendezvousStore(
            string projectRoot,
            string localAppDataOverride = null,
            IAgentRendezvousClock clock = null,
            IAgentRendezvousProcessProbe processProbe = null,
            IAgentRendezvousFileProtection fileProtection = null)
        {
            _path = AgentRendezvousPath.Resolve(
                projectRoot,
                localAppDataOverride);
            _clock = clock ?? new SystemAgentRendezvousClock();
            _processProbe = processProbe
                ?? new SystemAgentRendezvousProcessProbe();
            _fileProtection = fileProtection
                ?? new WindowsCurrentUserRendezvousFileProtection();
        }

        public AgentRendezvousDocument Publish(
            AgentRendezvousOwner owner,
            TimeSpan ticketTtl)
        {
            if (owner == null) throw new ArgumentNullException(nameof(owner));
            ValidateTicketTtl(ticketTtl);
            lock (_gate)
            {
                ThrowIfDisposed();
                if (!_processProbe.IsExactProcessAlive(
                        owner.LauncherProcessId,
                        owner.LauncherStartTimeUtc))
                    throw new InvalidOperationException(
                        "The rendezvous owner process identity is stale.");

                AgentRendezvousDocument document = CreateDocument(
                    owner,
                    ticketTtl);
                WriteAtomically(document);
                _ownedRegistration = owner;
                return document;
            }
        }

        public bool TryReadFresh(
            string expectedLifecycleId,
            out AgentRendezvousDocument document,
            out string reasonCode)
        {
            lock (_gate)
            {
                ThrowIfDisposed();
                return TryReadFreshLocked(
                    expectedLifecycleId,
                    out document,
                    out reasonCode);
            }
        }

        public bool TryConsumeAndRotate(
            string presentedTicket,
            string expectedLifecycleId,
            out AgentRendezvousDocument rotatedDocument,
            out string reasonCode)
        {
            rotatedDocument = null;
            lock (_gate)
            {
                ThrowIfDisposed();
                if (!TryReadFreshLocked(
                        expectedLifecycleId,
                        out AgentRendezvousDocument current,
                        out reasonCode))
                    return false;
                if (!FixedTimeEquals(
                        current.ConnectionTicket,
                        presentedTicket))
                {
                    reasonCode = "ticket_mismatch";
                    return false;
                }

                var owner = new AgentRendezvousOwner(
                    current.PipeId,
                    current.LauncherProcessId,
                    current.LauncherStartTimeUtc,
                    current.LifecycleId,
                    current.RuntimeQualificationState);
                rotatedDocument = CreateDocument(
                    owner,
                    MaximumTicketTtl);
                WriteAtomically(rotatedDocument);
                if (_ownedRegistration != null
                    && SameOwner(_ownedRegistration, owner))
                    _ownedRegistration = owner;
                reasonCode = "accepted";
                return true;
            }
        }

        public void Dispose()
        {
            lock (_gate)
            {
                if (_disposed) return;
                _disposed = true;
                if (_ownedRegistration == null || !File.Exists(_path))
                    return;

                if (TryReadDocument(
                        out AgentRendezvousDocument current,
                        out string ignored)
                    && SameOwner(_ownedRegistration, current))
                {
                    File.Delete(_path);
                }
            }
        }

        internal static string GenerateOpaqueId()
        {
            return ToBase64Url(RandomNumberGenerator.GetBytes(32));
        }

        internal static AgentRendezvousDocument ParseDocument(
            ReadOnlySpan<byte> json)
        {
            try
            {
                using JsonDocument parsed = JsonDocument.Parse(
                    json.ToArray(),
                    new JsonDocumentOptions
                    {
                        AllowTrailingCommas = false,
                        CommentHandling = JsonCommentHandling.Disallow,
                        MaxDepth = 8
                    });
                JsonElement root = parsed.RootElement;
                if (root.ValueKind != JsonValueKind.Object)
                    throw new InvalidDataException(
                        "The rendezvous document must be an object.");

                var seen = new HashSet<string>(StringComparer.Ordinal);
                foreach (JsonProperty property in root.EnumerateObject())
                {
                    if (!DocumentPropertyNames.Contains(property.Name)
                        || !seen.Add(property.Name))
                        throw new InvalidDataException(
                            "The rendezvous document has an unknown or duplicate property.");
                }
                if (!seen.SetEquals(DocumentPropertyNames))
                    throw new InvalidDataException(
                        "The rendezvous document is missing a required property.");

                int minimum = ReadInt(root, "protocolMinMajor");
                int maximum = ReadInt(root, "protocolMaxMajor");
                if (minimum != ProtocolMajor || maximum != ProtocolMajor)
                    throw new InvalidDataException(
                        "The rendezvous protocol range is unsupported.");

                string pipeId = ReadString(root, "pipeId");
                AgentNamedPipeServerFactory.ValidateOpaquePipeId(pipeId);
                int processId = ReadInt(root, "launcherProcessId");
                if (processId <= 0)
                    throw new InvalidDataException(
                        "The rendezvous process id is invalid.");
                DateTimeOffset processStart =
                    ReadUtcTimestamp(root, "launcherStartTimeUtc");
                string lifecycleId = ReadString(root, "lifecycleId");
                AgentRendezvousOwner.ValidateOpaqueId(
                    lifecycleId,
                    "lifecycleId");
                string qualification =
                    ReadString(root, "runtimeQualificationState");
                AgentRendezvousOwner.ValidateRuntimeQualificationState(
                    qualification);
                DateTimeOffset ticketExpiry =
                    ReadUtcTimestamp(root, "ticketExpiresUtc");
                string ticket = ReadString(root, "connectionTicket");
                AgentRendezvousOwner.ValidateOpaqueId(
                    ticket,
                    "connectionTicket");

                return new AgentRendezvousDocument(
                    minimum,
                    maximum,
                    pipeId,
                    processId,
                    processStart,
                    lifecycleId,
                    qualification,
                    ticketExpiry,
                    ticket);
            }
            catch (JsonException exception)
            {
                throw new InvalidDataException(
                    "The rendezvous document is not valid JSON.",
                    exception);
            }
            catch (ArgumentException exception)
            {
                throw new InvalidDataException(
                    "The rendezvous document contains an invalid value.",
                    exception);
            }
        }

        private bool TryReadFreshLocked(
            string expectedLifecycleId,
            out AgentRendezvousDocument document,
            out string reasonCode)
        {
            document = null;
            if (!TryReadDocument(out document, out reasonCode))
                return false;
            if (!string.IsNullOrEmpty(expectedLifecycleId)
                && !string.Equals(
                    document.LifecycleId,
                    expectedLifecycleId,
                    StringComparison.Ordinal))
            {
                document = null;
                reasonCode = "lifecycle_stale";
                return false;
            }
            if (!_processProbe.IsExactProcessAlive(
                    document.LauncherProcessId,
                    document.LauncherStartTimeUtc))
            {
                document = null;
                reasonCode = "process_stale";
                return false;
            }
            if (document.TicketExpiresUtc <= _clock.UtcNow)
            {
                document = null;
                reasonCode = "ticket_expired";
                return false;
            }
            if (document.TicketExpiresUtc - _clock.UtcNow > MaximumTicketTtl)
            {
                document = null;
                reasonCode = "ticket_expiry_invalid";
                return false;
            }

            reasonCode = "fresh";
            return true;
        }

        private bool TryReadDocument(
            out AgentRendezvousDocument document,
            out string reasonCode)
        {
            document = null;
            if (!File.Exists(_path))
            {
                reasonCode = "rendezvous_not_found";
                return false;
            }
            try
            {
                const int maximumLength = 64 * 1024;
                byte[] json;
                using (var stream = new FileStream(
                    _path,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete,
                    4096,
                    FileOptions.SequentialScan))
                {
                    if (stream.Length > maximumLength)
                    {
                        reasonCode = "rendezvous_oversized";
                        return false;
                    }
                    json = new byte[checked((int)stream.Length)];
                    stream.ReadExactly(json);
                }
                document = ParseDocument(json);
                reasonCode = "read";
                return true;
            }
            catch (IOException)
            {
                reasonCode = "rendezvous_unreadable";
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                reasonCode = "rendezvous_unreadable";
                return false;
            }
            catch (InvalidDataException)
            {
                reasonCode = "rendezvous_malformed";
                return false;
            }
        }

        private AgentRendezvousDocument CreateDocument(
            AgentRendezvousOwner owner,
            TimeSpan ticketTtl)
        {
            return new AgentRendezvousDocument(
                ProtocolMajor,
                ProtocolMajor,
                owner.PipeId,
                owner.LauncherProcessId,
                owner.LauncherStartTimeUtc,
                owner.LifecycleId,
                owner.RuntimeQualificationState,
                _clock.UtcNow.Add(ticketTtl),
                GenerateOpaqueId());
        }

        private void WriteAtomically(AgentRendezvousDocument document)
        {
            string directory = System.IO.Path.GetDirectoryName(_path)
                ?? throw new InvalidOperationException(
                    "The rendezvous directory cannot be resolved.");
            Directory.CreateDirectory(directory);
            _fileProtection.ProtectDirectory(directory);

            string temporaryPath = _path
                + "."
                + Guid.NewGuid().ToString("N")
                + ".tmp";
            try
            {
                byte[] json = JsonSerializer.SerializeToUtf8Bytes(
                    document,
                    SerializerOptions);
                using (var stream = new FileStream(
                    temporaryPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None,
                    4096,
                    FileOptions.WriteThrough))
                {
                    _fileProtection.ProtectFile(temporaryPath);
                    stream.Write(json, 0, json.Length);
                    stream.Flush(true);
                }

                File.Move(temporaryPath, _path, true);
                _fileProtection.ProtectFile(_path);
            }
            finally
            {
                if (File.Exists(temporaryPath))
                    File.Delete(temporaryPath);
            }
        }

        private static int ReadInt(JsonElement root, string name)
        {
            JsonElement property = root.GetProperty(name);
            if (property.ValueKind != JsonValueKind.Number
                || !property.TryGetInt32(out int value))
                throw new InvalidDataException(
                    "The rendezvous integer field is invalid: " + name);
            return value;
        }

        private static string ReadString(JsonElement root, string name)
        {
            JsonElement property = root.GetProperty(name);
            if (property.ValueKind != JsonValueKind.String)
                throw new InvalidDataException(
                    "The rendezvous string field is invalid: " + name);
            string value = property.GetString();
            if (string.IsNullOrWhiteSpace(value))
                throw new InvalidDataException(
                    "The rendezvous string field is empty: " + name);
            return value;
        }

        private static DateTimeOffset ReadUtcTimestamp(
            JsonElement root,
            string name)
        {
            string raw = ReadString(root, name);
            if (!DateTimeOffset.TryParse(
                    raw,
                    System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.RoundtripKind,
                    out DateTimeOffset value)
                || value.Offset != TimeSpan.Zero)
                throw new InvalidDataException(
                    "The rendezvous timestamp is not an explicit UTC value: "
                    + name);
            return value;
        }

        private static void ValidateTicketTtl(TimeSpan ttl)
        {
            if (ttl <= TimeSpan.Zero || ttl > MaximumTicketTtl)
                throw new ArgumentOutOfRangeException(
                    nameof(ttl),
                    "Connection ticket TTL must be in (0, 30s].");
        }

        private static bool SameOwner(
            AgentRendezvousOwner owner,
            AgentRendezvousOwner other)
        {
            return owner.LauncherProcessId == other.LauncherProcessId
                && owner.LauncherStartTimeUtc.UtcDateTime.Ticks
                    == other.LauncherStartTimeUtc.UtcDateTime.Ticks
                && string.Equals(
                    owner.LifecycleId,
                    other.LifecycleId,
                    StringComparison.Ordinal);
        }

        private static bool SameOwner(
            AgentRendezvousOwner owner,
            AgentRendezvousDocument document)
        {
            return owner.LauncherProcessId == document.LauncherProcessId
                && owner.LauncherStartTimeUtc.UtcDateTime.Ticks
                    == document.LauncherStartTimeUtc.UtcDateTime.Ticks
                && string.Equals(
                    owner.LifecycleId,
                    document.LifecycleId,
                    StringComparison.Ordinal);
        }

        private static bool FixedTimeEquals(string expected, string presented)
        {
            if (expected == null || presented == null) return false;
            if (expected.Length != presented.Length
                || expected.Length > 128)
                return false;
            byte[] expectedBytes = Encoding.UTF8.GetBytes(expected);
            byte[] presentedBytes = Encoding.UTF8.GetBytes(presented);
            return CryptographicOperations.FixedTimeEquals(
                expectedBytes,
                presentedBytes);
        }

        private static string ToBase64Url(byte[] bytes)
        {
            return Convert.ToBase64String(bytes)
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(
                    nameof(AgentRendezvousStore));
        }
    }
}
