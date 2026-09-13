/*
 * =============================================================================
 *  PauseManager — _root.暂停 单一权威观察者 + lease/CAS 暂停契约
 * -----------------------------------------------------------------------------
 *  背景：
 *    全项目 _root.暂停 写入点共 8 处（unused/ 死代码不计）：UI 切换、对话、
 *    场景切换、商城 panel。AS2 Object.watch 每个属性只能挂一个 callback，
 *    UI管理.as:240 处已存在一个 watch 做 FrameBroadcaster UI 同步 + IME 禁用。
 *
 *    Launcher WebView panel 关闭后需要把 _root.暂停 还原到打开前的值，但
 *    panel 期间 AS2 业务侧（对话/场景）可能自行写了一次新值，盲目还原会
 *    把对话暂停误清掉。需要一个 owner 归属 + CAS-on-release 的契约。
 *
 *  设计三件套：
 *    1. **接管 watch**：PauseManager 占用 _root.watch("暂停", ...) 唯一槽位，
 *       业务侧通过 subscribe(fn) 订阅；UI管理.as:240 的旧 watch 迁移为第一个
 *       subscriber，行为完全等价。
 *    2. **side-channel writer tag**：set(value, owner) 在写入瞬间挂 _writerTag，
 *       watch 回调读取后立刻清零；subscribers 收到的 tag 区分"launcher 写"vs
 *       "AS2 直写"，无需改业务侧的 _root.暂停 = ... 写法。
 *    3. **claim-OR（lease 的现行语义）**：lease(true, owner) 登记为一条暂停
 *       责任声明；多条 claim 之间是 OR——任何一条存活期间实体恒 true，
 *       期间业务侧裸写只更新 _unownedPause 基值意图而不降下暂停；最后一条
 *       claim 释放时才把 _unownedPause 写回。这取代早期“各自记录 prevValue
 *       再 CAS 还原”的实现：两份布尔 lease 交叠（对白+web/shop）会错序
 *       提前解除暂停。lease(false,...) 仍走原 prevValue/CAS 路径（现无调用方）。
 *
 *  使用示例：
 *    bootstrap（UI管理.as 帧脚本一次性调用）：
 *      org.flashNight.arki.pause.PauseManager.install();
 *      org.flashNight.arki.pause.PauseManager.subscribe(function(newVal, oldVal, tag):Void {
 *          org.flashNight.arki.render.FrameBroadcaster.pushUiState("p:" + (newVal ? "1" : "0"));
 *          System.IME.setEnabled(false);
 *      }, null);
 *
 *    Web panel（商城_WebView.as 等）：
 *      var leaseId = PauseManager.lease(true, "shop");
 *      ...
 *      PauseManager.releaseLease(leaseId);
 *
 *  约束：
 *    - 任何想观察 _root.暂停 变化的新代码必须走 PauseManager.subscribe，
 *      禁止再调 _root.watch("暂停", ...)（会覆盖 PauseManager 的回调）。
 *    - 业务侧直写 _root.暂停 = ... 不变（subscribers 收到 tag === null）。
 *    - 帧脚本不要在 install 之前发起 set / lease / subscribe / unsubscribe 调用
 *      （_subscribers / _leases 字段在 install() 内才初始化，提前调用会 NPE）。
 * =============================================================================
 */
class org.flashNight.arki.pause.PauseManager {

    //----------------------------------
    // 静态字段
    //----------------------------------

    private static var _initialized:Boolean = false;
    private static var _rewardCommitPending:Boolean = false;
    private static var _rewardResumeValue:Boolean = false;

    /** 保存授权尚未裁决时，普通 UI 关闭不能恢复游戏并改写候选。 */
    public static function setRewardCommitPending(value:Boolean):Void {
        PauseManager.install();
        if (value === PauseManager._rewardCommitPending) return;
        if (value) {
            // claim 存续期间 isPaused() 反映的是 claim 强制值而非业务基值；
            // 以 _unownedPause 为恢复候选，避免把对话/web 的暂停责任永久化。
            PauseManager._rewardResumeValue = (PauseManager._claimCount > 0)
                ? PauseManager._unownedPause : PauseManager.isPaused();
            PauseManager._rewardCommitPending = true;
            // 强制 true 不是基值意图，按 claim 内部写处理，不污染 _unownedPause。
            PauseManager._claimWriting = true;
            PauseManager.set(true, "reward_save");
            PauseManager._claimWriting = false;
        } else {
            PauseManager._rewardCommitPending = false;
            PauseManager.set(PauseManager._rewardResumeValue, "reward_save");
        }
    }

    // 订阅链：[{id:String, fn:Function, scope:Object}, ...]
    private static var _subscribers:Array;

    // lease 表：{leaseId:String -> {owner:String, prevValue:Boolean, leasedValue:Boolean}}
    private static var _leases:Object;

