/** 世界低显示槽与 authored 定位器必须成对交换；身份不能使用可重指的 MC 引用。 */
class org.flashNight.arki.scene.SharedScenePlacement {
    private static var lease:Object;
    private static var busy:Boolean = false;
    public static var lastError:String = "";

    private static function fail(code:String):Boolean {
        lastError = code;
        return false;
    }
    private static function anchorMatches(root:MovieClip, p:Object):Boolean {
        var a:MovieClip = root.gameworld层级定位器;
        return a._parent === root && a.__sharedSceneAnchorIdentity === p.anchorIdentity
            && root._currentframe === p.displayFrame;
    }
    public static function canReuse(root:MovieClip, frame:Number):Boolean {
        var p:Object = lease;
        return !busy && p != undefined && p.state === "IDLE" && frame === p.displayFrame
            && anchorMatches(root,p) && root.gameworld层级定位器.getDepth() === p.lowDepth
            && root.gameworld == undefined;
    }
    public static function attach(root:MovieClip, linkage:String, init:Object):MovieClip {
        lastError = "";
        if (busy) { fail("placement_busy"); return undefined; }
        var a:MovieClip = root.gameworld层级定位器;
        if (a._parent !== root || !(a.getDepth() < 0) || root.gameworld != undefined) {
            fail("placement_missing_idle_anchor"); return undefined;
        }
        if (lease != undefined && lease.state !== "RETIRED" && !canReuse(root,root._currentframe)) {
            fail("placement_not_idle"); return undefined;
        }
        if (init.__stageReturnWorldIdentity == undefined) { fail("placement_missing_world_identity"); return undefined; }
        if (a.__sharedSceneAnchorIdentity == undefined) a.__sharedSceneAnchorIdentity = {};
        var high:Number = root.getNextHighestDepth();
        if (!(high > 0) || root.getInstanceAtDepth(high) != undefined) {
            fail("placement_dynamic_slot_occupied"); return undefined;
        }
        var p:Object = {state:"ATTACHING", root:root, anchorIdentity:a.__sharedSceneAnchorIdentity,
            lowDepth:a.getDepth(), highDepth:high, displayFrame:root._currentframe,
            worldIdentity:init.__stageReturnWorldIdentity};
        init.__sharedScenePlacementLease = p;
        init._visible = false;
        busy = true;
        var world:MovieClip;
        try {
            world = root.attachMovie(linkage,"gameworld",high,init);
            if (world._parent !== root || world.__stageReturnWorldIdentity !== p.worldIdentity) {
                fail("placement_attach_failed"); p.state = "FAULT"; lease = p; return undefined;
            }
            world.swapDepths(a);
            if (world.getDepth() !== p.lowDepth || a.getDepth() !== high) {
                fail("placement_attach_depth_mismatch"); p.state = "FAULT"; lease = p; return undefined;
            }
            world._visible = true;
            p.state = "BOUND";
            lease = p;
            return world;
        } finally { busy = false; }
    }
    /** 必须在 loot barrier 后、任何资源销毁前调用。无 lease 的旧测试世界保留原清理路径。 */
    public static function preflightDetach(world:MovieClip, identity:Object):Boolean {
        if (busy) return fail("placement_busy");
        var p:Object = world.__sharedScenePlacementLease;
        if (p == undefined) return lease == undefined || lease.state === "IDLE" || lease.state === "RETIRED";
        if (p !== lease || p.state !== "BOUND" || identity !== p.worldIdentity
                || world.__stageReturnWorldIdentity !== identity || !anchorMatches(p.root,p)
                || world.getDepth() !== p.lowDepth
                || p.root.gameworld层级定位器.getDepth() !== p.highDepth) return fail("placement_detach_invariant");
        return true;
    }
    public static function returnSlot(world:MovieClip, identity:Object):Boolean {
        if (!preflightDetach(world,identity)) return false;
        var p:Object = world.__sharedScenePlacementLease;
        if (p == undefined) return true;
        busy = true;
        try {
            world.swapDepths(p.root.gameworld层级定位器);
            if (world.getDepth() !== p.highDepth || p.root.gameworld层级定位器.getDepth() !== p.lowDepth) {
                p.state = "FAULT"; return fail("placement_return_depth_mismatch");
            }
            p.state = "DETACHING";
            return true;
        } finally { busy = false; }
    }
    public static function detached(world:MovieClip, identity:Object):Void {
        var p:Object = lease;
        if (p == undefined || p.state !== "DETACHING" || p.worldIdentity !== identity) return;
        p.worldIdentity = undefined;
        p.state = "IDLE";
    }
    /** 真正跳离根帧前退役精确的 idle anchor，不能依赖 swap 后的时间轴自动卸载。 */
    public static function retireIdle(root:MovieClip):Boolean {
        var p:Object = lease;
        if (p == undefined || p.state === "RETIRED") return true;
        if (!canReuse(root,p.displayFrame)) return fail("placement_retire_not_idle");
        var a:MovieClip = root.gameworld层级定位器;
        var high:Number = root.getNextHighestDepth();
        if (root.getInstanceAtDepth(high) != undefined) return fail("placement_retire_slot_occupied");
        busy = true;
        try {
            a.swapDepths(high);
            if (a.getDepth() !== high) return fail("placement_retire_depth_mismatch");
            a.removeMovieClip();
            p.state = "RETIRED";
            p.root = undefined;
            p.anchorIdentity = undefined;
            return true;
        } finally { busy = false; }
    }
    public static function diagnostics():Object {
        var p:Object = lease;
        return {state:p == undefined ? "DETACHED" : p.state, lowDepth:p.lowDepth,
            highDepth:p.highDepth, displayFrame:p.displayFrame, error:lastError};
    }
}
