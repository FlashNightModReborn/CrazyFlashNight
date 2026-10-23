import org.flashNight.arki.scene.PlayerResourceTransfer;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.SceneTransitionGuard;
import org.flashNight.arki.unit.PlayerStatRefreshCoordinator;
import org.flashNight.arki.unit.Action.Regeneration.ResourceNumber;

/** 冷路径接线：清场最终采样、完整模板尾部消费、同一 ready 屏障放行场景消费者。 */
class org.flashNight.arki.scene.PlayerResourceTransferBridge {
    private static var transfer:PlayerResourceTransfer;
    private static var mercs:Array;
    private static var mercWorld:Object;
    private static var installed:Boolean;
    private static var generation:Object={};
    private static var activeIntent:Object;
    private static var revival:Object;
    private static var captureFailure:String;
    private static var captureDetail:String;
    public static function cleanupFailureReason():String {return captureFailure;}
    public static function cleanupFailureDetail():String {return captureDetail;}
    private static function intentMismatch(i:Object,current:Object,ticket:Object,stage:Number):String {
        if(i==null) return "missing";
        if(i.generation!==generation) return "generation";
        if(i.frame!==ticket.frame) return "frame";
        if(i.context!==current.context) return "context";
        if(i.run!==current.run) return "run";
        if(i.world!==current.world) return "world";
        if(i.actor!==current.actor) return "actor";
        if(i.slot!==current.slot) return "slot";
        if(i.name!==current.name) return "name";
        if(i.kind!==current.kind) return "kind";
        if(i.stage!==stage) return "source_stage";
        if(i.targetStage!==stage+1) return "target_stage";
        return "";
    }
    private static function core():PlayerResourceTransfer {
        if(transfer==undefined) transfer=new PlayerResourceTransfer();
        return transfer;
    }
    public static function install():Void {
        if(installed) return;
        installed=true;
        PlayerStatRefreshCoordinator.setSpawnResourceHooks(checkSeed,finishResources,actorReady,retire);
    }
    /** 死亡仅保留本世界已完成初始化的 owner；旧意图、快照和回调身份仍全部退休。 */
    private static function rememberRevival():Object {
        var world:Object=_root.gameworld;var gate:Object=world.__resourceReadyGate;
        if(isReady(gate) && gate.manager!=null && gate.setup===true && gate.published===true) {
            var actor:Object=world[_root.控制目标];var spawn:Object=actor.__resourceSpawn;
            return {gate:gate,spawn:spawn,actor:spawn.identity,body:actor.__playerStatBody,
                context:gate.context,run:gate.run,world:gate.world,slot:gate.slot,name:spawn.name,
                kind:spawn.kind,stage:gate.stage,manager:gate.manager,started:gate.started,
                publishScene:gate.publishScene,arrivalToken:gate.arrivalToken};
        }
        // 扣币/respawn 失败仍处于同一次死亡，不能丢掉原 owner，也不能从旧剪辑重建 owner。
        return revival!=null && revival.generation===generation ? revival : null;
    }
    public static function retire(reason:String):Void {
        var owner:Object=reason=="hero_dead" ? rememberRevival() : null;
        generation={};activeIntent=null;core().retire(reason);mercs=null;mercWorld=null;
        revival=owner;if(owner!=null) owner.generation=generation;
    }
    /** 仅由 life authority 确认同一主角已复活后调用；不改 HP/MP、不重发场景启动。 */
    public static function onHeroRespawn(target:MovieClip):Boolean {
        var owner:Object=revival;var world:Object=_root.gameworld;
        var run:Object=StageRunSession.getRunAuthority();
        if(owner==null || owner.generation!==generation || run!==owner.run || !liveRun(run) || run.life!=="alive"
                || _root.当前为战斗地图!==true || context()!==owner.context || String(_root.savePath)!==owner.slot
                || String(_root.控制目标)!==owner.name || StageReturnFlow.worldIdentity(world)!==owner.world
                || world.__resourceReadyGate!==owner.gate || world[owner.name]!==target
                || target.__resourceSpawn!==owner.spawn || target.__resourceActorIdentity!==owner.actor
                || target.__playerStatBody!==owner.body || target.__playerStatProjectionBlocked===true
                || (owner.kind=="player" && (target.__playerStatInitializing===true || target.__playerStatFullReady!==owner.body))) return false;
        var manager:Object=owner.manager;
        if(manager==null || manager.gameworld!==world || manager.currentStage!==owner.stage
                || manager.isActive!==true || manager.isFinished===true || manager.isFailed===true
                || kindOf(String(target.兵种),target)!==owner.kind
                || !ResourceNumber.positive(target.hp) || !ResourceNumber.positive(target.hp满血值)
                || !ResourceNumber.nonnegative(target.mp)
                || !(ResourceNumber.positive(target.mp满血值) || (owner.kind=="lee" && target.mp满血值===0 && target.mp===0))) return false;
        var gate:Object={generation:generation,world:owner.world,context:owner.context,run:run,stage:owner.stage,manager:manager,
            setup:true,actorReady:true,published:true,started:owner.started,publishScene:owner.publishScene,
            arrivalToken:owner.arrivalToken,slot:owner.slot};
        var spawn:Object={identity:{},gate:gate,name:owner.name,kind:owner.kind,resourcesReady:true,
            hero:true,handle:null,merc:null,readyNotified:true,finalHp:target.hp,finalMp:target.mp};
        gate.hero=spawn;world.__resourceReadyGate=gate;
        target.__resourceSpawn=spawn;target.__resourceActorIdentity=spawn.identity;
        revival=null;return isReady(gate);
    }
    private static function context():Object {return PlayerStatRefreshCoordinator.production().contextToken();}
    private static function kindOf(identifier:String,params:Object):String {
        if(identifier=="主角-男" || identifier=="主角-女") return "player";
        if(identifier=="敌人-李小龙" && params.__enemyActionPlayer===true) return "lee";
        return "unsupported";
    }
    private static function identity(world:Object,target:Object,kind:String,stage:Number):Object {
        return {context:context(),run:StageRunSession.getRunAuthority(),world:StageReturnFlow.worldIdentity(world),
            actor:target.__resourceActorIdentity,slot:String(_root.savePath),name:String(_root.控制目标),kind:kind,stage:stage};
    }
    private static function liveRun(run:Object):Boolean {return run!=null && run.outcome=="active" && run.life!="dead";}
    /** 请求只冻结身份和目的地；资源要等 loot/preflight 完成后才读。 */
    private static function makeIntent(frame:String):Object {
        var world:Object=_root.gameworld;var gate:Object=world.__resourceReadyGate;
        if(frame!=="wuxianguotu_1" || _root.当前为战斗地图!==true || !isReady(gate)) return null;
        var actor:Object=world[_root.控制目标];var spawn:Object=actor.__resourceSpawn;
        var intent:Object=identity(world,actor,spawn.kind,gate.stage);
        intent.generation=generation;intent.gate=gate;intent.frame=frame;intent.targetStage=gate.stage+1;
        return intent;
    }
    private static function admitIntent(intent:Object):Boolean {
        if(intent==null) return true;
        if(intent.generation!==generation || !isReady(intent.gate)
                || core().status()=="captured" || core().status()=="committed" || core().status()=="bound") return false;
        activeIntent=intent;return true;
    }
    public static function requestFade(frame:String):Boolean {
        var intent:Object=makeIntent(frame);
        if(typeof _root.淡出动画.淡出跳转帧!="function" || _root.淡出动画.淡出跳转帧(frame)!==true) return false;
        return admitIntent(intent);
    }
    /** prepareDoor 成功之后、播放开门效果之前调用。 */
    public static function recordAdmittedDoor(frame:String):Boolean {return admitIntent(makeIntent(frame));}
    /** 返回 null 表示无此事务；false 表示必须保留旧世界。 */
    public static function captureCleanup(ticket:Object,world:Object,stage:Number):Object {
        install();
        captureFailure="resource_identity_invalid";captureDetail="cleanup_ticket_stale";
        if(ticket==undefined) return null;
        if(!SceneTransitionGuard.isCurrent(ticket)) return false;
        var mode:Object=org.flashNight.arki.scene.StageManager.instance.getWarlordActionEncounterSnapshot();
        if((mode!=undefined && mode.phase!="unavailable") || world.__resourceTransferBypass==="calibration") {
            retire("special_scene_exit");return null;
        }
        var run:Object=StageRunSession.getRunAuthority();
        if(_root.当前为战斗地图!==true || ticket.frame!=="wuxianguotu_1" || !liveRun(run)) {
            retire("scene_contract_exit");return null;
        }
        var actor:Object=world[_root.控制目标];var spawn:Object=actor.__resourceSpawn;
        var kind:String=kindOf(String(actor.兵种),actor);
        if(kind=="unsupported" || spawn==undefined || spawn.resourcesReady!==true || !owns(actor,spawn)
                || spawn.gate.actorReady!==true || actor.__playerStatProjectionBlocked===true
                || (kind=="player" && (actor.__playerStatInitializing===true || actor.__playerStatFullReady!==actor.__playerStatBody))) {
            captureDetail="capture_actor_not_ready";
            ResourceNumber.reject(actor,captureDetail);return false;
        }
        var current:Object=identity(world,actor,kind,stage);var i:Object=activeIntent;
        var mismatch:String=intentMismatch(i,current,ticket,stage);
        if(mismatch!="") {
            captureDetail="capture_intent_mismatch:"+mismatch;
            ResourceNumber.reject(actor,captureDetail);return false;
        }
        var values:Object={hp:actor.hp,mp:actor.mp,hpMax:actor.hp满血值,mpMax:actor.mp满血值};
        if(!core().capture(ticket,i,values,i.targetStage)) {
            captureDetail=core().reason;
            if(captureDetail=="capture_resources_invalid") captureFailure="resource_invalid";
            ResourceNumber.reject(actor,captureDetail);return false;
        }
        captureFailure="";captureDetail="";
        i.ticket=ticket;
        // 佣兵只承接本次最终快照中的 HP；不复用旧全局数组，不继承 MP。
        mercs=[];mercWorld=null;
        for(var index:Number=0;index<_root.佣兵个数限制;index++) {
            var merc:Object=world["同伴"+index];
            if(merc!=undefined && ResourceNumber.positive(merc.hp) && ResourceNumber.positive(merc.hp满血值))
                mercs[index]={hp:merc.hp,max:merc.hp满血值,user:merc.用户ID,name:merc.名字,used:false};
        }
        return ticket;
    }
    public static function commitCleanup(ticket:Object):Void {
        if(ticket!=null && !core().commit(ticket)) {
            abortCleanup(ticket);trace("[ResourceTransfer] cleanup_commit_rejected");
        }
    }
    public static function abortCleanup(ticket:Object):Void {
        if(core().abort(ticket,"cleanup_failed")) {activeIntent=null;mercs=null;mercWorld=null;}
    }
    public static function beginStage(world:Object,stage:Number,manager:Object):Object {
        install();
        var c:Object=context();var run:Object=StageRunSession.getRunAuthority();
        if(_root.新出生===true || core().sourceRun()!==run || core().sourceContext()!==c) retire("new_run_or_context");
        var gate:Object={generation:generation,world:StageReturnFlow.worldIdentity(world),context:c,run:run,stage:stage,manager:manager,
            setup:false,actorReady:false,published:false,publishScene:true,arrivalToken:world.__stageReturnToken,slot:String(_root.savePath)};
        world.__resourceReadyGate=gate;return gate;
    }
    public static function prepareScene(world:Object,publishScene:Boolean):Void {
        install();
        var mode:Object=org.flashNight.arki.scene.StageManager.instance.getWarlordActionEncounterSnapshot();
        if(mode!=undefined && mode.phase!="unavailable") {
            retire("warlord_bypass");
            world.__resourceSceneBypass={world:StageReturnFlow.worldIdentity(world),publishScene:publishScene};
            return;
        }
        if(world.__resourceReadyGate==undefined) {
            var currentContext:Object=context();
            retire("non_stage_spawn");
            var gate:Object={generation:generation,world:StageReturnFlow.worldIdentity(world),context:currentContext,run:StageRunSession.getRunAuthority(),
                stage:-1,manager:null,setup:false,actorReady:false,published:false,publishScene:publishScene,arrivalToken:world.__stageReturnToken,slot:String(_root.savePath)};
            world.__resourceReadyGate=gate;
        }
    }
    public static function finishSceneSetup(world:MovieClip):Void {
        var bypass:Object=world.__resourceSceneBypass;
        if(bypass!=undefined && bypass.world===StageReturnFlow.worldIdentity(_root.gameworld)) {
            delete world.__resourceSceneBypass;
            org.flashNight.arki.camera.HorizontalScroller.onPlayerBound(world,bypass.world,world[_root.控制目标]);
            if(bypass.publishScene) org.flashNight.neur.Event.EventBus.instance.publish("SceneReady",world,world.__stageReturnToken,bypass.world);
            return;
        }
        var gate:Object=world.__resourceReadyGate;
        if(gate.manager!=null) return;
        gate.setup=true;publishReady(gate);
    }
    public static function finishStageSetup(gate:Object):Void {gate.setup=true;publishReady(gate);}
    /** 在 attachMovie 的 initObject 中分配身份，不能在 attach 返回栈补发。 */
    public static function prepareSpawn(identifier:String,name:String,params:Object):Void {
        install();
        if(name!==_root.控制目标 && params.是否为佣兵!==true) return;
        var world:Object=_root.gameworld;var gate:Object=world.__resourceReadyGate;
        if(gate==undefined) return;
        var spawn:Object={identity:{},gate:gate,name:name,kind:kindOf(identifier,params),resourcesReady:false,
            hero:name===_root.控制目标,handle:null,merc:null};
        params.__resourceSpawn=spawn;params.__resourceActorIdentity=spawn.identity;
        if(spawn.hero) {
            if(gate.hero!=undefined) {gate.failed=true;throw new Error("resource_duplicate_hero_spawn");}
            gate.hero=spawn;
            if(spawn.kind=="unsupported") {gate.failed=true;throw new Error("resource_actor_contract_missing");}
            if(core().status()=="committed") {
                spawn.handle=core().bind({context:gate.context,run:gate.run,world:gate.world,actor:spawn.identity,
                    slot:gate.slot,name:name,kind:spawn.kind,stage:gate.stage});
                if(spawn.handle==null) {gate.failed=true;throw new Error(core().reason);}
                mercWorld=gate.world;
            } else if(core().status()=="captured" || core().status()=="bound" || core().status()=="failed") {
                gate.failed=true;throw new Error("resource_transfer_unavailable");
            }
        } else if(mercWorld===gate.world) {
            var record:Object=mercs[params.佣兵是否出战信息id];
            if(record!=undefined && record.used!==true && record.user===params.用户ID && record.name===params.名字) {
                record.used=true;spawn.merc=record;
            }
        }
    }
    public static function isCurrent(gate:Object):Boolean {
        var world:Object=_root.gameworld;
        if(gate==null || gate.generation!==generation || gate.failed===true || world.__resourceReadyGate!==gate
                || gate.world!==StageReturnFlow.worldIdentity(world) || gate.context!==context()
                || gate.slot!==String(_root.savePath)) return false;
        return gate.manager==null || (gate.run===StageRunSession.getRunAuthority() && liveRun(gate.run)
            && gate.manager.isActive===true && gate.manager.isFinished!==true && gate.manager.isFailed!==true
            && gate.manager.currentStage===gate.stage && gate.manager.gameworld===world);
    }
    private static function owns(target:Object,spawn:Object):Boolean {
        return spawn!=null && target.__resourceSpawn===spawn && target.__resourceActorIdentity===spawn.identity
            && isCurrent(spawn.gate) && _root.gameworld[spawn.name]===target
            && (!spawn.hero || spawn.gate.hero===spawn);
    }
    public static function isReady(gate:Object):Boolean {
        return isCurrent(gate) && gate.actorReady===true && gate.hero.resourcesReady===true
            && owns(_root.gameworld[_root.控制目标],gate.hero);
    }
    public static function checkSeed(target:Object):Void {
        var spawn:Object=target.__resourceSpawn;if(spawn==undefined || spawn.resourcesReady===true) return;
        if(!owns(target,spawn)) throw new Error("resource_seed_identity_invalid");
        if((typeof target.hp!="undefined" && !ResourceNumber.nonnegative(target.hp))
                || (spawn.hero && typeof target.mp!="undefined" && !ResourceNumber.nonnegative(target.mp))) {
            spawn.gate.failed=true;ResourceNumber.reject(target,"spawn_seed_invalid");throw new Error("spawn_seed_invalid");
        }
    }
    public static function finishResources(target:Object,window:Object):Void {
        var spawn:Object=target.__resourceSpawn;
        if(spawn==undefined || spawn.resourcesReady===true) return;
        if(!owns(target,spawn)) throw new Error("resource_tail_identity_invalid");
        if(!ResourceNumber.positive(target.hp) || !ResourceNumber.positive(target.hp满血值)
                || (spawn.hero && (!ResourceNumber.nonnegative(target.mp)
                    || !(ResourceNumber.positive(target.mp满血值) || (spawn.kind=="lee" && target.mp满血值===0 && target.mp===0))))) {
            spawn.gate.failed=true;ResourceNumber.reject(target,"spawn_tail_invalid");throw new Error("spawn_tail_invalid");
        }
        if(spawn.handle!=null) {
            var i:Object=identity(_root.gameworld,target,spawn.kind,spawn.gate.stage);
            // 显式 cap 由对应模式提供；普通角色没有通用溢出倍率。
            if(!core().consume(spawn.handle,target,i,target.__resourceTransferCaps)) {
                spawn.gate.failed=true;ResourceNumber.reject(target,core().reason);throw new Error(core().reason);
            }
            if(core().diagnostic!="") trace("[ResourceTransfer] "+core().diagnostic);
        } else if(spawn.merc!=null) {
            target.hp=PlayerResourceTransfer.project(spawn.merc.hp,spawn.merc.max,target.hp满血值,undefined);
        }
        if(window!=null) {window.hpDone=true;window.mpDone=true;window.settledHp=target.hp;window.settledMp=target.mp;}
        spawn.resourcesReady=true;spawn.finalHp=target.hp;spawn.finalMp=target.mp;
    }
    public static function actorReady(target:Object):Void {
        var spawn:Object=target.__resourceSpawn;
        if(!owns(target,spawn) || !spawn.hero || spawn.resourcesReady!==true || spawn.readyNotified===true) return;
        if(target.hp!==spawn.finalHp || target.mp!==spawn.finalMp) {
            spawn.gate.failed=true;ResourceNumber.reject(target,"resource_changed_before_ready");return;
        }
        spawn.readyNotified=true;spawn.gate.actorReady=true;publishReady(spawn.gate);
    }
    private static function publishReady(gate:Object):Void {
        if(!isReady(gate) || !gate.setup || gate.published) return;
        var world:MovieClip=_root.gameworld;var actor:MovieClip=world[_root.控制目标];
        if(!owns(actor,gate.hero) || gate.hero.resourcesReady!==true) return;
        gate.published=true;
        org.flashNight.arki.camera.HorizontalScroller.onPlayerBound(world,gate.world,actor);
        if(!isReady(gate)) return;
        if(gate.publishScene) org.flashNight.neur.Event.EventBus.instance.publish("SceneReady",world,gate.arrivalToken,gate.world);
        if(isReady(gate) && gate.manager!=null) gate.manager.onResourcesReady(gate);
    }
    public static function scheduleMercs(x:Number,y:Number):Void {
        var world:Object=_root.gameworld;
        _root.帧计时器.添加单次任务(mercCallback(world.__resourceReadyGate,StageReturnFlow.worldIdentity(world),x,y),33);
    }
    private static function mercCallback(gate:Object,worldIdentity:Object,x:Number,y:Number):Function {
        return function():Void {
            if(worldIdentity!==StageReturnFlow.worldIdentity(_root.gameworld) || (gate!=undefined && !PlayerResourceTransferBridge.isCurrent(gate))) return;
            for(var i:Number=0;i<_root.佣兵个数限制;i++) {
                if(worldIdentity!==StageReturnFlow.worldIdentity(_root.gameworld)) return;
                _root.加载单个佣兵(i,x,y);
            }
        };
    }
    public static function finishEnemyState(target:Object,label:String):Void {
        var spawn:Object=target.__resourceSpawn;
        var routing:Object=org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntent;
        routing.createStateTransitionJob(target,label,enemyCompletion(spawn));
        target.gotoAndStop(label);routing.executeStateTransitionJob(target);
    }
    private static function enemyCompletion(spawn:Object):Function {
        return function(target:Object):Void {
            if(!PlayerResourceTransferBridge.owns(target,spawn)) return;
            PlayerResourceTransferBridge.finishResources(target,null);
            PlayerResourceTransferBridge.actorReady(target);
        };
    }
}