    // side-channel writer tag：set(value, owner) 期间临时挂上，watch 回调读取后立刻清零；
    // null 表示当前是业务侧直接 _root.暂停 = ... 写入（无 owner）。
    private static var _writerTag:String = null;

    // claim 表（lease(true,...) 的现行载体）：{claimId:String -> {owner:String}}
    // OR 语义：任一 claim 存活期间 _root.暂停 恒 true；最后一条释放才恢复基值。
    private static var _claims:Object;
    private static var _claimCount:Number = 0;
    // 无 claim 时业务侧对 _root.暂停 的取值意图；claim 存续期间由外部写持续更新。
    private static var _unownedPause:Boolean = false;
    // claim/lease 内部写标记：acquire/release 路径的 set 不参与基值记账。
    private static var _claimWriting:Boolean = false;

    // 自增 id 计数器
    private static var _nextLeaseId:Number = 1;
    private static var _nextSubId:Number = 1;

    // 重入保护：subscriber 内若再调 set/lease 触发新一轮 watch，跳过递归分发
    private static var _dispatching:Boolean = false;

    //----------------------------------
    // 生命周期
    //----------------------------------

    public static function install():Void {
        if (PauseManager._initialized) return;
        PauseManager._initialized = true;
        PauseManager._subscribers = [];
        PauseManager._leases = {};
        PauseManager._claims = {};
        PauseManager._claimCount = 0;
        PauseManager._unownedPause = false;
        PauseManager._claimWriting = false;
        PauseManager._writerTag = null;
        // 占用 _root.暂停 唯一 watch 槽位；后续任何 _root.watch("暂停", ...) 都会
        // 覆盖此 callback，必须走 PauseManager.subscribe 而非 _root.watch。
        _root.watch("暂停", PauseManager.onPauseChanged);
    }

    //----------------------------------
    // watch 回调：单一入口，分发到所有 subscribers
    // AS2 watch 签名：function(prop, oldValue, newValue):any
    // 必须返回 newValue 才能让赋值生效（return 不同值会拦截写入）。
    //----------------------------------

    public static function onPauseChanged(prop:String, oldVal, newVal) {
        // 重入跳过：subscriber 回调内若再调 set / lease / releaseLease 触发本 watch，
        // 内层直接 return newVal 让赋值生效（_root.暂停 = ... 不被拦截），但 subscribers
        // **不会收到该次嵌套写入的通知**。这是设计意图：避免无限递归 + 避免分发顺序乱套。
        // 业务约束：subscriber 内不要做"会改 _root.暂停 又依赖被其他 subscriber 同步观察到"的操作。
        var tag:String = PauseManager._writerTag;
        // claim 记账先于 reward 折叠：必须使用调用方原始入参（newVal 改写前），
        // 否则 pending 期被 reward 折成 true 的值会污染基值意图。
        // reward_save 自己的 force/resume 写不表达业务基值意图，跳过记账——
        // pending 期间的 resume 值已含 claim 产生的强制 true，回写会永久化。
        if (PauseManager._claimCount > 0 && !PauseManager._claimWriting
                && tag != "reward_save") {
            PauseManager._unownedPause = (newVal === true);
        }
        if (PauseManager._rewardCommitPending && tag != "reward_save") {
            PauseManager._rewardResumeValue = newVal === true;
            newVal = true;
        }
        if (PauseManager._claimCount > 0 && !PauseManager._claimWriting) {
            // OR：任一 claim 存活期间，外部写（裸写/其他 owner 的 set/reward_save
            // 的 resume 写）一律不降下暂停，只进上面的基值意图记账。
            newVal = true;
        }
        if (PauseManager._dispatching) return newVal;
        PauseManager._dispatching = true;

        // 写时快照 subscribers 数组：subscriber 内可安全调 unsubscribe（自己或他人），
        // 当前轮分发仍以 snapshot 为准；新 subscribe 进来的回调本轮不触发。
        var subs:Array = PauseManager._subscribers.concat();
        var len:Number = subs.length;
        for (var i:Number = 0; i < len; i++) {
            var sub:Object = subs[i];
            sub.fn.call(sub.scope, newVal, oldVal, tag);
        }

        PauseManager._dispatching = false;
        return newVal;
    }

    //----------------------------------
    // 读 / 写
    //----------------------------------

    // 读当前 _root.暂停（=== true 严格比较避免 truthy 噪音）
    public static function isPaused():Boolean {
        return _root.暂停 === true;
    }

