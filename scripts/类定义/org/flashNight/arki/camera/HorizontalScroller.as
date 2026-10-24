import org.flashNight.arki.camera.ZoomController;
import org.flashNight.arki.camera.ParallaxBackground;
/** 单一 authored driver；世界、基底目标与临时焦点各自拥有不可重指身份。 */
class org.flashNight.arki.camera.HorizontalScroller {
    private static var instance:HorizontalScroller;
    private var gameWorld:MovieClip;
    private var worldIdentity:Object;
    private var cameraScope:Object;
    private var state:String;
    private var mode:String;
    private var fault:String;
    private var player:MovieClip;
    private var playerIdentity:Object;
    private var base:MovieClip;
    private var baseIdentity:Object;
    private var explicitOwner:Object;
    private var scrollObj:MovieClip;
    private var bgLayer:MovieClip;
    private var frameTimer:Object;
    private var focusStack:Array;
    private var currentFocus:Object;
    private var nextFocusExpiry:Number;
    private var readyCommitted:Boolean;
    private var initialSnapPending:Boolean;
    private var reframePending:Boolean;
    private var poseCommitted:Boolean;
    private var bgWidth:Number;
    private var bgHeight:Number;
    private var horizonHeight:Number;
    private var stageWidth:Number;
    private var stageHeight:Number;
    private var easeFactor:Number;
    private var offsetTolerance:Number;
    private var enableParallax:Boolean;
    private var enableCameraZoom:Boolean;
    private var currentScale:Number;
    private var zoomOffsetX:Number;
    private var zoomOffsetY:Number;
    private var logicalWorldX:Number;
    private var logicalWorldY:Number;
    private var lastWrittenX:Number;
    private var lastWrittenY:Number;
    private var boundsEffBgW:Number;
    private var boundsEffBgH:Number;
    private var boundsMinX:Number;
    private var boundsMaxX:Number;
    private var boundsMinY:Number;
    private var boundsMaxY:Number;
    private var cachedBoundsScale:Number;
    private var cachedBoundsStageWidth:Number;
    private var cachedBoundsStageHeight:Number;
    private var updateFunction:Function;
    private var invokeCount:Number;
    private var updateCount:Number;
    private var lastDriverCount:Number;
    private var driverMissing:Boolean;
    private var diagTick:Number;
    private var retiredIdentity:Object;
    private var retiredScope:Object;
    private static var epoch:Number = 0;

