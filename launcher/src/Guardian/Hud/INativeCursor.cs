using System.Drawing;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Native cursor overlay 抽象。Phase 1 抽出此接口以便引入 DesktopCursorOverlay
    /// （desktop 顶层 ULW，独立于 OverlayBase / Flash anchor 体系）与旧 CursorOverlayForm
    /// 共存切换。WebOverlayForm / PanelHostController / Program.cs 通过此接口与 cursor 通信，
    /// 不再持有具体类型。
    ///
    /// 接口签名与现 CursorOverlayForm 1:1 对齐；新增 SetForceHidden 用于 game-forced 隐藏路径
    /// （Phase 2 替代 WebOverlayForm 直接调 Cursor.Hide/Show）。
    /// </summary>
    public interface INativeCursor
    {
        /// <summary>启动期 ready 信号（WebView2 ready 或 Flash 首帧后调）。</summary>
        void SetReady();

        /// <summary>更新视觉状态（normal/click/hoverGrab/grab/attack/openDoor）。</summary>
        void SetCursorState(string state, bool dragging);

        /// <summary>推送屏幕坐标（来自 WH_MOUSE_LL hook 或 web 端推送）。</summary>
        void UpdateCursorPosition(Point screen);

        /// <summary>调用方主控可见性（panel 打开/关闭、热区切换）。</summary>
        void SetCursorVisible(bool visible);

        /// <summary>
        /// 设置渲染 scale。viewportScale 主用，dpi 仅在 viewport 失效时 fallback。
        /// 见 DesktopCursorOverlay.ComputeEffectiveScale。
        /// </summary>
        void SetScale(double viewportScale, int dpiX, int dpiY);

        /// <summary>
        /// Game-forced 隐藏（Phase 2 引入）。优先级最高，mouse activity 不会唤醒。
        /// 用于 cutscene / 强制脚本控制阶段。Phase 1 桩：旧 CursorOverlayForm 转 SetCursorVisible。
        /// </summary>
        void SetForceHidden(bool forceHidden);

        /// <summary>兼容旧入口：仅传 DPI（viewportScale 默认 1.0）。新代码请用 SetScale。</summary>
        void SetDpiScale(int dpiX, int dpiY);

        /// <summary>P2-3 perf：ULW 首帧预提交。OverlayBase.PreCommitTransparent 的接口投影。</summary>
        void PreCommitTransparent();

        /// <summary>资源释放（IDisposable 投影；Form.Dispose 已实现）。</summary>
        void Dispose();

        /// <summary>
        /// true 表示 cursor 是 desktop 顶层实现，坐标与系统 cursor 隐藏由自身管理；
        /// WebOverlayForm 不应再按 Flash/Web overlay bounds 裁剪它。
        /// </summary>
        bool UsesDesktopCoordinates { get; }
    }
}
