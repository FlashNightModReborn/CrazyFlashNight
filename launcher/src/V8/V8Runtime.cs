using System;
using System.IO;
using Microsoft.ClearScript.V8;

namespace CF7Launcher.V8
{
    /// <summary>
    /// 持久化 V8 引擎单例，运行受信任的内部 TS 编译产物（hit-number-bundle.js）。
    /// 由 FrameTask 每帧驱动：UpdateCamera → SpawnBatch → Tick → 渲染描述符。
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

        // ========== GameInput namespace (搓招 DFA 迁移) ==========

        /// <summary>
        /// 初始化搓招输入处理器（启动时调用一次）。
        /// </summary>
        public void InitGameInput()
        {
            if (!_loaded) return;
            lock (_lock)
            {
                _engine.Script.GameInput.init();
                object logResult = _engine.Script.GameInput.flushLog();
                string logs = logResult as string ?? "";
                if (logs.Length > 0)
                    Guardian.LogManager.Log(logs);
            }
            Guardian.LogManager.Log("[V8Runtime] GameInput initialized");
        }

        /// <summary>
        /// 加载一个搓招模组的 DFA 数据（AS2 通过 D 前缀发送）。
        /// </summary>
        /// <param name="moduleId">"0"=barehand, "1"=lightWeapon, "2"=heavyWeapon</param>
        /// <param name="dataJson">DfaModuleData JSON 字符串</param>
        public void LoadInputModule(string moduleId, string dataJson)
        {
            if (!_loaded) return;
            lock (_lock)
            {
                _engine.Script.GameInput.loadModule(moduleId, dataJson);
                object logResult = _engine.Script.GameInput.flushLog();
                string logs = logResult as string ?? "";
                if (logs.Length > 0)
                    Guardian.LogManager.Log(logs);
            }
            Guardian.LogManager.Log("[V8Runtime] GameInput module loaded: " + moduleId);
        }

        /// <summary>
        /// 每帧处理输入：InputSampler + CommandDFA 状态转移。
        /// 返回 K 前缀 payload 字符串。
        /// </summary>
        /// <param name="mask">8-bit bitmask (AS2 Key.isDown 生成)</param>
        /// <param name="facingBit">0=左, 1=右</param>
        /// <param name="moduleId">0/1/2</param>
        /// <param name="doubleTapDir">-1/0/1</param>
        public string ProcessInput(int mask, int facingBit, int moduleId, int doubleTapDir)
        {
            if (!_loaded) return "";
            lock (_lock)
            {
                object result = _engine.Script.GameInput.processFrame(mask, facingBit, moduleId, doubleTapDir);
                string kPayload = result as string ?? "";

                // 刷新 V8 日志缓冲
                object logResult = _engine.Script.GameInput.flushLog();
                string logs = logResult as string ?? "";
                if (logs.Length > 0)
                    Guardian.LogManager.Log(logs);

                return kPayload;
            }
        }

        public void Dispose()
        {
            _engine.Dispose();
        }
    }
}
