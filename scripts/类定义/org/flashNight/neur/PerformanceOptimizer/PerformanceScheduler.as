import org.flashNight.arki.render.FrameBroadcaster;

/**
 * PerformanceScheduler - 性能调度薄壳（采样 + 广播 + 远程/本地执行）
 *
 * 决策逻辑已迁移到 C# PerfDecisionEngine（launcher/src/Guardian/PerfDecisionEngine.cs）。
 * AS2 端仅负责：
 * 1. 帧计数 + 区间平均 FPS 测量（IntervalSampler）
 * 2. FPS 载荷广播（FrameBroadcaster → C# FrameTask）
 * 3. 接收 C# P 指令并执行（applyFromLauncher → PerformanceActuator）
 * 4. 本地后备：Socket 断连时的极简阈值降级
 *
 * 【数据流】
 *   evaluate() 每帧调用 → 采样计数器递减 → 到达采样点 → 测量 FPS → 广播
 *   C# PerfDecisionEngine 收到 FPS → 统计决策 → P{tier}|{softU100}
 *   ServerManager P 前缀 → applyFromLauncher() → PerformanceActuator.apply()
 *
 * 【本地后备（Socket 断连时）】
 *   极简阈值：FPS < 15 → tier=1, FPS > 24 连续 3 次 → tier=0
 *   不使用 Kalman/PID，仅保证不冻屏
 */
class org.flashNight.neur.PerformanceOptimizer.PerformanceScheduler {

    private var _host:Object;
    private var _env:Object;

    private var _frameRate:Number;
    private var _targetFPS:Number;
    private var _presetQuality:String;
    private var _performanceLevel:Number;
    private var _actualFPS:Number;

    private var _sampler:org.flashNight.neur.PerformanceOptimizer.IntervalSampler;
    private var _actuator:Object;
    private var _lastAppliedSoftU:Number;

    // --- 远程控制 (C# 决策引擎) ---
    private var _remoteControlled:Boolean;
    private var _lastRemoteMs:Number;
    private static var REMOTE_TIMEOUT_MS:Number = 10000;

    // --- 本地后备（断连时使用）---
    private var _fallbackUpgradeCount:Number;  // 升级确认计数
    private var _panicFPS:Number;

    /**
     * 构造函数
     * @param host:Object       宿主对象（_root.帧计时器）
     * @param frameRate:Number  标称帧率（默认30）
     * @param targetFPS:Number  目标帧率（默认26）
     * @param presetQuality:String 预设画质（默认 _root._quality）
     * @param env:Object        （可选）依赖注入，至少应包含 {root}
     */
    public function PerformanceScheduler(host:Object, frameRate:Number, targetFPS:Number, presetQuality:String, env:Object) {
        this._host = host;

        if (env == undefined) {
            env = { root: _root };
        }
        this._env = env;

        this._frameRate = (frameRate != undefined) ? frameRate : 30;
        this._targetFPS = (targetFPS != undefined) ? targetFPS : 26;
        this._presetQuality = (presetQuality != undefined) ? presetQuality : this._env.root._quality;
        this._performanceLevel = 0;
        this._actualFPS = 0;

        this._sampler = new org.flashNight.neur.PerformanceOptimizer.IntervalSampler(this._frameRate);
        this._actuator = new org.flashNight.neur.PerformanceOptimizer.PerformanceActuator(host, this._presetQuality, this._env);

        this._lastAppliedSoftU = 0;
        this._remoteControlled = false;
        this._lastRemoteMs = 0;
        this._fallbackUpgradeCount = 0;
        this._panicFPS = 5;
    }

    /**
     * 每帧调用。采样计数→测量→广播→（远程: 等待 P 指令 / 本地后备: 极简阈值）
     */
    public function evaluate(currentTime:Number):Void {
        var sampler:Object = this._sampler;
        if (--sampler._framesLeft !== 0) {
            return;
        }

        if (currentTime == undefined) {
            currentTime = getTimer();
        }

        var root:Object = this._env.root;
        var currentLevel:Number = this._performanceLevel;

        // 测量：区间平均 FPS
        var actualFPS:Number = sampler.measure(currentTime, currentLevel);
        this._actualFPS = actualFPS;

        // ── 远程控制模式 ──────────────────────────
        if (this._remoteControlled) {
            if (currentTime - this._lastRemoteMs > REMOTE_TIMEOUT_MS) {
                this.setRemoteControlled(false);
                // 落入本地后备
            } else {
                sampler.resetInterval(currentTime, currentLevel);
                var fpsStrR:String = String(Math.round(actualFPS * 10) / 10);
                var hourStrR:String = (root.天气系统 != undefined) ? String(root.天气系统.getCurrentTime()) : "6";
                fpsStrR += "|" + hourStrR + "|" + String(currentLevel);
                FrameBroadcaster.setFpsPayload(fpsStrR);
                return;
            }
        }

        // ── 本地后备（Socket 断连或超时时运行）──────
        var actuator:Object = this._actuator;

        // 紧急降级
        if (actualFPS < this._panicFPS && currentLevel < 1) {
            actuator.setPresetQuality(this._presetQuality);
            actuator.apply(1, 1.0);
            this._performanceLevel = 1;
            this._lastAppliedSoftU = 1.0;
            this._fallbackUpgradeCount = 0;
            currentLevel = 1;
        } else if (currentLevel < 1 && actualFPS < 15) {
            // 简单降级: FPS < 15 → tier=1
            actuator.setPresetQuality(this._presetQuality);
            actuator.apply(1, 1.0);
            this._performanceLevel = 1;
            this._lastAppliedSoftU = 1.0;
            this._fallbackUpgradeCount = 0;
            currentLevel = 1;
        } else if (currentLevel > 0 && actualFPS > 24) {
            // 升级候选: FPS > 24 连续 3 次
            this._fallbackUpgradeCount++;
            if (this._fallbackUpgradeCount >= 3) {
                var host:Object = this._host;
                var cap:Number = (host && !isNaN(host.性能等级上限)) ? host.性能等级上限 : 0;
                if (cap < 1) {
                    actuator.setPresetQuality(this._presetQuality);
                    actuator.apply(0, 0);
                    this._performanceLevel = 0;
                    this._lastAppliedSoftU = 0;
                    currentLevel = 0;
                }
                this._fallbackUpgradeCount = 0;
            }
        } else {
            this._fallbackUpgradeCount = 0;
        }

        // 重置采样窗口 + 广播
        sampler.resetInterval(currentTime, currentLevel);
        var fpsStr:String = String(Math.round(actualFPS * 10) / 10);
        var hourStr:String = (root.天气系统 != undefined) ? String(root.天气系统.getCurrentTime()) : "6";
        fpsStr += "|" + hourStr + "|" + String(currentLevel);
        FrameBroadcaster.setFpsPayload(fpsStr);
    }

