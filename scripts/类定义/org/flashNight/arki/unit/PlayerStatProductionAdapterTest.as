import org.flashNight.arki.unit.PlayerStatRefreshCoordinator;
/** 真实 MC、真实数值 adapter 和真实 Heal；全部输入/存档 owner 隔离在 TestLoader 内存。 */
class org.flashNight.arki.unit.PlayerStatProductionAdapterTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var rootKeys:Array=["gameworld","控制目标","存档系统","savePath","_saveExt","主角被动技能","玩家信息界面","暂停","全局健身HP加成","全局健身MP加成","全局健身空攻加成","全局健身防御加成","全局健身内力加成","敌人函数"];
    private static var owned:Array;
    private static var world:MovieClip;
    public static function runAllTests():Void {
        passed=failed=0;owned=[];
        var saved:Object={};var i:Number;
        for(i=0;i<rootKeys.length;i++) saved[rootKeys[i]]=_root[rootKeys[i]];
        var name:String="__playerStatProductionWorld"+getTimer();
        world=_root.createEmptyMovieClip(name,_root.getNextHighestDepth());
        try {
            _root.gameworld=world;_root.控制目标="stat-test";_root.存档系统={};_root.savePath="isolated-stat-production";_root._saveExt={};
            _root.主角被动技能={};
            for(i=8;i<13;i++) _root[rootKeys[i]]=0;
            _root.敌人函数={魔法伤害种类:["基础","电","热","冷","波","蚀","毒","冲","人类"]};
            testPartialRecovery();testValidationAndContract();testSamePathIdentity();testResetBeforeLeaseRelease();
        } catch(error) {check(false,"unexpected: "+error);}
        finally {
            var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;api._setProjectionFaultForTests(undefined);
            for(i=0;i<owned.length;i++) owned[i].c._releaseProjectionLeaseForTests();
            world.removeMovieClip();
            for(i=0;i<rootKeys.length;i++) _root[rootKeys[i]]=saved[rootKeys[i]];
        }
        trace("PlayerStatProductionAdapterTest Tests Passed: "+passed);
        trace("PlayerStatProductionAdapterTest Tests Failed: "+failed);
    }
    private static function check(ok:Boolean,label:String):Void {
        if(ok) {passed++;trace("[PASS] ProductionAdapter: "+label);} else {failed++;trace("[FAIL] ProductionAdapter: "+label);}
    }
    private static function fixture(hp:Number):Object {
        var previous:MovieClip=world["stat-test"];if(previous!=undefined) previous.removeMovieClip();
        var t:MovieClip=world.createEmptyMovieClip("stat-test",world.getNextHighestDepth());
        var factory:Object=org.flashNight.arki.unit.PlayerStatProjectionTest;
        var seed:Object=factory.persistentFixture();
        for(var key:String in seed) if(key!="_name") t[key]=seed[key];
        t.__playerStatBody={};t.hasDressup=true;t.hp基本满血值=800;t.hp满血值=1000;t.mp满血值=500;t.enableShoot=true;
        var f:Object={actor:t,body:t.__playerStatBody,c:new PlayerStatRefreshCoordinator(),hpData:{hp:hp,writes:0},fault:false,steal:false,changeBody:false,deriveFault:false,fields:0};
        attachHpProbe(t,f.hpData);
        f.token=f.c.resetContext(_root.存档系统,String(_root.savePath),_root._saveExt);
        f.c.setAdapter(PlayerStatRefreshCoordinator._productionAdapterForTests(f.c));
        var identity:Object=org.flashNight.arki.scene.StageReturnFlow.worldIdentity(world);
        f.c.bindHero(t,identity,f.body,f.token);f.c.notifyReady(t,identity,f.body,f.token,null);
        _root.玩家信息界面=uiFor(f);
        var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        api._setProjectionFaultForTests(faultFor(f));owned.push(f);return f;
    }
    private static function attachHpProbe(t:MovieClip,value:Object):Void {
        t.addProperty("hp",function():Number {return value.hp;},function(next:Number):Void {value.hp=next;value.writes++;});
    }
    private static function faultFor(f:Object):Function {
        return function(stage:String,target:Object):Void {
            f.fields++;
            if(stage=="field:hp满血值") {
                if(f.steal) {f.steal=false;target.hp-=100;}
                if(f.changeBody) {f.changeBody=false;target.__playerStatBody={};}
                if(f.fault) {f.fault=false;throw new Error("injected_after_max");}
            }
        };
    }
    private static function uiFor(f:Object):Object {
        return {刷新hp显示:function():Void {if(f.deriveFault) {f.deriveFault=false;throw new Error("injected_derived");}},
            刷新mp显示:function():Void {},刷新攻击模式:function():Void {}};
    }
    private static function testPartialRecovery():Void {
        var f:Object=fixture(900);f.fault=true;
        var result:Object=f.c.flush("production_test");
        check(result.status=="failed" && f.actor.hp满血值==800 && f.actor.hp==900 && f.actor.__playerStatProjectionBlocked,"real max-write fault retains resource checkpoint and blocks actor");
        org.flashNight.arki.pause.PauseManager.set(false,"production-test-generic-unpause");
        check(org.flashNight.arki.pause.PauseManager.isPaused() && f.actor.enableShoot===false,"generic unpause cannot release projection failure claim");
        result=f.c.flush("production_retry");
        check(result.status=="applied" && f.actor.hp==800 && f.actor.enableShoot===true,"real 900/1000 retry settles to 800 from original old max");
        f=fixture(1300);f.fault=true;f.c.flush("production_test");
        check(f.c.flush("production_retry").status=="applied" && f.actor.hp==1200,"real overflow retry settles to 1200");
        f=fixture(900);f.deriveFault=true;f.c.flush("production_test");var writes:Number=f.hpData.writes;
        check(f.c.flush("production_retry").status=="applied" && f.hpData.writes==writes,"derived failure does not write current HP again");
    }
    private static function testValidationAndContract():Void {
        var f:Object=fixture(600);var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        var values:Array=[NaN,undefined,Number.POSITIVE_INFINITY];var all:Boolean=true;
        for(var i:Number=0;i<values.length;i++) {
            var snapshot:Object=api.buildPersistentSnapshot(f.actor);
            for(var n:Number=0;n<api.persistentNumberKeys.length;n++) {
                var key:String=api.persistentNumberKeys[n];var old=snapshot.unbuffed[key];snapshot.unbuffed[key]=values[i];
                var before:Number=f.fields;var caught:Boolean=false;
                try {api.applyPersistentSnapshot(f.actor,snapshot);} catch(error) {caught=true;}
                if(!caught || f.fields!=before || f.actor.hp!=600) all=false;
                snapshot.unbuffed[key]=old;
            }
        }
        check(all,"every required scalar rejects NaN/undefined/Infinity before the first live field write");
        f.steal=true;var result:Object=f.c.flush("production_test");
        check(result.status=="failed" && result.reason=="resource_contract_violation" && f.actor.hp==500,"stealth damage is a contract failure and is not silently restored");
        var count:Number=f.fields;
        check(f.c.flush("production_retry").status=="failed" && f.fields==count && f.actor.hp==500,"invalid resource window cannot be replayed");
        f.c._releaseProjectionLeaseForTests();
    }
    private static function testSamePathIdentity():Void {
        var f:Object=fixture(900);f.changeBody=true;
        check(f.c.flush("production_test").status=="failed" && f.actor.hp==900 && org.flashNight.arki.pause.PauseManager.isPaused(),"unplanned body revocation blocks resource writes and keeps a global failure claim");
        var old:MovieClip=f.actor;var oldBody:Object=f.body;
        old.removeMovieClip();var replacement:MovieClip=world.createEmptyMovieClip("stat-test",world.getNextHighestDepth());
        replacement.__playerStatBody={};replacement.hp=777;replacement.hp满血值=888;
        check(old===replacement && replacement.__playerStatBody!==oldBody,"AVM1 same-path MovieClip reference reuse is reproduced with distinct ordinary body");
        check(f.c.flush("late_old_result").status=="failed" && replacement.hp==777 && replacement.hp满血值==888,"late old-body adapter never writes the replacement MC");
        f.c.resetContext(_root.存档系统,String(_root.savePath),{});
        check(f.c.flush("unbound").reason=="pending_actor" && replacement.hp==777,"context reset detaches before any new binding");
    }
    private static function resetReleaseObserver(f:Object,seen:Object):Function {
        return function(value,previous,tag):Void {
            if(tag!="player_stat_projection:release") return;
            seen.calls++;
            seen.token=f.c.contextToken();
            seen.result=f.c.flush("reset_release_subscriber");
        };
    }
    private static function testResetBeforeLeaseRelease():Void {
        var f:Object=fixture(900);f.fault=true;
        check(f.c.flush("reset_failure").status=="failed" && f.actor.__playerStatProjectionBlocked,
            "reset regression begins with a real failed commit and owned pause lease");
        var seen:Object={calls:0};
        var fields:Number=f.fields;var writes:Number=f.hpData.writes;
        var subscription:String=org.flashNight.arki.pause.PauseManager.subscribe(resetReleaseObserver(f,seen),null);
        try {
            f.c.resetContext(_root.存档系统,String(_root.savePath),_root._saveExt);
            check(seen.calls==1 && seen.token!==f.token && seen.result.reason=="pending_actor"
                    && f.fields==fields && f.hpData.writes==writes && f.actor.hp==900,
                "synchronous pause-release subscriber sees new detached context and writes no old actor fields or HP");
        } finally {org.flashNight.arki.pause.PauseManager.unsubscribe(subscription);}
    }
}
