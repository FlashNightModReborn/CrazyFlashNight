import org.flashNight.arki.unit.Action.Regeneration.*;
import org.flashNight.arki.component.Effect.HitNumberBatchProcessor;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.unit.UnitBattleRecord;
import org.flashNight.arki.unit.UnitAI.Custom.PhoenixPhaseController;

/** 真实 AVM1 MovieClip、生产拒写setter、生产结算/打包/序列化；无存档写入。 */
class org.flashNight.arki.unit.Action.Regeneration.HealNumberContractTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) { passed++; trace("[PASS] heal-number: " + label); }
        else { failed++; trace("[FAIL] heal-number: " + label); }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var oldServer:Object = _root.server;
        var oldWorld:Object = _root.gameworld;
        var world:MovieClip = _root.createEmptyMovieClip("__healContractWorld", _root.getNextHighestDepth());
        _root.gameworld = world;
        _root.server = {isSocketConnected: true};
        var unit:MovieClip = world.createEmptyMovieClip("ally",1);
        unit._x = 512; unit._y = 360; unit.hp满血值 = 100; unit.hp = 50;
        HitNumberBatchProcessor.clear();
        HitNumberBatchProcessor.setHostEnabled(true);
        HitNumberBatchProcessor.setHealHostEnabled(false);
        check(HealApplier.applyHpCapped(unit,10,100) === 10 && unit.hp === 60,
            "旧Host能力关闭不影响结算");
        check(HitNumberBatchProcessor.getHealQueueLength() === 0,"旧Host默认无治疗事件");
        HitNumberBatchProcessor.setHealHostEnabled(true);
        check(HealApplier.applyHpCapped(unit,0.4,100) > 0,"capped保留小数提交量");
        check(HitNumberBatchProcessor.getHealQueueLength() === 1,"一次真实治疗只入队一次");
        HitNumberBatchProcessor.flush();
        var bridge:Object = org.flashNight.arki.render.FrameBroadcaster;
        var wire:String = bridge._hnPayload;
        var fields:Array = wire.split("|");
        check(fields.length === 11 && Number(fields[3]) === 4194304 && fields[9] === "",
            "heal-only序列化严格11字段且Burst为空");
        check(Number(fields[0]) > 0 && Number(fields[0]) < 1,"wire保留小数");
        check(HitNumberBatchProcessor.getHealQueueLength() === 0,"flush清治疗缓冲");

        unit.hp = 130;
        check(HealApplier.applyHpCapped(unit,20,100) === 0 && unit.hp === 130,"治疗不削掉已有临时生命");
        unit.hp = 0;
        check(HealApplier.applyHpCapped(unit,20,100) === 0 && unit.hp === 0,"普通治疗不复活");
        unit.hp = 90;
        check(HealApplier.applyHpCapped(unit,NaN,100) === 0 && unit.hp === 90,"无效数值无提交");
        unit.__huofengHpContract = {};
        check(HealApplier.applyHpOverflow(unit,100,100) === 10 && unit.hp === 100,
            "火凤overflow转capped回读真实提交");
        check(HitNumberBatchProcessor.getHealQueueLength() === 1,"火凤回退只生成一次事件");
        HitNumberBatchProcessor.clear(); unit.hp = 90;
        check(HealApplier.applyHpOverflow(unit,100,100,true) === 10 &&
            HitNumberBatchProcessor.getHealQueueLength() === 0,"静默policy沿火凤回退传递");
        unit.hp = 90;
        var victim:Object = {hp:100, 损伤值:30};
        var bullet:Object = {吸血:100, 子弹威力:30};
        var result:DamageResult = new DamageResult(); result.actualScatterUsed = 2;
        LifeStealDamageHandle.getInstance().handleBulletDamage(bullet,unit,victim,null,result);
        check(unit.hp === 100 && HitNumberBatchProcessor.getHealQueueLength() === 0,
            "生产吸血保留原汲字且不重复生成绿字");
        check(result._efLifeSteal === 5,"吸血槽使用真实回读量");
        delete unit.__huofengHpContract;

        var boss:MovieClip = world.createEmptyMovieClip("protected",2);
        boss._x=600;boss._y=360;boss.hp满血值=100;
        boss.__phoenixPhase = {hp:50, transition:true, phase:0};
        boss.addProperty("hp", function():Number {return this.__phoenixPhase.hp;},
            function(value:Number):Void {PhoenixPhaseController.setHP(this,value);});
        check(HealApplier.applyHpCapped(boss,20,100) === 0 && boss.hp === 50,
            "生产Phoenix拒写setter不返回虚构治疗量");
        check(HitNumberBatchProcessor.getHealQueueLength() === 0,"拒写不生成事实事件");
        boss.__phoenixPhase.transition = false;
        check(HealApplier.applyHpOverflow(boss,20,100) === 20 && boss.hp === 70,
            "保护结束恢复真实写入");
        var beforeId:String = UnitBattleRecord.healDisplayId(boss);
        UnitBattleRecord.invalidateHealDisplay(boss);
        check(beforeId !== UnitBattleRecord.healDisplayId(boss) &&
            HitNumberBatchProcessor.getHealQueueLength() === 0,"纯显示代际清未发旧生命事件");
        check(boss.__battleRecord.life === 0 && boss.__battleRecord.down === false,
            "显示失效不改变战报life/down");

        result = new DamageResult(); result.addDamageValue(1); result.damageSize = 7014; result._dmgColorId = 7;
        result.triggerDisplay(512,360,"enemy");
        var queue:Object = org.flashNight.arki.component.Effect.HitNumberBatchProcessor;
        var packed:Number = queue._packed[0];
        check(packed === 1939456 && (packed & 4194304) === 0,"异常字号不能占用bit22或串入颜色");
        check(((packed >> 18) & 15) === 7,"字号字段不污染颜色");
        unit.hp=50; HealApplier.applyHpCapped(unit,10,100);
        HitNumberBatchProcessor.setHealHostEnabled(false);
        check(HitNumberBatchProcessor.getHealQueueLength() === 0 &&
            HitNumberBatchProcessor.getQueueLength() === 1,"Hh0只清治疗，不删伤害");
        HitNumberBatchProcessor.setHealHostEnabled(true); HealApplier.applyHpCapped(unit,10,100);
        HitNumberBatchProcessor.clear();
        check(HitNumberBatchProcessor.getQueueLength() === 0 && HitNumberBatchProcessor.getHealQueueLength() === 0,
            "场景清理同时清两类缓冲");
        HitNumberBatchProcessor.setHostEnabled(false);HitNumberBatchProcessor.setHealHostEnabled(false);
        FrameBroadcaster.setHnPayload(null);
        _root.server=oldServer; _root.gameworld=oldWorld; world.removeMovieClip();
        trace("HealNumberContract Tests Passed: " + passed);
        trace("HealNumberContract Tests Failed: " + failed);
    }
}
