import org.flashNight.neur.Server.ServerManager;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.item.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.weather.*;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import LiteJSON;
import JSON;
/**
 * SaveManager — 存档系统统一管理器（单例）
 *
 * 职责：
 *   1. 归一化存档数据（tasks/pets/shop 折入 mydata）
 *   2. 单次 flush 替代多模块各自 flush
 *   3. 过渡期 dual-write（顶层 key + mydata 内部），读取优先非空顶层，空壳回退 mydata
 *   4. 版本迁移链（undefined → 2.6 → 2.7 → 3.0）
 *   5. 为后续 Launcher 迁移提供统一接口
 */
class org.flashNight.neur.Server.SaveManager {

    // ==================== 单例 ====================
    private static var _instance:SaveManager;

    public static function getInstance():SaveManager {
        if (!_instance) {
            _instance = new SaveManager();
        }
        SaveManager.getInstance = function():SaveManager {
            return _instance;
        };
        return _instance;
    }

    // ==================== 常量 ====================
    public static var LATEST_VERSION:String = "3.0";
    public static var SAVE_KEY:String = "test";

    // ==================== 状态 ====================
    private var _dirtyMark:Boolean;
    private var _lastSaveHash:String;
    private var _liteJson:LiteJSON;
    private var _jsonParser:JSON;
    private var _prefetchedData:Object;
    private var _prefetchedSlot:String;
    private var _prefetchGen:Number;
    private var _prefetchInFlight:Boolean;

    // ── Protocol 2 (launcher 存档决议) ──
    // 握手回调把 _root._launcher* 写入, preload() 一次性消费并转存到实例字段后 delete.
    // preload() 被 asLoader frame 4 + 主FLA frame 63 各调一次, _protocol2Consumed 保证幂等.
    private var _bootstrapSnapshot:Object = undefined;
    private var _bootstrapSnapshotSource:String = undefined;
    private var _skipPrefetch:Boolean = false;
    private var _protocol2Consumed:Boolean = false;
    private var _deferredResolutionAttempted:Boolean = false;
    private var _deferredDecisionSource:String = undefined;

    // ==================== 构造 ====================
    private function SaveManager() {
        _dirtyMark = false;
        _lastSaveHash = "";
        _liteJson = new LiteJSON();
        _jsonParser = new JSON(false);
        _prefetchGen = 0;
        _prefetchInFlight = false;
    }

    // ==================== 测试专用 ====================
    // 仅供 BootstrapProtocolTest 使用。因为 SaveManager 是全局单例，正常运行
    // 期 _protocol2Consumed 单向拉起后 preload 不再响应决议；测试需要复位状态
    // 才能跑完 snapshot / deleted / empty / corrupt / needs_migration 五条分支。
    // 产品代码不得调用。
    public function _resetProtocol2ForTest():Void {
        _bootstrapSnapshot = undefined;
        _bootstrapSnapshotSource = undefined;
        _skipPrefetch = false;
        _protocol2Consumed = false;
        _deferredResolutionAttempted = false;
        _deferredDecisionSource = undefined;
        _prefetchedData = undefined;
        _prefetchedSlot = undefined;
        _prefetchGen++;
        _prefetchInFlight = false;
    }

    // ==================== 预取管理 ====================

    public function getPrefetchStatus():Object {
        return { hasPrefetch: (_prefetchedData != undefined), slot: _prefetchedSlot, gen: _prefetchGen };
    }

    public function clearPrefetch():Void {
        _prefetchedData = undefined;
        _prefetchedSlot = undefined;
        _prefetchGen++;
        _prefetchInFlight = false;
    }

    public function receiveSavePush(response:Object):Void {
        var sm:ServerManager = ServerManager.getInstance();
        _prefetchGen++;
        var dataRaw = response.data;

        if (typeof dataRaw != "string") {
            sm.sendServerMessage("[SaveManager] receiveSavePush: data not string, type=" + typeof dataRaw);
            return;
        }

        var parsed:Object = _jsonParser.parse(dataRaw);
        if (_jsonParser.errors.length > 0) {
            sm.sendServerMessage("[SaveManager] receiveSavePush: parse errors=" + _jsonParser.errors.length);
            return;
        }
        if (!validateMydata(parsed)) {
            sm.sendServerMessage("[SaveManager] receiveSavePush: validate failed");
            return;
        }
        _prefetchedData = parsed;
        _prefetchedSlot = String(response.slot);
        sm.sendServerMessage("[SaveManager] receiveSavePush OK slot=" + _prefetchedSlot);
    }

    // ==================== 核心存/读 ====================

    public function saveAll():Boolean {
        if (_root.允许存档 !== true) return false;

        // 同步外部 dirtyMark
        if (_root.存档系统.dirtyMark) _dirtyMark = true;

        var sm:ServerManager = ServerManager.getInstance();
        sm.sendServerMessage("[SaveManager.saveAll] 角色=" + _root.角色名 + " 等级=" + _root.等级 + " 金钱=" + _root.金钱 + " savePath=" + _root.savePath);

        FrameBroadcaster.pushUiState("sv:1");

        // 同步主线任务进度（确保 mydata[3] 与 task_chains_progress 一致）
        if (!isNaN(_root.task_chains_progress.主线)) {
            _root.主线任务进度 = _root.task_chains_progress.主线;
        }

        // 身价校正
        if (_root.身价 < 1000 * _root.等级) {
            _root.身价 = 1000 * _root.等级;
        }

        // 组包
        var mydata:Object = packGameState();
        var so:SharedObject = getSO();
        var soData:Object = so.data;

        // 写入新位置
        soData[SAVE_KEY] = mydata;
        // 清除删档墓碑（如果有）
        delete soData._deleted;

        // dual-write 顶层 key（读取优先层，空壳时允许回退 mydata）
        soData.tasks_to_do = _root.tasks_to_do;
        soData.tasks_finished = _root.tasks_finished;
        soData.task_chains_progress = _root.task_chains_progress;
        soData.战宠 = _root.宠物信息;
        soData.宠物领养限制 = _root.宠物领养限制;
        soData.商城已购买物品 = _root.商城已购买物品;
        soData.商城购物车 = _root.商城购物车;

        // 单次 flush
        var ok:Boolean = flushSO(so);
        if (ok) {
            _dirtyMark = false;
            _root.存档系统.dirtyMark = false;
        }

        _root.mydata = mydata;
        _root.存盘标志 = 1;
        FrameBroadcaster.pushUiState("sv:2");
        _root.UpdateTaskProgress();

        var _saLen = (_root.tasks_to_do != undefined) ? _root.tasks_to_do.length : 0;
        sm.sendServerMessage("[SaveManager.saveAll] flush=" + ok + " version=" + mydata.version + " tasks_to_do.len=" + _saLen);

        // P3a: shadow 推送到 Launcher 落盘 + 回调确认
        sm.sendServerMessage("[SaveManager] shadow gate: ok=" + ok + " socket=" + sm.isSocketConnected);
        if (ok && sm.isSocketConnected) {
            pushShadowWithConfirm(sm, mydata);
        }

        return ok;
    }

    /**
     * Phase 1b hook (10a-1 stub / 10b implementation)：
     * preload 收到 launcher load 响应 error 以 "tombstoned:" 开头时调用本方法，
     * 对齐 SOL 墓碑（_deleted=true）。不变式 3：launcher tombstone 清除的唯一路径仍是 shadow。
     */
    public function handlePreloadTombstoned(slot:String):Void {
        // 不变式 3：launcher tombstone → 对齐 SOL 墓碑，清预取
        // （saveAll → shadow 是 tombstone 唯一安全清除路径；这里不碰 launcher tombstone）
        var safeSlot:String = (slot == undefined || slot.length == 0) ? _root.savePath : slot;
        var so:SharedObject = SharedObject.getLocal(safeSlot);
        if (so != null) {
            so.data._deleted = true;
            try { so.flush(); } catch (e:Error) {}
        }
        _prefetchedData = undefined;
        _prefetchedSlot = undefined;
        _prefetchInFlight = false;
        _prefetchGen++;
    }

