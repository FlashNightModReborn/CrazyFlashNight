using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Host-bound monotonic revision journal for the AS2 hair state. The
    /// Launcher binds it from session/save truth; wire requests can only
    /// present an expectation and cannot create or replace that binding.
    /// </summary>
    internal sealed class PersistentHairDomainAuthority
        : IHairDomainAuthority
    {
        private const int MaximumDocumentBytes = 8 * 1024;
        private static readonly HashSet<string> RootPropertyNames =
            new HashSet<string>(
                new[]
                {
                    "v",
                    "binding",
                    "revision",
                    "generation",
                    "currentHair"
                },
                StringComparer.Ordinal);
        private static readonly HashSet<string> BindingPropertyNames =
            new HashSet<string>(
                new[]
                {
                    "sessionId",
                    "lifecycleGeneration",
                    "attemptId",
                    "attemptGeneration",
                    "slotId",
                    "saveSignature"
                },
                StringComparer.Ordinal);
        private static readonly JsonSerializerOptions SerializerOptions =
            new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                PropertyNameCaseInsensitive = false,
                AllowTrailingCommas = false,
                ReadCommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 4,
                UnmappedMemberHandling =
                    JsonUnmappedMemberHandling.Disallow
            };

        private readonly object _gate = new object();
        private readonly string _directory;
        private readonly string _path;
        private readonly string _lockPath;
        private readonly IAgentRendezvousFileProtection _fileProtection;
        private HairSaveBinding _activeBinding;
        private bool _hasBoundInThisProcess;

        public PersistentHairDomainAuthority(
            string projectRoot,
            string localAppDataOverride = null,
            IAgentRendezvousFileProtection fileProtection = null)
        {
            if (string.IsNullOrWhiteSpace(projectRoot))
                throw new ArgumentException(
                    "A project root is required.",
                    nameof(projectRoot));
            string localAppData = string.IsNullOrWhiteSpace(
                    localAppDataOverride)
                ? Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData)
                : Path.GetFullPath(localAppDataOverride);
            if (string.IsNullOrWhiteSpace(localAppData))
                throw new InvalidOperationException(
                    "LOCALAPPDATA is unavailable.");

            _directory = Path.Combine(
                localAppData,
                "CF7FlashNight",
                "agent-runtime",
                "v1",
                AgentRendezvousPath.ComputeProjectRootHash(projectRoot));
            _path = Path.Combine(
                _directory,
                "hair-authority.json");
            _lockPath = Path.Combine(
                _directory,
                ".hair-authority.lock");
            _fileProtection = fileProtection
                ?? new WindowsCurrentUserRendezvousFileProtection();
        }

        internal string StatePath
        {
            get { return _path; }
        }

        /// <summary>
        /// Called only from Launcher-owned session/save lifecycle code.
        /// Rebinding after an in-process detach advances generation even when
        /// the apparent save identity is identical.
        /// </summary>
        internal HairDomainAuthorityStamp Bind(
            HairSaveBinding binding,
            long initialRevision = 0)
        {
            if (!HairAppearanceValidation.IsValidBinding(binding))
                throw new ArgumentException(
                    "The hair save binding is invalid.",
                    nameof(binding));
            if (initialRevision < 0)
                throw new ArgumentOutOfRangeException(
                    nameof(initialRevision));

            lock (_gate)
            {
                EnsureDirectory();
                using FileStream fileLock = AcquireLock();
                AuthorityDocument current = TryRead();
                bool samePersisted = current != null
                    && binding.Equals(current.Binding?.ToBinding());
                bool sameActive = _activeBinding != null
                    && binding.Equals(_activeBinding);

                long generation;
                long revision;
                string currentHair;
                if (!_hasBoundInThisProcess && samePersisted)
                {
                    generation = current.Generation;
                    revision = Math.Max(
                        current.Revision,
                        initialRevision);
                    currentHair = current.CurrentHair;
                }
                else if (sameActive && samePersisted)
                {
                    generation = current.Generation;
                    revision = Math.Max(
                        current.Revision,
                        initialRevision);
                    currentHair = current.CurrentHair;
                }
                else
                {
                    generation = checked(
                        Math.Max(0, current?.Generation ?? 0) + 1);
                    revision = initialRevision;
                    currentHair = null;
                }

                var replacement = AuthorityDocument.Create(
                    binding,
                    revision,
                    generation,
                    currentHair);
                Write(replacement);
                _activeBinding = binding;
                _hasBoundInThisProcess = true;
                return replacement.ToStamp();
            }
        }

        internal void Unbind()
        {
            lock (_gate)
            {
                _activeBinding = null;
            }
        }

        public bool TryValidate(
            HairSaveBinding expectedBinding,
            long expectedRevision,
            long expectedGeneration,
            string expectedCurrentHair,
            out string reasonCode)
        {
            lock (_gate)
            {
                if (!TryLoadExact(
                        expectedBinding,
                        out AuthorityDocument current,
                        out reasonCode))
                    return false;
                if (current.Generation != expectedGeneration
                    || current.Revision != expectedRevision)
                {
                    reasonCode =
                        HairAppearanceReasonCodes.StaleRevision;
                    return false;
                }
                if (!string.Equals(
                    current.CurrentHair,
                    expectedCurrentHair,
                    StringComparison.Ordinal))
                {
                    reasonCode =
                        HairAppearanceReasonCodes.StaleState;
                    return false;
                }
                reasonCode = null;
                return true;
            }
        }

        public bool TryObserve(
            HairSaveBinding expectedBinding,
            string currentHair,
            out HairDomainAuthorityStamp stamp,
            out string reasonCode)
        {
            stamp = null;
            if (!HairAppearanceValidation.IsSafeString(
                currentHair,
                160,
                false))
            {
                reasonCode =
                    HairAppearanceReasonCodes.MalformedAuthority;
                return false;
            }

            lock (_gate)
            {
                if (!TryLoadExact(
                        expectedBinding,
                        out AuthorityDocument current,
                        out reasonCode))
                    return false;
                if (!string.Equals(
                    current.CurrentHair,
                    currentHair,
                    StringComparison.Ordinal))
                {
                    long previousRevision = current.Revision;
                    string previousHair = current.CurrentHair;
                    try
                    {
                        current.Revision = current.CurrentHair == null
                            ? current.Revision
                            : checked(current.Revision + 1);
                    }
                    catch (OverflowException)
                    {
                        reasonCode =
                            HairAppearanceReasonCodes.AdapterUnavailable;
                        return false;
                    }
                    current.CurrentHair = currentHair;
                    if (!TryWrite(
                        current,
                        previousRevision,
                        previousHair))
                    {
                        reasonCode =
                            HairAppearanceReasonCodes.AdapterUnavailable;
                        return false;
                    }
                }
                stamp = current.ToStamp();
                reasonCode = null;
                return true;
            }
        }

        public bool TryApply(
            HairSaveBinding expectedBinding,
            long expectedRevision,
            long expectedGeneration,
            string expectedCurrentHair,
            string newCurrentHair,
            out HairDomainAuthorityStamp stamp,
            out string reasonCode)
        {
            stamp = null;
            if (!HairAppearanceValidation.IsSafeString(
                    expectedCurrentHair,
                    160,
                    false)
                || !HairAppearanceValidation.IsSafeString(
                    newCurrentHair,
                    160,
                    false))
            {
                reasonCode =
                    HairAppearanceReasonCodes.InvalidPayload;
                return false;
            }

            lock (_gate)
            {
                if (!TryLoadExact(
                        expectedBinding,
                        out AuthorityDocument current,
                        out reasonCode))
                    return false;
                if (current.Revision != expectedRevision
                    || current.Generation != expectedGeneration)
                {
                    reasonCode =
                        HairAppearanceReasonCodes.StaleRevision;
                    return false;
                }
                if (!string.Equals(
                    current.CurrentHair,
                    expectedCurrentHair,
                    StringComparison.Ordinal))
                {
                    reasonCode =
                        HairAppearanceReasonCodes.StaleState;
                    return false;
                }

                long previousRevision = current.Revision;
                string previousHair = current.CurrentHair;
                try
                {
                    current.Revision = checked(current.Revision + 1);
                }
                catch (OverflowException)
                {
                    reasonCode =
                        HairAppearanceReasonCodes.AdapterUnavailable;
                    return false;
                }
                current.CurrentHair = newCurrentHair;
                if (!TryWrite(
                    current,
                    previousRevision,
                    previousHair))
                {
                    reasonCode =
                        HairAppearanceReasonCodes.AdapterUnavailable;
                    return false;
                }
                stamp = current.ToStamp();
                reasonCode = null;
                return true;
            }
        }

        private bool TryLoadExact(
            HairSaveBinding expectedBinding,
            out AuthorityDocument document,
            out string reasonCode)
        {
            document = null;
            if (!HairAppearanceValidation.IsValidBinding(
                    expectedBinding))
            {
                reasonCode =
                    HairAppearanceReasonCodes.InvalidPayload;
                return false;
            }
            if (_activeBinding == null
                || !expectedBinding.Equals(_activeBinding))
            {
                reasonCode = HairAppearanceReasonCodes.CrossSave;
                return false;
            }

            try
            {
                EnsureDirectory();
                using FileStream fileLock = AcquireLock();
                document = TryRead();
            }
            catch (Exception exception)
                when (exception is IOException
                    || exception is UnauthorizedAccessException
                    || exception is InvalidDataException
                    || exception is JsonException)
            {
                reasonCode =
                    HairAppearanceReasonCodes.AdapterUnavailable;
                return false;
            }
            if (document == null
                || !expectedBinding.Equals(
                    document.Binding?.ToBinding()))
            {
                reasonCode = HairAppearanceReasonCodes.CrossSave;
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool TryWrite(
            AuthorityDocument document,
            long expectedRevision,
            string expectedCurrentHair)
        {
            try
            {
                EnsureDirectory();
                using FileStream fileLock = AcquireLock();
                AuthorityDocument onDisk = TryRead();
                if (onDisk == null
                    || !document.Binding.ToBinding().Equals(
                        onDisk.Binding?.ToBinding())
                    || onDisk.Generation != document.Generation
                    || onDisk.Revision != expectedRevision
                    || !string.Equals(
                        onDisk.CurrentHair,
                        expectedCurrentHair,
                        StringComparison.Ordinal))
                {
                    return false;
                }
                Write(document);
                return true;
            }
            catch (Exception exception)
                when (exception is IOException
                    || exception is UnauthorizedAccessException
                    || exception is InvalidDataException
                    || exception is JsonException)
            {
                return false;
            }
        }

        private void EnsureDirectory()
        {
            Directory.CreateDirectory(_directory);
            _fileProtection.ProtectDirectory(_directory);
        }

        private FileStream AcquireLock()
        {
            var stream = new FileStream(
                _lockPath,
                FileMode.OpenOrCreate,
                FileAccess.ReadWrite,
                FileShare.None,
                1,
                FileOptions.WriteThrough);
            _fileProtection.ProtectFile(_lockPath);
            return stream;
        }

        private AuthorityDocument TryRead()
        {
            if (!File.Exists(_path))
                return null;
            var info = new FileInfo(_path);
            if (info.Length <= 0
                || info.Length > MaximumDocumentBytes)
                throw new InvalidDataException(
                    "The hair authority journal size is invalid.");

            byte[] bytes = File.ReadAllBytes(_path);
            using JsonDocument parsed = JsonDocument.Parse(
                bytes,
                new JsonDocumentOptions
                {
                    AllowTrailingCommas = false,
                    CommentHandling = JsonCommentHandling.Disallow,
                    MaxDepth = 4
                });
            RequireExactObject(
                parsed.RootElement,
                RootPropertyNames);
            if (!parsed.RootElement.TryGetProperty(
                    "binding",
                    out JsonElement binding))
                throw new InvalidDataException(
                    "The authority binding is missing.");
            RequireExactObject(binding, BindingPropertyNames);

            AuthorityDocument document =
                JsonSerializer.Deserialize<AuthorityDocument>(
                    bytes,
                    SerializerOptions)
                ?? throw new InvalidDataException(
                    "The authority journal is empty.");
            if (document.V != 1
                || !document.IsValid())
                throw new InvalidDataException(
                    "The authority journal is invalid.");
            return document;
        }

        private void Write(AuthorityDocument document)
        {
            if (document == null || !document.IsValid())
                throw new InvalidDataException(
                    "The hair authority journal is invalid.");
            byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(
                document,
                SerializerOptions);
            if (bytes.Length > MaximumDocumentBytes)
                throw new InvalidDataException(
                    "The hair authority journal is too large.");

            string temporaryPath = Path.Combine(
                _directory,
                ".hair-authority."
                    + Guid.NewGuid().ToString("N") + ".tmp");
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
                    stream.Write(bytes, 0, bytes.Length);
                    stream.Flush(true);
                }
                _fileProtection.ProtectFile(temporaryPath);
                File.Move(temporaryPath, _path, true);
                _fileProtection.ProtectFile(_path);
            }
            finally
            {
                try
                {
                    if (File.Exists(temporaryPath))
                        File.Delete(temporaryPath);
                }
                catch
                {
                }
            }
        }

        private static void RequireExactObject(
            JsonElement value,
            HashSet<string> expectedNames)
        {
            if (value.ValueKind != JsonValueKind.Object)
                throw new InvalidDataException(
                    "A JSON object was required.");
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (JsonProperty property in value.EnumerateObject())
            {
                if (!expectedNames.Contains(property.Name)
                    || !seen.Add(property.Name))
                {
                    throw new InvalidDataException(
                        "The journal has an unknown or duplicate property.");
                }
            }
            if (!seen.SetEquals(expectedNames))
                throw new InvalidDataException(
                    "The journal is missing a required property.");
        }

        private sealed class AuthorityDocument
        {
            public int V { get; set; }
            public BindingDocument Binding { get; set; }
            public long Revision { get; set; }
            public long Generation { get; set; }
            public string CurrentHair { get; set; }

            public static AuthorityDocument Create(
                HairSaveBinding binding,
                long revision,
                long generation,
                string currentHair)
            {
                return new AuthorityDocument
                {
                    V = 1,
                    Binding = BindingDocument.From(binding),
                    Revision = revision,
                    Generation = generation,
                    CurrentHair = currentHair
                };
            }

            public bool IsValid()
            {
                HairSaveBinding binding;
                try
                {
                    binding = Binding?.ToBinding();
                }
                catch (Exception)
                {
                    return false;
                }
                return V == 1
                    && HairAppearanceValidation.IsValidBinding(binding)
                    && Revision >= 0
                    && Generation >= 0
                    && (CurrentHair == null
                        || HairAppearanceValidation.IsSafeString(
                            CurrentHair,
                            160,
                            false));
            }

            public HairDomainAuthorityStamp ToStamp()
            {
                return new HairDomainAuthorityStamp(
                    Binding.ToBinding(),
                    Revision,
                    Generation,
                    CurrentHair);
            }
        }

        private sealed class BindingDocument
        {
            public string SessionId { get; set; }
            public long LifecycleGeneration { get; set; }
            public string AttemptId { get; set; }
            public long AttemptGeneration { get; set; }
            public string SlotId { get; set; }
            public string SaveSignature { get; set; }

            public static BindingDocument From(HairSaveBinding binding)
            {
                return new BindingDocument
                {
                    SessionId = binding.SessionId,
                    LifecycleGeneration =
                        binding.LifecycleGeneration,
                    AttemptId = binding.AttemptId,
                    AttemptGeneration =
                        binding.AttemptGeneration,
                    SlotId = binding.SlotId,
                    SaveSignature = binding.SaveSignature
                };
            }

            public HairSaveBinding ToBinding()
            {
                return new HairSaveBinding(
                    SessionId,
                    LifecycleGeneration,
                    AttemptId,
                    AttemptGeneration,
                    SlotId,
                    SaveSignature);
            }
        }
    }
}
