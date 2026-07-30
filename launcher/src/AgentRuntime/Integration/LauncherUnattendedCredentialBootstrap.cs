using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.AgentRuntime.TrustedRunner;

namespace CF7Launcher.AgentRuntime.Integration
{
    internal sealed class RejectingUnattendedCredentialBindingAuthority
        : IUnattendedCredentialBindingAuthority
    {
        public bool TryAuthorizeEvidence(
            UnattendedCredentialEvidence evidence,
            AgentProcessSecurityIdentity peerIdentity,
            out string reasonCode)
        {
            reasonCode =
                "unattended_bootstrap_not_configured";
            return false;
        }

        public void BindPrincipal(
            PrincipalCredential principal,
            UnattendedCredentialEvidence evidence)
        {
            throw new InvalidOperationException(
                "unattended_bootstrap_not_configured");
        }

        public bool IsPrincipalAuthorized(
            PrincipalCredential principal)
        {
            return false;
        }
    }

    /// <summary>
    /// Immutable request imported from the fixed automation/start.ps1
    /// standard-entry chain. It carries no capability or target selection;
    /// those are derived later from Host-observed session state.
    /// </summary>
    internal sealed class LauncherUnattendedBootstrapRequest
    {
        private const string Schema =
            "cf7.agent_runtime.trusted_unattended_bootstrap_request.v2";
        private const string Issuer =
            "core/trusted-unattended-runner";
        internal const string RunnerPolicyId =
            "cf7_trusted_core_unattended_runner_v2";
        private const int MaximumRequestBytes = 32 * 1024;
        private static readonly TimeSpan MaximumLifetime =
            TimeSpan.FromMinutes(10);
        private static readonly TimeSpan MaximumClockSkew =
            TimeSpan.FromMinutes(1);
        private static readonly HashSet<string> PropertyNames =
            new HashSet<string>(
                new[]
                {
                    "schema",
                    "issuer",
                    "runtimeMode",
                    "clientInstanceId",
                    "runnerPolicyId",
                    "runnerProcessId",
                    "runnerProcessStartTimeUtc",
                    "runnerExecutablePath",
                    "runnerExecutableSha256",
                    "runnerExecutableSize",
                    "runtimeExecutablePath",
                    "slot",
                    "canonicalSavePath",
                    "buildIdentity",
                    "payloadClosure",
                    "issuedUtc",
                    "expiresUtc",
                    "requestNonce"
                },
                StringComparer.Ordinal);
        private static readonly JsonSerializerOptions JsonOptions =
            new JsonSerializerOptions
            {
                PropertyNamingPolicy =
                    JsonNamingPolicy.CamelCase,
                UnmappedMemberHandling =
                    System.Text.Json.Serialization
                        .JsonUnmappedMemberHandling.Disallow,
                MaxDepth = 8
            };

        private LauncherUnattendedBootstrapRequest(
            string projectRoot,
            string runtimeRoot,
            CF7Launcher.AgentRuntime.Contracts
                .RuntimeMode runtimeMode,
            RequestDocument document,
            Process runnerProcess,
            long deadlineMonotonic,
            DateTimeOffset expiresUtc)
        {
            ProjectRoot = projectRoot;
            RuntimeRoot = runtimeRoot;
            RuntimeMode =
                runtimeMode;
            ClientInstanceId =
                document.ClientInstanceId;
            RunnerPolicy =
                document.RunnerPolicyId;
            RunnerProcessId =
                document.RunnerProcessId;
            RunnerProcessStartTimeUtc =
                ParseUtc(
                    document.RunnerProcessStartTimeUtc,
                    "runnerProcessStartTimeUtc");
            RunnerExecutablePath =
                Path.GetFullPath(
                    document.RunnerExecutablePath);
            RunnerExecutableSha256 =
                document.RunnerExecutableSha256
                    .ToLowerInvariant();
            RunnerExecutableSize =
                document.RunnerExecutableSize;
            RuntimeExecutablePath =
                Path.GetFullPath(
                    document.RuntimeExecutablePath);
            Slot = document.Slot;
            CanonicalSavePath =
                document.CanonicalSavePath;
            BuildIdentity =
                document.BuildIdentity.ToLowerInvariant();
            PayloadClosure =
                document.PayloadClosure.ToLowerInvariant();
            RequestNonce = document.RequestNonce;
            DeadlineMonotonic = deadlineMonotonic;
            ExpiresUtc = expiresUtc;
            CredentialPath = CredentialPathFor(
                runtimeRoot,
                document.ClientInstanceId);
            RunnerProcess = runnerProcess;
        }

        public string ProjectRoot { get; }
        public string RuntimeRoot { get; }
        public CF7Launcher.AgentRuntime.Contracts.RuntimeMode
            RuntimeMode { get; }
        public string RuntimeModeName =>
            RuntimeModeWireName(RuntimeMode);
        public string ClientInstanceId { get; }
        public string RunnerPolicy { get; }
        public uint RunnerProcessId { get; }
        public DateTimeOffset RunnerProcessStartTimeUtc
        {
            get;
        }
        public string RunnerExecutablePath { get; }
        public string RunnerExecutableSha256 { get; }
        public long RunnerExecutableSize { get; }
        public string RuntimeExecutablePath { get; }
        public string Slot { get; }
        public string CanonicalSavePath { get; }
        public string BuildIdentity { get; }
        public string PayloadClosure { get; }
        public string RequestNonce { get; }
        public long DeadlineMonotonic { get; }
        public DateTimeOffset ExpiresUtc { get; }
        public string CredentialPath { get; }
        public Process RunnerProcess { get; }

