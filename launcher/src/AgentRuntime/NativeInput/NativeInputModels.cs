using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Input;

namespace CF7Launcher.AgentRuntime.NativeInput
{
    public readonly record struct NativeScreenPoint(int X, int Y);

    public enum NativeInputPacketKind
    {
        Keyboard,
        Mouse
    }

    public enum NativeControlTransition
    {
        None,
        Down,
        Up
    }

    /// <summary>
    /// A deliberately small representation of one Win32 INPUT record.
    /// Callers remain responsible for using only the operation-specific
    /// key/button allow-list established by the Agent gateway.
    /// </summary>
    public sealed class NativeInputPacket
    {
        private NativeInputPacket(
            NativeInputPacketKind kind,
            ushort virtualKey,
            ushort scanCode,
            uint keyboardFlags,
            int mouseDx,
            int mouseDy,
            uint mouseData,
            uint mouseFlags,
            string controlId,
            NativeControlTransition transition)
        {
            Kind = kind;
            VirtualKey = virtualKey;
            ScanCode = scanCode;
            KeyboardFlags = keyboardFlags;
            MouseDx = mouseDx;
            MouseDy = mouseDy;
            MouseData = mouseData;
            MouseFlags = mouseFlags;
            ControlId = controlId;
            Transition = transition;
        }

        public NativeInputPacketKind Kind { get; }
        public ushort VirtualKey { get; }
        public ushort ScanCode { get; }
        public uint KeyboardFlags { get; }
        public int MouseDx { get; }
        public int MouseDy { get; }
        public uint MouseData { get; }
        public uint MouseFlags { get; }
        public string ControlId { get; }
        public NativeControlTransition Transition { get; }

        public static NativeInputPacket Key(
            ushort virtualKey,
            ushort scanCode,
            uint flags,
            bool keyUp)
        {
            if (virtualKey == 0 && scanCode == 0)
            {
                throw new ArgumentException(
                    "A virtual key or scan code is required.");
            }

            const uint KeyEventFKeyUp = 0x0002;
            uint normalizedFlags = keyUp
                ? flags | KeyEventFKeyUp
                : flags & ~KeyEventFKeyUp;
            return new NativeInputPacket(
                NativeInputPacketKind.Keyboard,
                virtualKey,
                scanCode,
                normalizedFlags,
                0,
                0,
                0,
                0,
                "Key:" + virtualKey,
                keyUp
                    ? NativeControlTransition.Up
                    : NativeControlTransition.Down);
        }

        public static NativeInputPacket Unicode(
            char value,
            bool keyUp)
        {
            const uint KeyEventFKeyUp = 0x0002;
            const uint KeyEventFUnicode = 0x0004;
            return new NativeInputPacket(
                NativeInputPacketKind.Keyboard,
                0,
                value,
                KeyEventFUnicode
                    | (keyUp ? KeyEventFKeyUp : 0),
                0,
                0,
                0,
                0,
                "Unicode:" + ((int)value).ToString("X4"),
                keyUp
                    ? NativeControlTransition.Up
                    : NativeControlTransition.Down);
        }

        public static NativeInputPacket Mouse(
            int dx,
            int dy,
            uint mouseData,
            uint flags,
            string controlId = null,
            NativeControlTransition transition =
                NativeControlTransition.None)
        {
            if (transition != NativeControlTransition.None
                && string.IsNullOrWhiteSpace(controlId))
            {
                throw new ArgumentException(
                    "A button transition requires a control ID.",
                    nameof(controlId));
            }
            return new NativeInputPacket(
                NativeInputPacketKind.Mouse,
                0,
                0,
                0,
                dx,
                dy,
                mouseData,
                flags,
                controlId,
                transition);
        }

        public NativeInputPacket CreateRelease()
        {
            const uint KeyEventFKeyUp = 0x0002;
            const uint MouseEventFLeftUp = 0x0004;
            const uint MouseEventFRightUp = 0x0010;
            const uint MouseEventFMiddleUp = 0x0040;
            const uint MouseEventFXUp = 0x0100;

            if (Transition != NativeControlTransition.Down)
            {
                throw new InvalidOperationException(
                    "Only a control-down packet has a release.");
            }
            if (Kind == NativeInputPacketKind.Keyboard)
            {
                return new NativeInputPacket(
                    Kind,
                    VirtualKey,
                    ScanCode,
                    KeyboardFlags | KeyEventFKeyUp,
                    0,
                    0,
                    0,
                    0,
                    ControlId,
                    NativeControlTransition.Up);
            }

            uint releaseFlag;
            if ((MouseFlags & 0x0002) != 0)
            {
                releaseFlag = MouseEventFLeftUp;
            }
            else if ((MouseFlags & 0x0008) != 0)
            {
                releaseFlag = MouseEventFRightUp;
            }
            else if ((MouseFlags & 0x0020) != 0)
            {
                releaseFlag = MouseEventFMiddleUp;
            }
            else if ((MouseFlags & 0x0080) != 0)
            {
                releaseFlag = MouseEventFXUp;
            }
            else
            {
                throw new InvalidOperationException(
                    "Unsupported mouse button-down flag.");
            }
            return new NativeInputPacket(
                Kind,
                0,
                0,
                0,
                MouseDx,
                MouseDy,
                MouseData,
                releaseFlag,
                ControlId,
                NativeControlTransition.Up);
        }
    }

