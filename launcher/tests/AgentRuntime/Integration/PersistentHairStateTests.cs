using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Transport;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class PersistentHairStateTests : IDisposable
    {
        private readonly string _temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            "cf7-hair-state-tests",
            Guid.NewGuid().ToString("N"));
        private readonly RecordingProtection _protection =
            new RecordingProtection();

        [Fact]
        public async Task RestoreStore_CreateReadUpdateAndRestart_AreOptimistic()
        {
            PersistentHairRestorePointStore first = CreateRestoreStore();
            HairRestorePointRecord prepared = CreateRecord();

            HairRestoreStoreResult created = await first.TryCreateAsync(
                prepared,
                CancellationToken.None);
            Assert.Equal(HairRestoreStoreStatus.Success, created.Status);
            Assert.Equal(1, created.Record.StoreVersion);

            PersistentHairRestorePointStore restarted =
                CreateRestoreStore();
            HairRestoreStoreResult read = await restarted.ReadAsync(
                prepared.TransactionId,
                CancellationToken.None);
            Assert.Equal(HairRestoreStoreStatus.Success, read.Status);
            Assert.Equal(
                prepared.RestoreTokenHash,
                read.Record.RestoreTokenHash);

            HairRestorePointRecord replacement = read.Record.With(
                HairRestorePointState.CommitUnknown,
                read.Record.AuthoritativeRevision,
                read.Record.AuthoritativeGeneration,
                read.Record.AuthoritativeSnapshotHash,
                false);
            HairRestoreStoreResult updated =
                await restarted.TryUpdateAsync(
                    replacement,
                    1,
                    CancellationToken.None);
            Assert.Equal(HairRestoreStoreStatus.Success, updated.Status);
            Assert.Equal(2, updated.Record.StoreVersion);

            HairRestoreStoreResult stale =
                await first.TryUpdateAsync(
                    read.Record,
                    1,
                    CancellationToken.None);
            Assert.Equal(HairRestoreStoreStatus.Conflict, stale.Status);
            Assert.Equal(2, stale.Record.StoreVersion);
        }

        [Fact]
        public async Task RestoreStore_ConcurrentCreatesAt127_HaveStrictPhysicalLimit()
        {
            PersistentHairRestorePointStore first = CreateRestoreStore();
            PersistentHairRestorePointStore second = CreateRestoreStore();
            for (int index = 0;
                index < PersistentHairRestorePointStore.MaximumRecords - 1;
                index++)
            {
                HairRestoreStoreResult seeded =
                    await first.TryCreateAsync(
                        CreateRecord(TransactionId(index)),
                        CancellationToken.None);
                Assert.Equal(
                    HairRestoreStoreStatus.Success,
                    seeded.Status);
            }

            using var start = new ManualResetEventSlim(false);
            Task<HairRestoreStoreResult> firstCreate = Task.Run(
                async () =>
                {
                    start.Wait();
                    return await first.TryCreateAsync(
                        CreateRecord(TransactionId(1000)),
                        CancellationToken.None);
                });
            Task<HairRestoreStoreResult> secondCreate = Task.Run(
                async () =>
                {
                    start.Wait();
                    return await second.TryCreateAsync(
                        CreateRecord(TransactionId(1001)),
                        CancellationToken.None);
                });
            start.Set();

            HairRestoreStoreResult[] results = await Task.WhenAll(
                firstCreate,
                secondCreate);
            Assert.Single(
                results,
                result =>
                    result.Status == HairRestoreStoreStatus.Success);
            Assert.Single(
                results,
                result =>
                    result.Status == HairRestoreStoreStatus.Unavailable);
            Assert.Equal(
                PersistentHairRestorePointStore.MaximumRecords,
                Directory.GetFiles(
                    first.DirectoryPath,
                    "hairtx_*.json",
                    SearchOption.TopDirectoryOnly).Length);
        }

        [Fact]
        public async Task RestoreStore_ExpiredCommittedRecordIsReclaimed()
        {
            PersistentHairRestorePointStore store = CreateRestoreStore();
            for (int index = 0;
                index < PersistentHairRestorePointStore.MaximumRecords - 1;
                index++)
            {
                Assert.Equal(
                    HairRestoreStoreStatus.Success,
                    (await store.TryCreateAsync(
                        CreateRecord(TransactionId(index)),
                        CancellationToken.None)).Status);
            }

            string expiredId = TransactionId(1000);
            HairRestorePointRecord expired = CreateRecord(
                expiredId,
                HairRestorePointState.Committed,
                DateTimeOffset.UtcNow.AddMinutes(-1));
            Assert.Equal(
                HairRestoreStoreStatus.Success,
                (await store.TryCreateAsync(
                    expired,
                    CancellationToken.None)).Status);

            string replacementId = TransactionId(1001);
            Assert.Equal(
                HairRestoreStoreStatus.Success,
                (await store.TryCreateAsync(
                    CreateRecord(replacementId),
                    CancellationToken.None)).Status);
            Assert.False(File.Exists(
                Path.Combine(
                    store.DirectoryPath,
                    expiredId + ".json")));
            Assert.True(File.Exists(
                Path.Combine(
                    store.DirectoryPath,
                    replacementId + ".json")));
            Assert.Equal(
                PersistentHairRestorePointStore.MaximumRecords,
                Directory.GetFiles(
                    store.DirectoryPath,
                    "hairtx_*.json",
                    SearchOption.TopDirectoryOnly).Length);
        }

        [Fact]
        public async Task RestoreStore_TerminalRecordIsReclaimedAfterRestart()
        {
            PersistentHairRestorePointStore first = CreateRestoreStore();
            string terminalId = TransactionId(0);
            Assert.Equal(
                HairRestoreStoreStatus.Success,
                (await first.TryCreateAsync(
                    CreateRecord(
                        terminalId,
                        HairRestorePointState.Restored),
                    CancellationToken.None)).Status);

            PersistentHairRestorePointStore restarted =
                CreateRestoreStore();
            string replacementId = TransactionId(1);
            Assert.Equal(
                HairRestoreStoreStatus.Success,
                (await restarted.TryCreateAsync(
                    CreateRecord(replacementId),
                    CancellationToken.None)).Status);
            Assert.Equal(
                HairRestoreStoreStatus.NotFound,
                (await restarted.ReadAsync(
                    terminalId,
                    CancellationToken.None)).Status);
            Assert.Equal(
                HairRestoreStoreStatus.Success,
                (await restarted.ReadAsync(
                    replacementId,
                    CancellationToken.None)).Status);
        }

        [Fact]
        public async Task RestoreStore_ExpiredPreparedAndUnknownRecordsAreNeverPruned()
        {
            PersistentHairRestorePointStore store = CreateRestoreStore();
            string preparedId = TransactionId(0);
            string commitUnknownId = TransactionId(1);
            string restoreUnknownId = TransactionId(2);
            DateTimeOffset expiredAt = DateTimeOffset.UtcNow.AddMinutes(-1);
            foreach (HairRestorePointRecord record in new[]
            {
                CreateRecord(
                    preparedId,
                    HairRestorePointState.Prepared,
                    expiredAt),
                CreateRecord(
                    commitUnknownId,
                    HairRestorePointState.CommitUnknown,
                    expiredAt),
                CreateRecord(
                    restoreUnknownId,
                    HairRestorePointState.RestoreUnknown,
                    expiredAt)
            })
            {
                Assert.Equal(
                    HairRestoreStoreStatus.Success,
                    (await store.TryCreateAsync(
                        record,
                        CancellationToken.None)).Status);
            }

            Assert.Equal(
                HairRestoreStoreStatus.Success,
                (await store.TryCreateAsync(
                    CreateRecord(TransactionId(3)),
                    CancellationToken.None)).Status);
            foreach (string transactionId in new[]
            {
                preparedId,
                commitUnknownId,
                restoreUnknownId
            })
            {
                Assert.Equal(
                    HairRestoreStoreStatus.Success,
                    (await store.ReadAsync(
                        transactionId,
                        CancellationToken.None)).Status);
            }
        }

        [Fact]
        public async Task RestoreStore_DirectoryLockCompetitionFailsClosed()
        {
            PersistentHairRestorePointStore store = CreateRestoreStore();
            Directory.CreateDirectory(store.DirectoryPath);
            using (var held = new FileStream(
                store.DirectoryLockPath,
                FileMode.OpenOrCreate,
                FileAccess.ReadWrite,
                FileShare.None))
            {
                HairRestoreStoreResult blocked =
                    await store.TryCreateAsync(
                        CreateRecord(),
                        CancellationToken.None);
                Assert.Equal(
                    HairRestoreStoreStatus.Unavailable,
                    blocked.Status);
            }

            Assert.Equal(
                HairRestoreStoreStatus.Success,
                (await store.TryCreateAsync(
                    CreateRecord(),
                    CancellationToken.None)).Status);
        }

        [Fact]
        public async Task RestoreStore_PruneRecordLockCompetitionFailsClosed()
        {
            PersistentHairRestorePointStore store = CreateRestoreStore();
            string terminalId = TransactionId(0);
            Assert.Equal(
                HairRestoreStoreStatus.Success,
                (await store.TryCreateAsync(
                    CreateRecord(
                        terminalId,
                        HairRestorePointState.CommitRejected),
                    CancellationToken.None)).Status);

            string terminalLockPath = Path.Combine(
                store.DirectoryPath,
                terminalId + ".lock");
            using (var held = new FileStream(
                terminalLockPath,
                FileMode.OpenOrCreate,
                FileAccess.ReadWrite,
                FileShare.None))
            {
                HairRestoreStoreResult blocked =
                    await store.TryCreateAsync(
                        CreateRecord(TransactionId(1)),
                        CancellationToken.None);
                Assert.Equal(
                    HairRestoreStoreStatus.Unavailable,
                    blocked.Status);
                Assert.True(File.Exists(
                    Path.Combine(
                        store.DirectoryPath,
                        terminalId + ".json")));
            }

            Assert.Equal(
                HairRestoreStoreStatus.Success,
                (await store.TryCreateAsync(
                    CreateRecord(TransactionId(1)),
                    CancellationToken.None)).Status);
            Assert.False(File.Exists(
                Path.Combine(
                    store.DirectoryPath,
                    terminalId + ".json")));
        }

        [Fact]
        public async Task RestoreStore_DuplicateCreateAndUnsafeIdFailClosed()
        {
            PersistentHairRestorePointStore store = CreateRestoreStore();
            HairRestorePointRecord record = CreateRecord();

            Assert.Equal(
                HairRestoreStoreStatus.Success,
                (await store.TryCreateAsync(
                    record,
                    CancellationToken.None)).Status);
            Assert.Equal(
                HairRestoreStoreStatus.Conflict,
                (await store.TryCreateAsync(
                    record,
                    CancellationToken.None)).Status);
            Assert.Equal(
                HairRestoreStoreStatus.NotFound,
                (await store.ReadAsync(
                    "../rendezvous",
                    CancellationToken.None)).Status);

            string expectedPrefix = Path.GetFullPath(
                store.DirectoryPath).TrimEnd(
                    Path.DirectorySeparatorChar)
                + Path.DirectorySeparatorChar;
            Assert.All(
                Directory.EnumerateFiles(
                    store.DirectoryPath,
                    "*",
                    SearchOption.TopDirectoryOnly),
                path => Assert.StartsWith(
                    expectedPrefix,
                    Path.GetFullPath(path),
                    StringComparison.OrdinalIgnoreCase));
        }

        [Fact]
        public void RestoreStore_SerializedRecordHasExactShapeAndNoClearToken()
        {
            HairRestorePointRecord record = CreateRecord();
            byte[] bytes =
                PersistentHairRestorePointStore.Serialize(record);
            string json = Encoding.UTF8.GetString(bytes);

            Assert.DoesNotContain(
                "clear-text-restore-token",
                json,
                StringComparison.Ordinal);
            HairRestorePointRecord parsed =
                PersistentHairRestorePointStore.Parse(bytes);
            Assert.Equal(record.TransactionId, parsed.TransactionId);
            Assert.Equal(record.PreviewHash, parsed.PreviewHash);
            Assert.Equal(record.Binding.SaveSignature,
                parsed.Binding.SaveSignature);
        }

        [Fact]
        public void RestoreStore_UnknownDuplicateAndOversizeDocumentsReject()
        {
            string valid = Encoding.UTF8.GetString(
                PersistentHairRestorePointStore.Serialize(
                    CreateRecord()));
            string unknown = valid.Insert(
                valid.Length - 1,
                ",\"unexpected\":true");
            string duplicate = valid.Replace(
                "\"v\":1",
                "\"v\":1,\"v\":1",
                StringComparison.Ordinal);

            Assert.Throws<InvalidDataException>(
                () => PersistentHairRestorePointStore.Parse(
                    Encoding.UTF8.GetBytes(unknown)));
            Assert.Throws<InvalidDataException>(
                () => PersistentHairRestorePointStore.Parse(
                    Encoding.UTF8.GetBytes(duplicate)));
            Assert.Throws<InvalidDataException>(
                () => PersistentHairRestorePointStore.Parse(
                    new byte[
                        PersistentHairRestorePointStore
                            .MaximumDocumentBytes + 1]));
        }

        [Fact]
        public async Task RestoreStore_CorruptionIsUnavailableNotNotFound()
        {
            PersistentHairRestorePointStore store = CreateRestoreStore();
            HairRestorePointRecord record = CreateRecord();
            await store.TryCreateAsync(
                record,
                CancellationToken.None);
            string path = Path.Combine(
                store.DirectoryPath,
                record.TransactionId + ".json");
            File.WriteAllText(
                path,
                "{\"v\":1,\"transactionId\":\"tampered\"}",
                Encoding.UTF8);

            HairRestoreStoreResult read = await store.ReadAsync(
                record.TransactionId,
                CancellationToken.None);
            Assert.Equal(HairRestoreStoreStatus.Unavailable, read.Status);
        }

        [Fact]
        public async Task RestoreStore_ProtectsDirectoryLockTemporaryAndFinalFiles()
        {
            PersistentHairRestorePointStore store = CreateRestoreStore();
            HairRestorePointRecord record = CreateRecord();
            HairRestoreStoreResult created = await store.TryCreateAsync(
                record,
                CancellationToken.None);
            Assert.Equal(HairRestoreStoreStatus.Success, created.Status);

            Assert.Contains(
                store.DirectoryPath,
                _protection.Directories);
            Assert.Contains(
                _protection.Files,
                path => path.EndsWith(
                    ".lock",
                    StringComparison.Ordinal));
            Assert.Contains(
                Path.Combine(
                    store.DirectoryPath,
                    record.TransactionId + ".json"),
                _protection.Files);
            Assert.DoesNotContain(
                Directory.EnumerateFiles(store.DirectoryPath),
                path => path.EndsWith(
                    ".tmp",
                    StringComparison.OrdinalIgnoreCase));
        }

        [Fact]
        public void Authority_RevisionsAreMonotonicAndRestartStable()
        {
            HairSaveBinding binding = CreateBinding();
            var first = new PersistentHairDomainAuthority(
                @"C:\Games\CrazyFlashNight",
                _temporaryRoot,
                _protection);
            HairDomainAuthorityStamp bound = first.Bind(binding, 12);
            Assert.Equal(12, bound.Revision);

            Assert.True(first.TryObserve(
                binding,
                "光头",
                out HairDomainAuthorityStamp initial,
                out string initialReason));
            Assert.Null(initialReason);
            Assert.Equal(12, initial.Revision);
            Assert.True(first.TryApply(
                binding,
                initial.Revision,
                initial.Generation,
                "光头",
                "发型-男式-平头",
                out HairDomainAuthorityStamp applied,
                out string applyReason));
            Assert.Null(applyReason);
            Assert.Equal(13, applied.Revision);

            var restarted = new PersistentHairDomainAuthority(
                @"c:\games\crazyflashnight\",
                _temporaryRoot,
                _protection);
            HairDomainAuthorityStamp rebound = restarted.Bind(
                binding,
                2);
            Assert.Equal(applied.Revision, rebound.Revision);
            Assert.Equal(applied.Generation, rebound.Generation);
            Assert.Equal(
                applied.CurrentHair,
                rebound.CurrentHair);
        }

        [Fact]
        public void Authority_DetectsHumanChangeCrossSaveAndRebind()
        {
            HairSaveBinding binding = CreateBinding();
            var authority = new PersistentHairDomainAuthority(
                @"C:\Games\CrazyFlashNight",
                _temporaryRoot,
                _protection);
            HairDomainAuthorityStamp bound = authority.Bind(binding, 0);
            Assert.True(authority.TryObserve(
                binding,
                "光头",
                out HairDomainAuthorityStamp first,
                out string ignored));
            Assert.True(authority.TryObserve(
                binding,
                "发型-女式-短发",
                out HairDomainAuthorityStamp humanChange,
                out ignored));
            Assert.Equal(first.Revision + 1, humanChange.Revision);

            HairSaveBinding other = new HairSaveBinding(
                "session_other_1234567890123456",
                binding.LifecycleGeneration,
                binding.AttemptId,
                binding.AttemptGeneration,
                binding.SlotId,
                binding.SaveSignature);
            Assert.False(authority.TryValidate(
                other,
                humanChange.Revision,
                humanChange.Generation,
                humanChange.CurrentHair,
                out string crossSave));
            Assert.Equal(HairAppearanceReasonCodes.CrossSave, crossSave);

            authority.Unbind();
            HairDomainAuthorityStamp rebound = authority.Bind(binding);
            Assert.True(rebound.Generation > bound.Generation);
            Assert.Null(rebound.CurrentHair);
        }

        public void Dispose()
        {
            if (!Directory.Exists(_temporaryRoot))
                return;
            string full = Path.GetFullPath(_temporaryRoot);
            string expected = Path.GetFullPath(
                Path.Combine(
                    Path.GetTempPath(),
                    "cf7-hair-state-tests"));
            if (full.StartsWith(
                expected + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase))
            {
                Directory.Delete(full, true);
            }
        }

        private PersistentHairRestorePointStore CreateRestoreStore()
        {
            return new PersistentHairRestorePointStore(
                @"C:\Games\CrazyFlashNight",
                _temporaryRoot,
                _protection);
        }

        private static HairRestorePointRecord CreateRecord(
            string transactionId =
                "hairtx_ABCDEFGHIJKLMNOPQRSTUVWX",
            HairRestorePointState state =
                HairRestorePointState.Prepared,
            DateTimeOffset? expiresAtUtc = null)
        {
            HairSaveBinding binding = CreateBinding();
            DateTimeOffset expiration =
                expiresAtUtc ?? DateTimeOffset.UtcNow.AddMinutes(15);
            string beforeSnapshotHash =
                new string('a', 64);
            string previewHash =
                HairAppearanceHashing.ComputePreviewHash(
                    transactionId,
                    binding,
                    "光头",
                    "发型-男式-平头",
                    7,
                    3,
                    beforeSnapshotHash);
            return new HairRestorePointRecord(
                transactionId,
                binding,
                "光头",
                "发型-男式-平头",
                7,
                3,
                beforeSnapshotHash,
                previewHash,
                HairAppearanceHashing.HashOpaqueToken(
                    "clear-text-restore-token"),
                expiration.AddMinutes(-15),
                expiration,
                state,
                0,
                7,
                3,
                beforeSnapshotHash,
                state == HairRestorePointState.RestorePending
                    || state == HairRestorePointState.RestoreUnknown
                    || state == HairRestorePointState.RestoreRejected
                    || state == HairRestorePointState.Restored);
        }

        private static string TransactionId(int value)
        {
            return "hairtx_" + value.ToString("D24");
        }

        private static HairSaveBinding CreateBinding()
        {
            return new HairSaveBinding(
                "session_ABCDEFGHIJKLMNOPQRSTUVWX",
                4,
                "attempt_ABCDEFGHIJKLMNOPQRSTUVWX",
                2,
                "slot1",
                new string('b', 64));
        }

        private sealed class RecordingProtection
            : IAgentRendezvousFileProtection
        {
            public List<string> Directories { get; } =
                new List<string>();
            public List<string> Files { get; } =
                new List<string>();

            public void ProtectDirectory(string path)
            {
                if (!Directories.Contains(
                    path,
                    StringComparer.OrdinalIgnoreCase))
                    Directories.Add(path);
            }

            public void ProtectFile(string path)
            {
                if (!Files.Contains(
                    path,
                    StringComparer.OrdinalIgnoreCase))
                    Files.Add(path);
            }
        }
    }
}
