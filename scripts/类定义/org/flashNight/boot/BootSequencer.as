// ⚠⚠ DRAFT — 未经 Flash CS6 编译 / 真机验证。2026-06-16 自主生成的 P4 起点（未被任何处 #include/引用，不影响现有构建）。
// 权威契约: docs/asLoader-BootSequencer-构建标准-2026-06-16.md
// 未验证假设（编译期/真机必查）:
//  1. L42 陷阱: 本类被引用时引用方需显式 import org.flashNight.boot.BootSequencer。
//  2. _root.__boot 由折叠后的单帧 staged 函数预先填充(s0_init/s1_syncCode/s5_parseTask/s6_syncSystems/
//     s7_syncLogic/s8_fanout/s9_onCrafting + 标志位)。本类只编排，不 #include（避开 import-in-method）。
//  3. 主 FLA 改动 A: MAIN f33 (DOMDocument.xml:1271) _root.asLoader.play() → _root.__boot.mainReadyToContinue=true。
//  4. 异步 loader 回调与 tick clip 均挂 _root，保证 asLoader 自删(S_HANDOFF)后仍存活。
//  5. 握手逻辑移植自 asLoader.xml f4(socket 10s / handshake 60s / 存档恢复 gate)；失败=不前进(匹配原版 hang)。
//  6. S6 串行序列必须含「最终化2」(原 f26 land-frame，易漏)。

import org.flashNight.gesh.json.LoadJson.TaskDataLoader;
import org.flashNight.gesh.json.LoadJson.TaskTextLoader;
import org.flashNight.gesh.json.LoadJson.CraftingListLoader;

class org.flashNight.boot.BootSequencer {
    static var S_INIT:Number = 0;
    static var S_SYNCCODE:Number = 1;
    static var S_HANDSHAKE:Number = 2;
    static var S_TASKDATA:Number = 3;
    static var S_TASKTEXT:Number = 4;
    static var S_PARSE:Number = 5;
    static var S_SYNCSYS:Number = 6;
    static var S_SYNCLOGIC:Number = 7;
    static var S_FANOUT:Number = 8;
    static var S_CRAFTING:Number = 9;
    static var S_HANDOFF:Number = 10;
    static var S_HALT:Number = -1;

    static var _instance:BootSequencer;

    var host:MovieClip;     // asLoader 实例
    var b:Object;           // _root.__boot — staged 函数 + 标志位容器
    var tickClip:MovieClip; // _root 挂载的驱动 clip
    var state:Number;
    var hsPhase:Number;     // S_HANDSHAKE 子相位: 1=socket 2=handshake 3=wait-main-resume
    var hsStart:Number;     // socket 等待起始 getTimer()

    // 幂等入口（防单帧 loop 回绕重入）
    static function run(host:MovieClip):Void {
        if (_instance != undefined) return;
        _instance = new BootSequencer(host);
        _instance.start();
    }

    function BootSequencer(host:MovieClip) {
        this.host = host;
        if (_root.__boot == undefined) _root.__boot = {};
        this.b = _root.__boot;
        this.state = S_INIT;
        this.hsPhase = 0;
    }

    function start():Void {
        this.host._lockroot = false;
        var self:BootSequencer = this;
        // tick 挂 _root（仿 DataQueryService.whenAvailable 存活模式），asLoader 自删后回调仍可达
        this.tickClip = _root.createEmptyMovieClip("__bootSeqTick", _root.getNextHighestDepth());
        this.tickClip.onEnterFrame = function():Void { self.step(); };
    }