    internal interface INativeInputProcessIdentitySignal
        : IDisposable
    {
        bool IsAliveBounded();
    }

    public sealed class NativeInputTargetSnapshot : IDisposable
    {
        private INativeInputProcessIdentitySignal
            _processIdentitySignal;

        public NativeInputTargetSnapshot(
            string sessionId,
            string targetId,
            IntPtr topLevelHwnd,
            int ownerProcessId,
            InputEpochSnapshot epochs,
            bool visible,
            bool minimized,
            bool securityModalLatched)
            : this(
                sessionId,
                targetId,
                topLevelHwnd,
                topLevelHwnd,
                ownerProcessId,
                epochs,
                visible,
                minimized,
                securityModalLatched)
        {
        }

        public NativeInputTargetSnapshot(
            string sessionId,
            string targetId,
            IntPtr targetHwnd,
            IntPtr topLevelHwnd,
            int ownerProcessId,
            InputEpochSnapshot epochs,
            bool visible,
            bool minimized,
            bool securityModalLatched)
            : this(
                sessionId,
                targetId,
                targetHwnd,
                topLevelHwnd,
                ownerProcessId,
                epochs,
                visible,
                minimized,
                securityModalLatched,
                0,
                null)
        {
        }

        internal NativeInputTargetSnapshot(
            string sessionId,
            string targetId,
            IntPtr targetHwnd,
            IntPtr topLevelHwnd,
            int ownerProcessId,
            InputEpochSnapshot epochs,
            bool visible,
            bool minimized,
            bool securityModalLatched,
            long expectedOwnerWindowHandle,
            INativeInputProcessIdentitySignal processIdentitySignal)
        {
            if (string.IsNullOrWhiteSpace(sessionId))
            {
                throw new ArgumentException(
                    "A session ID is required.",
                    nameof(sessionId));
            }
            if (string.IsNullOrWhiteSpace(targetId))
            {
                throw new ArgumentException(
                    "A target ID is required.",
                    nameof(targetId));
            }
            if (targetHwnd == IntPtr.Zero)
            {
                throw new ArgumentException(
                    "A non-zero registered target HWND is required.",
                    nameof(targetHwnd));
            }
            if (topLevelHwnd == IntPtr.Zero)
            {
                throw new ArgumentException(
                    "A non-zero foreground top-level HWND is required.",
                    nameof(topLevelHwnd));
            }
            if (ownerProcessId <= 0)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(ownerProcessId));
            }

