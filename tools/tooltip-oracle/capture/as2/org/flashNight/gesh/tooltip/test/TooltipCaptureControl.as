/** Offline-only coordination. It never changes an item, content rule or expected value. */
class org.flashNight.gesh.tooltip.test.TooltipCaptureControl {
    private static var _url:String;
    private static var _runId:String = "";
    private static var _busy:Boolean = false;
    private static var _paused:Boolean = false;
    private static var _nonce:String = "";
    private static var _announced:String = "";
    private static var _nextPoll:Number = 0;

    public static function configure(url:String):Void {
        _url = url; _runId = ""; _busy = false; _paused = false;
        _nonce = ""; _announced = ""; _nextPoll = 0;
    }

    public static function poll(runId:String, nativeCount:Number, inputCount:Number):Boolean {
        if (!_url) return false;
        if (_runId != runId) {
            _runId = runId; _busy = false; _paused = false;
            _nonce = ""; _announced = ""; _nextPoll = 0;
        }
        if (!_busy && getTimer() >= _nextPoll) {
            _busy = true; _nextPoll = getTimer() + 200;
            var control:XML = new XML();
            control.ignoreWhite = true;
            control.onLoad = function(success:Boolean):Void {
                org.flashNight.gesh.tooltip.test.TooltipCaptureControl.receive(success,this);
            };
            if (!control.load(_url)) _busy = false;
        }
        if (_paused && _announced != _nonce) {
            _announced = _nonce;
            trace("TC_CAPTURE_PAUSED|" + _runId + "|" + _nonce
                + "|native=" + nativeCount + "|inputs=" + inputCount);
        }
        return _paused;
    }

    private static function receive(success:Boolean, control:XML):Void {
        _busy = false;
        if (!success || control.firstChild == null) return;
        var attributes:Object = control.firstChild.attributes;
        if (attributes.runId != _runId) return;
        var nonce:String = String(attributes.nonce);
        if (nonce.length != 32) return;
        for (var index:Number = 0; index < nonce.length; index++) {
            if ("0123456789abcdef".indexOf(nonce.charAt(index)) < 0) return;
        }
        if (attributes.state == "pause") {
            _nonce = nonce; _paused = true;
        } else if (attributes.state == "run" && nonce == _nonce) {
            _paused = false;
            trace("TC_CAPTURE_RESUMED|" + _runId + "|" + nonce);
        }
    }
}