    function step():Void {
        switch (this.state) {
            case S_INIT:      this.b.s0_init();        this.state = S_SYNCCODE;  break;
            case S_SYNCCODE:  this.b.s1_syncCode();    this.state = S_HANDSHAKE; this.hsPhase = 1; this.hsStart = getTimer(); break;
            case S_HANDSHAKE: this.stepHandshake();    break;
            case S_TASKDATA:  this.stepTaskData();     break;
            case S_TASKTEXT:  this.stepTaskText();     break;
            case S_PARSE:     this.b.s5_parseTask();   this.state = S_SYNCSYS;   break;
            case S_SYNCSYS:   this.b.s6_syncSystems(); this.state = S_SYNCLOGIC; break;
            case S_SYNCLOGIC: this.b.s7_syncLogic();   this.state = S_FANOUT;    break;
            case S_FANOUT:    this.b.s8_fanout();      this.state = S_CRAFTING;  break;
            case S_CRAFTING:  this.stepCrafting();     break;
            case S_HANDOFF:   this.handoff();          break;
            case S_HALT:      break; // 停在加载画面（fail-closed）
        }
    }

    // === S2 握手（移植 asLoader.xml f4，三相位） ===
    function stepHandshake():Void {
        var sm:Object = _root._bootstrap;
        if (sm == undefined) { this.b.bootFailed = "shim_missing"; this.state = S_HALT; return; }

        if (this.hsPhase == 1) { // 阶段1: 等 socket
            if (getTimer() - this.hsStart > 10000) { _root._bootstrapFailed = "socket_connect_timeout"; this.state = S_HALT; return; }
            if (_root.server != undefined && _root.server.isSocketConnected) {
                _root._bootstrapHandshakeFired = true;
                sm.startHandshake();
                this.hsPhase = 2;
            }
            return;
        }
        if (this.hsPhase == 2) { // 阶段2: handshake → preload → 存档恢复 gate → ready → boot_check
            var hs:String = sm.handshakeStatus();
            if (hs == "Failed") { this.state = S_HALT; return; }
            if (hs != "Success") return;
            if (!_root._bootstrapPreloadFired) { _root._bootstrapPreloadFired = true; _root.读取本地存盘(); }
            if (_root.存档恢复等待中 != undefined && _root.存档恢复等待中() == true) return; // C2-β 自旋
            if (!_root._bootstrapReadySent) { _root._bootstrapReadySent = true; sm.sendReady(); }
            _root.gotoAndStop("boot_check"); // 驱动主 SWF 播放头
            this.b.mainReadyToContinue = false;
            this.hsPhase = 3;
            return;
        }
        if (this.hsPhase == 3) { // 阶段3: 等主 SWF 恢复信号（改动 A 替代 _root.asLoader.play()）
            if (this.b.mainReadyToContinue == true) this.state = S_TASKDATA;
            return;
        }
    }

    // === S3/S4/S9 异步 await（失败=不前进，匹配原版 hang） ===
    function stepTaskData():Void {
        if (this.b.taskDataFired != true) {
            this.b.taskDataFired = true;
            var self:BootSequencer = this;
            TaskDataLoader.getInstance().loadTaskData(
                function(data:Object):Void { self.host.rawTaskData = data; self.b.taskDataReady = true; },
                function():Void {});
        }
        if (this.b.taskDataReady == true) this.state = S_TASKTEXT;
    }

    function stepTaskText():Void {
        if (this.b.taskTextFired != true) {
            this.b.taskTextFired = true;
            var self:BootSequencer = this;
            TaskTextLoader.getInstance().loadTaskText(
                function(data:Object):Void { self.host.rawTextData = data; self.b.taskTextReady = true; },
                function():Void {});
        }
        if (this.b.taskTextReady == true) this.state = S_PARSE;
    }

    function stepCrafting():Void {
        if (this.b.craftFired != true) {
            this.b.craftFired = true;
            var self:BootSequencer = this;
            CraftingListLoader.getInstance().loadCraftingList(
                function(data:Object):Void { self.b.s9_onCrafting(data); self.b.craftReady = true; },
                function():Void {});
        }
        if (this.b.craftReady == true) this.state = S_HANDOFF;
    }

    // === S10 handoff（顺序铁律: _root.play() 必先于卸载） ===
    function handoff():Void {
        this.tickClip.onEnterFrame = null;
        _root.play();
        this.host.removeMovieClip();
        this.tickClip.removeMovieClip();
        this.state = S_HALT;
    }
}