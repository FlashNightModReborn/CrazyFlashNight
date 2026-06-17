import org.flashNight.boot.BootSequencer;

/**
 * BootSequencer 逻辑回归套件（L1 — TestLoader 单元测试，见 docs/asLoader-BootSequencer-构建标准 §5.3）。
 * mock host/_root._bootstrap/_root.server/_root.__boot staged 函数/存档恢复等待中，直接 new + 手动驱 step()。
 * ⚠ 仅状态机逻辑层：真 socket 连接 / 佣兵满编 / 跨 SWF 生命周期 / 存档三分支须真机（L3）。
 * 失败用 [TEST_FAIL] 哨兵（compile_test.ps1 据此 exit 1）。
 */
class org.flashNight.boot.BootSequencerTest {
    private var _pass:Number;
    private var _fail:Number;
    // 下三者由 mock 闭包经捕获的 t.xxx 写入（AS2 闭包委托惯语），用非 private 杜绝任何 private-from-closure 访问疑虑
    public var _serverMsgs:Array;    // _root.server.sendServerMessage 收集
    public var _printed:Array;       // host.打印加载内容 收集
    public var _calls:Object;        // 桩调用计数

    public function BootSequencerTest() {
        this._pass = 0;
        this._fail = 0;
    }

    public function runTests():Void {
        trace("=== BootSequencerTest start ===");
        this.test_shimMissing_halts();
        this.test_socketTimeout_halts();
        this.test_socketReady_firesHandshake();
        this.test_handshakeFailed_halts();
        this.test_repairGate_spinsThenReleases();
        this.test_crafting_emitsEvent();
        this.test_handoff_emitsEvent();
        this.test_run_idempotent();
        this.test_s6_waitGateThenDrain();
        this.test_s6_ceilingRelease();
        this.printSummary();
        // 清理 _root 上对内置方法的影子覆盖（其余 mock 全局留着无害，TestLoader 非真游戏）
        delete _root.play;
        delete _root.gotoAndStop;
        trace("=== BootSequencerTest end ===");
    }

    // ====== 夹具：重建 BootSequencer 依赖的全部 mock，返回 mock host ======
    private function freshEnv() {   // 返回 untyped：mock host 传入 host:MovieClip 形参时绕开 AS2 实参类型检查
        var t:BootSequencerTest = this;
        this._serverMsgs = [];
        this._printed = [];
        this._calls = {};

        _root.server = {
            isSocketConnected: false,
            sendServerMessage: function(msg) { t._serverMsgs.push(msg); }
        };
        _root._bootstrap = {
            _hs: "Pending",
            _failReason: "",
            startHandshake: function() { t._calls.startHandshake = t.inc(t._calls.startHandshake); },
            handshakeStatus: function() { return this._hs; },
            handshakeFailReason: function() { return this._failReason; },
            sendReady: function() { t._calls.sendReady = t.inc(t._calls.sendReady); }
        };
        _root._bootstrapPreloadFired = false;
        _root._bootstrapReadySent = false;
        _root._bootstrapHandshakeFired = false;
        _root._repairWaiting = false;
        _root.读取本地存盘 = function() { t._calls.读取本地存盘 = t.inc(t._calls.读取本地存盘); };
        _root.存档恢复等待中 = function() { return _root._repairWaiting == true; };
        _root.发布消息 = function(m) {};
        _root.gotoAndStop = function(s) { t._calls.gotoAndStop = s; };
        _root.play = function() { t._calls.rootPlay = t.inc(t._calls.rootPlay); };

        // staged 函数桩（仅记录；构造函数见 _root.__boot != undefined 即直接用本对象）
        _root.__boot = {
            s0_init: function() { t._calls.s0 = t.inc(t._calls.s0); },
            s1_syncCode: function() { t._calls.s1 = t.inc(t._calls.s1); },
            s5_parseTask: function(host) { t._calls.s5 = t.inc(t._calls.s5); },
            s6_pre: function() { t._calls.s6pre = t.inc(t._calls.s6pre); },
            s6_post: function() { t._calls.s6post = t.inc(t._calls.s6post); },
            s7_syncLogic: function() { t._calls.s7 = t.inc(t._calls.s7); },
            s8_fanout: function() { t._calls.s8 = t.inc(t._calls.s8); },
            s9_onCrafting: function(data) { t._calls.s9 = t.inc(t._calls.s9); }
        };

        BootSequencer._instance = undefined;   // 复位重入保护

        return {
            打印加载内容: function(s) { t._printed.push(s); },
            removeMovieClip: function() { t._calls.hostRemoved = t.inc(t._calls.hostRemoved); }
        };
    }

