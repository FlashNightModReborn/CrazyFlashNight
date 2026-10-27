/** 冷路径协调：只持有投影水位/身份，不拥有技能、装备、费用或保存事务。 */
class org.flashNight.arki.unit.PlayerStatRefreshCoordinator {
    public static var STATS:Number=1;
    public static var SKILLS:Number=2;
    public static var EQUIPMENT:Number=4;
    private static var instance:PlayerStatRefreshCoordinator;
    private var context:Object;
    private var actor:Object;
    private var world:Object;
    private var body:Object;
    private var appliedBody:Object;
    private var ready:Boolean;
    private var revision:Number;
    private var projectedRevision:Number;
    private var requested:Array;
    private var completed:Array;
    private var batchDepth:Number;
    private var flushing:Boolean;
    private var adapter:Object;
    private var checkpoint:Object;
    private var transition:Object;
    private var lastFailure:Object;
    private var contextOwner:Object;
    private var contextSlot:String;
    private var productionInstalled:Boolean;
    private var failureLease:String;
    private static var sceneScopes:Array=[];
    private static var spawnSeedHook:Function;
    private static var spawnResourceHook:Function;
    private static var spawnReadyHook:Function;
    private static var spawnRetireHook:Function;
    private static var spawnFailedHook:Function;
    /** 完整模板唯一尾部的窄接口；不改变换装/成长资源结算。 */
    public static function setSpawnLifecycleHooks(seed:Function,settle:Function,readyHook:Function,retireHook:Function,failedHook:Function):Void {
        spawnSeedHook=seed;spawnResourceHook=settle;spawnReadyHook=readyHook;spawnRetireHook=retireHook;spawnFailedHook=failedHook;
    }
    private static var gymGrowthReadGate:Function;
    private static var skillRewardReadGate:Function;

    /** Gym 在产生候选前登记只读门；数值核心不反向装载保存/库存领域。 */
    public static function setGymGrowthReadGate(value:Function):Void {gymGrowthReadGate=value;}
    public static function setSkillRewardReadGate(value:Function):Void {skillRewardReadGate=value;}
    private static function growthReadReason():String {
        if(gymGrowthReadGate!=undefined && gymGrowthReadGate()!==false) return "gym_save_pending";
        if(skillRewardReadGate!=undefined && skillRewardReadGate()!==false) return "skill_reward_pending";
        return "";
    }
    private static function growthReadable():Boolean {return growthReadReason()=="";}
    public static function _inputsReadableForTests():Boolean {return growthReadable();}

