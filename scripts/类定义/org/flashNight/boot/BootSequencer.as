// 2026-06-16 P4 起点；2026-07-25 当前由 _collapsed_frame.as 显式 import + BootSequencer.run(this) 驱动。
// happy-path、完整 S2→S10 trace、shim/握手/存档/S6/生命周期与单帧防重入已有分层证据；
// 真 socket 10s 超时仍保留为低价值人工边界，详见构建标准 §5.3。
// 权威契约: docs/asLoader-BootSequencer-构建标准-2026-06-16.md
// 未验证假设（编译期/真机必查）:
//  1. L42 陷阱: 本类被引用时引用方需显式 import org.flashNight.boot.BootSequencer。
//  2. _root.__boot 由折叠后的单帧 staged 函数预先填充(s1_syncCode/s6_pre/s6_post/
//     s7_syncLogic/s7_miscLoaders/s8_fanout + 标志位)。S0/S5/S9 业务归本类，不 #include（避开 import-in-method）。
//     ⚠ S6 拆 s6_pre(f9 建 _root.loaders + f10 兼容×4 push 入队 + f18 最终化1 跑 _root.preloaders)
//        / s6_post(f32 最终化3 跑 _root.loaderkillers + 删三队列)；中间 _root.loaders 由本类 stepSyncSys
//        每 tick 抽 1 个（复刻 f26 最终化2 的 onEnterFrame 时间切片，prevent 单帧抽干卡顿）。
//  3. 主 FLA 改动 A: MAIN f33 (DOMFrame index=33) _root.asLoader.play() → _root.__boot.mainReadyToContinue=true。
//  4. 异步 loader 回调与 tick clip 均挂 _root，保证 asLoader 自删(S_HANDOFF)后仍存活。
//  5. 握手逻辑移植自 asLoader.xml f4(socket 10s / handshake 60s / 存档恢复 gate)；失败=halt() fail-closed(主 SWF 不前进=匹配原版 hang)+恢复 f4 的 host.打印加载内容 玩家文案 + [BootstrapAS] socket 日志(便于边界 smoke 定位卡死点)。
//  6. S6 串行序列必须含「最终化2」(原 f26 land-frame，易漏)。