    public function inc(n:Number):Number { return (n == undefined ? 0 : n) + 1; }   // 经 t.inc() 由闭包调用

    // 驱 S_INIT + S_SYNCCODE → 停在 S_HANDSHAKE 子相位 1
    private function driveToHsP1(inst:BootSequencer):Void {
        inst.step();   // S_INIT → s0_init, → S_SYNCCODE
        inst.step();   // S_SYNCCODE → s1_syncCode, → S_HANDSHAKE hsPhase=1
    }

    // ====== 边界 (c)：shim 缺失 → HALT shim_missing ======
    private function test_shimMissing_halts():Void {
        var host = this.freshEnv();
        _root._bootstrap = undefined;            // 抹掉 shim
        var inst:BootSequencer = new BootSequencer(host);
        this.driveToHsP1(inst);
        inst.step();                             // S_HANDSHAKE: sm==undefined → halt
        this.assert(inst.state == BootSequencer.S_HALT, "(c) shim 缺失 → state=HALT");
        this.assert(inst.b.bootFailed == "shim_missing", "(c) bootFailed=shim_missing");
        this.assert(this.msgHas("shim missing"), "(c) [BootstrapAS] shim missing 日志");
        this.assert(this.printedHas("shim 缺失"), "(c) 玩家文案 启动器通信 shim 缺失");
    }

    // ====== 边界 (b)：socket 10s 超时 → HALT ======
    private function test_socketTimeout_halts():Void {
        var host = this.freshEnv();
        _root.server.isSocketConnected = false;
        var inst:BootSequencer = new BootSequencer(host);
        this.driveToHsP1(inst);
        inst.hsStart = getTimer() - 11000;       // 伪造已等 >10s
        inst.step();                             // phase1: elapsed>10000 → halt
        this.assert(inst.state == BootSequencer.S_HALT, "(b) socket 超时 → state=HALT");
        this.assert(inst.b.bootFailed == "socket_connect_timeout", "(b) bootFailed=socket_connect_timeout");
        this.assert(this.msgHas("socket timeout"), "(b) [BootstrapAS] socket timeout 日志");
        this.assert(this.printedHas("连接超时"), "(b) 玩家文案 启动器连接超时");
    }

    // ====== socket 连上 → 触发握手, 进 phase 2 ======
    private function test_socketReady_firesHandshake():Void {
        var host = this.freshEnv();
        _root.server.isSocketConnected = true;
        var inst:BootSequencer = new BootSequencer(host);
        this.driveToHsP1(inst);
        inst.step();                             // phase1: socket ready → startHandshake, hsPhase=2
        this.assert(inst.hsPhase == 2, "socket ready → hsPhase=2");
        this.assert(this._calls.startHandshake == 1, "socket ready → startHandshake() 一次");
        this.assert(_root._bootstrapHandshakeFired == true, "socket ready → _bootstrapHandshakeFired");
        this.assert(this.msgHas("firing handshake"), "[BootstrapAS] firing handshake");
    }

    // ====== 边界（握手失败）：hs=Failed → HALT ======
    private function test_handshakeFailed_halts():Void {
        var host = this.freshEnv();
        _root.server.isSocketConnected = true;
        var inst:BootSequencer = new BootSequencer(host);
        this.driveToHsP1(inst);
        inst.step();                             // → hsPhase=2
        _root._bootstrap._hs = "Failed";
        _root._bootstrap._failReason = "boom";
        inst.step();                             // phase2: Failed → halt
        this.assert(inst.state == BootSequencer.S_HALT, "握手失败 → state=HALT");
        this.assert(inst.b.bootFailed == "handshake_failed", "握手失败 → bootFailed=handshake_failed");
        this.assert(this.msgHas("handshake FAILED"), "握手失败 [BootstrapAS] 日志含因 boom");
    }

