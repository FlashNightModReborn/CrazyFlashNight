using System;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 从 WM_ACTIVATEAPP / WM_SIZE 采样呈现与性能决策所需的进程激活和最小化状态。
    /// UI 线程写入，呈现和帧处理线程读取。短暂失活期间沿用当前性能策略。
    /// </summary>
    public sealed class AppActivationState
    {
        /// <summary>
        /// WM_ACTIVATEAPP(false) 之后，仍视作激活的宽限窗口（毫秒）。
        /// 给呈现策略保留短暂通知窗口抢占前台时的稳定期。
        /// </summary>
        private const int DEACTIVATE_DEBOUNCE_MS = 200;

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
