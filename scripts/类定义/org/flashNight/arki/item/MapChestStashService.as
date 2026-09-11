import org.flashNight.arki.item.RewardStashService;
import org.flashNight.arki.item.RewardStashStore;
import org.flashNight.arki.item.LootContainerService;
import org.flashNight.arki.item.LootMaterializationPlanner;
import org.flashNight.neur.Server.SaveManager;

/** 只接管已授权的正网格地图箱。现役存档不恢复 gameworld；每次重建明确分配新代际。 */
class org.flashNight.arki.item.MapChestStashService {
    private static var _world:Object = null;
    private static var _generation:Number = 0;
    private static var _boxSequence:Number = 0;

    public static function beginWorld(world:Object):Void {
        if (_world === world) return;
        _world = world; _boxSequence = 0;
        var prior:Object = _root._saveExt.mapStashSources;
        if (prior != null && !validLane(prior)) { _generation = -1; return; }
        var previous:Number = prior == null ? 0 : Number(prior.generation);
        _generation = Math.max(_generation, previous) + 1;
        if (!RewardStashStore.whole(_generation)) _generation = -1;
        // 只记运行时新代际，直到奖励提交才改存档。旧世界已销毁且不被存档恢复。
    }

    private static function validLane(lane:Object):Boolean {
        if (lane == null || lane.v !== 1 || !RewardStashStore.whole(lane.generation)) return false;
        if (!(lane.consumed instanceof Array)) {
            if (lane.consumed == null || typeof lane.consumed != "object") return false;
            for (var bad:String in lane.consumed) return false;
            return true;
        }
        var seen:Object = {};
        for (var i:Number = 0; i < lane.consumed.length; i++) {
            var id:Object = lane.consumed[i];
            if (typeof id != "string" || id.indexOf("map." + lane.generation + ".") != 0 || seen["$" + id]) return false;
            seen["$" + id] = true;
        }
        return true;
    }

    public static function isStashed(target:Object):Boolean {
        return target != null && target.__rewardStashCommitted === true;
    }

    public static function open(target:Object, killAction:Function):Object {
        if (LootContainerService.classifyMapChestShape(target) != "supported_web_grid") return {handled:false};
        if (_world == null || _world !== _root.gameworld || _generation < 1 || typeof killAction != "function") return rejected("source_identity_unavailable");
        if (SaveManager.getInstance().hasRewardCommitPending()) return rejected("commit_pending");
        if (org.flashNight.arki.item.RewardInboxService.hasActiveAuthority()) return rejected("legacy_recovery_required");
        var oldGuard:Object = LootContainerService.guardOpenGrid(target);
        if (oldGuard.handled || oldGuard.reason == "loot_reservation_ready") return {handled:false};
        if (isStashed(target)) {
            finishEntity(target, killAction);
            return {handled:true, success:true, duplicate:true};
        }
        if (target.__rewardStashSource == undefined) {
            _boxSequence++;
            target.__rewardStashSource = "map." + _generation + "." + _boxSequence;
        }
        var source:String = String(target.__rewardStashSource);
        if (source.indexOf("map." + _generation + ".") != 0) return rejected("stale_map_source");
        var lane:Object = _root._saveExt.mapStashSources;
        if (lane != null && !validLane(lane)) return rejected("map_source_quarantined");
        if (lane != null && lane.generation === _generation && lane.consumed instanceof Array) {
            for (var c:Number = 0; c < lane.consumed.length; c++) {
                if (lane.consumed[c] === source) {
                    target.__rewardStashCommitted = true;
                    finishEntity(target, killAction);
                    return {handled:true, success:true, duplicate:true};
                }
            }
        }
        var plan:Object = LootMaterializationPlanner.planForStash(target);
        if (plan == null || plan.success !== true) return rejected("materialization_failed");
        var context:Object = {source:"map_chest", reason:"opened_chest_stash", operationId:source, mergeScope:"operation"};
        var domain:Object = {target:target, plan:plan, killAction:killAction};
        if (!RewardStashService.begin(source, context, resolved, domain)) return rejected(RewardStashService.lastError);
        try {
            var items:Array = [];
            var raw:Object = plan.inventory.toObject();
            for (var s:Number = 0; s < plan.capacity; s++) if (raw[String(s)] != null) items.push(raw[String(s)]);
            if (!RewardStashService.admit(items, false, true, context)) throw new Error("invalid_map_reward");
            if (!LootMaterializationPlanner.commitStashSource(target)) throw new Error("source_changed");
            lane = _root._saveExt.mapStashSources;
            if (lane == null || lane.generation !== _generation) lane = {v:1, generation:_generation, consumed:[]};
            if (!(lane.consumed instanceof Array)) lane.consumed = [];
            lane.consumed.push(source); _root._saveExt.mapStashSources = lane;
            var result:Object = RewardStashService.end("map.stash.v2|" + source,
                {success:true, kind:"map_stash", sourceId:source}, "reward.map_stash");
            result.handled = true;
            return result;
        } catch (error) { return rejected(String(RewardStashService.cancel("map_stash_failed").error)); }
    }

    /** Only for an already materialized legacy container, within the same stash candidate. */
    public static function markLegacySource(target:Object):Boolean {
        if (_world !== _root.gameworld) beginWorld(_root.gameworld);
        if (_world == null || _generation < 1 || target == null) return false;
        if (target.__rewardStashSource == undefined) {
            _boxSequence++;
            if (!RewardStashStore.whole(_boxSequence)) return false;
            target.__rewardStashSource = "map." + _generation + "." + _boxSequence;
        }
        var source:String = String(target.__rewardStashSource);
        if (source.indexOf("map." + _generation + ".") != 0) return false;
        var lane:Object = _root._saveExt.mapStashSources;
        if (lane != null && !validLane(lane)) return false;
        if (lane == null || lane.generation !== _generation) lane = {v:1, generation:_generation, consumed:[]};
        if (!(lane.consumed instanceof Array)) lane.consumed = [];
        for (var i:Number = 0; i < lane.consumed.length; i++) if (lane.consumed[i] === source) return false;
        lane.consumed.push(source); _root._saveExt.mapStashSources = lane;
        return true;
    }

    private static function resolved(committed:Boolean, domain:Object):Boolean {
        if (!committed) return LootMaterializationPlanner.restoreStashSource(domain.target);
        domain.target.__rewardStashCommitted = true;
        finishEntity(domain.target, domain.killAction);
        try { _root.发布消息("箱中物资已存入暂存区。"); } catch (noticeError) { }
        return true;
    }

    private static function finishEntity(target:Object, killAction:Function):Void {
        if (target.__rewardStashEnded === true) return;
        try { if (killAction(target) === true) target.__rewardStashEnded = true; }
        catch (effectError) { trace("[MapChestStash] committed entity projection: " + effectError); }
    }

    private static function rejected(error:String):Object { return {handled:true, success:false, error:error}; }
}