    public function preload():Void {
        var sm:ServerManager = ServerManager.getInstance();

        // ── 幂等保护: asLoader frame 4 和主FLA frame 63 各调一次 ──
        if (_protocol2Consumed) {
            sm.sendServerMessage("[SaveManager.preload] idempotent skip (protocol 2 already consumed)");
            return;
        }

        sm.sendServerMessage("[SaveManager.preload] savePath=" + _root.savePath);

        // ── Protocol 2 快路径: launcher 存档决议 ──
        var decision:String = _root._launcherSaveDecision;
        if (decision != undefined) {
            var snap:Object = _root._launcherSnapshot;
            var src:String = _root._launcherSnapshotSource;
            var corruptDetail:String = _root._launcherCorruptDetail;
            delete _root._launcherSaveDecision;
            delete _root._launcherSnapshot;
            delete _root._launcherSnapshotSource;
            delete _root._launcherCorruptDetail;

            _protocol2Consumed = true;
            clearPrefetch();
            sm.sendServerMessage("[SaveManager.preload] launcher decision=" + decision + " source=" + src);

            if (decision == "snapshot" && snap != undefined) {
                _root.mydata = snap;
                _bootstrapSnapshot = snap;
                _bootstrapSnapshotSource = (src != undefined) ? src : "unknown";
                return;
            }
            if (decision == "deleted") {
                var soDel:SharedObject = getSO();
                soDel.clear();
                soDel.data._deleted = true;
                var flushOk:Boolean = flushSO(soDel);
                if (!flushOk) {
                    sm.sendServerMessage("[SaveManager.preload] tombstone flush FAILED slot=" + _root.savePath);
                }
                _root.mydata = undefined;
                return;
            }
            if (decision == "empty") {
                _root.mydata = undefined;
                return;
            }
            if (decision == "corrupt") {
                sm.sendServerMessage("[SaveManager.preload] corrupt detail=" +
                    (corruptDetail != undefined ? corruptDetail : "unknown"));
                _deferredResolutionAttempted = true;
                _deferredDecisionSource = "corrupt";
                _skipPrefetch = true;
                // 穿透到同步 SOL 读取
            } else if (decision == "needs_migration") {
                sm.sendServerMessage("[SaveManager.preload] needs_migration/defer_to_flash, sync SOL path");
                _deferredResolutionAttempted = true;
                _deferredDecisionSource = "needs_migration";
                _skipPrefetch = true;
                // 穿透到同步 SOL 读取
            }
        }

        // P3a: 异步预取 — 无论 SOL 状态如何，都向 Launcher 请求 JSON 存档
        // 这确保了"本地档坏了还能靠 Launcher 恢复"的场景
        // Protocol 2 needs_migration/corrupt 路径显式跳过 (_skipPrefetch), 消除启动期 async 等待.
        if (_skipPrefetch) {
            _skipPrefetch = false;
        } else {
            _prefetchGen++;
            var currentGen:Number = _prefetchGen;
            var self:SaveManager = this;
            var requestedSlot:String = _root.savePath;
            if (sm.isSocketConnected) {
                _prefetchInFlight = true;
                sm.sendTaskWithCallback("archive", {op:"load", slot:requestedSlot}, null,
                    function(resp:Object):Void {
                        self._prefetchInFlight = false;
                        if (currentGen != self._prefetchGen) return;
                        if (resp.success != true || typeof resp.data != "string") {
                            // launcher 返回 tombstoned → 对齐 SOL 墓碑，避免"本地无墓碑而launcher已删"的状态分叉
                            if (resp.error != null && String(resp.error).indexOf("tombstoned") == 0) {
                                self.handlePreloadTombstoned(requestedSlot);
                            }
                            return;
                        }
                        var parsed:Object = self._jsonParser.parse(resp.data);
                        if (self._jsonParser.errors.length > 0) return;
                        if (!self.validateMydata(parsed)) return;
                        self._prefetchedData = parsed;
                        self._prefetchedSlot = requestedSlot;
                        sm.sendServerMessage("[SaveManager] prefetch OK slot=" + requestedSlot);
                    }
                );
            }
        }

        // SOL 读取
        var so:SharedObject = getSO();
        var raw:Object = so.data[SAVE_KEY];
        if (raw == undefined) {
            sm.sendServerMessage("[SaveManager.preload] 空槽位，mydata=undefined（Launcher 预取可能恢复）");
            _root.mydata = undefined;
            return;
        }
        _root.mydata = raw;

        // 结构校验：主角储存数据必须存在
        if (raw[0] == undefined) {
            sm.sendServerMessage("[SaveManager.preload] 存档结构异常: mydata[0]=undefined，跳过");
            _root.mydata = undefined;
            return;
        }

        sm.sendServerMessage("[SaveManager.preload] version=" + raw.version + " 角色名=" + raw[0][0] + " 等级=" + raw[0][3]);
        sm.sendServerMessage("[SaveManager.preload] 顶层key: tasks_to_do=" + (so.data.tasks_to_do != undefined) + " 战宠=" + (so.data.战宠 != undefined) + " 商城=" + (so.data.商城已购买物品 != undefined));
        sm.sendServerMessage("[SaveManager.preload] mydata内部: tasks=" + (raw.tasks != undefined) + " pets=" + (raw.pets != undefined) + " shop=" + (raw.shop != undefined));
        var changed:Boolean = migrate(_root.mydata, so.data);
        sm.sendServerMessage("[SaveManager.preload] migrate changed=" + changed + " newVersion=" + _root.mydata.version);
        if (changed) {
            syncTopLevelFromMydata(_root.mydata, so.data);
            if (flushSO(so)) {
                sm.sendServerMessage("[SaveManager.preload] 迁移已持久化");
            }
        }
    }

