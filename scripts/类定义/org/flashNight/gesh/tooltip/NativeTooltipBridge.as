/**
 * NativeTooltipBridge - AS2 原生注释出口（COMMON 桥协议 v1）
 *
 * 职责：
 * - 把 NativeTooltipDocument 产出的 document 通过
 *   _root.server.sendTaskToNode("native_interaction", payload, null) 发布到宿主。
 * - payload 形状：{kind:"tooltip", op:"show"|"hide", version:1,
 *   requestId:"ni:<n>", sceneId, x, y, document?, anchorRect?, placement?}
 *   x/y 为 Flash 逻辑鼠标锚点（_root._xmouse/_ymouse）。
 *   anchorRect 可选：{x,y,width,height}，_root 系 Flash 逻辑坐标，
 *   取真实 owner/图标 MovieClip 的 getBounds(_root)；无有效 owner 时整段省略，
 *   宿主按纯指针锚点旧契约处理。placement 可选：left/right/top/bottom。
 * - 身份统一走共享 org.flashNight.arki.interaction.NativeInteractionContext：
 *   requestId = ctx.nextRequestId()（ni:<正整数>，与菜单共用全局递增序号）；
 *   sceneId  = ctx.getSceneId()（当前场景不可复用代号）。
 *   本桥不另建计数器/场景ID，避免与 NPC 菜单浮层身份口径不一致。
 * - 身份安全：hide 按 requestId 匹配；迟到的 hide 不会关掉更新的请求。
 * - 通道不可用（server 缺失/未连接/上下文类未加载/发送失败）时返回 null/false，
 *   由调用方决定是否回退旧 Flash 渲染，桥本身不产生副作用。
 *
 * - 已编译 ItemIcon 兼容（不重建 main）：install() 幂等 patch
 *   ItemIcon.prototype.RollOver，wrapper 经 getIconMovieClip() 捕获 owner 进
 *   _scopedOwner，再以 apply(this,arguments) 调回原方法；show() 的 ownerClip
 *   实参缺省时回退 _scopedOwner。wrapper/original 均为 class 持有的 static
 *   Function，不依赖帧脚本 activation，asLoader teardown 后仍存活。
 *
 * 典型用法：
 *   var reqId = NativeTooltipBridge.show(doc);          // 成功返回 requestId
 *   var reqId = NativeTooltipBridge.show(doc, iconMc);  // 携带 anchorRect
 *   NativeTooltipBridge.hide(reqId);                // 或 hide() 隐藏当前实例
 *   NativeTooltipBridge.reset();                    // 场景生命周期重置（as2-menu 在
 *                                                   // 更新场景身份前先调用）
 */
class org.flashNight.gesh.tooltip.NativeTooltipBridge {

    public static var TASK_TYPE:String = "native_interaction";
    public static var KIND_TOOLTIP:String = "tooltip";

    private static var _activeRequestId:String = null; // 当前已下发实例身份
    private static var _activeSceneId:String = null;
    private static var _teardownRegistered:Boolean = false;

    private static var _scopedOwner:MovieClip = null;      // patched RollOver 调用期捕获的 owner

    /**
     * 共享身份上下文。经 _global 动态解析：
     * as2-menu 的 NativeInteractionContext 未编入/未加载时返回 null，
     * 桥降级为"通道不可用"，不伪造身份。
     */
    private static function context():Object {
        var g:Object = _global;
        // AVM1 的 _global 对象与 null 宽松比较会相等；只校验实际命名空间。
        if (g.org == null) return null;
        var c:Object = g.org.flashNight;
        if (c == null) return null;
        c = c.arki;
        if (c == null) return null;
        c = c.interaction;
        if (c == null) return null;
        c = c.NativeInteractionContext;
        if (c == null || c.getSceneId == undefined || c.nextRequestId == undefined) return null;
        return c;
    }