import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;
import org.flashNight.arki.item.ChoiceRewardDefinition;
import org.flashNight.gesh.json.LoadJson.TaskDataLoader;
import org.flashNight.gesh.json.LoadJson.TaskTextLoader;
import org.flashNight.gesh.json.LoadJson.CraftingListLoader;
import org.flashNight.gesh.xml.LoadXml.MaterialCatalogLoader;
import org.flashNight.gesh.xml.LoadXml.ArenaDropRulesLoader;
import org.flashNight.gesh.xml.LoadXml.LightProfilesLoader;

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
    var sysPhase:Number;    // S_SYNCSYS 子相位: 0=pre 1=等异步preload落地 2=逐tick抽干 _root.loaders
    private var phaseStarted:Number;
    private var phaseWall:Array;
    private var phaseWork:Array;
    private var workMax:Array;
    private var systemWaitStarted:Number;
    private var systemWaitMs:Number;
    private var systemLoadWork:Array;
    private var syncLogicMs:Number;
    private var miscStartMs:Number;
    private var itemIndexMs:Number;
    private var acquireIndexMs:Number;
    var sysWait:Number;     // S_SYNCSYS 相位1 等待计帧（等 GetFileByPath/LoadVars 异步加载落地）
    var sawPending:Boolean; // S_SYNCSYS 相位1: 是否曾观测到 __pendingFileLoads>0（二级文件加载已起飞）——
                            //   防「首层 list.xml 慢加载、GetFileByPath 尚未起飞」时 pending==0 被误判为「已加载完」提前放行

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
        this.sysPhase = 0;
        this.sysWait = 0;
        this.sawPending = false;
        this.phaseWall = [];
        this.phaseWork = [];
        this.workMax = [];
        this.systemLoadWork = [];
        // Bounds the evidence retained during startup; the boot object disappears at handoff.
        this.b.slowLoads = [];
        this.b.recordLoad = function(path:String, parseMs:Number, handlerMs:Number):Void {
            var total:Number = parseMs + handlerMs;
            this.totalParseMs += parseMs;
            this.totalHandlerMs += handlerMs;
            if (total < 25) return;
            var at:Number = 0;
            while (at < this.slowLoads.length && this.slowLoads[at].total >= total) at++;
            if (at < 12) {
                this.slowLoads.splice(at, 0, {total:total, name:path.substr(path.lastIndexOf("/") + 1),
                    parse:parseMs, handler:handlerMs});
                if (this.slowLoads.length > 12) this.slowLoads.pop();
            }
        };
        this.b.totalParseMs = 0;
        this.b.totalHandlerMs = 0;
        for (var phase:Number = S_TASKDATA; phase <= S_CRAFTING; phase++) {
            this.phaseWork[phase - S_TASKDATA] = 0;
            this.workMax[phase - S_TASKDATA] = 0;
        }
    }

    function start():Void {
        // Bind resource location from the live host before singleton initialization.
        org.flashNight.gesh.path.PathManager.initialize(this.host._url);
        var self:BootSequencer = this;
        // tick 挂 _root（仿 DataQueryService.whenAvailable 存活模式），asLoader 自删后回调仍可达
        this.tickClip = _root.createEmptyMovieClip("__bootSeqTick", _root.getNextHighestDepth());
        this.tickClip.onEnterFrame = function():Void { self.step(); };
    }

    function step():Void {
        var previous:Number = this.state;
        var started:Number = getTimer();
        switch (this.state) {
            case S_INIT:      org.flashNight.gesh.init.GlobalInitializer.initialize(); this.state = S_SYNCCODE; break;
            case S_SYNCCODE:  this.b.s1_syncCode();    this.state = S_HANDSHAKE; this.hsPhase = 1; this.hsStart = getTimer(); this.bslog("handshake stage entered, _bootstrap=" + (_root._bootstrap != undefined) + " server=" + (_root.server != undefined)); break;
            case S_HANDSHAKE: this.stepHandshake();    break;
            case S_TASKDATA:  this.stepTaskData();     break;
            case S_TASKTEXT:  this.stepTaskText();     break;
            case S_PARSE:     this.parseTaskAndStartGuide(); this.state = S_SYNCSYS; break;
            case S_SYNCSYS:   this.stepSyncSys();      break;
            case S_SYNCLOGIC: this.stepSyncLogic();    break;
            case S_FANOUT:    this.b.s8_fanout();      this.state = S_CRAFTING;  break;
            case S_CRAFTING:  this.stepCrafting();     break;
            case S_HANDOFF:   this.handoff();          break;
            case S_HALT:      break; // 停在加载画面（fail-closed）
        }
        if (previous >= S_HANDSHAKE && previous <= S_CRAFTING) this.recordStep(previous, started);
    }

    // Wall includes inter-frame callbacks. Work is only synchronous time inside step().
    private function recordStep(previous:Number, started:Number):Void {
        var now:Number = getTimer();
        if (previous >= S_TASKDATA && previous <= S_CRAFTING) {
            var index:Number = previous - S_TASKDATA;
            var elapsed:Number = now - started;
            this.phaseWork[index] += elapsed;
            if (elapsed > this.workMax[index]) this.workMax[index] = elapsed;
            if (this.state != previous) this.phaseWall[index] = now - this.phaseStarted;
        }
        if (this.state != previous) this.phaseStarted = now;
    }

    // === 诊断 + 终止辅助 ===
    // 移植 f4 的 __bslog：socket 诊断日志（Flash SA 剔 trace），走 _root.server.sendServerMessage，
    // 对齐 trace-diff golden 的 [BootstrapAS] 词汇（§5 trace 等价门）。
    function bslog(msg:String):Void {
        if (_root.server != undefined) _root.server.sendServerMessage("[BootstrapAS] " + msg);
    }

    // fail-closed 终止：记原因 + [BootstrapAS] 日志 + 停 tick + 释放单例重入保护。
    // 释放 _instance 是关键：否则同一 AVM1 会话重挂/重试 asLoader 时 run() 因 _instance 残留直接 return，
    // 新建的 _root.__boot 没有 tick 驱动 → boot 停在握手后的主时间轴信号附近（与 handoff 同源问题）。
    function halt(reason:String):Void {
        this.b.bootFailed = reason;
        this.bslog("HALT: " + reason);
        this.state = S_HALT;
        // 对齐 handoff()：不仅停 tick 还回收 clip。否则同会话失败重试时 getNextHighestDepth() 升高、
        // createEmptyMovieClip 不替换旧同名 clip → 每次重试泄漏一个 inert 空 clip 占深度槽。
        // 从自身 onEnterFrame 内 removeMovieClip 安全（handoff 已用同一自卸载模式，BootSequencer 实例由闭包 self 持有，非 clip）。
        if (this.tickClip != undefined) { this.tickClip.onEnterFrame = null; this.tickClip.removeMovieClip(); }
        BootSequencer._instance = undefined;   // 显式限定静态：实例方法内不可裸写 _instance（恐解析为实例属性→重入保护未释放）
    }

    // === S2 握手（移植 asLoader.xml f4，三相位） ===
    // 失败路径恢复 f4 的 host.打印加载内容（玩家可见文案）+ [BootstrapAS] 日志（launcher.log 记失败原因），
    // 否则边界 smoke 只见旧加载文本 + 日志缺失，难判卡死点。
    function stepHandshake():Void {
        var sm:Object = _root._bootstrap;
        if (sm == undefined) {
            this.host.打印加载内容("启动器通信 shim 缺失");
            this.bslog("shim missing, stopped");
            this.halt("shim_missing");
            return;
        }

        if (this.hsPhase == 1) { // 阶段1: 等 socket
            var elapsed:Number = getTimer() - this.hsStart;
            if (elapsed > 10000) {
                _root._bootstrapFailed = "socket_connect_timeout";
                this.bslog("socket timeout after " + elapsed + "ms, connected=" + (_root.server != undefined ? _root.server.isSocketConnected : "n/a"));
                this.host.打印加载内容("启动器连接超时");   // bslog 先于打印加载内容，保持旧 f4 顺序
                this.halt("socket_connect_timeout");
                return;
            }
            if (_root.server != undefined && _root.server.isSocketConnected) {
                _root._bootstrapHandshakeFired = true;
                this.host.打印加载内容("握手启动器……");
                this.bslog("socket ready, firing handshake");
                sm.startHandshake();
                if (this.tickClip != undefined && this.b.catalogReads == undefined) {
                    this.b.catalogReads = {};
                    this.b.catalogDemand = {};
                    org.flashNight.aven.Promise.ListLoader.primeBootList(this.b, "data/task/", "task", "agent_tasks.json");
                    org.flashNight.aven.Promise.ListLoader.primeBootList(this.b, "data/task/text/", "text", "agent_text.json");
                    org.flashNight.arki.scene.BookDefinition.primeRoutes(this.b);
                }
                this.hsPhase = 2;
            }
            return;
        }
        if (this.hsPhase == 2) { // 阶段2: handshake → preload → 存档恢复 gate → ready → boot_check
            var hs:String = sm.handshakeStatus();
            if (hs == "Failed") {
                this.bslog("handshake FAILED = " + sm.handshakeFailReason());
                this.host.打印加载内容("启动器握手失败: " + sm.handshakeFailReason());
                this.halt("handshake_failed");
                return;
            }
            if (hs != "Success") return;
            if (!_root._bootstrapPreloadFired) {
                _root._bootstrapPreloadFired = true;
                this.bslog("handshake hs=Success");   // 握手成功沿记一次（旧 f4 经 tick 轮询日志 hs=Success；供 trace-diff HANDSHAKE_RESULT 等价）
                this.host.打印加载内容("读取存档数据……");
                this.bslog("firing preload");
                _root.读取本地存盘();
            }
            if (_root.存档恢复等待中 != undefined && _root.存档恢复等待中() == true) return; // C2-β 自旋
            if (!_root._bootstrapReadySent) {
                _root._bootstrapReadySent = true;
                this.bslog("sending ready ack");
                sm.sendReady();
            }
            this.bslog("bootstrap complete, jumping boot_check");
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

    // The bookshelf starts BookDefinition loads during S7; its economy rules
    // already consume this catalog. Do not defer this barrier to S9.
    function stepSyncLogic():Void {
        if (!ChoiceRewardDefinition.ready()) {
            if (this.b.choiceRewardsFired != true) {
                this.b.choiceRewardsFired = true;
                var self:BootSequencer = this;
                var loader:BaseJSONLoader = new BaseJSONLoader("data/rewards/choice-rewards.runtime.json", "CatalogJSON");
                loader.load(function(data:Object):Void {
                    if (self.state != BootSequencer.S_SYNCLOGIC) return;
                    if (!ChoiceRewardDefinition.accept(data)) {
                        self.host.打印加载内容("配给目录格式错误");
                        self.halt("choice_rewards_failed");
                    }
                }, function(error:String):Void {
                    if (self.state != BootSequencer.S_SYNCLOGIC) return;
                    self.host.打印加载内容("配给目录加载失败");
                    self.halt("choice_rewards_failed");
                });
            }
            if (this.state == S_HALT || !ChoiceRewardDefinition.ready()) return;
        }
        var codeStarted:Number = getTimer();
        this.b.s7_syncLogic();
        this.syncLogicMs = getTimer() - codeStarted;
        this.host.打印加载内容("加载杂项数据……");
        var miscStarted:Number = getTimer();
        this.b.s7_miscLoaders();
        this.miscStartMs = getTimer() - miscStarted;
        org.flashNight.arki.interaction.NativeMenuBridge.install();
        org.flashNight.arki.dialogue.NativeDialogueService.install();
        org.flashNight.arki.hud.PlayerHudService.install();
        this.state = S_FANOUT;
    }

    // === S3/S4/S9 异步 await（失败=不前进，匹配原版 hang） ===
    function stepTaskData():Void {
        if (this.b.taskDataFired != true) {
            this.b.taskDataFired = true;
            this.host.打印加载内容("加载任务数据……");      // 移植 f5:2（host 即 asLoader 实例，帧顶函数挂其上）
            var self:BootSequencer = this;
            TaskDataLoader.getInstance().loadTaskData(
                function(data:Object):Void {
                    self.bslog("任务数据加载完毕");
                    self.host.rawTaskData = data; self.b.taskDataReady = true;
                },
                function():Void {});
        }
        if (this.b.taskDataReady == true) this.state = S_TASKTEXT;
    }

    function stepTaskText():Void {
        if (this.b.taskTextFired != true) {
            this.b.taskTextFired = true;
            var self:BootSequencer = this;
            TaskTextLoader.getInstance().loadTaskText(
                function(data:Object):Void {
                    self.bslog("任务文本加载完毕");
                    self.host.rawTextData = data; self.b.taskTextReady = true;
                },
                function():Void {});
        }
        if (this.b.taskTextReady == true) this.state = S_PARSE;
    }

    // === S5 任务解析（原 f7；guide 为 fire-and-forget，不新增等待态） ===
    function parseTaskAndStartGuide():Void {
        org.flashNight.arki.task.TaskUtil.ParseTaskData(
            this.host.rawTaskData,
            this.host.rawTextData
        );
        this.host.rawTaskData = null;
        this.host.rawTextData = null;

        var guideLoader = org.flashNight.gesh.json.LoadJson.ProgressGuideLoader.getInstance();
        guideLoader.loadGuideData(
            function(data:Object):Void {
                org.flashNight.arki.task.TaskUtil.ParseGuideData(data);
            },
            function():Void {}
        );
    }

    // === S9 合成表落地（原 f75 成功回调） ===
    function applyCraftingData(data:Object):Void {
        var craftingDict = {};
        for (var category in data) {
            var list = data[category];
            for (var i = 0; i < list.length; i++) {
                var item = list[i];
                craftingDict[item.name] = item;
                if (isNaN(item.value)) item.value = 1;
            }
        }
        _root.改装清单 = data;
        _root.改装清单对象 = craftingDict;
        _root.改装分类顺序 = CraftingListLoader.getInstance().getCategoryOrder();
    }

    function stepCrafting():Void {
        if (this.b.craftFired != true) {
            this.b.craftFired = true;
            LightProfilesLoader.start();
            var self:BootSequencer = this;
            CraftingListLoader.getInstance().loadCraftingList(
                function(data:Object):Void {
                    self.applyCraftingData(data);
                    self.bslog("合成表数据加载完毕");   // S9 完成事件 → trace-diff CRAFTING_OK。旧 f75 仅 trace()（SA 剔除）→ gate 对 S9 盲；此处补 [BootstrapAS] 可见事件。
                    self.b.craftReady = true;
                },
                function():Void {
                    self.host.打印加载内容("合成表加载失败");
                    self.halt("crafting_catalog_failed");
                });
            MaterialCatalogLoader.getInstance().loadMaterialCatalog(
                function(data:Object):Void {
                    _root.材料档案目录 = data;
                    self.bslog("材料档案目录加载完毕");
                    self.b.materialCatalogReady = true;
                },
                function():Void {
                    self.host.打印加载内容("材料档案目录加载失败");
                    self.halt("material_catalog_failed");
                });
            ArenaDropRulesLoader.getInstance().loadArenaDropRules(
                function(data:Object):Void {
                    _root.竞技场掉落规则 = data;
                    self.bslog("竞技场掉落规则加载完毕");
                    self.b.arenaDropRulesReady = true;
                },
                function():Void {
                    self.b.arenaDropRulesFailed = true;
                    self.host.打印加载内容("竞技场掉落规则加载失败");
                    self.halt("arena_drop_rules_failed");
                });
        }
        if (this.b.itemDataLoaded == true && this.b.equipmentConfigSettled == true
                && this.b.itemDataReady != true && this.b.itemDataFailed != true) {
            var itemStarted:Number = getTimer();
            org.flashNight.arki.item.ItemUtil.loadItemData(this.b.itemDataPayload);
            this.itemIndexMs = getTimer() - itemStarted;
            delete this.b.itemDataPayload;
            if (org.flashNight.arki.item.ItemUtil.itemDataDict == undefined
                    || org.flashNight.arki.item.ItemUtil.materialDict == undefined) {
                this.b.itemDataFailed = true;
            } else {
                this.b.itemDataReady = true;
            }
        }
        if (this.b.itemDataFailed == true) {
            this.host.打印加载内容("物品数据加载失败");
            this.halt("item_data_failed");
            return;
        }
        if (this.b.enemyPropertiesFailed == true) {
            this.host.打印加载内容("敌人属性数据加载失败");
            this.halt("enemy_properties_failed");
            return;
        }
        if (this.b.mapDomainFailed == true) {
            this.host.打印加载内容("地图领域加载失败，请检查启动器与地图内容版本");
            this.halt("map_domain_failed");
            return;
        }
        if (this.b.legacyMaterialDictionaryFailed == true) {
            this.host.打印加载内容("材料大全数据加载失败");
            this.halt("material_dictionary_failed");
            return;
        }
        if (this.b.equipmentModFailed == true) {
            this.host.打印加载内容("插件数据加载失败");
            this.halt("equipment_mod_data_failed");
            return;
        }
        if (this.b.shopCatalogFailed == true) {
            this.host.打印加载内容("金币商店目录加载失败");
            this.halt("shop_catalog_failed");
            return;
        }
        if (this.b.kshopCatalogFailed == true) {
            this.host.打印加载内容("K点商城目录加载失败");
            this.halt("kshop_catalog_failed");
            return;
        }
        if (this.b.arenaDropRulesFailed == true) {
            this.host.打印加载内容("竞技场掉落规则加载失败");
            this.halt("arena_drop_rules_failed");
            return;
        }
        if (LightProfilesLoader.settled() && this.b.craftReady == true && this.b.materialCatalogReady == true
                && this.b.mapDomainReady == true
                && this.b.arenaDropRulesReady == true
                && this.b.itemDataReady == true
                && this.b.enemyPropertiesReady == true
                && this.b.legacyMaterialDictionaryReady == true
                && this.b.equipmentModReady == true
                && this.b.shopCatalogReady == true
                && this.b.kshopCatalogReady == true) {
            var shopCatalogCount:Number = 0;
            if (_root.shops != undefined && typeof _root.shops == "object"
                    && !(_root.shops instanceof Array)) {
                for (var shopId:String in _root.shops) {
                    shopCatalogCount++;
                }
            }
            if (shopCatalogCount < 1) {
                this.host.打印加载内容("金币商店目录加载失败");
                this.halt("shop_catalog_failed");
                return;
            }
            if (!(_root.kshop_list instanceof Array) || _root.kshop_list.length < 1) {
                this.host.打印加载内容("K点商城目录加载失败");
                this.halt("kshop_catalog_failed");
                return;
            }
            if (this.b.materialSourceIndexReady != true) {
                var indexStarted:Number = getTimer();
                var obtainIndex = org.flashNight.arki.item.obtain.ItemObtainIndex.getInstance();
                obtainIndex.buildIndex(_root.改装清单, _root.shops,
                    _root.kshop_list, _root.竞技场掉落规则);
                obtainIndex.rehydrateDiscoveredRecordsFromCurrentConfig();
                this.b.materialSourceIndexReady = true;
                this.acquireIndexMs = getTimer() - indexStarted;
            }
            this.state = S_HANDOFF;
        }
    }

    // === S6 系统初始化（移植 f9/f10/f18/f26/f32 + _root.loaders 逐 tick 抽干队列） ===
    // 原始 boot：f9 建 _root.loaders → f10(兼容×4) push 入队 → f18(最终化1) 跑全部 _root.preloaders →
    //   f26(最终化2) onEnterFrame 每帧抽 1 个 _root.loaders（时间切片防卡顿）→ 队空后 f32(最终化3)
    //   跑全部 _root.loaderkillers 并删三队列。单帧塌缩后由本 tick 复刻「每 tick 抽 1 个」。
    function stepSyncSys():Void {
        if (this.sysPhase == 0) {       // pre：建队列 + 入队 + 跑 preloaders（fire 异步 XML.load / GetFileByPath）
            this.b.s6_pre();            // = f9() + f10() + f18()
            this.sysPhase = 1;
            this.systemWaitStarted = getTimer();
            this.sysWait = 0;
            return;
        }
        if (this.sysPhase == 1) {       // ★ 等异步 preloader 落地再抽 loader（原版靠 f18→f26 帧间隔，塌缩压没了→曾致佣兵库只载 1 条）
            this.sysWait++;
            var pending:Number = (_root.__pendingFileLoads == undefined) ? 0 : _root.__pendingFileLoads;
            if (pending > 0) this.sawPending = true;             // 二级文件加载已起飞（GetFileByPath ++）
            // 每个受管 list 的 onLoad 在发出全部子请求后才封口；不能只看二级计数偶然为零。
            // 兼容外部扩展的旧 preload 队列，未知生产者仍使用原来的等待门。
            var lists:Array = _root.preloaders;
            var tracked:Boolean = lists.length == 4 && lists.merc_jsons_list != undefined
                && lists.units_jsons_list != undefined && lists.kshop_jsons_list != undefined
                && lists.shops_jsons_list != undefined;
            if (tracked) {
                var issued:Boolean = lists.merc_jsons_list.__bootChildrenIssued === true
                    && lists.units_jsons_list.__bootChildrenIssued === true
                    && lists.kshop_jsons_list.__bootChildrenIssued === true
                    && lists.shops_jsons_list.__bootChildrenIssued === true;
                if ((!issued || pending > 0) && this.sysWait < 150) return;
            } else {
                if (this.sysWait < 30) return;
                if ((!this.sawPending || pending > 0) && this.sysWait < 150) return;
            }
            this.systemWaitMs = getTimer() - this.systemWaitStarted;
            this.sysPhase = 2;
            return;
        }
        // phase 2：复刻 f26 —— 每 tick 抽 1 个 loader（保序、时间切片）；此时 preload 数据已就绪
        if (_root.loaders != undefined && (_root.loaders.current == undefined || isNaN(_root.loaders.current))) {
            _root.loaders.current = 0;  // 防 malformed queue：f9 契约若被误改漏设 current，不让 NaN 卡死 phase2
        }
        if (_root.loaders == undefined || _root.loaders.current >= _root.loaders.length) {
            this.b.s6_post();           // = f32()：跑 loaderkillers + 删三队列
            this.state = S_SYNCLOGIC;
            return;
        }
        var loadStarted:Number = getTimer();
        _root.loaders[_root.loaders.current]();
        this.systemLoadWork.push(getTimer() - loadStarted);
        _root.loaders.current++;
    }

    // === S10 handoff（顺序铁律: _root.play() 必先于卸载） ===
    function handoff():Void {
        if (_root.server != undefined) {
            var top:Array = [];
            for (var j:Number = 0; j < this.b.slowLoads.length; j++) {
                var load:Object = this.b.slowLoads[j];
                top.push(load.name + ":" + load.parse + "/" + load.handler);
            }
            _root.server.sendServerMessage("[BootTiming] observedParseMs=" + this.b.totalParseMs
                + " observedHandlerMs=" + this.b.totalHandlerMs + " slowParseHandlerMs=" + top.join(","));
            _root.server.sendServerMessage("[BootTiming] phases=3,4,5,6,7,8,9 wallMs=" + this.phaseWall.join(",")
                + " workMs=" + this.phaseWork.join(",") + " maxStepMs=" + this.workMax.join(",")
                + " systemWaitFrames=" + this.sysWait + " systemWaitMs=" + this.systemWaitMs
                + " systemLoadWorkMs=" + this.systemLoadWork.join(",") + " syncLogicMs=" + this.syncLogicMs
                + " miscStartMs=" + this.miscStartMs + " itemIndexMs=" + this.itemIndexMs + " obtainIndexMs=" + this.acquireIndexMs);
        }
        this.bslog("event=handoff");   // S10 handoff 事件 → trace-diff HANDOFF_PLAY。原 f91 无 SA-可见事件 → gate 对 S10 盲；_root.server 在自删后仍存活，先于卸载发。
        if (this.tickClip != undefined) this.tickClip.onEnterFrame = null;   // 判空：单测可不经 start() 直驱到 handoff（halt() 已同款判空）
        delete _root.__boot;   // 收尾：回收引导脚手架（staged 函数容器），boot 后即死代码，避免常驻 _root
        _root.play();
        if (this.host != undefined) {
            // asLoaderLogic.swf 内 _definitions 在时间轴处于负深度（如 -16383），
            // AVM1 对负深度直接调 removeMovieClip() 为静默 no-op；若 _definitions 残留存活，
            // 其帧上定义的全局闭包（如 _root.初始化玩家模板）会持续以 _definitions 为 AVM1 baseClip，
            // 使裸变量/裸调无法回退到调用方 MovieClip（导致主角出生漏跑装扮初始化并卡在 p:1）。
            if (this.host.getDepth != undefined && this.host.swapDepths != undefined) {
                var hostDepth:Number = this.host.getDepth();
                if (hostDepth < 0) {
                    var targetDepth:Number = (this.host._parent != undefined
                            && this.host._parent.getNextHighestDepth != undefined)
                        ? this.host._parent.getNextHighestDepth() : 0;
                    if (isNaN(targetDepth) || targetDepth < 0) {
                        targetDepth = 0;
                    }
                    this.host.swapDepths(targetDepth);
                }
            }
            this.host.removeMovieClip();
        }
        if (this.tickClip != undefined) this.tickClip.removeMovieClip();
        this.state = S_HALT;
        BootSequencer._instance = undefined;  // 释放重入保护(显式限定静态)：同会话重挂 asLoader 时 run() 才会重建实例 + tick（否则新 _root.__boot 无驱动→卡死）
    }
}
