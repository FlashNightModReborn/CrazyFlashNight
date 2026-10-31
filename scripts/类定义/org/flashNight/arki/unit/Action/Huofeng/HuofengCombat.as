import org.flashNight.arki.unit.Action.Huofeng.*;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletCancelQueueProcessor;

/** 链锤与涅槃只声明原生伤害类型；伤害、抗性、护盾和飘字统一由既有管线结算。 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengCombat {
    private static var fallbackIdentity:Number=0;
    private static var point:Object={x:0,y:0};

    public static function primaryAttributes(unit:Object,bullet:Object):Void {
        // 只从非武器汇总层投影，绝不借用真实刀槽或拳套模组词条。
        var source:Object={伤害类型:unit.基础伤害类型 || "物理",魔法伤害属性:unit.基础魔法伤害属性,
            毒:unit.基础毒,吸血:unit.基础吸血,击溃:unit.基础击溃,斩杀:unit.基础斩杀,
            暴击率:unit.暴击率};
        delete bullet.伤害类型;
        delete bullet.魔法伤害属性;
        delete bullet.暴击;
        bullet.毒=HuofengRules.numberOrZero(unit.基础毒);
        bullet.吸血=HuofengRules.numberOrZero(unit.基础吸血);
        bullet.血量上限击溃=HuofengRules.numberOrZero(unit.基础击溃);
        bullet.斩杀=HuofengRules.numberOrZero(unit.基础斩杀);
        // 尚未安装 lock 位时复用原生“药剂/酒水暴击率”包装，之后冻结快照。
        BulletInitializer.inheritShooterAttributes(bullet,source);
        bullet.lockShooterAttributes=true;
        bullet.命中率=unit.基础命中率*(1+HuofengRules.numberOrZero(unit.基础命中加成)/100);
        decorateCold(unit,bullet);
    }

    public static function decorateCold(unit:Object,bullet:Object):Void {
        // Only the set's meteor hammer is converted. Real weapons keep their own type.
        if (!HuofengRules.profileActive(unit)) return;
        var tier:Number=unit.__huofeng.getTier();
        if (tier==1) {
            bullet.伤害类型="破击";
            bullet.魔法伤害属性="热";
        } else if (tier>=2) {
            bullet.伤害类型="魔法";
            bullet.魔法伤害属性="热";
        }
    }

    private static function baseBullet(unit:MovieClip,power:Number,depth:Number,push:Number,knockRate:Number):Object {
        var bullet:Object={发射者:unit._name,声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
            子弹种类:"近战子弹",子弹速度:0,击中地图效果:"",击中后子弹的效果:"空手攻击火花",
            shootZ:unit.Z轴坐标,子弹威力:power,Z轴攻击范围:depth,击倒率:knockRate,
            水平击退速度:push,垂直击退速度:0,固伤:0,百分比伤害:0,__huofengFinalPower:true};
        primaryAttributes(unit,bullet);
        return bullet;
    }

    public static function emit(unit:MovieClip,action:Object,b:Number,f:Number,depth:Number,push:Number,knockRate:Number):Void {
        if (!HuofengAction.ownsMan(unit,action)) return;
        var power:Number=b*HuofengRules.attackUnit(unit)+f*HuofengRules.numberOrZero(unit.内力);
        var bullet:Object=baseBullet(unit,power,depth,push,knockRate);
        bullet.技能名=action.kind==="spin" ? "焰链回旋" : "火凤链锤";
        bullet.__huofengPulse={action:action,seen:{}};
        // 三处采样是同一小段的空间覆盖，不是三次独立伤害。
        for(var i:Number=1;i<=3;i++) emitAt(unit,bullet,unit.man["hfHit"+i]);
    }

    /** The rotating chain covers both directions; ordinary cancellation only.
     * Reuse the damage bands and native faction/Z/stationary/melee rules. */
    public static function cancelBullets(unit:MovieClip,action:Object):Void {
        if (!HuofengAction.ownsMan(unit,action) || !(unit.hp>0) || _root.暂停) return;
        var request:Object={shooter:unit._name,shootZ:unit.Z轴坐标,
            消弹敌我属性:unit.是否为敌人,消弹方向:null,Z轴攻击范围:35,反弹:false,强力:false};
        for(var i:Number=1;i<=3;i++) {
            request.区域定位area=unit.man["hfHit"+i];
            BulletCancelQueueProcessor.enqueue(request);
        }
    }

    public static function emitAt(unit:MovieClip,bullet:Object,area:MovieClip):Void {
        if (area==undefined) return;
        point.x=0;
        point.y=0;
        area.localToGlobal(point);
        _root.gameworld.globalToLocal(point);
        bullet.shootX=point.x;
        bullet.shootY=point.y;
        bullet.区域定位area=area;
        _root.子弹区域shoot传递(bullet);
    }

    public static function blast(unit:MovieClip,action:Object):Void {
        if (!HuofengAction.ownsMan(unit,action)) return;
        var tier:Number=action.tier;
        var power:Number=HuofengRules.BLAST_B[tier]*HuofengRules.attackUnit(unit)
            +HuofengRules.BLAST_F[tier]*HuofengRules.numberOrZero(unit.内力);
        var bullet:Object=baseBullet(unit,power,HuofengRules.BLAST_DEPTH[tier],2,30);
        // 复活爆发只有自身热伤，不带主段词条、不再触发热附击。
        bullet.伤害类型="魔法";
        bullet.魔法伤害属性="热";
        bullet.毒=0;
        bullet.吸血=0;
        bullet.血量上限击溃=0;
        bullet.击溃=0;
        bullet.斩杀=0;
        delete bullet.暴击;
        bullet.__huofengPulse={action:action,seen:{}};
        bullet.技能名=tier==1 ? "涅槃" : "涅槃复苏";
        bullet.__huofengBlast={x:unit._x,z:unit.Z轴坐标,radius:tier==1?75:90};
        emitAt(unit,bullet,unit.man.hfBlast);
    }

    /** BQP 在任何伤害/命中钩子之前领取；MISS 也消费本次接触，禁止三次闪避重投。 */
    public static function claimPulse(bullet:Object,target:Object):Boolean {
        var pulse:Object=bullet.__huofengPulse;
        if (pulse==null) return true;
        var action:Object=pulse.action;
        if (action.cancelled || !action.owner.isActive()) return false;
        if (action.requiresProfile && !HuofengRules.profileActive(action.owner.getUnit())) return false;
        var blast:Object=bullet.__huofengBlast;
        if (blast!=undefined) {
            var dx:Number=Number(target._x)-blast.x;
            var dz:Number=Number(target.Z轴坐标)-blast.z;
            // Top-down radius complements the engine's independent Z-depth gate.
            if (!isFinite(dx) || !isFinite(dz) || dx*dx+dz*dz>blast.radius*blast.radius) return false;
        }
        // Only custom hammer samples share a seen table. Native multi-hit
        // projectiles and independent blade nodes keep the standard hit lifecycle.
        if (pulse.seen==undefined) return true;
        var record:Object=target.__battleRecord;
        var key:String;
        if (record!=null && record.unitId!=undefined) key=record.unitId+":"+record.life;
        else {
            if (target.__huofengTargetIdentity==undefined) target.__huofengTargetIdentity=++fallbackIdentity;
            key="fixture:"+target.__huofengTargetIdentity+":"+target.version;
        }
        if (pulse.seen[key]===true) return false;
        pulse.seen[key]=true;
        return true;
    }

}
