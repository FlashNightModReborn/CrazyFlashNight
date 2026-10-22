/** #154：实际 things5 黑龙 AI / 普攻时间轴；初始化、弹体及存档出口隔离。 */
class org.flashNight.arki.unit.Action.Input.BlackDragonAttackTimelineTest {
    private static var passed:Number, failed:Number, frame:Number, age:Number, index:Number, round:Number;
    private static var stage:String, cases:Array, current:Object, saved:Object;
    private static var driver:MovieClip, world:MovieClip, unit:MovieClip, target:MovieClip;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("[TEST_FAIL] BlackDragonAttackTimelineTest: " + label); }
    }
    public static function initialize(u:MovieClip):Void {
        u.hp=1000; u.攻击模式="空手"; u.状态="空手站立"; u.方向=current.facing;
        u._x=200; u._y=u.Z轴坐标=200; u.攻击目标="dragonTarget"; u.是否为敌人=true;
        u.x轴攻击范围=100; u.y轴攻击范围=10; u.x轴保持距离=50; u.攻击欲望=1000000;
        u.__dragonCompleted=0; u.硬直中=false; u.倒地=false;
        u.状态改变=_root.敌人函数.状态改变;
        u.动画完毕=function():Void {
            this.__dragonCompleted++;
            _root.敌人函数.动画完毕.call(this);
        };
        u.aabbCollider={updateFromUnitArea:function():Void {}};
        u.方向改变=function(value:String):Void { this.方向=value; };
        u.移动=function():Void {}; u.行走=function():Void {}; u.死亡检测=function():Void {};
        u.gotoAndStop("空手站立");
    }
    public static function runAllTests():Void {
        passed=failed=frame=0; index=-1; stage="start";
        cases=[
            {name:"idle-right",start:"空手站立",facing:"右"},
            {name:"idle-left",start:"空手站立",facing:"左"},
            {name:"walk-right",start:"空手行走",facing:"右"},
            {name:"run-left",start:"空手跑",facing:"左"},
            {name:"lost-target",start:"空手站立",facing:"右",removeTarget:true},
            {name:"repeat-idle",start:"空手站立",facing:"右",repeat:true},
            {name:"stagger-recovery",start:"空手站立",facing:"右",interrupt:true}
        ];
        saved={world:_root.gameworld,control:_root.控制目标,auto:_root.控制目标全自动,
            pause:_root.暂停,init:_root.初始化敌人模板,shoot:_root.子弹区域shoot};
        _root.暂停=false; _root.控制目标全自动=false; _root.控制目标="dragonCase";
        _root.初始化敌人模板=function():Void {
            org.flashNight.arki.unit.Action.Input.BlackDragonAttackTimelineTest.initialize(this);
        };
        _root.子弹区域shoot=function():Void {};
        world=_root.createEmptyMovieClip("__blackDragonWorld",_root.getNextHighestDepth());
        _root.gameworld=world; world._visible=false;
        driver=_root.createEmptyMovieClip("__blackDragonDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {
            org.flashNight.arki.unit.Action.Input.BlackDragonAttackTimelineTest.step();
        };
        check(_root.__blackDragonRsl!=undefined,"explicit production shared-library import is placed");
        nextCase();
    }
    private static function nextCase():Void {
        if (unit) unit.removeMovieClip();
        if (target) target.removeMovieClip();
        index++;
        if (index>=cases.length) { finish(); return; }
        current=cases[index]; round=1; age=0; stage="ready";
        target=world.createEmptyMovieClip("dragonTarget",10);
        target.hp=100; target._x=current.facing=="左"?150:250; target._y=target.Z轴坐标=200; target.是否为敌人=false;
        unit=world.attachMovie("敌人-铠甲勇士战马形态","dragonCase",20);
        check(unit!=undefined,"attach actual mounted black dragon: "+current.name);
        if (unit==undefined) finish();
    }
    private static function findAI():MovieClip {
        for (var key:String in unit) {
            if (typeof unit[key].攻击=="function" && typeof unit[key].思考=="function") return unit[key];
        }
        return null;
    }
    private static function fire(ai:MovieClip):Void {
        check(unit.状态==current.start,"initial logical state: "+current.name+" round="+round);
        ai.攻击(100,10,50);
        check(unit._currentframe==51,"real parent reaches ordinary attack frame: "+current.name);
        check(unit.man._totalframes==54,"real ordinary attack has 54 frames: "+current.name);
        check(unit.状态==(_root.__blackDragonExpectLegacy?current.start:"空手攻击"),
            "logical state agrees with tested version: "+current.name);
        age=0; stage="attack";
    }
    private static function step():Void {
        if (stage=="done") return;
        frame++; age++;
        if (frame>1800) { check(false,"native suite watchdog"); finish(); return; }
        if (stage=="ready") {
            if (typeof unit.状态改变!="function" || unit._currentframe!=2) {
                if (age>30) { check(false,"initialization/standing timeline becomes ready"); finish(); }
                return;
            }
            unit.状态改变(current.start); stage="fire"; age=0; return;
        }
        if (stage=="fire") {
            var ai:MovieClip=findAI();
            if (ai==null) {
                if (age>30) { check(false,"real AI function is available before attack"); finish(); }
                return;
            }
            fire(ai); return;
        }
        if (stage!="attack") return;
        if (age==1) {
            var remainingAI:MovieClip=findAI();
            trace("[BLACK_DRAGON_AI] case="+current.name+" remaining="+remainingAI+" parent="+remainingAI._parent);
            check(remainingAI==null,"idle AI is absent on the next native frame: "+current.name);
        }
        if (current.removeTarget && age==5) {
            target.removeMovieClip(); unit.攻击目标="无";
        }
        if (current.interrupt && age==12) {
            // 单独验证受击状态改变可解开循环；不将此用例称为削韧管线验证。
            unit.状态改变("被击");
        }
        var expectLoop:Boolean=_root.__blackDragonExpectLegacy && current.start=="空手站立" && !current.interrupt;
        if (expectLoop) {
            if (age<120) return;
            check(unit._currentframe==51 && unit.状态=="空手站立","old binary reproduces animation/state mismatch: "+current.name);
            check(unit.__dragonCompleted>=2,"old binary naturally repeats beyond two animation ends: "+current.name);
            trace("[BLACK_DRAGON_CASE] "+current.name+" legacy=true loop=true completed="+unit.__dragonCompleted);
            nextCase(); return;
        }
        if (unit._currentframe==2 && unit.状态=="空手站立" && unit.__dragonCompleted>=round) {
            check(age<=60,"actual attack returns by its animation end: "+current.name+" round="+round);
            trace("[BLACK_DRAGON_CASE] "+current.name+" legacy="+_root.__blackDragonExpectLegacy+" round="+round+" returnedAt="+age);
            if (current.repeat && round==1) { round=2; stage="fire"; age=0; return; }
            nextCase(); return;
        }
        if (age>120) { check(false,"attack exits without external intervention: "+current.name); nextCase(); }
    }
    private static function finish():Void {
        if (stage=="done") return;
        stage="done"; delete driver.onEnterFrame;
        if (unit) unit.removeMovieClip();
        if (target) target.removeMovieClip();
        world.removeMovieClip();
        _root.gameworld=saved.world; _root.控制目标=saved.control; _root.控制目标全自动=saved.auto;
        _root.暂停=saved.pause; _root.初始化敌人模板=saved.init; _root.子弹区域shoot=saved.shoot;
        trace("--- BlackDragonAttackTimelineTest: "+passed+"/"+(passed+failed)+" passed, "+failed+" failed ---");
        _root.blackDragonAttackComplete();
    }
}
