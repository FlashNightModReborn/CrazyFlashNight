using System;
using System.Collections.Generic;

namespace CF7Launcher.AgentRuntime.NativeInput
{
    public enum NativeHookDevice
    {
        Keyboard,
        Mouse
    }

    public sealed class NativeLowLevelHookEvent
    {
        public NativeLowLevelHookEvent(
            NativeHookDevice device,
            string controlId,
            NativeControlTransition transition,
            bool isInjected,
            ulong extraInfo,
            NativeScreenPoint? screenPoint,
            uint nativeMessage)
        {
            Device = device;
            ControlId = controlId;
            Transition = transition;
            IsInjected = isInjected;
            ExtraInfo = extraInfo;
            ScreenPoint = screenPoint;
            NativeMessage = nativeMessage;
        }

        public NativeHookDevice Device { get; }
        public string ControlId { get; }
        public NativeControlTransition Transition { get; }
        public bool IsInjected { get; }
        public ulong ExtraInfo { get; }
        public NativeScreenPoint? ScreenPoint { get; }
        public uint NativeMessage { get; }
    }

    public interface INativeLowLevelHookSession : IDisposable
    {
        bool IsHealthy(TimeSpan maximumHeartbeatAge);
        bool TryRefresh(TimeSpan timeout);
    }

    public interface INativeInputWin32Facade
    {
        int CurrentProcessId { get; }
        long MonotonicMilliseconds { get; }

        INativeLowLevelHookSession InstallLowLevelHooks(
            ulong runtimeInjectionTag,
            Func<NativeLowLevelHookEvent, bool> callback);

        bool IsInteractiveDesktopAvailable();
        IntPtr GetForegroundWindow();
        bool TryGetFocusedWindow(
            IntPtr foregroundTopLevelHwnd,
            out IntPtr focusedHwnd);
        IntPtr WindowFromPoint(NativeScreenPoint point);
        bool IsSameChildOrOwnedWindow(
            IntPtr targetTopLevelHwnd,
            IntPtr candidateHwnd);
        IReadOnlyCollection<string> GetAsyncHeldModifiersAndButtons();
        bool TryGetProcessIntegrityLevel(
            int processId,
            out int integrityRid);

        int SendInput(
            IReadOnlyList<NativeInputPacket> packets,
            ulong runtimeInjectionTag);
    }
}