    public function loadAll():Boolean {
        var sm:ServerManager = ServerManager.getInstance();
        sm.sendServerMessage("[SaveManager.loadAll] savePath=" + _root.savePath);

        // ── Protocol 2: launcher snapshot 快路径 ──
        // snap 已在 preload 经 validator 校验 (launcher C# 侧),
        // 直接喂 loadFromMydata 即可跳过所有 SOL/JSON 合并逻辑.
        if (_bootstrapSnapshot != undefined) {
            var pSnap:Object = _bootstrapSnapshot;
            var pSrc:String = _bootstrapSnapshotSource;
            _bootstrapSnapshot = undefined;
            _bootstrapSnapshotSource = undefined;
            sm.sendServerMessage("[SaveManager.loadAll] using launcher snapshot source=" + pSrc);

            var pOk:Boolean = loadFromMydata(pSnap);
            if (pOk) {
                _deferredResolutionAttempted = false;
                _deferredDecisionSource = undefined;
                _prefetchGen++;
                return true;
            }
            // apply 失败 — source-aware 分流
            if (pSrc == "sol") {
                sm.sendServerMessage("[SaveManager.loadAll] sol snapshot apply failed, fallthrough to native SOL path");
                // fallthrough: _root.mydata 已被 preload 设为 snap, 但 snap 已被此处 apply 失败,
                // 下方 SOL 分支会重新赋值 _root.mydata = soData[SAVE_KEY] 并走原路径 migrate.
            } else {
                sm.sendServerMessage("[SaveManager.loadAll] json_shadow snapshot apply failed, restore error");
                _root._saveRestoreError = true;
                return false;
            }
        }

        // P3a: JSON 优先分支
        if (_prefetchedData != undefined) {
            var solMissing:Boolean = (_root.mydata == undefined);
            var solLastSaved:String = solMissing ? undefined : _root.mydata.lastSaved;
            var jsonLastSaved:String = _prefetchedData.lastSaved;

            var useJson:Boolean = false;
            var solDeleted:Boolean = (getSO().data._deleted == true);
            if (sanitizeSlot(_prefetchedSlot) != sanitizeSlot(_root.savePath)) {
                sm.sendServerMessage("[SaveManager.loadAll] slot 不匹配: prefetch=" + _prefetchedSlot + " savePath=" + _root.savePath);
            } else if (solDeleted) {
                // 墓碑存在 → 此槽位被主动删除，不允许 JSON 恢复
                sm.sendServerMessage("[SaveManager.loadAll] 槽位已删除（墓碑），不从 JSON 恢复");
            } else if (solMissing) {
                // SOL 完全缺失且无墓碑 → JSON 是唯一恢复源
                sm.sendServerMessage("[SaveManager.loadAll] SOL 缺失，尝试 JSON 恢复");
                useJson = true;
            } else if (solLastSaved == undefined) {
                // SOL 存在但无时间戳（刚迁移的存档）→ 保守，用 SOL
                sm.sendServerMessage("[SaveManager.loadAll] SOL 无时间戳，保守走 SOL");
            } else if (jsonLastSaved == undefined || jsonLastSaved < solLastSaved) {
                sm.sendServerMessage("[SaveManager.loadAll] 时间戳检查不通过: json=" + jsonLastSaved + " sol=" + solLastSaved);
            } else {
                useJson = true;
            }

            if (useJson) {
                sm.sendServerMessage("[SaveManager.loadAll] 使用 JSON 权威数据 ts=" + jsonLastSaved);
                var jsonData:Object = _prefetchedData;
                clearPrefetch();

                if (!_applyCore(jsonData)) {
                    sm.sendServerMessage("[SaveManager.loadAll] JSON applyCore 失败，降级 SOL");
                } else {
                    // SO 覆盖层：与 SOL 路径步骤一致
                    var jso:SharedObject = getSO();
                    var jsoData:Object = jso.data;

                    // tasks（优先非空顶层；空顶层回退到 mydata.tasks，并用 mydata[3] 修补旧档主线）
                    applyTaskBundleWithFallback(jsoData, _root.mydata.tasks, "loadAll.json");

                    // 宠物/商城（优先非空顶层；空顶层回退到 mydata）
                    applyPetsBundleWithFallback(jsoData, _root.mydata.pets, "loadAll.json");
                    applyShopBundleWithFallback(jsoData, _root.mydata.shop, "loadAll.json");

                    // lastsave + dirtyMark
                    if (_root.当前玩家总数 == 1) {
                        _root.lastsave = _root.mydata.toString();
                    }
                    _dirtyMark = false;
                    _root.存档系统.dirtyMark = false;

                    // 副作用链 — 严格复用 SOL 路径写法，保持直接调用
                    _root.UpdateTaskProgress();
                    _root.检查任务数据完整性();
                    _root.UI系统.防御性刷新等级经验();
                    _root.发布消息("游戏本地读取成功！");
                    _root.载入新佣兵库数据(0, 0, 0, 0, 0);
                    _root.是否达成任务检测();

                    var _jLen = (_root.tasks_to_do != undefined) ? _root.tasks_to_do.length : 0;
                    var _jpLen = (_root.宠物信息 != undefined) ? _root.宠物信息.length : 0;
                    sm.sendServerMessage("[SaveManager.loadAll] JSON+SO 完成: " + _root.角色名 + " lv" + _root.等级 + " tasks=" + _jLen + " pets=" + _jpLen);
                    _deferredResolutionAttempted = false;
                    _deferredDecisionSource = undefined;
                    _prefetchGen++;
                    return true;
                }
            } else {
                clearPrefetch();
            }
        } else if (sm.isSocketConnected) {
            sm.sendServerMessage("[SaveManager.loadAll] prefetch 未就绪，走 SOL");
        }

        // ─── SOL 路径（原有逻辑完全不变）───

        // 始终从 SO 鲜读
        var so:SharedObject = getSO();
        var soData:Object = so.data;
        _root.mydata = soData[SAVE_KEY];

        // 空槽位 guard
        if (_root.mydata == undefined) {
            sm.sendServerMessage("[SaveManager.loadAll] 空槽位，return false");
            _prefetchGen++;
            return false;
        }

        // 结构校验：主角储存数据必须存在
        if (_root.mydata[0] == undefined) {
            sm.sendServerMessage("[SaveManager.loadAll] 存档结构异常: mydata[0]=undefined，return false");
            _prefetchGen++;
            return false;
        }

        sm.sendServerMessage("[SaveManager.loadAll] version=" + _root.mydata.version + " 角色名=" + _root.mydata[0][0] + " 等级=" + _root.mydata[0][3]);

        // 迁移
        var changed:Boolean = migrate(_root.mydata, soData);
        if (changed) {
            syncTopLevelFromMydata(_root.mydata, soData);
            if (flushSO(so)) {
                sm.sendServerMessage("[SaveManager.loadAll] 迁移已持久化");
            }
        }

        // 解包 mydata 内部数据（主角/装备/设置/物品栏等）
        if (!unpackGameState(_root.mydata)) {
            sm.sendServerMessage("[SaveManager.loadAll] unpackGameState 失败");
            _prefetchGen++;
            return false;
        }

        sm.sendServerMessage("[SaveManager.loadAll] unpack完成: 角色名=" + _root.角色名 + " 等级=" + _root.等级 + " 金钱=" + _root.金钱);

        // 从顶层 key 读取 tasks/pets/shop（优先非空顶层；空顶层回退到 mydata）
        applyTaskBundleWithFallback(soData, _root.mydata.tasks, "loadAll.sol");
        applyPetsBundleWithFallback(soData, _root.mydata.pets, "loadAll.sol");
        applyShopBundleWithFallback(soData, _root.mydata.shop, "loadAll.sol");

        var _ttdLen = (_root.tasks_to_do != undefined) ? _root.tasks_to_do.length : 0;
        sm.sendServerMessage("[SaveManager.loadAll] 顶层tasks: tasks_to_do=" + (soData.tasks_to_do != undefined) + " len=" + _ttdLen);
        sm.sendServerMessage("[SaveManager.loadAll] 顶层pets: 战宠=" + (soData.战宠 != undefined) + " 宠物领养限制=" + soData.宠物领养限制);

        // lastsave 初始化
        if (_root.当前玩家总数 == 1) {
            _root.lastsave = _root.mydata.toString();
        }

        // 刚读取的存档是干净的，重置 dirtyMark
        _dirtyMark = false;
        _root.存档系统.dirtyMark = false;

        // 副作用链
        _root.UpdateTaskProgress();
        _root.检查任务数据完整性();
        _root.UI系统.防御性刷新等级经验();
        _root.发布消息("游戏本地读取成功！");
        _root.载入新佣兵库数据(0, 0, 0, 0, 0);
        _root.是否达成任务检测();

        var _laLen = (_root.tasks_to_do != undefined) ? _root.tasks_to_do.length : 0;
        var _lpLen = (_root.宠物信息 != undefined) ? _root.宠物信息.length : 0;
        sm.sendServerMessage("[SaveManager.loadAll] 完成: 主线进度=" + _root.主线任务进度 + " tasks_to_do.len=" + _laLen + " 宠物数=" + _lpLen);
        _deferredResolutionAttempted = false;
        _deferredDecisionSource = undefined;
        _prefetchGen++;
        return true;
    }

