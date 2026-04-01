namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Toast 消息接收接口。
    /// 解耦 ToastTask 与具体 overlay 实现（GDI+ ToastOverlay 或 WebOverlayForm）。
    /// </summary>
    public interface IToastSink
    {
        void AddMessage(string text);
        void SetReady();
    }
}
