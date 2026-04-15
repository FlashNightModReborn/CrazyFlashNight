/**
 * BootstrapWait - preload 响应等待门闩 (Phase 1b)
 *
 * 帧 64 闭包的替代: class 持久 state + 专用 empty movie clip 做 tick
 * 轮询 _root.存档恢复等待中() (== SaveManager.isRecoveryPending())
 * 5s 超时 fail-closed (不推进)
 *
 * cleanup 顺序: 先复制 timeline/label 本地引用, 再 gotoAndPlay (v14 修复)
 *
 * 测试 hook: _tickForTest / _forceTimeoutForTest 绕过 onEnterFrame
 */
class org.flashNight.neur.Server.BootstrapWait {

    private static var _state:String = "Idle";
    private static var _done:Boolean = false;
    private static var _timeoutMs:Number = 0;
    private static var _startMs:Number = 0;
    private static var _targetTimeline:MovieClip = null;
    private static var _targetLabel:String = null;
    private static var _tickMc:MovieClip = null;

    public static function startWait(timeoutMs:Number, targetTimeline:MovieClip, targetLabel:String):Void {
        _state = "Waiting";
        _done = false;
        _timeoutMs = timeoutMs;
        _startMs = getTimer();
        _targetTimeline = targetTimeline;
        _targetLabel = targetLabel;

        try {
            var parent:MovieClip = _root;
            if (parent != null && parent.createEmptyMovieClip != null) {
                _tickMc = parent.createEmptyMovieClip("__bootstrapWaitTick", parent.getNextHighestDepth());
                _tickMc.onEnterFrame = function() {
                    org.flashNight.neur.Server.BootstrapWait._tickForTest();
                };
            }
        } catch (e:Error) {}
    }

    /** 每帧 tick: 轮询存档恢复状态 / 检测超时. 测试中可外部触发. */
    public static function _tickForTest():Void {
        if (_done) return;
        if (getTimer() - _startMs >= _timeoutMs) {
            _done = true;
            _state = "Failed";
            cleanupTickMc();
            return;
        }
        var pending:Boolean = false;
        try {
            var fn:Function = _root["存档恢复等待中"];
            if (fn != null) pending = (fn() == true);
        } catch (e:Error) {}
        if (!pending) {
            _done = true;
            _state = "Success";
            // 顺序修复: 先复制本地引用 再 cleanup 最后 gotoAndPlay
            var tl:MovieClip = _targetTimeline;
            var lbl:String = _targetLabel;
            cleanupTickMc();
            if (tl != null && lbl != null) {
                try { tl.gotoAndPlay(lbl); } catch (e2:Error) {}
            }
        }
    }

    public static function _forceTimeoutForTest():Void {
        if (_done) return;
        _startMs = getTimer() - _timeoutMs - 1;
        _tickForTest();
    }

    private static function cleanupTickMc():Void {
        if (_tickMc != null) {
            try { _tickMc.onEnterFrame = null; _tickMc.removeMovieClip(); } catch (e:Error) {}
            _tickMc = null;
        }
    }

    public static function getState():String { return _state; }
    public static function isDone():Boolean { return _done; }
}
