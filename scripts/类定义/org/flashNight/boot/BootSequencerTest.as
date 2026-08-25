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

    public static function runAllTests():Void {
        new BootSequencerTest().runTests();
    }

    public function runTests():Void {
        trace("=== BootSequencerTest start ===");
        this.test_s0_initializesGlobals();
        this.test_shimMissing_halts();
        this.test_socketTimeout_halts();
        this.test_socketReady_firesHandshake();
        this.test_handshakeFailed_halts();
        this.test_repairGate_spinsThenReleases();
        this.test_s5_parsesTaskAndStartsGuide();
        this.test_s7_preservesOrder();
        this.test_crafting_emitsEvent();
        this.test_crafting_dependencyFailureHalts();
        this.test_crafting_catalogLoaderFailureHalts();
        this.test_itemDataWaitsForEquipmentConfigSettlement();
        this.test_handoff_emitsEvent();
        this.test_run_idempotent();
        this.test_s6_waitGateThenDrain();
        this.test_s6_ceilingRelease();
        this.test_s6_loaderQueueCurrentDefaults();
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
        this._calls = {handoffOrder: []};

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
        _root.play = function() {
            t._calls.rootPlay = t.inc(t._calls.rootPlay);
            t._calls.handoffOrder.push("play");
        };

        // staged 函数桩（仅记录；构造函数见 _root.__boot != undefined 即直接用本对象）
        _root.__boot = {
            s1_syncCode: function() { t._calls.s1 = t.inc(t._calls.s1); },
            s6_pre: function() { t._calls.s6pre = t.inc(t._calls.s6pre); },
            s6_post: function() { t._calls.s6post = t.inc(t._calls.s6post); },
            s7_syncLogic: function() { t._calls.s7 = t.inc(t._calls.s7); },
            s7_miscLoaders: function() { t._calls.s7misc = t.inc(t._calls.s7misc); },
            s8_fanout: function() { t._calls.s8 = t.inc(t._calls.s8); }
        };

        BootSequencer._instance = undefined;   // 复位重入保护

        return {
            打印加载内容: function(s) { t._printed.push(s); },
            removeMovieClip: function() {
                t._calls.hostRemoved = t.inc(t._calls.hostRemoved);
                t._calls.handoffOrder.push("remove");
            }
        };
    }

    public function inc(n:Number):Number { return (n == undefined ? 0 : n) + 1; }   // 经 t.inc() 由闭包调用

    // 握手 case 不真跑全局初始化；S0 由独立 case 覆盖。
    private function driveToHsP1(inst:BootSequencer):Void {
        inst.state = BootSequencer.S_SYNCCODE;
        inst.step();   // S_SYNCCODE → s1_syncCode, → S_HANDSHAKE hsPhase=1
    }

    // ====== S0：全局初始化业务归 BootSequencer，不回流生成器 ======
    private function test_s0_initializesGlobals():Void {
        var host = this.freshEnv();
        var initializer:Object = org.flashNight.gesh.init.GlobalInitializer;
        var originalInitialize:Function = initializer.initialize;
        var t:BootSequencerTest = this;
        initializer.initialize = function():Void {
            t._calls.globalInitialize = t.inc(t._calls.globalInitialize);
        };
        var inst:BootSequencer = new BootSequencer(host);
        try {
            inst.step();
        } finally {
            initializer.initialize = originalInitialize;
        }
        this.assert(this._calls.globalInitialize == 1, "(S0) GlobalInitializer.initialize() 调用一次");
        this.assert(inst.state == BootSequencer.S_SYNCCODE, "(S0) 初始化后进入 S_SYNCCODE");
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

    // ====== S5：任务解析 + guide fire-and-forget 业务归 BootSequencer ======
    private function test_s5_parsesTaskAndStartsGuide():Void {
        var host = this.freshEnv();
        var rawTask:Object = {id:"task"};
        var rawText:Object = {id:"text"};
        var guideData:Object = {id:"guide"};
        host.rawTaskData = rawTask;
        host.rawTextData = rawText;

        var t:BootSequencerTest = this;
        var taskUtil:Object = org.flashNight.arki.task.TaskUtil;
        var guideLoader:Object = org.flashNight.gesh.json.LoadJson.ProgressGuideLoader.getInstance();
        var originalParseTask:Function = taskUtil.ParseTaskData;
        var originalParseGuide:Function = taskUtil.ParseGuideData;
        var originalLoadGuide:Function = guideLoader.loadGuideData;
        taskUtil.ParseTaskData = function(task:Object, text:Object):Void {
            t._calls.parsedTask = task;
            t._calls.parsedText = text;
        };
        taskUtil.ParseGuideData = function(data:Object):Void {
            t._calls.parsedGuide = data;
        };
        guideLoader.loadGuideData = function(ok:Function, fail:Function):Void {
            t._calls.guideLoads = t.inc(t._calls.guideLoads);
            ok(guideData);
        };

        var inst:BootSequencer = new BootSequencer(host);
        inst.state = BootSequencer.S_PARSE;
        try {
            inst.step();
        } finally {
            taskUtil.ParseTaskData = originalParseTask;
            taskUtil.ParseGuideData = originalParseGuide;
            guideLoader.loadGuideData = originalLoadGuide;
        }
        this.assert(this._calls.parsedTask == rawTask && this._calls.parsedText == rawText,
            "(S5) ParseTaskData 收到两份原始引用");
        this.assert(host.rawTaskData == null && host.rawTextData == null,
            "(S5) 任务解析后清空 host raw 数据");
        this.assert(this._calls.guideLoads == 1 && this._calls.parsedGuide == guideData,
            "(S5) guide fire-and-forget 发起并解析成功回调");
        this.assert(inst.state == BootSequencer.S_SYNCSYS, "(S5) 不等待 guide，直接进入 S_SYNCSYS");
    }

    // ====== f48 / S7：同 tick 保持 sync logic → 文案 → misc loaders 顺序 ======
    private function test_s7_preservesOrder():Void {
        var host = this.freshEnv();
        var order:Array = [];
        var expectedText:String = "加载杂项数据……";
        host.打印加载内容 = function(text:String):Void { order.push("print:" + text); };
        _root.__boot.s7_syncLogic = function():Void { order.push("sync"); };
        _root.__boot.s7_miscLoaders = function():Void { order.push("misc"); };

        var inst:BootSequencer = new BootSequencer(host);
        inst.state = BootSequencer.S_SYNCLOGIC;
        inst.step();
        this.assert(order.join("|") == "sync|print:" + expectedText + "|misc",
            "(S7) sync logic → f48 文案 → misc loaders 保序且同 tick");
        this.assert(inst.state == BootSequencer.S_FANOUT, "(S7) 完成后进入 S_FANOUT");
    }

    // ====== Finding 1：S9 合成表 + 材料档案 + 竞技场掉落三门成功 ======
    private function test_crafting_emitsEvent():Void {
        var host = this.freshEnv();
        var inst:BootSequencer = new BootSequencer(host);
        inst.state = BootSequencer.S_CRAFTING;

        var recipe:Object = {name:"测试配方"};
        var crafting:Object = {testCategory:[recipe]};
        var materialCatalog:Object = {schemaVersion:1, DirectPurpose:[], Material:[]};
        var arenaDropCatalog:Object = {schemaVersion:1, sources:[]};
        // 三个目录允许测试桩给 authored 空集合，但必须等 loader 成功信号，不能凭形状猜 ready。
        var shops:Object = {};
        var kshop:Array = [];
        var oldCrafting = _root.改装清单;
        var oldCraftingDict = _root.改装清单对象;
        var oldCraftingOrder = _root.改装分类顺序;
        var oldMaterialCatalog = _root.材料档案目录;
        var oldArenaDropCatalog = _root.竞技场掉落规则;
        var oldShops = _root.shops;
        var oldKshop = _root.kshop_list;
        _root.shops = shops;
        _root.kshop_list = kshop;

        // 把四个真单例换成可控成功/记录桩；用后还原，避免单例状态污染后续 suite。
        var loader:Object = org.flashNight.gesh.json.LoadJson.CraftingListLoader.getInstance();
        var catalogLoader:Object = org.flashNight.gesh.xml.LoadXml.MaterialCatalogLoader.getInstance();
        var arenaLoader:Object = org.flashNight.gesh.xml.LoadXml.ArenaDropRulesLoader.getInstance();
        var obtainIndex:Object = org.flashNight.arki.item.obtain.ItemObtainIndex.getInstance();
        var originalLoad:Function = loader.loadCraftingList;
        var originalGetCategoryOrder:Function = loader.getCategoryOrder;
        var originalCatalogLoad:Function = catalogLoader.loadMaterialCatalog;
        var originalArenaLoad:Function = arenaLoader.loadArenaDropRules;
        var originalBuildIndex:Function = obtainIndex.buildIndex;
        var originalRehydrate:Function = obtainIndex.rehydrateDiscoveredRecordsFromCurrentConfig;
        var t:BootSequencerTest = this;
        var craftOk:Function;
        var catalogOk:Function;
        var arenaOk:Function;
        loader.loadCraftingList = function(ok:Function, fail:Function):Void {
            craftOk = ok;
            t._calls.craftStarted = true;
        };
        loader.getCategoryOrder = function():Array { return ["testCategory"]; };
        catalogLoader.loadMaterialCatalog = function(ok:Function, fail:Function):Void {
            catalogOk = ok;
            t._calls.catalogStarted = true;
        };
        arenaLoader.loadArenaDropRules = function(ok:Function, fail:Function):Void {
            arenaOk = ok;
            t._calls.arenaStarted = true;
        };
        obtainIndex.buildIndex = function(craftingArg:Object, shopsArg:Object,
                                          kshopArg:Object, arenaArg:Object):Void {
            t._calls.indexCrafting = craftingArg;
            t._calls.indexShops = shopsArg;
            t._calls.indexKshop = kshopArg;
            t._calls.indexArena = arenaArg;
        };
        obtainIndex.rehydrateDiscoveredRecordsFromCurrentConfig = function():Void {
            t._calls.rehydrate = t.inc(t._calls.rehydrate);
        };

        var installedCrafting;
        var installedDict;
        var installedOrder;
        var installedMaterialCatalog;
        var installedArenaDropCatalog;
        try {
            inst.step();
            this.assert(this._calls.craftStarted == true
                && this._calls.catalogStarted == true
                && this._calls.arenaStarted == true &&
                inst.state == BootSequencer.S_CRAFTING,
                "(S9) 同 tick 发起合成表/材料目录/竞技场掉落三个加载，未就绪不 handoff");
            catalogOk(materialCatalog);
            inst.step();
            this.assert(inst.state == BootSequencer.S_CRAFTING,
                "(S9) catalog-first 反序仅 material catalog ready 不得 handoff");
            craftOk(crafting);
            inst.step();
            this.assert(inst.state == BootSequencer.S_CRAFTING
                    && this._calls.indexCrafting == undefined,
                "(S9) craft/catalog 就绪但 arena 门未齐，不得提前建索引或 handoff");
            arenaOk(arenaDropCatalog);
            _root.__boot.itemDataReady = true;
            _root.__boot.enemyPropertiesReady = true;
            _root.__boot.legacyMaterialDictionaryReady = true;
            _root.__boot.equipmentModReady = true;
            inst.step();
            this.assert(inst.state == BootSequencer.S_CRAFTING
                    && this._calls.indexCrafting == undefined,
                "(S9) shop/kshop 即使已有对象形状，未收到成功完成信号也只能等待");
            // 显式 npc-shop.v2 停用店会归一成一个存在的 identity + 空 catalog。
            // S9 只要求全局 identity 集合非空，不得把该 authored 空目录误判为全局空商店表。
            shops["测试停用商店"] = {};
            kshop.push({id:"测试商品"});
            _root.__boot.shopCatalogReady = true;
            _root.__boot.kshopCatalogReady = true;
            inst.step();
            installedCrafting = _root.改装清单;
            installedDict = _root.改装清单对象;
            installedOrder = _root.改装分类顺序;
            installedMaterialCatalog = _root.材料档案目录;
            installedArenaDropCatalog = _root.竞技场掉落规则;
        } finally {
            loader.loadCraftingList = originalLoad;
            loader.getCategoryOrder = originalGetCategoryOrder;
            catalogLoader.loadMaterialCatalog = originalCatalogLoad;
            arenaLoader.loadArenaDropRules = originalArenaLoad;
            obtainIndex.buildIndex = originalBuildIndex;
            obtainIndex.rehydrateDiscoveredRecordsFromCurrentConfig = originalRehydrate;
            _root.改装清单 = oldCrafting;
            _root.改装清单对象 = oldCraftingDict;
            _root.改装分类顺序 = oldCraftingOrder;
            _root.材料档案目录 = oldMaterialCatalog;
            _root.竞技场掉落规则 = oldArenaDropCatalog;
            _root.shops = oldShops;
            _root.kshop_list = oldKshop;
        }
        this.assert(installedCrafting == crafting && installedDict != undefined &&
            installedDict["测试配方"] == recipe,
            "(S9) 合成表与 name→recipe 字典按原引用落地");
        this.assert(installedOrder.join("|") == "testCategory"
            && installedMaterialCatalog == materialCatalog
            && installedArenaDropCatalog == arenaDropCatalog,
            "(S9) 分类顺序、材料档案与竞技场掉落 catalog 按原引用落地");
        this.assert(recipe.value == 1, "(S9) 缺省 recipe.value 保持旧语义补为 1");
        this.assert(this._calls.indexCrafting == crafting && this._calls.indexShops == shops &&
            this._calls.indexKshop == kshop && this._calls.indexArena == arenaDropCatalog,
            "(S9) ItemObtainIndex 收到 crafting/shop/kshop/arena 原引用");
        this.assert(this._calls.rehydrate == 1,
            "(S9) 静态索引完成后只幂等恢复一次 enemy/base/challenge 已发现来源");
        this.assert(this.msgHas("合成表数据加载完毕")
            && this.msgHas("材料档案目录加载完毕")
            && this.msgHas("竞技场掉落规则加载完毕"),
            "(S9) 三个成功回调均发可观测事件");
        this.assert(inst.state == BootSequencer.S_HANDOFF,
            "(S9) 显式 v2 停用店空 catalog 仍提供 identity；其余依赖 ready 后进入 S_HANDOFF");
    }

    private function test_crafting_dependencyFailureHalts():Void {
        var cases:Array = [
            {flag:"itemDataFailed", ready:"itemDataReady", reason:"item_data_failed"},
            {flag:"enemyPropertiesFailed", ready:"enemyPropertiesReady", reason:"enemy_properties_failed"},
            {flag:"legacyMaterialDictionaryFailed", ready:"legacyMaterialDictionaryReady", reason:"material_dictionary_failed"},
            {flag:"equipmentModFailed", ready:"equipmentModReady", reason:"equipment_mod_data_failed"},
            {flag:"shopCatalogFailed", ready:"shopCatalogReady", reason:"shop_catalog_failed"},
            {flag:"kshopCatalogFailed", ready:"kshopCatalogReady", reason:"kshop_catalog_failed"},
            {flag:"arenaDropRulesFailed", ready:"arenaDropRulesReady", reason:"arena_drop_rules_failed"}
        ];
        for (var i:Number = 0; i < cases.length; i++) {
            var host = this.freshEnv();
            var inst:BootSequencer = new BootSequencer(host);
            inst.state = BootSequencer.S_CRAFTING;
            _root.__boot.craftFired = true;
            _root.__boot[cases[i].flag] = true;
            inst.step();
            this.assert(inst.state == BootSequencer.S_HALT
                    && _root.__boot.bootFailed == cases[i].reason,
                "(S9) provider " + cases[i].flag + " exact fail-closed");
            _root.__boot[cases[i].ready] = true;
            inst.step();
            this.assert(inst.state == BootSequencer.S_HALT,
                "(S9) " + cases[i].flag + " halt 后迟到 success 不得 handoff");
        }

        var validShops:Object = {};
        validShops["测试商店"] = [];
        var malformed:Array = [
            {shops:[], kshop:[{id:"测试商品"}], reason:"shop_catalog_failed"},
            {shops:{}, kshop:[{id:"测试商品"}], reason:"shop_catalog_failed"},
            {shops:validShops, kshop:{}, reason:"kshop_catalog_failed"},
            {shops:validShops, kshop:[], reason:"kshop_catalog_failed"}
        ];
        for (var j:Number = 0; j < malformed.length; j++) {
            var host2 = this.freshEnv();
            var inst2:BootSequencer = new BootSequencer(host2);
            inst2.state = BootSequencer.S_CRAFTING;
            _root.__boot.craftFired = true;
            _root.__boot.craftReady = true;
            _root.__boot.materialCatalogReady = true;
            _root.__boot.arenaDropRulesReady = true;
            _root.__boot.itemDataReady = true;
            _root.__boot.enemyPropertiesReady = true;
            _root.__boot.legacyMaterialDictionaryReady = true;
            _root.__boot.equipmentModReady = true;
            _root.__boot.shopCatalogReady = true;
            _root.__boot.kshopCatalogReady = true;
            var oldShops = _root.shops;
            var oldKshop = _root.kshop_list;
            _root.shops = malformed[j].shops;
            _root.kshop_list = malformed[j].kshop;
            inst2.step();
            _root.shops = oldShops;
            _root.kshop_list = oldKshop;
            this.assert(inst2.state == BootSequencer.S_HALT
                    && _root.__boot.bootFailed == malformed[j].reason,
                "(S9) ready 信号后的畸形目录仍以对应 exact reason fail-closed");
        }
    }

    private function test_crafting_catalogLoaderFailureHalts():Void {
        var modes:Array = ["craft", "catalog", "arena"];
        for (var i:Number = 0; i < modes.length; i++) {
            var host = this.freshEnv();
            var inst:BootSequencer = new BootSequencer(host);
            inst.state = BootSequencer.S_CRAFTING;
            var loader:Object = org.flashNight.gesh.json.LoadJson.CraftingListLoader.getInstance();
            var catalogLoader:Object = org.flashNight.gesh.xml.LoadXml.MaterialCatalogLoader.getInstance();
            var arenaLoader:Object = org.flashNight.gesh.xml.LoadXml.ArenaDropRulesLoader.getInstance();
            var originalLoad:Function = loader.loadCraftingList;
            var originalCatalogLoad:Function = catalogLoader.loadMaterialCatalog;
            var originalArenaLoad:Function = arenaLoader.loadArenaDropRules;
            var craftOk:Function;
            var craftFail:Function;
            var catalogOk:Function;
            var catalogFail:Function;
            var arenaOk:Function;
            var arenaFail:Function;
            loader.loadCraftingList = function(ok:Function, fail:Function):Void {
                craftOk = ok; craftFail = fail;
            };
            catalogLoader.loadMaterialCatalog = function(ok:Function, fail:Function):Void {
                catalogOk = ok; catalogFail = fail;
            };
            arenaLoader.loadArenaDropRules = function(ok:Function, fail:Function):Void {
                arenaOk = ok; arenaFail = fail;
            };
            try {
                inst.step();
                if (modes[i] == "craft") {
                    craftFail();
                    catalogOk({schemaVersion:1, DirectPurpose:[], Material:[]});
                    arenaOk({schemaVersion:1, sources:[]});
                } else if (modes[i] == "catalog") {
                    catalogFail();
                    craftOk({testCategory:[]});
                    arenaOk({schemaVersion:1, sources:[]});
                } else {
                    arenaFail();
                    craftOk({testCategory:[]});
                    catalogOk({schemaVersion:1, DirectPurpose:[], Material:[]});
                }
                inst.step();
            } finally {
                loader.loadCraftingList = originalLoad;
                catalogLoader.loadMaterialCatalog = originalCatalogLoad;
                arenaLoader.loadArenaDropRules = originalArenaLoad;
            }
            var expected:String = modes[i] == "craft" ? "crafting_catalog_failed"
                : (modes[i] == "catalog" ? "material_catalog_failed"
                    : "arena_drop_rules_failed");
            this.assert(inst.state == BootSequencer.S_HALT
                    && _root.__boot.bootFailed == expected,
                "(S9) " + modes[i] + " loader failure + peer late success remains halted");
        }
    }

    private function test_itemDataWaitsForEquipmentConfigSettlement():Void {
        var itemUtil:Object = org.flashNight.arki.item.ItemUtil;
        var originalLoad:Function = itemUtil.loadItemData;
        var originalItemDict:Object = itemUtil.itemDataDict;
        var originalMaterialDict:Object = itemUtil.materialDict;
        var t:BootSequencerTest = this;
        itemUtil.loadItemData = function(payload:Object):Void {
            t._calls.itemApply = t.inc(t._calls.itemApply);
            t._calls.itemPayload = payload;
            itemUtil.itemDataDict = {};
            itemUtil.materialDict = {};
        };
        try {
            var host = this.freshEnv();
            var inst:BootSequencer = new BootSequencer(host);
            var payload:Object = [{name:"raw-first"}];
            inst.state = BootSequencer.S_CRAFTING;
            _root.__boot.craftFired = true;
            _root.__boot.itemDataLoaded = true;
            _root.__boot.itemDataPayload = payload;
            inst.step();
            this.assert(this._calls.itemApply == undefined
                    && _root.__boot.itemDataReady != true,
                "(S8→S9) item raw first 必须等待 equipment config settled");
            _root.__boot.equipmentConfigSettled = true;
            inst.step();
            inst.step();
            this.assert(this._calls.itemApply == 1 && this._calls.itemPayload == payload
                    && _root.__boot.itemDataReady == true,
                "(S8→S9) config settled 后只 apply item payload 一次并置 ready");

            host = this.freshEnv();
            inst = new BootSequencer(host);
            payload = [{name:"config-first"}];
            inst.state = BootSequencer.S_CRAFTING;
            _root.__boot.craftFired = true;
            _root.__boot.equipmentConfigSettled = true;
            inst.step();
            this.assert(this._calls.itemApply == undefined,
                "(S8→S9) config first 但 item raw 未到时不得空 apply");
            _root.__boot.itemDataLoaded = true;
            _root.__boot.itemDataPayload = payload;
            inst.step();
            this.assert(this._calls.itemApply == 1 && this._calls.itemPayload == payload
                    && _root.__boot.itemDataReady == true,
                "(S8→S9) config-first 反序在 raw 到达后恰一次 apply");
        } finally {
            itemUtil.loadItemData = originalLoad;
            itemUtil.itemDataDict = originalItemDict;
            itemUtil.materialDict = originalMaterialDict;
        }
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
        this.assert(this._calls.handoffOrder.join(",") == "play,remove",
            "(S10) 调用顺序严格为 _root.play() → host.removeMovieClip()");
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
        this.assert(inst.sysPhase == 2 && inst.sysWait == 150, "(e/ceiling) sysWait=150 兜底放行 → 进抽干相位");
        inst.step();                             // 空队列 current>=length → s6_post + S_SYNCLOGIC
        this.assert(this._calls.s6post == 1 && inst.state == BootSequencer.S_SYNCLOGIC, "(e/ceiling) 队空 → s6_post + 推进");
    }

    // ====== 边界 (e) 防御：loader 队列缺 current 时归零，不让 phase2 NaN 比较卡死 ======
    private function test_s6_loaderQueueCurrentDefaults():Void {
        var host = this.freshEnv();
        var inst:BootSequencer = new BootSequencer(host);
        inst.state = BootSequencer.S_SYNCSYS;
        var drained:Array = [];
        var q:Array = [];
        q.push(function() { drained.push(1); });
        _root.loaders = q;                       // 故意不设 q.current
        _root.__pendingFileLoads = 0;

        inst.step();                             // sysPhase0: s6_pre → sysPhase=1, sysWait=0
        inst.sawPending = true;                  // 已观测过二级加载起飞，现已落地
        inst.sysWait = 29;
        inst.step();                             // phase1: sysWait=30 → 放行到 phase2
        this.assert(inst.sysPhase == 2 && inst.sysWait == 30, "(e/current) sysWait 精确计到 30 才放行");
        this.assert(_root.loaders.current == undefined, "(e/current) phase2 前 malformed queue.current 仍缺失");

        inst.step();                             // phase2: current 缺失 → 归零 → 抽 loaders[0]
        this.assert(_root.loaders.current == 1 && drained.length == 1 && drained[0] == 1, "(e/current) current 缺失时归零并正常抽 1 个 loader");
        inst.step();                             // 队空 → s6_post + S_SYNCLOGIC
        this.assert(this._calls.s6post == 1 && inst.state == BootSequencer.S_SYNCLOGIC, "(e/current) 队空 → s6_post + 推进");
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
