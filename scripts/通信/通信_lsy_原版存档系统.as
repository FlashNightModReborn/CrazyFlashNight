import org.flashNight.neur.Server.*;

// ==================== SaveManager shim 层 ====================
// 注意：不能用 var sm = SaveManager.getInstance() 然后闭包捕获 sm
// 因为帧脚本局部变量在 asLoader 卸载后被回收（AS2 闭包陷阱）
// 每个委托函数必须每次调用时通过 SaveManager.getInstance() 获取实例

// 初始化 SaveManager 单例（确保构造运行）
SaveManager.getInstance();

_root.存档系统 = new Object();
_root.存档系统.latest_version = SaveManager.LATEST_VERSION;
_root.存档系统.dirtyMark = false;

// 数据组包/初始化委托（每次调用走 class 静态方法，不依赖帧脚本局部变量）
_root.存档系统.mydata数据组包 = function() { _root.mydata = SaveManager.getInstance().packGameState(); };
_root.存档系统.初始化物品栏 = function() { return SaveManager.getInstance().initInventory(); };
_root.存档系统.初始化收集品栏 = function() { return SaveManager.getInstance().initCollection(); };
_root.存档系统.存储设置 = function() { return SaveManager.getInstance().packSettings(); };
_root.存档系统.读取设置 = function(s) { SaveManager.getInstance().applySettings(s); };
_root.存档系统.convert = function(data) { SaveManager.getInstance().migrateAndSync(data, SaveManager.getInstance().getSOData()); };
_root.存档系统.migrateAndSync = function(data, soData) { SaveManager.getInstance().migrateAndSync(data, soData); };

// 核心存/读委托
_root.自动存盘 = function() { SaveManager.getInstance().saveAll(); };
_root.本地存盘 = function() { SaveManager.getInstance().saveAll(); };
_root.读取本地存盘 = function() { SaveManager.getInstance().preload(); };
_root.读取存盘 = function() { return SaveManager.getInstance().loadAll(); };
_root.是否存过盘 = function() { return SaveManager.getInstance().hasSaveData(); };
_root.存档恢复等待中 = function() { return SaveManager.getInstance().isRecoveryPending(); };
_root.新建角色 = function() { return SaveManager.getInstance().newCharacter(); };
_root.删除存盘 = function() { SaveManager.getInstance().deleteSlot(); };

// 折入 saveAll/loadAll，保留空壳防外部调用报错
_root.本地存盘战宠 = function() {};
_root.读取本地存盘战宠 = function() {};
_root.SavePCTasks = function() {};
_root.LoadPCTasks = function() {};

// 商城委托
_root.保存购物车 = function() { SaveManager.getInstance().saveShopCart(); };
_root.获取购物车信息 = function() { SaveManager.getInstance().loadShopCart(); };
_root.存盘商城已购买物品 = function() { SaveManager.getInstance().saveShopPurchased(); };
_root.读盘商城已购买物品 = function() { SaveManager.getInstance().loadShopPurchased(); };

// 保留旧变量声明（兼容性）
_root.存盘名 = "test";
_root.lastsave = "";
_root.lastsave2 = [];
_root.lastsave2_1 = [];
_root.lastsave2_2 = [];
_root.lastsave2_3 = [];
_root.lastsave_1 = "";
_root.lastsave_2 = "";
_root.lastsave_3 = "";

_root.允许存档 = true;

// 调试入口（/console → #func:_root.debugSavePrefetch() 然后 #get:debugLastResult）
_root.debugSaveRoundtrip = function():Void {
    _root.debugLastResult = "roundtrip=" + SaveManager.getInstance().loadFromMydata(SaveManager.getInstance().packGameState());
};
_root.debugSavePrefetch = function():Void {
    var st:Object = SaveManager.getInstance().getPrefetchStatus();
    _root.debugLastResult = "hasPrefetch=" + st.hasPrefetch + " slot=" + st.slot + " gen=" + st.gen;
};

// P3b Spike 3: bootstrap 握手验证（一次性，Phase 1 会重新设计）
// 用法：/console → #func:_root.spike_bootstrap_handshake() 然后 #get:debugLastResult
_root.spike_bootstrap_handshake = function():Void {
    var sm:ServerManager = ServerManager.getInstance();
    _root.debugLastResult = "sending... connected=" + sm.isSocketConnected;
    if (!sm.isSocketConnected) return;
    sm.sendTaskWithCallback("bootstrap_handshake", {hello:"from_flash"}, null,
        function(resp:Object):Void {
            _root.debugLastResult = "resp: success=" + resp.success
                + " savePath=" + resp.savePath
                + " raw=" + resp.task;
        });
};