    /**
     * O1 临时只读观测面：只返回有界、脱敏的暂停 owner 类别。
     * 不创建/释放 lease，不写 _root.暂停，也不暴露 leaseId。
     */
    public static function getObservationOwner():String {
        if (!PauseManager.isPaused()) return "none";
        if (!PauseManager._initialized || PauseManager._leases == undefined) {
            return "unowned_pause";
        }
        var count:Number = 0;
        var owner:String = "";
        for (var leaseId:String in PauseManager._leases) {
            count++;
            if (count == 1) owner = String(PauseManager._leases[leaseId].owner || "");
            if (count > 1) return "multiple_leases";
        }
        for (var claimId:String in PauseManager._claims) {
            count++;
            if (count == 1) owner = String(PauseManager._claims[claimId].owner || "");
            if (count > 1) return "multiple_leases";
        }
        if (count == 0) return "unowned_pause";
        if (owner == "shop" || owner == "webpanel" || owner == "dialogue") return owner;
        return "other_lease";
    }

    // 带 owner tag 的写入。owner 例：'shop' / 'dialog' / 'stage' / 'merc'；
    // 业务侧裸写 _root.暂停 = ... 不调本方法，subscribers 收到 tag === null。
    public static function set(value:Boolean, owner:String):Void {
        PauseManager._writerTag = owner;
        _root.暂停 = value;
        PauseManager._writerTag = null;
    }

    //----------------------------------
    // 订阅链（取代直接 _root.watch）
    // Callback 签名：function(newVal:Boolean, oldVal, ownerTag:String):Void
    //   ownerTag === null 表示无 owner 的 AS2 直写
    //   ownerTag === "<name>" 表示 PauseManager.set / lease 写入
    //----------------------------------

    public static function subscribe(fn:Function, scope:Object):String {
        var id:String = "sub" + (PauseManager._nextSubId++);
        PauseManager._subscribers.push({id: id, fn: fn, scope: scope});
        return id;
    }

    public static function unsubscribe(id:String):Void {
        var subs:Array = PauseManager._subscribers;
        var len:Number = subs.length;
        for (var i:Number = 0; i < len; i++) {
            if (subs[i].id == id) {
                subs.splice(i, 1);
                return;
            }
        }
    }

    //----------------------------------
    // Lease → claim-OR（lease(true,...)）／ legacy CAS（lease(false,...)）
    //
    // lease(true, owner)：登记一条暂停责任声明。首个 claim 建立时把当前
    //   _root.暂停（reward pending 时取 _rewardResumeValue 意图）记为
    //   _unownedPause 基值；claim 存续期间任何外部写只更新基值、实体恒 true；
    //   最后一条 claim 释放时 set(_unownedPause, owner+":release") 落回——
    //   reward pending 仍在时该写会被 watch 折入 _rewardResumeValue，实体保持
    //   true，由 reward_save 终局统一恢复。
    // lease(false,...)：保留原 prevValue/CAS 路径（当前无调用方，防御性保留）。
    //----------------------------------

    public static function lease(value:Boolean, owner:String):String {
        PauseManager.install();
        var leaseId:String = "lease" + (PauseManager._nextLeaseId++);
        if (value === true) {
            if (PauseManager._claimCount == 0) {
                PauseManager._unownedPause = PauseManager._rewardCommitPending
                    ? PauseManager._rewardResumeValue : PauseManager.isPaused();
            }
            PauseManager._claims[leaseId] = {owner: owner};
            PauseManager._claimCount++;
            PauseManager._claimWriting = true;
            PauseManager.set(true, owner);
            PauseManager._claimWriting = false;
            return leaseId;
        }
        PauseManager._leases[leaseId] = {
            owner: owner,
            prevValue: PauseManager.isPaused(),
            leasedValue: value
        };
        PauseManager.set(value, owner);
        return leaseId;
    }

    public static function releaseLease(leaseId:String):Void {
        var claim:Object = PauseManager._claims != undefined
            ? PauseManager._claims[leaseId] : undefined;
        if (claim != undefined) {
            delete PauseManager._claims[leaseId];
            PauseManager._claimCount--;
            if (PauseManager._claimCount <= 0) {
                PauseManager._claimCount = 0;
                PauseManager._claimWriting = true;
                PauseManager.set(PauseManager._unownedPause, claim.owner + ":release");
                PauseManager._claimWriting = false;
            }
            return;
        }

        var data:Object = PauseManager._leases[leaseId];
        if (data == undefined) return;
        delete PauseManager._leases[leaseId];

        // CAS：当前值仍等于自己设的值 → 安全还原；否则放弃，由业务侧接管。
        // 失败路径打一条服务器消息：调用方收不到信号，但运维侧能在日志里观测
        // "release 时业务已改写"的真实分布，给后续设计调整提供依据。
        if (PauseManager.isPaused() === data.leasedValue) {
            PauseManager.set(data.prevValue, data.owner + ":release");
        } else {
            _root.服务器.发布服务器消息(
                "[PauseManager] CAS fail lease=" + leaseId
                + " owner=" + data.owner
                + " leasedValue=" + data.leasedValue
                + " current=" + PauseManager.isPaused()
                + " prevValue=" + data.prevValue
            );
        }
    }
}