    public static function getInstance():PlayerStatRefreshCoordinator {
        if(instance==undefined) instance=new PlayerStatRefreshCoordinator();
        return instance;
    }
    public static function production():PlayerStatRefreshCoordinator {
        var c:PlayerStatRefreshCoordinator=getInstance();
        if(!c.productionInstalled) {c.adapter=productionAdapterFor(c);c.productionInstalled=true;}
        if(!c.sameAuthority(_root.存档系统,String(_root.savePath))) {
            c.resetContext(_root.存档系统,String(_root.savePath),_root._saveExt);
        }
        return c;
    }
    public static function _productionAdapterForTests(c:PlayerStatRefreshCoordinator):Object { return productionAdapterFor(c); }
    public function _releaseProjectionLeaseForTests():Void {
        if(failureLease!=undefined) org.flashNight.arki.pause.PauseManager.releaseLease(failureLease);
        failureLease=undefined;
    }
    private static function productionCurrent(c:PlayerStatRefreshCoordinator,s:Object):Boolean {
        return c.sameAuthority(_root.存档系统,String(_root.savePath))
            && _root.gameworld!=undefined
            && org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)===s.world
            && _root.gameworld[_root.控制目标]===s.actor && s.actor.__playerStatBody===s.body;
    }
    private static function resourceWindow(actor:Object,r:Object):Void {
        if(r==null) return;
        if(r.invalid===true) throw new Error("resource_contract_violation");
        var hp:Number=r.hpDone ? r.settledHp : r.hp;
        var mp:Number=r.mpDone ? r.settledMp : r.mp;
        if(Number(actor.hp)!==hp || Number(actor.mp)!==mp) {
            r.invalid=true;throw new Error("resource_window_changed");
        }
    }
    private static function productionAdapterFor(c:PlayerStatRefreshCoordinator):Object {
        return {
            isCurrent:function(s:Object):Boolean {return PlayerStatRefreshCoordinator.productionCurrent(c,s);},
            canProject:function(s:Object):Boolean {return s.actor.hasDressup===true;},
            canConsume:function():Boolean {return PlayerStatRefreshCoordinator.growthReadable();},
            compute:function(s:Object,mask:Number):Object {
                var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
                return api.buildPersistentSnapshot(s.actor,(mask & 2)!=0 ? _root.主角被动技能 : undefined);
            },
            captureResources:function(s:Object,record:Object):Object {
                var t:Object=s.actor;
                var r:Object={hp:Number(t.hp),oldMax:Number(t.hp满血值),mp:Number(t.mp),hpDone:false,mpDone:false};
                if(!isFinite(r.hp) || !(r.oldMax>0) || !isFinite(r.oldMax) || !isFinite(r.mp)) throw new Error("resource_capture_invalid");
                record.resourceWindow=r;return r;
            },
            commit:function(s:Object,record:Object,r:Object):Void {
                PlayerStatRefreshCoordinator.resourceWindow(s.actor,r);
                var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
                try {
                    api.applyPersistentSnapshot(s.actor,record);
                    s.actor.__statProjectionCommit=true;
                    try {api.refreshPersistentWeaponCaches(s.actor,record);}
                    finally {s.actor.__statProjectionCommit=false;}
                } finally {
                    if(Number(s.actor.hp)!==r.hp || Number(s.actor.mp)!==r.mp) {
                        r.invalid=true;throw new Error("resource_contract_violation");
                    }
                }
            },
            settleResources:function(s:Object,record:Object,r:Object):Void {
                PlayerStatRefreshCoordinator.resourceWindow(s.actor,r);
                if(!r.hpDone) {
                    r.settledHp=org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleHpAfterMaxChange(r.hp,r.oldMax,Number(s.actor.hp满血值));
                    if(Number(s.actor.hp)!==r.settledHp) s.actor.hp=r.settledHp;
                    r.hpDone=true;
                }
                if(!r.mpDone) {
                    r.settledMp=org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleMpAfterMaxChange(r.mp,Number(s.actor.mp满血值));
                    if(Number(s.actor.mp)!==r.settledMp) s.actor.mp=r.settledMp;
                    r.mpDone=true;
                }
            },
            derive:function(s:Object,record:Object):Void {
                PlayerStatRefreshCoordinator.resourceWindow(s.actor,record.resourceWindow);
                org.flashNight.arki.component.StatHandler.ImpactHandler.refreshImpactDerived(s.actor);
                org.flashNight.arki.unit.PlayerInfoProvider.invalidateDpsCache(s.actor);
                if(typeof _root.玩家信息界面.刷新hp显示=="function") _root.玩家信息界面.刷新hp显示();
                if(typeof _root.玩家信息界面.刷新mp显示=="function") _root.玩家信息界面.刷新mp显示();
                if(typeof _root.玩家信息界面.刷新攻击模式=="function") _root.玩家信息界面.刷新攻击模式(s.actor.攻击模式);
                s.actor.__statImpactPending=false;
            },
            verify:function(s:Object,record:Object):Boolean {
                PlayerStatRefreshCoordinator.resourceWindow(s.actor,record.resourceWindow);
                return org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer.verifyPersistentSnapshot(s.actor,record);
            },
            block:function(s:Object,stage:String,reason:String):Void {
                if(c.failureLease==undefined) c.failureLease=org.flashNight.arki.pause.PauseManager.lease(true,"player_stat_projection");
                if(s.actor.__playerStatProjectionBlocked!==true) s.actor.__playerStatShootBeforeFault=s.actor.enableShoot;
                s.actor.__playerStatProjectionBlocked=true;s.actor.enableShoot=false;
            },
            blockIdentityFault:function():Void {
                if(c.failureLease==undefined) c.failureLease=org.flashNight.arki.pause.PauseManager.lease(true,"player_stat_projection");
            },
            unblock:function(s:Object):Void {
                if(s.actor.__playerStatProjectionBlocked===true) {
                    s.actor.enableShoot=s.actor.__playerStatShootBeforeFault;
                    delete s.actor.__playerStatShootBeforeFault;
                }
                s.actor.__playerStatProjectionBlocked=false;
                // release 可同步重入并创建新 context/lease；先交出旧令牌，不能擦掉后来取得的责任。
                var releasedLease=c.failureLease;c.failureLease=undefined;
                if(releasedLease!=undefined) org.flashNight.arki.pause.PauseManager.releaseLease(releasedLease);
            },
            verifyEquipmentInput:function(ticket:Object):Boolean {
                return ticket.proof!=null && typeof ticket.owner.verifyInput=="function" && ticket.owner.verifyInput(ticket.proof)===true;
            },
            rebuild:function(ticket:Object):Void {ticket.owner.rebuild(ticket);},
            verifyEquipment:function(ticket:Object):Boolean {
                return ticket.actor.__playerStatFullReady===ticket.targetBody
                    && typeof ticket.owner.verifyOutput=="function" && ticket.owner.verifyOutput(ticket.proof)===true;
            },
            abortEquipment:function(ticket:Object):Void {
                if(ticket.actor.__playerStatBody===ticket.targetBody
                        && PlayerStatRefreshCoordinator.productionCurrent(c,{actor:ticket.actor,world:ticket.world,body:ticket.targetBody})) {
                    ticket.actor.__playerStatProjectionBlocked=true;ticket.actor.enableShoot=false;
                }
            }
        };
    }
    public static function beginSceneInitialization(value:Object):Object {
        var readReason:String=growthReadReason();if(readReason!="") throw new Error(readReason);
        var c:PlayerStatRefreshCoordinator=production();
        var scope:Object={context:c.context,world:org.flashNight.arki.scene.StageReturnFlow.worldIdentity(value),open:true};
        sceneScopes.push(scope);return scope;
    }
    public static function endSceneInitialization(scope:Object):Object {
        if(scope==null || scope.open!==true) return {status:"failed",reason:"scene_scope_mismatch"};
        scope.open=false;
        for(var i:Number=sceneScopes.length-1;i>=0;i--) if(sceneScopes[i]===scope) sceneScopes.splice(i,1);
        var c:PlayerStatRefreshCoordinator=production();
        if(scope.context!==c.context || scope.world!==org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)) return {status:"failed",reason:"stale_scene_scope"};
        var target:Object=_root.gameworld[_root.控制目标];
        var plan:Object=target.__playerStatInitPlan;
        if(scope.failed===true) return {status:"failed",reason:"scene_initialization_failed"};
        return plan==undefined ? {status:"pending",reason:"pending_actor"} : finishFullPlan(plan);
    }
    public static function failSceneInitialization(scope:Object,error:Object):Void {
        if(scope==null || scope.context!==production().context) return;
        scope.failed=true;
        var plan:Object=_root.gameworld[_root.控制目标].__playerStatInitPlan;
        if(plan!=undefined && plan.context===scope.context && plan.world===scope.world) failOuterInitialization({plan:plan},error);
    }
    private static function scenePending(plan:Object):Boolean {
        if(plan.coordinator==null) return false;
        for(var i:Number=0;i<sceneScopes.length;i++) {
            var scope:Object=sceneScopes[i];
            if(scope.open && scope.context===plan.context && scope.world===plan.world) return true;
        }
        return false;
    }
    public static function validateSpawnResourceSeed(target:Object):Void {
        if(spawnSeedHook!=undefined) spawnSeedHook(target);
    }
    public static function beginOuterInitialization(target:Object,ticket:Object):Object {
        if(spawnSeedHook!=undefined) spawnSeedHook(target);
        var currentCoordinator:PlayerStatRefreshCoordinator=production();
        var isHero:Boolean=target._name===_root.控制目标;
        if(isHero) {var readReason:String=growthReadReason();if(readReason!="") throw new Error(readReason);}
        var plan:Object=target.__playerStatInitPlan;
        if(target.__playerStatInitializing!==true || plan==undefined || plan.complete===true
                || plan.context!==currentCoordinator.context || (ticket!=null && plan.ticket!==ticket)) {
            plan={actor:target,context:currentCoordinator.context,
                world:org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld),
                body:ticket==null ? {} : ticket.targetBody,sourceBody:target.__playerStatBody,ticket:ticket,coordinator:isHero ? currentCoordinator : null,
                open:0,activated:false,complete:false,stage:"planned",ownerResources:ticket.recoveryResources};
            target.__playerStatInitPlan=plan;
            if(plan.ownerResources==undefined && isFinite(Number(target.hp)) && isFinite(Number(target.mp))
                    && Number(target.hp满血值)>0 && isFinite(Number(target.hp满血值)))
                plan.ownerResources={hp:Number(target.hp),oldMax:Number(target.hp满血值),mp:Number(target.mp),stage:"captured"};
        }
        if(plan.failed===true) throw new Error("lifecycle_owner_recovery_required");
        target.__playerStatInitializing=true;target.__playerStatFullReady=null;plan.open++;
        if(isHero) {
            currentCoordinator.revokeReady(target,target.__playerStatBody);
            currentCoordinator.adapter.blockIdentityFault();
        }
        return {plan:plan,open:true};
    }
    /** 遗留完整换装仍由原入口执行一次；它不能把失败后的 dirty 当成再初始化许可。 */
    public static function admitLegacyEquipmentMutation():Boolean {
        var c:PlayerStatRefreshCoordinator=production();
        if(c.equipmentTransition()!=null) return false;
        var result:Object=c.flush("legacy_equipment_admission");
        return result.status=="applied" || result.status=="unchanged";
    }
    public static function refreshLegacyEquipment(target:Object):Object {
        var c:PlayerStatRefreshCoordinator=production();
        var existing:Object=c.equipmentTransition();
        if(existing!=null) return c.flush("legacy_equipment");
        var projection:Object=org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        var inventory:Object=_root.物品栏.装备栏;
        if(typeof inventory.getItem!="function") return {status:"failed",reason:"equipment_inventory_missing"};
        var keys:Array=projection.getSlotKeys();var refs:Array=[];
        for(var i:Number=0;i<keys.length;i++) refs[i]=inventory.getItem(keys[i]);
        var proof:Object={context:c.context,actor:target,world:c.world,inventory:inventory,refs:refs,
            signature:projection.buildSemanticSignature(refs)};
        var owner:Object=legacyEquipmentOwner(proof);
        var ticket:Object=c.prepareEquipmentTransition(proof,owner);
        if(ticket==null) return {status:"failed",reason:"equipment_ticket_unavailable"};
        target.__legacyStatEquipmentOwner=owner;
        c.invalidate(4,"legacy_equipment",c.contextToken());return c.flush("legacy_equipment");
    }
    private static function legacyEquipmentOwner(proof:Object):Object {
        return {
            verifyInput:function(p:Object):Boolean {return p===proof && PlayerStatRefreshCoordinator.legacyEquipmentCurrent(p);},
            rebuild:function(ticket:Object):Void {_root.刷新人物装扮(proof.actor._name,ticket);},
            verifyOutput:function(p:Object):Boolean {return p===proof && PlayerStatRefreshCoordinator.legacyEquipmentCurrent(p)
                && PlayerStatRefreshCoordinator.canonicalCurrent(p.actor);}
        };
    }
    private static function legacyEquipmentCurrent(proof:Object):Boolean {
        var c:PlayerStatRefreshCoordinator=production();
        if(proof.context!==c.context || proof.world!==c.world || _root.gameworld[_root.控制目标]!==proof.actor
                || _root.物品栏.装备栏!==proof.inventory) return false;
        var projection:Object=org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        var keys:Array=projection.getSlotKeys();var refs:Array=[];
        for(var i:Number=0;i<keys.length;i++) {
            refs[i]=proof.inventory.getItem(keys[i]);if(refs[i]!==proof.refs[i]) return false;
        }
        return proof.signature!=null && projection.buildSemanticSignature(refs)===proof.signature;
    }
    /** 只供原完整 owner 的显式恢复动作调用；普通 flush 不会走中止/新 ticket。 */
    public static function recoverLegacyEquipment(target:Object):Object {
        var c:PlayerStatRefreshCoordinator=production();var ticket:Object=c.equipmentTransition();
        var owner:Object=target.__legacyStatEquipmentOwner;
        if(ticket==null || ticket.owner!==owner) return {status:"failed",reason:"equipment_owner_mismatch"};
        if(ticket.actor.__playerStatInitPlan.tailCheckpoint!=undefined) {
            var resumed:Object=resumeFullInitialization(ticket,owner);
            return resumed.status=="applied" || resumed.status=="unchanged" ? c.flush("legacy_equipment_recovered") : resumed;
        }
        var resources:Object=c.fullRecoveryResources(ticket,owner);
        if(resources==null || !c.abortEquipmentTransition(ticket,owner)) return {status:"failed",reason:"equipment_recovery_window_invalid"};
        var next:Object=c.prepareEquipmentTransition(ticket.proof,owner);if(next==null) return {status:"failed",reason:"equipment_ticket_unavailable"};
        next.recoveryResources=resources;
        // 原 owner 已验证并显式中止旧 ticket；只将这个 ticket 自己的后续模式意图交给预分配新体。
        var continuation:Object=target.__pickupEquipmentModeReceipt;
        if(continuation.ticket===ticket && continuation.context===ticket.context && continuation.world===ticket.world
                && continuation.actor===target && continuation.body===ticket.targetBody) {
            continuation.ticket=next;continuation.body=next.targetBody;
        }
        c.invalidate(4,"legacy_equipment",c.contextToken());return c.flush("legacy_equipment_owner_restart");
    }
    public static function activateInitialization(target:Object):Void {
        if(target.hasDressup!==true) {
            target.__playerStatBody={};
            if(target._name===_root.控制目标) production().detachHeroBinding();
            return;
        }
        var plan:Object=target.__playerStatInitPlan;
        if(plan==undefined || target.__playerStatInitializing!==true) {
            var implicit:Object=beginOuterInitialization(target,null);plan=implicit.plan;plan.implicitScope=implicit;
        }
        var c:PlayerStatRefreshCoordinator=plan.coordinator;
        if(plan.activated===true || plan.context!==production().context
                || plan.world!==org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)) throw new Error("lifecycle_plan_mismatch");
        if(plan.ticket!=null) {
            if(c==null || c.startEquipmentTransition(plan.ticket,target)!==plan.body) throw new Error("equipment_body_ticket_rejected");
        } else {
            target.__playerStatBody=plan.body;
            if(c!=null && !c.bindHero(target,plan.world,plan.body,plan.context)) throw new Error("lifecycle_bind_rejected");
        }
        plan.activated=true;plan.stage="initializing";
        target.__playerStatProjectionBlocked=false;
        delete target.__playerStatShootBeforeFault;
        delete target.__persistentStatBase;
        delete target.变形手枪;
        delete target.__dominatorModeReadyBody;
    }
    public function detachHeroBinding():Void {
        actor=null;world=null;body=null;ready=false;appliedBody=null;checkpoint=null;
    }
    private static function planCurrent(plan:Object):Boolean {
        var target:Object=plan.actor;
        return plan.context===production().context && target.__playerStatBody===plan.body
            && plan.world===org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)
            && (plan.coordinator==null || _root.gameworld[_root.控制目标]===target);
    }
    public static function prepareFullNumeric(target:Object,scope:Object):Void {
        var plan:Object=scope.plan;
        if(plan.coordinator!=null) {var readReason:String=growthReadReason();if(readReason!="") throw new Error(readReason);}
        if(!planCurrent(plan) || !plan.activated) throw new Error("lifecycle_numeric_identity_changed");
        var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        plan.stage="prepare_numeric";
        var captured:Object=plan.coordinator==null ? null : plan.coordinator.capture();
        var record:Object=api.buildPersistentSnapshot(target,plan.coordinator==null ? undefined : _root.主角被动技能);
        if(!planCurrent(plan)) throw new Error("lifecycle_numeric_identity_changed");
        api.applyPersistentSnapshot(target,record);
        target.__statProjectionCommit=true;
        try {api.refreshPersistentWeaponCaches(target,record);} finally {target.__statProjectionCommit=false;}
        if(!planCurrent(plan)) throw new Error("lifecycle_numeric_identity_changed");
        plan.record=record;plan.numericSnapshot=captured;plan.stage="numeric_prepared";
        target.__playerStatNeedsNumericTail=false;
    }
    public static function finishOuterAfterState(target:Object,label:String,scope:Object):Void {
        if(!planCurrent(scope.plan)) throw new Error("lifecycle_state_identity_changed");
        var routing:Object=org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntent;
        routing.createStateTransitionJob(target,label,stateCompletion(scope));
        target.gotoAndStop(label);
        routing.executeStateTransitionJob(target);
    }
    private static function stateCompletion(scope:Object):Function {
        return function(target:Object):Void {
            if(!PlayerStatRefreshCoordinator.planCurrent(scope.plan)) return;
            try {
                if(typeof _root.装备引用配置.刷新所有装扮=="function") _root.装备引用配置.刷新所有装扮(target);
                PlayerStatRefreshCoordinator.endOuterInitialization(scope);
            } catch(error) {
                PlayerStatRefreshCoordinator.failOuterInitialization(scope,error);
                throw error;
            }
        };
    }
    public static function endOuterInitialization(scope:Object):Object {
        if(scope==null || scope.open!==true) return {status:"failed",reason:"lifecycle_scope_mismatch"};
        scope.open=false;var plan:Object=scope.plan;plan.open--;
        if(plan.open==0) plan.finalScope=scope;
        return finishFullPlan(plan);
    }
    public static function failOuterInitialization(scope:Object,error:Object):Void {
        if(scope==null || scope.plan==null || !planCurrent(scope.plan)
                || scope.plan.actor.__playerStatInitPlan!==scope.plan) return;
        var plan:Object=scope.plan;plan.failed=true;
        if(scope.open===true) {scope.open=false;plan.open--;}
        var c:PlayerStatRefreshCoordinator=plan.coordinator;
        if(c!=null) {
            c.revokeReady(plan.actor,plan.actor.__playerStatBody);
            if(plan.actor.__playerStatBody===plan.body) plan.actor.__playerStatFullReady=null;
            c.fail(c.capture(),"lifecycle:"+plan.stage,error);
        } else if(spawnFailedHook!=undefined) spawnFailedHook(plan.actor,plan.body,error);
    }
    public static function notifyModeComponentReady(target:Object,capturedBody:Object):Void {
        if(capturedBody==null || target.__playerStatBody!==capturedBody || target.变形手枪.属性投影身体!==capturedBody) return;
        var plan:Object=target.__playerStatInitPlan;
        if(plan==undefined || !planCurrent(plan)) return;
        target.__dominatorModeReadyBody=capturedBody;
        if(plan.open==0) finishFullPlan(plan);
    }
    private static function modeComponentsReady(plan:Object):Boolean {
        var target:Object=plan.actor;
        var projection:Object=org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        return projection.numericSourceRef(target,"手枪").name!="dominator" || target.__dominatorModeReadyBody===plan.body;
    }
    private static function canonicalCurrent(target:Object):Boolean {
        var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        var projection:Object=org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        if(api.readNumericSources(target)==null) return false;
        if(target._name!==_root.控制目标) return true;
        var inventory:Object=_root.物品栏.装备栏;
        if(typeof inventory.getItem!="function") return false;
        var keys:Array=projection.getSlotKeys();var refs:Array=[];
        for(var i:Number=0;i<keys.length;i++) refs[i]=inventory.getItem(keys[i]);
        return projection.getStatus(target,refs)==projection.STATUS_ALIGNED;
    }
    private static function finishFullPlan(plan:Object):Object {
        if(plan.complete===true) return {status:"unchanged",reason:""};
        if(!planCurrent(plan)) return {status:"failed",reason:"stale_lifecycle"};
        if(plan.open>0 || scenePending(plan)) return {status:"pending",reason:"outer_initialization"};
        if(!modeComponentsReady(plan)) {plan.stage="waiting_mode_component";return {status:"pending",reason:"mode_component"};}
        if(plan.failed===true) return {status:"failed",reason:"lifecycle_owner_recovery_required"};
        var target:Object=plan.actor;var c:PlayerStatRefreshCoordinator=plan.coordinator;
        var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        try {
            if(!canonicalCurrent(target)) throw new Error("full_equipment_source_changed");
            plan.stage="final_numeric";
            if(c==null) {
                if(target.__playerStatNeedsNumericTail || plan.record==undefined) {
                    var hp:Number=Number(target.hp);var maxHp:Number=Number(target.hp满血值);var mp:Number=Number(target.mp);var maxMp:Number=Number(target.mp满血值);
                    var npcRecord:Object=api.buildPersistentSnapshot(target);api.applyPersistentSnapshot(target,npcRecord);api.refreshPersistentWeaponCaches(target,npcRecord);
                    if(maxHp!=target.hp满血值) target.hp=org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleHpAfterMaxChange(hp,maxHp,Number(target.hp满血值));
                    if(maxMp!=target.mp满血值) target.mp=org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleMpAfterMaxChange(mp,Number(target.mp满血值));
                    plan.record=npcRecord;
                }
                if(!api.verifyPersistentSnapshot(target,plan.record)) throw new Error("full_stat_postcondition_failed");
                if(spawnResourceHook!=undefined) spawnResourceHook(target,null);
                target.__playerStatFullReady=plan.body;target.__playerStatInitializing=false;plan.complete=true;
                if(spawnReadyHook!=undefined) spawnReadyHook(target);
                return {status:"applied",reason:""};
            }
            if(plan.tailCheckpoint==undefined) {
                var s:Object=c.capture();
                var needsNumbers:Boolean=target.__playerStatNeedsNumericTail || plan.record==undefined || plan.numericSnapshot.revision!=s.revision;
                var record:Object=needsNumbers ? c.adapter.compute(s,3) : plan.record;
                var resources:Object=c.adapter.captureResources(s,record);
                // 完整 owner / 转场已确认的资源例外，在上限未改变时按原值保留。
                if(record.expected.hp满血值==target.hp满血值) {resources.hpDone=true;resources.settledHp=resources.hp;}
                if(record.expected.mp满血值==target.mp满血值) {resources.mpDone=true;resources.settledMp=resources.mp;}
                plan.tailCheckpoint={snapshot:s,record:record,resources:resources,stage:needsNumbers ? "captured" : "committed"};
            }
            var cp:Object=plan.tailCheckpoint;
            if(!planCurrent(plan)) throw new Error("lifecycle_identity_changed");
            if(cp.stage=="captured") {c.adapter.commit(cp.snapshot,cp.record,cp.resources);cp.stage="committed";}
            if(!planCurrent(plan)) throw new Error("lifecycle_identity_changed");
            if(cp.stage=="committed") {c.adapter.settleResources(cp.snapshot,cp.record,cp.resources);cp.stage="settled";}
            if(spawnResourceHook!=undefined) spawnResourceHook(target,cp.resources);
            c.adapter.derive(cp.snapshot,cp.record);
            if(!planCurrent(plan) || !canonicalCurrent(target) || c.adapter.verify(cp.snapshot,cp.record)!==true) throw new Error("full_stat_postcondition_failed");
            target.__playerStatFullReady=plan.body;
            if(plan.ticket!=null) plan.ticket.coveredSnapshot=cp.snapshot;
            if(!c.notifyReady(target,plan.world,plan.body,plan.context,plan.ticket)) throw new Error("full_final_ready_rejected");
            target.__playerStatInitializing=false;target.__playerStatNeedsNumericTail=false;
            if(plan.ticket==null) {
                // PauseManager 的释放可同步回调消费者；发布期间禁止重入另一次提交。
                var wasFlushing:Boolean=c.flushing;c.flushing=true;
                try {
                    c.adapter.unblock(cp.snapshot);
                    if(!planCurrent(plan) || !canonicalCurrent(target) || c.adapter.verify(cp.snapshot,cp.record)!==true) throw new Error("full_stat_postcondition_failed");
                    c.accept(cp.snapshot);
                } finally {c.flushing=wasFlushing;}
                plan.complete=true;plan.stage="completed";plan.initialReadyPending=true;
                var initialReady:Object=c.flush("initial_ready");
                return initialReady;
            }
            plan.complete=true;plan.stage="completed";
            return {status:"applied",reason:""};
        } catch(error) {failOuterInitialization({plan:plan},error);return {status:"failed",reason:String(error.message)};}
    }
    public static function resumeFullInitialization(ticket:Object,owner:Object):Object {
        var plan:Object=ticket.actor.__playerStatInitPlan;
        if(ticket.owner!==owner || ticket.status!="started" || plan.ticket!==ticket || plan.tailCheckpoint==undefined
                || plan.open!=0 || !planCurrent(plan)) return {status:"failed",reason:"lifecycle_abort_required"};
        plan.failed=false;return finishFullPlan(plan);
    }
    /** 初生/成长原 owner 持有的 scope，只可恢复已到达的数值尾部。 */
    public static function resumeOuterInitialization(scope:Object):Object {
        var plan:Object=scope.plan;
        if(plan==undefined || plan.finalScope!==scope || plan.ticket!=null || scope.open===true || plan.open!=0
                || plan.tailCheckpoint==undefined || !planCurrent(plan)) return {status:"failed",reason:"lifecycle_abort_required"};
        plan.failed=false;return finishFullPlan(plan);
    }
    /** 原完整 owner 的显式早期恢复：已知资源窗口、旧 scope 和身体都必须仍然匹配。 */
    public static function restartOuterInitialization(scope:Object):Object {
        var plan:Object=scope.plan;var c:PlayerStatRefreshCoordinator=plan.coordinator;
        if(plan==null || c==null || plan.ticket!=null || plan.failed!==true || plan.open!=0 || scope.open===true
                || plan.tailCheckpoint!=undefined || plan.recoveryIssued===true || plan.actor.__playerStatInitPlan!==plan
                || plan.context!==production().context || plan.world!==org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)
                || _root.gameworld[_root.控制目标]!==plan.actor
                || plan.actor.__playerStatBody!==(plan.activated ? plan.body : plan.sourceBody)) return null;
        var resources:Object=knownFullResources(plan);
        if(resources==null) return null;
        plan.recoveryIssued=true;plan.actor.__playerStatInitializing=false;
        var next:Object=beginOuterInitialization(plan.actor,null);
        next.plan.ownerResources=resources;
        return next;
    }
    public function PlayerStatRefreshCoordinator() {
        adapter={}; revision=0; projectedRevision=0; requested=[0,0,0]; completed=[0,0,0];
        batchDepth=0; flushing=false; ready=false; context={};
    }
    public function setAdapter(value:Object):Void { adapter=value; }
    public function contextToken():Object { return context; }
    public function sameAuthority(owner:Object,slot:String):Boolean {
        return contextOwner===owner && contextSlot===slot;
    }
    public function resetContext(owner:Object,slot:String,ext:Object):Object {
        if(this===instance) {
            sceneScopes=[];
            if(spawnRetireHook!=undefined) spawnRetireHook("context_reset");
        }
        // releaseLease 会同步通知订阅者，必须先让它们只能看见已 detach 的新上下文。
        var oldFailureLease:String=failureLease;
        failureLease=undefined;
        // 真实换档/同槽重读由 owner 显式 mint generation；普通奖励保存会克隆 ext，不换角色。
        context={};contextOwner=owner;contextSlot=slot;
        actor=null;world=null;body=null;appliedBody=null;ready=false;
        checkpoint=null;transition=null;lastFailure=null;batchDepth=0;
        revision++; requested=[revision,revision,0]; completed=[0,0,0]; projectedRevision=0;
        if(oldFailureLease!=undefined) org.flashNight.arki.pause.PauseManager.releaseLease(oldFailureLease);
        return context;
    }
    public function bindHero(value:Object,worldToken:Object,bodyToken:Object,contextToken:Object):Boolean {
        if(contextToken!==context || value==null || bodyToken==null || worldToken==null) return false;
        if(actor!==value || world!==worldToken || body!==bodyToken) {
            actor=value;world=worldToken;body=bodyToken;ready=false;appliedBody=null;checkpoint=null;
        }
        return true;
    }
    public function revokeReady(value:Object,bodyToken:Object):Void {
        if(actor===value && body===bodyToken) ready=false;
    }
    public function notifyReady(value:Object,worldToken:Object,bodyToken:Object,contextToken:Object,ticket:Object):Boolean {
        if(ticket!=null) return completeEquipmentTransition(ticket,value,worldToken,bodyToken,contextToken);
        if(contextToken!==context || actor!==value || world!==worldToken || body!==bodyToken
                || value.__playerStatBody!==bodyToken) return false;
        ready=true; return true;
    }
    public function invalidate(mask:Number,reason:String,contextToken:Object):Object {
        if(contextToken!==context) return result("failed","stale_context");
        if(!isFinite(mask) || mask!=Math.floor(mask) || mask<0 || mask>7) return result("failed","invalid_mask");
        var reasons:Object={skills:true,gym:true,meridian:true,config:true,equipment:true,pickup:true,
            legacy_equipment:true,companion:true,context:true,growth:true,morph:true,recovery:true};
        if(reasons[reason]!==true) return result("failed","invalid_reason");
        if(mask==0) return result("unchanged","");
        revision++;
        for(var i:Number=0;i<3;i++) if((mask & (1<<i))!=0) requested[i]=revision;
        return result("pending","dirty");
    }
    public function beginBatch(contextToken:Object):Object {
        if(contextToken!==context) return null;
        batchDepth++; return {context:context,open:true};
    }
    public function endBatch(batch:Object,barrier:String):Object {
        if(batch==null || batch.context!==context || batch.open!==true) return result("failed","batch_mismatch");
        batch.open=false;batchDepth--;
        return flush(barrier);
    }
    private function dirtyMask():Number {
        var mask:Number=0;
        for(var i:Number=0;i<3;i++) if(requested[i]>completed[i]) mask|=1<<i;
        return mask;
    }
    private function capture():Object {
        return {context:context,actor:actor,world:world,body:body,revision:revision,
            requested:requested.concat(),mask:dirtyMask()};
    }
    private function current(s:Object,requireReady:Boolean):Boolean {
        if(s==null || s.context!==context || s.actor!==actor || s.world!==world || s.body!==body
                || actor==null || actor.__playerStatBody!==s.body || (requireReady && !ready)) return false;
        return typeof adapter.isCurrent!="function" || adapter.isCurrent(s)===true;
    }
    private function accept(s:Object):Void {
        for(var i:Number=0;i<3;i++) if((s.mask & (1<<i))!=0 && s.requested[i]>completed[i]) completed[i]=s.requested[i];
        projectedRevision=s.revision; appliedBody=s.body; lastFailure=null;
    }
    private function result(status:String,reason:String):Object {
        return {status:status,reason:reason,statRevision:revision,projectedRevision:projectedRevision,
            dirtyMask:dirtyMask(),stage:lastFailure==null ? "" : lastFailure.stage};
    }
    private function fail(s:Object,stage:String,error:Object):Object {
        if(s.context!==context) return result("failed","stale_context");
        var failureReason:String=String(error.message==undefined ? error : error.message);
        var changed:Boolean=lastFailure==null || lastFailure.stage!==stage || lastFailure.reason!==failureReason;
        lastFailure={stage:stage,reason:failureReason};
        if(changed && typeof _root.服务器.发布服务器消息=="function") {
            try {_root.服务器.发布服务器消息("[PlayerStatProjection] failed stage="+stage+" reason="+failureReason
                +" hp="+s.actor.hp+" hpMax="+s.actor.hp满血值+" mp="+s.actor.mp+" mpMax="+s.actor.mp满血值);}
            catch(diagnosticError) {}
        }
        if(current(s,false) && typeof adapter.block=="function") adapter.block(s,stage,lastFailure.reason);
        else if(s.actor===actor && s.world===world && s.body===body && typeof adapter.blockIdentityFault=="function") adapter.blockIdentityFault();
        // 仅出生场景接管失败；已进入游戏后的换装/成长仍由原事务恢复。
        var failedPlan:Object=s.actor.__playerStatInitPlan;
        if(spawnFailedHook!=undefined && failedPlan!=undefined && failedPlan.ticket==null
                && (failedPlan.complete!==true || failedPlan.initialReadyPending===true) && current(s,false))
            spawnFailedHook(s.actor,s.body,failureReason);
        return result("failed",failureReason);
    }
    public function prepareEquipmentTransition(proof:Object,owner:Object):Object {
        if(actor==null || body==null || world==null || owner==null || transition!=null) return null;
        var s:Object=capture();
        if(!current(s,false)) return null;
        var ticket:Object={context:context,actor:actor,world:world,fromBody:body,targetBody:{},proof:proof,
            owner:owner,status:"planned",stage:"planned"};
        transition=ticket; return ticket;
    }
    public function startEquipmentTransition(ticket:Object,value:Object):Object {
        if(ticket!==transition || ticket.context!==context || ticket.status!="planned"
                || actor!==value || ticket.actor!==actor || ticket.world!==world
                || ticket.fromBody!==body || actor.__playerStatBody!==body) return null;
        ticket.status="started";ticket.stage="initializing";body=ticket.targetBody;
        value.__playerStatBody=body;ready=false;appliedBody=null;checkpoint=null;
        return body;
    }
    private function completeEquipmentTransition(ticket:Object,value:Object,worldToken:Object,bodyToken:Object,contextToken:Object):Boolean {
        if(ticket!==transition || ticket.status!="started" || ticket.context!==contextToken || context!==contextToken
                || actor!==value || ticket.actor!==value || world!==worldToken || ticket.world!==worldToken
                || bodyToken!==ticket.targetBody || body!==bodyToken || value.__playerStatBody!==bodyToken) return false;
        if(typeof adapter.verifyEquipment!="function" || adapter.verifyEquipment(ticket)!==true) return false;
        ready=true;ticket.status="completed";ticket.stage="completed";return true;
    }
    /** 只能由持有 ticket 的原领域 owner 显式中止；普通 flush 不会再 full init。 */
    public function abortEquipmentTransition(ticket:Object,owner:Object):Boolean {
        if(ticket!==transition || ticket.owner!==owner || ticket.context!==context
                || (ticket.status!="started" && ticket.status!="planned")) return false;
        ticket.status="aborted";ticket.stage="owner_aborted";transition=null;ready=false;checkpoint=null;
        if(typeof adapter.abortEquipment=="function") adapter.abortEquipment(ticket);
        return true;
    }
    /** 原完整 owner 的已知资源窗口；这不是普通 STATS 检查点，也不容许覆盖现场新损伤。 */
    public function fullRecoveryResources(ticket:Object,owner:Object):Object {
        if(ticket!==transition || ticket.owner!==owner || ticket.context!==context
                || (ticket.status!="started" && ticket.status!="planned") || !current(capture(),false)
                || typeof adapter.verifyEquipmentInput!="function" || adapter.verifyEquipmentInput(ticket)!==true) return null;
        var plan:Object=ticket.actor.__playerStatInitPlan;
        if(plan.ticket!==ticket || plan.context!==context || plan.world!==world) return null;
        return knownFullResources(plan);
    }
    private static function knownFullResources(plan:Object):Object {
        var r:Object=plan.ownerResources;var target:Object=plan.actor;
        if(r==null || !isFinite(r.hp) || !(r.oldMax>0) || !isFinite(r.oldMax) || !isFinite(r.mp)) return null;
        var hp:Number=Number(target.hp);var mp:Number=Number(target.mp);
        var hpKnown:Boolean=r.hpDone || r.stage=="settled" ? hp===r.settledHp
            : hp===r.hp || (r.hpAttempted===true && hp===r.settledHp);
        var mpKnown:Boolean=r.mpDone || r.stage=="settled" ? mp===r.settledMp
            : mp===r.mp || (r.mpAttempted===true && mp===r.settledMp);
        if(!hpKnown || !mpKnown) return null;
        // 成长一次性 setter 已消费的值归该意图所有；重建不得退回回满前的资源。
        return {hp:r.mode=="growth_one_shot" ? hp : r.hp,oldMax:r.oldMax,
            mp:r.mode=="growth_one_shot" ? mp : r.mp,stage:"captured"};
    }
    public function equipmentTransition():Object { return transition; }
    public function diagnostics():Object { return result(lastFailure==null ? "pending" : "failed",lastFailure==null ? "" : lastFailure.reason); }

    /** 初生尾部完成后，合批/权威等待可由原 owner 稍后收口；不重做初始化或资源写入。 */
    private static function publishInitialReady(target:Object):Void {
        var plan:Object=target.__playerStatInitPlan;
        if(plan.initialReadyPending!==true || plan.complete!==true || plan.failed===true
                || !planCurrent(plan) || target.__playerStatFullReady!==plan.body
                || target.__playerStatInitializing===true) return;
        plan.initialReadyPending=false;
        if(spawnReadyHook!=undefined) spawnReadyHook(target);
    }
    public function flush(barrier:String):Object {
        var flushed:Object=flushProjection(barrier);
        if(flushed.status=="applied" || flushed.status=="unchanged") {
            var readySnapshot:Object=capture();
            try {PlayerStatRefreshCoordinator.publishInitialReady(actor);}
            catch(error) {return fail(readySnapshot,"initial_ready",error);}
        }
        return flushed;
    }
    private function flushProjection(barrier:String):Object {
        if(batchDepth>0) return result("pending","batch_open");
        if(flushing) return result("pending","reentrant");
        if(actor==null || body==null || world==null) return result("pending","pending_actor");
        if((dirtyMask() & 4)!=0 && transition!=null && transition.status=="started")
            return fail(capture(),"equipment_owner_recovery",new Error("equipment_owner_recovery_required"));
        if(!current(capture(),false)) return fail(capture(),"identity",new Error("identity_changed"));
        var canConsume:Boolean=true;
        try {if(typeof adapter.canConsume=="function") canConsume=adapter.canConsume()===true;}
        catch(visibilityError) {return fail(capture(),"visibility",visibilityError);}
        if(!canConsume) {
            var readReason:String=growthReadReason();if(readReason=="") readReason="authority_pending";
            if(typeof adapter.block=="function") adapter.block(capture(),"visibility",readReason);
            return result("pending",readReason);
        }
        if(typeof adapter.canProject=="function" && adapter.canProject(capture())!==true) return result("pending","pending_actor_shape");
        if((dirtyMask() & 4)==0 && !ready) {
            var pendingPlan:Object=actor.__playerStatInitPlan;
            if(pendingPlan.failed===true && pendingPlan.ticket==null && pendingPlan.tailCheckpoint!=undefined
                    && pendingPlan.open==0 && pendingPlan.finalScope!=null) return PlayerStatRefreshCoordinator.resumeOuterInitialization(pendingPlan.finalScope);
        }
        if((dirtyMask() & 4)==0 && !ready) return result("pending","pending_ready");
        flushing=true;
        try {
            if(dirtyMask()==0 && checkpoint==null && appliedBody===body && lastFailure==null) {
                var cleanSnapshot:Object=capture();
                try {
                    // 权威等待可能仅持有暂停而没有属性 dirty；成功的 clean 返回也须归还本模块责任。
                    if(typeof adapter.unblock=="function") adapter.unblock(cleanSnapshot);
                    if(!current(cleanSnapshot,true)) throw new Error("identity_changed");
                    canConsume=typeof adapter.canConsume!="function" || adapter.canConsume()===true;
                    if(!current(cleanSnapshot,true)) throw new Error("identity_changed");
                    if(!canConsume) {
                        readReason=growthReadReason();if(readReason=="") readReason="authority_pending";
                        if(typeof adapter.block=="function") adapter.block(cleanSnapshot,"visibility",readReason);
                        return result("pending",readReason);
                    }
                    if(batchDepth>0) return result("pending","batch_open");
                    if(typeof adapter.canProject=="function" && adapter.canProject(cleanSnapshot)!==true) return result("pending","pending_actor_shape");
                    if(!current(cleanSnapshot,true)) throw new Error("identity_changed");
                    if(dirtyMask()==0 && checkpoint==null && appliedBody===body && lastFailure==null) return result("unchanged","");
                    // 释放回调新增的 dirty 在当前受保护刷新中继续收敛，不伪造一次 clean 回执。
                } catch(cleanError) {return fail(cleanSnapshot,"clean_unblock",cleanError);}
            }
            for(var pass:Number=0;pass<4;pass++) {
                var s:Object=checkpoint==null ? capture() : checkpoint.snapshot;
                var stage:String="identity";
                try {
                    if((s.mask & 4)!=0) {
                        var ticket:Object=transition;
                        if(ticket==null) return fail(s,"equipment_ticket",new Error("equipment_ticket_required"));
                        if(ticket.status=="started") return fail(capture(),"equipment_owner_recovery",new Error("equipment_owner_recovery_required"));
                        if(ticket.status=="planned") {
                            if(!current(s,false)) throw new Error("identity_changed");
                            stage="equipment_preflight";
                            if(typeof adapter.verifyEquipmentInput!="function" || adapter.verifyEquipmentInput(ticket)!==true) throw new Error("equipment_proof_rejected");
                            stage="equipment_rebuild"; adapter.rebuild(ticket);
                        }
                        if(ticket!==transition || ticket.status!="completed" || ticket.context!==context
                                || ticket.world!==world || ticket.actor!==actor || body!==ticket.targetBody
                                || actor.__playerStatBody!==ticket.targetBody || !ready
                                || adapter.verifyEquipment(ticket)!==true) throw new Error("equipment_final_barrier_missing");
                        s.body=ticket.targetBody;
                        if(!current(s,true)) throw new Error("identity_changed");
                        if(typeof adapter.unblock=="function") adapter.unblock(s);
                        if(!current(s,true)) throw new Error("identity_changed");
                        if(adapter.verifyEquipment(ticket)!==true) throw new Error("equipment_final_barrier_missing");
                        accept(s);
                        if(ticket.coveredSnapshot!=undefined && current(ticket.coveredSnapshot,true)) accept(ticket.coveredSnapshot);
                        transition=null;
                    } else {
                        if(!current(s,true)) throw new Error("identity_changed");
                        if(checkpoint==null) {
                            stage="compute"; var record:Object=adapter.compute(s,s.mask);
                            if(!current(s,true)) throw new Error("identity_changed");
                            stage="capture"; var resources:Object=adapter.captureResources(s,record);
                            if(!current(s,true)) throw new Error("identity_changed");
                            checkpoint={snapshot:s,record:record,resources:resources,stage:"captured"};
                        }
                        var cp:Object=checkpoint;
                        if(cp.stage=="captured") {
                            stage="commit";adapter.commit(s,cp.record,cp.resources);
                            if(!current(s,true)) throw new Error("identity_changed");
                            cp.stage="committed";
                        }
                        if(cp.stage=="committed") {
                            stage="resources";adapter.settleResources(s,cp.record,cp.resources);
                            if(!current(s,true)) throw new Error("identity_changed");
                            cp.stage="settled";
                        }
                        stage="derived";adapter.derive(s,cp.record);
                        if(!current(s,true)) throw new Error("identity_changed");
                        stage="postcondition";
                        if(adapter.verify(s,cp.record)!==true) throw new Error("stat_postcondition_failed");
                        if(!current(s,true)) throw new Error("identity_changed");
                        if(typeof adapter.unblock=="function") adapter.unblock(s);
                        if(!current(s,true)) throw new Error("identity_changed");
                        if(adapter.verify(s,cp.record)!==true) throw new Error("stat_postcondition_failed");
                        accept(s);checkpoint=null;
                    }
                    if(dirtyMask()==0) return result("applied","");
                } catch(error) { return fail(s,stage,error); }
            }
            return result("pending","convergence_limit");
        } finally { flushing=false; }
        return result("failed","unreachable");
    }
}