    /**
     * 幂等安装：预热共享上下文并向其注册场景 teardown（先于身份轮换执行）；
     * 同时幂等 patch 已编译 ItemIcon.prototype.RollOver，首个悬停即携带图标矩形。
     * 供 NativeMenuBridge.install 接力调用；未调用时由首个 show() 惰性完成注册。
     */
    public static function install():Void {
        patchItemIconRollOver();
        var ctx:Object = context();
        if (ctx == null) return;
        if (ctx.install != undefined) ctx.install();
        if (!_teardownRegistered && ctx.onSceneTeardown != undefined) {
            _teardownRegistered = true;
            ctx.onSceneTeardown(NativeTooltipBridge.reset);
        }
    }

    /** 发送通道是否可用（server 就绪 + 共享身份上下文已加载）。 */
    public static function isAvailable():Boolean {
        var server:Object = _root.server;
        return server != undefined && server != null
            && server.sendTaskToNode != undefined
            && server.isSocketConnected === true
            && context() != null;
    }

    /**
     * 发布 tooltip.show。成功返回本次 requestId（ni:<n>）；通道不可用/发送失败返回 null。
     * ownerClip 可选：真实 owner/图标 MovieClip，有效时写入 payload.anchorRect；
     * 缺省回退 patched ItemIcon.RollOver 捕获的 _scopedOwner；两者皆无则旧 payload。
     * placement 可选：left/right/top/bottom，非法值不下发。
     */
    public static function show(document:Object, ownerClip:MovieClip, placement:String):String {
        if (document == null || document == undefined) return null;
        var ctx:Object = context();
        if (ctx == null) return null;
        var server:Object = _root.server;
        if (server == undefined || server == null
                || server.sendTaskToNode == undefined
                || server.isSocketConnected !== true) return null;

        // 注册场景切换 teardown（先于身份轮换执行）：切场景自动按身份 hide 当前实例
        install();

        var requestId:String = ctx.nextRequestId();
        var sceneId:String = ctx.getSceneId();
        if (requestId == undefined || requestId == null || requestId == "") return null;

        var mx:Number = _root._xmouse;
        var my:Number = _root._ymouse;
        if (isNaN(mx)) mx = 0;
        if (isNaN(my)) my = 0;

        var payload:Object = {
            kind: KIND_TOOLTIP,
            op: "show",
            version: 1,
            requestId: requestId,
            sceneId: sceneId,
            x: mx,
            y: my,
            document: document
        };
        var anchor:Object = anchorRectFor(typeof ownerClip == "movieclip" ? ownerClip : _scopedOwner);
        if (anchor !== null && anchor !== undefined) payload.anchorRect = anchor;
        if (placement == "left" || placement == "right"
                || placement == "top" || placement == "bottom") {
            payload.placement = placement;
        }
        if (server.sendTaskToNode(TASK_TYPE, payload, null) !== true) return null;

        _activeRequestId = requestId;
        _activeSceneId = sceneId;
        return requestId;
    }

    /**
     * 发布 tooltip.hide。
     * - requestId 省略/null/空串 → 针对当前活跃实例；无活跃实例直接返回 false。
     * - 指定 requestId 与当前活跃身份不符（迟到请求）→ 仍发送给宿主按身份匹配，
     *   但不清本地活跃状态；宿主侧同样只清匹配实例。
     * 返回是否真正下发（通道不可用为 false）。
     */
    public static function hide(requestId:String):Boolean {
        var target:String = (requestId != undefined && requestId != null && requestId != "")
            ? requestId : _activeRequestId;
        if (target == null || target == "") return false;

        var isCurrent:Boolean = (target == _activeRequestId);
        var sent:Boolean = false;
        var server:Object = _root.server;
        if (server != undefined && server != null
                && server.sendTaskToNode != undefined
                && server.isSocketConnected === true) {
            var payload:Object = {
                kind: KIND_TOOLTIP,
                op: "hide",
                version: 1,
                requestId: target
            };
            if (isCurrent && _activeSceneId != null) payload.sceneId = _activeSceneId;
            sent = (server.sendTaskToNode(TASK_TYPE, payload, null) === true);
        }
        if (isCurrent) {
            _activeRequestId = null;
            _activeSceneId = null;
        }
        return sent;
    }

