using System;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.V8;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 处理 Flash 每帧发送的 "frame" 消息。
    /// 包含摄像头状态（cam）和可选的伤害数字数据（hn）。
    ///
    /// 调用链：
    ///   ReadLoop 线程 → Handle()
    ///     → V8 updateCamera + spawnBatch + tick（V8 lock 内）
    ///     → overlay.UpdateRender（BeginInvoke → UI 线程）
    /// </summary>
    public class FrameTask
    {
        private readonly V8Runtime _v8;
        private readonly HitNumberOverlay _overlay;

        public FrameTask(V8Runtime v8, HitNumberOverlay overlay)
        {
            _v8 = v8;
            _overlay = overlay;
        }

        public string Handle(JObject message)
        {
            try
            {
                string cam = message.Value<string>("cam");
                if (!string.IsNullOrEmpty(cam))
                    _v8.UpdateCamera(cam);

                string hn = message.Value<string>("hn");
                if (!string.IsNullOrEmpty(hn))
                    _v8.SpawnBatch(hn);

                string renderStr = _v8.Tick();
                _overlay.UpdateRender(renderStr);
            }
            catch (Exception ex)
            {
                LogManager.Log("[Frame] Error: " + ex.Message);
            }
            return null; // fire-and-forget
        }
    }
}
