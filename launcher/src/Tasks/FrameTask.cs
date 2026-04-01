using System;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.V8;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 处理 Flash 每帧发送的 frame 消息。
    /// 包含摄像头状态（cam）、可选的伤害数字数据（hn）和可选的 FPS 数据。
    ///
    /// 快车道路径（主路径）：
    ///   XmlSocketServer 前缀检测 → HandleRaw(cam, hn, fps)
    ///     绕过 MessageRouter / JObject.Parse，零 GC 分配
    ///
    /// JSON 回退路径（兼容）：
    ///   MessageRouter → Handle(JObject)
    ///     Phase 1 期间保留，确认快车道稳定后由 Phase 3 移除
    ///
    /// 共同调用链：
    ///   → V8 updateCamera + spawnBatch + tick（V8 lock 内）
    ///   → overlay.UpdateRender（BeginInvoke → UI 线程）
    /// </summary>
    public class FrameTask
    {
        private readonly V8Runtime _v8;
        private readonly HitNumberOverlay _overlay;
        private readonly FpsRingBuffer _fpsBuffer;

        public FpsRingBuffer FpsBuffer { get { return _fpsBuffer; } }

        public FrameTask(V8Runtime v8, HitNumberOverlay overlay)
        {
            _v8 = v8;
            _overlay = overlay;
            _fpsBuffer = new FpsRingBuffer(600);
        }

        /// <summary>
        /// 快车道入口：由 XmlSocketServer 前缀检测直接调用，跳过 JObject 构造。
        /// 前缀协议格式：F{cam}\x01{hn}\x02{fps}
        /// fps 字段可选（仅在有新采样时存在）。
        /// </summary>
        public void HandleRaw(string cam, string hn, string fps)
        {
            try
            {
                if (!string.IsNullOrEmpty(cam))
                    _v8.UpdateCamera(cam);

                if (!string.IsNullOrEmpty(hn))
                    _v8.SpawnBatch(hn);

                string renderStr = _v8.Tick();
                _overlay.UpdateRender(renderStr);

                if (!string.IsNullOrEmpty(fps))
                {
                    // 格式：fps 或 fps|hour
                    int pipe = fps.IndexOf('|');
                    string fpsStr = (pipe >= 0) ? fps.Substring(0, pipe) : fps;
                    float fpsVal;
                    if (float.TryParse(fpsStr, out fpsVal))
                        _fpsBuffer.Push(fpsVal);
                    if (pipe >= 0 && pipe < fps.Length - 1)
                    {
                        float hour;
                        if (float.TryParse(fps.Substring(pipe + 1), out hour))
                            _fpsBuffer.SetGameHour(hour);
                    }
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[Frame] HandleRaw error: " + ex.Message);
            }
        }

        /// <summary>
        /// 快车道入口：hn_reset，由前缀 "R" 触发。
        /// </summary>
        public void HandleReset()
        {
            try
            {
                _v8.Reset();
                _overlay.NotifyReset();
            }
            catch (Exception ex)
            {
                LogManager.Log("[Frame] HandleReset error: " + ex.Message);
            }
        }

        /// <summary>
        /// JSON 回退入口：由 MessageRouter 调用（Phase 1 兼容，Phase 3 移除）。
        /// </summary>
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