    public function deleteSlot():Void {
        // P3a: 清理预取缓存（防止删档后被内存缓存复活）
        clearPrefetch();

        var so:SharedObject = getSO();
        so.clear();

        // P3a: 写入墓碑——防止 Launcher JSON 复活已删存档
        // 墓碑**仅在 saveAll 写入新数据时清除**，不在 delete 回调中清除。
        // 原因：旧的 inflight shadow 可能晚于 delete 落地，重新写回 JSON 文件；
        // 如果 delete 回调清了墓碑，这个迟到的旧 shadow 就会在下次启动时复活已删存档。
        so.data._deleted = true;
        flushSO(so);

        // 通知 Launcher 删除 shadow JSON（best-effort，墓碑是真正的防线）
        var sm:ServerManager = ServerManager.getInstance();
        if (sm.isSocketConnected) {
            sm.sendTaskWithCallback("archive", {op:"delete", slot:_root.savePath}, null,
                function(resp:Object):Void {
                    sm.sendServerMessage("[SaveManager] shadow delete: " + (resp.success == true));
                }
            );
        }

        // 现有清理
        _root.主角技能表 = [];
        _root.初始化主角技能表();
        _root.主角被动技能 = {};
        _root.物品栏 = initInventory();
        _root.收集品栏 = initCollection();
        _root.同伴数据 = [];
        _root.同伴数 = 0;
        _root.killStats = { total:0, byType:{} };

        // 补充遗漏项（类型与运行时一致）
        _root.宠物信息 = [[], [], [], [], []];
        _root.宠物领养限制 = 5;
        _root.tasks_to_do = [];
        _root.tasks_finished = {};
        _root.task_chains_progress = {};
        _root.主线任务进度 = 0;
        _root.基建系统.infrastructure = {};
        _root.商城已购买物品 = [];
        _root.商城购物车 = [];
        _root.easterEgg = undefined;

        // 缓存层清理
        _root.mydata = undefined;
        if (_root.playerData == undefined) _root.playerData = [];
        _root.playerData[0] = undefined;
        _root.lastsave = "";
        _root.lastsave2 = [];
        _lastSaveHash = "";

        // 禁止在删档→新建角色之间的窗口期意外触发存盘
        _root.允许存档 = false;
        _dirtyMark = false;
        _root.存档系统.dirtyMark = false;
    }

    public function hasSaveData():Boolean {
        // Protocol 2: launcher snapshot 已就绪 → 肯定有存档
        if (_bootstrapSnapshot != undefined) return true;

        var so:SharedObject = getSO();
        var raw:Object = so.data[SAVE_KEY];
        if (raw != undefined && raw[0] != undefined && raw[0][0] != undefined) {
            return true;
        }
        // 墓碑检查：此槽位被主动删除，不允许 JSON 恢复
        if (so.data._deleted == true) return false;
        // SOL 无有效数据 — 检查 Launcher 预取是否有可用恢复数据
        if (_prefetchedData != undefined && sanitizeSlot(_prefetchedSlot) == sanitizeSlot(_root.savePath)) {
            ServerManager.getInstance().sendServerMessage(
                "[SaveManager.hasSaveData] SOL 无数据，但 Launcher 预取可用 slot=" + _prefetchedSlot);
            return true;
        }

        // Protocol 2 双重失败升格: launcher 决议 needs_migration/corrupt, 本地 SOL 也读不出 →
        // 不能误送"重新游戏确认", 设 _saveRestoreError = true 让 frame 128/:3198/:3363 走"存档损坏" UI.
        if (_deferredResolutionAttempted) {
            var src:String = (_deferredDecisionSource != undefined) ? _deferredDecisionSource : "unknown";
            _deferredResolutionAttempted = false;
            _deferredDecisionSource = undefined;
            _root._saveRestoreError = true;
            ServerManager.getInstance().sendServerMessage(
                "[SaveManager.hasSaveData] deferred resolution double failure (source=" + src + ") → restore error");
        }
        return false;
    }

    /**
     * Launcher 异步预取是否正在进行中（SOL 缺失时帧脚本可轮询此状态）
     * true = 预取请求已发出且尚未返回（_prefetchInFlight），SOL 缺失，且未被主动删除
     * Protocol 2 下 snapshot 已就绪, 无需异步等待, 立即返回 false.
     */
    public function isRecoveryPending():Boolean {
        if (_bootstrapSnapshot != undefined) return false;
        if (_root.mydata != undefined) return false;
        if (_prefetchedData != undefined) return false;
        if (getSO().data._deleted == true) return false;
        return _prefetchInFlight;
    }

    public function newCharacter():Boolean {
        // deleteSlot() 禁用了存档，新建角色时恢复
        _root.允许存档 = true;

        // 初始装备
        if (_root.上装装备 != "") {
            _root.物品栏.装备栏.add("上装装备", BaseItem.create(_root.上装装备, 1));
        }
        if (_root.下装装备 != "") {
            _root.物品栏.装备栏.add("下装装备", BaseItem.create(_root.下装装备, 1));
        }
        if (_root.脚部装备 != "") {
            _root.物品栏.装备栏.add("脚部装备", BaseItem.create(_root.脚部装备, 1));
        }

        // 难度模式
        if (_root.难度 == "逆天模式（简单）") {
            _root.difficultyMode = 1;
        } else if (_root.难度 == "挑战模式（自限）") {
            _root.difficultyMode = 2;
        } else {
            _root.difficultyMode = 0;
        }

        _root.上装装备 = undefined;
        _root.下装装备 = undefined;
        _root.脚部装备 = undefined;
        _root.难度 = undefined;

        // 存档数据
        _root.mydata = packGameState();
        _root.金钱 = 0;
        _root.虚拟币 = 0;
        _root.宠物信息 = [[], [], [], [], []];
        _root.宠物领养限制 = 5;

        // 全局加成
        _root.全局健身HP加成 = 0;
        _root.全局健身MP加成 = 0;
        _root.全局健身空攻加成 = 0;
        _root.全局健身内力加成 = 0;
        _root.全局健身防御加成 = 0;

        // 基建
        _root.基建系统.infrastructure = {};

        // 击杀统计
        _root.killStats = { total:0, byType:{} };

        // 清空物品获取方式的动态发现集合
        ItemObtainIndex.getInstance().clearDynamicDiscoveries();

        _root.soundEffectManager.stopBGMForTransition();

        // 新出生标志
        _root.新出生 = false;

        // 延迟触发 SceneReady
        _root.帧计时器.添加单次任务(function() {
            EventBus.instance.publish("SceneReady");
        }, 30);

        _root.载入关卡数据("无限过图", "data/stages/特殊/教学关卡.xml");
        _root.场景进入位置名 = "出生地";
        _root.淡出动画.淡出跳转帧("wuxianguotu_1");
        return true;
    }

    // ==================== 数据组包/解包 ====================

    public function packGameState():Object {
        _root.身价 = _root.基础身价值 * _root.等级;

        var 主角储存数据:Array = [
            _root.角色名, _root.性别, _root.金钱, _root.等级, _root.经验值,
            _root.身高, _root.技能点数, _root.玩家称号, _root.身价, _root.虚拟币,
            _root.键值设定, _root.difficultyMode, _root.佣兵是否出战信息, _root.easterEgg
        ];

        var 装备储存数据:Array = [
            _root.脸型, _root.发型,
            null, null, null, null, null, null, null, null, null, null, null,
            null, null, null,
            _root.快捷技能栏1, _root.快捷技能栏2, _root.快捷技能栏3, _root.快捷技能栏4,
            _root.快捷技能栏5, _root.快捷技能栏6, _root.快捷技能栏7, _root.快捷技能栏8,
            _root.快捷技能栏9, _root.快捷技能栏10, _root.快捷技能栏11, _root.快捷技能栏12,
            _root.快捷物品栏4
        ];

        var 物品储存数据:Object = {
            背包:   _root.物品栏.背包.toObject(),
            装备栏: _root.物品栏.装备栏.toObject(),
            药剂栏: _root.物品栏.药剂栏.toObject(),
            仓库:   _root.物品栏.仓库.toObject(),
            战备箱: _root.物品栏.战备箱.toObject()
        };

        var 收集品储存数据:Object = {
            材料: _root.收集品栏.材料.toObject(),
            情报: _root.收集品栏.情报.toObject()
        };

        if (_root.killStats == null) {
            _root.killStats = { total:0, byType:{} };
        }

        var 其他存储数据:Object = {
            设置: packSettings(),
            击杀统计: _root.killStats,
            物品来源缓存: ItemObtainIndex.getInstance().exportToSave()
        };

        var mydata:Object = {};
        mydata.version = LATEST_VERSION;
        mydata[0] = 主角储存数据;
        mydata[1] = 装备储存数据;
        mydata[2] = null;
        mydata[3] = _root.主线任务进度;
        mydata[4] = [_root.同伴数据, _root.同伴数];
        mydata[5] = _root.主角技能表;
        mydata[6] = null;
        mydata[7] = [_root.全局健身HP加成, _root.全局健身MP加成, _root.全局健身空攻加成, _root.全局健身防御加成, _root.全局健身内力加成];
        mydata.inventory = 物品储存数据;
        mydata.collection = 收集品储存数据;
        mydata.infrastructure = _root.基建系统.infrastructure;
        mydata.lastSaved = packTimestamp();
        mydata.others = 其他存储数据;

        // 归一化：折入 tasks/pets/shop
        mydata.tasks = {
            tasks_to_do: _root.tasks_to_do,
            tasks_finished: _root.tasks_finished,
            task_chains_progress: _root.task_chains_progress
        };
        mydata.pets = {
            宠物信息: _root.宠物信息,
            宠物领养限制: _root.宠物领养限制
        };
        mydata.shop = {
            商城已购买物品: _root.商城已购买物品,
            商城购物车: _root.商城购物车
        };

        // 预留命名空间 — 透传已有数据，保证往返不丢
        if (_root._saveExt == undefined) _root._saveExt = {};
        mydata.ext = _root._saveExt;
        mydata.reserved = {};

        return mydata;
    }

