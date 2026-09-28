import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightDefense;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.component.Buff.PodBuff;
import org.flashNight.arki.component.Buff.BuffCalculationType;
import org.flashNight.arki.component.StatHandler.DodgeHandler;
import org.flashNight.neur.Event.EventDispatcher;

class org.flashNight.arki.render.EquipmentLightDefenseTest {
    private static var passed:Number, failed:Number;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("EquipmentLightDefenseTest FAIL: " + label); }
    }
    private static function near(a:Number,b:Number):Boolean { return Math.abs(a-b)<0.00001; }
    private static function actorIn(world:MovieClip):MovieClip {
        var actor:MovieClip = world.createEmptyMovieClip("actor", 10);
        actor.hp=100; actor.version=1; actor.攻击模式="双枪"; actor.闪避加成=50;
        actor.基础躲闪率=3; actor.躲闪率=DodgeHandler.applyDodgeBonus(3,50);
        actor.dispatcher=new EventDispatcher(); actor.syncRefs={};
        actor.buffManager=new BuffManager(actor, {});
        for (var i:Number=0;i<2;i++) {
            var slot:String=i==0?"手枪":"手枪2";
            actor[slot]={name:slot,value:{mods:[]}};
            actor[slot+"数据"]={use:"手枪",inherentTags:i==0?"侧导轨挂点":"侧导轨挂点,电力"};
            var gun:MovieClip=actor.createEmptyMovieClip("gun"+i, i+1);
            gun.createEmptyMovieClip("枪口位置",1);
            actor[slot+"_引用"]=gun;
        }
        return actor;
    }
    private static function refFor(actor:MovieClip,slot:String):Object {
        return {自机:actor,装备类型:slot,来源插件:"战术手电",生命周期函数列表:[]};
    }
    private static function start(ref:Object):Void {
        EquipmentLightController.initialize(ref,{kind:"flashlight",evasionBonus:20,electricEvasionBonus:5});
    }
    public static function runAllTests():Void {
        passed=0; failed=0;
        var oldWorld=_root.gameworld, oldClock=_root.帧计时器, oldPause=_root.暂停;
        var world:MovieClip=_root.createEmptyMovieClip("__equipmentDefenseFixture",_root.getNextHighestDepth());
        _root.gameworld=world; _root.帧计时器={当前帧数:0}; _root.暂停=false;
        EquipmentLightBridge.disconnect();
        var actor:MovieClip=actorIn(world);
        try {
            actor.buffManager.addBuffImmediate(new PodBuff("躲闪率",BuffCalculationType.MULTIPLY,1.2),"other-buff");
            var left:Object=refFor(actor,"手枪"); start(left);
            check(EquipmentLightDefense.getActiveBonus(actor)==20,"无native握手也提供20");
            check(near(actor.躲闪率,3/1.7*1.2),"按已有50点闪避的同一加成池叠加20");
            check(actor.闪避加成==50 && near(actor.buffManager.getBaseValue("躲闪率"),2),"不修改装备原值与manager基值");
            check(actor.buffManager.getActiveBuffCount()==2,"手电与其他buff共存");
            for(var n:Number=0;n<20;n++) EquipmentLightController.update(left);
            check(actor.buffManager.getActiveBuffCount()==2 && near(actor.躲闪率,3/1.7*1.2),"连续刷新不累加");
            actor.状态="双枪换弹"; EquipmentLightController.update(left);
            check(EquipmentLightDefense.getActiveBonus(actor)==20,"换弹保留防御");
            actor.攻击模式="空手"; EquipmentLightController.update(left);
            check(EquipmentLightDefense.getActiveBonus(actor)==0 && near(actor.躲闪率,2.4),"收枪移除且保留其他buff");
            actor.攻击模式="双枪"; EquipmentLightController.update(left);
            check(EquipmentLightDefense.getActiveBonus(actor)==20,"重新持枪恢复");
            actor.手枪_引用._visible=false; EquipmentLightController.update(left);
            check(near(actor.躲闪率,2.4),"枪体隐藏不提供防御");
            actor.手枪_引用._visible=true; actor.hp=0; EquipmentLightController.update(left);
            check(EquipmentLightDefense.getActiveBonus(actor)==0,"死亡移除");
            actor.hp=100; actor._x=10000; EquipmentLightController.update(left);
            var caps:Object={equipmentLights:2};caps["native"]=true;EquipmentLightBridge.configure(caps);
            check(EquipmentLightBridge.payload()=="" && EquipmentLightDefense.getActiveBonus(actor)==20,"屏外裁剪不改变玩法");
            actor._x=0; _root.暂停=true; EquipmentLightController.update(left);
            check(near(actor.躲闪率,3/1.7*1.2),"暂停不消耗或叠加"); _root.暂停=false;
            actor.闪避加成=100; actor.躲闪率=DodgeHandler.applyDodgeBonus(3,100); EquipmentLightController.update(left);
            check(near(actor.躲闪率,3/2.2*1.2),"换装基值重算后仍准确加20");
            var right:Object=refFor(actor,"手枪2");start(right);
            check(EquipmentLightDefense.getActiveBonus(actor)==25 && near(actor.躲闪率,3/2.25*1.2),"电力25取高且不与20叠加");
            check(actor.buffManager.getActiveBuffCount()==2,"双持只有一个防御pod");
            actor.手枪2_引用._visible=false;EquipmentLightController.update(right);
            check(EquipmentLightDefense.getActiveBonus(actor)==20,"较强灯关闭时较弱灯接替");
            actor.手枪2_引用._visible=true;EquipmentLightController.update(right);
            EquipmentLightController.dispose(left);
            check(EquipmentLightDefense.getActiveBonus(actor)==25,"卸下弱灯不移除强灯");
            EquipmentLightController.dispose(right);EquipmentLightController.dispose(right);
            check(near(actor.躲闪率,1.8) && actor.buffManager.getActiveBuffCount()==1,"幂等卸载准确还原其他buff");
            EquipmentLightController.update(right);
            check(EquipmentLightDefense.getActiveBonus(actor)==0,"迟到周期不复活卸载的加成");
            left=refFor(actor,"手枪");start(left);
            actor.手枪.value.mods.push("new-mod");EquipmentLightController.update(left);
            check(near(actor.躲闪率,1.8),"插件集合变化使旧防御失效");
            left=refFor(actor,"手枪");start(left);
            actor.version++;EquipmentLightController.update(left);
            check(EquipmentLightDefense.getActiveBonus(actor)==0,"版本变化清理");
            left=refFor(actor,"手枪");start(left);
            actor.removeMovieClip();actor=actorIn(world);
            right=refFor(actor,"手枪2");start(right);
            var replacementRate:Number=actor.躲闪率;
            EquipmentLightController.dispose(left);
            check(EquipmentLightDefense.getActiveBonus(actor)==25 && near(actor.躲闪率,replacementRate),"同路径旧owner清理不能污染新actor");
            EquipmentLightController.dispose(right);
            var builtin:Object=refFor(actor,"手枪");delete builtin.来源插件;start(builtin);
            check(EquipmentLightDefense.getActiveBonus(actor)==0,"内置灯不因视觉迁移获赠插件数值");
            EquipmentLightController.dispose(builtin);
        } catch(error:Error) { check(false,"exception "+error); }
        actor.buffManager.destroy();actor.dispatcher.destroy();EquipmentLightBridge.disconnect();world.removeMovieClip();
        _root.gameworld=oldWorld;_root.帧计时器=oldClock;_root.暂停=oldPause;
        trace("EquipmentLightDefenseTest Tests Passed: "+passed);trace("EquipmentLightDefenseTest Tests Failed: "+failed);
    }
}
