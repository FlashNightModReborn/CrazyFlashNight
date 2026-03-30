using System;
using System.IO;
using Microsoft.ClearScript.V8;

namespace CF7Launcher.V8
{
    /// <summary>
    /// 持久化 V8 引擎单例，运行受信任的内部 TS 编译产物。
    /// 与 EvalTask（每次创建新引擎的不受信任沙箱）独立共存。
    ///
    /// 线程安全：ReadLoop 线程写 camera/spawn，UI 线程可能调用 Reset。
    /// 单 _lock 保护所有 V8 访问。
    /// </summary>
    public class V8Runtime : IDisposable
    {
        private readonly V8ScriptEngine _engine;
        private readonly object _lock = new object();
        private readonly bool _loaded;

        public V8Runtime(string scriptsDir)
        {
            _engine = new V8ScriptEngine(V8ScriptEngineFlags.DisableGlobalMembers);
            string bundlePath = Path.Combine(scriptsDir, "dist", "hit-number-bundle.js");
            if (!File.Exists(bundlePath))
            {
                Guardian.LogManager.Log("[V8Runtime] FATAL: Bundle not found: " + bundlePath);
                _loaded = false;
                return;
            }
            string code = File.ReadAllText(bundlePath);
            _engine.Execute(code);
            _loaded = true;
            Guardian.LogManager.Log("[V8Runtime] Loaded: " + bundlePath);
        }

        public bool IsLoaded { get { return _loaded; } }

        /// <summary>
        /// 更新摄像头状态。格式: "gx|gy|sx"
        /// </summary>
        public void UpdateCamera(string raw)
        {
            if (!_loaded) return;
            lock (_lock)
            {
                _engine.Script.HitNumber.updateCameraRaw(raw);
            }
        }

        /// <summary>
        /// 批量 spawn 伤害数字。格式: "v|x|y|p|et|ee|ls|sa;..."
        /// </summary>
        public void SpawnBatch(string raw)
        {
            if (!_loaded) return;
            lock (_lock)
            {
                _engine.Script.HitNumber.spawnBatch(raw);
            }
        }

        /// <summary>
        /// 推进一帧动画并返回渲染描述符字符串。
        /// 由 Flash frame 消息驱动，非独立 Timer。
        /// </summary>
        public string Tick()
        {
            if (!_loaded) return "";
            lock (_lock)
            {
                object result = _engine.Script.HitNumber.tick();
                return result as string ?? "";
            }
        }

        /// <summary>
        /// 场景切换时清空所有活跃动画。
        /// </summary>
        public void Reset()
        {
            if (!_loaded) return;
            lock (_lock)
            {
                _engine.Script.HitNumber.reset();
            }
        }

        public void Dispose()
        {
            _engine.Dispose();
        }
    }
}
