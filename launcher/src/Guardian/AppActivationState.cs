using System;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 应用激活状态的权威源——取代散落在 KeyboardHook / PerfDecisionEngine 里的
    /// GetForegroundWindow() 现场轮询。
    ///
    /// 设计（Win32 game-loop 标准范式）：
    ///   • 激活：来自 WM_ACTIVATEAPP。它是【进程级】信号——同进程窗口之间切换不触发，
    ///     正好回答"用户当前在不在用我这个 app"。比轮询 GetForegroundWindow() 可靠：
    ///     后者只反映窗口级焦点，且与瞬态窗口存在竞态。
    ///   • 最小化：来自 WM_SIZE / SIZE_MINIMIZED。
    ///
    /// 去抖动机：后台程序（QQ / Telegram 等的消息通知）会瞬间抢走系统前台再归还，
    /// 产生 WM_ACTIVATEAPP(false) → (true) 抖动。失活【不立即生效】，留一个
    /// DEACTIVATE_DEBOUNCE_MS 宽限窗；窗内重新激活则视作从未失活。
    ///
    /// 线程模型：GuardianForm 的 UI 线程写（WndProc），KeyboardHook 钩子线程与
    /// FrameTask 线程读。所有字段 volatile + 单调 TickCount 运算，无锁。
    /// </summary>
    public sealed class AppActivationState
    {
        /// <summary>WM_ACTIVATEAPP(false) 之后，仍视作激活的宽限窗口（毫秒）。</summary>
        private const int DEACTIVATE_DEBOUNCE_MS = 450;

        // 最近一次 WM_ACTIVATEAPP 的原始值（未去抖）。
        private volatile bool _rawActive = true;
        private volatile bool _minimized;
        // WM_ACTIVATEAPP(false) 发生的 TickCount；仅在 _rawActive==false 时有意义。
        private volatile int _deactivateTick;

        /// <summary>
        /// 应用是否激活（已去抖）。WM_ACTIVATEAPP(false) 之后 DEACTIVATE_DEBOUNCE_MS
        /// 毫秒内仍返回 true，以容忍后台程序的瞬时抢焦。
        /// </summary>
        public bool IsAppActive
        {
            get
            {
                if (_rawActive) return true;
                // unchecked 减法处理 TickCount 49 天溢出（rollover 后差值仍正确）。
                int elapsed = unchecked(Environment.TickCount - _deactivateTick);
                return elapsed >= 0 && elapsed < DEACTIVATE_DEBOUNCE_MS;
            }
        }

        /// <summary>窗口是否处于最小化状态。</summary>
        public bool IsMinimized { get { return _minimized; } }

        /// <summary>
        /// WM_ACTIVATEAPP 处理入口。active = (wParam != 0)：true 表示本进程被激活。
        /// 由 GuardianForm.WndProc 在 UI 线程调用。
        /// </summary>
        public void OnActivateApp(bool active)
        {
            if (active)
            {
                _rawActive = true;
            }
            else
            {
                // 先记 tick 再翻 _rawActive：_rawActive 的 volatile 写是 release 语义，
                // 保证读到 _rawActive==false 的线程必能看到此处写入的 _deactivateTick。
                _deactivateTick = Environment.TickCount;
                _rawActive = false;
            }
        }

        /// <summary>
        /// WM_SIZE 处理入口。minimized = (wParam == SIZE_MINIMIZED)。
        /// 由 GuardianForm.WndProc 在 UI 线程调用。
        /// </summary>
        public void OnMinimizeChanged(bool minimized)
        {
            _minimized = minimized;
        }
    }
}
