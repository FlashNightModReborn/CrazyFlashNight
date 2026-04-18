// Phase 1b: bootstrap 握手 + preload 等待 shim
// 主时间线 frame 62/63/64/65 只调 _root._bootstrap.xxx(), 不 import class.
// class 字节码打包在 asLoader.swf 里, 修改 class 只需重编 asLoader, 主 SWF 无感.
//
// 注意: asLoader 使用 #include 拼接多 .as 文件到同一作用域,
// 若其他 .as 已 import 同名 class, 此处 import 会触发"叶名称冲突",
// 因此直接用全限定名调用 org.flashNight.neur.Server.BootstrapHandshake / BootstrapWait.

_root._bootstrap = new Object();

// ===== handshake =====

_root._bootstrap.startHandshake = function():Void {
    if (org.flashNight.neur.Server.BootstrapHandshake.getState() != "Idle") return;

    if (_root._bootstrapAttemptId == undefined) {
        _root._bootstrapAttemptId = "attempt_" + getTimer();
    }
    _root._bootstrapSavePathReady = false;
    _root._bootstrapFailed = undefined;

    org.flashNight.neur.Server.BootstrapHandshake.setSender(function(attemptId:String, onResponse:Function):Void {
        var sm:Object = _root.server;
        if (sm != undefined && sm.isSocketConnected) {
            sm.sendTaskWithCallback("bootstrap_handshake",
                { attemptId: attemptId, hello: "from_flash" }, null, onResponse);
        }
    });

    org.flashNight.neur.Server.BootstrapHandshake.start(_root._bootstrapAttemptId,
        function(resp:Object):Void {
            _root.savePath = resp.savePath;
            // 覆盖用 launcher 权威 attemptId (guid); Flash 本地 id 只是握手前的占位
            if (resp.attemptId != undefined && resp.attemptId != null) {
                _root._bootstrapAttemptId = String(resp.attemptId);
            }
            // Protocol 2 (launcher 存档决议): 存到 _root._launcher* 一次性字段,
            // SaveManager.preload() 消费后立即 delete 并置幂等锁 _protocol2Consumed.
            if (resp.protocol >= 2 && resp.saveDecision != undefined) {
                _root._launcherSaveDecision = resp.saveDecision;
                _root._launcherSnapshot = resp.snapshot;
                _root._launcherSnapshotSource = resp.snapshotSource;
                _root._launcherCorruptDetail = resp.corruptDetail;
            }
            _root._bootstrapSavePathReady = true;
            if (_root.server != undefined) {
                _root.server.sendServerMessage("[Bootstrap] handshake OK savePath=" + resp.savePath + " attemptId=" + _root._bootstrapAttemptId + " protocol=" + resp.protocol + " decision=" + resp.saveDecision);
            }
        },
        function(reason:String):Void {
            _root._bootstrapFailed = reason;
            if (_root.server != undefined) {
                _root.server.sendServerMessage("[Bootstrap] handshake FAILED: " + reason);
            }
        });
};

// 返回 "Waiting" / "Success" / "Failed"
_root._bootstrap.handshakeStatus = function():String {
    if (_root._bootstrapFailed != undefined) return "Failed";
    if (_root._bootstrapSavePathReady == true) return "Success";
    return "Waiting";
};

_root._bootstrap.handshakeFailReason = function():String {
    return _root._bootstrapFailed;
};

// ===== preload wait =====

_root._bootstrap.startPreloadWait = function(timeline:MovieClip):Void {
    if (org.flashNight.neur.Server.BootstrapWait.getState() != "Idle") return;
    org.flashNight.neur.Server.BootstrapWait.startWait(5000, timeline, "bootstrap_ready_send");
};

// 返回 "Idle" / "Waiting" / "Success" / "Failed"
_root._bootstrap.preloadWaitStatus = function():String {
    return org.flashNight.neur.Server.BootstrapWait.getState();
};

// ===== ready ack =====

_root._bootstrap.sendReady = function():Void {
    var sm:Object = _root.server;
    var attemptId:String = _root._bootstrapAttemptId;
    if (sm != undefined && sm.isSocketConnected) {
        // ServerManager 无 sendTask 方法; sendTaskToNode 是 fire-and-forget, 适合 ack 语义
        var ok:Boolean = sm.sendTaskToNode("bootstrap_ready", { attemptId: attemptId }, null);
        sm.sendServerMessage("[Bootstrap] sent bootstrap_ready attemptId=" + attemptId + " ok=" + ok);
    } else if (sm != undefined) {
        // socket 不可用, 但 ServerManager 尚在: 记 log buffer (下次 flush 失败也无害)
        sm.sendServerMessage("[Bootstrap] WARN: socket disconnected, skip ready ack");
    }
    // sm == undefined 时静默: 没任何可用日志通道, 继续流程不阻断时间线
};
