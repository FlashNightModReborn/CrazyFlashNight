/*
 * =============================================================================
 *  MouseProxy — _root.鼠标 / _root.鼠标代理 兼容代理（class 化）
 * -----------------------------------------------------------------------------
 *  背景：
 *    主时间轴旧鼠标 MovieClip 移除后，旧 UI 仍依赖如下入口：
 *      _root.鼠标.gotoAndStop(...)
 *      _root.鼠标代理.命中目标(target, shapeFlag)
 *      _root.鼠标代理.清理拖拽图标()
 *    手型视觉交给 Launcher C# CursorOverlayForm（cursor_control {state, dragging}）。
 *
 *  2026-09-12 精简（native-interaction cleanup）：
 *    旧"物品拖影"通道已确认无活跃生产者——现役物品/窗口拖拽全部由
 *    UI 元件自身 startDrag(this,0) 承载（对话框界面、新版物品栏/商店/仓库等），
 *    没有任何代码再向 _root.鼠标.物品图标容器 attachMovie。退役：
 *      - 图标容器 attachMovie 挂接拦截（原 wrapAttachMovie）
 *      - 子图标 removeMovieClip 包装（原 wrapChildRemove）
 *      - 空容器逐帧跟随（原 onEnterFrame = syncDragPos）
 *    保留：
 *      - _root.鼠标 兼容状态入口（gotoAndStop/gotoAndPlay → setState）
 *      - _root.鼠标代理.命中目标 / 清理拖拽图标 签名
 *      - 窗口 startDrag 场景的逻辑 dragging 状态：isDragging 经 sendState
 *        上报 cursor_control dragging 字段，由 C# HandleCursorControl 仲裁
 *      - 物理释放 / 场景复位协议：stopDragSync 清标志并发终态；
 *        关卡系统_lsy_场景转换 仍调 清理拖拽图标 + _root.鼠标.gotoAndStop(1)
 *    物品图标容器 MovieClip 本体保留为兼容占位（场景转换兜底分支与
 *    _root.鼠标.物品图标容器 引用可达），但不再拦截 attachMovie。
 *    cursor_control 消息与 WebOverlayForm 输入协调不在本类改动范围。
 *
 *  为什么 class 化：
 *    asLoader 帧脚本中创建的 Function 闭包会暗中持有定义时的 With 链，
 *    asLoader 卸载后链头被 GC，闭包可能失效。把所有方法挂在 class 上，
 *    活动对象由 SWF 持有，跨 asLoader 生命周期安全。
 *    帧脚本只负责一次性 bootstrap：MouseProxy.install()。
 *
 *  对外 API（中文是给中文调用方的 facade，class 内部全部英文）：
 *    _root.鼠标.{gotoAndStop, gotoAndPlay, removeMovieClip, 物品图标容器}
 *    _root.鼠标代理.{命中目标, 清理拖拽图标, 设置状态, 启用拖拽同步, 停止拖拽同步,
 *                    标准化状态, 发送状态, 确保容器, 状态映射, 普通状态, 安装}
 * =============================================================================
 */
class org.flashNight.arki.cursor.MouseProxy {

    //----------------------------------
    // 静态字段（持久存活，跨 asLoader 生命周期）
    //----------------------------------

    public static var DEFAULT_STATE:String = "normal";
    public static var currentState:String = "normal";
    public static var isDragging:Boolean = false;

    // 上次发送签名拆成两字段，避免每次 sendState 都拼接字符串
    private static var lastState:String = null;
    private static var lastDrag:Boolean = false;

    private static var _containerReady:Boolean = false;

    // AS2 对象字面量的 key 必须是裸 identifier，无法表达 "1" / 中文 key，
    // 所以用 init 静态方法 + 桶赋值。
    private static var stateMap:Object = MouseProxy.initStateMap();

    private static function initStateMap():Object {
        var m:Object = {};
        m["1"] = "normal";
        m["手型普通"] = "normal";
        m["手型点击"] = "click";
        m["手型准备抓取"] = "hoverGrab";
        m["手型抓取"] = "grab";
        m["手型攻击"] = "attack";
        m["开门"] = "openDoor";
        return m;
    }

    //----------------------------------
    // 容器管理
    //----------------------------------

    public static function ensureContainer():MovieClip {
        var layer:MovieClip = _root.鼠标图标层;
        var container:MovieClip = layer.物品图标容器;

        // 快速路径：容器已就绪且 MC 仍存在，只做最轻处理
        if (MouseProxy._containerReady && container != undefined) {
            layer._visible = true;
            if (layer.命中锚点 != undefined) layer.命中锚点.removeMovieClip();
            return container;
        }

        if (layer == undefined) {
            // AS2 中 undefined.prop 返回 undefined 不崩溃，无需逐级判空
            var depth:Number = _root.层级管理器.mouse;
            if (depth == undefined) depth = 65535;
            _root.createEmptyMovieClip("鼠标图标层", depth);
            layer = _root.鼠标图标层;
        }
        layer._visible = true;

        if (layer.命中锚点 != undefined) layer.命中锚点.removeMovieClip();

        if (layer.物品图标容器 == undefined) {
            layer.createEmptyMovieClip("物品图标容器", 0);
        }

        container = layer.物品图标容器;
        MouseProxy._containerReady = true;
        return container;
    }

