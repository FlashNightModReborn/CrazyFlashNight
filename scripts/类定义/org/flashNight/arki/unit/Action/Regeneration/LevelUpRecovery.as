/** 升级 owner 保留有限恢复意图；投影重试不重新收费、发奖或回满。 */
class org.flashNight.arki.unit.Action.Regeneration.LevelUpRecovery {
    private static var context:Object;
    private static var claimedLevel:Number=-1;
    private static var latest:Object;
    private static var queued:Object;

    public static function captureIntentOwner(operationId:String):Object {
        var c:org.flashNight.arki.unit.PlayerStatRefreshCoordinator=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production();
        var actor:Object=_root.gameworld[_root.控制目标];
        return {operationId:operationId,context:c.contextToken(),actor:actor,body:actor.__playerStatBody,
            world:org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)};
    }
    private static function currentContext():Object {
        var token:Object=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production().contextToken();
        if(context!==token) {context=token;claimedLevel=-1;latest=null;queued=null;}
        else if(latest!=null && !latest.executing && latest.phase!="retired_actor" && latest.phase!="skipped_actor") {
            var expectedBody:Object=latest.scope.plan.activated===true ? latest.scope.plan.body : latest.owner.body;
            if(latest.owner.world!==org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)
                    || _root.gameworld[_root.控制目标]!==latest.actor || latest.actor.__playerStatBody!==expectedBody) {
                // 合法新场景/新体由它自己的完整初始化读取最新权威；旧成长不能迟到回满或卡住以后升级。
                latest.phase="retired_actor";latest.playEffect=false;
                if(queued!=null) claimedLevel=Math.max(claimedLevel,queued.level);
                queued=null;
            }
        }
        return token;
    }
    public static function refresh(target:Object,level:Number,owner:Object):Object {
        currentContext();
        if(!isFinite(level) || level<1 || level!=Math.floor(level)) return outcome("failed","growth_level_invalid");
        if(owner==null) owner=captureIntentOwner("");
        if(owner.context!==context) return outcome("failed","growth_context_changed");
        if(latest.phase=="tail" && latest.scope.plan.complete===true) latest.phase="completed";
        if(level<=claimedLevel) {
            if(latest!=null && latest.level==level && unfinished(latest)) {
                if(latest.phase=="tail") return resume(latest);
                return outcome("failed","growth_owner_recovery_required");
            }
            return outcome("unchanged","growth_intent_consumed");
        }
        if(latest!=null && unfinished(latest)) {
            // 暂停期间迟到的已提交更高等级保留一个最终意图，不覆盖正在恢复的 owner。
            if(queued==null || level>queued.level) queued={actor:target,level:level,owner:owner};
            org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production().invalidate(3,"growth",context);
            return outcome("failed","growth_owner_recovery_required");
        }
        claimedLevel=level;
        var c:org.flashNight.arki.unit.PlayerStatRefreshCoordinator=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production();
        c.invalidate(3,"growth",context);
        var intent:Object={context:context,owner:owner,level:level,actor:target,phase:"claimed",playEffect:false};
        latest=intent;
        if(target==undefined || owner.actor!==target || owner.body!==target.__playerStatBody
                || owner.world!==org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)
                || _root.gameworld[_root.控制目标]!==target) {
            intent.phase="skipped_actor";return outcome("pending","growth_actor_absent_or_replaced");
        }
        intent.hp=Number(target.hp);intent.mp=target.mp;intent.hasMp=isFinite(Number(target.mp)) && target.mp!=undefined;
        intent.alive=isFinite(intent.hp) && intent.hp>0;
        return execute(intent,null);
    }
    private static function execute(intent:Object,restartScope:Object):Object {
        var api:Object=org.flashNight.arki.unit.PlayerStatRefreshCoordinator;
        var target:Object=intent.actor;var scope:Object=restartScope;
        intent.executing=true;
        try {
            if(scope==null && target.hasDressup===true) scope=api.beginOuterInitialization(target,null);
            intent.scope=scope;intent.phase="started";
            target.等级=intent.level;
            target.根据等级初始数值(intent.level);
            if(api.production().contextToken()!==intent.context || _root.gameworld[_root.控制目标]!==target
                    || intent.owner.world!==org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)
                    || (scope!=null && target.__playerStatBody!==scope.plan.body)) throw new Error("growth_identity_changed");
            // 初始化已成功；一次恢复拥有自己的有效上限窗口。标志早于 setter，未知 setter 不重放。
            var r:Object;
            if(scope!=null) {
                r={hp:Number(target.hp),oldMax:Number(target.hp满血值),mp:Number(target.mp),stage:"captured",mode:"growth_one_shot"};
                scope.plan.ownerResources=r;
            }
            if(!intent.hpConsumed) {
                intent.hpConsumed=true;
                var healedHp:Number=intent.alive ? Number(target.hp满血值) : isFinite(intent.hp) && intent.hp<=0 ? intent.hp : 0;
                if(r!=null) {r.settledHp=healedHp;r.hpAttempted=true;}
                target.hp=healedHp;
                if(r!=null) r.hpDone=true;
            }
            if(!intent.mpConsumed) {
                intent.mpConsumed=true;
                if(intent.hasMp) {
                    var healedMp:Number=intent.alive ? Number(target.mp满血值) : Number(intent.mp);
                    if(r!=null) {r.settledMp=healedMp;r.mpAttempted=true;}
                    target.mp=healedMp;
                    if(r!=null) r.mpDone=true;
                }
            }
            intent.phase="tail";intent.playEffect=true;
            var result:Object=scope==null ? outcome("applied","") : api.endOuterInitialization(scope);
            if(result.status=="applied" || result.status=="unchanged") intent.phase="completed";
            result.playEffect=consumeEffect(intent);return result;
        } catch(error) {
            intent.phase="owner_recovery_required";
            if(scope!=null) api.failOuterInitialization(scope,error);
            return outcome("failed",String(error));
        } finally {intent.executing=false;}
    }
    /** 明确的原成长 owner 恢复入口；普通 dirty flush 只允许接续已经到达的纯尾部。 */
    public static function recoverCommitted(owner:Object):Object {
        currentContext();
        if(latest==null || latest.owner!==owner || owner.context!==context) return outcome("failed","growth_owner_mismatch");
        return recoverLatest();
    }
    public static function recoverLatest():Object {
        currentContext();
        var intent:Object=latest;
        if(intent==null) return outcome("unchanged","growth_intent_consumed");
        if(intent.phase=="skipped_actor" || intent.phase=="retired_actor")
            return org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production().flush("growth_replaced_actor");
        if(intent.executing) return outcome("pending","growth_reentrant");
        if(intent.context!==context || intent.owner.world!==org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)
                || _root.gameworld[_root.控制目标]!==intent.actor) return outcome("failed","growth_identity_changed");
        var oldBody:Object=intent.scope.plan.body;var result:Object;
        if(intent.phase=="completed") result=outcome("unchanged","");
        else if(intent.phase=="tail") result=resume(intent);
        else {
            var scope:Object=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.restartOuterInitialization(intent.scope);
            if(scope==null) return outcome("failed","growth_recovery_window_invalid");
            result=execute(intent,scope);
        }
        if(intent.phase=="completed" && queued!=null) {
            var next:Object=queued;queued=null;
            if(next.owner.context===context && next.owner.world===intent.owner.world && next.owner.actor===intent.actor
                    && (next.owner.body===oldBody || next.owner.body===intent.actor.__playerStatBody)) {
                var owner:Object={operationId:next.owner.operationId,context:context,world:next.owner.world,
                    actor:next.owner.actor,body:intent.actor.__playerStatBody};
                var nextResult:Object=refresh(next.actor,next.level,owner);
                nextResult.playEffect=nextResult.playEffect || result.playEffect;return nextResult;
            }
            return refresh(next.actor,next.level,next.owner);
        }
        return result;
    }
    private static function outcome(status:String,reason:String):Object {return {status:status,reason:reason,playEffect:false};}
    private static function unfinished(intent:Object):Boolean {return intent.phase!="completed" && intent.phase!="skipped_actor" && intent.phase!="retired_actor";}
    private static function consumeEffect(intent:Object):Boolean {
        if(!intent.playEffect || intent.effectConsumed) return false;
        intent.effectConsumed=true;return true;
    }
    private static function resume(intent:Object):Object {
        if(intent.context!==org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production().contextToken()) return outcome("failed","growth_context_changed");
        var result:Object=intent.scope.plan.complete===true ? outcome("unchanged","")
            : org.flashNight.arki.unit.PlayerStatRefreshCoordinator.resumeOuterInitialization(intent.scope);
        if(result.status=="applied" || result.status=="unchanged") intent.phase="completed";
        result.playEffect=consumeEffect(intent);return result;
    }
}
