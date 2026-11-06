/** Versioned observations at existing combat commit/terminal boundaries. */
class org.flashNight.arki.scene.Cf6SoldierSignals {
    private static var room:Object;
    private static var serial:Number=0;
    public static function bindRoom(context:Object):Void {room=context;}
    public static function current():Boolean {
        return room!=null && room.world===_root.gameworld
            && room.owner===org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld);
    }
    public static function identity(actor:Object):String {
        if(!current() || actor==null || actor._parent!==room.world || actor.version==undefined)return "";
        var mark:Object=actor.__cf6SignalIdentity;
        if(mark==null || mark.epoch!==room.owner || mark.version!==actor.version || mark.actor!==actor){
            mark={epoch:room.owner,version:actor.version,actor:actor,key:room.key+".u"+(++serial)};
            actor.__cf6SignalIdentity=mark;
        }
        return mark.key;
    }
    public static function owns(record:Object):Boolean {
        if(record==null)return false;
        var actor:Object=record.actor;
        return current() && record!=null && record.worldEpoch===room.owner && actor._parent===room.world
            && actor._name===record.name && actor.version===record.version
            && actor.__cf6SignalIdentity===record.signalMark;
    }
    public static function event(actor:Object,name:String):Void {
        var record:Object=actor.cf6ActionRecord;
        if(!owns(record) || record.actor!==actor)return;
        record.events[name]=++room.sequence;record.eventFrames[name]=room.clock;
        if(name=="death")record.combatDead=true;
    }
    public static function reloadCommitted(actor:Object,slot:String):Void {
        var record:Object=actor.cf6ActionRecord,owner:Object=actor.soldierAttackOwner;
        if(!owns(record) || slot!="长枪" || !owner.fixed || !owner.reload || owner.reloadReceiptCommitted
            || owner.weapon!==actor.长枪 || owner.token!==actor.man.soldierToken)return;
        owner.reloadReceiptCommitted=true;record.reloadSequence++;
    }
    public static function playerState(actor:Object,state:String):Void {
        if(!current() || actor._name!==_root.控制目标 || !(actor.hp>0))return;
        if(state!="空手攻击" && state!="近战" && state!="兵器攻击" && state!="空手冲击" && state!="兵器冲击"
            && state!="长枪冲击" && state!="手枪冲击" && state!="双枪冲击"
            && state!="长枪攻击" && state!="手枪攻击" && state!="双枪攻击" && state!="躲闪")return;
        playerCommit(actor,state,actor.man);
    }
    /** A successful native container attachment is a committed action. Buffs,
     * walking and missing symbols never synthesize a counterattack trigger. */
    public static function playerContainer(actor:Object,kind:String,name:String,body:MovieClip):Void {
        if(!current() || actor._name!==_root.控制目标 || !(actor.hp>0) || body._parent!==actor)return;
        if(kind!="unarmed" && kind!="weapon"){
            if(kind!="skill" && kind!="battleSkill")return;
            var accepted:String="|小跳|闪现|一瞬千击|寸拳|气动波|踩人|日字冲拳|组合拳|旋风腿|虎拳|兽王崩拳|瞬步斩|凶斩|火舞旋风|拔刀术|龙斩|六连|空间斩|迅斩|震地|地震|觉醒震地|追猎射击|翻滚换弹|火力支援|上帝之杖|死亡绽放|不卸之力|重力场|重力井|王之财宝|背摔|抱腿摔|龟派气功|升龙拳|径庭拳/黑闪|追踪五连|狼跳|回旋裂地|破坏殆尽|一文字落雷|战技小跳|特勤盾冲|蓝瞬步斩|";
            if(name=="" || name.indexOf("|")>=0 || accepted.indexOf("|"+name+"|")<0)return;
        }
        playerCommit(actor,kind+":"+name,body);
    }
    private static function playerCommit(actor:Object,state:String,body:MovieClip):Void {
        var key:String=identity(actor);
        if(key=="")return;
        var mark:Object;
        if(body!=null && body._parent===actor){
            mark=body.__cf6PlayerCommitMark;
            if(mark==null){mark={};body.__cf6PlayerCommitMark=mark;}
            if(room.player.key===key && room.player.mark===mark)return;
        }
        room.player={key:key,version:actor.version,sequence:++room.sequence,frame:room.clock,state:state,mark:mark};
    }
    private static function externalRecord(actor:Object,kind:String):Object {
        if(!current() && !org.flashNight.arki.scene.Cf6Type61Service.ensureFixedWorld(_root.gameworld))return null;
        if(!current() || actor._parent!==room.world)return null;
        var lookup:String=kind;
        if(kind=="wings"){
            if(actor.兵种!="敌人-CF6Wings")return null;
            lookup="wings."+identity(actor);
        }else{
            var expected:String=kind=="robot"?"cf6Boss_A20__elderbot":"cf6Boss_A20";
            if(room.mapId!="A20" || actor._name!==expected || actor.cf6BossIdentity==null)return null;
        }
        var record:Object=room.external[lookup];
        if(record!=null)return owns(record) && record.actor===actor?record:null;
        var key:String=identity(actor);if(key=="")return null;
        record={actor:actor,name:actor._name,version:actor.version,signalMark:actor.__cf6SignalIdentity,
            worldEpoch:room.owner,key:key,busy:false,owner:null,sequence:0,frame:-1,bossMark:actor.cf6BossIdentity};
        record.kind=kind;record.dispatches=0;record.group=null;
        room.external[lookup]=record;
        if(kind=="wings" && room.mapId=="A18" && actor.cf6SpawnWave===1
            && actor.cf6SpawnEntry===0 && actor.cf6SpawnOrdinal===0)room.designatedWings=record;
        return record;
    }
    public static function bindBoss(actor:Object,kind:String):Void {externalRecord(actor,kind);}
    public static function externalStart(actor:Object,kind:String,owner:Object,highRisk:Boolean):Void {
        var record:Object=externalRecord(actor,kind);
        if(record==null || owner==null)return;
        record.owner=owner;record.busy=highRisk;
        record.dispatches=0;record.group=null;actor.__cf6ExternalRecord=record;
        if(highRisk)record.startedAt=room.clock;
    }
    public static function externalEnd(actor:Object,kind:String,owner:Object,complete:Boolean):Void {
        var record:Object=externalRecord(actor,kind);
        if(record==null || record.owner!==owner)return;
        if(record.busy && complete){record.sequence=++room.sequence;record.frame=room.clock;}
        if(record.group!=null){
            if(record.dispatches>0)org.flashNight.arki.scene.Cf6DamageGroups.seal(record.group);
            else org.flashNight.arki.scene.Cf6DamageGroups.noEmission(record.group);
        }
        record.busy=false;record.owner=null;
    }
    public static function decorate(actor:Object,props:Object):Void {
        var record:Object=actor.__cf6ExternalRecord;
        if(props.cf6DamageGroup!=null || !owns(record) || !record.busy)return;
        if(record.group==null)record.group=org.flashNight.arki.scene.Cf6DamageGroups.begin(record,room.sequence);
        props.cf6DamageGroup=record.group;record.dispatches++;
    }
    public static function externalBusy():Boolean {
        if(!current())return true;
        for(var kind:String in room.external){
            var record:Object=room.external[kind];
            if(owns(record) && record.actor.hp>0 && record.busy
                || org.flashNight.arki.scene.Cf6DamageGroups.live(record,-1))return true;
        }
        return false;
    }
    public static function fill(record:Object,target:Object,o:Object):Void {
        var e:Object=record.events,f:Object=record.eventFrames;
        o.attackEvent=e.damage|0;o.attackAge=o.frame-Number(f.damage);
        if(!isFinite(o.attackAge))o.attackAge=100000;
        o.shieldEvent=e.shield|0;
        o.reloadHidden=isFinite(record.reloadNotBefore) && o.frame<record.reloadNotBefore;
        o.reloadEvent=o.reloadHidden?0:record.reloadSequence;
        o.chargeTerminal=e.charge|0;
        var player:Object=room.player;
        o.commitEvent=player.key===o.targetKey && player.version===o.targetVersion?player.sequence:0;
        o.commitAge=o.frame-player.frame;
        var wings:Object=room.designatedWings,robot:Object=room.external.robot,human:Object=room.external.human;
        o.wingsEvent=owns(wings)?wings.sequence:0;o.wingsRecovery=owns(wings) && wings.actor.hp>0 && !wings.busy;
        o.robotEvent=owns(robot)?robot.sequence:0;o.robotRecovery=owns(robot) && robot.actor.hp>0 && !robot.busy;
        o.humanGuardValid=owns(human) && human.actor.hp>0 && human.actor.cf6BossIdentity===human.bossMark;
        o.guardThreat=o.humanGuardValid && Math.abs(target._x-human.actor._x)<=220;
        o.guardTether=o.humanGuardValid && Math.abs(record.actor._x-human.actor._x)<=220;
        o.guardX=o.humanGuardValid?human.actor._x:record.birthX;
        var first:Object=room.actors["CF6-N-PE-05"],second:Object=room.actors["CF6-N-PE-06"];
        o.reserveEvent=Math.max(reserve(first),reserve(second));
    }
    private static function reserve(record:Object):Number {
        if(record==null || record.worldEpoch!==room.owner)return 0;
        if(!owns(record) && !record.combatDead)return 0;
        return Math.max(record.events.retreat|0,record.events.reload|0,record.events.death|0);
    }
}
