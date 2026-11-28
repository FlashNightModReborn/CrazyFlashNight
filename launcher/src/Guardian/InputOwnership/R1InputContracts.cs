using System;
using System.Drawing;

namespace CF7Launcher.Guardian.InputOwnership
{
    internal readonly record struct TextInputLease(
        string EndpointId,
        long InstanceGeneration,
        ulong LeaseId);

    internal readonly record struct TextFocusObservation(
        string SessionId,
        IntPtr RootHwnd,
        IntPtr EditorHwnd,
        long FocusSerial,
        bool LocalFocusConfirmed,
        bool ImeComposing = false);

    internal readonly record struct TextExitObservation(
        string SessionId,
        long FocusSerial,
        string Reason,
        bool EditorFocusCleared,
        int TriggerVk = 0);

    internal enum TextExitStatus
    {
        Released = 0,
        Stale = 1
    }

    internal readonly record struct TextExitReceipt(
        TextExitStatus Status,
        string SessionId,
        TextInputLease Lease,
        long KeyboardEpoch,
        long RequestSerial);

    internal readonly record struct PointerGestureTicket(
        string EndpointId,
        long InstanceGeneration,
        long GeometryVersion,
        long PointerEpoch,
        long GestureId,
        int Button);

    internal interface ITextInputAuthority
    {
        string CurrentSessionId { get; }
        long CurrentKeyboardEpoch { get; }
        TextInputLease? CurrentTextLease { get; }
        bool IsGameKeyboardAdmitted { get; }

        long NextInstanceGeneration(string endpointId);

        TextInputLease? AcquireText(
            string endpointId,
            long instanceGeneration,
            in TextFocusObservation observedFocus);

        TextExitReceipt ReleaseText(
            in TextInputLease exactLease,
            in TextExitObservation observedExit);

        bool RequestGameKeyboard(in TextExitReceipt exactRelease);
    }

    internal interface IUiPointerAuthority
    {
        long CurrentPointerEpoch { get; }
        long CurrentGeometryVersion { get; }

        bool TryBeginPointer(
            string endpointId,
            long instanceGeneration,
            int button,
            Point screenPoint,
            string localTargetId,
            out PointerGestureTicket ticket);

        bool ValidatePointerCommit(
            in PointerGestureTicket exactTicket,
            string localTargetId);

        void EndPointer(in PointerGestureTicket exactTicket, bool committed);
        void CancelPointer(in PointerGestureTicket exactTicket, string reason);
    }
}
