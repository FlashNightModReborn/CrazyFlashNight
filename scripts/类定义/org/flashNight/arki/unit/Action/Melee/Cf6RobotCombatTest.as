import org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;

/** Actual unit declarations, production settlement/knockback/shields; isolated player bodies only. */
class org.flashNight.arki.unit.Action.Melee.Cf6RobotCombatTest {
    private static var passed:Number,failed:Number,serial:Number,deathCount:Number;
    private static var family:String;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6RobotCombatTest: "+family+" "+label);}
    }
    public static function reset(name:String):Void {family=name;passed=failed=serial=deathCount=0;DamageManagerFactory.init();PinkNoiseEngine.getInstance();}
    private static function target(actor:MovieClip):MovieClip {
        var t:MovieClip=_root.cf6MakePlayerTarget(_root.gameworld,"robotEffectTarget"+(++serial),175);
        t._x=actor._x;t._y=t.Z轴坐标=actor.Z轴坐标;t.createEmptyMovieClip("man",2);return t;
    }
    private static function copyBullet(source:Object):Object {
        var data:Object={};for(var key:String in source)data[key]=source[key];
        data.固伤=0;data.flags=256;data.hitCount=0;data.伤害加成=0;
        data.damageManager=DamageManagerFactory.resolveForBullet(data);return data;
    }
    private static function settle(data:Object,actor:MovieClip,t:MovieClip,miss:Boolean):Object {
        actor.dispatcher={publish:function():Void {}};
        var queue:Object=BulletQueueProcessor,impact:Object=DamageResult.getIMPACT(),display:Function=impact.triggerDisplay;
        impact.triggerDisplay=function():Void {};
        var result:Object=queue.settleHit({bullet:data,shooter:actor,Damage:DamageCalculator,flags:256,meleeMask:768},
            t,{overlapCenter:{x:t._x,y:t._y}},1,miss?"躲闪":"未躲闪",true);
        impact.triggerDisplay=display;return result;
    }
    public static function captureDeath(data:Object,actor:MovieClip):Void {
        deathCount++;
        check(actor.hp<=0 && actor.cf6RobotDeathSpent===true,"death authorization precedes emission");
        check(data.cf6DeathBurst===true && data.子弹种类=="近战子弹" && data.子弹威力==actor.空手攻击力*2
            && data.伤害类型=="物理" && data.Z轴攻击范围==80 && data.友军伤害!==true,"one ordinary physical area attack declaration");
        var t:MovieClip=target(actor),sourceBox:AABBCollider=new AABBCollider(0,0,0,0),targetBox:AABBCollider=new AABBCollider(0,0,0,0);
        sourceBox.updateFromBullet(actor.man.cf6DeathPoint,data.区域定位area);targetBox.updateFromUnitArea(t);
        check(sourceBox.checkCollision(targetBox,0).isColliding,"nearby player lies inside real native explosion area");
        t._x+=1000;targetBox.updateFromUnitArea(t);
        check(!sourceBox.checkCollision(targetBox,0).isColliding,"distant player outside explosion area");t._x=actor._x;
        var before:Number=t.hp;settle(copyBullet(data),actor,t,true);check(t.hp==before,"missed death burst does not write HP");
        settle(copyBullet(data),actor,t,false);check(t.hp<before && t.hp>0,"actual death burst uses production damage settlement");
        var actualDamage:Number=before-t.hp,originalHp:Number=actor.hp;
        t.removeMovieClip();
        var rec:Object=actor.fixtureRecord,count:Number=rec.deathBursts,body:MovieClip=actor.man,point:MovieClip=body.cf6DeathPoint;
        actor.cf6RobotDeathSpent=false;actor.hp=1;actor.cf6RobotDeathTick(body);
        check(rec.deathBursts==count && !actor.cf6RobotDeathSpent,"living pose cannot explode");actor.hp=0;
        var paused:Boolean=_root.暂停;_root.暂停=true;actor.cf6RobotDeathTick(body);_root.暂停=paused;
        check(rec.deathBursts==count && !actor.cf6RobotDeathSpent,"pause cannot consume death burst");
        var identity:Object=point.cf6RobotDeathIdentity;point.cf6RobotDeathIdentity={};actor.cf6RobotDeathTick(body);point.cf6RobotDeathIdentity=identity;
        check(rec.deathBursts==count && !actor.cf6RobotDeathSpent,"stale attack point cannot explode");
        var worldIdentity:Object=_root.gameworld.__cf6RobotDeathWorldIdentity;
        _root.gameworld.__cf6RobotDeathWorldIdentity={};actor.cf6RobotDeathTick(body);_root.gameworld.__cf6RobotDeathWorldIdentity=worldIdentity;
        check(rec.deathBursts==count && !actor.cf6RobotDeathSpent,"other world cannot receive old death burst");
        actor.cf6RobotDeathSpent=true;actor.cf6RobotDeathTick(body);actor.cf6RobotDeathTick(body);
        check(rec.deathBursts==count,"repeat death callback cannot emit twice");
        actor.hp=originalHp;
        trace("[CF6_ROBOT_DEATH_TEST] family="+family+" actor="+actor._name+" frame="+body._currentframe+" power="+data.子弹威力+" damage="+actualDamage);
    }
    public static function headCombo(actor:MovieClip,source:Object,nativeKnockback:Function):Void {
        check(source!=null && typeof source.击中时触发函数=="function","actual thrust callback captured");
        if(source==null)return;
        actor.headbotCombo=null;var t:MovieClip=target(actor),data:Object=copyBullet(source);
        t._x=actor._x+(actor.方向=="左"?-150:150);
        var originalHp:Number=actor.hp;actor.hp=500;
        check(source.吸血==30,"actual thrust declares bounded ordinary lifesteal");
        var shieldCount:Number=actor.shield.getShieldCount();
        settle(data,actor,t,true);check(actor.headbotCombo==null,"MISS cannot arm laser follow-up");
        check(actor.hp==500 && actor.shield.getShieldCount()==shieldCount,"MISS grants neither lifesteal nor melee shield");
        data=copyBullet(source);var beforeHitHp:Number=t.hp,result:Object=settle(data,actor,t,false);
        check(actor.headbotCombo.target==t._name && actor.headbotCombo.identity===t.__headbotActionIdentity,"real melee hit binds laser follow-up target");
        var dealt:Number=beforeHitHp-t.hp,healed:Number=actor.hp-500;
        check(healed>0 && Math.abs(healed-dealt*0.3)<1,"real settled thrust heals thirty percent of actual damage with integer rounding");
        trace("[CF6_HEAD_MELEE_HEAL] dealt="+dealt+" healed="+healed+" declaredPercent="+source.吸血);
        var meleeId:Number=actor.headbotMeleeShield,meleeShield:IShield=actor.shield.getShieldById(meleeId);
        check(meleeId>=0 && meleeShield.getCapacity()==200 && meleeShield.getStrength()==35,"real melee hit earns one calibrated shield");
        data.击中时触发函数();check(actor.headbotMeleeShield==meleeId,"duplicate hit callback cannot stack or refresh shield");
        actor.headbotCancelAttack();check(actor.shield.getShieldById(meleeId)!=null,"melee shield survives attack interruption");
        actor.shield.update(179);check(actor.shield.getShieldById(meleeId)!=null,"earned shield lives through 179 frames");
        actor.shield.update(1);check(actor.shield.getShieldById(meleeId)==null,"earned shield expires at 180 frames");
        t.刚体=true;t.免疫击退=t.浮空=t.倒地=t.硬直中=false;t.韧性系数=0;t.remainingImpactForce=0;
        t.移动钝感硬直=t.状态改变=function():Void {};
        t.移动=function(direction:String,speed:Number):Void {this._x+=direction=="右"?speed:-speed;};t.被击移动=nativeKnockback;
        var impact:MovieClip=_root.gameworld.createEmptyMovieClip("headThrustImpact"+serial,_root.gameworld.getNextHighestDepth());
        for(var key:String in data)impact[key]=data[key];impact.破坏力=data.子弹威力;
        ImpactStateHandler.handleImpactState(t,impact,DamageResult(result),actor.方向,true);
        check(t.speed==14 && t.减速度==0.5,"thrust applies strong grounded knockback through real impact handler");
        for(var i:Number=0;i<35;i++)if(t.speed>0)t.onEnterFrame();
        var distance:Number=Math.abs(t._x-actor._x),clock:Number=actor.headbotClock;
        actor.headbotClock+=35;actor.headbotReadyAt=0;
        check(Math.abs(distance-339)<0.1 && actor.headbotChooseAttack(distance,0,0)=="none"
            && actor.headbotComboReady(t,distance,0,0),"150-to-339 knockback enables otherwise out-of-range laser");
        var identity:Object=t.__headbotActionIdentity;t.__headbotActionIdentity={};
        check(!actor.headbotComboReady(t,distance,0,0),"replacement target cannot inherit old follow-up");t.__headbotActionIdentity=identity;
        actor.headbotClock=clock;actor.headbotCombo=null;
        data=copyBullet(source);var old:Object=actor.headbotIdentity;actor.headbotIdentity={};settle(data,actor,t,false);
        check(actor.headbotCombo==null && actor.shield.getShieldById(actor.headbotMeleeShield)==null,"replacement shooter cannot use old contact reward");actor.headbotIdentity=old;
        data=copyBullet(source);settle(data,actor,t,false);meleeId=actor.headbotMeleeShield;
        data=copyBullet(source);settle(data,actor,t,false);
        check(actor.headbotMeleeShield!=meleeId && actor.shield.getShieldById(meleeId)==null,"new melee contact refreshes only the owned layer");
        meleeId=actor.headbotMeleeShield;actor.hp=0;actor.headbotCancelAttack();
        settle(copyBullet(source),actor,t,false);
        check(actor.hp==0 && actor.shield.getShieldById(meleeId)==null,"late contact cannot revive a dead shooter or retain its shield");actor.hp=originalHp;
        actor.headbotCombo={target:t._name,identity:identity,expires:clock-1};
        check(!actor.headbotComboReady(t,distance,0,0),"expired follow-up is rejected");
        impact.removeMovieClip();t.removeMovieClip();
    }
    public static function headShield(actor:MovieClip):Void {
        var foreign:Shield=Shield.createTemporary(17,2,999,"foreign");actor.shield.addShield(foreign);
        actor.状态="空手攻击";actor.headbotBeginAttack(actor.man,"beam");
        var id:Number=actor.headbotBeamShield,s:IShield=actor.shield.getShieldById(id);
        check(id>=0 && s.getCapacity()==200 && s.getStrength()==35,"laser owns the calibrated capacity/strength shield");
        check(s.absorbDamage(100,false,1)==65 && s.getCapacity()==165,"laser shield absorbs its per-hit budget, not its full capacity");
        actor.headbotBeginAttack(actor.man,"beam");
        check(actor.headbotBeamShield!=id && actor.shield.getShieldById(id)==null && actor.shield.getShieldById(foreign.getId())!=null,"reentry replaces only own laser shield");
        id=actor.headbotBeamShield;actor.shield.update(29);check(actor.shield.getShieldById(id)!=null,"laser shield lives through 29 frames");
        actor.shield.update(1);check(actor.shield.getShieldById(id)==null,"laser shield expires after its 30-frame budget");
        actor.headbotBeginAttack(actor.man,"beam");id=actor.headbotBeamShield;actor.headbotCancelAttack();
        check(actor.shield.getShieldById(id)==null && actor.shield.getShieldById(foreign.getId())!=null,"interrupt removes owned shield while preserving another source");
        actor.状态="空手站立";
    }
    public static function finish():Boolean {
        check(deathCount>0,"real death timeline emitted a burst");
        trace("Cf6RobotCombatTest "+family+": "+passed+" passed, "+failed+" failed; deathBursts="+deathCount);return failed==0;
    }
}