    // ------------------------------------------------------------------
    // 前馈控制接口
    // ------------------------------------------------------------------

    public function setPerformanceLevel(level:Number, holdSec:Number, currentTime:Number):Void {
        level = Math.round(level);
        var host:Object = this._host;
        var cap:Number = (host && !isNaN(host.性能等级上限)) ? host.性能等级上限 : 0;
        level = Math.max(cap, Math.min(level, 1));

        var appliedSoftU:Number = (level > 0) ? 1.0 : 0.0;
        this._actuator.setPresetQuality(this._presetQuality);
        this._actuator.apply(level, appliedSoftU);
        this._performanceLevel = level;
        this._lastAppliedSoftU = appliedSoftU;

        if (currentTime == undefined) {
            currentTime = getTimer();
        }
        this._sampler.resetInterval(currentTime, level);

        var root:Object = this._env.root;
        var estimatedFPS:Number = this._frameRate - level * 2;
        this._actualFPS = estimatedFPS;
        var fpsStr:String = String(Math.round(estimatedFPS * 10) / 10);
        var hourStr:String = (root.天气系统 != undefined) ? String(root.天气系统.getCurrentTime()) : "6";
        fpsStr += "|" + hourStr + "|" + String(level);
        FrameBroadcaster.setFpsPayload(fpsStr);
    }

    public function decreaseLevel(steps:Number, holdSec:Number, currentTime:Number):Void {
        steps = steps || 1;
        this.setPerformanceLevel(this._performanceLevel + steps, holdSec, currentTime);
    }

    public function increaseLevel(steps:Number, holdSec:Number, currentTime:Number):Void {
        steps = steps || 1;
        this.setPerformanceLevel(this._performanceLevel - steps, holdSec, currentTime);
    }

    /**
     * 场景切换重置
     */
    public function onSceneChanged():Void {
        var now:Number = getTimer();

        var host:Object = this._host;
        var cap:Number = (host && !isNaN(host.性能等级上限)) ? host.性能等级上限 : 0;
        var resetLevel:Number = Math.max(cap, 0);
        var resetSoftU:Number = (resetLevel > 0) ? 1.0 : 0.0;
        this._actuator.setPresetQuality(this._presetQuality);
        this._actuator.apply(resetLevel, resetSoftU);
        this._performanceLevel = resetLevel;
        this._lastAppliedSoftU = resetSoftU;
        this._fallbackUpgradeCount = 0;
        this._sampler.resetInterval(now, resetLevel);
    }

    // ------------------------------------------------------------------
    // 远程控制接口（C# 决策引擎）
    // ------------------------------------------------------------------

    public function setRemoteControlled(enabled:Boolean):Void {
        if (!enabled && this._remoteControlled) {
            this._fallbackUpgradeCount = 0;
            this._sampler.resetInterval(getTimer(), this._performanceLevel);
        }
        this._remoteControlled = enabled;
        if (enabled) {
            this._lastRemoteMs = getTimer();
        }
    }

    public function isRemoteControlled():Boolean {
        return this._remoteControlled;
    }

    public function applyFromLauncher(tier:Number, softU:Number):Void {
        var now:Number = getTimer();
        this._lastRemoteMs = now;
        this._remoteControlled = true;

        if (tier == this._performanceLevel && softU == this._lastAppliedSoftU) {
            return;
        }

        if (tier != this._performanceLevel) {
            this._sampler.resetInterval(now, tier);
        }

        this._actuator.setPresetQuality(this._presetQuality);
        this._actuator.apply(tier, softU);
        this._performanceLevel = tier;
        this._lastAppliedSoftU = softU;
    }

    // ------------------------------------------------------------------
    // Accessors
    // ------------------------------------------------------------------

    public function setPresetQuality(q:String):Void { this._presetQuality = q; }
    public function getPresetQuality():String { return this._presetQuality; }
    public function getActuator():Object { return this._actuator; }
    public function setActuator(actuator:Object):Void { this._actuator = actuator; }
    public function getSampler():org.flashNight.neur.PerformanceOptimizer.IntervalSampler { return this._sampler; }
    public function getPerformanceLevel():Number { return this._performanceLevel; }
    public function getActualFPS():Number { return this._actualFPS; }
    public function getTargetFPS():Number { return this._targetFPS; }
    public function getLastAppliedSoftU():Number { return this._lastAppliedSoftU; }
}