        public static LauncherUnattendedBootstrapRequest
            Import(
                string projectRoot,
                string localRoot,
                string requestPath,
                IAgentRuntimeClock clock,
                AgentRuntimeHostIdentity identity,
                IAgentRendezvousFileProtection protection)
        {
            if (string.IsNullOrWhiteSpace(requestPath))
                return null;
            if (clock == null)
                throw new ArgumentNullException(nameof(clock));
            if (identity == null)
                throw new ArgumentNullException(nameof(identity));
            if ((identity.Qualification.RuntimeMode
                    != CF7Launcher.AgentRuntime.Contracts
                        .RuntimeMode.FormalRuntime
                    && identity.Qualification.RuntimeMode
                    != CF7Launcher.AgentRuntime.Contracts
                        .RuntimeMode.IsolatedCandidate)
                || string.IsNullOrWhiteSpace(
                    identity.Qualification.BuildIdentity)
                || string.IsNullOrWhiteSpace(
                    identity.Qualification.PayloadClosure))
            {
                throw new InvalidOperationException(
                    "unattended_bootstrap_requires_qualified_runtime");
            }

            string canonicalProjectRoot =
                Path.GetFullPath(projectRoot)
                    .TrimEnd(
                        Path.DirectorySeparatorChar,
                        Path.AltDirectorySeparatorChar);
            string runtimeRoot = Path.Combine(
                Path.GetFullPath(localRoot),
                "CF7FlashNight",
                "agent-runtime",
                "v1",
                AgentRendezvousPath.ComputeProjectRootHash(
                    canonicalProjectRoot));
            string canonicalRequestPath =
                Path.GetFullPath(requestPath);
            string requestDirectory = Path.Combine(
                runtimeRoot,
                "unattended",
                "bootstrap");
            if (!IsContainedPath(
                    requestDirectory,
                    canonicalRequestPath)
                || !string.Equals(
                    Path.GetExtension(canonicalRequestPath),
                    ".json",
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException(
                    "unattended_bootstrap_path_invalid");
            }

            protection ??=
                new WindowsCurrentUserRendezvousFileProtection();
            Directory.CreateDirectory(requestDirectory);
            protection.ProtectDirectory(requestDirectory);
            TrustedUnattendedRuntimeBundle
                .RejectReparseChain(
                    requestDirectory,
                    runtimeRoot);

            RequestDocument document;
            try
            {
                FileAttributes attributes =
                    File.GetAttributes(canonicalRequestPath);
                if ((attributes
                        & FileAttributes.ReparsePoint) != 0
                    || (attributes
                        & FileAttributes.Directory) != 0)
                {
                    throw new InvalidDataException(
                        "unattended_bootstrap_not_regular");
                }
                using var stream = new FileStream(
                    canonicalRequestPath,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.None,
                    4096,
                    FileOptions.SequentialScan);
                if (stream.Length <= 0
                    || stream.Length > MaximumRequestBytes)
                {
                    throw new InvalidDataException(
                        "unattended_bootstrap_size_invalid");
                }
                byte[] payload =
                    new byte[checked((int)stream.Length)];
                stream.ReadExactly(payload);
                document = ParseDocument(payload);
            }
            finally
            {
                try
                {
                    File.Delete(canonicalRequestPath);
                }
                catch
                {
                }
            }

            string expectedRequestPath = RequestPathFor(
                runtimeRoot,
                document.ClientInstanceId);
            if (!string.Equals(
                    canonicalRequestPath,
                    expectedRequestPath,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException(
                    "unattended_bootstrap_path_invalid");
            }
            ValidateSlot(document.Slot);
            RequireOpaque(
                document.ClientInstanceId,
                nameof(document.ClientInstanceId));
            RequireOpaque(
                document.RequestNonce,
                nameof(document.RequestNonce));
            if (!string.Equals(
                    document.RunnerPolicyId,
                    RunnerPolicyId,
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "unattended_runner_policy_invalid");
            }
            RequireSha256(
                document.RunnerExecutableSha256,
                nameof(document.RunnerExecutableSha256));
            string expectedRuntimeMode =
                RuntimeModeWireName(
                    identity.Qualification.RuntimeMode);
            if (!string.Equals(
                    document.RuntimeMode,
                    expectedRuntimeMode,
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "unattended_runtime_mode_mismatch");
            }
            TrustedUnattendedRuntimeBundle selectedBundle =
                TrustedUnattendedRuntimeBundle
                    .VerifySelectedProcess(
                        document.RunnerExecutablePath);
            if (!string.Equals(
                    selectedBundle.ProjectRoot,
                    canonicalProjectRoot,
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    selectedBundle.RuntimeMode,
                    document.RuntimeMode,
                    StringComparison.Ordinal)
                || !string.Equals(
                    selectedBundle.BuildIdentity,
                    document.BuildIdentity,
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    selectedBundle.PayloadClosure,
                    document.PayloadClosure,
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    selectedBundle.CoreSha256,
                    document.RunnerExecutableSha256,
                    StringComparison.OrdinalIgnoreCase)
                || selectedBundle.CoreSize
                    != document.RunnerExecutableSize)
            {
                throw new InvalidDataException(
                    "unattended_runner_payload_mismatch");
            }
            Process runnerProcess =
                ValidateRunnerProcess(document);
            if (!LauncherUnattendedCredentialBootstrap
                    .DirectParentMatchesRunner(
                    document.RunnerProcessId))
            {
                runnerProcess.Dispose();
                throw new InvalidDataException(
                    "unattended_runner_not_direct_parent");
            }
            string actualRuntimePath =
                Path.GetFullPath(
                    Environment.ProcessPath);
            if (!string.Equals(
                    Path.GetFullPath(
                        document.RuntimeExecutablePath),
                    actualRuntimePath,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException(
                    "unattended_runtime_path_mismatch");
            }
            RequireSha256(
                document.BuildIdentity,
                nameof(document.BuildIdentity));
            RequireSha256(
                document.PayloadClosure,
                nameof(document.PayloadClosure));

            string expectedSavePath =
                CanonicalSavePathFor(
                    canonicalProjectRoot,
                    document.Slot);
            if (!string.Equals(
                    Path.GetFullPath(
                        document.CanonicalSavePath),
                    expectedSavePath,
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    document.BuildIdentity,
                    identity.Qualification.BuildIdentity,
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    document.PayloadClosure,
                    identity.Qualification.PayloadClosure,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException(
                    "unattended_bootstrap_identity_mismatch");
            }

            DateTimeOffset issuedUtc =
                ParseUtc(document.IssuedUtc, "issuedUtc");
            DateTimeOffset expiresUtc =
                ParseUtc(document.ExpiresUtc, "expiresUtc");
            DateTimeOffset now =
                clock.UtcNow.ToUniversalTime();
            TimeSpan remaining = expiresUtc - now;
            if (issuedUtc > now.Add(MaximumClockSkew)
                || expiresUtc <= issuedUtc
                || expiresUtc - issuedUtc
                    > MaximumLifetime
                || remaining <= TimeSpan.Zero
                || remaining > MaximumLifetime)
            {
                throw new InvalidDataException(
                    "unattended_bootstrap_expired");
            }
            long deadline = checked(
                clock.MonotonicMilliseconds
                + (long)remaining.TotalMilliseconds);
            try
            {
                ConsumeRequestNonce(
                    runtimeRoot,
                    document.RequestNonce,
                    protection);
                return new LauncherUnattendedBootstrapRequest(
                    canonicalProjectRoot,
                    runtimeRoot,
                    identity.Qualification.RuntimeMode,
                    document,
                    runnerProcess,
                    deadline,
                    expiresUtc);
            }
            catch
            {
                runnerProcess.Dispose();
                throw;
            }
        }

        public static string RequestPath(
            string projectRoot,
            string localRoot,
            string clientInstanceId)
        {
            string runtimeRoot = Path.Combine(
                Path.GetFullPath(localRoot),
                "CF7FlashNight",
                "agent-runtime",
                "v1",
                AgentRendezvousPath.ComputeProjectRootHash(
                    projectRoot));
            return RequestPathFor(
                runtimeRoot,
                clientInstanceId);
        }

        public static string CanonicalSavePathFor(
            string projectRoot,
            string slot)
        {
            ValidateSlot(slot);
            return Path.GetFullPath(
                Path.Combine(
                    projectRoot,
                    "saves",
                    slot + ".json"));
        }

        private static string RequestPathFor(
            string runtimeRoot,
            string clientInstanceId)
        {
            RequireOpaque(
                clientInstanceId,
                nameof(clientInstanceId));
            return Path.GetFullPath(
                Path.Combine(
                    runtimeRoot,
                    "unattended",
                    "bootstrap",
                    HashedFileName(clientInstanceId)));
        }

        private static string CredentialPathFor(
            string runtimeRoot,
            string clientInstanceId)
        {
            return Path.GetFullPath(
                Path.Combine(
                    runtimeRoot,
                    "unattended",
                    "credentials",
                    HashedFileName(clientInstanceId)));
        }

        private static string HashedFileName(string value)
        {
            byte[] digest = SHA256.HashData(
                Encoding.UTF8.GetBytes(value));
            return Convert.ToHexString(digest)
                .ToLowerInvariant()
                + ".json";
        }

        private static RequestDocument ParseDocument(
            byte[] payload)
        {
            try
            {
                using JsonDocument parsed =
                    JsonDocument.Parse(
                        payload,
                        new JsonDocumentOptions
                        {
                            AllowTrailingCommas = false,
                            CommentHandling =
                                JsonCommentHandling.Disallow,
                            MaxDepth = 8
                        });
                if (parsed.RootElement.ValueKind
                    != JsonValueKind.Object)
                {
                    throw new InvalidDataException(
                        "unattended_bootstrap_invalid");
                }
                var seen = new HashSet<string>(
                    StringComparer.Ordinal);
                foreach (JsonProperty property
                    in parsed.RootElement
                        .EnumerateObject())
                {
                    if (!PropertyNames.Contains(
                            property.Name)
                        || !seen.Add(property.Name))
                    {
                        throw new InvalidDataException(
                            "unattended_bootstrap_invalid");
                    }
                }
                if (!seen.SetEquals(PropertyNames))
                {
                    throw new InvalidDataException(
                        "unattended_bootstrap_invalid");
                }
                RequestDocument document =
                    JsonSerializer
                        .Deserialize<RequestDocument>(
                            payload,
                            JsonOptions);
                if (document == null
                    || !string.Equals(
                        document.Schema,
                        Schema,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        document.Issuer,
                        Issuer,
                        StringComparison.Ordinal)
                    || (document.RuntimeMode
                            != "formal_runtime"
                        && document.RuntimeMode
                            != "isolated_candidate"))
                {
                    throw new InvalidDataException(
                        "unattended_bootstrap_invalid");
                }
                return document;
            }
            catch (JsonException exception)
            {
                throw new InvalidDataException(
                    "unattended_bootstrap_invalid",
                    exception);
            }
        }

        private static string RuntimeModeWireName(
            CF7Launcher.AgentRuntime.Contracts.RuntimeMode
                mode)
        {
            return mode switch
            {
                CF7Launcher.AgentRuntime.Contracts
                    .RuntimeMode.FormalRuntime =>
                        "formal_runtime",
                CF7Launcher.AgentRuntime.Contracts
                    .RuntimeMode.IsolatedCandidate =>
                        "isolated_candidate",
                _ => throw new InvalidDataException(
                    "unattended_runtime_mode_invalid")
            };
        }

        private static Process ValidateRunnerProcess(
            RequestDocument document)
        {
            if (document.RunnerProcessId == 0
                || document.RunnerProcessId
                    > int.MaxValue)
            {
                throw new InvalidDataException(
                    "unattended_runner_process_invalid");
            }
            DateTimeOffset expectedStart =
                ParseUtc(
                    document.RunnerProcessStartTimeUtc,
                    "runnerProcessStartTimeUtc");
            string expectedPath = Path.GetFullPath(
                document.RunnerExecutablePath);
            Process process =
                Process.GetProcessById(
                    checked((int)document.RunnerProcessId));
            try
            {
                process.Refresh();
                FileInfo runnerFile =
                    new FileInfo(expectedPath);
                if (process.HasExited
                    || new DateTimeOffset(
                        process.StartTime.ToUniversalTime())
                        .UtcDateTime.Ticks
                        != expectedStart.UtcDateTime.Ticks
                    || !string.Equals(
                        Path.GetFullPath(
                            process.MainModule.FileName),
                        expectedPath,
                        StringComparison.OrdinalIgnoreCase)
                    || runnerFile.Length
                        != document.RunnerExecutableSize
                    || !string.Equals(
                        ComputeFileSha256(expectedPath),
                        document.RunnerExecutableSha256,
                        StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException(
                        "unattended_runner_process_mismatch");
                }
                return process;
            }
            catch
            {
                process.Dispose();
                throw;
            }
        }

        private static void ConsumeRequestNonce(
            string runtimeRoot,
            string requestNonce,
            IAgentRendezvousFileProtection protection)
        {
            string directory = Path.Combine(
                runtimeRoot,
                "unattended",
                "consumed");
            Directory.CreateDirectory(directory);
            protection.ProtectDirectory(directory);
            TrustedUnattendedRuntimeBundle
                .RejectReparseChain(
                    directory,
                    runtimeRoot);
            string tombstone = Path.Combine(
                directory,
                HashedFileName(requestNonce)
                    + ".used");
            using var stream = new FileStream(
                tombstone,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                1,
                FileOptions.WriteThrough);
            protection.ProtectFile(tombstone);
            stream.WriteByte(1);
            stream.Flush(true);
        }

        private static string ComputeFileSha256(
            string path)
        {
            using FileStream stream =
                new FileStream(
                    path,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.Read | FileShare.Delete);
            return Convert.ToHexString(
                SHA256.HashData(stream))
                .ToLowerInvariant();
        }

        private static DateTimeOffset ParseUtc(
            string value,
            string field)
        {
            if (string.IsNullOrWhiteSpace(value)
                || !(value.EndsWith(
                        "Z",
                        StringComparison.Ordinal)
                    || value.EndsWith(
                        "+00:00",
                        StringComparison.Ordinal))
                || !DateTimeOffset.TryParseExact(
                    value,
                    "O",
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.RoundtripKind,
                    out DateTimeOffset result)
                || result.Offset != TimeSpan.Zero)
            {
                throw new InvalidDataException(
                    field + "_invalid");
            }
            return result.ToUniversalTime();
        }

        private static bool IsContainedPath(
            string directory,
            string path)
        {
            string parent = Path.GetFullPath(directory)
                .TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar);
            string candidate = Path.GetFullPath(path);
            return candidate.StartsWith(
                parent + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase);
        }

        internal static void ValidateSlot(string slot)
        {
            try
            {
                TrustedUnattendedRunnerOptions.Parse(
                    new[]
                    {
                        "--agent-unattended-runner",
                        "--adapter",
                        "jsonl",
                        "--slot",
                        slot
                    });
            }
            catch (InvalidDataException)
            {
                throw new InvalidDataException(
                    "unattended_slot_invalid");
            }
        }

        private static void RequireOpaque(
            string value,
            string field)
        {
            if (string.IsNullOrWhiteSpace(value)
                || value.Length
                    < AgentProtocolV1
                        .MinimumOpaqueIdCharacters
                || value.Length
                    > AgentProtocolV1
                        .MaximumOpaqueIdCharacters
                || value.Any(character =>
                    !((character >= 'a'
                            && character <= 'z')
                        || (character >= 'A'
                            && character <= 'Z')
                        || (character >= '0'
                            && character <= '9')
                        || character == '-'
                        || character == '_')))
            {
                throw new InvalidDataException(
                    field + "_invalid");
            }
        }

        private static void RequireSha256(
            string value,
            string field)
        {
            if (value == null
                || value.Length != 64
                || value.Any(character =>
                    !((character >= '0'
                            && character <= '9')
                        || (character >= 'a'
                            && character <= 'f')
                        || (character >= 'A'
                            && character <= 'F'))))
            {
                throw new InvalidDataException(
                    field + "_invalid");
            }
        }

        private sealed class RequestDocument
        {
            public string Schema { get; init; }
            public string Issuer { get; init; }
            public string RuntimeMode { get; init; }
            public string ClientInstanceId { get; init; }
            public string RunnerPolicyId { get; init; }
            public uint RunnerProcessId { get; init; }
            public string RunnerProcessStartTimeUtc
            {
                get;
                init;
            }
            public string RunnerExecutablePath { get; init; }
            public string RunnerExecutableSha256 { get; init; }
            public long RunnerExecutableSize { get; init; }
            public string RuntimeExecutablePath { get; init; }
            public string Slot { get; init; }
            public string CanonicalSavePath { get; init; }
            public string BuildIdentity { get; init; }
            public string PayloadClosure { get; init; }
            public string IssuedUtc { get; init; }
            public string ExpiresUtc { get; init; }
            public string RequestNonce { get; init; }
        }
    }

    /// <summary>
    /// Production-only unattended issuer and live binding authority. It
    /// publishes a one-shot proof only after the requested Flash attempt and
    /// its runtime-owned surface are observed by the Host registry.
    /// </summary>
    internal sealed class LauncherUnattendedCredentialBootstrap
        : IUnattendedCredentialBindingAuthority,
          IDisposable
    {
        private const string CredentialSchema =
            "cf7.agent_runtime.trusted_unattended_credential.v2";
        private const int MaximumCredentialBytes =
            64 * 1024;
        private static readonly HashSet<string>
            FixedCapabilities =
                new HashSet<string>(
                    new[]
                    {
                        AgentCapabilitiesV1.ListWindows,
                        AgentCapabilitiesV1.GetWindow,
                        AgentCapabilitiesV1.GetWindowState,
                        AgentCapabilitiesV1.Click,
                        AgentCapabilitiesV1.PressKey,
                        AgentCapabilitiesV1.TypeText,
                        AgentCapabilitiesV1.Scroll,
                        AgentCapabilitiesV1.Drag,
                        AgentCapabilitiesV1.ActivateWindow,
                        AgentCapabilitiesV1.SessionStatus,
                        AgentCapabilitiesV1.SessionDiscover,
                        AgentCapabilitiesV1.SessionAttach,
                        AgentCapabilitiesV1.SessionDetach,
                        AgentCapabilitiesV1.SessionShutdown,
                        AgentCapabilitiesV1.LifecycleReveal,
                        AgentCapabilitiesV1.LifecycleCancel,
                        AgentCapabilitiesV1.PanelOpen,
                        AgentCapabilitiesV1.LeaseAcquire,
                        AgentCapabilitiesV1.LeaseRenew,
                        AgentCapabilitiesV1.LeaseRelease,
                        AgentCapabilitiesV1
                            .ObservationGrantManage,
                        AgentCapabilitiesV1
                            .ObservationCapture,
                        AgentCapabilitiesV1.ContentRead,
                        AgentCapabilitiesV1.ActionGet,
                        "observe:"
                            + ObservationDataScopesV1
                                .WindowMetadata,
                        "observe:"
                            + ObservationDataScopesV1.Pixels,
                        "observe:"
                            + ObservationDataScopesV1.Focus,
                        "observe:"
                            + ObservationDataScopesV1.Selection
                    },
                    StringComparer.Ordinal);
        private static readonly JsonSerializerOptions
            CredentialJsonOptions =
                new JsonSerializerOptions
                {
                    PropertyNamingPolicy =
                        JsonNamingPolicy.CamelCase,
                    WriteIndented = false,
                    MaxDepth = 8
                };

        private readonly object _sync = new object();
        private readonly LauncherUnattendedBootstrapRequest
            _request;
        private readonly IAgentRuntimeClock _clock;
        private readonly SessionSurfaceHostController
            _surfaces;
        private readonly IAgentRendezvousFileProtection
            _protection;
        private readonly Dictionary<
            string,
            UnattendedCredentialEvidence> _principals =
                new Dictionary<
                    string,
                    UnattendedCredentialEvidence>(
                        StringComparer.Ordinal);
        private UnattendedCredentialEvidence
            _publishedEvidence;
        private string _credentialProof;
        private string _issuerReceipt;
        private bool _authorizationConsumed;
        private bool _disposed;

        public LauncherUnattendedCredentialBootstrap(
            LauncherUnattendedBootstrapRequest request,
            IAgentRuntimeClock clock,
            SessionSurfaceHostController surfaces,
            IAgentRendezvousFileProtection protection)
        {
            _request = request
                ?? throw new ArgumentNullException(
                    nameof(request));
            _clock = clock
                ?? throw new ArgumentNullException(
                    nameof(clock));
            _surfaces = surfaces
                ?? throw new ArgumentNullException(
                    nameof(surfaces));
            _protection = protection
                ?? new WindowsCurrentUserRendezvousFileProtection();
        }

        public string Slot => _request.Slot;

        public string CredentialPath =>
            _request.CredentialPath;

        public bool TryPublishObservedCredential(
            AgentConnectionAuthenticator authenticator,
            out string reasonCode)
        {
            if (authenticator == null)
                throw new ArgumentNullException(
                    nameof(authenticator));
            lock (_sync)
            {
                if (_disposed)
                {
                    reasonCode =
                        "unattended_bootstrap_disposed";
                    return false;
                }
                if (_publishedEvidence != null)
                {
                    reasonCode = null;
                    return true;
                }
                SessionSnapshot snapshot =
                    _surfaces.Snapshot;
                if (!TryCreateEvidence(
                        snapshot,
                        out UnattendedCredentialEvidence
                            evidence,
                        out reasonCode))
                {
                    return false;
                }
                string proof =
                    OpaqueIdGenerator.Create(
                        "credential_proof");
                string receipt =
                    OpaqueIdGenerator.Create(
                        "unattended");
                _publishedEvidence = evidence;
                _credentialProof = proof;
                _issuerReceipt = receipt;

                try
                {
                    authenticator.RegisterUnattendedProof(
                        proof,
                        evidence,
                        receipt);
                    WriteCredential(
                        evidence,
                        receipt,
                        proof);
                    reasonCode = null;
                    return true;
                }
                catch
                {
                    authenticator.RemoveUnattendedProof(
                        _request.ClientInstanceId);
                    _publishedEvidence = null;
                    _credentialProof = null;
                    _issuerReceipt = null;
                    DeleteCredentialFile();
                    reasonCode =
                        "unattended_credential_publish_failed";
                    return false;
                }
            }
        }

        public bool TryAuthorizeEvidence(
            UnattendedCredentialEvidence evidence,
            AgentProcessSecurityIdentity peerIdentity,
            out string reasonCode)
        {
            UnattendedCredentialEvidence published;
            lock (_sync)
            {
                if (_disposed
                    || _authorizationConsumed
                    || _publishedEvidence == null)
                {
                    reasonCode =
                        "unattended_evidence_unavailable";
                    return false;
                }
                published = _publishedEvidence;
            }
            if (!EvidenceMatchesPublished(
                    evidence,
                    published)
                || !PeerMatchesEvidence(
                    peerIdentity,
                    evidence)
                || !CurrentSnapshotMatches(evidence))
            {
                reasonCode =
                    "unattended_binding_mismatch";
                return false;
            }
            try
            {
                DeleteCredentialFile();
            }
            catch
            {
                reasonCode =
                    "unattended_credential_consume_failed";
                return false;
            }
            lock (_sync)
            {
                if (_disposed
                    || _authorizationConsumed)
                {
                    reasonCode =
                        "unattended_evidence_unavailable";
                    return false;
                }
                _authorizationConsumed = true;
            }
            reasonCode = null;
            return true;
        }

        public void BindPrincipal(
            PrincipalCredential principal,
            UnattendedCredentialEvidence evidence)
        {
            if (principal == null)
                throw new ArgumentNullException(
                    nameof(principal));
            if (principal.PrincipalKind
                    != AgentPrincipalKind
                        .UnattendedTestRunner
                || principal.SessionMode
                    != AgentSessionMode.UnattendedTest
                || !EvidenceMatchesPublished(
                    evidence,
                    _publishedEvidence)
                || !CurrentSnapshotMatches(evidence))
            {
                throw new InvalidOperationException(
                    "unattended_binding_mismatch");
            }
            lock (_sync)
            {
                if (_disposed
                    || !_authorizationConsumed
                    || _principals.Count != 0)
                {
                    throw new InvalidOperationException(
                        "unattended_binding_unavailable");
                }
                _principals.Add(
                    principal.CredentialId,
                    evidence);
                _credentialProof = null;
                _issuerReceipt = null;
            }
        }

        public bool IsPrincipalAuthorized(
            PrincipalCredential principal)
        {
            if (principal == null
                || principal.PrincipalKind
                    != AgentPrincipalKind
                        .UnattendedTestRunner
                || principal.SessionMode
                    != AgentSessionMode.UnattendedTest
                || principal.State
                    != CredentialState.Active)
            {
                return false;
            }
            UnattendedCredentialEvidence evidence;
            lock (_sync)
            {
                if (_disposed
                    || !_principals.TryGetValue(
                        principal.CredentialId,
                        out evidence))
                {
                    return false;
                }
            }
            return string.Equals(
                    principal.ClientInstanceId,
                    evidence.ClientInstanceId,
                    StringComparison.Ordinal)
                && string.Equals(
                    principal.BuildIdentity,
                    evidence.BuildIdentity,
                    StringComparison.Ordinal)
                && string.Equals(
                    principal.AttemptId,
                    evidence.AttemptId,
                    StringComparison.Ordinal)
                && string.Equals(
                    principal.Slot,
                    evidence.Slot,
                    StringComparison.Ordinal)
                && CurrentSnapshotMatches(evidence);
        }

        public ReadOnlyCollection<string>
            TakeInvalidPrincipalCredentialIds()
        {
            KeyValuePair<
                string,
                UnattendedCredentialEvidence>[] candidates;
            lock (_sync)
            {
                candidates = _principals.ToArray();
            }
            string[] invalid = candidates
                .Where(pair =>
                    !CurrentSnapshotMatches(pair.Value))
                .Select(pair => pair.Key)
                .ToArray();
            lock (_sync)
            {
                foreach (string credentialId in invalid)
                    _principals.Remove(credentialId);
            }
            return Array.AsReadOnly(invalid);
        }

        public void EnforceCurrentBinding(
            AgentConnectionAuthenticator authenticator,
            AgentRuntimeRevocationCoordinator revocations)
        {
            if (authenticator == null)
                throw new ArgumentNullException(
                    nameof(authenticator));
            if (revocations == null)
                throw new ArgumentNullException(
                    nameof(revocations));

            UnattendedCredentialEvidence pending;
            lock (_sync)
            {
                pending = !_authorizationConsumed
                    ? _publishedEvidence
                    : null;
            }
            if (pending != null
                && !CurrentSnapshotMatches(pending))
            {
                authenticator.RemoveUnattendedProof(
                    _request.ClientInstanceId);
                DeleteCredentialFile();
                lock (_sync)
                {
                    _authorizationConsumed = true;
                }
            }

            foreach (string credentialId
                in TakeInvalidPrincipalCredentialIds())
            {
                revocations.RevokeCredential(
                    credentialId,
                    "unattended_binding_changed");
            }
        }

        public void Dispose()
        {
            lock (_sync)
            {
                if (_disposed)
                    return;
                _disposed = true;
                _principals.Clear();
                _publishedEvidence = null;
                _credentialProof = null;
                _issuerReceipt = null;
            }
            DeleteCredentialFile();
            _request.RunnerProcess.Dispose();
        }

        private bool TryCreateEvidence(
            SessionSnapshot snapshot,
            out UnattendedCredentialEvidence evidence,
            out string reasonCode)
        {
            evidence = null;
            if (!SnapshotMatchesRequest(snapshot))
            {
                reasonCode =
                    "unattended_attempt_not_observed";
                return false;
            }
            string[] targets = snapshot.Surfaces
                .Where(surface =>
                    surface.SafetyKind
                        == AgentTargetSafetyKind.RuntimeOwned)
                .Select(surface => surface.TargetId)
                .Distinct(StringComparer.Ordinal)
                .OrderBy(
                    value => value,
                    StringComparer.Ordinal)
                .ToArray();
            if (!snapshot.Surfaces.Any(surface =>
                    surface.Kind == SurfaceKind.Flash
                    && surface.SafetyKind
                        == AgentTargetSafetyKind.RuntimeOwned)
                || targets.Length == 0)
            {
                reasonCode =
                    "unattended_flash_surface_not_observed";
                return false;
            }

            var sessionCapabilities =
                new HashSet<string>(
                    snapshot.Capabilities,
                    StringComparer.Ordinal);
            string[] capabilities =
                FixedCapabilities
                    .Where(capability =>
                        capability.StartsWith(
                            "observe:",
                            StringComparison.Ordinal)
                        || sessionCapabilities.Contains(
                            capability))
                    .OrderBy(
                        value => value,
                        StringComparer.Ordinal)
                    .ToArray();
            if (capabilities.Length == 0)
            {
                reasonCode =
                    "unattended_capability_scope_empty";
                return false;
            }
            evidence =
                new UnattendedCredentialEvidence
                {
                    ClientInstanceId =
                        _request.ClientInstanceId,
                    RunnerPolicyId =
                        _request.RunnerPolicy,
                    RunnerProcessId =
                        _request.RunnerProcessId,
                    RunnerProcessStartTimeUtc =
                        _request
                            .RunnerProcessStartTimeUtc,
                    RunnerExecutablePath =
                        _request.RunnerExecutablePath,
                    RunnerExecutableSha256 =
                        _request
                            .RunnerExecutableSha256,
                    RunnerExecutableSize =
                        _request.RunnerExecutableSize,
                    RuntimeExecutablePath =
                        _request.RuntimeExecutablePath,
                    RequestNonce =
                        _request.RequestNonce,
                    BuildIdentity =
                        _request.BuildIdentity,
                    PayloadClosure =
                        _request.PayloadClosure,
                    SessionId = snapshot.SessionId,
                    AttemptId = snapshot.AttemptId,
                    AttemptGeneration =
                        snapshot.AttemptGeneration
                            .GetValueOrDefault(),
                    Slot = _request.Slot,
                    CanonicalSavePath =
                        _request.CanonicalSavePath,
                    RunnerDeadlineMonotonic =
                        _request.DeadlineMonotonic,
                    AllowedCapabilities =
                        capabilities,
                    AllowedTargets = targets
                };
            reasonCode = null;
            return true;
        }

        private bool SnapshotMatchesRequest(
            SessionSnapshot snapshot)
        {
            return snapshot != null
                && snapshot.SessionMode
                    == SessionMode.UnattendedTest
                && snapshot.RuntimeQualification.RuntimeMode
                    == _request.RuntimeMode
                && string.Equals(
                    snapshot.RuntimeQualification
                        .BuildIdentity,
                    _request.BuildIdentity,
                    StringComparison.OrdinalIgnoreCase)
                && string.Equals(
                    snapshot.RuntimeQualification
                        .PayloadClosure,
                    _request.PayloadClosure,
                    StringComparison.OrdinalIgnoreCase)
                && string.Equals(
                    Path.GetFullPath(
                        snapshot.LauncherProcess
                            .ExecutablePath),
                    _request.RuntimeExecutablePath,
                    StringComparison.OrdinalIgnoreCase)
                && string.Equals(
                    snapshot.Slot,
                    _request.Slot,
                    StringComparison.Ordinal)
                && !string.IsNullOrWhiteSpace(
                    snapshot.AttemptId)
                && snapshot.AttemptGeneration
                    .GetValueOrDefault() != 0
                && snapshot.FlashProcess != null
                && !_request.RunnerProcess.HasExited
                && _clock.MonotonicMilliseconds
                    < _request.DeadlineMonotonic;
        }

        private bool CurrentSnapshotMatches(
            UnattendedCredentialEvidence evidence)
        {
            if (evidence == null
                || _clock.MonotonicMilliseconds
                    >= evidence.RunnerDeadlineMonotonic)
            {
                return false;
            }
            SessionSnapshot snapshot;
            try
            {
                snapshot = _surfaces.Snapshot;
            }
            catch
            {
                return false;
            }
            return SnapshotMatchesRequest(snapshot)
                && string.Equals(
                    snapshot.SessionId,
                    evidence.SessionId,
                    StringComparison.Ordinal)
                && string.Equals(
                    snapshot.AttemptId,
                    evidence.AttemptId,
                    StringComparison.Ordinal)
                && snapshot.AttemptGeneration
                    .GetValueOrDefault()
                    == evidence.AttemptGeneration
                && string.Equals(
                    evidence.CanonicalSavePath,
                    LauncherUnattendedBootstrapRequest
                        .CanonicalSavePathFor(
                            _request.ProjectRoot,
                            snapshot.Slot),
                    StringComparison.OrdinalIgnoreCase);
        }

        internal static bool EvidenceMatchesPublished(
            UnattendedCredentialEvidence evidence,
            UnattendedCredentialEvidence published)
        {
            if (evidence == null || published == null)
                return false;
            var allowedCapabilities =
                new HashSet<string>(
                    published.AllowedCapabilities
                        ?? Array.Empty<string>(),
                    StringComparer.Ordinal);
            string[] selected =
                (evidence.AllowedCapabilities
                    ?? Array.Empty<string>())
                .Distinct(StringComparer.Ordinal)
                .ToArray();
            return selected.Length > 0
                && selected.All(
                    allowedCapabilities.Contains)
                && SetEquals(
                    evidence.AllowedTargets,
                    published.AllowedTargets)
                && string.Equals(
                    evidence.ClientInstanceId,
                    published.ClientInstanceId,
                    StringComparison.Ordinal)
                && string.Equals(
                    evidence.RunnerPolicyId,
                    published.RunnerPolicyId,
                    StringComparison.Ordinal)
                && evidence.RunnerProcessId
                    == published.RunnerProcessId
                && evidence.RunnerProcessStartTimeUtc
                    .UtcDateTime.Ticks
                    == published
                        .RunnerProcessStartTimeUtc
                        .UtcDateTime.Ticks
                && string.Equals(
                    evidence.RunnerExecutablePath,
                    published.RunnerExecutablePath,
                    StringComparison.OrdinalIgnoreCase)
                && string.Equals(
                    evidence.RunnerExecutableSha256,
                    published.RunnerExecutableSha256,
                    StringComparison.Ordinal)
                && evidence.RunnerExecutableSize
                    == published.RunnerExecutableSize
                && string.Equals(
                    evidence.RuntimeExecutablePath,
                    published.RuntimeExecutablePath,
                    StringComparison.OrdinalIgnoreCase)
                && string.Equals(
                    evidence.RequestNonce,
                    published.RequestNonce,
                    StringComparison.Ordinal)
                && string.Equals(
                    evidence.BuildIdentity,
                    published.BuildIdentity,
                    StringComparison.Ordinal)
                && string.Equals(
                    evidence.PayloadClosure,
                    published.PayloadClosure,
                    StringComparison.Ordinal)
                && string.Equals(
                    evidence.SessionId,
                    published.SessionId,
                    StringComparison.Ordinal)
                && string.Equals(
                    evidence.AttemptId,
                    published.AttemptId,
                    StringComparison.Ordinal)
                && evidence.AttemptGeneration
                    == published.AttemptGeneration
                && string.Equals(
                    evidence.Slot,
                    published.Slot,
                    StringComparison.Ordinal)
                && string.Equals(
                    evidence.CanonicalSavePath,
                    published.CanonicalSavePath,
                    StringComparison.OrdinalIgnoreCase)
                && evidence.RunnerDeadlineMonotonic
                    == published.RunnerDeadlineMonotonic;
        }

        internal static bool PeerMatchesEvidence(
            AgentProcessSecurityIdentity peerIdentity,
            UnattendedCredentialEvidence evidence)
        {
            return peerIdentity != null
                && evidence != null
                && peerIdentity.ProcessId
                    == evidence.RunnerProcessId
                && peerIdentity.ProcessStartTimeUtc
                    .UtcDateTime.Ticks
                    == evidence.RunnerProcessStartTimeUtc
                        .UtcDateTime.Ticks
                && string.Equals(
                    Path.GetFullPath(
                        peerIdentity.ExecutablePath
                            ?? string.Empty),
                    Path.GetFullPath(
                        evidence.RunnerExecutablePath),
                    StringComparison.OrdinalIgnoreCase)
                && string.Equals(
                    peerIdentity.ExecutableSha256,
                    evidence.RunnerExecutableSha256,
                    StringComparison.OrdinalIgnoreCase)
                && !HasRunnerExited(evidence);
        }

        private static bool HasRunnerExited(
            UnattendedCredentialEvidence evidence)
        {
            try
            {
                using Process process =
                    Process.GetProcessById(
                        checked((int)evidence
                            .RunnerProcessId));
                return process.HasExited
                    || process.StartTime
                        .ToUniversalTime()
                        .Ticks
                        != evidence
                            .RunnerProcessStartTimeUtc
                            .UtcDateTime.Ticks;
            }
            catch
            {
                return true;
            }
        }

        internal static bool DirectParentMatchesRunner(
            uint runnerProcessId,
            Func<uint> parentProcessIdProbe = null)
        {
            if (runnerProcessId == 0)
                return false;
            uint directParent;
            try
            {
                directParent = parentProcessIdProbe != null
                    ? parentProcessIdProbe()
                    : GetCurrentDirectParentProcessId();
            }
            catch
            {
                return false;
            }
            return directParent == runnerProcessId;
        }

        private static uint GetCurrentDirectParentProcessId()
        {
            using Process current =
                Process.GetCurrentProcess();
            int status = NtQueryInformationProcess(
                current.Handle,
                0,
                out ProcessBasicInformation information,
                Marshal.SizeOf<ProcessBasicInformation>(),
                out _);
            if (status != 0
                || information
                    .InheritedFromUniqueProcessId
                    == IntPtr.Zero)
            {
                throw new InvalidOperationException(
                    "unattended_parent_process_unavailable");
            }
            long value = information
                .InheritedFromUniqueProcessId
                .ToInt64();
            if (value <= 0 || value > uint.MaxValue)
            {
                throw new InvalidOperationException(
                    "unattended_parent_process_invalid");
            }
            return checked((uint)value);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessBasicInformation
        {
            public IntPtr Reserved1;
            public IntPtr PebBaseAddress;
            public IntPtr Reserved2_0;
            public IntPtr Reserved2_1;
            public IntPtr UniqueProcessId;
            public IntPtr InheritedFromUniqueProcessId;
        }

        [DllImport("ntdll.dll")]
        private static extern int NtQueryInformationProcess(
            IntPtr processHandle,
            int processInformationClass,
            out ProcessBasicInformation processInformation,
            int processInformationLength,
            out int returnLength);

        private static bool SetEquals(
            IEnumerable<string> left,
            IEnumerable<string> right)
        {
            return new HashSet<string>(
                    left ?? Array.Empty<string>(),
                    StringComparer.Ordinal)
                .SetEquals(
                    right ?? Array.Empty<string>());
        }

        private void WriteCredential(
            UnattendedCredentialEvidence evidence,
            string issuerReceipt,
            string credentialProof)
        {
            string directory = Path.GetDirectoryName(
                _request.CredentialPath);
            Directory.CreateDirectory(directory);
            _protection.ProtectDirectory(directory);
            TrustedUnattendedRuntimeBundle
                .RejectReparseChain(
                    directory,
                    _request.RuntimeRoot);
            var document =
                new CredentialDocument
                {
                    Schema = CredentialSchema,
                    ClientInstanceId =
                        evidence.ClientInstanceId,
                    RuntimeMode =
                        _request.RuntimeModeName,
                    RunnerPolicyId =
                        evidence.RunnerPolicyId,
                    RunnerProcessId =
                        evidence.RunnerProcessId,
                    RunnerProcessStartTimeUtc =
                        evidence
                            .RunnerProcessStartTimeUtc
                            .ToUniversalTime()
                            .ToString(
                                "O",
                                CultureInfo
                                    .InvariantCulture),
                    RunnerExecutablePath =
                        evidence.RunnerExecutablePath,
                    RunnerExecutableSha256 =
                        evidence
                            .RunnerExecutableSha256,
                    RunnerExecutableSize =
                        evidence.RunnerExecutableSize,
                    RuntimeExecutablePath =
                        evidence.RuntimeExecutablePath,
                    RequestNonce =
                        evidence.RequestNonce,
                    IssuerReceipt = issuerReceipt,
                    CredentialProof = credentialProof,
                    SessionId = evidence.SessionId,
                    AttemptId = evidence.AttemptId,
                    AttemptGeneration =
                        evidence.AttemptGeneration,
                    Slot = evidence.Slot,
                    CanonicalSavePath =
                        evidence.CanonicalSavePath,
                    BuildIdentity =
                        evidence.BuildIdentity,
                    PayloadClosure =
                        evidence.PayloadClosure,
                    AllowedCapabilities =
                        evidence.AllowedCapabilities
                            .OrderBy(
                                value => value,
                                StringComparer.Ordinal)
                            .ToArray(),
                    AllowedTargets =
                        evidence.AllowedTargets
                            .OrderBy(
                                value => value,
                                StringComparer.Ordinal)
                            .ToArray(),
                    IssuedUtc = _clock.UtcNow
                        .ToUniversalTime()
                        .ToString(
                            "O",
                            CultureInfo.InvariantCulture),
                    ExpiresUtc = _request.ExpiresUtc
                        .ToUniversalTime()
                        .ToString(
                            "O",
                            CultureInfo.InvariantCulture)
                };
            byte[] payload =
                JsonSerializer.SerializeToUtf8Bytes(
                    document,
                    CredentialJsonOptions);
            if (payload.Length <= 0
                || payload.Length
                    > MaximumCredentialBytes)
            {
                throw new InvalidOperationException(
                    "unattended_credential_size_invalid");
            }
            string temporaryPath =
                _request.CredentialPath
                + "."
                + Guid.NewGuid().ToString("N")
                + ".tmp";
            try
            {
                using (var stream = new FileStream(
                    temporaryPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None,
                    4096,
                    FileOptions.WriteThrough))
                {
                    _protection.ProtectFile(
                        temporaryPath);
                    stream.Write(
                        payload,
                        0,
                        payload.Length);
                    stream.Flush(true);
                }
                File.Move(
                    temporaryPath,
                    _request.CredentialPath,
                    false);
                _protection.ProtectFile(
                    _request.CredentialPath);
            }
            finally
            {
                if (File.Exists(temporaryPath))
                    File.Delete(temporaryPath);
            }
        }

        private void DeleteCredentialFile()
        {
            if (File.Exists(_request.CredentialPath))
                File.Delete(_request.CredentialPath);
        }

        private sealed class CredentialDocument
        {
            public string Schema { get; init; }
            public string ClientInstanceId { get; init; }
            public string RuntimeMode { get; init; }
            public string RunnerPolicyId { get; init; }
            public uint RunnerProcessId { get; init; }
            public string RunnerProcessStartTimeUtc
            {
                get;
                init;
            }
            public string RunnerExecutablePath { get; init; }
            public string RunnerExecutableSha256 { get; init; }
            public long RunnerExecutableSize { get; init; }
            public string RuntimeExecutablePath { get; init; }
            public string RequestNonce { get; init; }
            public string IssuerReceipt { get; init; }
            public string CredentialProof { get; init; }
            public string SessionId { get; init; }
            public string AttemptId { get; init; }
            public ulong AttemptGeneration { get; init; }
            public string Slot { get; init; }
            public string CanonicalSavePath { get; init; }
            public string BuildIdentity { get; init; }
            public string PayloadClosure { get; init; }
            public string[] AllowedCapabilities { get; init; }
            public string[] AllowedTargets { get; init; }
            public string IssuedUtc { get; init; }
            public string ExpiresUtc { get; init; }
        }
    }
}
