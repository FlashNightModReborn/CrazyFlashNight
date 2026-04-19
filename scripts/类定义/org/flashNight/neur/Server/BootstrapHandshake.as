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

    // Phase D Step D1: timeoutMs 可配置 (legacy 默认 5s; prewarm 路径由外层传 60s).
    // 真正被拉长的只是 "socket 已连接但 launcher 不回 handshake" 场景;
    // asLoader.xml 10s socket 未连上 fail-closed 不受影响.
    public static var DEFAULT_TIMEOUT_MS:Number = 5000;

    private static var _state:String = "Idle";
    private static var _done:Boolean = false;
    private static var _attemptId:String = null;
    private static var _onSuccess:Function = null;
    private static var _onFailure:Function = null;
    private static var _timeoutId:Number = -1;
    private static var _sender:Function = null;  // function(attemptId, onResponse):Void

    /**
     * 启动 bootstrap 握手.
     * @param timeoutMs 可选; 缺省/非法 (undefined/NaN/<=0) 回退 DEFAULT_TIMEOUT_MS.
     */
    public static function start(attemptId:String, onSuccess:Function, onFailure:Function, timeoutMs:Number):Void {
        if (timeoutMs == undefined || isNaN(timeoutMs) || timeoutMs <= 0) {
            timeoutMs = DEFAULT_TIMEOUT_MS;
        }
        _state = "Sending";
        _done = false;
        _attemptId = attemptId;
        _onSuccess = onSuccess;
        _onFailure = onFailure;

        try { _timeoutId = setTimeout(BootstrapHandshake.handleTimeout, timeoutMs); } catch (e:Error) {}

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