    // ==================== JSON 校验/装载 ====================

    /**
     * 校验 mydata 结构完整性 — 覆盖 unpackGameState + loadFromMydata 消费的全部字段。
     * 用于拦截截断/损坏的 JSON 数据（含边界截断导致尾部 tasks/pets/shop 丢失的场景）。
     */
    private function validateMydata(mydata:Object):Boolean {
        if (mydata == undefined) return false;
        if (mydata.version != "3.0") return false;
        if (mydata.lastSaved == undefined) return false;

        // 数组槽位（unpackGameState 消费的最大索引+1）
        if (!(mydata[0] instanceof Array) || mydata[0].length < 14) return false;
        if (!(mydata[1] instanceof Array) || mydata[1].length < 28) return false;
        if (mydata[3] == undefined) return false;
        if (!(mydata[4] instanceof Array) || mydata[4].length < 2) return false;
        if (!(mydata[5] instanceof Array)) return false;
        if (!(mydata[7] instanceof Array) || mydata[7].length < 5) return false;

        // 对象字段
        if (mydata.inventory == undefined) return false;
        if (mydata.inventory.背包 == undefined) return false;
        if (mydata.inventory.装备栏 == undefined) return false;
        if (mydata.inventory.药剂栏 == undefined) return false;
        if (mydata.inventory.仓库 == undefined) return false;
        if (mydata.inventory.战备箱 == undefined) return false;
        if (mydata.collection == undefined) return false;
        if (mydata.collection.材料 == undefined) return false;
        if (mydata.collection.情报 == undefined) return false;
        if (mydata.infrastructure == undefined) return false;

        // 尾部字段校验 — 每个 loadFromMydata 消费的子字段都必须存在
        if (mydata.tasks == undefined) return false;
        if (mydata.tasks.tasks_to_do == undefined) return false;
        if (mydata.tasks.tasks_finished == undefined) return false;
        if (mydata.tasks.task_chains_progress == undefined) return false;
        if (mydata.pets == undefined) return false;
        if (mydata.pets.宠物信息 == undefined) return false;
        if (mydata.pets.宠物领养限制 == undefined) return false;
        if (mydata.shop == undefined) return false;
        if (mydata.shop.商城已购买物品 == undefined) return false;
        if (mydata.shop.商城购物车 == undefined) return false;

        return true;
    }

    /**
     * 无副作用的核心装载 — loadAll JSON 分支和 loadFromMydata 的共用内核。
     * 只做：validate → 设 _root.mydata → 归一化 → unpackGameState。
     * 不做：tasks/pets/shop、dirtyMark、副作用链。
     */
    private function _applyCore(mydata:Object):Boolean {
        if (!validateMydata(mydata)) return false;
        _root.mydata = mydata;
        if (!(mydata[0][10] instanceof Array)) mydata[0][10] = [];
        if (!(mydata[0][12] instanceof Array)) mydata[0][12] = [];
        return unpackGameState(mydata);
    }

    /**
     * 独立公共 API — 从 mydata 对象恢复完整游戏状态。
     * 包含 tasks/pets/shop 处理 + 副作用链（带防御性 typeof 检查）。
     * loadAll 的 JSON 分支不调用此方法，而是用 _applyCore + SO 覆盖 + 副作用。
     */
    public function loadFromMydata(mydata:Object):Boolean {
        var sm:ServerManager = ServerManager.getInstance();

        if (!_applyCore(mydata)) {
            sm.sendServerMessage("[SaveManager.loadFromMydata] applyCore failed");
            return false;
        }

        // tasks（防御性默认化 — validateMydata 已保证字段存在，fallback 是二次防御）
        var t:Object = mydata.tasks;
        _root.tasks_to_do = (t != undefined && t.tasks_to_do != undefined) ? t.tasks_to_do : [];
        _root.tasks_finished = (t != undefined && t.tasks_finished != undefined) ? t.tasks_finished : {};
        _root.task_chains_progress = (t != undefined && t.task_chains_progress != undefined) ? t.task_chains_progress : {};

        // 宠物
        var p:Object = mydata.pets;
        _root.宠物信息 = (p != undefined && p.宠物信息 != undefined) ? p.宠物信息 : [[], [], [], [], []];
        _root.宠物领养限制 = (p != undefined && p.宠物领养限制 != undefined) ? p.宠物领养限制 : 5;

        // 商城
        var sh:Object = mydata.shop;
        _root.商城已购买物品 = (sh != undefined && sh.商城已购买物品 != undefined) ? sh.商城已购买物品 : [];
        _root.商城购物车 = (sh != undefined && sh.商城购物车 != undefined) ? sh.商城购物车 : [];

        // lastsave
        if (_root.当前玩家总数 == 1) {
            _root.lastsave = _root.mydata.toString();
        }
        // dirtyMark
        _dirtyMark = false;
        _root.存档系统.dirtyMark = false;

        // 副作用链（防御性检查 — loadFromMydata 是独立公共 API，可能在启动早期调用）
        if (typeof _root.UpdateTaskProgress == "function") _root.UpdateTaskProgress();
        if (typeof _root.检查任务数据完整性 == "function") _root.检查任务数据完整性();
        if (_root.UI系统 != undefined && typeof _root.UI系统.防御性刷新等级经验 == "function") _root.UI系统.防御性刷新等级经验();
        _root.发布消息("游戏本地读取成功！");
        if (typeof _root.载入新佣兵库数据 == "function") _root.载入新佣兵库数据(0, 0, 0, 0, 0);
        if (typeof _root.是否达成任务检测 == "function") _root.是否达成任务检测();

        sm.sendServerMessage("[SaveManager.loadFromMydata] OK: " + _root.角色名 + " lv" + _root.等级);
        return true;
    }

