using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal enum WingsOperationState
    {
        Offline,
        Idle,
        Observing,
        Advising,
        AwaitingGrant,
        Executing,
        Reporting,
        SafeError
    }

    [Flags]
    internal enum WingsPrivilegeDowngrade
    {
        None = 0,
        RevokeObservationGrant = 1 << 0,
        RevokeWriteLease = 1 << 1,
        CancelPendingActions = 1 << 2,
        RevokeOneShotTokens = 1 << 3
    }

    internal sealed class TrustedStoryPhaseTransition
    {
        internal TrustedStoryPhaseTransition(
            string transitionReceiptId,
            string storyPhaseId,
            bool publicCompanionEligible,
            long authorityRevision)
        {
            WingsProtocolValue.RequireOpaqueId(
                transitionReceiptId,
                nameof(transitionReceiptId));
            WingsProtocolValue.RequireOpaqueId(
                storyPhaseId,
                nameof(storyPhaseId));
            if (authorityRevision <= 0)
                throw new ArgumentOutOfRangeException(
                    nameof(authorityRevision));

            TransitionReceiptId = transitionReceiptId;
            StoryPhaseId = storyPhaseId;
            PublicCompanionEligible = publicCompanionEligible;
            AuthorityRevision = authorityRevision;
        }

        public string TransitionReceiptId { get; }
        public string StoryPhaseId { get; }
        public bool PublicCompanionEligible { get; }
        public long AuthorityRevision { get; }
    }

    /// <summary>
    /// Only the host narrative-progress authority can turn its receipt into a
    /// trusted phase transition. Persona/model text is not an authority input.
    /// </summary>
    internal interface IStoryPhaseAuthority
    {
        bool TryResolveTransition(
            string transitionReceiptId,
            out TrustedStoryPhaseTransition transition,
            out string reasonCode);
    }

    internal sealed class WingsPersonaStateSnapshot
    {
        public WingsPersonaStateSnapshot(
            string storyPhaseId,
            long storyAuthorityRevision,
            bool publicCompanionEligible,
            WingsOperationState operationState)
        {
            StoryPhaseId = storyPhaseId;
            StoryAuthorityRevision = storyAuthorityRevision;
            PublicCompanionEligible = publicCompanionEligible;
            OperationState = operationState;
        }

        public string StoryPhaseId { get; }
        public long StoryAuthorityRevision { get; }
        public bool PublicCompanionEligible { get; }
        public WingsOperationState OperationState { get; }
    }

    internal sealed class WingsStoryPhaseChange
    {
        public WingsStoryPhaseChange(
            WingsPersonaStateSnapshot snapshot,
            WingsPrivilegeDowngrade downgrade)
        {
            Snapshot = snapshot;
            Downgrade = downgrade;
        }

        public WingsPersonaStateSnapshot Snapshot { get; }
        public WingsPrivilegeDowngrade Downgrade { get; }
    }

    /// <summary>
    /// Story and tool lifecycle are deliberately independent state machines.
    /// Story transitions can only preserve or reduce privileges.
    /// </summary>
    internal sealed class WingsPersonaStateMachine
    {
        private const WingsPrivilegeDowngrade PublicPhaseExitDowngrade =
            WingsPrivilegeDowngrade.RevokeObservationGrant
            | WingsPrivilegeDowngrade.RevokeWriteLease
            | WingsPrivilegeDowngrade.CancelPendingActions
            | WingsPrivilegeDowngrade.RevokeOneShotTokens;

        private static readonly IReadOnlyDictionary<
            WingsOperationState,
            HashSet<WingsOperationState>> AllowedTransitions =
                CreateAllowedTransitions();

        private readonly object _sync = new object();
        private string _storyPhaseId;
        private long _storyAuthorityRevision;
        private bool _publicCompanionEligible;
        private WingsOperationState _operationState;

        public WingsPersonaStateMachine(
            string initialStoryPhaseId,
            long storyAuthorityRevision,
            bool publicCompanionEligible,
            WingsOperationState initialOperationState =
                WingsOperationState.Offline)
        {
            WingsProtocolValue.RequireOpaqueId(
                initialStoryPhaseId,
                nameof(initialStoryPhaseId));
            if (storyAuthorityRevision <= 0)
                throw new ArgumentOutOfRangeException(
                    nameof(storyAuthorityRevision));
            if (!Enum.IsDefined(initialOperationState))
                throw new ArgumentOutOfRangeException(
                    nameof(initialOperationState));

            _storyPhaseId = initialStoryPhaseId;
            _storyAuthorityRevision = storyAuthorityRevision;
            _publicCompanionEligible = publicCompanionEligible;
            _operationState = initialOperationState;
        }

        public WingsPersonaStateSnapshot Snapshot
        {
            get
            {
                lock (_sync)
                {
                    return SnapshotLocked();
                }
            }
        }

        public WingsPersonaStateSnapshot TransitionOperation(
            WingsOperationState next)
        {
            if (!Enum.IsDefined(next))
                throw new ArgumentOutOfRangeException(nameof(next));
            lock (_sync)
            {
                if (_operationState == next)
                    return SnapshotLocked();
                if (!AllowedTransitions[_operationState].Contains(next))
                {
                    throw new InvalidOperationException(
                        "operation_transition_invalid");
                }
                _operationState = next;
                return SnapshotLocked();
            }
        }

        public WingsStoryPhaseChange ApplyStoryPhaseTransition(
            string transitionReceiptId,
            IStoryPhaseAuthority authority)
        {
            if (authority == null)
                throw new ArgumentNullException(nameof(authority));
            WingsProtocolValue.RequireOpaqueId(
                transitionReceiptId,
                nameof(transitionReceiptId));
            if (!authority.TryResolveTransition(
                    transitionReceiptId,
                    out TrustedStoryPhaseTransition transition,
                    out string reasonCode)
                || transition == null)
            {
                throw new InvalidOperationException(
                    reasonCode ?? "story_phase_authority_rejected");
            }
            if (!string.Equals(
                    transition.TransitionReceiptId,
                    transitionReceiptId,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "story_phase_receipt_mismatch");
            }

            lock (_sync)
            {
                if (transition.AuthorityRevision
                    <= _storyAuthorityRevision)
                {
                    throw new InvalidOperationException(
                        "story_phase_revision_stale");
                }

                bool wasEligible = _publicCompanionEligible;
                _storyPhaseId = transition.StoryPhaseId;
                _storyAuthorityRevision =
                    transition.AuthorityRevision;
                _publicCompanionEligible =
                    transition.PublicCompanionEligible;
                WingsPrivilegeDowngrade downgrade =
                    wasEligible && !_publicCompanionEligible
                        ? PublicPhaseExitDowngrade
                        : WingsPrivilegeDowngrade.None;
                return new WingsStoryPhaseChange(
                    SnapshotLocked(),
                    downgrade);
            }
        }

        private WingsPersonaStateSnapshot SnapshotLocked()
        {
            return new WingsPersonaStateSnapshot(
                _storyPhaseId,
                _storyAuthorityRevision,
                _publicCompanionEligible,
                _operationState);
        }

        private static IReadOnlyDictionary<
            WingsOperationState,
            HashSet<WingsOperationState>> CreateAllowedTransitions()
        {
            return new Dictionary<
                WingsOperationState,
                HashSet<WingsOperationState>>
            {
                [WingsOperationState.Offline] = Set(
                    WingsOperationState.Idle),
                [WingsOperationState.Idle] = Set(
                    WingsOperationState.Offline,
                    WingsOperationState.Observing,
                    WingsOperationState.Advising,
                    WingsOperationState.AwaitingGrant,
                    WingsOperationState.SafeError),
                [WingsOperationState.Observing] = Set(
                    WingsOperationState.Idle,
                    WingsOperationState.Advising,
                    WingsOperationState.AwaitingGrant,
                    WingsOperationState.SafeError),
                [WingsOperationState.Advising] = Set(
                    WingsOperationState.Idle,
                    WingsOperationState.Observing,
                    WingsOperationState.AwaitingGrant,
                    WingsOperationState.SafeError),
                [WingsOperationState.AwaitingGrant] = Set(
                    WingsOperationState.Idle,
                    WingsOperationState.Executing,
                    WingsOperationState.SafeError),
                [WingsOperationState.Executing] = Set(
                    WingsOperationState.Reporting,
                    WingsOperationState.SafeError),
                [WingsOperationState.Reporting] = Set(
                    WingsOperationState.Idle,
                    WingsOperationState.Advising,
                    WingsOperationState.SafeError),
                [WingsOperationState.SafeError] = Set(
                    WingsOperationState.Offline,
                    WingsOperationState.Idle)
            };
        }

        private static HashSet<WingsOperationState> Set(
            params WingsOperationState[] values)
        {
            return new HashSet<WingsOperationState>(values);
        }
    }

    internal static class WingsProtocolValue
    {
        private static readonly Regex OpaqueIdPattern = new Regex(
            "^[A-Za-z0-9_-]{22,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex StableKeyPattern = new Regex(
            "^[a-z][a-z0-9._-]{2,127}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex Sha256Pattern = new Regex(
            "^[A-Fa-f0-9]{64}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);

        public static void RequireOpaqueId(
            string value,
            string parameterName)
        {
            if (!OpaqueIdPattern.IsMatch(value ?? string.Empty))
                throw new ArgumentException(
                    "An opaque 128-bit-or-stronger id is required.",
                    parameterName);
        }

        public static void RequireStableKey(
            string value,
            string parameterName)
        {
            if (!StableKeyPattern.IsMatch(value ?? string.Empty))
                throw new ArgumentException(
                    "A registered stable key is required.",
                    parameterName);
        }

        public static void RequireSha256(
            string value,
            string parameterName)
        {
            if (!Sha256Pattern.IsMatch(value ?? string.Empty))
                throw new ArgumentException(
                    "A hexadecimal SHA-256 is required.",
                    parameterName);
        }

        public static void RequireText(
            string value,
            int maximumLength,
            string parameterName)
        {
            if (string.IsNullOrWhiteSpace(value)
                || value.Length > maximumLength)
            {
                throw new ArgumentException(
                    "A bounded non-empty value is required.",
                    parameterName);
            }
        }
    }
}
