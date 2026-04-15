/**
 * BootstrapHandshake - launcher bootstrap握手 (Phase 1b)
 *
 * 状态机: Idle -> Sending -> WaitResp -> (Success | Failed)
 * _done 锁存防止回调晚到后重复推进
 * invalid_response (success:true 但 savePath:undefined) -> failure("invalid_response")
 * 5s timeout fail-closed
 *
 * 测试 hook: _onResponseForTest / _triggerTimeoutForTest 绕过真实 socket
 */
class org.flashNight.neur.Server.BootstrapHandshake {

    private static var _state:String = "Idle";
    private static var _done:Boolean = false;
    private static var _attemptId:String = null;
    private static var _onSuccess:Function = null;
    private static var _onFailure:Function = null;
    private static var _timeoutId:Number = -1;
    private static var _sender:Function = null;  // function(attemptId, onResponse):Void

    public static function start(attemptId:String, onSuccess:Function, onFailure:Function):Void {
        _state = "Sending";
        _done = false;
        _attemptId = attemptId;
        _onSuccess = onSuccess;
        _onFailure = onFailure;

        try { _timeoutId = setTimeout(BootstrapHandshake.handleTimeout, 5000); } catch (e:Error) {}

        // ServerManager 调用由外层包装代码注入 (BootstrapHandshake 不直接引用 ServerManager,
        // 避免 class-as-value 在 AS2 的运行期解析开销/碎片)
        _state = "WaitResp";
        if (_sender != null) {
            try { _sender(attemptId, BootstrapHandshake.handleResponse); } catch (e2:Error) {}
        }
    }

    /** 外部注入真实 socket 发送逻辑. null = 不发送 (测试 / 无 socket). */
    public static function setSender(fn:Function):Void {
        _sender = fn;
    }

    public static function handleResponse(resp:Object):Void {
        if (_done) return;
        if (resp == null) { handleFailure("null_response"); return; }
        if (resp.success != true) {
            var err:String = (resp.error != null) ? String(resp.error) : "failed";
            handleFailure(err);
            return;
        }
        if (resp.savePath == undefined || resp.savePath == null || String(resp.savePath).length == 0) {
            handleFailure("invalid_response");
            return;
        }
        _done = true;
        _state = "Success";
        cancelTimeout();
        if (_onSuccess != null) _onSuccess(resp);
    }

    public static function handleTimeout():Void {
        if (_done) return;
        handleFailure("timeout");
    }

    private static function handleFailure(reason:String):Void {
        if (_done) return;
        _done = true;
        _state = "Failed";
        cancelTimeout();
        if (_onFailure != null) _onFailure(reason);
    }

    private static function cancelTimeout():Void {
        if (_timeoutId >= 0) {
            try { clearTimeout(_timeoutId); } catch (e:Error) {}
            _timeoutId = -1;
        }
    }

    public static function _onResponseForTest(resp:Object):Void { handleResponse(resp); }
    public static function _triggerTimeoutForTest():Void { handleTimeout(); }

    public static function getState():String { return _state; }
    public static function isDone():Boolean { return _done; }
}
