using System;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Fire-and-forget toast 消息处理器。
    /// 接收 Flash 发来的 {"task":"toast","payload":"消息文本"} 并转发到 ToastOverlay。
    /// </summary>
    public class ToastTask
    {
        private readonly IToastSink _overlay;

        public ToastTask(IToastSink overlay)
        {
            _overlay = overlay;
        }

        public string Handle(JObject message)
        {
            try
            {
                string text = message.Value<string>("payload");
                if (!string.IsNullOrEmpty(text))
                    _overlay.AddMessage(text);
            }
            catch (Exception ex)
            {
                LogManager.Log("[Toast] Handle error: " + ex.Message);
            }
            return null; // fire-and-forget，不回复 Flash
        }
    }
}