    private function HorizontalScroller() {
        state = "DETACHED"; mode = "PLAYER"; fault = "";
        focusStack = []; nextFocusExpiry = 0;
        easeFactor = 10; offsetTolerance = 0.5;
        invokeCount = updateCount = lastDriverCount = diagTick = 0;
    }
    public static function getInstance():HorizontalScroller {
        if (!instance) instance = new HorizontalScroller();
        return instance;
    }
    public static function update():Void {
        if (instance) instance.performUpdate();
    }
    private static function currentWorld(world:MovieClip, identity:Object):Boolean {
        return identity != undefined && world._parent != undefined && world === _root.gameworld
            && world.__stageReturnWorldIdentity === identity;
    }
    /** 参数随真实 SceneReady 冻结；匿名、迟到事件不能认领当前路径的新世界。 */
    public static function onSceneChanged(world:MovieClip, token:String, identity:Object):Void {
        if (!currentWorld(world,identity) || world.__stageReturnToken !== token) return;
        var c:HorizontalScroller = getInstance();
        if (c.state === "DETACHED" && c.retiredIdentity === identity) return;
        if (c.worldIdentity !== identity || c.state === "DETACHED") c.bindWorld(world,identity);
        onPlayerBound(world,identity,world[_root.控制目标]);
    }
    private static function targetBelongs(target:MovieClip, world:MovieClip):Boolean {
        if (target._x == undefined || target._parent == undefined) return false;
        var parent:MovieClip = target;
        while (parent != undefined && parent !== world && parent !== _root) parent = parent._parent;
        return parent === world;
    }
    private static function targetIdentity(target:MovieClip):Object {
        if (target.__cameraTargetIdentity == undefined) target.__cameraTargetIdentity = {};
        _global.ASSetPropFlags(target,["__cameraTargetIdentity"],1,false);
        return target.__cameraTargetIdentity;
    }
    public static function onPlayerBound(world:MovieClip, identity:Object, target:MovieClip):Boolean {
        if (!currentWorld(world,identity) || !targetBelongs(target,world)) return false;
        var c:HorizontalScroller = getInstance();
        // 玩家可能早于真实 Ready 出现；只记录通知，不提前重置世界或发布 Ready。
        if (c.worldIdentity !== identity || c.state === "DETACHED") return false;
        c.player = target; c.playerIdentity = targetIdentity(target);
        if (c.mode === "PLAYER") {
            c.base = target; c.baseIdentity = c.playerIdentity;
            c.fault = ""; c.state = "ACTIVE"; c.readyCommitted = true;
        }
        return true;
    }
    public static function bindExplicitScene(world:MovieClip, identity:Object, target:MovieClip,
            owner:Object, reset:Boolean):Object {
        if (!currentWorld(world,identity) || owner == undefined || !targetBelongs(target,world)) return undefined;
        var c:HorizontalScroller = getInstance();
        if (reset === true || c.worldIdentity !== identity || c.state === "DETACHED") c.bindWorld(world,identity);
        c.mode = "EXPLICIT"; c.base = target; c.baseIdentity = targetIdentity(target);
        c.explicitOwner = owner; c.fault = ""; c.state = "ACTIVE"; c.readyCommitted = true;
        return c.cameraScope;
    }
    private function bindWorld(world:MovieClip, identity:Object):Void {
        gameWorld = world; worldIdentity = identity; cameraScope = {epoch:++epoch};
        state = "WAIT_TARGET"; mode = "PLAYER"; fault = ""; readyCommitted = false;
        player = base = scrollObj = undefined;
        playerIdentity = baseIdentity = explicitOwner = undefined;
        focusStack.length = 0; currentFocus = undefined; nextFocusExpiry = 0;
        bgLayer = _root.天空盒; frameTimer = _root.帧计时器;
        bgWidth = world.背景长; bgHeight = world.背景高;
        horizonHeight = bgLayer.地平线高度;
        if (horizonHeight == undefined) horizonHeight = 0;
        bgLayer._x = 0;
        enableParallax = _root.启用后景 === true;
        enableCameraZoom = _root.cameraZoomToggle === true;
        stageWidth = Stage.width; stageHeight = Stage.height - 64;
        ZoomController.resetState();
        currentScale = _root.basicZoomScale;
        if (!(currentScale > 0) || (currentScale-currentScale) != 0) currentScale = 1;
        world._xscale = world._yscale = currentScale * 100;
        bgLayer._xscale = bgLayer._yscale = currentScale * 100;
        ZoomController.setCurrentScale(currentScale);
        cachedBoundsScale = -1;
        logicalWorldX = lastWrittenX = world._x;
        logicalWorldY = lastWrittenY = world._y;
        initialSnapPending = true; reframePending = false; poseCommitted = false;
        lastDriverCount = invokeCount; driverMissing = false; diagTick = 0;
        updateFunction = enableParallax ? updateWithParallax : updateWithoutParallax;
    }
    public static function sceneScope(world:MovieClip, identity:Object):Object {
        return instance && instance.worldIdentity === identity && instance.gameWorld === world
            && instance.state !== "DETACHED" ? instance.cameraScope : undefined;
    }
    public static function hasInitialPose(world:MovieClip, identity:Object, scope:Object):Boolean {
        return scope != undefined && currentWorld(world,identity) && sceneScope(world,identity) === scope && instance.poseCommitted === true;
    }
    public static function canReleaseScene(world:MovieClip, identity:Object):Boolean {
        return !instance || instance.state === "DETACHED"
            || (identity != undefined && instance.worldIdentity === identity && instance.gameWorld === world);
    }
    public static function releaseScene(world:MovieClip, identity:Object, scope:Object):Boolean {
        if (!instance) return scope == undefined;
        if (instance.state === "DETACHED") return scope == undefined
            || (identity === instance.retiredIdentity && scope === instance.retiredScope);
        var c:HorizontalScroller = instance;
        if (!canReleaseScene(world,identity) || (scope != undefined && scope !== c.cameraScope)) return false;
        c.retiredIdentity = c.worldIdentity; c.retiredScope = c.cameraScope;
        c.state = "DETACHED"; c.poseCommitted = false; c.fault = "";
        c.gameWorld = c.bgLayer = c.player = c.base = c.scrollObj = undefined;
        c.worldIdentity = c.cameraScope = c.playerIdentity = c.baseIdentity = c.explicitOwner = undefined;
        c.frameTimer = undefined; c.currentFocus = undefined; c.focusStack.length = 0;
        c.nextFocusExpiry = 0; c.updateFunction = undefined;
        ZoomController.resetState();
        return true;
    }
    public static function switchFollowTo(target:MovieClip):Void {
        if (!instance || instance.state === "DETACHED") return;
        var c:HorizontalScroller = instance;
        c.focusStack.length = 0; c.currentFocus = undefined; c.nextFocusExpiry = 0;
        if (target == undefined) { followPlayer(false); return; }
        if (!targetBelongs(target,c.gameWorld)) return;
        c.mode = "EXPLICIT"; c.base = target; c.baseIdentity = targetIdentity(target);
        c.fault = ""; c.state = "ACTIVE"; c.readyCommitted = true;
    }
    public static function followPlayer(snap:Boolean):Void {
        if (!instance || instance.state === "DETACHED") return;
        var c:HorizontalScroller = instance;
        c.mode = "PLAYER"; c.base = c.player; c.baseIdentity = c.playerIdentity; c.explicitOwner = undefined;
        c.fault = ""; c.reframePending = snap === true;
        c.state = c.validTarget(c.base,c.baseIdentity) ? "ACTIVE" : "WAIT_TARGET";
    }
    public static function pushFocus(target:MovieClip, frames:Number, snap:Boolean, ease:Number,
            tol:Number, biasX:Number, biasY:Number, minZoom:Number, owner:Object):Object {
        if (!instance || instance.state === "DETACHED" || !targetBelongs(target,instance.gameWorld)) return undefined;
        var c:HorizontalScroller = instance;
        var f:Object = {target:target, identity:targetIdentity(target), scope:c.cameraScope, owner:owner,
            expireFrame:frames > 0 ? c.frameTimer.当前帧数 + frames : 0,
            easeFactor:ease > 0 ? ease : c.easeFactor, offsetTolerance:tol == undefined || tol < 0 ? -1 : tol,
            biasX:biasX == undefined ? 0 : biasX, biasY:biasY == undefined ? 0 : biasY,
            minZoom:minZoom > 0 ? minZoom : 0, snapPending:snap === true, released:false};
        c.focusStack.push(f); c.recomputeExpiry();
        return f;
    }
    public static function popFocus():Void {
        if (!instance || instance.focusStack.length == 0) return;
        instance.focusStack.pop(); instance.recomputeExpiry();
    }
    /** Optional authored framing belongs to one existing focus; it never adds another camera driver. */
    public static function setFocusViewport(handle:Object,screenX:Number,screenY:Number,bounds:Array):Boolean {
        if(!instance || handle==null || !instance.validFocus(handle,instance.frameTimer.当前帧数)
                || !currentWorld(instance.gameWorld,instance.worldIdentity)) return false;
        var found:Boolean=false;
        for(var i:Number=0;i<instance.focusStack.length;i++) if(instance.focusStack[i]===handle) {found=true;break;}
        if(!found || typeof screenX!="number" || typeof screenY!="number"
                || (screenX-screenX)!=0 || (screenY-screenY)!=0
                || screenX<0 || screenX>1 || screenY<0 || screenY>1
                || !(bounds instanceof Array) || bounds.length!==4) return false;
        for(i=0;i<4;i++) if(typeof bounds[i]!="number" || (bounds[i]-bounds[i])!=0 || Math.abs(bounds[i])>1000000) return false;
        if(bounds[0]>bounds[2] || bounds[1]>bounds[3] || bounds[2]>0 || bounds[3]>0) return false;
        handle.viewport={x:screenX,y:screenY,minX:bounds[0],minY:bounds[1],maxX:bounds[2],maxY:bounds[3]};
        return true;
    }
    public static function releaseFocus(handle:Object):Boolean {
        if (!instance || handle == undefined || handle.scope !== instance.cameraScope || handle.released === true) return false;
        var found:Boolean = false;
        var i:Number = instance.focusStack.length;
        while (i--) if (instance.focusStack[i] === handle) { found = true; break; }
        if (!found) return false;
        handle.released = true;
        instance.compactFocus();
        return true;
    }
    private function validTarget(target:MovieClip, identity:Object):Boolean {
        return identity != undefined && target._x != undefined && target._parent != undefined
            && target.__cameraTargetIdentity === identity;
    }
    private function validFocus(f:Object, now:Number):Boolean {
        return f.scope === cameraScope && f.released !== true && validTarget(f.target,f.identity)
            && (!(f.expireFrame > 0) || now < f.expireFrame);
    }
    private function recomputeExpiry():Void {
        var earliest:Number = 0;
        var i:Number = focusStack.length;
        while (i--) {
            var expiry:Number = focusStack[i].expireFrame;
            if (expiry > 0 && (earliest == 0 || expiry < earliest)) earliest = expiry;
        }
        nextFocusExpiry = earliest;
    }
    private function compactFocus():Void {
        var now:Number = frameTimer.当前帧数;
        var count:Number = focusStack.length;
        var kept:Number = 0;
        var earliest:Number = 0;
        for (var i:Number = 0; i < count; i++) {
            var f:Object = focusStack[i];
            if (validFocus(f,now)) {
                focusStack[kept++] = f;
                if (f.expireFrame > 0 && (earliest == 0 || f.expireFrame < earliest)) earliest = f.expireFrame;
            }
        }
        focusStack.length = kept; nextFocusExpiry = earliest;
    }
    private function selectTarget():Boolean {
        var now:Number = frameTimer.当前帧数;
        if (nextFocusExpiry > 0 && !(now < nextFocusExpiry)) compactFocus();
        var count:Number = focusStack.length;
        while (count > 0 && !validFocus(focusStack[count-1],now)) { focusStack.pop(); count--; }
        currentFocus = count > 0 ? focusStack[count-1] : undefined;
        if (currentFocus != undefined) { scrollObj = currentFocus.target; return true; }
        if (validTarget(base,baseIdentity)) { scrollObj = base; return true; }
        scrollObj = undefined; state = "WAIT_TARGET";
        if (readyCommitted && fault === "") latchFault(mode === "EXPLICIT" ? "explicit_target_invalid" : "player_target_invalid");
        return false;
    }
    private function latchFault(reason:String):Void {
        state = "WAIT_TARGET";
        if (fault !== "") return;
        fault = reason;
        if (org.flashNight.arki.scene.StageRunSession.cameraObservationActive())
            org.flashNight.arki.scene.StageRunSession.cameraDiag("binding_fault",
                "reason=" + reason + " epoch=" + cameraScope.epoch + " frame=" + _root._currentframe
                + " mode=" + mode + " invoke=" + invokeCount + " update=" + updateCount);
    }
    private function performUpdate():Void {
        invokeCount++;
        if (state === "DETACHED") return;
        if (!currentWorld(gameWorld,worldIdentity)) { latchFault("world_identity_mismatch"); return; }
        // 曾有效绑定后的失效必须由匹配的合法通知解除，不能仅凭坐标恢复自行解锁。
        if (fault !== "" || !selectTarget()) return;
        state = "ACTIVE"; readyCommitted = true;
        updateFunction.call(this);
        updateCount++;
    }
    private function updateWithParallax():Void { composeFrame(true); }
    private function updateWithoutParallax():Void { composeFrame(false); }
    /** 同一个选定目标：缩放、边界、构图、一次整数写回，最后同步视差。 */
    private function composeFrame(parallax:Boolean):Void {
        var gw:MovieClip = gameWorld;
        if (gw._x !== lastWrittenX) logicalWorldX = gw._x;
        if (gw._y !== lastWrittenY) logicalWorldY = gw._y;
        zoomOffsetX = zoomOffsetY = 0;
        var effectiveEase:Number = currentFocus != undefined ? currentFocus.easeFactor : easeFactor;
        var minZoom:Number = currentFocus != undefined ? currentFocus.minZoom : 0;
        var newScale:Number = currentScale;
        if (enableCameraZoom) {
            var z:Object = ZoomController.updateScale(scrollObj,gw,bgLayer,effectiveEase,_root.basicZoomScale,minZoom);
            newScale = z.newScale; zoomOffsetX = z.offsetX; zoomOffsetY = z.offsetY;
        } else if (currentScale !== _root.basicZoomScale && _root.basicZoomScale > 0) {
            newScale = _root.basicZoomScale;
            // 固定倍率只在设置真的变化时计算补偿，不给稳定帧增加临时对象。
            zoomOffsetX = scrollObj._x * (currentScale-newScale);
            zoomOffsetY = scrollObj._y * (currentScale-newScale);
            gw._xscale = gw._yscale = newScale * 100;
            bgLayer._xscale = bgLayer._yscale = newScale * 100;
            ZoomController.setCurrentScale(newScale);
        }
        currentScale = newScale;
        updateBoundsForScale(newScale);
        var x:Number = logicalWorldX + zoomOffsetX;
        var y:Number = logicalWorldY + zoomOffsetY;
        var halfScale:Number = newScale * 0.5;
        var directionOffset:Number = 100 / (halfScale > 1 ? halfScale : 1);
        var tx:Number = stageWidth * 0.5 + (scrollObj._xscale > 0 ? -directionOffset : directionOffset);
        var ty:Number = stageHeight - 100;
        if (currentFocus != undefined) { tx += currentFocus.biasX; ty += currentFocus.biasY; }
        var viewport:Object=currentFocus.viewport;
        if(viewport!=undefined) {tx=stageWidth*viewport.x;ty=stageHeight*viewport.y;}
        var idealX:Number = tx - scrollObj._x * newScale;
        var idealY:Number = ty - scrollObj._y * newScale;
        var snap:Boolean = initialSnapPending || reframePending || currentFocus.snapPending === true;
        var tolerance:Number = frameTimer.offsetTolerance;
        if (tolerance == undefined) tolerance = offsetTolerance;
        if (currentFocus != undefined && !(currentFocus.offsetTolerance < 0)) tolerance = currentFocus.offsetTolerance;
        var dx:Number = idealX-x; var dy:Number = idealY-y;
        var ax:Number = dx < 0 ? -dx : dx; var ay:Number = dy < 0 ? -dy : dy;
        if (snap) { x = idealX; y = idealY; }
        else {
            if (ax > tolerance) x += ax > 1 ? dx/effectiveEase : dx;
            if (ay > tolerance) y += ay > 1 ? dy/effectiveEase : dy;
        }
        // 可呈现整数边界，避免小数边缘取整后反复越界。
        var minX:Number = boundsMinX; var minY:Number = boundsMinY;
        var maxX:Number=0,maxY:Number=0;
        if(viewport!=undefined) {
            minX=Math.max(minX,Math.ceil(viewport.minX*newScale));minY=Math.max(minY,Math.ceil(viewport.minY*newScale));
            maxX=Math.max(minX,Math.floor(viewport.maxX*newScale));maxY=Math.max(minY,Math.floor(viewport.maxY*newScale));
        }
        x = stageWidth < boundsEffBgW ? (x < minX ? minX : (x > maxX ? maxX : x)) : 0;
        y = stageHeight < boundsEffBgH ? (y < minY ? minY : (y > maxY ? maxY : y)) : 0;
        logicalWorldX = x; logicalWorldY = y;
        lastWrittenX = x < 0 ? ((x-0.5)|0) : ((x+0.5)|0);
        lastWrittenY = y < 0 ? ((y-0.5)|0) : ((y+0.5)|0);
        if (gw._x !== lastWrittenX) gw._x = lastWrittenX;
        if (gw._y !== lastWrittenY) gw._y = lastWrittenY;
        bgLayer._y = lastWrittenY + horizonHeight * newScale;
        if (parallax) {
            if (zoomOffsetX !== 0 || zoomOffsetY !== 0) ParallaxBackground.refreshOnZoom(bgLayer,lastWrittenX);
            else ParallaxBackground.updateParallax(bgLayer,frameTimer.当前帧数,lastWrittenX);
        }
        if (currentFocus != undefined) currentFocus.snapPending = false;
        initialSnapPending = reframePending = false; poseCommitted = true;
    }
    private function updateBoundsForScale(scale:Number):Void {
        if (this.cachedBoundsScale === scale &&
            this.cachedBoundsStageWidth === this.stageWidth &&
            this.cachedBoundsStageHeight === this.stageHeight) {
            return;
        }

        var effBgW:Number = this.bgWidth * scale;
        var effBgH:Number = this.bgHeight * scale;

        this.boundsEffBgW = effBgW;
        this.boundsEffBgH = effBgH;
        this.boundsMinX = Math.ceil(this.stageWidth - effBgW);
        this.boundsMaxX = 0;
        this.boundsMinY = Math.ceil(this.stageHeight - effBgH);
        this.boundsMaxY = 0;
        this.cachedBoundsScale = scale;
        this.cachedBoundsStageWidth = this.stageWidth;
        this.cachedBoundsStageHeight = this.stageHeight;
    }

