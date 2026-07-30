using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.Security
{
    internal sealed class DeveloperEnrollment
    {
        internal DeveloperEnrollment(
            string clientInstanceId,
            string enrollmentReceipt,
            string credentialProof,
            IEnumerable<string> allowedCapabilities,
            IEnumerable<string> allowedTargets,
            DateTimeOffset issuedUtc,
            DateTimeOffset expiresUtc,
            string credentialFilePath)
        {
            ClientInstanceId = clientInstanceId;
            EnrollmentReceipt = enrollmentReceipt;
            CredentialProof = credentialProof;
            AllowedCapabilities = Freeze(allowedCapabilities);
            AllowedTargets = Freeze(allowedTargets);
            IssuedUtc = issuedUtc.ToUniversalTime();
            ExpiresUtc = expiresUtc.ToUniversalTime();
            CredentialFilePath = credentialFilePath;
        }

        public string ClientInstanceId { get; }
        public string EnrollmentReceipt { get; }
        public string CredentialProof { get; }
        public ReadOnlyCollection<string> AllowedCapabilities { get; }
        public ReadOnlyCollection<string> AllowedTargets { get; }
        public DateTimeOffset IssuedUtc { get; }
        public DateTimeOffset ExpiresUtc { get; }
        public string CredentialFilePath { get; }

        private static ReadOnlyCollection<string> Freeze(
            IEnumerable<string> values)
        {
            return Array.AsReadOnly(
                (values ?? Array.Empty<string>())
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray());
        }
    }

    /// <summary>
    /// Same-logon protected developer enrollment storage. The proof is a
    /// bearer credential by design: it is never logged or copied into the
    /// rendezvous document, and comparisons are fixed-time. Reissuing a
    /// client record atomically rotates both receipt and proof.
    /// </summary>
    internal sealed class PersistentDeveloperEnrollmentStore
    {
        private const string Schema =
            "cf7.agent_runtime.developer_credential.v1";
        private const int MaximumCredentialFileBytes = 64 * 1024;
        private static readonly TimeSpan MaximumLifetime =
            TimeSpan.FromHours(8);
        private static readonly HashSet<string>
            SecurityScopeCapabilities =
                new HashSet<string>(
                    ObservationDataScopesV1.All
                        .Select(scope => "observe:" + scope)
                        .Concat(
                            new[]
                            {
                                "observation.persist",
                                "observation.export"
                            }),
                    StringComparer.Ordinal);
        private static readonly HashSet<string> PropertyNames =
            new HashSet<string>(
                new[]
                {
                    "schema",
                    "clientInstanceId",
                    "enrollmentReceipt",
                    "credentialProof",
                    "allowedCapabilities",
                    "allowedTargets",
                    "issuedUtc",
                    "expiresUtc"
                },
                StringComparer.Ordinal);
        private static readonly JsonSerializerOptions JsonOptions =
            new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                WriteIndented = false,
                UnmappedMemberHandling =
                    System.Text.Json.Serialization
                        .JsonUnmappedMemberHandling.Disallow,
                MaxDepth = 8
            };

        private readonly object _sync = new object();
        private readonly string _directory;
        private readonly IAgentRuntimeClock _clock;
        private readonly IAgentRendezvousFileProtection _protection;

        public PersistentDeveloperEnrollmentStore(
            string projectRoot,
            IAgentRuntimeClock clock,
            string directoryOverride = null,
            IAgentRendezvousFileProtection protection = null)
        {
            if (string.IsNullOrWhiteSpace(projectRoot))
                throw new ArgumentException(
                    "A project root is required.",
                    nameof(projectRoot));
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _protection = protection
                ?? new WindowsCurrentUserRendezvousFileProtection();
            _directory = string.IsNullOrWhiteSpace(directoryOverride)
                ? ResolveDirectory(projectRoot)
                : Path.GetFullPath(directoryOverride);
        }

        public string DirectoryPath
        {
            get { return _directory; }
        }

        public DeveloperEnrollment IssueOrRotate(
            string clientInstanceId,
            IEnumerable<string> allowedCapabilities,
            IEnumerable<string> allowedTargets,
            TimeSpan lifetime)
        {
            string[] capabilities =
                ValidateCapabilities(allowedCapabilities);
            string[] targets = ValidateTargets(allowedTargets);
            ValidateClientInstanceId(clientInstanceId);
            if (lifetime <= TimeSpan.Zero
                || lifetime > MaximumLifetime)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(lifetime),
                    "Developer enrollment lifetime must be in (0, 8h].");
            }

            DateTimeOffset issuedUtc = _clock.UtcNow.ToUniversalTime();
            DateTimeOffset expiresUtc = issuedUtc.Add(lifetime);
            var document = new CredentialDocument
            {
                Schema = Schema,
                ClientInstanceId = clientInstanceId,
                EnrollmentReceipt =
                    OpaqueIdGenerator.Create("enrollment"),
                CredentialProof =
                    OpaqueIdGenerator.Create("proof"),
                AllowedCapabilities = capabilities,
                AllowedTargets = targets,
                IssuedUtc = FormatUtc(issuedUtc),
                ExpiresUtc = FormatUtc(expiresUtc)
            };
            string path = PathForClient(clientInstanceId);

            lock (_sync)
            {
                Directory.CreateDirectory(_directory);
                _protection.ProtectDirectory(_directory);
                WriteAtomically(path, document);
            }
            return ToEnrollment(document, path);
        }

        public bool TryAuthenticate(
            string clientInstanceId,
            string presentedProof,
            IEnumerable<string> requestedCapabilities,
            out DeveloperEnrollmentEvidence evidence,
            out string reasonCode)
        {
            evidence = null;
            if (!TryReadActive(
                    clientInstanceId,
                    out CredentialDocument document,
                    out reasonCode))
            {
                return false;
            }
            if (!FixedTimeEquals(
                    document.CredentialProof,
                    presentedProof))
            {
                reasonCode = "authentication_failed";
                return false;
            }
            if (!TrySelectCapabilities(
                    document.AllowedCapabilities,
                    requestedCapabilities,
                    out string[] selected,
                    out reasonCode))
            {
                return false;
            }

            DateTimeOffset expiresUtc =
                ParseUtc(document.ExpiresUtc, "expiresUtc");
            TimeSpan remaining =
                expiresUtc - _clock.UtcNow.ToUniversalTime();
            if (remaining <= TimeSpan.Zero)
            {
                reasonCode = "credential_revoked";
                return false;
            }
            if (remaining > MaximumLifetime)
                remaining = MaximumLifetime;
            evidence = new DeveloperEnrollmentEvidence
            {
                ClientInstanceId = document.ClientInstanceId,
                EnrollmentReceipt =
                    document.EnrollmentReceipt,
                AllowedCapabilities = selected,
                AllowedTargets = document.AllowedTargets,
                RequestedLifetime = remaining
            };
            reasonCode = null;
            return true;
        }

        public bool TryVerifyReceipt(
            DeveloperEnrollmentEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            authorization = null;
            reasonCode = null;
            if (evidence == null
                || !TryReadActive(
                    evidence.ClientInstanceId,
                    out CredentialDocument document,
                    out reasonCode))
            {
                reasonCode ??=
                    "developer_enrollment_evidence_invalid";
                return false;
            }
            if (!FixedTimeEquals(
                    document.EnrollmentReceipt,
                    evidence.EnrollmentReceipt))
            {
                reasonCode =
                    "developer_enrollment_evidence_invalid";
                return false;
            }
            if (!TrySelectCapabilities(
                    document.AllowedCapabilities,
                    evidence.AllowedCapabilities,
                    out string[] selectedCapabilities,
                    out reasonCode)
                || !IsExactSubset(
                    document.AllowedTargets,
                    evidence.AllowedTargets))
            {
                reasonCode =
                    "developer_enrollment_scope_invalid";
                return false;
            }

            authorization =
                VerifiedPrincipalAuthorization.CreateTrusted(
                    selectedCapabilities,
                    evidence.AllowedTargets,
                    document.EnrollmentReceipt);
            reasonCode = null;
            return true;
        }

        public bool Revoke(string clientInstanceId)
        {
            ValidateClientInstanceId(clientInstanceId);
            string path = PathForClient(clientInstanceId);
            lock (_sync)
            {
                if (!File.Exists(path))
                    return false;
                File.Delete(path);
                return true;
            }
        }

        private bool TryReadActive(
            string clientInstanceId,
            out CredentialDocument document,
            out string reasonCode)
        {
            document = null;
            try
            {
                ValidateClientInstanceId(clientInstanceId);
            }
            catch (ArgumentException)
            {
                reasonCode = "authentication_failed";
                return false;
            }

            string path = PathForClient(clientInstanceId);
            lock (_sync)
            {
                if (!File.Exists(path))
                {
                    reasonCode = "authentication_failed";
                    return false;
                }
                try
                {
                    using var stream = new FileStream(
                        path,
                        FileMode.Open,
                        FileAccess.Read,
                        FileShare.Read,
                        4096,
                        FileOptions.SequentialScan);
                    if (stream.Length <= 0
                        || stream.Length
                            > MaximumCredentialFileBytes)
                    {
                        reasonCode = "authentication_failed";
                        return false;
                    }
                    byte[] payload =
                        new byte[checked((int)stream.Length)];
                    stream.ReadExactly(payload);
                    document = ParseDocument(payload);
                }
                catch (IOException)
                {
                    reasonCode = "authentication_failed";
                    return false;
                }
                catch (UnauthorizedAccessException)
                {
                    reasonCode = "authentication_failed";
                    return false;
                }
                catch (InvalidDataException)
                {
                    reasonCode = "authentication_failed";
                    return false;
                }
            }

            if (!string.Equals(
                    document.ClientInstanceId,
                    clientInstanceId,
                    StringComparison.Ordinal)
                || ParseUtc(document.ExpiresUtc, "expiresUtc")
                    <= _clock.UtcNow.ToUniversalTime())
            {
                document = null;
                reasonCode = "credential_revoked";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private void WriteAtomically(
            string path,
            CredentialDocument document)
        {
            string temporaryPath = path
                + "."
                + Guid.NewGuid().ToString("N")
                + ".tmp";
            try
            {
                byte[] payload =
                    JsonSerializer.SerializeToUtf8Bytes(
                        document,
                        JsonOptions);
                if (payload.Length > MaximumCredentialFileBytes)
                {
                    throw new InvalidOperationException(
                        "Developer credential file is oversized.");
                }
                using (var stream = new FileStream(
                    temporaryPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None,
                    4096,
                    FileOptions.WriteThrough))
                {
                    _protection.ProtectFile(temporaryPath);
                    stream.Write(payload, 0, payload.Length);
                    stream.Flush(true);
                }
                File.Move(temporaryPath, path, true);
                _protection.ProtectFile(path);
            }
            finally
            {
                if (File.Exists(temporaryPath))
                    File.Delete(temporaryPath);
            }
        }

        private static CredentialDocument ParseDocument(
            byte[] payload)
        {
            try
            {
                using JsonDocument parsed = JsonDocument.Parse(
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
                        "Credential document must be an object.");
                }
                var seen = new HashSet<string>(
                    StringComparer.Ordinal);
                foreach (JsonProperty property
                    in parsed.RootElement.EnumerateObject())
                {
                    if (!PropertyNames.Contains(property.Name)
                        || !seen.Add(property.Name))
                    {
                        throw new InvalidDataException(
                            "Credential document has unknown or duplicate fields.");
                    }
                }
                if (!seen.SetEquals(PropertyNames))
                {
                    throw new InvalidDataException(
                        "Credential document is incomplete.");
                }
                CredentialDocument document =
                    JsonSerializer.Deserialize<CredentialDocument>(
                        payload,
                        JsonOptions);
                ValidateDocument(document);
                return document;
            }
            catch (JsonException exception)
            {
                throw new InvalidDataException(
                    "Credential document is invalid JSON.",
                    exception);
            }
            catch (ArgumentException exception)
            {
                throw new InvalidDataException(
                    "Credential document has invalid values.",
                    exception);
            }
        }

        private static void ValidateDocument(
            CredentialDocument document)
        {
            if (document == null
                || !string.Equals(
                    document.Schema,
                    Schema,
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "Credential schema is unsupported.");
            }
            ValidateClientInstanceId(document.ClientInstanceId);
            RequireOpaque(
                document.EnrollmentReceipt,
                "enrollmentReceipt");
            RequireOpaque(
                document.CredentialProof,
                "credentialProof");
            document.AllowedCapabilities =
                ValidateCapabilities(
                    document.AllowedCapabilities);
            document.AllowedTargets =
                ValidateTargets(document.AllowedTargets);
            DateTimeOffset issued =
                ParseUtc(document.IssuedUtc, "issuedUtc");
            DateTimeOffset expires =
                ParseUtc(document.ExpiresUtc, "expiresUtc");
            if (expires <= issued
                || expires - issued > MaximumLifetime)
            {
                throw new InvalidDataException(
                    "Credential lifetime is invalid.");
            }
        }

        private static string[] ValidateCapabilities(
            IEnumerable<string> values)
        {
            string[] result = FreezeRequired(
                values,
                nameof(values));
            if (result.Any(capability =>
                    !AgentCapabilitiesV1.All.Contains(
                        capability)
                    && !SecurityScopeCapabilities.Contains(
                        capability)))
            {
                throw new ArgumentException(
                    "An unknown Agent capability was requested.",
                    nameof(values));
            }
            return result;
        }

        private static string[] ValidateTargets(
            IEnumerable<string> values)
        {
            string[] result = FreezeRequired(
                values,
                nameof(values));
            foreach (string target in result)
            {
                if (target == "*")
                {
                    throw new ArgumentException(
                        "Developer enrollment requires explicit targets.",
                        nameof(values));
                }
                RequireOpaque(target, nameof(values));
            }
            return result;
        }

        private static string[] FreezeRequired(
            IEnumerable<string> values,
            string parameter)
        {
            string[] result = (values ?? Array.Empty<string>())
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            if (result.Length == 0)
            {
                throw new ArgumentException(
                    "At least one scope value is required.",
                    parameter);
            }
            return result;
        }

        private static bool TrySelectCapabilities(
            IEnumerable<string> allowed,
            IEnumerable<string> requested,
            out string[] selected,
            out string reasonCode)
        {
            selected = (requested ?? Array.Empty<string>())
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            if (selected.Length == 0
                || selected.Any(capability =>
                    !AgentCapabilitiesV1.All.Contains(capability)
                    && !SecurityScopeCapabilities.Contains(
                        capability))
                || !IsExactSubset(allowed, selected))
            {
                selected = null;
                reasonCode = "capability_denied";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static bool IsExactSubset(
            IEnumerable<string> allowed,
            IEnumerable<string> requested)
        {
            var allowedSet = new HashSet<string>(
                allowed ?? Array.Empty<string>(),
                StringComparer.Ordinal);
            string[] requestedValues =
                (requested ?? Array.Empty<string>())
                    .Where(value =>
                        !string.IsNullOrWhiteSpace(value))
                    .Distinct(StringComparer.Ordinal)
                    .ToArray();
            return requestedValues.Length > 0
                && requestedValues.All(allowedSet.Contains);
        }

        private static void ValidateClientInstanceId(string value)
        {
            RequireOpaque(value, nameof(value));
        }

        private static void RequireOpaque(
            string value,
            string parameter)
        {
            if (string.IsNullOrWhiteSpace(value)
                || value.Length
                    < AgentProtocolV1.MinimumOpaqueIdCharacters
                || value.Length
                    > AgentProtocolV1.MaximumOpaqueIdCharacters
                || value.Any(character =>
                    !((character >= 'a' && character <= 'z')
                        || (character >= 'A' && character <= 'Z')
                        || (character >= '0' && character <= '9')
                        || character == '-'
                        || character == '_')))
            {
                throw new ArgumentException(
                    "An opaque protocol ID is required.",
                    parameter);
            }
        }

        private static string ResolveDirectory(
            string projectRoot)
        {
            string localAppData = Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(localAppData))
            {
                throw new InvalidOperationException(
                    "LOCALAPPDATA is unavailable.");
            }
            return Path.Combine(
                localAppData,
                "CF7FlashNight",
                "agent-runtime",
                "v1",
                AgentRendezvousPath.ComputeProjectRootHash(
                    projectRoot),
                "developer-credentials");
        }

        private string PathForClient(string clientInstanceId)
        {
            byte[] digest = SHA256.HashData(
                Encoding.UTF8.GetBytes(clientInstanceId));
            string name = Convert.ToHexString(digest)
                .ToLowerInvariant()
                + ".json";
            return Path.Combine(_directory, name);
        }

        private static DeveloperEnrollment ToEnrollment(
            CredentialDocument document,
            string path)
        {
            return new DeveloperEnrollment(
                document.ClientInstanceId,
                document.EnrollmentReceipt,
                document.CredentialProof,
                document.AllowedCapabilities,
                document.AllowedTargets,
                ParseUtc(document.IssuedUtc, "issuedUtc"),
                ParseUtc(document.ExpiresUtc, "expiresUtc"),
                path);
        }

        private static string FormatUtc(DateTimeOffset value)
        {
            return value.ToUniversalTime().ToString(
                "O",
                CultureInfo.InvariantCulture);
        }

        private static DateTimeOffset ParseUtc(
            string value,
            string field)
        {
            if (!DateTimeOffset.TryParseExact(
                    value,
                    "O",
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.RoundtripKind,
                    out DateTimeOffset parsed)
                || parsed.Offset != TimeSpan.Zero)
            {
                throw new InvalidDataException(
                    "Credential timestamp is not explicit UTC: "
                    + field);
            }
            return parsed;
        }

        private static bool FixedTimeEquals(
            string expected,
            string presented)
        {
            if (expected == null
                || presented == null
                || expected.Length != presented.Length
                || expected.Length
                    > AgentProtocolV1.MaximumOpaqueIdCharacters)
            {
                return false;
            }
            return CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(expected),
                Encoding.UTF8.GetBytes(presented));
        }

        private sealed class CredentialDocument
        {
            public string Schema { get; set; }
            public string ClientInstanceId { get; set; }
            public string EnrollmentReceipt { get; set; }
            public string CredentialProof { get; set; }
            public string[] AllowedCapabilities { get; set; }
            public string[] AllowedTargets { get; set; }
            public string IssuedUtc { get; set; }
            public string ExpiresUtc { get; set; }
        }
    }
}