    /**
     * 解包 mydata 内部数据到 _root.*（纯 mydata 内部，不含 tasks/pets/shop）
     * tasks/pets/shop 由 loadAll() 走“优先非空顶层，空壳回退 mydata”的合并逻辑
     */
    public function unpackGameState(mydata:Object):Boolean {
        if (mydata == undefined) return false;

        var 主角储存数据:Array = mydata[0];
        var 装备储存数据:Array = mydata[1];
        var 健身储存数据:Array = mydata[7];

        if (主角储存数据 == undefined) return false;

        // 主角数据
        _root.角色名 = 主角储存数据[0];
        _root.性别 = 主角储存数据[1];
        _root.金钱 = Math.floor(Number(主角储存数据[2]));
        _root.等级 = Math.floor(Number(主角储存数据[3]));
        _root.经验值 = Math.floor(Number(主角储存数据[4]));
        _root.虚拟币 = Math.floor(Number(主角储存数据[9]));
        _root.身高 = Math.floor(Number(主角储存数据[5]));
        _root.技能点数 = Math.floor(Number(主角储存数据[6]));
        _root.玩家称号 = 主角储存数据[7];
        _root.身价 = Math.floor(Number(主角储存数据[8]));
        _root.easterEgg = 主角储存数据[13];

        // 健身加成
        _root.全局健身HP加成 = Math.floor(Number(健身储存数据[0]));
        _root.全局健身MP加成 = Math.floor(Number(健身储存数据[1]));
        _root.全局健身空攻加成 = Math.floor(Number(健身储存数据[2]));
        _root.全局健身防御加成 = Math.floor(Number(健身储存数据[3]));
        _root.全局健身内力加成 = Math.floor(Number(健身储存数据[4]));
        if (isNaN(_root.全局健身HP加成)) _root.全局健身HP加成 = 0;
        if (isNaN(_root.全局健身MP加成)) _root.全局健身MP加成 = 0;
        if (isNaN(_root.全局健身空攻加成)) _root.全局健身空攻加成 = 0;
        if (isNaN(_root.全局健身内力加成)) _root.全局健身内力加成 = 0;
        if (isNaN(_root.全局健身防御加成)) _root.全局健身防御加成 = 0;

        // 键值设定
        if (主角储存数据[10].length > 0) {
            _root.键值设定 = 主角储存数据[10];
        }

        // 难度模式
        if (主角储存数据[11] >= 0) {
            _root.difficultyMode = 主角储存数据[11];
        } else {
            _root.difficultyMode = 0;
        }

        // 佣兵出战信息
        if (主角储存数据[12].length > 0) {
            _root.佣兵是否出战信息 = 主角储存数据[12];
            var i:Number = 0;
            while (i < _root.佣兵是否出战信息.length) {
                if (_root.佣兵是否出战信息[i] == -1) {
                    _root.佣兵是否出战信息[i] = 1;
                }
                i++;
            }
        }

        // 经验值校验
        var tmp经验值:Number = _root.根据等级得升级所需经验(_root.等级);
        if (tmp经验值 < _root.经验值) {
            _root.经验值 = tmp经验值;
        }
        tmp经验值 = _root.根据等级得升级所需经验(_root.等级 - 1);
        if (tmp经验值 > _root.经验值) {
            _root.经验值 = tmp经验值;
        }

        // 强化等级重置
        _root.长枪强化等级 = undefined;
        _root.手枪强化等级 = undefined;
        _root.手枪2强化等级 = undefined;
        _root.刀强化等级 = undefined;

        // 装备数据
        _root.脸型 = 装备储存数据[0];
        _root.发型 = 装备储存数据[1];
        _root.快捷技能栏1 = 装备储存数据[16];
        _root.快捷技能栏2 = 装备储存数据[17];
        _root.快捷技能栏3 = 装备储存数据[18];
        _root.快捷技能栏4 = 装备储存数据[19];
        _root.快捷技能栏5 = 装备储存数据[20];
        _root.快捷技能栏6 = 装备储存数据[21];
        _root.快捷技能栏7 = 装备储存数据[22];
        _root.快捷技能栏8 = 装备储存数据[23];
        _root.快捷技能栏9 = 装备储存数据[24];
        _root.快捷技能栏10 = 装备储存数据[25];
        _root.快捷技能栏11 = 装备储存数据[26];
        _root.快捷技能栏12 = 装备储存数据[27];

        // 同伴
        _root.同伴数据 = mydata[4][0];
        _root.同伴数 = Math.floor(Number(mydata[4][1]));

        // 技能表
        _root.主角技能表 = mydata[5];
        _root.更新主角被动技能();

        // 物品栏
        _root.物品栏 = {
            背包: new ArrayInventory(mydata.inventory.背包, 50),
            装备栏: new EquipmentInventory(mydata.inventory.装备栏),
            药剂栏: new DrugInventory(mydata.inventory.药剂栏, 4),
            仓库: new ArrayInventory(mydata.inventory.仓库, 1200),
            战备箱: new ArrayInventory(mydata.inventory.战备箱, 400)
        };

        // 收集品栏
        _root.收集品栏 = {
            材料: new DictCollection(mydata.collection.材料),
            情报: new InformationCollection(mydata.collection.情报)
        };

        // 基建
        _root.基建系统.infrastructure = mydata.infrastructure;

        // 其他数据
        if (mydata.others) {
            if (mydata.others.设置) {
                applySettings(mydata.others.设置);
            }
            if (mydata.others.击杀统计) {
                _root.killStats = mydata.others.击杀统计;
            } else {
                _root.killStats = { total:0, byType:{} };
            }
            if (mydata.others.物品来源缓存) {
                ItemObtainIndex.getInstance().loadFromSave(mydata.others.物品来源缓存);
            }
        } else {
            _root.killStats = { total:0, byType:{} };
        }

        // 预留命名空间恢复
        _root._saveExt = (mydata.ext != undefined) ? mydata.ext : {};

        // 主线任务进度（从 mydata[3]，后续 loadAll 会从 task_chains_progress 覆盖）
        _root.主线任务进度 = Math.floor(Number(mydata[3]));

        if (_root.角色名 == undefined) {
            _root.发布消息("游戏本地无存盘！");
            return false;
        }

        return true;
    }

    // ==================== 商城即时写入 ====================

    public function saveShopCart():Void {
        var so:SharedObject = getSO();
        var soData:Object = so.data;
        ensureShopNode(soData);
        soData[SAVE_KEY].shop.商城购物车 = _root.商城购物车;
        soData.商城购物车 = _root.商城购物车;
        flushSO(so);
    }

    public function loadShopCart():Void {
        var soData:Object = getSO().data;
        var nestedShop:Object = (soData[SAVE_KEY] != undefined) ? soData[SAVE_KEY].shop : undefined;
        _root.商城购物车 = preferListLayer(soData.商城购物车,
                                          nestedShop != undefined ? nestedShop.商城购物车 : undefined,
                                          []);
    }

    public function saveShopPurchased():Void {
        var so:SharedObject = getSO();
        var soData:Object = so.data;
        ensureShopNode(soData);
        soData[SAVE_KEY].shop.商城已购买物品 = _root.商城已购买物品;
        soData.商城已购买物品 = _root.商城已购买物品;
        flushSO(so);
    }

    public function loadShopPurchased():Void {
        var soData:Object = getSO().data;
        var nestedShop:Object = (soData[SAVE_KEY] != undefined) ? soData[SAVE_KEY].shop : undefined;
        _root.商城已购买物品 = preferListLayer(soData.商城已购买物品,
                                            nestedShop != undefined ? nestedShop.商城已购买物品 : undefined,
                                            []);
    }

    // ==================== Dirty 追踪 ====================

    public function markDirty():Void {
        _dirtyMark = true;
    }

    public function isDirty():Boolean {
        return _dirtyMark;
    }

    // ==================== 迁移 ====================

    /**
     * 迁移存档数据。纯内存变换，不负责 flush。
     * 调用方（preload/loadAll）负责在 changed 时 syncTopLevel + flush。
     * @return 是否有变更
     */
    public function migrate(mydata:Object, soData:Object):Boolean {
        if (mydata == undefined) return false;
        var changed:Boolean = false;
        var sm:ServerManager = ServerManager.getInstance();

        // Stage 1: unknown → 2.6（委托旧迁移函数）
        if (isNaN(mydata.version)) {
            sm.sendServerMessage("SaveManager: 将存档从未知版本更新至2.6");
            if (mydata[2] && !mydata.inventory) {
                _root.存档系统.convertInventory(mydata);
            }
            if (mydata.infrastructure == null) {
                mydata.infrastructure = {};
            }
            mydata.version = "2.6";
            changed = true;
        }

        // Stage 2: 2.6 → 2.7（委托旧迁移函数 + 修复：补上 version）
        if (mydata.version == "2.6") {
            sm.sendServerMessage("SaveManager: 将存档从2.6更新至2.7");
            _root.存档系统.convert_2_6(mydata);
            mydata.version = "2.7";
            changed = true;
        }

        // Stage 3: 2.7 → 3.0（归一化：拷贝顶层 key 到 mydata 内部）
        if (mydata.version == "2.7") {
            sm.sendServerMessage("SaveManager: 将存档从2.7更新至3.0");
            convert_2_7_to_3_0(mydata, soData);
            mydata.version = "3.0";
            changed = true;
        }

        return changed;
    }

