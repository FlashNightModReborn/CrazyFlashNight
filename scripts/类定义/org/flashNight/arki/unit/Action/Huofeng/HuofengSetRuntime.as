import org.flashNight.arki.unit.Action.Huofeng.*;
import org.flashNight.arki.unit.Action.Regeneration.HealApplier;
import org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.component.Buff.MetaBuff;
import org.flashNight.arki.component.Buff.Component.ConditionComponent;

/** 五件事务只拥有一个运行态。档位/冷却属于当前地图，装备只拥有其当前投影。 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengSetRuntime {
    private var target:MovieClip;
    private var effect:Object;
    private var equipment:Array;
    private var version;
    private var manager:BuffManager;
    private var state:Object;
    private var registered:Boolean;
    private var disposed:Boolean;
    private var initialized:Boolean;
    private var lastFrame:Number;
    private var healTicks:Number;
    private var projectedTier:Number;
    private var ownerRef:Object;
    private var action:Object;
    private var oldSkill:Object;
    private var skill:Object;
    private var visuals:HuofengVisual;
    private var hudSet:MetaBuff;
    private var hudSetId:String;
    private var hudNirvana:MetaBuff;
    private var hudNirvanaId:String;
    private var hudTier:Number;

    public static function prepare(record:Object, unit:MovieClip):Object {
        if (!unit || !unit.buffManager || unit.__huofeng || !HuofengRules.hasFivePieces(unit)) return null;
        var runtime:HuofengSetRuntime=new HuofengSetRuntime();
        runtime.target=unit;
        runtime.effect=record;
        runtime.version=unit.version;
        runtime.manager=unit.buffManager;
        runtime.equipment=[];
        for(var i:Number=0;i<HuofengRules.SLOTS.length;i++) runtime.equipment.push(unit[HuofengRules.SLOTS[i]]);
        runtime.state=HuofengRunState.forUnit(unit);
        runtime.state.setEquipped=true;
        runtime.registered=false;
        runtime.disposed=false;
        runtime.initialized=false;
        runtime.lastFrame=-1;
        runtime.healTicks=0;
        runtime.projectedTier=-1;
        runtime.hudTier=-1;
        return runtime;
    }

    public function initializeComponent(ref:Object, params:Object):String {
        if (disposed || ref.自机 !== target || ref.套装效果记录 !== effect) return SetEffectController.FAILURE;
        var found:Boolean=false;
        for(var i:Number=0;i<HuofengRules.SLOTS.length;i++) {
            if (ref.装备类型===HuofengRules.SLOTS[i] && target[ref.装备类型]===equipment[i]) found=true;
        }
        if (!found) return SetEffectController.FAILURE;
        if (!registered) {
            var self:HuofengSetRuntime=this;
            if (!SetEffectController.registerResource(ref,function():Void { self.dispose(); })) return SetEffectController.FAILURE;
            registered=true;
            ownerRef=ref;
        }
        if (ref.装备类型==="手部装备") {
            oldSkill=target.主动战技["空手"];
            target.装载主动战技({skillname:"焰链回旋",cd:8000,mp:36,
                description:"抡动流星锤扫击周身，挥击时可消除普通敌方飞弹。轻按转一圈，共消耗36MP；按住追加一圈，总计48MP。消耗按起手与入轮分次扣除，中断不返还。"},"空手",target.手部装备);
            skill=target.主动战技["空手"];
            if (skill==null) return SetEffectController.FAILURE;
        }
        if (ref.装备类型==="上装装备") {
            initialized=true;
            target.__huofeng=this;
            visuals=new HuofengVisual(target,this);
            return SetEffectController.READY_CYCLE;
        }
        return SetEffectController.READY_STATIC;
    }

    private function bindingValid():Boolean {
        if (disposed || !initialized || !target._parent
            || target.__huofeng!==this || target.buffManager!==manager) return false;
        for(var i:Number=0;i<HuofengRules.SLOTS.length;i++) {
            var slot:String=HuofengRules.SLOTS[i];
            if (target[slot]!==equipment[i] || target[slot+"数据"].setId!==HuofengRules.SET_ID) return false;
        }
        return true;
    }

    public function isActive():Boolean {
        // 死亡仍保留资格，成功付费复活入口才有权递增档位。
        return bindingValid() && effect.group.status==="committed";
    }

    public function getState():Object { return state; }
    public function getTier():Number { return isActive() ? Number(state.tier) : 0; }
    public function getAction():Object { return action; }
    public function getUnit():MovieClip { return target; }
    public function controlLocked():Boolean { return action!=null && action.kind==="nirvana" && !action.cancelled; }

    private function synchronizeRun():Void {
        var next:Object=HuofengRunState.forUnit(target);
        if (next===state) return;
        cancelAction(false);
        HuofengNative.cancel(target,false);
        if (visuals!=null) visuals.actionChanged();
        manager.clearHuofengHpContract(this);
        state=next;
        projectedTier=-1;
        healTicks=0;
    }

    /** Existing MetaBuff/HUD registration only; numeric ownership stays with the contract. */
    private function makeStatus(name:String,description:String):MetaBuff {
        var self:HuofengSetRuntime=this;
        var meta:MetaBuff=new MetaBuff([], [new ConditionComponent(
            function():Boolean {return self.isActive();},30,false)],0);
        meta.hudInfo={name:name,description:description,polarity:"neutral",stacks:0};
        return meta;
    }

    private function synchronizeHud(tier:Number):Void {
        if (hudSet==undefined) {
            hudSet=makeStatus("火凤链锤","五件齐备：空手改用流星锤，按冷兵器加成结算。普攻五段30击，跑攻12击。焰链回旋36/48MP、冷却8秒，挥击消弹。成功付费复活触发涅槃。");
            var self:HuofengSetRuntime=this;
            hudSet.hudPresentation={activeLabel:"流星锤模式",inactiveLabel:"切换空手启用",activation:{
                isActive:function():Boolean {return HuofengRules.profileActive(self.target);},
                getRemaining:function():Number {return 0;},getDuration:function():Number {return 0;}}};
            hudSetId=manager.addBuff(hudSet,null);
        }
        if (tier===hudTier) return;
        if (hudNirvana!=undefined && manager.getBuffById(hudNirvanaId)===hudNirvana) manager.removeBuff(hudNirvanaId);
        hudNirvana=null;hudNirvanaId=null;hudTier=tier;
        if (tier!=1 && tier!=2) return;
        var description:String="生命上限为正常值"+Math.round(HuofengRules.HP_FACTORS[tier]*100)
            +"%，每秒回复正常上限"+Math.round(HuofengRules.HEAL_RATES[tier]*100)+"%。";
        description+=tier==1
            ? "仅流星锤攻击转为热破击：附伤为破坏力10%，受热抗影响。跨图或卸下任一火凤防具清零。"
            : "仅流星锤主伤转为纯热属性，不再叠加热附伤。跨图或卸下任一火凤防具清零；后续付费复活仍播放完整涅槃。";
        hudNirvana=makeStatus(tier==1 ? "初次涅槃" : "涅槃复苏",description);
        hudNirvanaId=manager.addBuff(hudNirvana,null);
    }

    private function projectContract():Void {
        var tier:Number=Number(state.tier);
        if (tier!==projectedTier || (tier>0 && target.__huofengHpContract.owner!==this)) {
            if (tier==1 || tier==2) {
                if (!manager.setHuofengHpContract(this,HuofengRules.HP_FACTORS[tier])) return;
            } else manager.clearHuofengHpContract(this);
            projectedTier=tier;
        }
        synchronizeHud(tier);
        if (tier>0 && target.hp>target.hp满血值) target.hp=target.hp满血值;
    }

    public function tick(ref:Object):Void {
        if (disposed) return;
        if (!bindingValid()) {
            if (target.__playerStatInitializing!==true) HuofengRunState.reconcileEquipment(target);
            if (effect.group.status==="committed") SetEffectController.teardownGroup(target,effect.group.id);
            else SetEffectController.failRef(ownerRef,"huofeng_binding_changed");
            return;
        }
        if (!isActive() || target.__playerStatInitializing===true
            || (target.__resourceSpawn!=undefined && target.__resourceSpawn.resourcesReady!==true)) return;
        version=target.version;
        ref.版本号=version;
        synchronizeRun();
        if (state.pendingNirvanaTier>0) requestNirvanaPresentation();
        projectContract();
        if (target.man.__huofengColdSnapshot!=null && !HuofengRules.profileActive(target)) HuofengNative.cancel(target,true);
        if (visuals!=null) visuals.tick();
        // HP can change after this frame's maintenance. Death cleanup must
        // run again even while paused or on the same frame number.
        if (!(target.hp>0)) { cancelAction(false);HuofengNative.cancel(target,false);healTicks=0;return; }
        var frame:Number=Number(_root.帧计时器.当前帧数);
        if (!HuofengRules.finite(frame) || frame===lastFrame) return;
        lastFrame=frame;
        if (_root.暂停) return;
        if (action!=null && !HuofengAction.ownsMan(target,action)) {
            // 等待容器只给一个维护帧，失败不补发过去的爆发。
            if (++action.pendingTicks>1) cancelAction(false);
        }
        if (action!=null && action.kind==="nirvana") {
            if (++action.watchdog>120) cancelAction(true);
            healTicks=0;
            return;
        }
        var tier:Number=Number(state.tier);
        if (tier<1) { healTicks=0; return; }
        // 只累计真正到达的未暂停维护帧，不用时间差补发治疗。
        if (++healTicks<15) return;
        healTicks=0;
        var h0:Number=manager.getHuofengNormalMaxHp();
        var healed:Number=HealApplier.applyHpCapped(target,h0*HuofengRules.HEAL_RATES[tier]*0.5,target.hp满血值);
        if (healed>0 && visuals!=null) visuals.heal(tier);
    }

    public function requestNirvanaPresentation():Void {
        if (!isActive() || _root.暂停 || _root.场景转换中===true || !(target.hp>0) || target.__playerStatInitializing===true
            || target.dressupRefreshing || (target.__resourceSpawn!=undefined && target.__resourceSpawn.resourcesReady!==true)) return;
        synchronizeRun();
        if (!(state.pendingNirvanaTier>0) || state.pendingReviveSequence===state.presentedReviveSequence) return;
        if (action!=null && action.kind==="nirvana") {
            if (HuofengAction.ownsMan(target,action) || action.man==undefined) return;
            cancelAction(false);
        }
        beginNirvana(state.pendingNirvanaTier);
    }

    public function beginNirvana(tier:Number):Void {
        if (!isActive() || !(target.hp>0) || (tier!=1 && tier!=2)) return;
        synchronizeRun();
        projectContract();
        healTicks=0;
        cancelAction(false);
        HuofengAction.begin(this,"nirvana",tier);
    }

    public function startAttack(running:Boolean):Boolean {
        if (!HuofengRules.profileActive(target) || !(target.hp>0) || target.浮空 || action!=null) return false;
        synchronizeRun();
        var frame:Number=Number(_root.帧计时器.当前帧数);
        if (frame<state.primaryReadyFrame) return false;
        if (running && frame<state.runReadyFrame) return false;
        state.primaryReadyFrame=frame+(running ? 48 : HuofengRules.NORMAL_FRAMES[0]+12);
        if (running) state.runReadyFrame=state.primaryReadyFrame;
        return HuofengAction.begin(this,running ? "run" : "normal",0);
    }

    public function canSpin():Boolean {
        return canEnterSpin() && HuofengRules.finite(target.mp) && target.mp>=36;
    }

    // Input eligibility excludes MP so the real release can report a resource denial.
    public function canEnterSpin():Boolean {
        return HuofengRules.profileActive(target) && target.hp>0 && !target.浮空 && action==null
            && (target.状态==="空手站立" || target.状态==="空手行走" || target.状态==="空手跑")
            && Number(_root.帧计时器.当前帧数)>=state.spinReadyFrame;
    }

    public function startSpin():Boolean {
        synchronizeRun();
        if (!canEnterSpin()) return false;
        if (!HuofengRules.finite(target.mp) || target.mp<36)
            return org.flashNight.arki.skill.SkillResourceService.reject(target,"mp");
        // 入口预检第一轮总成本，实际按开招/入轮分别扣款，取消不退款。
        target.mp-=24;
        state.spinReadyFrame=Number(_root.帧计时器.当前帧数)+240;
        HuofengAction.begin(this,"spin",0);
        return true;
    }

    public function setAction(value:Object):Void {
        action=value;
        if (visuals!=null) visuals.actionChanged();
    }
    public function clearAction(value:Object):Void {
        if (action!==value) return;
        action=null;
        healTicks=0;
        if (target.__huofengNirvana===value) delete target.__huofengNirvana;
    }
    public function cancelAction(recover:Boolean):Void {
        if (action!=null) HuofengAction.cancel(this,action,recover);
    }

    public function dispose():Void {
        if (disposed) return;
        disposed=true;
        cancelAction(true);
        HuofengNative.cancel(target,true);
        if (visuals!=null) visuals.dispose();
        if (hudSet!=undefined && manager.getBuffById(hudSetId)===hudSet) manager.removeBuff(hudSetId);
        if (hudNirvana!=undefined && manager.getBuffById(hudNirvanaId)===hudNirvana) manager.removeBuff(hudNirvanaId);
        hudSet=null;hudSetId=null;hudNirvana=null;hudNirvanaId=null;
        if (target.主动战技["空手"]===skill) target.主动战技["空手"]=oldSkill;
        manager.clearHuofengHpContract(this);
        if (target.__huofeng===this) delete target.__huofeng;
        healTicks=0;
    }
}