    // ====== 边界 (a)：存档恢复 gate 自旋 → 放行 ======
    private function test_repairGate_spinsThenReleases():Void {
        var host = this.freshEnv();
        _root.server.isSocketConnected = true;
        _root._repairWaiting = true;             // 修复在途
        var inst:BootSequencer = new BootSequencer(host);
        this.driveToHsP1(inst);
        inst.step();                             // → hsPhase=2
        _root._bootstrap._hs = "Success";
        inst.step();                             // phase2: preload fire, 但 gate=true → 自旋
        this.assert(this._calls.读取本地存盘 == 1, "(a) gate: 读取本地存盘() 触发一次");
        this.assert(this._calls.sendReady == undefined, "(a) gate 自旋时未 sendReady");
        this.assert(inst.state == BootSequencer.S_HANDSHAKE && inst.hsPhase == 2, "(a) gate=true → 留在 phase2 自旋");
        inst.step();                             // 仍自旋（再证不重复 preload）
        this.assert(this._calls.读取本地存盘 == 1, "(a) 自旋不重复 preload（_bootstrapPreloadFired 幂等）");
        _root._repairWaiting = false;            // 修复落地
        inst.step();                             // gate 放行 → sendReady + boot_check
        this.assert(this._calls.sendReady == 1, "(a) gate 放行 → sendReady 一次");
        this.assert(this._calls.gotoAndStop == "boot_check", "(a) gate 放行 → gotoAndStop(boot_check)");
        this.assert(inst.hsPhase == 3, "(a) gate 放行 → hsPhase=3 等主 SWF resume");
    }

    // ====== Finding 1：S9 成功发 CRAFTING_OK ======
    private function test_crafting_emitsEvent():Void {
        var host = this.freshEnv();
        var inst:BootSequencer = new BootSequencer(host);
        inst.state = BootSequencer.S_CRAFTING;
        // 把真单例的 loadCraftingList 换成同步成功桩；用后**还原**，避免污染后续 suite / 真游戏复用该单例（顺序无关）。
        var loader:Object = org.flashNight.gesh.json.LoadJson.CraftingListLoader.getInstance();
        var origLoad = loader.loadCraftingList;
        loader.loadCraftingList = function(ok, fail) { ok({}); };
        inst.step();                             // stepCrafting → 同步 ok → s9_onCrafting + bslog + craftReady → S_HANDOFF
        loader.loadCraftingList = origLoad;      // 还原真方法
        this.assert(this._calls.s9 == 1, "(S9) s9_onCrafting 调用一次");
        this.assert(this.msgHas("合成表数据加载完毕"), "(S9) 成功 cb 发 CRAFTING_OK（合成表数据加载完毕）");
        this.assert(inst.state == BootSequencer.S_HANDOFF, "(S9) craftReady → S_HANDOFF");
    }

    // ====== Finding 1：S10 handoff 发 HANDOFF_PLAY ======
    private function test_handoff_emitsEvent():Void {
        var host = this.freshEnv();
        var inst:BootSequencer = new BootSequencer(host);
        inst.state = BootSequencer.S_HANDOFF;
        inst.step();                             // handoff()（tickClip 判空已加，不经 start() 不崩）
        this.assert(this.msgHas("event=handoff"), "(S10) handoff 发 HANDOFF_PLAY（event=handoff）");
        this.assert(this._calls.rootPlay == 1, "(S10) _root.play() 先于卸载");
        this.assert(this._calls.hostRemoved == 1, "(S10) host.removeMovieClip()");
        this.assert(inst.state == BootSequencer.S_HALT, "(S10) handoff → state=HALT");
        this.assert(BootSequencer._instance == undefined, "(S10) 释放 _instance（同会话可重挂）");
    }

    // ====== 边界 (g)：run() 幂等（已存在实例不重建） ======
    private function test_run_idempotent():Void {
        var host = this.freshEnv();
        var sentinel:BootSequencer = new BootSequencer(host);   // 不 start()，无 tick
        BootSequencer._instance = sentinel;
        BootSequencer.run(host);                                // guard: _instance != undefined → return
        this.assert(BootSequencer._instance == sentinel, "(g) run() 幂等：已存在实例时不重建");
        BootSequencer._instance = undefined;
    }

