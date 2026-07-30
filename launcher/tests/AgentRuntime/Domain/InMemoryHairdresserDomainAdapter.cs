using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Domain;

namespace CF7Launcher.Tests.AgentRuntime.Domain
{
    public enum FakeHairCommitBehavior
    {
        Applied = 0,
        Rejected = 1,
        AppliedThenUnknown = 2,
        UnknownWithoutApply = 3,
        AppliedThenThrow = 4,
        MalformedAppliedAck = 5
    }

    internal sealed class InMemoryHairdresserDomainAdapter
        : IHairdresserDomainAdapter
    {
        private readonly object _gate = new object();
        private HairSaveBinding _binding;
        private long _revision;
        private long _generation;
        private string _currentHair;
        private readonly IReadOnlyList<HairCatalogEntry> _catalog;

        public InMemoryHairdresserDomainAdapter(
            HairSaveBinding binding,
            string currentHair,
            long revision = 7,
            long generation = 3)
        {
            _binding = binding;
            _currentHair = currentHair;
            _revision = revision;
            _generation = generation;
            _catalog = new[]
            {
                new HairCatalogEntry("光头", "光头"),
                new HairCatalogEntry("发型-男式-平头", "男式平头"),
                new HairCatalogEntry("发型-女式-短发", "女式短发"),
                new HairCatalogEntry("发型-男式-平头", "男式平头（源重复行）")
            };
        }

        public FakeHairCommitBehavior NextCommitBehavior { get; set; } =
            FakeHairCommitBehavior.Applied;

        public string RejectionReason { get; set; } =
            HairAppearanceReasonCodes.StaleState;

        public string InspectFailure { get; set; }

        public Action<HairDomainCommitCommand> BeforeCommit { get; set; }

        public List<HairDomainCommitCommand> CommitCommands { get; } =
            new List<HairDomainCommitCommand>();

        public HairAuthoritativeSnapshot CurrentSnapshot
        {
            get
            {
                lock (_gate)
                {
                    return SnapshotLocked();
                }
            }
        }

        public Task<HairAdapterInspectResult> InspectAsync(
            HairSaveBinding expectedBinding,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            lock (_gate)
            {
                if (InspectFailure != null)
                {
                    return Task.FromResult(
                        HairAdapterInspectResult.Failed(InspectFailure));
                }
                return Task.FromResult(
                    HairAdapterInspectResult.Succeeded(SnapshotLocked()));
            }
        }

        public Task<HairAdapterCommitResult> CommitAsync(
            HairDomainCommitCommand command,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            BeforeCommit?.Invoke(command);
            lock (_gate)
            {
                CommitCommands.Add(command);
                HairAuthoritativeSnapshot before = SnapshotLocked();
                if (!_binding.Equals(command.Binding))
                {
                    return Task.FromResult(
                        HairAdapterCommitResult.Rejected(
                            HairAppearanceReasonCodes.CrossSave));
                }
                if (_revision != command.ExpectedRevision
                    || _generation != command.ExpectedGeneration)
                {
                    return Task.FromResult(
                        HairAdapterCommitResult.Rejected(
                            HairAppearanceReasonCodes.StaleRevision));
                }
                if (!string.Equals(
                        _currentHair,
                        command.ExpectedCurrentHair,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        HairAppearanceHashing.ComputeSnapshotHash(before),
                        command.ExpectedSnapshotHash,
                        StringComparison.Ordinal))
                {
                    return Task.FromResult(
                        HairAdapterCommitResult.Rejected(
                            HairAppearanceReasonCodes.StaleState));
                }
                if (!Contains(command.HairIdentifier))
                {
                    return Task.FromResult(
                        HairAdapterCommitResult.Rejected(
                            HairAppearanceReasonCodes.HairNotFound));
                }

                FakeHairCommitBehavior behavior = NextCommitBehavior;
                NextCommitBehavior = FakeHairCommitBehavior.Applied;
                if (behavior == FakeHairCommitBehavior.Rejected)
                {
                    return Task.FromResult(
                        HairAdapterCommitResult.Rejected(RejectionReason));
                }
                if (behavior == FakeHairCommitBehavior.UnknownWithoutApply)
                {
                    return Task.FromResult(
                        HairAdapterCommitResult.Unknown(
                            HairAppearanceReasonCodes.UnknownWriteOutcome));
                }

                _currentHair = command.HairIdentifier;
                _revision++;
                HairAuthoritativeSnapshot after = SnapshotLocked();
                if (behavior == FakeHairCommitBehavior.AppliedThenUnknown)
                {
                    return Task.FromResult(
                        HairAdapterCommitResult.Unknown(
                            HairAppearanceReasonCodes.UnknownWriteOutcome));
                }
                if (behavior == FakeHairCommitBehavior.AppliedThenThrow)
                {
                    throw new InvalidOperationException(
                        "simulated acknowledgement loss");
                }
                if (behavior == FakeHairCommitBehavior.MalformedAppliedAck)
                {
                    return Task.FromResult(
                        HairAdapterCommitResult.Applied(
                            new HairAuthoritativeSnapshot(
                                _binding,
                                _revision,
                                _generation,
                                "目录外发型",
                                _catalog)));
                }
                return Task.FromResult(HairAdapterCommitResult.Applied(after));
            }
        }

        public void HumanChange(string hairIdentifier)
        {
            lock (_gate)
            {
                _currentHair = hairIdentifier;
                _revision++;
            }
        }

        public void ReplaceBinding(HairSaveBinding binding)
        {
            lock (_gate)
            {
                _binding = binding;
                _revision++;
                _generation++;
            }
        }

        private HairAuthoritativeSnapshot SnapshotLocked()
        {
            return new HairAuthoritativeSnapshot(
                _binding,
                _revision,
                _generation,
                _currentHair,
                _catalog);
        }

        private bool Contains(string identifier)
        {
            for (int i = 0; i < _catalog.Count; i++)
            {
                if (string.Equals(
                    _catalog[i].Identifier,
                    identifier,
                    StringComparison.Ordinal))
                {
                    return true;
                }
            }
            return false;
        }
    }
}
