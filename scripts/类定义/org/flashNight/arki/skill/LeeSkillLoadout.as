import org.flashNight.arki.unit.Action.Input.EnemyActionRuntime;
import org.flashNight.arki.unit.Action.Input.LeeActionProfile;

/** Lee 技能页适配：只改本篇的动作槽位，不触碰主角技能表、属性或冷却截止帧。 */
class org.flashNight.arki.skill.LeeSkillLoadout {
    private static var revision:Number = 0;
    private static var identity:Object;
    private static var ids:Array = ["hop","basic","rush","strongRush","a1","a2"];
    public static function isLeeRun():Boolean {
        var run:Object=_root._saveExt.bookRun;
        return run.bookId=="lee-trial" && run.slot===String(_root.savePath);
    }
    public static function actor():Object {
        var run:Object = _root._saveExt.bookRun;
        var unit:Object = _root.gameworld[_root.控制目标];
        return run.bookId == "lee-trial" && run.slot === String(_root.savePath)
            && run.outcome == "active" && unit.__enemyActionPlayer === true
            && unit.__enemyActionRuntime.enabled === true
            && unit.__controlledEnemyContext.run === run && unit.__controlledEnemyContext.slot === run.slot
            && unit.__controlledEnemyContext.world === _root.gameworld.__stageReturnWorldIdentity
            ? unit : null;
    }
    /** 严格复制十二个封闭动作 ID；非法/重复存档整体回到默认配置。 */
    public static function copySlots(value):Array {
        var result:Array = [], seen:Object = {}, valid:Boolean = value instanceof Array && value.length == 12;
        for (var i:Number=0; valid && i<12; i++) {
            var id = value[i];
            if (typeof id != "string" || (id != "" && ids.join("|").indexOf(id) < 0)) { valid=false; break; }
            var known:Boolean = id == "";
            for (var j:Number=0; j<ids.length; j++) if (id === ids[j]) known=true;
            if (!known || (id != "" && seen[id])) { valid=false; break; }
            if (id != "") seen[id]=true;
            result.push(id);
        }
        if (!valid) { result=ids.concat(); while(result.length<12) result.push(""); }
        return result;
    }
    public static function bind(unit:Object):Void {
        var run:Object = _root._saveExt.bookRun;
        if (unit.__enemyActionPlayer !== true || run.bookId != "lee-trial" || run.slot !== String(_root.savePath)) return;
        apply(unit,copySlots(run.leeLoadout));
    }
    private static function apply(unit:Object, slots:Array):Void {
        var runtime:Object=unit.__enemyActionRuntime, profile:Object=runtime.profile;
        profile.quickSlots=slots;
        profile.inputs=profile.inputs.slice(0,3);
        runtime.inputMask=16|32|64;
        for(var i:Number=0;i<12;i++) if(slots[i]!="") {
            var bit:Number=1<<(8+i);
            profile.inputs.push({bit:bit,actionId:slots[i],held:false}); runtime.inputMask|=bit;
        }
        runtime.hudSignature=null;
        EnemyActionRuntime.clearInput(unit);
        identity=runtime.identity; revision++;
    }
    private static function currentRevision(unit:Object):Number {
        if(identity !== unit.__enemyActionRuntime.identity) { identity=unit.__enemyActionRuntime.identity; revision++; }
        return revision;
    }
    public static function snapshot():Object {
        var unit:Object=actor(); if(unit==null) return fail("service_not_ready");
        currentRevision(unit);
        if(org.flashNight.neur.Server.SaveManager.getInstance().hasRewardCommitPending()) return fail("commit_pending");
        var profile:Object=unit.__enemyActionRuntime.profile, learned:Array=[], loadout:Array=[];
        for(var i:Number=0;i<ids.length;i++) {
            var id:String=ids[i], action:Object=profile.actions[id], slots:Array=[];
            for(var j:Number=0;j<12;j++) if(profile.quickSlots[j]===id) slots.push(j+1);
            learned.push({skillKey:action.name,orderIndex:i,level:1,maxLevel:1,type:"武术",
                passive:false,equippable:true,enabled:true,equippedSlots:slots,
                unlockLevel:0,unlockSP:0,upgradeSP:0,mp:0,cooldownMs:Math.round(action.cooldownFrames*1000/30),
                iconKey:action.icon,description:(EnemyActionRuntime.available(unit,id)?"":"尚未觉醒，领悟后可用。")
                    +action.description+" 可在下方快捷栏自由配置。",stateHealth:"ok",writeBlocked:false});
        }
        for(i=0;i<12;i++) {
            action=profile.actions[profile.quickSlots[i]];
            var row:Object={slot:i+1,skillKey:action==null?null:action.name,
                keyLabel:String(_root.keyshow(_root["快捷技能栏键"+(i+1)])||""),stateHealth:"ok",writeBlocked:false};
            if(action!=null) { row.level=1;row.iconKey=action.icon; }
            loadout.push(row);
        }
        return {success:true,v:1,revision:revision,view:"manage",player:{level:Number(_root.等级),skillPoints:0,easyMode:true},
            learned:learned,loadout:loadout,trainer:null,diagnostics:[]};
    }
    private static function slot(value):Boolean { return typeof value=="number" && value>=1 && value<=12 && Math.floor(value)==value; }
    private static function fail(code:String):Object { return {success:false,v:1,error:code,revision:revision}; }
    public static function execute(kind:String,p:Object):Object {
        var unit:Object=actor(); if(unit==null) return fail("service_not_ready");
        if(kind=="snapshot") return p.view=="manage" ? snapshot() : fail("invalid_payload");
        currentRevision(unit);
        if(p.view!="manage" || p.trainerSession!=undefined) return fail("invalid_payload");
        if(p.expectedRevision!==revision) return fail("stale_state");
        if(org.flashNight.neur.Server.SaveManager.getInstance().hasRewardCommitPending()) return fail("commit_pending");
        var slots:Array=unit.__enemyActionRuntime.profile.quickSlots.concat(), before:String=slots.join("|");
        var source:Number=-1, target:Number=Number(p.slot)-1;
        if(kind=="moveSlot") {
            if(!slot(p.sourceSlot)||!slot(p.targetSlot)) return fail("invalid_payload");
            source=p.sourceSlot-1; target=p.targetSlot-1;
            if(slots[source]=="") return fail("slot_empty");
            var old:String=slots[target]; slots[target]=slots[source]; slots[source]=old;
        } else if(kind=="equip") {
            if(!slot(p.slot)) return fail("invalid_payload");
            var id:String="", actions:Object=unit.__enemyActionRuntime.profile.actions;
            for(var i:Number=0;i<ids.length;i++) if(actions[ids[i]].name===p.skillKey) id=ids[i];
            if(id=="") return fail("skill_not_found");
            for(i=0;i<12;i++) if(slots[i]===id) source=i;
            if(source>=0 && source!=target) slots[source]=slots[target];
            slots[target]=id;
        } else if(kind=="unequip") {
            if(!slot(p.slot)) return fail("invalid_payload"); slots[target]="";
        } else return fail("invalid_payload");
        var changed:Boolean=before!==slots.join("|");
        if(changed) {
            _root._saveExt.bookRun.leeLoadout=slots.concat();
            _root.存档系统.markDirty();
            apply(unit,slots);
            if(typeof _root.刷新技能栏显示=="function") _root.刷新技能栏显示();
        }
        return {success:true,v:1,changed:changed,revision:revision,snapshot:snapshot()};
    }
}
