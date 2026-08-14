using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Threading;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.TrustedRunner
{
    internal enum TrustedUnattendedAdapter
    {
        Jsonl,
        Mcp
    }

    internal sealed class TrustedUnattendedRunnerOptions
    {
        private const string A5MaterialShopSlot =
            "cf7_agent_a5_material_shop_run";
        private static readonly Regex CandidateLeafPattern =
            new Regex(
                "^c-[0-9a-f]{12}-[0-9a-f]{10}-[a-z0-9][a-z0-9-]{0,31}$",
                RegexOptions.CultureInvariant);
        private static readonly HashSet<string> AllowedSlots =
            new HashSet<string>(
                new[]
                {
                    "cf7_agent_equipment_tuning",
                    "cf7_agent_arena_calibration",
                    "cf7_agent_character_build",
                    "cf7_agent_loot_target_full_v1",
                    "cf7_agent_a5_material_shop_run"
                },
                StringComparer.Ordinal);

        private TrustedUnattendedRunnerOptions(
            TrustedUnattendedAdapter adapter,
            string slot)
        {
            Adapter = adapter;
            Slot = slot;
        }

        public TrustedUnattendedAdapter Adapter { get; }
        public string Slot { get; }

        public static bool IsRunnerInvocation(string[] args)
        {
            return args != null
                && args.Any(
                    argument => string.Equals(
                        argument,
                        "--agent-unattended-runner",
                        StringComparison.Ordinal));
        }

        public static TrustedUnattendedRunnerOptions Parse(
            string[] args)
        {
            if (args == null
                || args.Length != 5
                || !string.Equals(
                    args[0],
                    "--agent-unattended-runner",
                    StringComparison.Ordinal)
                || !string.Equals(
                    args[1],
                    "--adapter",
                    StringComparison.Ordinal)
                || !string.Equals(
                    args[3],
                    "--slot",
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "trusted_runner_arguments_invalid");
            }

            TrustedUnattendedAdapter adapter =
                args[2] switch
                {
                    "jsonl" =>
                        TrustedUnattendedAdapter.Jsonl,
                    "mcp" =>
                        TrustedUnattendedAdapter.Mcp,
                    _ => throw new InvalidDataException(
                        "trusted_runner_adapter_invalid")
                };
            if (!AllowedSlots.Contains(args[4]))
            {
                throw new InvalidDataException(
                    "trusted_runner_slot_invalid");
            }
            return new TrustedUnattendedRunnerOptions(
                adapter,
                args[4]);
        }

        internal static void ValidateRuntimeBinding(
            string slot,
            string runtimeMode,
            string deploymentRoot)
        {
            bool a5Slot = string.Equals(
                slot,
                A5MaterialShopSlot,
                StringComparison.Ordinal);
            string candidateLeaf =
                string.IsNullOrWhiteSpace(deploymentRoot)
                    ? string.Empty
                    : new DirectoryInfo(
                        Path.GetFullPath(deploymentRoot))
                        .Name;
            bool isolatedCandidate = string.Equals(
                runtimeMode,
                "isolated_candidate",
                StringComparison.Ordinal);
            bool formalRuntime = string.Equals(
                runtimeMode,
                "formal_runtime",
                StringComparison.Ordinal);
            bool reservedA5Candidate = isolatedCandidate
                && string.Equals(
                    candidateLeaf,
                    "a5",
                    StringComparison.OrdinalIgnoreCase);
            bool canonicalA5Candidate =
                reservedA5Candidate
                && string.Equals(
                    candidateLeaf,
                    "a5",
                    StringComparison.Ordinal);
            bool immutableCandidate = isolatedCandidate
                && CandidateLeafPattern.IsMatch(
                    candidateLeaf);
            bool valid = a5Slot
                ? formalRuntime
                    || canonicalA5Candidate
                : formalRuntime
                    || (immutableCandidate
                        && !reservedA5Candidate);
            if (!valid)
            {
                throw new InvalidDataException(
                    "trusted_runner_candidate_binding_invalid");
            }
        }
    }

    internal sealed class TrustedUnattendedBootstrapLease
        : IDisposable
    {
        private const string RequestSchema =
            "cf7.agent_runtime.trusted_unattended_bootstrap_request.v2";
        private const string CredentialSchema =
            "cf7.agent_runtime.trusted_unattended_credential.v2";
        internal const string RunnerPolicyId =
            "cf7_trusted_core_unattended_runner_v2";
        private const int MaximumCredentialBytes =
            64 * 1024;
        private static readonly TimeSpan MaximumLifetime =
            TimeSpan.FromMinutes(10);
        private static readonly TimeSpan
            DefaultCredentialAcquisitionPolicyMaximum =
                TimeSpan.FromSeconds(30);
        private static readonly TimeSpan
            A5CredentialAcquisitionPolicyMaximum =
                TimeSpan.FromSeconds(60);
        private static readonly UTF8Encoding StrictUtf8 =
            new UTF8Encoding(false, true);
        private static readonly JsonSerializerOptions JsonOptions =
            new JsonSerializerOptions
            {
                PropertyNamingPolicy =
                    JsonNamingPolicy.CamelCase,
                WriteIndented = false,
                UnmappedMemberHandling =
                    JsonUnmappedMemberHandling.Disallow,
                MaxDepth = 8
            };
        private static readonly HashSet<string>
            CredentialPropertyNames =
                new HashSet<string>(
                    new[]
                    {
                        "schema",
                        "clientInstanceId",
                        "runtimeMode",
                        "runnerPolicyId",
                        "runnerProcessId",
                        "runnerProcessStartTimeUtc",
                        "runnerExecutablePath",
                        "runnerExecutableSha256",
                        "runnerExecutableSize",
                        "runtimeExecutablePath",
                        "requestNonce",
                        "issuerReceipt",
                        "credentialProof",
                        "sessionId",
                        "attemptId",
                        "attemptGeneration",
                        "slot",
                        "canonicalSavePath",
                        "buildIdentity",
                        "payloadClosure",
                        "allowedCapabilities",
                        "allowedTargets",
                        "issuedUtc",
                        "expiresUtc"
                    },
                    StringComparer.Ordinal);
        private static readonly HashSet<string>
            AllowedCredentialCapabilities =
                new HashSet<string>(
                    AgentCapabilitiesV1.All.Concat(
                        new[]
                        {
                            "observe:window_metadata",
                            "observe:pixels",
                            "observe:accessibility",
                            "observe:focus",
                            "observe:selection",
                            "observation.persist",
                            "observation.export"
                        }),
                    StringComparer.Ordinal);

        private readonly TrustedUnattendedRuntimeBundle _bundle;
        private readonly byte[] _requestNonceBytes;
        private readonly string _runtimeRoot;
        private bool _disposed;

        private TrustedUnattendedBootstrapLease(
            TrustedUnattendedRuntimeBundle bundle,
            string slot,
            string clientInstanceId,
            string requestNonce,
            byte[] requestNonceBytes,
            DateTimeOffset expiresUtc,
            string requestPath,
            string credentialPath,
            string runtimeRoot)
        {
            _bundle = bundle;
            Slot = slot;
            ClientInstanceId = clientInstanceId;
            RequestNonce = requestNonce;
            _requestNonceBytes = requestNonceBytes;
            ExpiresUtc = expiresUtc;
            RequestPath = requestPath;
            CredentialPath = credentialPath;
            _runtimeRoot = runtimeRoot;
        }

        public string Slot { get; }
        public string ClientInstanceId { get; }
        public string RequestNonce { get; }
        public DateTimeOffset ExpiresUtc { get; }
        public string RequestPath { get; }
        public string CredentialPath { get; }

        internal TimeSpan CredentialAcquisitionPolicyMaximum =>
            CredentialAcquisitionPolicyMaximumForSlot(Slot);

        internal static TimeSpan
            CredentialAcquisitionPolicyMaximumForSlot(
                string slot)
        {
            return string.Equals(
                    slot,
                    "cf7_agent_a5_material_shop_run",
                    StringComparison.Ordinal)
                ? A5CredentialAcquisitionPolicyMaximum
                : DefaultCredentialAcquisitionPolicyMaximum;
        }

        public static TrustedUnattendedBootstrapLease Create(
            TrustedUnattendedRuntimeBundle bundle,
            string slot,
            DateTimeOffset? nowOverride = null,
            string localAppDataOverride = null,
            IAgentRendezvousFileProtection protection = null)
        {
            if (bundle == null)
                throw new ArgumentNullException(nameof(bundle));
            TrustedUnattendedRunnerOptions.Parse(
                new[]
                {
                    "--agent-unattended-runner",
                    "--adapter",
                    "jsonl",
                    "--slot",
                    slot
                });
            TrustedUnattendedRunnerOptions
                .ValidateRuntimeBinding(
                    slot,
                    bundle.RuntimeMode,
                    bundle.DeploymentRoot);

            DateTimeOffset issuedUtc =
                (nowOverride ?? DateTimeOffset.UtcNow)
                    .ToUniversalTime();
            DateTimeOffset expiresUtc =
                issuedUtc.Add(MaximumLifetime);
            byte[] nonceBytes =
                RandomNumberGenerator.GetBytes(32);
            string requestNonce =
                ToBase64Url(nonceBytes);
            string clientInstanceId =
                ToBase64Url(
                    RandomNumberGenerator.GetBytes(32));
            string runtimeRoot = RuntimeRoot(
                bundle.ProjectRoot,
                localAppDataOverride);
            string requestPath = Path.Combine(
                runtimeRoot,
                "unattended",
                "bootstrap",
                HashedFileName(clientInstanceId));
            string credentialPath = Path.Combine(
                runtimeRoot,
                "unattended",
                "credentials",
                HashedFileName(clientInstanceId));
            protection ??=
                new WindowsCurrentUserRendezvousFileProtection();

            string requestDirectory =
                Path.GetDirectoryName(requestPath);
            string credentialDirectory =
                Path.GetDirectoryName(credentialPath);
            Directory.CreateDirectory(requestDirectory);
            Directory.CreateDirectory(credentialDirectory);
            protection.ProtectDirectory(requestDirectory);
            protection.ProtectDirectory(credentialDirectory);
            TrustedUnattendedRuntimeBundle
                .RejectReparseChain(
                    requestDirectory,
                    runtimeRoot);
            TrustedUnattendedRuntimeBundle
                .RejectReparseChain(
                    credentialDirectory,
                    runtimeRoot);
            if (File.Exists(requestPath)
                || File.Exists(credentialPath))
            {
                CryptographicOperations.ZeroMemory(
                    nonceBytes);
                throw new IOException(
                    "trusted_runner_bootstrap_collision");
            }

            using Process current =
                Process.GetCurrentProcess();
            DateTimeOffset processStart =
                current.StartTime.ToUniversalTime();
            var document =
                new RequestDocument
                {
                    Schema = RequestSchema,
                    Issuer =
                        "core/trusted-unattended-runner",
                    RuntimeMode = bundle.RuntimeMode,
                    ClientInstanceId = clientInstanceId,
                    RunnerPolicyId = RunnerPolicyId,
                    RunnerProcessId =
                        checked((uint)Environment.ProcessId),
                    RunnerProcessStartTimeUtc =
                        processStart.ToString(
                            "O",
                            CultureInfo.InvariantCulture),
                    RunnerExecutablePath = bundle.CorePath,
                    RunnerExecutableSha256 =
                        bundle.CoreSha256,
                    RunnerExecutableSize = bundle.CoreSize,
                    RuntimeExecutablePath = bundle.CorePath,
                    Slot = slot,
                    CanonicalSavePath =
                        Path.GetFullPath(
                            Path.Combine(
                                bundle.ProjectRoot,
                                "saves",
                                slot + ".json")),
                    BuildIdentity = bundle.BuildIdentity,
                    PayloadClosure =
                        bundle.PayloadClosure,
                    IssuedUtc = issuedUtc.ToString(
                        "O",
                        CultureInfo.InvariantCulture),
                    ExpiresUtc = expiresUtc.ToString(
                        "O",
                        CultureInfo.InvariantCulture),
                    RequestNonce = requestNonce
                };
            byte[] payload =
                JsonSerializer.SerializeToUtf8Bytes(
                    document,
                    JsonOptions);
            try
            {
                WriteNewProtectedFile(
                    requestPath,
                    payload,
                    protection);
            }
            catch
            {
                CryptographicOperations.ZeroMemory(
                    nonceBytes);
                throw;
            }
            finally
            {
                CryptographicOperations.ZeroMemory(
                    payload);
            }

            return new TrustedUnattendedBootstrapLease(
                bundle,
                slot,
                clientInstanceId,
                requestNonce,
                nonceBytes,
                expiresUtc,
                requestPath,
                credentialPath,
                runtimeRoot);
        }

        public Process StartOwnedGuardian()
        {
            ThrowIfDisposed();
            var startInfo = new ProcessStartInfo
            {
                FileName = _bundle.CorePath,
                UseShellExecute = false,
                CreateNoWindow = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                WorkingDirectory =
                    _bundle.ProjectRoot
            };
            startInfo.ArgumentList.Add(
                "--project-root");
            startInfo.ArgumentList.Add(
                _bundle.ProjectRoot);
            startInfo.ArgumentList.Add(
                "--unattended-bootstrap-request");
            startInfo.ArgumentList.Add(
                RequestPath);

            Process process = Process.Start(startInfo);
            if (process == null)
                throw new InvalidOperationException(
                    "trusted_runner_guardian_start_failed");
            // The owned GUI process logs to its authenticated file sinks.
            // Native dependencies may still write directly to inherited
            // console handles, so drain both streams to preserve the
            // runner's JSONL/MCP stdout as a protocol-only channel.
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            return process;
        }

        public TrustedUnattendedCredential
            WaitForCredential(
                Process guardian,
                TimeSpan pollInterval,
                TimeSpan maximumWait,
                CancellationToken cancellationToken)
        {
            ThrowIfDisposed();
            if (guardian == null)
                throw new ArgumentNullException(
                    nameof(guardian));
            if (pollInterval <= TimeSpan.Zero
                || pollInterval
                    > TimeSpan.FromSeconds(1))
            {
                throw new ArgumentOutOfRangeException(
                    nameof(pollInterval));
            }
            if (maximumWait <= TimeSpan.Zero
                || maximumWait
                    > CredentialAcquisitionPolicyMaximum)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(maximumWait));
            }

            Stopwatch acquisition = Stopwatch.StartNew();
            while (DateTimeOffset.UtcNow < ExpiresUtc
                && acquisition.Elapsed < maximumWait)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (guardian.HasExited)
                {
                    throw new InvalidOperationException(
                        "trusted_runner_guardian_exited");
                }
                if (File.Exists(CredentialPath))
                {
                    return ImportCredential();
                }
                TimeSpan remaining =
                    maximumWait - acquisition.Elapsed;
                TimeSpan delay =
                    remaining < pollInterval
                        ? remaining
                        : pollInterval;
                if (delay <= TimeSpan.Zero)
                    break;
                if (cancellationToken.WaitHandle.WaitOne(delay))
                {
                    cancellationToken
                        .ThrowIfCancellationRequested();
                }
            }
            throw new TimeoutException(
                "trusted_runner_credential_timeout");
        }

        private TrustedUnattendedCredential
            ImportCredential()
        {
            TrustedUnattendedRuntimeBundle
                .RejectReparseChain(
                    CredentialPath,
                    _runtimeRoot);
            FileInfo info = new FileInfo(
                CredentialPath);
            if ((info.Attributes
                    & (FileAttributes.Directory
                        | FileAttributes.ReparsePoint)) != 0
                || info.Length <= 0
                || info.Length
                    > MaximumCredentialBytes)
            {
                throw new InvalidDataException(
                    "trusted_runner_credential_file_invalid");
            }

            byte[] payload;
            using (var stream = new FileStream(
                CredentialPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.None,
                4096,
                FileOptions.SequentialScan))
            {
                if (stream.Length != info.Length)
                    throw new InvalidDataException(
                        "trusted_runner_credential_changed");
                payload = new byte[
                    checked((int)stream.Length)];
                stream.ReadExactly(payload);
            }
            try
            {
                CredentialDocument document =
                    ParseCredential(payload);
                ValidateCredential(document);
                byte[] challenge =
                    FromBase64Url(
                        document.RequestNonce);
                try
                {
                    if (!CryptographicOperations
                        .FixedTimeEquals(
                            challenge,
                            _requestNonceBytes))
                    {
                        throw new InvalidDataException(
                            "trusted_runner_credential_nonce_mismatch");
                    }
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(
                        challenge);
                }
                try
                {
                    File.Delete(CredentialPath);
                }
                catch
                {
                }
                return new TrustedUnattendedCredential(
                    document.RuntimeMode,
                    document.CredentialProof,
                    document.AllowedCapabilities,
                    document.AllowedTargets,
                    document.SessionId,
                    document.AttemptId,
                    document.AttemptGeneration,
                    document.IssuerReceipt);
            }
            catch (JsonException exception)
            {
                throw new InvalidDataException(
                    "trusted_runner_credential_invalid",
                    exception);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(
                    payload);
            }
        }

        private static CredentialDocument
            ParseCredential(byte[] payload)
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
                    "trusted_runner_credential_invalid");
            }
            var seen = new HashSet<string>(
                StringComparer.Ordinal);
            foreach (JsonProperty property
                in parsed.RootElement
                    .EnumerateObject())
            {
                if (!CredentialPropertyNames
                        .Contains(property.Name)
                    || !seen.Add(property.Name))
                {
                    throw new InvalidDataException(
                        "trusted_runner_credential_invalid");
                }
            }
            if (!seen.SetEquals(
                    CredentialPropertyNames))
            {
                throw new InvalidDataException(
                    "trusted_runner_credential_invalid");
            }
            return JsonSerializer.Deserialize<
                    CredentialDocument>(
                        payload,
                        JsonOptions)
                ?? throw new InvalidDataException(
                    "trusted_runner_credential_invalid");
        }

        private void ValidateCredential(
            CredentialDocument document)
        {
            if (!string.Equals(
                    document.Schema,
                    CredentialSchema,
                    StringComparison.Ordinal)
                || !string.Equals(
                    document.ClientInstanceId,
                    ClientInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    document.RuntimeMode,
                    _bundle.RuntimeMode,
                    StringComparison.Ordinal)
                || !string.Equals(
                    document.RunnerPolicyId,
                    RunnerPolicyId,
                    StringComparison.Ordinal)
                || document.RunnerProcessId
                    != checked((uint)Environment.ProcessId)
                || !TrustedUnattendedRuntimeBundle
                    .SamePath(
                        document.RunnerExecutablePath,
                        _bundle.CorePath)
                || !string.Equals(
                    document.RunnerExecutableSha256,
                    _bundle.CoreSha256,
                    StringComparison.OrdinalIgnoreCase)
                || document.RunnerExecutableSize
                    != _bundle.CoreSize
                || !TrustedUnattendedRuntimeBundle
                    .SamePath(
                        document.RuntimeExecutablePath,
                        _bundle.CorePath)
                || !string.Equals(
                    document.Slot,
                    Slot,
                    StringComparison.Ordinal)
                || !TrustedUnattendedRuntimeBundle
                    .SamePath(
                        document.CanonicalSavePath,
                        Path.Combine(
                            _bundle.ProjectRoot,
                            "saves",
                            Slot + ".json"))
                || !string.Equals(
                    document.BuildIdentity,
                    _bundle.BuildIdentity,
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    document.PayloadClosure,
                    _bundle.PayloadClosure,
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    document.RequestNonce,
                    RequestNonce,
                    StringComparison.Ordinal)
                || !IsOpaque(
                    document.CredentialProof)
                || !IsOpaque(document.SessionId)
                || !IsOpaque(document.AttemptId)
                || !IsOpaque(document.IssuerReceipt)
                || document.AttemptGeneration == 0
                || document.AllowedCapabilities == null
                || document.AllowedCapabilities.Length == 0
                || document.AllowedCapabilities.Any(
                    capability =>
                        !AllowedCredentialCapabilities
                            .Contains(
                                capability
                                    ?? string.Empty))
                || document.AllowedCapabilities
                    .Distinct(StringComparer.Ordinal)
                    .Count()
                    != document.AllowedCapabilities.Length
                || document.AllowedTargets == null
                || document.AllowedTargets.Length == 0
                || document.AllowedTargets.Any(
                    target => !IsOpaque(target)
                        || target == "*")
                || document.AllowedTargets
                    .Distinct(StringComparer.Ordinal)
                    .Count()
                    != document.AllowedTargets.Length)
            {
                throw new InvalidDataException(
                    "trusted_runner_credential_binding_invalid");
            }
            DateTimeOffset runnerStart =
                ParseUtc(
                    document.RunnerProcessStartTimeUtc);
            DateTimeOffset issued =
                ParseUtc(document.IssuedUtc);
            DateTimeOffset expires =
                ParseUtc(document.ExpiresUtc);
            using Process current =
                Process.GetCurrentProcess();
            if (runnerStart.UtcDateTime.Ticks
                    != current.StartTime.ToUniversalTime()
                        .Ticks
                || expires <= DateTimeOffset.UtcNow
                || issued >= expires
                || expires - issued > MaximumLifetime
                || expires.UtcDateTime.Ticks
                    != ExpiresUtc.UtcDateTime.Ticks)
            {
                throw new InvalidDataException(
                    "trusted_runner_credential_lifetime_invalid");
            }
        }

        private static string RuntimeRoot(
            string projectRoot,
            string localAppDataOverride)
        {
            string localRoot =
                string.IsNullOrWhiteSpace(
                    localAppDataOverride)
                ? Environment.GetFolderPath(
                    Environment.SpecialFolder
                        .LocalApplicationData)
                : Path.GetFullPath(
                    localAppDataOverride);
            if (string.IsNullOrWhiteSpace(localRoot))
                throw new InvalidOperationException(
                    "trusted_runner_local_app_data_missing");
            return Path.Combine(
                localRoot,
                "CF7FlashNight",
                "agent-runtime",
                "v1",
                AgentRendezvousPath
                    .ComputeProjectRootHash(
                        projectRoot));
        }

        private static void WriteNewProtectedFile(
            string path,
            byte[] payload,
            IAgentRendezvousFileProtection protection)
        {
            using var stream = new FileStream(
                path,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                4096,
                FileOptions.WriteThrough);
            protection.ProtectFile(path);
            stream.Write(
                payload,
                0,
                payload.Length);
            stream.Flush(true);
        }

        private static string HashedFileName(
            string value)
        {
            return Convert.ToHexString(
                    SHA256.HashData(
                        Encoding.UTF8.GetBytes(value)))
                .ToLowerInvariant()
                + ".json";
        }

        private static string ToBase64Url(
            byte[] value)
        {
            return Convert.ToBase64String(value)
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
        }

        private static byte[] FromBase64Url(
            string value)
        {
            if (!IsOpaque(value))
                throw new InvalidDataException(
                    "trusted_runner_nonce_invalid");
            string padded = value
                .Replace('-', '+')
                .Replace('_', '/');
            padded += new string(
                '=',
                (4 - padded.Length % 4) % 4);
            try
            {
                return Convert.FromBase64String(
                    padded);
            }
            catch (FormatException exception)
            {
                throw new InvalidDataException(
                    "trusted_runner_nonce_invalid",
                    exception);
            }
        }

        private static bool IsOpaque(string value)
        {
            return value != null
                && value.Length >= 16
                && value.Length <= 256
                && value.All(
                    character =>
                        (character >= 'A'
                            && character <= 'Z')
                        || (character >= 'a'
                            && character <= 'z')
                        || (character >= '0'
                            && character <= '9')
                        || character == '-'
                        || character == '_');
        }

        private static DateTimeOffset ParseUtc(
            string value)
        {
            if (!DateTimeOffset.TryParseExact(
                    value,
                    "O",
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal
                        | DateTimeStyles.AdjustToUniversal,
                    out DateTimeOffset result))
            {
                throw new InvalidDataException(
                    "trusted_runner_timestamp_invalid");
            }
            return result;
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(
                    nameof(
                        TrustedUnattendedBootstrapLease));
        }

        public void Dispose()
        {
            if (_disposed)
                return;
            _disposed = true;
            CryptographicOperations.ZeroMemory(
                _requestNonceBytes);
            try
            {
                if (File.Exists(RequestPath))
                    File.Delete(RequestPath);
            }
            catch
            {
            }
            try
            {
                if (File.Exists(CredentialPath))
                    File.Delete(CredentialPath);
            }
            catch
            {
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

    internal sealed class TrustedUnattendedCredential
    {
        internal TrustedUnattendedCredential(
            string runtimeMode,
            string credentialProof,
            string[] allowedCapabilities,
            string[] allowedTargets,
            string sessionId,
            string attemptId,
            ulong attemptGeneration,
            string issuerReceipt)
        {
            RuntimeMode = runtimeMode;
            CredentialProof = credentialProof;
            AllowedCapabilities =
                Array.AsReadOnly(
                    (string[])allowedCapabilities.Clone());
            AllowedTargets =
                Array.AsReadOnly(
                    (string[])allowedTargets.Clone());
            SessionId = sessionId;
            AttemptId = attemptId;
            AttemptGeneration =
                attemptGeneration;
            IssuerReceipt = issuerReceipt;
        }

        public string CredentialProof { get; private set; }
        public string RuntimeMode { get; }
        public IReadOnlyList<string> AllowedCapabilities
        {
            get;
        }
        public IReadOnlyList<string> AllowedTargets { get; }
        public string SessionId { get; }
        public string AttemptId { get; }
        public ulong AttemptGeneration { get; }
        public string IssuerReceipt { get; }

        public void ClearCredentialProof()
        {
            CredentialProof = null;
        }
    }
}
