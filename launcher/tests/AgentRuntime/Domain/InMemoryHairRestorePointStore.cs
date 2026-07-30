using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Domain;

namespace CF7Launcher.Tests.AgentRuntime.Domain
{
    internal sealed class InMemoryHairRestorePointStore
        : IHairRestorePointStore
    {
        private readonly object _gate = new object();
        private readonly Dictionary<string, HairRestorePointRecord> _records =
            new Dictionary<string, HairRestorePointRecord>(
                StringComparer.Ordinal);

        public bool FailCreate { get; set; }

        public bool FailRead { get; set; }

        public bool FailUpdate { get; set; }

        public int? FailUpdateOnCall { get; set; }

        public int UpdateCalls { get; private set; }

        public HairRestorePointRecord ReadDirect(string transactionId)
        {
            lock (_gate)
            {
                HairRestorePointRecord record;
                return _records.TryGetValue(transactionId, out record)
                    ? record
                    : null;
            }
        }

        public Task<HairRestoreStoreResult> TryCreateAsync(
            HairRestorePointRecord record,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            lock (_gate)
            {
                if (FailCreate)
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.Unavailable());
                }
                if (record == null
                    || record.StoreVersion != 0
                    || _records.ContainsKey(record.TransactionId))
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.Conflict());
                }

                HairRestorePointRecord stored = record.WithStoreVersion(1);
                _records.Add(stored.TransactionId, stored);
                return Task.FromResult(
                    HairRestoreStoreResult.Success(stored));
            }
        }

        public Task<HairRestoreStoreResult> ReadAsync(
            string transactionId,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            lock (_gate)
            {
                if (FailRead)
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.Unavailable());
                }
                HairRestorePointRecord record;
                if (!_records.TryGetValue(transactionId, out record))
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.NotFound());
                }
                return Task.FromResult(
                    HairRestoreStoreResult.Success(record));
            }
        }

        public Task<HairRestoreStoreResult> TryUpdateAsync(
            HairRestorePointRecord record,
            long expectedStoreVersion,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            lock (_gate)
            {
                UpdateCalls++;
                if (FailUpdate
                    || FailUpdateOnCall == UpdateCalls)
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.Unavailable());
                }
                HairRestorePointRecord current;
                if (record == null
                    || !_records.TryGetValue(
                        record.TransactionId,
                        out current))
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.NotFound());
                }
                if (current.StoreVersion != expectedStoreVersion)
                {
                    return Task.FromResult(
                        HairRestoreStoreResult.Conflict(current));
                }

                HairRestorePointRecord stored =
                    record.WithStoreVersion(expectedStoreVersion + 1);
                _records[stored.TransactionId] = stored;
                return Task.FromResult(
                    HairRestoreStoreResult.Success(stored));
            }
        }
    }
}