    // ====== 边界 (e) 逻辑：S6 等待门（含首层 list.xml 慢加载 race 防护）→ 逐 tick 抽干 → s6_post ======
    // 覆盖 sawPending 修复：pending==0 二义（全加载完 vs 二级加载尚未起飞）→ 仅当曾观测到 pending>0 才放行，
    //   否则即使过了 30 帧也继续等（防慢 list.xml 提前抽空 loader → 佣兵/兵种/商城/商店数据缺载）。
    private function test_s6_waitGateThenDrain():Void {
        var host = this.freshEnv();
        var inst:BootSequencer = new BootSequencer(host);
        inst.state = BootSequencer.S_SYNCSYS;
        var drained:Array = [];
        var q:Array = [];
        q.current = 0;
        q.push(function() { drained.push(1); });
        q.push(function() { drained.push(2); });
        _root.loaders = q;
        _root.__pendingFileLoads = 0;            // 首层 list.xml 加载中，二级 GetFileByPath 尚未起飞

        inst.step();                             // sysPhase0: s6_pre → sysPhase=1, sysWait=0
        this.assert(inst.sysPhase == 1 && this._calls.s6pre == 1, "(e) S6 phase0 跑 s6_pre");

        var i:Number = 0;
        while (i < 40) { inst.step(); i++; }     // 40 帧 pending 持续 0（list.xml 慢） → 不应放行（从未观测到 pending>0）
        this.assert(inst.sysPhase == 1 && drained.length == 0, "(e/race) 首层慢加载: pending 久=0 且未起飞过 → 过 30 帧仍不抽 loader");
        this.assert(inst.sawPending != true, "(e/race) 未观测到 pending>0 → sawPending=false");

        _root.__pendingFileLoads = 2;            // 二级文件加载起飞
        inst.step();
        this.assert(inst.sysPhase == 1 && inst.sawPending == true, "(e) 观测到 pending>0 → sawPending；在途不放行");
        inst.step();
        this.assert(inst.sysPhase == 1, "(e) pending 仍>0 → 继续等");

        _root.__pendingFileLoads = 0;            // 二级加载全部落地
        inst.step();                             // sawPending && sysWait>=30 && pending==0 → sysPhase=2
        this.assert(inst.sysPhase == 2, "(e) 加载落地(pending=0) + 曾起飞 → 进抽干相位");

        inst.step();                             // 抽 loaders[0]
        inst.step();                             // 抽 loaders[1]
        this.assert(drained.length == 2 && drained[0] == 1 && drained[1] == 2, "(e) 逐 tick 保序抽干");
        inst.step();                             // current>=length → s6_post + S_SYNCLOGIC
        this.assert(this._calls.s6post == 1 && inst.state == BootSequencer.S_SYNCLOGIC, "(e) 队空 → s6_post + 推进");
    }

    // ====== 边界 (e) 兜底：无二级加载时 150 帧上限放行（防 sawPending 永 false 致永久挂起） ======
    private function test_s6_ceilingRelease():Void {
        var host = this.freshEnv();
        var inst:BootSequencer = new BootSequencer(host);
        inst.state = BootSequencer.S_SYNCSYS;
        var q:Array = [];
        q.current = 0;                           // 空 loader 队列：放行后立即 s6_post
        _root.loaders = q;
        _root.__pendingFileLoads = 0;            // 全程无二级加载 → sawPending 永 false

        inst.step();                             // sysPhase0: s6_pre → sysPhase=1, sysWait=0
        var i:Number = 0;
        while (i < 148) { inst.step(); i++; }     // phase1 推进 sysWait 1..148（均 <150 且 sawPending=false → 不放行）
        this.assert(inst.sysPhase == 1 && inst.sawPending != true, "(e/ceiling) 无二级加载 <150 帧不放行");
        inst.step();                             // sysWait=149 <150 → 仍等
        this.assert(inst.sysPhase == 1, "(e/ceiling) 149 帧仍等");
        inst.step();                             // sysWait=150 → 兜底放行（防永久挂起）
        this.assert(inst.sysPhase == 2, "(e/ceiling) 150 帧兜底放行 → 进抽干相位");
        inst.step();                             // 空队列 current>=length → s6_post + S_SYNCLOGIC
        this.assert(this._calls.s6post == 1 && inst.state == BootSequencer.S_SYNCLOGIC, "(e/ceiling) 队空 → s6_post + 推进");
    }

    // ====== 工具 ======
    private function msgHas(sub:String):Boolean {
        for (var i:Number = 0; i < this._serverMsgs.length; i++)
            if (String(this._serverMsgs[i]).indexOf(sub) >= 0) return true;
        return false;
    }
    private function printedHas(sub:String):Boolean {
        for (var i:Number = 0; i < this._printed.length; i++)
            if (String(this._printed[i]).indexOf(sub) >= 0) return true;
        return false;
    }
    private function assert(cond:Boolean, msg:String):Void {
        if (cond) { this._pass++; trace("[PASS] " + msg); }
        else { this._fail++; trace("[TEST_FAIL] " + msg); }
    }
    private function printSummary():Void {
        trace("=== BootSequencerTest: " + this._pass + " passed, " + this._fail + " failed ===");
        if (this._fail > 0) trace("[TEST_FAIL] BootSequencerTest " + this._fail + " 项失败");
    }
}
