namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Panel ESC 拦截源。让 PanelHostController 在不直接耦合 KeyboardHook 的前提下
    /// 启用/禁用 ESC 拦截（fallback 模式下可由 RegisterHotKey 路径实现）。
    /// </summary>
    public interface IPanelEscapeSource
    {
        void SetPanelEscapeEnabled(bool enabled);
    }
}