    /**
     * 2.7 → 3.0 迁移：将顶层 key 拷贝到 mydata 内部
     * 顶层 key 为 undefined 时用默认值
     */
    private function convert_2_7_to_3_0(mydata:Object, soData:Object):Void {
        if (mydata.tasks == undefined) {
            mydata.tasks = {
                tasks_to_do:          soData.tasks_to_do || [],
                tasks_finished:       soData.tasks_finished || {},
                task_chains_progress: buildMigratedTaskChainsProgress(soData.task_chains_progress, mydata[3])
            };
        }
        if (mydata.pets == undefined) {
            mydata.pets = {
                宠物信息:    soData.战宠 || [[], [], [], [], []],
                宠物领养限制: (soData.宠物领养限制 != undefined) ? soData.宠物领养限制 : 5
            };
        }
        if (mydata.shop == undefined) {
            mydata.shop = {
                商城已购买物品: soData.商城已购买物品 || [],
                商城购物车:    soData.商城购物车 || []
            };
        }
    }

    public function migrateAndSync(mydata:Object, soData:Object):Void {
        migrate(mydata, soData);
        syncTopLevelFromMydata(mydata, soData);
    }

    public function syncTopLevelFromMydata(mydata:Object, soData:Object):Void {
        if (mydata == undefined) return;
        if (mydata.tasks != undefined) {
            ensureLegacyMainlineInTasks(mydata.tasks, mydata[3]);
            soData.tasks_to_do = mydata.tasks.tasks_to_do;
            soData.tasks_finished = mydata.tasks.tasks_finished;
            soData.task_chains_progress = mydata.tasks.task_chains_progress;
        }
        if (mydata.pets != undefined) {
            soData.战宠 = mydata.pets.宠物信息;
            soData.宠物领养限制 = mydata.pets.宠物领养限制;
        }
        if (mydata.shop != undefined) {
            soData.商城已购买物品 = mydata.shop.商城已购买物品;
            soData.商城购物车 = mydata.shop.商城购物车;
        }
    }

    private function buildMigratedTaskChainsProgress(source:Object, legacyMainValue:Object):Object {
        var result:Object = {};
        var key:String;
        if (source != undefined) {
            for (key in source) {
                result[key] = source[key];
            }
        }
        ensureLegacyMainlineInTasks({ task_chains_progress: result }, legacyMainValue);
        return result;
    }

    private function ensureLegacyMainlineInTasks(tasks:Object, legacyMainValue:Object):Void {
        if (tasks == undefined) return;
        if (tasks.task_chains_progress == undefined) {
            tasks.task_chains_progress = {};
        }
        var legacyMain:Number = Math.floor(Number(legacyMainValue));
        if (tasks.task_chains_progress.主线 == undefined && !isNaN(legacyMain)) {
            tasks.task_chains_progress.主线 = legacyMain;
        }
    }

    private function hasTaskEntries(value:Object):Boolean {
        if (value == undefined) return false;
        if (value.length != undefined) {
            return value.length > 0;
        }
        for (var key:String in value) {
            return true;
        }
        return false;
    }

    private function preferTaskLayer(primary:Object, fallback:Object, defaultValue:Object):Object {
        if (primary != undefined) {
            if (hasTaskEntries(primary) || fallback == undefined || !hasTaskEntries(fallback)) {
                return primary;
            }
        }
        if (fallback != undefined) return fallback;
        return defaultValue;
    }

    private function applyTaskBundleWithFallback(topData:Object, nestedTasks:Object, scope:String):Void {
        var nested:Object = (nestedTasks != undefined) ? nestedTasks : {};
        _root.tasks_to_do = preferTaskLayer(topData != undefined ? topData.tasks_to_do : undefined,
                                            nested.tasks_to_do, []);
        _root.tasks_finished = preferTaskLayer(topData != undefined ? topData.tasks_finished : undefined,
                                               nested.tasks_finished, {});
        _root.task_chains_progress = preferTaskLayer(topData != undefined ? topData.task_chains_progress : undefined,
                                                     nested.task_chains_progress, {});
        ensureLegacyMainlineInTasks({ task_chains_progress: _root.task_chains_progress }, _root.主线任务进度);
        if (_root.tasks_to_do == undefined) _root.tasks_to_do = [];
        if (_root.tasks_finished == undefined) _root.tasks_finished = {};
        if (_root.task_chains_progress == undefined) _root.task_chains_progress = {};
        if (_root.task_chains_progress.主线 == undefined) {
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 主线任务链缺失且无法从 mydata[3] 回填");
        }
    }

    private function hasListEntries(value:Object):Boolean {
        return value != undefined && value.length != undefined && value.length > 0;
    }

    private function preferListLayer(primary:Object, fallback:Object, defaultValue:Object):Object {
        if (primary != undefined) {
            if (hasListEntries(primary) || fallback == undefined || !hasListEntries(fallback)) {
                return primary;
            }
        }
        if (fallback != undefined) return fallback;
        return defaultValue;
    }