    public static function refreshConfiguration():Void {
        if (!instance || instance.state === "DETACHED") return;
        instance.enableCameraZoom = _root.cameraZoomToggle === true;
    }
    public static function onFullScreenChanged():Void { onViewportChanged(); }
    public static function onViewportChanged():Void {
        if (!instance || instance.state === "DETACHED") return;
        var c:HorizontalScroller = instance;
        if (c.stageWidth === Stage.width && c.stageHeight === Stage.height-64) return;
        c.stageWidth = Stage.width; c.stageHeight = Stage.height-64;
        c.cachedBoundsScale = -1; c.reframePending = true;
    }
    /** 独立计时器观察 driver；绝不从这里代调 update 或修复现场。 */
    public static function observeDriver():Void {
        if (!instance || !org.flashNight.arki.scene.StageRunSession.cameraObservationActive()) return;
        var c:HorizontalScroller = instance;
        if (++c.diagTick < 15) return;
        c.diagTick = 0;
        var missing:Boolean = c.state !== "DETACHED" && c.invokeCount === c.lastDriverCount;
        if (missing && !c.driverMissing) org.flashNight.arki.scene.StageRunSession.cameraDiag("driver_missing",
            "frame=" + _root._currentframe + " invoke=" + c.invokeCount + " update=" + c.updateCount
            + " state=" + c.state + " fault=" + c.fault + " anchor=" + (_root.gameworld层级定位器._parent != undefined)
            + " worldDepth=" + _root.gameworld.getDepth() + " menuDepth=" + _root.修改工具界面.getDepth()
            + " menuVisible=" + _root.修改工具界面._visible);
        c.driverMissing = missing; c.lastDriverCount = c.invokeCount;
    }
    public function getDebugInfo():Object {
        return {hasScrollObj:scrollObj != undefined, enableParallax:enableParallax,
            bgDimensions:{width:bgWidth,height:bgHeight}, stageDimensions:{width:stageWidth,height:stageHeight},
            updateFunctionType:enableParallax ? "WithParallax" : "WithoutParallax",
            state:state, mode:mode, fault:fault, worldIdentity:worldIdentity, scope:cameraScope,
            selected:scrollObj, player:player, base:base, focusDepth:focusStack.length,
            focus:currentFocus, invokeCount:invokeCount, updateCount:updateCount,
            initialPoseCommitted:poseCommitted, enableCameraZoom:enableCameraZoom,
            logicalX:logicalWorldX, logicalY:logicalWorldY, scale:currentScale};
    }
}
