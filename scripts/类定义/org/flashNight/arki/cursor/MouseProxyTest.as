import org.flashNight.arki.cursor.MouseProxy;

/**
 * MouseProxy 薄兼容回归（native-interaction cleanup 2026-09-12）。
 * 验证：_root.鼠标 / _root.鼠标代理 兼容入口与签名保留；grab/normal 只维护
 * isDragging 逻辑标志并经 cursor_control {state,dragging} 上报；
 * attachMovie 拦截、remove 包装与空容器 onEnterFrame 物理跟随已退役；
 * 场景复位序列（清理拖拽图标 + gotoAndStop(1)）仍收敛。
 */
class org.flashNight.arki.cursor.MouseProxyTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var sent:Array;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        trace("=== MouseProxyTest start ===");
        testInstallExposesCompatSurface();
        testGrabReleaseLogicalDragging();
        testSceneResetProtocol();
        testHitTargetAndContainerIdempotent();
        trace("MouseProxyTest Tests Passed: " + passed);
        trace("MouseProxyTest Tests Failed: " + failed);
        trace("=== MouseProxyTest end ===");
    }

    private static function saveRoot():Object {
        return {
            鼠标:_root.鼠标,
            鼠标代理:_root.鼠标代理,
            鼠标图标层:_root.鼠标图标层,
            server:_root.server,
            层级管理器:_root.层级管理器
        };
    }

    private static function restoreRoot(s:Object):Void {
        // 层是本测试新建的 MC 时整体移除；预先存在的层引用原样保留
        if (_root.鼠标图标层 != s.鼠标图标层) {
            if (_root.鼠标图标层 != undefined) _root.鼠标图标层.removeMovieClip();
            if (s.鼠标图标层 != undefined) _root.鼠标图标层 = s.鼠标图标层;
        }
        _root.鼠标 = s.鼠标;
        _root.鼠标代理 = s.鼠标代理;
        _root.server = s.server;
        _root.层级管理器 = s.层级管理器;
        MouseProxy.isDragging = false;
        MouseProxy.currentState = MouseProxy.DEFAULT_STATE;
    }

    private static function installMockServer():Void {
        sent = [];
        _root.server = {
            isSocketConnected:true,
            sent:sent,
            sendTaskToNode:function(kind, payload):Void {
                this.sent.push({kind:kind, payload:payload});
            }
        };
        _root.层级管理器 = {mouse:65535};
    }

    private static function lastSent():Object {
        return sent[sent.length - 1];
    }

    private static function testInstallExposesCompatSurface():Void {
        var s:Object = saveRoot();
        try {
            installMockServer();
            // 先推一个非 normal 签名，保证 install 的初始上报不被 dedupe 吞掉
            MouseProxy.setState("attack");
            var base:Number = sent.length;
            MouseProxy.install();
            check(typeof _root.鼠标 == "object"
                    && typeof _root.鼠标.gotoAndStop == "function"
                    && typeof _root.鼠标.gotoAndPlay == "function"
                    && typeof _root.鼠标.removeMovieClip == "function",
                "_root.鼠标 兼容状态入口安装");
            check(typeof _root.鼠标代理.命中目标 == "function"
                    && typeof _root.鼠标代理.清理拖拽图标 == "function"
                    && typeof _root.鼠标代理.设置状态 == "function"
                    && typeof _root.鼠标代理.启用拖拽同步 == "function"
                    && typeof _root.鼠标代理.停止拖拽同步 == "function",
                "_root.鼠标代理 命中/清理/拖拽签名保留");
            check(_root.鼠标.物品图标容器 != undefined
                    && _root.鼠标.物品图标容器 === _root.鼠标图标层.物品图标容器,
                "物品图标容器 兼容引用可达");
            check(_root.鼠标代理.同步拖拽位置 == undefined
                    && _root.鼠标.物品图标容器.__mouseProxyWrapped == undefined
                    && _root.鼠标.物品图标容器.__mouseProxyRawAttach == undefined,
                "物理跟随入口与 attachMovie 拦截已退役");
            check(sent.length == base + 1
                    && lastSent().kind == "cursor_control"
                    && lastSent().payload.state == "normal"
                    && lastSent().payload.dragging == false,
                "install 复位并上报初始 normal 状态");
        } finally {
            restoreRoot(s);
        }
    }

    /** 窗口 startDrag 场景：press→grab 置位、release→normal 复位，容器不挂帧跟随。 */
    private static function testGrabReleaseLogicalDragging():Void {
        var s:Object = saveRoot();
        try {
            installMockServer();
            MouseProxy.install();
            var base:Number = sent.length;

            _root.鼠标.gotoAndStop("手型抓取");
            check(MouseProxy.isDragging === true,
                "手型抓取 → 逻辑 dragging 置位");
            check(sent.length == base + 1
                    && lastSent().payload.state == "grab"
                    && lastSent().payload.dragging == true,
                "cursor_control 上报 grab+dragging");
            check(_root.鼠标图标层.onEnterFrame == undefined,
                "grab 不再给空容器挂 onEnterFrame 跟随");

            _root.鼠标.gotoAndStop("手型准备抓取");
            check(MouseProxy.isDragging === true
                    && lastSent().payload.state == "hoverGrab"
                    && lastSent().payload.dragging == true,
                "拖动中悬停变化保持 dragging 并上报 hoverGrab");

            _root.鼠标.gotoAndStop("手型普通");
            check(MouseProxy.isDragging === false
                    && lastSent().payload.state == "normal"
                    && lastSent().payload.dragging == false,
                "释放后复位 normal+not dragging");

            var n2:Number = sent.length;
            _root.鼠标代理.设置状态("手型普通");
            check(sent.length == n2, "重复同态 sendState 去重不发");
        } finally {
            restoreRoot(s);
        }
    }

    /** 关卡系统_lsy_场景转换 的复位序列：清理拖拽图标() + _root.鼠标.gotoAndStop(1)。 */
    private static function testSceneResetProtocol():Void {
        var s:Object = saveRoot();
        try {
            installMockServer();
            MouseProxy.install();
            _root.鼠标.gotoAndStop("手型抓取");

            var container:MovieClip = _root.鼠标.物品图标容器;
            container.createEmptyMovieClip("物品图标", 1);
            _root.鼠标代理.清理拖拽图标();
            check(container.物品图标 == undefined,
                "清理拖拽图标 摘除残留物品图标");
            check(MouseProxy.isDragging === false,
                "清理拖拽图标 收敛 dragging 标志");
            _root.鼠标.gotoAndStop(1);
            check(lastSent().payload.state == "normal"
                    && lastSent().payload.dragging == false,
                "场景复位后终态 normal+not dragging");

            _root.鼠标.gotoAndStop("手型抓取");
            _root.鼠标.removeMovieClip();
            check(MouseProxy.isDragging === false,
                "_root.鼠标.removeMovieClip 兼容入口走同一清理");
        } finally {
            restoreRoot(s);
        }
    }

    private static function testHitTargetAndContainerIdempotent():Void {
        var s:Object = saveRoot();
        try {
            installMockServer();
            MouseProxy.install();
            check(_root.鼠标代理.命中目标(undefined) === false,
                "命中目标 空目标返回 false");
            var probe:MovieClip = _root.createEmptyMovieClip(
                "mp_probe", _root.getNextHighestDepth());
            var r = _root.鼠标代理.命中目标(probe, false);
            check(typeof r == "boolean",
                "命中目标 委托 hitTest 返回布尔");
            probe.removeMovieClip();
            var c1:MovieClip = _root.鼠标代理.确保容器();
            var c2:MovieClip = _root.鼠标代理.确保容器();
            check(c1 === c2 && c1 === _root.鼠标.物品图标容器,
                "确保容器 幂等返回同一 MovieClip");
        } finally {
            restoreRoot(s);
        }
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            passed++;
            trace("[PASS] " + message);
        } else {
            failed++;
            trace("[FAIL] " + message);
        }
    }
}
