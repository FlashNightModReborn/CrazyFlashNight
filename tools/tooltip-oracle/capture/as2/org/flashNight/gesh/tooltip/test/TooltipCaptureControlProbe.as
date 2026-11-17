class org.flashNight.gesh.tooltip.test.TooltipCaptureControlProbe {
    private static var _pump:MovieClip;
    private static var _seenPause:Boolean = false;
    private static var _ticks:Number = 0;
    public static function runAllTests():Void {
        org.flashNight.gesh.tooltip.test.TooltipCaptureControl.configure(String(_root.__captureControlUri));
        _seenPause = false; _ticks = 0;
        _pump = _root.createEmptyMovieClip("__captureControlProbe",_root.getNextHighestDepth());
        _pump.onEnterFrame = function():Void {
            org.flashNight.gesh.tooltip.test.TooltipCaptureControlProbe.step();
        };
    }
    private static function step():Void {
        if (org.flashNight.gesh.tooltip.test.TooltipCaptureControl.poll(
                String(_root.__captureProbeControlRunId),_ticks,_ticks)) {
            _seenPause = true;
            return;
        }
        _ticks++;
        trace("CAPTURE_CONTROL_TICK|" + _ticks);
        if (_seenPause) {
            delete _pump.onEnterFrame;
            trace("CAPTURE_CONTROL_PROBE|passed");
            trace("FocusedTestRunId tooltip-capture-control Complete: " + _root.__captureProbeFocusedRun);
            _pump.removeMovieClip();
        }
    }
}
