// Phase 1b: bootstrap 握手 + preload wait → ready ack
// 诊断走 socket (Flash SA 剔除 trace): _root.server.sendServerMessage
function __bslog(msg) {
    if (_root.server != undefined) _root.server.sendServerMessage("[BootstrapAS] " + msg);
}

this.stop();
__bslog("frame4 entered, _bootstrap=" + (_root._bootstrap != undefined)
    + " server=" + (_root.server != undefined)
    + " connected=" + (_root.server != undefined ? _root.server.isSocketConnected : "n/a"));

if (_root._bootstrap == undefined) {
    打印加载内容("启动器通信 shim 缺失");
    __bslog("shim missing, stopped");
} else {
    // 分两阶段: 先等 socket 连上 (policy 握手完成), 再发 bootstrap_handshake
    // 整体 10s 超时; 超时走 fail-closed
    打印加载内容("等待启动器连接……");
    _root._bootstrapFrame4Start = getTimer();

    var __self = this;
    var __tickCount = 0;
    this.onEnterFrame = function():Void {
        __tickCount++;
        var __elapsed = getTimer() - _root._bootstrapFrame4Start;

        // 阶段 1: 等 socket 连上
        if (!_root._bootstrapHandshakeFired) {
            if (__elapsed > 10000) {
                __self.onEnterFrame = null;
                _root._bootstrapFailed = "socket_connect_timeout";
                __bslog("socket timeout after " + __elapsed + "ms, connected=" + _root.server.isSocketConnected);
                打印加载内容("启动器连接超时");
                return;
            }
            if (_root.server != undefined && _root.server.isSocketConnected) {
                _root._bootstrapHandshakeFired = true;
                打印加载内容("握手启动器……");
                __bslog("socket ready at tick=" + __tickCount + " elapsed=" + __elapsed + "ms, firing handshake");
                _root._bootstrap.startHandshake();
            } else {
                if (__tickCount <= 3 || __tickCount % 30 == 0) {
                    __bslog("waiting socket tick=" + __tickCount + " connected=" + (_root.server != undefined ? _root.server.isSocketConnected : "n/a"));
                }
                return;
            }
        }

        // 阶段 2: 等 handshake response
        var __hs = _root._bootstrap.handshakeStatus();
        if (__tickCount % 30 == 0) __bslog("tick=" + __tickCount + " hs=" + __hs);

        if (__hs == "Failed") {
            __self.onEnterFrame = null;
            __bslog("handshake FAILED = " + _root._bootstrap.handshakeFailReason());
            打印加载内容("启动器握手失败: " + _root._bootstrap.handshakeFailReason());
            return;
        }
        if (__hs != "Success") return;

        if (!_root._bootstrapPreloadFired) {
            _root._bootstrapPreloadFired = true;
            打印加载内容("读取存档数据……");
            __bslog("firing preload");
            _root.读取本地存盘();
        }
        if (_root.存档恢复等待中 != undefined && _root.存档恢复等待中() == true) return;

        __self.onEnterFrame = null;
        if (!_root._bootstrapReadySent) {
            _root._bootstrapReadySent = true;
            __bslog("sending ready ack");
            _root._bootstrap.sendReady();
        }
        __bslog("bootstrap complete, jumping boot_check");
        _root.gotoAndStop("boot_check");
    };
}
