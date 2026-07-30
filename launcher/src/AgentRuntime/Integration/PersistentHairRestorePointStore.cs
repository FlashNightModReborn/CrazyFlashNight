using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Current-user-only, bounded and restart-safe persistence for the one-shot
    /// hair restore transaction. A directory lock serializes prune/count/create
    /// across processes; each record also has an independent lock and an
    /// optimistic storeVersion. No clear-text restore token is persisted.
    /// </summary>
    internal sealed class PersistentHairRestorePointStore
        : IHairRestorePointStore
    {
        internal const int MaximumRecords = 128;
        internal const int MaximumDocumentBytes = 16 * 1024;
        private const string DirectoryLockFileName = ".quota.lock";

        private static readonly Regex TransactionIdPattern = new Regex(
            "^hairtx_[A-Za-z0-9_-]{24}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly HashSet<string> RootPropertyNames =
            new HashSet<string>(
                new[]
                {
                    "v",
                    "transactionId",
                    "binding",
                    "beforeHair",
                    "afterHair",
                    "beforeRevision",
                    "beforeGeneration",
                    "beforeSnapshotHash",
                    "previewHash",
                    "restoreTokenHash",
                    "createdAtUtc",
                    "expiresAtUtc",
                    "state",
                    "storeVersion",
                    "authoritativeRevision",
                    "authoritativeGeneration",
                    "authoritativeSnapshotHash",
                    "restoreTokenConsumed"
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
            CreateSerializerOptions();

        private readonly string _directory;
        private readonly IAgentRendezvousFileProtection _fileProtection;

        public PersistentHairRestorePointStore(
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
                AgentRendezvousPath.ComputeProjectRootHash(projectRoot),
                "hair-restore");
            _fileProtection = fileProtection
                ?? new WindowsCurrentUserRendezvousFileProtection();
        }

        internal string DirectoryPath
        {
            get { return _directory; }
        }

        internal string DirectoryLockPath
        {
            get
            {
                return Path.Combine(
                    _directory,
                    DirectoryLockFileName);
            }
        }

        public Task<HairRestoreStoreResult> TryCreateAsync(
            HairRestorePointRecord record,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!IsValidRecord(record)
                || record.StoreVersion != 0
                || !IsSafeTransactionId(record.TransactionId))
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Conflict());
            }

            try
            {
                EnsureDirectory();
                using FileStream directoryLock =
                    TryAcquireDirectoryLock();
                if (directoryLock == null)
                    return Task.FromResult(
                        HairRestoreStoreResult.Unavailable());

                if (!TryPruneSafeRecords(record.TransactionId))
                    return Task.FromResult(
                        HairRestoreStoreResult.Unavailable());

                string path = ResolveRecordPath(record.TransactionId);
                using FileStream recordLock = TryAcquireRecordLock(
                    record.TransactionId);
                if (recordLock == null)
                    return Task.FromResult(
                        HairRestoreStoreResult.Conflict());

                if (File.Exists(path))
                    return Task.FromResult(
                        HairRestoreStoreResult.Conflict());
                if (Directory.GetFiles(_directory, "hairtx_*.json").Length
                    >= MaximumRecords)
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.Unavailable());
                }

                HairRestorePointRecord stored =
                    record.WithStoreVersion(1);
                WriteAtomically(path, Serialize(stored));
                return Task.FromResult(
                    HairRestoreStoreResult.Success(stored));
            }
            catch (IOException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
            catch (UnauthorizedAccessException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
        }

        public Task<HairRestoreStoreResult> ReadAsync(
            string transactionId,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!IsSafeTransactionId(transactionId))
                return Task.FromResult(
                    HairRestoreStoreResult.NotFound());

            try
            {
                EnsureDirectory();
                using FileStream recordLock = TryAcquireRecordLock(
                    transactionId);
                if (recordLock == null)
                    return Task.FromResult(
                        HairRestoreStoreResult.Conflict());

                string path = ResolveRecordPath(transactionId);
                if (!File.Exists(path))
                    return Task.FromResult(
                        HairRestoreStoreResult.NotFound());
                HairRestorePointRecord record = ReadRecord(path);
                if (record == null
                    || !string.Equals(
                        record.TransactionId,
                        transactionId,
                        StringComparison.Ordinal))
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.Unavailable());
                }
                return Task.FromResult(
                    HairRestoreStoreResult.Success(record));
            }
            catch (IOException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
            catch (UnauthorizedAccessException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
            catch (InvalidDataException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
            catch (JsonException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
        }

        public Task<HairRestoreStoreResult> TryUpdateAsync(
            HairRestorePointRecord record,
            long expectedStoreVersion,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!IsValidRecord(record)
                || !IsSafeTransactionId(record.TransactionId)
                || expectedStoreVersion <= 0
                || record.StoreVersion != expectedStoreVersion)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Conflict());
            }

            try
            {
                EnsureDirectory();
                using FileStream recordLock = TryAcquireRecordLock(
                    record.TransactionId);
                if (recordLock == null)
                    return Task.FromResult(
                        HairRestoreStoreResult.Conflict());

                string path = ResolveRecordPath(record.TransactionId);
                if (!File.Exists(path))
                    return Task.FromResult(
                        HairRestoreStoreResult.NotFound());

                HairRestorePointRecord current = ReadRecord(path);
                if (current == null
                    || !string.Equals(
                        current.TransactionId,
                        record.TransactionId,
                        StringComparison.Ordinal))
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.Unavailable());
                }
                if (current.StoreVersion != expectedStoreVersion)
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.Conflict(current));
                }

                HairRestorePointRecord stored = record.WithStoreVersion(
                    checked(expectedStoreVersion + 1));
                WriteAtomically(path, Serialize(stored));
                return Task.FromResult(
                    HairRestoreStoreResult.Success(stored));
            }
            catch (OverflowException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
            catch (IOException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
            catch (UnauthorizedAccessException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
            catch (InvalidDataException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
            catch (JsonException)
            {
                return Task.FromResult(
                    HairRestoreStoreResult.Unavailable());
            }
        }

        internal static byte[] Serialize(
            HairRestorePointRecord record)
        {
            if (!IsValidRecord(record)
                || !IsSafeTransactionId(record.TransactionId))
                throw new InvalidDataException(
                    "The restore record is invalid.");

            var document = RestoreRecordDocument.From(record);
            byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(
                document,
                SerializerOptions);
            if (bytes.Length > MaximumDocumentBytes)
                throw new InvalidDataException(
                    "The restore record exceeds the size limit.");
            return bytes;
        }

        internal static HairRestorePointRecord Parse(
            ReadOnlySpan<byte> json)
        {
            if (json.Length == 0 || json.Length > MaximumDocumentBytes)
                throw new InvalidDataException(
                    "The restore record size is invalid.");

            using JsonDocument parsed = JsonDocument.Parse(
                json.ToArray(),
                new JsonDocumentOptions
                {
                    AllowTrailingCommas = false,
                    CommentHandling = JsonCommentHandling.Disallow,
                    MaxDepth = 4
                });
            JsonElement root = parsed.RootElement;
            RequireExactObject(root, RootPropertyNames);
            if (!root.TryGetProperty(
                    "binding",
                    out JsonElement bindingElement))
            {
                throw new InvalidDataException(
                    "The restore binding is missing.");
            }
            RequireExactObject(bindingElement, BindingPropertyNames);

            RestoreRecordDocument document =
                JsonSerializer.Deserialize<RestoreRecordDocument>(
                    json,
                    SerializerOptions)
                ?? throw new InvalidDataException(
                    "The restore record is empty.");
            HairRestorePointRecord record = document.ToRecord();
            if (document.V != 1
                || !IsSafeTransactionId(record.TransactionId)
                || !IsValidRecord(record))
            {
                throw new InvalidDataException(
                    "The restore record failed validation.");
            }
            return record;
        }

        private void EnsureDirectory()
        {
            Directory.CreateDirectory(_directory);
            _fileProtection.ProtectDirectory(_directory);
        }

        private FileStream TryAcquireDirectoryLock()
        {
            return TryAcquireLock(DirectoryLockPath);
        }

        private FileStream TryAcquireRecordLock(string transactionId)
        {
            return TryAcquireLock(
                Path.Combine(
                    _directory,
                    transactionId + ".lock"));
        }

        private FileStream TryAcquireLock(string path)
        {
            FileStream stream = null;
            try
            {
                stream = new FileStream(
                    path,
                    FileMode.OpenOrCreate,
                    FileAccess.ReadWrite,
                    FileShare.None,
                    1,
                    FileOptions.WriteThrough);
                _fileProtection.ProtectFile(path);
                return stream;
            }
            catch (IOException)
            {
                stream?.Dispose();
                return null;
            }
            catch (UnauthorizedAccessException)
            {
                stream?.Dispose();
                return null;
            }
        }

        private bool TryPruneSafeRecords(string protectedTransactionId)
        {
            DateTimeOffset now = DateTimeOffset.UtcNow;
            foreach (string path in Directory.EnumerateFiles(
                _directory,
                "hairtx_*.json",
                SearchOption.TopDirectoryOnly))
            {
                string transactionId = Path.GetFileNameWithoutExtension(
                    path);
                if (!IsSafeTransactionId(transactionId)
                    || string.Equals(
                        transactionId,
                        protectedTransactionId,
                        StringComparison.Ordinal))
                {
                    continue;
                }

                HairRestorePointRecord candidate;
                try
                {
                    candidate = ReadRecord(path);
                }
                catch (IOException)
                {
                    continue;
                }
                catch (UnauthorizedAccessException)
                {
                    continue;
                }
                catch (InvalidDataException)
                {
                    continue;
                }
                catch (JsonException)
                {
                    continue;
                }
                if (!CanPrune(candidate, now))
                    continue;

                using FileStream recordLock = TryAcquireRecordLock(
                    transactionId);
                if (recordLock == null)
                    return false;
                if (!File.Exists(path))
                    continue;

                HairRestorePointRecord confirmed;
                try
                {
                    confirmed = ReadRecord(path);
                }
                catch (IOException)
                {
                    return false;
                }
                catch (UnauthorizedAccessException)
                {
                    return false;
                }
                catch (InvalidDataException)
                {
                    return false;
                }
                catch (JsonException)
                {
                    return false;
                }
                if (!string.Equals(
                        confirmed.TransactionId,
                        transactionId,
                        StringComparison.Ordinal)
                    || !CanPrune(confirmed, now))
                {
                    continue;
                }

                try
                {
                    File.Delete(path);
                }
                catch (IOException)
                {
                    return false;
                }
                catch (UnauthorizedAccessException)
                {
                    return false;
                }
            }
            return true;
        }

        private static bool CanPrune(
            HairRestorePointRecord record,
            DateTimeOffset now)
        {
            if (record == null)
                return false;

            bool restoreAttempted =
                record.State == HairRestorePointState.RestorePending
                || record.State == HairRestorePointState.RestoreUnknown
                || record.State == HairRestorePointState.RestoreRejected
                || record.State == HairRestorePointState.Restored;
            if (record.State != HairRestorePointState.Expired
                && restoreAttempted != record.RestoreTokenConsumed)
            {
                return false;
            }

            switch (record.State)
            {
                case HairRestorePointState.CommitRejected:
                case HairRestorePointState.RestoreRejected:
                case HairRestorePointState.Restored:
                case HairRestorePointState.Expired:
                    return true;
                case HairRestorePointState.Committed:
                    return record.ExpiresAtUtc <= now;
                default:
                    return false;
            }
        }

        private string ResolveRecordPath(string transactionId)
        {
            if (!IsSafeTransactionId(transactionId))
                throw new InvalidDataException(
                    "The transaction id is invalid.");
            string path = Path.GetFullPath(
                Path.Combine(_directory, transactionId + ".json"));
            string prefix = Path.GetFullPath(_directory)
                .TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar)
                + Path.DirectorySeparatorChar;
            if (!path.StartsWith(
                prefix,
                StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException(
                    "The record path escaped its owned directory.");
            }
            return path;
        }

        private HairRestorePointRecord ReadRecord(string path)
        {
            var info = new FileInfo(path);
            if (!info.Exists
                || info.Length <= 0
                || info.Length > MaximumDocumentBytes)
            {
                throw new InvalidDataException(
                    "The restore record size is invalid.");
            }
            return Parse(File.ReadAllBytes(path));
        }

        private void WriteAtomically(string path, byte[] bytes)
        {
            string temporaryPath = Path.Combine(
                _directory,
                "." + Path.GetFileName(path) + "."
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
                File.Move(temporaryPath, path, true);
                _fileProtection.ProtectFile(path);
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
                    // A stale temporary file is neither a valid record nor a
                    // source of clear-text authority or restore credentials.
                }
            }
        }

        private static bool IsSafeTransactionId(string value)
        {
            return value != null
                && TransactionIdPattern.IsMatch(value);
        }

        private static bool IsValidRecord(HairRestorePointRecord record)
        {
            if (record == null
                || !HairAppearanceValidation.IsValidBinding(record.Binding)
                || !HairAppearanceValidation.IsSafeString(
                    record.BeforeHair,
                    160,
                    false)
                || !HairAppearanceValidation.IsSafeString(
                    record.AfterHair,
                    160,
                    false)
                || string.Equals(
                    record.BeforeHair,
                    record.AfterHair,
                    StringComparison.Ordinal)
                || record.BeforeRevision < 0
                || record.BeforeGeneration < 0
                || !HairAppearanceValidation.IsSha256(
                    record.BeforeSnapshotHash)
                || !HairAppearanceValidation.IsSha256(record.PreviewHash)
                || !HairAppearanceValidation.IsSha256(
                    record.RestoreTokenHash)
                || record.CreatedAtUtc == default
                || record.ExpiresAtUtc <= record.CreatedAtUtc
                || record.ExpiresAtUtc - record.CreatedAtUtc
                    > HairAppearanceModifierTransaction.MaximumRestoreTtl
                || record.StoreVersion < 0
                || record.AuthoritativeRevision < 0
                || record.AuthoritativeGeneration < 0
                || !HairAppearanceValidation.IsSha256(
                    record.AuthoritativeSnapshotHash)
                || !Enum.IsDefined(record.State))
            {
                return false;
            }

            string expectedPreviewHash =
                HairAppearanceHashing.ComputePreviewHash(
                    record.TransactionId,
                    record.Binding,
                    record.BeforeHair,
                    record.AfterHair,
                    record.BeforeRevision,
                    record.BeforeGeneration,
                    record.BeforeSnapshotHash);
            return string.Equals(
                expectedPreviewHash,
                record.PreviewHash,
                StringComparison.Ordinal);
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
                        "The restore record has an unknown or duplicate property.");
                }
            }
            if (!seen.SetEquals(expectedNames))
                throw new InvalidDataException(
                    "The restore record is missing a required property.");
        }

        private static JsonSerializerOptions CreateSerializerOptions()
        {
            var options = new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                PropertyNameCaseInsensitive = false,
                AllowTrailingCommas = false,
                ReadCommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 4,
                UnmappedMemberHandling =
                    JsonUnmappedMemberHandling.Disallow
            };
            options.Converters.Add(
                new JsonStringEnumConverter(
                    JsonNamingPolicy.SnakeCaseLower,
                    false));
            return options;
        }

        private sealed class RestoreRecordDocument
        {
            public int V { get; set; }
            public string TransactionId { get; set; }
            public BindingDocument Binding { get; set; }
            public string BeforeHair { get; set; }
            public string AfterHair { get; set; }
            public long BeforeRevision { get; set; }
            public long BeforeGeneration { get; set; }
            public string BeforeSnapshotHash { get; set; }
            public string PreviewHash { get; set; }
            public string RestoreTokenHash { get; set; }
            public DateTimeOffset CreatedAtUtc { get; set; }
            public DateTimeOffset ExpiresAtUtc { get; set; }
            public HairRestorePointState State { get; set; }
            public long StoreVersion { get; set; }
            public long AuthoritativeRevision { get; set; }
            public long AuthoritativeGeneration { get; set; }
            public string AuthoritativeSnapshotHash { get; set; }
            public bool RestoreTokenConsumed { get; set; }

            public static RestoreRecordDocument From(
                HairRestorePointRecord record)
            {
                return new RestoreRecordDocument
                {
                    V = 1,
                    TransactionId = record.TransactionId,
                    Binding = BindingDocument.From(record.Binding),
                    BeforeHair = record.BeforeHair,
                    AfterHair = record.AfterHair,
                    BeforeRevision = record.BeforeRevision,
                    BeforeGeneration = record.BeforeGeneration,
                    BeforeSnapshotHash = record.BeforeSnapshotHash,
                    PreviewHash = record.PreviewHash,
                    RestoreTokenHash = record.RestoreTokenHash,
                    CreatedAtUtc = record.CreatedAtUtc,
                    ExpiresAtUtc = record.ExpiresAtUtc,
                    State = record.State,
                    StoreVersion = record.StoreVersion,
                    AuthoritativeRevision =
                        record.AuthoritativeRevision,
                    AuthoritativeGeneration =
                        record.AuthoritativeGeneration,
                    AuthoritativeSnapshotHash =
                        record.AuthoritativeSnapshotHash,
                    RestoreTokenConsumed =
                        record.RestoreTokenConsumed
                };
            }

            public HairRestorePointRecord ToRecord()
            {
                return new HairRestorePointRecord(
                    TransactionId,
                    Binding?.ToBinding(),
                    BeforeHair,
                    AfterHair,
                    BeforeRevision,
                    BeforeGeneration,
                    BeforeSnapshotHash,
                    PreviewHash,
                    RestoreTokenHash,
                    CreatedAtUtc,
                    ExpiresAtUtc,
                    State,
                    StoreVersion,
                    AuthoritativeRevision,
                    AuthoritativeGeneration,
                    AuthoritativeSnapshotHash,
                    RestoreTokenConsumed);
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
