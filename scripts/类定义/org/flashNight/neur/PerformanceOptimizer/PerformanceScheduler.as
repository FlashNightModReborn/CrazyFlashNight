import org.flashNight.arki.render.FrameBroadcaster;

/**
 * Flash 性能桥：只采集实际帧时间并执行 C# 的完整表现目标。
 * C# 独占预设、预算、升降档与冷却；断连时保持最后有效状态。
 * P 指令：tier|softU100|quality|command|scene，scene 同时隔离场景与连接。
 */
class org.flashNight.neur.PerformanceOptimizer.PerformanceScheduler {
    private var _env:Object;
    private var _presetQuality:String;
    private var _performanceLevel:Number;
    private var _actualFPS:Number;
    private var _targetFPS:Number;
    private var _sampler:org.flashNight.neur.PerformanceOptimizer.IntervalSampler;
    private var _actuator:Object;
    private var _lastAppliedSoftU:Number;
    private var _renderQuality:String;
    private var _transportConnected:Boolean;
    private var _sceneEpoch:Number;
    private var _sampleSequence:Number;
    private var _receivedCommand:Number;
    private var _receivedTier:Number;
    private var _receivedSoftU:Number;
    private var _receivedQuality:String;
    private var _appliedCommand:Number;

    public function PerformanceScheduler(host:Object, frameRate:Number, targetFPS:Number, presetQuality:String, env:Object) {
        if (env == undefined) env = {root:_root};
        this._env = env;
        this._presetQuality = presetQuality != undefined ? presetQuality : env.root._quality;
        this._renderQuality = this._presetQuality;
        this._performanceLevel = this._renderQuality == "LOW" ? 1 : 0;
        this._actualFPS = 0;
        this._targetFPS = targetFPS != undefined ? targetFPS : 26;
        this._sampler = new org.flashNight.neur.PerformanceOptimizer.IntervalSampler(frameRate);
        this._actuator = new org.flashNight.neur.PerformanceOptimizer.PerformanceActuator(host, this._presetQuality, env);
        this._lastAppliedSoftU = 0;
        this._transportConnected = false;
        this._sceneEpoch = 0;
        this._sampleSequence = 0;
        this._receivedCommand = 0;
        this._appliedCommand = 0;
    }

    /** 固定的启动表现默认值，不形成调度或虚构执行确认。 */
    public function applyInitialState():Void {
        this._actuator.apply(this._performanceLevel, this._lastAppliedSoftU, this._renderQuality);
    }

    /** 每帧只累积实测时间；断连、低帧率或旧存档上限均不触发本地调档。 */
    public function evaluate(currentTime:Number):Void {
        if (currentTime == undefined) currentTime = getTimer();
        var sampler:Object = this._sampler;
        if (!sampler.observe(currentTime)) return;
        this._actualFPS = sampler.sampleFrames * 1000 / sampler.sampleDurationMs;
        var measuredPayload:String = this.buildMeasuredPayload();
        sampler.resetInterval(currentTime, this._performanceLevel);
        FrameBroadcaster.setFpsPayload(measuredPayload);
    }

    private function buildMeasuredPayload():String {
        var root:Object = this._env.root;
        var sampler:Object = this._sampler;
        var hour:Number = root.天气系统 != undefined ? root.天气系统.getCurrentTime() : 6;
        // preset 仅保留 v2 格式兼容；Host 不再把它当作策略或最高画质权威。
        return String(Math.round(this._actualFPS * 10) / 10) + "|" + hour + "|" + this._performanceLevel + "|" + this._sceneEpoch
            + "|v2|" + sampler.sampleFrames + "|" + sampler.sampleDurationMs + "|" + sampler.longFrames + "|" + sampler.maxFrameMs
            + "|" + this._presetQuality + "|" + root._quality + "|0"
            + "|" + (root.暂停 ? "1" : "0") + "|" + (++this._sampleSequence) + "|" + this._appliedCommand;
    }

    /** 新连接从新的观察 epoch 开始，Host 命令编号可从 1 重新开始。 */
    public function onTransportConnected():Void {
        if (this._transportConnected) return;
        this._transportConnected = true;
        this.resetObservationEpoch();
    }

    public function onTransportDisconnected():Void {
        this._transportConnected = false;
    }

    public function onSceneChanged():Void {
        this.resetObservationEpoch();
        // 新世界中的表现消费者只重放末次有效目标，不读取旧存档 cap。
        this._actuator.apply(this._performanceLevel, this._lastAppliedSoftU, this._renderQuality);
    }

    private function resetObservationEpoch():Void {
        this._sceneEpoch++;
        this._receivedCommand = 0;
        this._appliedCommand = 0;
        this._sampler.resetInterval(getTimer(), this._performanceLevel);
        FrameBroadcaster.setFpsPayload(null);
    }

    public function applyFromLauncher(tier:Number, softU:Number, quality:String, command:Number, scene:Number):Void {
        if (!this._transportConnected || (tier != 0 && tier != 1)) return;
        if ((softU - softU) != 0 || softU < 0 || softU > 1) return;
        if (quality != "LOW" && quality != "MEDIUM" && quality != "HIGH" && quality != "BEST") return;
        if ((quality == "LOW") != (tier == 1)) return;
        if ((command - command) != 0 || command < 1 || command % 1 != 0
                || command < this._receivedCommand || scene != this._sceneEpoch) return;

        if (command == this._receivedCommand) {
            // 同一身份只能表示同一个完整目标，包含失败后重发的情况。
            if (tier != this._receivedTier || softU != this._receivedSoftU || quality != this._receivedQuality) return;
            if (command == this._appliedCommand && this._env.root._quality == quality) return;
        } else {
            this._receivedCommand = command;
            this._receivedTier = tier;
            this._receivedSoftU = softU;
            this._receivedQuality = quality;
        }

        // 先执行再确认。未执行/实际画质不一致时保留未确认身份，允许同目标重试。
        if (this._actuator.apply(tier, softU, quality) !== true || this._env.root._quality != quality) return;
        this._renderQuality = quality;
        this._performanceLevel = tier;
        this._lastAppliedSoftU = softU;
        this._appliedCommand = command;
        this._sampler.resetInterval(getTimer(), tier);
    }

    public function isRemoteControlled():Boolean { return this._transportConnected; }
    public function getPresetQuality():String { return this._presetQuality; }
    public function getActuator():Object { return this._actuator; }
    public function setActuator(actuator:Object):Void { this._actuator = actuator; }
    public function getSampler():org.flashNight.neur.PerformanceOptimizer.IntervalSampler { return this._sampler; }
    public function getPerformanceLevel():Number { return this._performanceLevel; }
    public function getActualFPS():Number { return this._actualFPS; }
    public function getTargetFPS():Number { return this._targetFPS; }
    public function getLastAppliedSoftU():Number { return this._lastAppliedSoftU; }
    public function getSceneEpoch():Number { return this._sceneEpoch; }
    public function getAppliedCommand():Number { return this._appliedCommand; }
}