    /** 隐藏当前活跃实例（等价 hide(null)）。 */
    public static function hideCurrent():Boolean {
        return hide(null);
    }

    /**
     * 生命周期重置：下发一次带身份的 hide（若可能），并清空本地活跃状态。
     * 供 as2-menu 场景切换流程在更新场景身份之前调用。
     */
    public static function reset():Void {
        hide(null);
        _activeRequestId = null;
        _activeSceneId = null;
    }

    /** 当前活跃 requestId；无则 null。 */
    public static function activeRequestId():String {
        return _activeRequestId;
    }

    /** 当前活跃 sceneId；无则 null。 */
    public static function activeSceneId():String {
        return _activeSceneId;
    }

    /**
     * owner MovieClip → _root 系 anchorRect。
     * 非 MC / 无 getBounds / 任一边界非有限 / 非正宽高 → null（调用方整段省略）。
     * (v - v) == 0 同测 NaN 与 ±Infinity（NaN 比较与 Inf-Inf=NaN 均被滤掉）。
     */
    private static function anchorRectFor(owner:MovieClip):Object {
        // AVM1 活 MovieClip 不能用宽松 null 比较判断有效性。
        if (typeof owner != "movieclip") return null;
        if (owner.getBounds == undefined) return null;
        var b:Object = owner.getBounds(_root);
        // getBounds 返回的 AVM1 原生对象会宽松等于 null，必须用严格比较。
        if (b === null || b === undefined) return null;
        var xMin:Number = b.xMin;
        var yMin:Number = b.yMin;
        var xMax:Number = b.xMax;
        var yMax:Number = b.yMax;
        if ((xMin - xMin) != 0 || (yMin - yMin) != 0
                || (xMax - xMax) != 0 || (yMax - yMax) != 0) return null;
        var w:Number = xMax - xMin;
        var h:Number = yMax - yMin;
        if (!(w > 0) || !(h > 0) || w > 8192 || h > 8192
                || Math.abs(xMin) > 8192 || Math.abs(yMin) > 8192) return null;
        return {x: xMin, y: yMin, width: w, height: h};
    }

    /**
     * 静态引用保证类在 install 前可用；AVM1 复用已存在的类定义，不要求重编 main。
     * 每个原型持有自己的 wrapper 与原方法，避免类重装/测试替身串用原函数。
     */
    private static function patchItemIconRollOver():Void {
        var cls:Object = org.flashNight.arki.item.itemIcon.ItemIcon;
        if (cls == null || cls.prototype == null) return;
        var proto:Object = cls.prototype;
        var original:Function = proto.RollOver;
        if (original == undefined || original.__nativeTooltipOwnerWrapped === true) return;
        proto.RollOver = makeItemIconRollOverWrapper(original);
    }

    /** class 方法内产生闭包，避免 asLoader 帧脚本 With 链；this/参数/原行为保留。 */
    private static function makeItemIconRollOverWrapper(original:Function):Function {
        var wrapped:Function = function():Void {
            var self:Object = this;
            var prev:MovieClip = org.flashNight.gesh.tooltip.NativeTooltipBridge._scopedOwner;
            org.flashNight.gesh.tooltip.NativeTooltipBridge._scopedOwner =
                (self.getIconMovieClip != undefined) ? self.getIconMovieClip() : null;
            original.apply(self, arguments);
            org.flashNight.gesh.tooltip.NativeTooltipBridge._scopedOwner = prev;
        };
        wrapped.__nativeTooltipOwnerWrapped = true;
        return wrapped;
    }
}
