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
 *    3. **lease/CAS**：lease(value, owner) 记下打开瞬间的 prevValue，
 *       releaseLease 比较当前值是否仍等于自己设的值——是才还原，否表示
 *       业务侧已经接管暂停语义，留给业务侧自己负责。
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
 *    - 帧脚本不要在 install 之前发起 set/lease 调用。
 * =============================================================================
 */
class org.flashNight.arki.pause.PauseManager {

    //----------------------------------
    // 静态字段
    //----------------------------------

    private static var _initialized:Boolean = false;

    // 订阅链：[{id:String, fn:Function, scope:Object}, ...]
    private static var _subscribers:Array;

    // lease 表：{leaseId:String -> {owner:String, prevValue:Boolean, leasedValue:Boolean}}
    private static var _leases:Object;

    // side-channel writer tag：set(value, owner) 期间临时挂上，watch 回调读取后立刻清零；
    // null 表示当前是业务侧直接 _root.暂停 = ... 写入（无 owner）。
    private static var _writerTag:String = null;

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
        // 重入跳过：subscriber 内若调 PauseManager.set 又触发本 watch，避免无限递归
        if (PauseManager._dispatching) return newVal;

        var tag:String = PauseManager._writerTag;
        PauseManager._dispatching = true;

        var subs:Array = PauseManager._subscribers;
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
    // Lease / CAS-on-release
    //
    // lease(value, owner)：写入新值，记录 prevValue，返回 leaseId
    // releaseLease(leaseId)：只有当前值仍等于 leasedValue 时才还原 prevValue；
    //   否则说明业务侧已经写了新值（如对话开场设置暂停=true），不动它，
    //   把暂停归属权交还给业务侧。
    //----------------------------------

    public static function lease(value:Boolean, owner:String):String {
        var leaseId:String = "lease" + (PauseManager._nextLeaseId++);
        PauseManager._leases[leaseId] = {
            owner: owner,
            prevValue: PauseManager.isPaused(),
            leasedValue: value
        };
        PauseManager.set(value, owner);
        return leaseId;
    }

    public static function releaseLease(leaseId:String):Void {
        var data:Object = PauseManager._leases[leaseId];
        if (data == undefined) return;
        delete PauseManager._leases[leaseId];

        // CAS：当前值仍等于自己设的值 → 安全还原；否则放弃，由业务侧接管
        if (PauseManager.isPaused() === data.leasedValue) {
            PauseManager.set(data.prevValue, data.owner + ":release");
        }
    }
}
