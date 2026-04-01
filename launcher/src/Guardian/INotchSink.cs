using System.Drawing;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Notch 状态/通知接收接口。
    /// 解耦 XmlSocketServer 与具体 overlay 实现（GDI+ NotchOverlay 或 WebOverlayForm）。
    /// </summary>
    public interface INotchSink
    {
        void AddNotice(string category, string text, Color accentColor);
        void SetStatusItem(string id, string label, string subLabel, Color accentColor);
        void ClearStatusItem(string id);
        void SetReady();
    }
}