    private function hasPetEntries(value:Object):Boolean {
        if (value == undefined || value.length == undefined) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var pet:Object = value[i];
            if (pet == undefined) continue;
            if (pet.length != undefined) {
                if (pet.length > 0) return true;
            } else if (hasTaskEntries(pet)) {
                return true;
            }
        }
        return false;
    }

    private function preferPetsInfoLayer(primary:Object, fallback:Object, defaultValue:Object):Object {
        if (primary != undefined) {
            if (hasPetEntries(primary) || fallback == undefined || !hasPetEntries(fallback)) {
                return primary;
            }
        }
        if (fallback != undefined) return fallback;
        return defaultValue;
    }

    private function defaultPetsInfo():Array {
        return [[], [], [], [], []];
    }

    private function applyPetsBundleWithFallback(topData:Object, nestedPets:Object, scope:String):Void {
        var nested:Object = (nestedPets != undefined) ? nestedPets : {};
        var topPets:Object = (topData != undefined) ? topData.战宠 : undefined;
        var nestedPetsInfo:Object = nested.宠物信息;
        var useTopPets:Boolean = topPets != undefined
            && (hasPetEntries(topPets) || nestedPetsInfo == undefined || !hasPetEntries(nestedPetsInfo));

        _root.宠物信息 = preferPetsInfoLayer(topPets, nestedPetsInfo, defaultPetsInfo());
        if (useTopPets) {
            _root.宠物领养限制 = (topData != undefined && topData.宠物领养限制 != undefined)
                ? topData.宠物领养限制
                : (nested.宠物领养限制 != undefined ? nested.宠物领养限制 : 5);
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 宠物从顶层读取");
        } else if (nestedPetsInfo != undefined) {
            _root.宠物领养限制 = (nested.宠物领养限制 != undefined) ? nested.宠物领养限制 : 5;
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 顶层宠物为空，回退 mydata.pets");
        } else {
            _root.宠物领养限制 = (topData != undefined && topData.宠物领养限制 != undefined)
                ? topData.宠物领养限制
                : 5;
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 宠物用默认值");
        }
    }

    private function applyShopBundleWithFallback(topData:Object, nestedShop:Object, scope:String):Void {
        var nested:Object = (nestedShop != undefined) ? nestedShop : {};
        var topPurchased:Object = (topData != undefined) ? topData.商城已购买物品 : undefined;
        var topCart:Object = (topData != undefined) ? topData.商城购物车 : undefined;
        var nestedPurchased:Object = nested.商城已购买物品;
        var nestedCart:Object = nested.商城购物车;

        _root.商城已购买物品 = preferListLayer(topPurchased, nestedPurchased, []);
        _root.商城购物车 = preferListLayer(topCart, nestedCart, []);
        if (topPurchased != undefined && !hasListEntries(topPurchased) && hasListEntries(nestedPurchased)) {
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 顶层商城已购买物品为空，回退 mydata.shop");
        }
        if (topCart != undefined && !hasListEntries(topCart) && hasListEntries(nestedCart)) {
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 顶层商城购物车为空，回退 mydata.shop");
        }
    }

    // ==================== 设置/初始化 ====================

    public function packSettings():Object {
        var ws:WeatherSystem = WeatherSystem.getInstance();
        var sem:Object = _root.soundEffectManager;
        return {
            setGlobalVolume: sem.getGlobalVolume(),
            setBGMVolume: sem.getBGMVolume(),
            性能等级上限: _root.帧计时器.性能等级上限,
            是否阴影: _root.是否阴影,
            是否视觉元素: _root.是否视觉元素,
            是否打击数字特效: _root.是否打击数字特效,
            cameraZoomToggle: _root.cameraZoomToggle,
            basicZoomScale: _root.basicZoomScale,
            开启昼夜系统: ws.enableDayNightCycle,
            暂停昼夜系统: ws.pauseDayNightCycle,
            使用滤镜渲染: ws.useFilterRendering,
            立绘类型: _root.立绘类型,
            jukeboxOverride: sem.getJukeboxOverride(),
            jukeboxTrueRandom: sem.getTrueRandom(),
            jukeboxPlayMode: sem.getPlayMode()
        };
    }

    public function applySettings(s:Object):Void {
        if (!s) return;
        if (!isNaN(s.setGlobalVolume)) _root.soundEffectManager.setGlobalVolume(s.setGlobalVolume);
        if (!isNaN(s.setBGMVolume)) _root.soundEffectManager.setBGMVolume(s.setBGMVolume);
        if (!isNaN(s.性能等级上限)) {
            var cap:Number = Math.round(s.性能等级上限);
            cap = (cap >= 2) ? 1 : (cap < 0) ? 0 : cap;
            _root.帧计时器.性能等级上限 = cap;
        }
        if (s.cameraZoomToggle || s.cameraZoomToggle === false) _root.cameraZoomToggle = s.cameraZoomToggle;
        if (!isNaN(s.basicZoomScale)) _root.basicZoomScale = s.basicZoomScale;
        if (s.是否阴影 || s.是否阴影 === false) _root.是否阴影 = s.是否阴影;
        if (s.是否视觉元素 || s.是否视觉元素 === false) _root.是否视觉元素 = s.是否视觉元素;
        if (s.是否打击数字特效 || s.是否打击数字特效 === false) _root.是否打击数字特效 = s.是否打击数字特效;
        var ws:WeatherSystem = WeatherSystem.getInstance();
        if (s.开启昼夜系统 || s.开启昼夜系统 === false) ws.enableDayNightCycle = s.开启昼夜系统;
        if (s.暂停昼夜系统 || s.暂停昼夜系统 === false) ws.pauseDayNightCycle = s.暂停昼夜系统;
        if (s.使用滤镜渲染 || s.使用滤镜渲染 === false) ws.useFilterRendering = s.使用滤镜渲染;
        if (s.立绘类型) _root.立绘类型 = s.立绘类型;
        var sem:Object = _root.soundEffectManager;
        if (s.jukeboxOverride || s.jukeboxOverride === false) sem.setJukeboxOverride(s.jukeboxOverride);
        if (s.jukeboxTrueRandom || s.jukeboxTrueRandom === false) sem.setTrueRandom(s.jukeboxTrueRandom);
        if (s.jukeboxPlayMode) sem.setPlayMode(s.jukeboxPlayMode);
    }

    public function initInventory():Object {
        return {
            背包: new ArrayInventory(null, 50),
            装备栏: new EquipmentInventory(null),
            药剂栏: new DrugInventory(null, 4),
            仓库: new ArrayInventory(null, 1200),
            战备箱: new ArrayInventory(null, 400)
        };
    }

    public function initCollection():Object {
        return {
            材料: new DictCollection(null),
            情报: new InformationCollection(null)
        };
    }

    // ==================== SO 访问 ====================

    public function getSOData():Object {
        return getSO().data;
    }

    // ==================== Shadow 推送 ====================

    /**
     * 将 mydata 推送到 Launcher 做 shadow 备份。
     * 使用 fire-and-forget 模式：推送失败不影响 SOL 存盘结果。
     *
     * 实现要点：
     *   - 用 LiteJSON（无缓存）单独 stringify mydata，避免 FastJSON 缓存投毒
     *   - 手动拼外层 JSON 字符串，避免 sendTaskToNode 对深层嵌套对象二次 stringify
     *   - 直接调用 sendSocketMessage 发送，绕过 FastJSON 路径
     */
    private function pushShadow(sm:ServerManager, mydata:Object):Void {
        sm.sendServerMessage("[SaveManager] pushShadow enter");
        var dataJson:String = _jsonParser.stringify(mydata);
        if (dataJson == null || dataJson == "null") {
            sm.sendServerMessage("[SaveManager] shadow skipped: stringify returned " + dataJson);
            return;
        }
        sm.sendServerMessage("[SaveManager] shadow stringify ok, len=" + dataJson.length);

        // 手动拼装完整消息 JSON（外层结构简单，无需序列化器）
        var slot:String = _root.savePath;
        var msg:String = "{\"task\":\"archive\",\"payload\":{\"op\":\"shadow\",\"slot\":\"" + slot + "\",\"data\":" + dataJson + "}}";
        var ok:Boolean = sm.sendSocketMessage(msg);
        sm.sendServerMessage("[SaveManager] shadow sent slot=" + slot + " ok=" + ok);
    }

    private function pushShadowWithConfirm(sm:ServerManager, mydata:Object):Void {
        var dataJson:String = _jsonParser.stringify(mydata);
        if (dataJson == null || dataJson == "null") return;
        sm.sendTaskWithCallback("archive",
            {op:"shadow", slot:_root.savePath, data:dataJson}, null,
            function(resp:Object):Void {
                sm.sendServerMessage("[SaveManager] shadow confirm: " + (resp.success == true));
            }
        );
    }

    // ==================== 私有方法 ====================

    /**
     * 与 ArchiveTask.SanitizeSlotName 对齐的槽位名规范化。
     * 非法字符（非 a-z A-Z 0-9 _ -）替换为 _。
     */
    private function sanitizeSlot(slot:String):String {
        if (slot == undefined || slot.length == 0) return "default";
        var result:String = "";
        var i:Number = 0;
        while (i < slot.length) {
            var c:Number = slot.charCodeAt(i);
            // a-z: 97-122, A-Z: 65-90, 0-9: 48-57, _: 95, -: 45
            if ((c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95 || c == 45) {
                result += slot.charAt(i);
            } else {
                result += "_";
            }
            i++;
        }
        return (result.length == 0) ? "default" : result;
    }

    private function getSO():SharedObject {
        return SharedObject.getLocal(_root.savePath);
    }

    /**
     * flush SharedObject 并检查结果。
     * flush() 返回值：true=成功, "pending"=等待用户授权, false/其他=失败
     * 只有 true 才算成功落盘，"pending" 视为未完成（不清 dirtyMark）。
     */
    private function flushSO(so:SharedObject):Boolean {
        var result:Object = so.flush();
        if (result === true) {
            return true;
        }
        var msg:String = (result == "pending")
            ? "SaveManager: flush pending (awaiting user authorization) for "
            : "SaveManager: flush failed (result=" + result + ") for ";
        ServerManager.getInstance().sendServerMessage(msg + _root.savePath);
        return false;
    }

    private function ensureShopNode(soData:Object):Object {
        if (soData[SAVE_KEY] == undefined) soData[SAVE_KEY] = {};
        if (soData[SAVE_KEY].shop == undefined) soData[SAVE_KEY].shop = {};
        return soData[SAVE_KEY].shop;
    }

    public function packTimestamp():String {
        var now:Date = new Date();
        var y:Number = now.getFullYear();
        var mo:Number = now.getMonth() + 1;
        var d:Number = now.getDate();
        var h:Number = now.getHours();
        var mi:Number = now.getMinutes();
        var s:Number = now.getSeconds();
        var pad:Function = function(n:Number):String {
            return (n < 10) ? "0" + n : String(n);
        };
        return y + "-" + pad(mo) + "-" + pad(d) + " " + pad(h) + ":" + pad(mi) + ":" + pad(s);
    }
}
