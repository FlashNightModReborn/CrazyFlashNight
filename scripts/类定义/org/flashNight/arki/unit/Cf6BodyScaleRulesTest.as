import org.flashNight.arki.unit.*;
class org.flashNight.arki.unit.Cf6BodyScaleRulesTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else {failed++; trace("[FAIL] Cf6BodyScaleRules: " + label);}
    }
    private static function checkBody(kind:String, cm:Number, body:Number):Void {
        var target:Number = cm * 145.192765 / 175;
        var scale:Number = Cf6BodyScaleRules.heightScale(kind, cm, 100);
        check(Math.abs(body * scale / 100 - target) < 0.00001, kind + " measured body");
        check(Cf6BodyScaleRules.heightScale(kind, cm, scale) == scale, kind + " no multiplicative reapply");
        var holder:MovieClip = _root.createEmptyMovieClip("__cf6BodyScaleFixture", _root.getNextHighestDepth());
        var clip:MovieClip = holder.createEmptyMovieClip("body", 1);
        clip.beginFill(0x112233);clip.moveTo(0,0);clip.lineTo(10,0);clip.lineTo(10,-body);clip.lineTo(0,-body);clip.lineTo(0,0);clip.endFill();
        clip._xscale = -scale;clip._yscale = scale;
        var bounds:Object = clip.getBounds(holder);
        check(Math.abs(bounds.yMax - bounds.yMin - target) < 0.15, kind + " real MovieClip signed scale");
        holder.removeMovieClip();
        check(Cf6BodyScaleRules.heightScale(kind, 0, 93) == 93, kind + " invalid height fallback");
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        checkBody("敌人-CF6普通男僵尸", 175, 125.76746279166667);
        checkBody("敌人-CF6女僵尸", 175, 123.54263131978324);
        checkBody("敌人-CF6Wings", 190, 130.3736450718499);
        checkBody("敌人-CF6特种兵", 175, 131.81280009898865);
        checkBody("敌人-CF6持盾特种兵", 175, 131.81280009898865);
        checkBody("敌人-CF6光头保安", 175, 128.02282395);
        checkBody("敌人-CF6变身光头保安", 175, 128.02282395);
        var kinds:Array = ["敌人-完全体克隆兽", "敌人-CF6巨汉", "玩家", "敌人-CF6普通男僵尸-伪", "", "toString", "__proto__"];
        for(var i:Number=0;i<kinds.length;i++) check(Cf6BodyScaleRules.heightScale(kinds[i],230,131)==131,"exact scope " + kinds[i]);
        check(Cf6BodyScaleRules.heightScale(undefined,175,100)==100,"undefined kind");
        check(Cf6BodyScaleRules.heightScale(null,175,100)==100,"null kind");
        check(Cf6BodyScaleRules.heightScale("敌人-CF6普通男僵尸",NaN,94)==94,"NaN height");
        check(Cf6BodyScaleRules.heightScale("敌人-CF6普通男僵尸",Infinity,95)==95,"infinite height");
        check(Cf6BodyScaleRules.heightScale("敌人-CF6普通男僵尸",undefined,96)==96,"undefined height");
        check(Cf6BodyScaleRules.heightScale("敌人-CF6普通男僵尸",-175,97)==97,"negative height");
        trace("Cf6BodyScaleRulesTest: " + passed + " passed, " + failed + " failed");
    }
}
