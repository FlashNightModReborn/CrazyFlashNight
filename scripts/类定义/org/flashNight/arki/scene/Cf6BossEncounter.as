import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.StageEvent;
import org.flashNight.arki.scene.WaveSpawner;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/** CF6 四场 Boss 的有限增援；Boss 死亡优先，旁支不进入必须清场人数。 */
class org.flashNight.arki.scene.Cf6BossEncounter {
    private static var active:Cf6BossEncounter;
    private static var serial:Number = 0;
    private static var installed:Boolean = false;
    private var world:MovieClip;
    private var owner:Object;
    private var run:Object;
    private var slot:String;
    private var manager:Object;
    private var stage:Number;
    private var spawner:Object;
    private var plan:Object;
    private var token:String;
    private var clock:MovieClip;
    private var living:Object;
    private var issued:Object;
    private var queue:Array;
    private var groupIndex:Number;
    private var waitFrames:Number;
    private var nextName:Number;
    private var stopped:Boolean;
    private var bossMark:Object;
    private var elderStarted:Boolean;
    private var elderWaiting:Boolean;
    private var elderPhase:Object;
    private var elderParentMark:Object;
    private var elderWaitFrames:Number;
    private var elderError:String;
    private var finalDying:Boolean;
    private var finalDeathReady:Object;
    private var finalDeathRemoved:Boolean;
    private var finalDeathOriginal:Function;
    private var finalDeathWrapper:Function;
    public static function install():Void {
        if (installed) return;
        installed = true;
        org.flashNight.arki.interaction.NativeInteractionContext.onSceneTeardown(cancel);
    }
    public static function cancel():Void { if (active != null) active.finish(false); }
    /** First-form death is not a completed room, including late wave clear callbacks. */
    public static function blocksClear(w:MovieClip, m:Object):Boolean {
        return active != null && active.current() && active.world === w && active.manager === m
            && (active.plan.nextPhase != null || active.elderStarted === true);
    }
    public static function start(w:MovieClip, identity:Object, p:Object):Void {
        install();
        if (w == undefined || w !== _root.gameworld || identity == null
                || identity !== StageReturnFlow.worldIdentity(w) || p == null
                || _root._saveExt.bookRun.bookId !== "cf6-sting"
                || _root._saveExt.bookRun.routeId !== "historical"
                || _root._saveExt.bookRun.slot !== String(_root.savePath)
                || _root._saveExt.bookRun.outcome !== "active"
                || _root.当前关卡名 !== "书中历险-毒刺行动") return;
        if (active != null && active.scope() && active.stage === StageManager.instance.currentStage) return;
        cancel();
        active = new Cf6BossEncounter(w, identity, p);
    }
    private function Cf6BossEncounter(w:MovieClip, identity:Object, p:Object) {
        world=w; owner=identity; run=org.flashNight.gesh.object.PersistedSnapshot.clone(_root._saveExt.bookRun); slot=String(_root.savePath);
        manager=StageManager.instance; stage=manager.currentStage; spawner=WaveSpawner.instance; plan=p;
        token="cf6BossSupport"+(++serial); living={}; issued={}; queue=[];
        groupIndex=0; waitFrames=0; nextName=0; stopped=false;
        elderStarted=false;elderWaiting=false;elderWaitFrames=0;finalDying=false;finalDeathRemoved=false;
        clock=w.createEmptyMovieClip("__cf6BossEncounter",w.getNextHighestDepth());
        clock.cf6BossOwnerToken=token;
        var self:Cf6BossEncounter=this;
        clock.onEnterFrame=function():Void { self.tick(); };
        w.dispatcher.subscribe("UnitSpawn",onSpawn,this);
        w.dispatcher.subscribe("UnitDeath",onDeath,this);
        w.dispatcher.subscribe("UnitRemoved",onRemoved,this);
        bindBoss();
    }
    private function worldOwned():Boolean {
        return world === _root.gameworld && owner === StageReturnFlow.worldIdentity(_root.gameworld);
    }
    private function scope():Boolean {
        return worldOwned() && slot === String(_root.savePath) && run.slot === slot
            && org.flashNight.arki.scene.BookRunRules.sameCf6Run(run,_root._saveExt.bookRun)
            && _root.当前关卡名 === "书中历险-毒刺行动"
            && manager === StageManager.instance && stage === manager.currentStage;
    }
    private function current():Boolean {
        return !stopped && scope() && manager.isActive === true
            && spawner === WaveSpawner.instance
            && manager.isFinished !== true && manager.isFailed !== true && manager.isCleared !== true;
    }
    private static function finite(value):Boolean { return typeof value === "number" && !isNaN(value) && isFinite(value); }
    private function bindBoss():Void {
        var boss:MovieClip=world[plan.instanceName];
        if (bossMark == null && finite(boss.hp) && boss.hp > 0 && finite(boss.hp满血值) && boss.hp满血值 > 0) {
            bossMark={}; boss.cf6BossIdentity=bossMark;
        }
    }
    private function bossDead():Boolean {
        var boss:MovieClip=world[plan.instanceName];
        return bossMark != null && boss.cf6BossIdentity === bossMark && finite(boss.hp) && boss.hp <= 0;
    }
    private function tick():Void {
        if (!current()) { finish(false); return; }
        if(elderError!=undefined) return;
        for (var name:String in living) refreshGuard(living[name]);
        bindBoss();
        if (finalDeathRemoved) {finish(true);return;}
        if (elderWaiting) { advanceElder(); return; }
        if (bossDead()) {
            if (plan.nextPhase != null) { beginElder(); advanceElder(); return; }
            if (elderStarted) { beginFinalDeath(); return; }
            finish(true); return;
        }
        if (_root.暂停 === true || _root.场景转换中 === true) return;
        var hero:MovieClip=TargetCacheManager.findHero();
        var boss:MovieClip=world[plan.instanceName];
        if (!finite(hero.hp) || hero.hp <= 0 || bossMark == null || boss.cf6BossIdentity !== bossMark
                || !finite(boss.hp) || !finite(boss.hp满血值) || boss.hp满血值 <= 0) return;
        while (groupIndex < plan.groups.length && boss.hp / boss.hp满血值 <= plan.groups[groupIndex].hpRatio) {
            var entries:Array=plan.groups[groupIndex++].enemies;
            for (var i:Number=0;i<entries.length;i++) for (var q:Number=0;q<entries[i].Quantity;q++) queue.push(entries[i]);
        }
        if (waitFrames > 0) { waitFrames--; return; }
        var count:Number=0, ranged:Number=0;
        for (name in living) { count++; if (living[name].ranged) ranged++; }
        if (count >= plan.maxAlive || queue.length == 0) return;
        var index:Number=-1;
        for (i=0;i<queue.length;i++) {
            if(queue[i].ranged && !(ranged < plan.maxRanged)) continue;
            if(queue[i].podId!=undefined && !org.flashNight.arki.scene.Cf6InteractivePropService.podReady(world,queue[i].podId)) continue;
            index=i;break;
        }
        if (index < 0) return;
        var source:Object=queue.splice(index,1)[0], enemy:Object={}, parameters:Object={};
        for (var key:String in source) enemy[key]=source[key];
        for (key in source.Parameters) parameters[key]=source.Parameters[key];
        name=token+"_"+(nextName++);
        parameters.cf6BossOwnerToken=token; parameters.publishStageEvent=true; parameters.产生源="无";
        if(source.podId!=undefined) parameters.cf6PodId=source.podId;
        enemy.Parameters=parameters; enemy.InstanceName=name; enemy.Quantity=1;
        var record:Object={name:name,ranged:source.ranged,kind:source.Type};
        living[name]=record; issued[name]=record; waitFrames=plan.intervalFrames;
        // Claim after reserving the original slot; unknown delivery retains that slot and is never replayed.
        if(source.podId!=undefined && !org.flashNight.arki.scene.Cf6InteractivePropService.claimPod(world,source.podId,token,name)) {
            finish(false);return;
        }
        var event:StageEvent=new StageEvent({EventName:"Cf6FiniteSupport",Enemy:[enemy]});
        event.execute();
        // 同步 attach 返回后补绑；若资源延迟，UnitSpawn 仍保留预占人数。
        bind(record);
    }
    private function beginElder():Void {
        if (elderStarted || !bossDead() || plan.nextPhase == null) return;
        elderStarted=true;elderWaiting=true;elderParentMark=bossMark;
        queue=[];waitFrames=0;
        // Each form owns its finite budget. Pending first-form deliveries remain tombstoned.
        for (var name:String in living) {
            living[name].retired=true;
            retireRecord(living[name]);
        }
        living={};
        trace("[CF6_FINALE_PHASE] human-defeated; waiting for native elder successor");
    }
    private function failElder(reason:String):Void {
        if (elderError != undefined) return;
        elderError=reason;
        trace("[CF6_FINALE_PHASE_ERROR] "+reason);
        if (typeof _root.发布消息=="function") _root.发布消息("元老变形接续未完成，请保留现场并退出本次历险。");
    }
    private function advanceElder():Void {
        if (!elderWaiting || elderError != undefined || !current()
                || _root.暂停 === true || _root.场景转换中 === true) return;
        elderWaitFrames++;
        var parent:MovieClip=world[plan.instanceName];
        if (elderPhase == null && parent.cf6BossIdentity === elderParentMark) {
            var observed:Object=parent.elderTransform;
            if (observed != null && parent.老头变身 === true
                    && observed.parentIdentity === parent.elderIdentity) elderPhase=observed;
        }
        var phase:Object=elderPhase;
        if (phase == null) {
            if (elderWaitFrames >= 600) failElder("native-transform-not-started");
            return;
        }
        if (phase.world !== world || phase.worldIdentity !== world.__elderWorldIdentity
                || phase.name !== plan.instanceName+"__elderbot"
                || phase.name !== plan.nextPhase.instanceName || phase.spawnIdentity == null) {
            failElder("native-transform-identity-mismatch");return;
        }
        if (phase.error != undefined) {failElder("native-transform-"+phase.error);return;}
        var child:MovieClip=phase.child;
        if (phase.attempted === true && (child._parent !== world || child._name !== phase.name
                || world[phase.name] !== child || child.elderSpawnIdentity !== phase.spawnIdentity)) {
            failElder("native-successor-identity-mismatch");return;
        }
        if (phase.retired !== true || phase.attempted !== true || child._visible !== true
                || child.__unitInitializedVersion == null || child.__unitInitializedVersion !== child.version
                || child.兵种 !== "敌人-CF6老头机器人" || child.等级 !== phase.level
                || child.是否为敌人 !== phase.side || child.产生源 !== phase.source
                || !finite(child.hp) || !finite(child.hp满血值) || !(child.hp满血值 > 0)) {
            if (elderWaitFrames >= 600) failElder("native-successor-not-ready");
            return;
        }
        // Native unit code alone creates and counts the successor; this controller binds it.
        plan=plan.nextPhase;bossMark={};child.cf6BossIdentity=bossMark;child.publishStageEvent=true;
        bindFinalDeath(child);
        groupIndex=0;waitFrames=0;elderWaiting=false;
        trace("[CF6_FINALE_PHASE] robot-ready; native successor="+child._name);
    }
    private function beginFinalDeath():Void {
        if(finalDying) return;finalDying=true;queue=[];
        for(var name:String in living) {living[name].retired=true;retireRecord(living[name]);}
        living={};
    }
    private function bindFinalDeath(child:MovieClip):Void {
        if(typeof child.死亡检测!="function") {failElder("successor-death-handler-missing");return;}
        finalDeathOriginal=child.死亡检测;
        finalDeathWrapper=finalDeathCallback(this,bossMark,finalDeathOriginal);
        child.死亡检测=finalDeathWrapper;
    }
    private static function finalDeathCallback(controller:Cf6BossEncounter,mark:Object,original:Function):Function {
        return function(options:Object):Void {
            controller.observeFinalDeath(this,mark);
            original.call(this,options);
        };
    }
    private function observeFinalDeath(child:MovieClip,mark:Object):Void {
        if(!current() || elderError!=undefined || !elderStarted || elderWaiting || mark!==bossMark
                || child!==world[plan.instanceName] || child.cf6BossIdentity!==mark
                || !finite(child.hp) || child.hp>0) return;
        var body:MovieClip=child.man;
        if(body.elderMode!=="death" || body._currentframe!==body._totalframes
                || body.cf6CorpseFinished!==true || body.尸体碎片.cf6Settled!==true) return;
        // Captured before native removeMovieClip invalidates the actor reference.
        finalDeathReady={mark:mark,owner:owner,name:plan.instanceName};
    }
    private function victoryReady():Boolean {
        if(elderStarted && plan.nextPhase==null)
            return elderError==undefined && finalDeathRemoved && finalDeathReady.mark===bossMark && finalDeathReady.owner===owner
                && finalDeathReady.name===plan.instanceName;
        return bossDead();
    }
    private function bind(record:Object):MovieClip {
        var unit:MovieClip=world[record.name];
        if (unit == undefined || unit.cf6BossOwnerToken !== token) return null;
        if (record.mark == null) { record.mark={}; unit.cf6SupportIdentity=record.mark; }
        return unit.cf6SupportIdentity === record.mark ? unit : null;
    }
    private function refreshGuard(record:Object):Void {
        if (record.kind !== "兵种469") return;
        var parent:MovieClip=bind(record);
        if (record.phase == null && parent.guardTransform != null) record.phase=parent.guardTransform;
        var phase:Object=record.phase;
        if (phase == null || phase.world !== world || phase.name !== record.name+"__tyrant") return;
        var child:MovieClip=phase.child;
        if (child == undefined || child._parent !== world || child._name !== phase.name
                || world[phase.name] !== child || phase.attempted !== true
                || child.名字 !== "暴君克隆兽" || child.等级 !== phase.level
                || child.是否为敌人 !== phase.side || child.产生源 !== phase.source
                || (child.兵种 != undefined && child.兵种 !== "敌人-完全体克隆兽")) return;
        // attachMovie 的 initObject 在资源首帧初始化之前已存在；因此初始化中也可精确退场。
        if (record.childMark == null) { record.childMark={}; child.cf6SupportIdentity=record.childMark; }
        if (child.cf6SupportIdentity !== record.childMark) return;
        child.cf6BossOwnerToken=token; child.publishStageEvent=true;
        record.childName=phase.name;
    }
    private function retire(unit:MovieClip, mark:Object):Void {
        if (unit == undefined || mark == null || unit.cf6SupportIdentity !== mark || unit.cf6BossOwnerToken !== token) return;
        unit.已加经验值=true; unit.掉落物=[]; unit.removeMovieClip();
    }
    private function retireRecord(record:Object):Void {
        refreshGuard(record);
        retire(bind(record),record.mark);
        if (record.childName != null) retire(world[record.childName],record.childMark);
    }
    private function onSpawn(name:String):Void {
        if (!worldOwned()) return;
        var record:Object=issued[name];
        if (record == null) return;
        bind(record);
        if (stopped || record.retired === true) retireRecord(record);
    }
    private function onDeath(name:String):Void {
        if (!current()) return;
        if (name === plan.instanceName) {
            if (bossDead()) {
                if (plan.nextPhase != null) beginElder();
                else if(elderStarted) beginFinalDeath();
                else finish(true);
            }
            return;
        }
        for (var key:String in living) {
            var record:Object=living[key]; refreshGuard(record);
            if (name === record.childName) {
                var child:MovieClip=world[name];
                if (child.cf6SupportIdentity === record.childMark && finite(child.hp) && child.hp <= 0) delete living[key];
            } else if (name === key) {
                var unit:MovieClip=bind(record);
                if (unit == null || !finite(unit.hp) || unit.hp > 0) continue;
                // 变身父体的死亡不释放位置；后继正常死亡才释放同一逻辑槽位。
                if (record.kind !== "兵种469" || unit.光头保安变身 === false) delete living[key];
            }
        }
    }
    private function onRemoved(name:String):Void {
        if (!current()) return;
        if(elderStarted && !elderWaiting && name===plan.instanceName) {
            if(elderError==undefined && finalDeathReady.mark===bossMark && finalDeathReady.owner===owner
                    && finalDeathReady.name===name) finalDeathRemoved=true;
            else failElder("robot-removed-before-native-death-completion");
            return;
        }
        // 未知消失不冒充死亡，也不重放；最多保留一个预占位置直至本场结束。
        for (var key:String in living) refreshGuard(living[key]);
    }
    private function finish(victory:Boolean):Void {
        if (stopped) return;
        var mayWin:Boolean=victory && current() && victoryReady();
        stopped=true; queue=[];
        if (!worldOwned()) return;
        var boss:MovieClip=world[plan.instanceName];
        if(boss.cf6BossIdentity===bossMark && boss.死亡检测===finalDeathWrapper && finalDeathOriginal!=undefined)
            boss.死亡检测=finalDeathOriginal;
        org.flashNight.arki.scene.Cf6InteractivePropService.cancelBossPods(world);
        if (clock.cf6BossOwnerToken === token) delete clock.onEnterFrame;
        world.dispatcher.unsubscribe("UnitDeath",onDeath,this);
        world.dispatcher.unsubscribe("UnitRemoved",onRemoved,this);
        // UnitSpawn 留下仅本场 token 的墓碑，以处理已发出但迟到的增援。
        if (mayWin && WaveSpawner.instance === spawner) spawner.close();
        for (var name:String in living) {living[name].retired=true;retireRecord(living[name]);}
        living={};
        if (mayWin && scope()) manager.clearStage();
    }
}