            SessionId = sessionId;
            TargetId = targetId;
            TargetHwnd = targetHwnd;
            TopLevelHwnd = topLevelHwnd;
            OwnerProcessId = ownerProcessId;
            Epochs = epochs
                ?? throw new ArgumentNullException(nameof(epochs));
            Visible = visible;
            Minimized = minimized;
            SecurityModalLatched = securityModalLatched;
            ExpectedOwnerWindowHandle =
                expectedOwnerWindowHandle;
            _processIdentitySignal =
                processIdentitySignal;
        }

        public string SessionId { get; }
        public string TargetId { get; }
        public IntPtr TargetHwnd { get; }
        public IntPtr TopLevelHwnd { get; }
        public int OwnerProcessId { get; }
        public InputEpochSnapshot Epochs { get; }
        public bool Visible { get; }
        public bool Minimized { get; }
        public bool SecurityModalLatched { get; }

        internal long ExpectedOwnerWindowHandle { get; }
        internal bool HasBoundedProcessIdentitySignal =>
            _processIdentitySignal != null;

        internal bool IsProcessIdentityAliveBounded()
        {
            INativeInputProcessIdentitySignal signal =
                _processIdentitySignal;
            return signal != null
                && signal.IsAliveBounded();
        }

        public void Dispose()
        {
            Interlocked.Exchange(
                    ref _processIdentitySignal,
                    null)
                ?.Dispose();
        }
    }

    /// <summary>
    /// Implemented by SessionSurfaceRegistry. It must resolve only
    /// Launcher-owner positive registrations; window titles and process
    /// names are never authority. Hook callbacks use only the explicitly
    /// bounded TryValidateDispatchIdentity path.
    /// </summary>
    public interface IAuthoritativeNativeInputTarget
    {
        bool TryResolve(
            string sessionId,
            string targetId,
            out NativeInputTargetSnapshot target,
            out string reasonCode);

        /// <summary>
        /// Caller-thread resolution that may perform process start-time/path
        /// probes and captures a bounded signal tied to that exact process.
        /// The returned target must be disposed by the dispatch owner.
        /// </summary>
        bool TryResolveForDispatch(
            string sessionId,
            string targetId,
            out NativeInputTargetSnapshot target,
            out string reasonCode);

        /// <summary>
        /// Hook-safe validation. Implementations may consume only bounded
        /// identity signals, HWND ownership, and in-memory generations.
        /// </summary>
        bool TryValidateDispatchIdentity(
            NativeInputTargetSnapshot target,
            out string reasonCode);

        /// <summary>
        /// Revalidates the exact registered target HWND or a real child whose
        /// GA_ROOT is that exact registered HWND. Owned/sibling windows are
        /// not registration authority.
        /// </summary>
        bool IsRegisteredInputWindow(
            NativeInputTargetSnapshot target,
            IntPtr candidateHwnd);
    }

    public interface INativeInputPreemptionSink
    {
        void RevokeLeaseAndCancelQueuedActions(
            string sessionId,
            string leaseId,
            string reasonCode);
    }

    public sealed class NativeInputDispatchRequest
    {
        public string LeaseId { get; init; }
        public InputEpochSnapshot ExpectedEpochs { get; init; }
        public long ExpectedInputEpoch { get; init; }
        public bool RequireTargetFocus { get; init; }
        public IReadOnlyList<NativeInputPacket> Packets { get; init; } =
            Array.Empty<NativeInputPacket>();
        public IReadOnlyList<NativeScreenPoint> PointerHitTestPoints { get; init; } =
            Array.Empty<NativeScreenPoint>();
    }

    public sealed class NativeInputDispatchResult
    {
        private NativeInputDispatchResult(
            ActionOutcome outcome,
            EvidenceKind evidenceKind,
            string reasonCode,
            ReconcileKind reconcileKind,
            int requestedInputCount,
            int insertedInputCount,
            bool focusVerified)
        {
            Outcome = outcome;
            EvidenceKind = evidenceKind;
            ReasonCode = reasonCode;
            ReconcileKind = reconcileKind;
            RequestedInputCount = requestedInputCount;
            InsertedInputCount = insertedInputCount;
            FocusVerified = focusVerified;
        }

        public ActionOutcome Outcome { get; }
        public EvidenceKind EvidenceKind { get; }
        public string ReasonCode { get; }
        public ReconcileKind ReconcileKind { get; }
        public int RequestedInputCount { get; }
        public int InsertedInputCount { get; }
        public bool FocusVerified { get; }

        public static NativeInputDispatchResult Rejected(
            string reasonCode,
            int requestedInputCount,
            bool focusVerified = false)
        {
            return new NativeInputDispatchResult(
                ActionOutcome.Rejected,
                EvidenceKind.None,
                reasonCode,
                ReconcileKind.None,
                requestedInputCount,
                0,
                focusVerified);
        }

        public static NativeInputDispatchResult Dispatched(
            int inputCount)
        {
            return new NativeInputDispatchResult(
                ActionOutcome.InputDispatched,
                EvidenceKind.BrokerDispatch,
                "none",
                ReconcileKind.None,
                inputCount,
                inputCount,
                true);
        }

        public static NativeInputDispatchResult InsertionUnknown(
            int requestedInputCount,
            int insertedInputCount,
            bool focusVerified)
        {
            return new NativeInputDispatchResult(
                ActionOutcome.Unknown,
                EvidenceKind.ReconciliationRequired,
                "input_not_inserted",
                ReconcileKind.VisualAmbiguous,
                requestedInputCount,
                Math.Max(0, insertedInputCount),
                focusVerified);
        }
    }

    internal static class NativeInputEpochComparer
    {
        public static bool ExactEquals(
            InputEpochSnapshot left,
            InputEpochSnapshot right)
        {
            return left != null
                && right != null
                && string.Equals(
                    left.SessionId,
                    right.SessionId,
                    StringComparison.Ordinal)
                && left.LifecycleGeneration
                    == right.LifecycleGeneration
                && string.Equals(
                    left.AttemptId,
                    right.AttemptId,
                    StringComparison.Ordinal)
                && left.AttemptGeneration
                    == right.AttemptGeneration
                && string.Equals(
                    left.TargetId,
                    right.TargetId,
                    StringComparison.Ordinal)
                && left.SurfaceEpoch == right.SurfaceEpoch
                && left.CoordinateSpaceVersion
                    == right.CoordinateSpaceVersion
                && string.Equals(
                    left.PanelInstanceId,
                    right.PanelInstanceId,
                    StringComparison.Ordinal)
                && left.DocumentGeneration
                    == right.DocumentGeneration
                && left.FocusEpoch == right.FocusEpoch
                && left.ModalEpoch == right.ModalEpoch;
        }
    }
}