    //----------------------------------
    // 状态
    //----------------------------------

    public static function normalizeState(state):String {
        var key:String = "" + state;
        var mapped:String = MouseProxy.stateMap[key];
        if (mapped === undefined) return key;
        return mapped;
    }

    public static function sendState(state:String):Void {
        var dragging:Boolean = MouseProxy.isDragging;
        if (MouseProxy.lastState === state && MouseProxy.lastDrag === dragging) return;
        MouseProxy.lastState = state;
        MouseProxy.lastDrag = dragging;

        var srv:Object = _root.server;
        if (srv == undefined || !srv.isSocketConnected) return;
        srv.sendTaskToNode("cursor_control", { state: state, dragging: dragging });
    }

    public static function hitTarget(target:MovieClip, shapeFlag:Boolean):Boolean {
        if (target == undefined) return false;
        return target.hitTest(_root._xmouse, _root._ymouse, !!shapeFlag);
    }

    //----------------------------------
    // 拖拽同步（逻辑标志）
    //----------------------------------

    // 物理跟随已退役：物品图标容器恒空，现役拖拽由 UI 元件自身 startDrag 承载，
    // 没有东西需要逐帧贴鼠标。本组方法只维护 isDragging 逻辑标志——
    // 窗口 startDrag 期间经 sendState 上报 cursor_control dragging 字段，
    // 供 C# CursorOverlayForm 仲裁原生光标显示。
    public static function startDragSync():Void {
        if (MouseProxy.isDragging) return;
        MouseProxy.isDragging = true;
        MouseProxy.sendState(MouseProxy.currentState);
    }

    public static function stopDragSync():Void {
        if (!MouseProxy.isDragging) return;
        MouseProxy.isDragging = false;
        // 防御：旧会话/旧 SWF 遗留的物理跟随 handler 在复位时一并摘除
        if (_root.鼠标图标层 != undefined) delete _root.鼠标图标层.onEnterFrame;
        MouseProxy.sendState(MouseProxy.currentState);
    }

    public static function cleanupDragIcon():Void {
        var container:MovieClip = MouseProxy.ensureContainer();
        if (container.物品图标 != undefined) container.物品图标.removeMovieClip();
        MouseProxy.stopDragSync();
    }

    public static function setState(state):Void {
        var normalized:String = MouseProxy.normalizeState(state);
        MouseProxy.currentState = normalized;

        if (normalized == "grab") MouseProxy.startDragSync();
        else if (normalized == "normal") MouseProxy.stopDragSync();

        MouseProxy.sendState(normalized);
    }

    //----------------------------------
    // 安装：bootstrap 入口，由帧脚本调用一次
    //----------------------------------

    public static function install():Void {
        var container:MovieClip = MouseProxy.ensureContainer();

        // _root.鼠标 stub —— 函数引用全部指向 class 静态方法，持久
        var stub:Object = {};
        stub.物品图标容器 = container;
        stub.gotoAndStop = MouseProxy.setState;
        stub.gotoAndPlay = MouseProxy.setState;
        stub.removeMovieClip = MouseProxy.cleanupDragIcon;
        _root.鼠标 = stub;

        // _root.鼠标代理 forwarding namespace —— 中文 key 给中文脚本调用方，
        // 内部全部桥到 class 英文方法
        var ns:Object = {};
        ns.命中目标 = MouseProxy.hitTarget;
        ns.清理拖拽图标 = MouseProxy.cleanupDragIcon;
        ns.设置状态 = MouseProxy.setState;
        ns.启用拖拽同步 = MouseProxy.startDragSync;
        ns.停止拖拽同步 = MouseProxy.stopDragSync;
        ns.标准化状态 = MouseProxy.normalizeState;
        ns.发送状态 = MouseProxy.sendState;
        ns.确保容器 = MouseProxy.ensureContainer;
        ns.安装 = MouseProxy.install;
        ns.状态映射 = MouseProxy.stateMap;
        ns.普通状态 = MouseProxy.DEFAULT_STATE;
        _root.鼠标代理 = ns;

        // 复位：旧实例可能遗留物理跟随 handler 与 dragging 标志，统一归零后上报
        if (_root.鼠标图标层 != undefined) delete _root.鼠标图标层.onEnterFrame;
        MouseProxy.isDragging = false;
        MouseProxy.currentState = MouseProxy.DEFAULT_STATE;
        MouseProxy.sendState(MouseProxy.DEFAULT_STATE);
    }
}
