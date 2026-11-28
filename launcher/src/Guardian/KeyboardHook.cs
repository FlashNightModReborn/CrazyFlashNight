using System;
using CF7Launcher.Guardian.InputOwnership;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 低级键盘钩子——运行在专用线程上，永不超时。
    /// 拦截 Ctrl+W/R/P/O（Flash SA 原生快捷键）和 Ctrl+F/Q（Guardian 动作键）。
    /// 按会话的实时前台和当前文本租约决定是否派发快捷键。
    /// </summary>
    public class KeyboardHook : IDisposable, IPanelEscapeSource
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

        [DllImport("user32.dll")]
        private static extern bool TranslateMessage(ref MSG lpMsg);

        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage(ref MSG lpMsg);

        [DllImport("user32.dll")]
        private static extern bool PostThreadMessage(uint idThread, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [StructLayout(LayoutKind.Sequential)]
        private struct MSG
        {
            public IntPtr hwnd;
            public uint message;
            public IntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public int pt_x;
            public int pt_y;
        }

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;
        private const int WM_QUIT = 0x0012;

        private const uint VK_CONTROL = 0x11;
        private const uint VK_LCONTROL = 0xA2;
        private const uint VK_RCONTROL = 0xA3;
        private const uint VK_ESCAPE = 0x1B;

        private IntPtr _hookId = IntPtr.Zero;
        private LowLevelKeyboardProc _proc;
        private Thread _thread;
        private uint _threadId;
        private volatile bool _running;

        // 仅拦截的键（Ctrl+ 组合）
        private readonly HashSet<uint> _blockedVks;
        // 拦截后需要触发动作的键 → action 回调
        private readonly Dictionary<uint, Action> _actionVks;
        private readonly uint _myPid;
        private bool _leftCtrlHeld, _rightCtrlHeld;
        private bool _ctrlHeld { get { return _leftCtrlHeld || _rightCtrlHeld; } }
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int vk);

        internal static bool ControlSideAfterEvent(uint side, uint vk, bool down, bool asyncHeld)
        {
            // LL 回调内当前键的异步状态仍是上一边沿，当前键只服从事件。
            return vk == side ? down : asyncHeld;
        }

        private volatile SessionInputAuthority _r1;
        private Func<bool> _r1Foreground;
        private Func<bool> _shortcutForeground;
        private Action<Action> _postShortcut;
        private long _lastObservationGeneration;
        private (long Generation, ulong Lease, int GameEpoch)? _leftCtrlStamp, _rightCtrlStamp;
        internal void BindPassiveInput(SessionInputAuthority authority, Func<bool> exactForeground,
            Action<Action> postShortcut = null, Func<bool> shortcutForeground = null)
        {
            _r1Foreground = exactForeground;
            _shortcutForeground = shortcutForeground ?? exactForeground;
            _postShortcut = postShortcut;
            _r1 = authority;
        }
        internal Func<int, short> ReadAsyncKeyState = GetAsyncKeyState;
        internal Func<bool> LiveForegroundProbeForTests;

        private void ReconcileKeyState(uint vk, bool down)
        {
            _leftCtrlHeld = ControlSideAfterEvent(VK_LCONTROL, vk, down, (ReadAsyncKeyState((int)VK_LCONTROL) & 0x8000) != 0);
            _rightCtrlHeld = ControlSideAfterEvent(VK_RCONTROL, vk, down, (ReadAsyncKeyState((int)VK_RCONTROL) & 0x8000) != 0);
            // 被本 hook 消费的 down 可能未更新 OS 异步键态，不能用 false 清其长按锁存。
            // 外部前台的事件不被我们消费，此时可清理外部释放遗留的锁存。
            bool external = _r1 == null && !IsLiveApplicationForeground();
            _physicalKeysDown.RemoveWhere(key => (key != vk || down)
                && (external || (!_dialogueConsumedKeys.Contains(key) && !_shortcutConsumedKeys.Contains(key)))
                && (ReadAsyncKeyState((int)key) & 0x8000) == 0);
            _dialogueConsumedKeys.RemoveWhere(key => (key != vk || down) && !_physicalKeysDown.Contains(key));
            _shortcutConsumedKeys.RemoveWhere(key => (key != vk || down) && !_physicalKeysDown.Contains(key));
        }
        // Escape 拦截（全屏时动态启用）
        private volatile bool _escEnabled;
        // 面板 ESC 拦截（与 _escEnabled 独立）
        private volatile bool _panelEscEnabled;
        public bool PanelEscEnabled { get { return _panelEscEnabled; } }
        public void SetPanelEscapeEnabled(bool enabled) { _panelEscEnabled = enabled; }
        internal Func<Action> CapturePanelEscapeAction;

        // native_interaction ESC（NPC 菜单 / pinned tooltip 存活时吞掉 ESC 转交宿主关闭）。
        // 探针由 GuardianForm.SetInteractionEscSurface 注入，在本钩子专用线程同步调用，
        // 必须 O(1) 返回；实现侧异常按 false 处理，绝不让宿主代码异常逃出钩子回调。
        private volatile Func<bool> _interactionEscProbe;
        private volatile Func<uint, Action> _dialogueKeyProbe;
        private readonly HashSet<uint> _physicalKeysDown = new HashSet<uint>();
        private readonly HashSet<uint> _shortcutConsumedKeys = new HashSet<uint>();
        private readonly HashSet<uint> _dialogueConsumedKeys = new HashSet<uint>();
        public void SetDialogueKeyProbe(Func<uint, Action> probe) { _dialogueKeyProbe = probe; }
        public void SetInteractionEscapeProbe(Func<bool> probe) { _interactionEscProbe = probe; }

        public bool TextInputActive => _r1?.CurrentTextLease.HasValue == true;
        public bool InteractionEscActive
        {
            get
            {
                Func<bool> p = _interactionEscProbe;
                if (p == null) return false;
                try { return p(); } catch { return false; }
            }
        }

        public KeyboardHook()
        {
            _myPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
            _proc = HookCallback;

            _blockedVks = new HashSet<uint>();
            _blockedVks.Add(0x57); // W
            _blockedVks.Add(0x52); // R
            _blockedVks.Add(0x50); // P
            _blockedVks.Add(0x4F); // O
            _blockedVks.Add(0x46); // F — 原 RegisterHotKey，现迁入此处
            _blockedVks.Add(0x51); // Q — 原 RegisterHotKey，现迁入此处
            // 0x47 (G) 由 GuardianForm 按 config.devGpuProbeHotkey 动态启用，玩家版不注入

            _actionVks = new Dictionary<uint, Action>();
        }

        /// <summary>
        /// 注册拦截后的动作回调（UI 线程安全：回调在专用线程触发，调用方需自行 BeginInvoke）
        /// </summary>
        public void RegisterAction(uint vk, Action callback)
        {
            _actionVks[vk] = callback;
        }

        /// <summary>
        /// 运行时把 vk 加入 Ctrl+&lt;vk&gt; 拦截列表。
        /// 用于按 config 决定是否启用某些开发用快捷键（如 Ctrl+G GPU probe）。
        /// </summary>
        public void EnableBlockedVk(uint vk)
        {
            _blockedVks.Add(vk);
        }

        /// <summary>
        /// 动态启用/禁用 Escape 键拦截（全屏时启用）
        /// </summary>
        public void SetEscapeEnabled(bool enabled)
        {
            _escEnabled = enabled;
        }

        public bool Install()
        {
            _physicalKeysDown.Clear();
            _dialogueConsumedKeys.Clear();
            _shortcutConsumedKeys.Clear();
            _leftCtrlHeld = _rightCtrlHeld = false;
            _running = true;
            ManualResetEvent ready = new ManualResetEvent(false);

            _thread = new Thread(delegate()
            {
                _threadId = GetCurrentThreadId();

                using (var proc = System.Diagnostics.Process.GetCurrentProcess())
                using (var mod = proc.MainModule)
                {
                    IntPtr hMod = GetModuleHandle(mod.ModuleName);
                    _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, hMod, 0);
                }

                ready.Set();

                if (_hookId == IntPtr.Zero)
                    return;

                // 专用消息泵——此线程永远不会忙，钩子永远不会超时
                MSG msg;
                while (_running && GetMessage(out msg, IntPtr.Zero, 0, 0))
                {
                    TranslateMessage(ref msg);
                    DispatchMessage(ref msg);
                }
            });
            _thread.IsBackground = true;
            _thread.Start();

            ready.WaitOne(2000);
            bool ok = _hookId != IntPtr.Zero;
            Guardian.LogManager.Log("[KeyboardHook] Install " + (ok ? "OK" : "FAILED")
                + " (dedicated thread, blocks: W/R/P/O/F/Q [+G if dev])");
            return ok;
        }

        /// <summary>
        /// 钩子回调——在专用线程上运行，极轻量。
        /// 拦截逻辑 + 动作触发分离：拦截在微秒级返回，动作通过 ThreadPool 异步执行。
        /// </summary>
        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0 && ProcessKeyEdge(wParam.ToInt32(), lParam) != IntPtr.Zero) return new IntPtr(1);
            return CallNextHookEx(_hookId, nCode, wParam, lParam);
        }

        internal IntPtr ProcessKeyEdge(int msg, IntPtr lParam)
        {
            {
                uint vk = (uint)Marshal.ReadInt32(lParam);
                if (vk == VK_CONTROL) vk = (Marshal.ReadInt32(lParam, 8) & 1) != 0 ? VK_RCONTROL : VK_LCONTROL;
                bool down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
                bool up = msg == WM_KEYUP || msg == WM_SYSKEYUP;
                if(_r1 is { } input && !CanObserveForeground(input)) {
                    if(up) {
                        _physicalKeysDown.Remove(vk);_dialogueConsumedKeys.Remove(vk);_shortcutConsumedKeys.Remove(vk);
                        input.ObserveSuppressedRelease((int)vk,(Marshal.ReadInt32(lParam,8)&0x10)!=0 ?
                            InputObservationSource.Injected : InputObservationSource.Unmarked);
                    }
                    return IntPtr.Zero;
                }
                if (_r1 is { } session && _lastObservationGeneration != session.ObservationGeneration) {
                    _physicalKeysDown.Clear();
                    _shortcutConsumedKeys.Clear();
                    _dialogueConsumedKeys.Clear();
                    _lastObservationGeneration = session.ObservationGeneration;
                }
                ReconcileKeyState(vk, down);
                bool repeated = down && !_physicalKeysDown.Add(vk);
                if (up) _physicalKeysDown.Remove(vk);
                if (_r1 != null && (vk is VK_LCONTROL or VK_RCONTROL) && !repeated)
                {
                    // Control may be held from outside the window or from an editor.
                    // Only a fresh local Down in this same focus interval starts a chord.
                    var stamp = down && _shortcutForeground() && !_r1.IsSuppressed((int)vk) ? _r1.ShortcutStamp : null;
                    if (vk == VK_LCONTROL) _leftCtrlStamp = stamp; else _rightCtrlStamp = stamp;
                }

                // 文字输入期间全部放行：清掉本键的历史消费标记，保证退出输入后
                // 第一次真实按键不会被"已消费"状态误吞。
                if (TextInputActive || (_r1 != null && !_shortcutForeground()))
                {
                    _shortcutConsumedKeys.Remove(vk);
                    _dialogueConsumedKeys.Remove(vk);
                    return TraceDecision(vk, msg, lParam, false);
                }

                if (_shortcutConsumedKeys.Contains(vk))
                {
                    if (up) _shortcutConsumedKeys.Remove(vk);
                    if ((down || up) && IsLiveApplicationForeground()) return TraceDecision(vk, msg, lParam, true);
                }

                // 对话按一次推进一次。先于显示而已按住的互动键也不能被自动重复采纳。
                // 捕获的 Action 已绑定当时行号；不得在异步执行时重新选择当前对话。
                if (_dialogueConsumedKeys.Contains(vk))
                {
                    if (up) _dialogueConsumedKeys.Remove(vk);
                    if ((down || up) && IsLiveApplicationForeground()) return TraceDecision(vk, msg, lParam, true);
                }
                // A held key on return from a text field, modal or another app
                // cannot start a shortcut on repeat. Its actual Up clears suppression.
                if (down && _r1 != null && (repeated || _r1.IsSuppressed((int)vk)))
                    return TraceDecision(vk, msg, lParam, false);
                if (down && !repeated && msg == WM_KEYDOWN && !_ctrlHeld
                    && !_physicalKeysDown.Contains(0x10) && !_physicalKeysDown.Contains(0xA0)
                    && !_physicalKeysDown.Contains(0xA1) && !_physicalKeysDown.Contains(0x12)
                    && !_physicalKeysDown.Contains(0xA4) && !_physicalKeysDown.Contains(0xA5)
                    && !_panelEscEnabled && !(vk == VK_ESCAPE && InteractionEscActive)
                    && (_r1 == null || _r1.IsGameKeyboardAdmitted) && IsLiveApplicationForeground())
                {
                    Action dialogueAction = null;
                    try { dialogueAction = _dialogueKeyProbe?.Invoke(vk); } catch { }
                    if (dialogueAction != null)
                    {
                        _dialogueConsumedKeys.Add(vk);
                        return TraceDecision(vk, msg, lParam, true, dialogueAction);
                    }
                }

                if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
                {
                    bool shouldBlock = false;

                    // Ctrl + 被保护键
                    if (_ctrlHeld && _blockedVks.Contains(vk))
                    {
                        var stamp = _r1?.ShortcutStamp;
                        shouldBlock = _r1 == null || stamp.HasValue &&
                            ((_leftCtrlHeld && _leftCtrlStamp == stamp) || (_rightCtrlHeld && _rightCtrlStamp == stamp));
                    }

                    // Escape（全屏时 / 面板打开时 / native_interaction 交互会话存活时）
                    if (vk == VK_ESCAPE && (_escEnabled || _panelEscEnabled || InteractionEscActive))
                        shouldBlock = true;

                    if (shouldBlock && ShouldInterceptForOurApp())
                    {
                        // Capture a panel owner now, before the queued worker/UI callbacks.
                        Action capturedEscape=vk==VK_ESCAPE ? CapturePanelEscapeAction?.Invoke() : null;
                        if(vk==VK_ESCAPE && _panelEscEnabled && capturedEscape==null)return TraceDecision(vk,msg,lParam,false);
                        _shortcutConsumedKeys.Add(vk);
                        // 触发动作回调（异步，不阻塞钩子线程）
                        bool panelEscAtCapture=_panelEscEnabled;
                        Action shortcut = capturedEscape;
                        if (shortcut == null && _actionVks.TryGetValue(vk, out var action) && action != null)
                        {
                            shortcut = () => { if (vk != VK_ESCAPE || panelEscAtCapture == _panelEscEnabled) action(); };
                        }
                        return TraceDecision(vk, msg, lParam, true, shortcut);
                    }
                }
                return TraceDecision(vk, msg, lParam, false);
            }
        }

        private IntPtr TraceDecision(uint vk, int message, IntPtr data, bool blocked, Action action = null)
        {
            if(_r1 is {} input && (message is WM_KEYDOWN or WM_SYSKEYDOWN or WM_KEYUP or WM_SYSKEYUP)) {
                var source = (Marshal.ReadInt32(data,8)&0x10)!=0 ? InputObservationSource.Injected : InputObservationSource.Unmarked;
                bool down = message is WM_KEYDOWN or WM_SYSKEYDOWN;
                if (!CanObserveForeground(input)) {
                    _shortcutConsumedKeys.Remove(vk);
                    _dialogueConsumedKeys.Remove(vk);
                    if (!down) input.ObserveSuppressedRelease((int)vk,source);
                    return IntPtr.Zero;
                }
                var stamp = input.ShortcutStamp;
                bool hostKeyboard = _shortcutForeground();
                if (!hostKeyboard) input.SetBusinessEligible(false, "local_window");
                if (blocked && (!hostKeyboard || !stamp.HasValue)) {
                    _shortcutConsumedKeys.Remove(vk);
                    _dialogueConsumedKeys.Remove(vk);
                    blocked = false;
                }
                input.ObserveKey((int)vk,down,!blocked && hostKeyboard && stamp.HasValue,source:source);
                if (blocked && action != null) {
                    void Deliver() {
                        if (_r1Foreground() && _shortcutForeground() && input.ShortcutStamp == stamp) action();
                    }
                    if (_postShortcut == null) ThreadPool.QueueUserWorkItem(_ => Deliver());
                    else try { _postShortcut(Deliver); } catch (InvalidOperationException) { }
                }
            }
            else if (blocked && action != null) ThreadPool.QueueUserWorkItem(_ => action());
            if (CF7Launcher.Diagnostic.FocusTrace.Enabled &&
                (vk == 0x57 || vk == 0x41 || vk == 0x53 || vk == 0x44 || vk == 0x52
                    || vk == VK_LCONTROL || vk == VK_RCONTROL))
                CF7Launcher.Diagnostic.FocusTrace.Record("keyboard.decision", new {
                    hook = "KeyboardHook", vk, message, blocked,
                    leftCtrl = _leftCtrlHeld, rightCtrl = _rightCtrlHeld,
                    hookTime = unchecked((uint)Marshal.ReadInt32(data, 12)),
                    flags = Marshal.ReadInt32(data, 8),
                    foreground = GetForegroundWindow().ToInt64(),
                    liveApplicationForeground = IsLiveApplicationForeground()
                });
            return blocked ? new IntPtr(1) : IntPtr.Zero;
        }

        private bool CanObserveForeground(SessionInputAuthority input)
        {
            if (_r1Foreground()) return input.ForegroundEligible;
            input.SetForeground(false);
            return false;
        }

        private bool ShouldInterceptForOurApp() => IsLiveApplicationForeground() && !TextInputActive;

        private bool IsLiveApplicationForeground()
        {
            if (_r1 != null) return _r1.ForegroundEligible && _r1Foreground();
            if (LiveForegroundProbeForTests != null) return LiveForegroundProbeForTests();
            IntPtr foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero) return false;
            uint pid;
            GetWindowThreadProcessId(foreground, out pid);
            return pid == _myPid;
        }

        public void Dispose()
        {
            _running = false;

            if (_hookId != IntPtr.Zero)
            {
                UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
            }

            if (_threadId != 0)
                PostThreadMessage(_threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);

            if (_thread != null && _thread.IsAlive)
                _thread.Join(1000);

            Guardian.LogManager.Log("[KeyboardHook] Disposed");
        }
    }
}
