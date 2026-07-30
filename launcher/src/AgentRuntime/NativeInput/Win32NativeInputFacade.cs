using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace CF7Launcher.AgentRuntime.NativeInput
{
    /// <summary>
    /// Windows-only production facade. Every probe returns false/zero on an
    /// indeterminate native result; no caller is permitted to interpret a
    /// failed probe as authorization.
    /// </summary>
    public sealed class Win32NativeInputFacade :
        INativeInputWin32Facade
    {
        private const uint InputMouse = 0;
        private const uint InputKeyboard = 1;
        private const uint ProcessQueryLimitedInformation = 0x1000;
        private const uint TokenQuery = 0x0008;
        private const int TokenIntegrityLevel = 25;
        private const uint DesktopReadObjects = 0x0001;
        private const uint DesktopSwitchDesktop = 0x0100;
        private const int UoiName = 2;
        private const uint GaRootOwner = 3;
        private const uint GwOwner = 4;

        public int CurrentProcessId => Environment.ProcessId;
        public long MonotonicMilliseconds =>
            Environment.TickCount64;

        public INativeLowLevelHookSession InstallLowLevelHooks(
            ulong runtimeInjectionTag,
            Func<NativeLowLevelHookEvent, bool> callback)
        {
            if (runtimeInjectionTag == 0)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(runtimeInjectionTag));
            }
            return new DedicatedLowLevelHookSession(
                runtimeInjectionTag,
                callback
                    ?? throw new ArgumentNullException(
                        nameof(callback)));
        }

        public bool IsInteractiveDesktopAvailable()
        {
            IntPtr desktop = OpenInputDesktop(
                0,
                false,
                DesktopReadObjects | DesktopSwitchDesktop);
            if (desktop == IntPtr.Zero)
            {
                return false;
            }
            try
            {
                var name = new StringBuilder(256);
                if (!GetUserObjectInformation(
                        desktop,
                        UoiName,
                        name,
                        name.Capacity * sizeof(char),
                        out _))
                {
                    return false;
                }
                return string.Equals(
                        name.ToString(),
                        "Default",
                        StringComparison.OrdinalIgnoreCase)
                    && NativeGetForegroundWindow()
                        != IntPtr.Zero;
            }
            finally
            {
                CloseDesktop(desktop);
            }
        }

        public IntPtr GetForegroundWindow()
        {
            return NativeGetForegroundWindow();
        }

        public bool TryGetFocusedWindow(
            IntPtr foregroundTopLevelHwnd,
            out IntPtr focusedHwnd)
        {
            focusedHwnd = IntPtr.Zero;
            if (foregroundTopLevelHwnd == IntPtr.Zero)
                return false;
            uint threadId = GetWindowThreadProcessId(
                foregroundTopLevelHwnd,
                out _);
            if (threadId == 0)
                return false;
            var info = new GuiThreadInfo
            {
                Size = checked(
                    (uint)Marshal.SizeOf<GuiThreadInfo>())
            };
            if (!GetGUIThreadInfo(threadId, ref info)
                || info.FocusWindow == IntPtr.Zero)
            {
                return false;
            }
            focusedHwnd = info.FocusWindow;
            return true;
        }

        public IntPtr WindowFromPoint(NativeScreenPoint point)
        {
            return NativeWindowFromPoint(
                new Point
                {
                    X = point.X,
                    Y = point.Y
                });
        }

        public bool IsSameChildOrOwnedWindow(
            IntPtr targetTopLevelHwnd,
            IntPtr candidateHwnd)
        {
            if (targetTopLevelHwnd == IntPtr.Zero
                || candidateHwnd == IntPtr.Zero)
            {
                return false;
            }
            if (targetTopLevelHwnd == candidateHwnd
                || IsChild(
                    targetTopLevelHwnd,
                    candidateHwnd))
            {
                return true;
            }
            if (GetAncestor(candidateHwnd, GaRootOwner)
                == targetTopLevelHwnd)
            {
                return true;
            }

            IntPtr current = candidateHwnd;
            for (int i = 0; i < 32; i++)
            {
                current = GetWindow(current, GwOwner);
                if (current == IntPtr.Zero)
                {
                    return false;
                }
                if (current == targetTopLevelHwnd)
                {
                    return true;
                }
            }
            return false;
        }

        public IReadOnlyCollection<string>
            GetAsyncHeldModifiersAndButtons()
        {
            var held = new List<string>();
            bool leftShift =
                AddIfDown(held, 0xA0, "Key:160");
            bool rightShift =
                AddIfDown(held, 0xA1, "Key:161");
            if (!leftShift && !rightShift)
            {
                AddIfDown(held, 0x10, "Key:16");
            }
            bool leftControl =
                AddIfDown(held, 0xA2, "Key:162");
            bool rightControl =
                AddIfDown(held, 0xA3, "Key:163");
            if (!leftControl && !rightControl)
            {
                AddIfDown(held, 0x11, "Key:17");
            }
            bool leftAlt =
                AddIfDown(held, 0xA4, "Key:164");
            bool rightAlt =
                AddIfDown(held, 0xA5, "Key:165");
            if (!leftAlt && !rightAlt)
            {
                AddIfDown(held, 0x12, "Key:18");
            }
            AddIfDown(held, 0x5B, "Key:91"); // Left Windows
            AddIfDown(held, 0x5C, "Key:92"); // Right Windows
            AddIfDown(held, 0x01, "MouseLeft");
            AddIfDown(held, 0x02, "MouseRight");
            AddIfDown(held, 0x04, "MouseMiddle");
            AddIfDown(held, 0x05, "MouseX1");
            AddIfDown(held, 0x06, "MouseX2");
            return held;
        }

        public bool TryGetProcessIntegrityLevel(
            int processId,
            out int integrityRid)
        {
            integrityRid = 0;
            if (processId <= 0)
            {
                return false;
            }

            IntPtr process = OpenProcess(
                ProcessQueryLimitedInformation,
                false,
                processId);
            if (process == IntPtr.Zero)
            {
                return false;
            }
            IntPtr token = IntPtr.Zero;
            IntPtr buffer = IntPtr.Zero;
            try
            {
                if (!OpenProcessToken(
                        process,
                        TokenQuery,
                        out token))
                {
                    return false;
                }
                GetTokenInformation(
                    token,
                    TokenIntegrityLevel,
                    IntPtr.Zero,
                    0,
                    out int required);
                if (required <= 0)
                {
                    return false;
                }

                buffer = Marshal.AllocHGlobal(required);
                if (!GetTokenInformation(
                        token,
                        TokenIntegrityLevel,
                        buffer,
                        required,
                        out _))
                {
                    return false;
                }

                TokenMandatoryLabel label =
                    Marshal.PtrToStructure<TokenMandatoryLabel>(
                        buffer);
                if (label.Label.Sid == IntPtr.Zero)
                {
                    return false;
                }
                IntPtr countPointer =
                    GetSidSubAuthorityCount(label.Label.Sid);
                if (countPointer == IntPtr.Zero)
                {
                    return false;
                }
                byte count = Marshal.ReadByte(countPointer);
                if (count == 0)
                {
                    return false;
                }
                IntPtr ridPointer = GetSidSubAuthority(
                    label.Label.Sid,
                    (uint)(count - 1));
                if (ridPointer == IntPtr.Zero)
                {
                    return false;
                }
                integrityRid = Marshal.ReadInt32(ridPointer);
                return integrityRid > 0;
            }
            catch
            {
                integrityRid = 0;
                return false;
            }
            finally
            {
                if (buffer != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(buffer);
                }
                if (token != IntPtr.Zero)
                {
                    CloseHandle(token);
                }
                CloseHandle(process);
            }
        }

        public int SendInput(
            IReadOnlyList<NativeInputPacket> packets,
            ulong runtimeInjectionTag)
        {
            if (packets == null || packets.Count == 0)
            {
                throw new ArgumentException(
                    "A non-empty input batch is required.",
                    nameof(packets));
            }
            if (runtimeInjectionTag == 0)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(runtimeInjectionTag));
            }

            var native = new Input[packets.Count];
            UIntPtr extraInfo = new UIntPtr(
                runtimeInjectionTag);
            for (int i = 0; i < packets.Count; i++)
            {
                NativeInputPacket packet = packets[i]
                    ?? throw new ArgumentException(
                        "Input packets cannot contain null.",
                        nameof(packets));
                if (packet.Kind
                    == NativeInputPacketKind.Keyboard)
                {
                    native[i] = new Input
                    {
                        Type = InputKeyboard,
                        Union = new InputUnion
                        {
                            Keyboard = new KeyboardInput
                            {
                                VirtualKey =
                                    packet.VirtualKey,
                                ScanCode =
                                    packet.ScanCode,
                                Flags =
                                    packet.KeyboardFlags,
                                Time = 0,
                                ExtraInfo = extraInfo
                            }
                        }
                    };
                }
                else
                {
                    native[i] = new Input
                    {
                        Type = InputMouse,
                        Union = new InputUnion
                        {
                            Mouse = new MouseInput
                            {
                                Dx = packet.MouseDx,
                                Dy = packet.MouseDy,
                                MouseData =
                                    packet.MouseData,
                                Flags =
                                    packet.MouseFlags,
                                Time = 0,
                                ExtraInfo = extraInfo
                            }
                        }
                    };
                }
            }

            return checked((int)NativeSendInput(
                (uint)native.Length,
                native,
                Marshal.SizeOf<Input>()));
        }

        private static bool AddIfDown(
            ICollection<string> held,
            int virtualKey,
            string controlId)
        {
            if ((GetAsyncKeyState(virtualKey) & 0x8000) != 0)
            {
                held.Add(controlId);
                return true;
            }
            return false;
        }

        private sealed class DedicatedLowLevelHookSession :
            INativeLowLevelHookSession
        {
            private const int WhKeyboardLl = 13;
            private const int WhMouseLl = 14;
            private const uint WmQuit = 0x0012;
            private const uint WmTimer = 0x0113;
            private const uint WmAppRefresh = 0x8001;
            private const uint WmKeyDown = 0x0100;
            private const uint WmKeyUp = 0x0101;
            private const uint WmSysKeyDown = 0x0104;
            private const uint WmSysKeyUp = 0x0105;
            private const uint WmMouseMove = 0x0200;
            private const uint WmLeftButtonDown = 0x0201;
            private const uint WmLeftButtonUp = 0x0202;
            private const uint WmRightButtonDown = 0x0204;
            private const uint WmRightButtonUp = 0x0205;
            private const uint WmMiddleButtonDown = 0x0207;
            private const uint WmMiddleButtonUp = 0x0208;
            private const uint WmMouseWheel = 0x020A;
            private const uint WmXButtonDown = 0x020B;
            private const uint WmXButtonUp = 0x020C;
            private const uint WmMouseHWheel = 0x020E;
            private const uint LlkHfInjected = 0x10;
            private const uint LlmHfInjected = 0x01;
            private const uint HookTimerId = 1;

            private readonly ulong _runtimeInjectionTag;
            private readonly Func<NativeLowLevelHookEvent, bool>
                _callback;
            private readonly LowLevelKeyboardProc _keyboardProc;
            private readonly LowLevelMouseProc _mouseProc;
            private readonly Thread _thread;
            private readonly ManualResetEventSlim _ready =
                new ManualResetEventSlim(false);
            private readonly ManualResetEventSlim _refreshComplete =
                new ManualResetEventSlim(false);
            private readonly object _refreshSync = new object();
            private IntPtr _keyboardHook;
            private IntPtr _mouseHook;
            private uint _threadId;
            private long _lastHeartbeatTick;
            private bool _lastRefreshResult;
            private volatile bool _installed;
            private bool _disposed;

            internal DedicatedLowLevelHookSession(
                ulong runtimeInjectionTag,
                Func<NativeLowLevelHookEvent, bool> callback)
            {
                _runtimeInjectionTag =
                    runtimeInjectionTag;
                _callback = callback;
                _keyboardProc = KeyboardHookCallback;
                _mouseProc = MouseHookCallback;
                _thread = new Thread(HookThread)
                {
                    IsBackground = true,
                    Name = "CF7 Agent low-level input guard"
                };
                _thread.Start();
                _ready.Wait(TimeSpan.FromSeconds(2));
            }

            public bool IsHealthy(
                TimeSpan maximumHeartbeatAge)
            {
                if (_disposed
                    || !_installed
                    || !_thread.IsAlive)
                {
                    return false;
                }
                long heartbeat = Interlocked.Read(
                    ref _lastHeartbeatTick);
                if (heartbeat == 0)
                {
                    return false;
                }
                long maximumAge = Math.Max(
                    0,
                    (long)Math.Ceiling(
                        maximumHeartbeatAge
                            .TotalMilliseconds));
                return Environment.TickCount64
                    - heartbeat <= maximumAge;
            }

            public bool TryRefresh(TimeSpan timeout)
            {
                if (_disposed
                    || !_thread.IsAlive
                    || _threadId == 0)
                {
                    return false;
                }
                lock (_refreshSync)
                {
                    _refreshComplete.Reset();
                    _lastRefreshResult = false;
                    if (!PostThreadMessage(
                            _threadId,
                            WmAppRefresh,
                            UIntPtr.Zero,
                            IntPtr.Zero))
                    {
                        return false;
                    }
                    return _refreshComplete.Wait(timeout)
                        && _lastRefreshResult;
                }
            }

            private void HookThread()
            {
                _threadId = GetCurrentThreadId();
                PeekMessage(
                    out _,
                    IntPtr.Zero,
                    0,
                    0,
                    0);
                _installed = InstallHooks();
                Interlocked.Exchange(
                    ref _lastHeartbeatTick,
                    Environment.TickCount64);
                SetTimer(
                    IntPtr.Zero,
                    HookTimerId,
                    100,
                    IntPtr.Zero);
                _ready.Set();

                while (GetMessage(
                    out Message message,
                    IntPtr.Zero,
                    0,
                    0) > 0)
                {
                    if (message.MessageId == WmAppRefresh)
                    {
                        _installed = ReinstallHooks();
                        _lastRefreshResult =
                            _installed;
                        Interlocked.Exchange(
                            ref _lastHeartbeatTick,
                            Environment.TickCount64);
                        _refreshComplete.Set();
                        continue;
                    }
                    if (message.MessageId == WmTimer)
                    {
                        Interlocked.Exchange(
                            ref _lastHeartbeatTick,
                            Environment.TickCount64);
                        continue;
                    }
                    TranslateMessage(ref message);
                    DispatchMessage(ref message);
                }

                KillTimer(IntPtr.Zero, HookTimerId);
                RemoveHooks();
                _installed = false;
                _refreshComplete.Set();
            }

            private bool ReinstallHooks()
            {
                RemoveHooks();
                return InstallHooks();
            }

            private bool InstallHooks()
            {
                IntPtr module = GetModuleHandle(null);
                _keyboardHook = SetWindowsHookEx(
                    WhKeyboardLl,
                    _keyboardProc,
                    module,
                    0);
                if (_keyboardHook == IntPtr.Zero)
                {
                    return false;
                }
                _mouseHook = SetWindowsHookEx(
                    WhMouseLl,
                    _mouseProc,
                    module,
                    0);
                if (_mouseHook == IntPtr.Zero)
                {
                    UnhookWindowsHookEx(_keyboardHook);
                    _keyboardHook = IntPtr.Zero;
                    return false;
                }
                return true;
            }

            private void RemoveHooks()
            {
                if (_keyboardHook != IntPtr.Zero)
                {
                    UnhookWindowsHookEx(_keyboardHook);
                    _keyboardHook = IntPtr.Zero;
                }
                if (_mouseHook != IntPtr.Zero)
                {
                    UnhookWindowsHookEx(_mouseHook);
                    _mouseHook = IntPtr.Zero;
                }
            }

            private IntPtr KeyboardHookCallback(
                int code,
                IntPtr wParam,
                IntPtr lParam)
            {
                if (code < 0)
                {
                    return CallNextHookEx(
                        _keyboardHook,
                        code,
                        wParam,
                        lParam);
                }

                KeyboardLowLevelHook data =
                    Marshal.PtrToStructure<
                        KeyboardLowLevelHook>(lParam);
                uint message = unchecked(
                    (uint)wParam.ToInt64());
                NativeControlTransition transition =
                    message == WmKeyDown
                        || message == WmSysKeyDown
                            ? NativeControlTransition.Down
                            : message == WmKeyUp
                                || message == WmSysKeyUp
                                    ? NativeControlTransition.Up
                                    : NativeControlTransition.None;
                var hookEvent = new NativeLowLevelHookEvent(
                    NativeHookDevice.Keyboard,
                    data.VirtualKey == 0xE7
                        ? "Unicode:"
                            + data.ScanCode.ToString("X4")
                        : "Key:" + data.VirtualKey,
                    transition,
                    (data.Flags & LlkHfInjected) != 0,
                    data.ExtraInfo.ToUInt64(),
                    null,
                    message);
                return DispatchBounded(
                    hookEvent,
                    _keyboardHook,
                    code,
                    wParam,
                    lParam);
            }

            private IntPtr MouseHookCallback(
                int code,
                IntPtr wParam,
                IntPtr lParam)
            {
                if (code < 0)
                {
                    return CallNextHookEx(
                        _mouseHook,
                        code,
                        wParam,
                        lParam);
                }

                MouseLowLevelHook data =
                    Marshal.PtrToStructure<
                        MouseLowLevelHook>(lParam);
                uint message = unchecked(
                    (uint)wParam.ToInt64());
                string control = null;
                NativeControlTransition transition =
                    NativeControlTransition.None;
                switch (message)
                {
                    case WmLeftButtonDown:
                        control = "MouseLeft";
                        transition =
                            NativeControlTransition.Down;
                        break;
                    case WmLeftButtonUp:
                        control = "MouseLeft";
                        transition =
                            NativeControlTransition.Up;
                        break;
                    case WmRightButtonDown:
                        control = "MouseRight";
                        transition =
                            NativeControlTransition.Down;
                        break;
                    case WmRightButtonUp:
                        control = "MouseRight";
                        transition =
                            NativeControlTransition.Up;
                        break;
                    case WmMiddleButtonDown:
                        control = "MouseMiddle";
                        transition =
                            NativeControlTransition.Down;
                        break;
                    case WmMiddleButtonUp:
                        control = "MouseMiddle";
                        transition =
                            NativeControlTransition.Up;
                        break;
                    case WmXButtonDown:
                    case WmXButtonUp:
                        control =
                            ((data.MouseData >> 16) & 0xFFFF)
                                == 1
                                ? "MouseX1"
                                : "MouseX2";
                        transition = message
                            == WmXButtonDown
                                ? NativeControlTransition.Down
                                : NativeControlTransition.Up;
                        break;
                    case WmMouseMove:
                    case WmMouseWheel:
                    case WmMouseHWheel:
                        break;
                }

                var hookEvent = new NativeLowLevelHookEvent(
                    NativeHookDevice.Mouse,
                    control,
                    transition,
                    (data.Flags & LlmHfInjected) != 0,
                    data.ExtraInfo.ToUInt64(),
                    new NativeScreenPoint(
                        data.Point.X,
                        data.Point.Y),
                    message);
                return DispatchBounded(
                    hookEvent,
                    _mouseHook,
                    code,
                    wParam,
                    lParam);
            }

            private IntPtr DispatchBounded(
                NativeLowLevelHookEvent hookEvent,
                IntPtr hook,
                int code,
                IntPtr wParam,
                IntPtr lParam)
            {
                Interlocked.Exchange(
                    ref _lastHeartbeatTick,
                    Environment.TickCount64);
                try
                {
                    if (_callback(hookEvent))
                    {
                        return new IntPtr(1);
                    }
                }
                catch
                {
                    _installed = false;
                    if (hookEvent.IsInjected
                        && hookEvent.ExtraInfo
                            == _runtimeInjectionTag)
                    {
                        return new IntPtr(1);
                    }
                }
                return CallNextHookEx(
                    hook,
                    code,
                    wParam,
                    lParam);
            }

            public void Dispose()
            {
                if (_disposed)
                {
                    return;
                }
                _disposed = true;
                if (_threadId != 0)
                {
                    PostThreadMessage(
                        _threadId,
                        WmQuit,
                        UIntPtr.Zero,
                        IntPtr.Zero);
                }
                if (Thread.CurrentThread != _thread)
                {
                    _thread.Join(
                        TimeSpan.FromSeconds(2));
                }
                _ready.Dispose();
                _refreshComplete.Dispose();
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Point
        {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Message
        {
            public IntPtr Hwnd;
            public uint MessageId;
            public UIntPtr WParam;
            public IntPtr LParam;
            public uint Time;
            public Point Point;
            public uint Private;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KeyboardLowLevelHook
        {
            public uint VirtualKey;
            public uint ScanCode;
            public uint Flags;
            public uint Time;
            public UIntPtr ExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MouseLowLevelHook
        {
            public Point Point;
            public uint MouseData;
            public uint Flags;
            public uint Time;
            public UIntPtr ExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Input
        {
            public uint Type;
            public InputUnion Union;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct InputUnion
        {
            [FieldOffset(0)]
            public MouseInput Mouse;

            [FieldOffset(0)]
            public KeyboardInput Keyboard;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MouseInput
        {
            public int Dx;
            public int Dy;
            public uint MouseData;
            public uint Flags;
            public uint Time;
            public UIntPtr ExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KeyboardInput
        {
            public ushort VirtualKey;
            public ushort ScanCode;
            public uint Flags;
            public uint Time;
            public UIntPtr ExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SidAndAttributes
        {
            public IntPtr Sid;
            public uint Attributes;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TokenMandatoryLabel
        {
            public SidAndAttributes Label;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct GuiThreadInfo
        {
            public uint Size;
            public uint Flags;
            public IntPtr ActiveWindow;
            public IntPtr FocusWindow;
            public IntPtr CaptureWindow;
            public IntPtr MenuOwnerWindow;
            public IntPtr MoveSizeWindow;
            public IntPtr CaretWindow;
            public Rect CaretRect;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        private delegate IntPtr LowLevelKeyboardProc(
            int code,
            IntPtr wParam,
            IntPtr lParam);

        private delegate IntPtr LowLevelMouseProc(
            int code,
            IntPtr wParam,
            IntPtr lParam);

        [DllImport(
            "user32.dll",
            SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(
            int hookId,
            LowLevelKeyboardProc callback,
            IntPtr module,
            uint threadId);

        [DllImport(
            "user32.dll",
            SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(
            int hookId,
            LowLevelMouseProc callback,
            IntPtr module,
            uint threadId);

        [DllImport(
            "user32.dll",
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(
            IntPtr hook);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(
            IntPtr hook,
            int code,
            IntPtr wParam,
            IntPtr lParam);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetModuleHandle(
            string moduleName);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [DllImport(
            "user32.dll",
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PostThreadMessage(
            uint threadId,
            uint message,
            UIntPtr wParam,
            IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern int GetMessage(
            out Message message,
            IntPtr hwnd,
            uint minimum,
            uint maximum);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PeekMessage(
            out Message message,
            IntPtr hwnd,
            uint minimum,
            uint maximum,
            uint removeMessage);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TranslateMessage(
            ref Message message);

        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage(
            ref Message message);

        [DllImport("user32.dll")]
        private static extern UIntPtr SetTimer(
            IntPtr hwnd,
            UIntPtr timerId,
            uint intervalMilliseconds,
            IntPtr callback);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool KillTimer(
            IntPtr hwnd,
            UIntPtr timerId);

        [DllImport(
            "user32.dll",
            SetLastError = true)]
        private static extern IntPtr OpenInputDesktop(
            uint flags,
            [MarshalAs(UnmanagedType.Bool)] bool inherit,
            uint desiredAccess);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseDesktop(
            IntPtr desktop);

        [DllImport(
            "user32.dll",
            CharSet = CharSet.Unicode,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetUserObjectInformation(
            IntPtr handle,
            int index,
            StringBuilder information,
            int length,
            out int needed);

        [DllImport(
            "user32.dll",
            EntryPoint = "GetForegroundWindow")]
        private static extern IntPtr
            NativeGetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(
            IntPtr hwnd,
            out uint processId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetGUIThreadInfo(
            uint threadId,
            ref GuiThreadInfo info);

        [DllImport(
            "user32.dll",
            EntryPoint = "WindowFromPoint")]
        private static extern IntPtr
            NativeWindowFromPoint(Point point);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsChild(
            IntPtr parent,
            IntPtr child);

        [DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(
            IntPtr hwnd,
            uint flags);

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindow(
            IntPtr hwnd,
            uint command);

        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(
            int virtualKey);

        [DllImport(
            "user32.dll",
            SetLastError = true,
            EntryPoint = "SendInput")]
        private static extern uint NativeSendInput(
            uint inputCount,
            [In] Input[] inputs,
            int inputSize);

        [DllImport(
            "kernel32.dll",
            SetLastError = true)]
        private static extern IntPtr OpenProcess(
            uint desiredAccess,
            [MarshalAs(UnmanagedType.Bool)] bool inherit,
            int processId);

        [DllImport(
            "advapi32.dll",
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(
            IntPtr process,
            uint desiredAccess,
            out IntPtr token);

        [DllImport(
            "advapi32.dll",
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetTokenInformation(
            IntPtr token,
            int informationClass,
            IntPtr information,
            int informationLength,
            out int returnLength);

        [DllImport("advapi32.dll")]
        private static extern IntPtr GetSidSubAuthorityCount(
            IntPtr sid);

        [DllImport("advapi32.dll")]
        private static extern IntPtr GetSidSubAuthority(
            IntPtr sid,
            uint subAuthority);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(
            IntPtr handle);
    }
}
