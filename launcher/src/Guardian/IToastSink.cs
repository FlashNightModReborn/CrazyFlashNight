namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Toast 消息接收接口。
    /// 解耦 ToastTask 与具体 overlay 实现（WebOverlayForm 转发到 NativeHud ToastWidget）。
    /// </summary>
    public interface IToastSink
    {
        void AddMessage(string text);
        void SetReady();
    }
}
