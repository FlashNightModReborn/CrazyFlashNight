import org.flashNight.arki.scene.*;
import org.flashNight.arki.unit.Action.Regeneration.LevelUpRecovery;
import org.flashNight.arki.unit.Action.PickUp.PickUpManager;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

/** 独立真实 MovieClip 夹具，验证死亡边界、分批增援与晚到加载；不读写玩家档案。 */
class org.flashNight.arki.scene.BookIterationTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] BookIteration: " + message); }
    }
    private static function frames(count:Number):Void {
        for (var i:Number = 0; i < count; i++) _root.gameworld.__bookBossEncounter.onEnterFrame();
    }
    private static function actor(name:String, hp:Number):MovieClip {
        var unit:MovieClip = _root.gameworld.createEmptyMovieClip(name, _root.gameworld.getNextHighestDepth());
        unit.hp = hp; unit.hp满血值 = 100;
        return unit;
    }
    private static function spawn(id:String, name:String, parameters:Object):Void {
        _root.__bookSpawns.push(name);
        if (_root.__bookDelayed === true) { _root.__bookLate = name; return; }
        var unit:MovieClip = actor(name, 100);
        unit.掉落物 = parameters.掉落物;
        _root.gameworld.dispatcher.publish("UnitSpawn", name);
    }
    private static function defeated(name:String):Void {
        _root.gameworld[name].hp = 0;
        _root.gameworld.dispatcher.publish("UnitDeath", name);
    }
    private static function setupBoss(plan:Object):Void {
        if (_root.gameworld != undefined) _root.gameworld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("bookIterationWorld", 9284);
        _root.gameworld.dispatcher = new LifecycleEventDispatcher(_root.gameworld);
        actor("hero", 100); actor(plan.instanceName, 100);
        _root.__bookSpawns = []; _root.__bookClears = 0; _root.__bookCloses = 0; _root.__bookDelayed = false;
        _root.暂停 = false;
        var managerClass:Object = StageManager, wheelClass:Object = WaveSpawner;
        managerClass.instance = {isActive:true,isFinished:false,isFailed:false,clearStage:function():Void {
            this.isFinished = true; _root.__bookClears++;
        }};
        wheelClass.instance = {spawnEnemy:spawn,close:function():Void { _root.__bookCloses++; }};
        BookBossEncounter.start(_root.gameworld, plan);
    }
    private static function testBoss():Void {
        var plan:Object = BookRunRules.stages(1729, 6)[0].BasicInformation.BookBoss;
        _root.兵种库 = {};
        for (var g:Number = 0; g < plan.groups.length; g++) for (var n:Number = 0; n < plan.groups[g].enemies.length; n++) {
            var spec:Object = plan.groups[g].enemies[n];
            _root.兵种库[spec.Type] = {兵种名:"fixture",是否为敌人:true};
        }
        setupBoss(plan); frames(180);
        check(_root.__bookSpawns.length == 0, "healthy boss does not frontload reinforcements");
        _root.gameworld[plan.instanceName].hp = 70; frames(1);
        check(_root.__bookSpawns.length == 1, "first HP threshold releases only one enemy");
        frames(150);
        check(_root.__bookSpawns.length == 1, "no simultaneous arrival during interval");
        frames(1); frames(200);
        check(_root.__bookSpawns.length == 2, "two live reinforcements block a third");
        defeated(_root.__bookSpawns[0]); frames(1);
        check(_root.__bookSpawns.length == 3, "defeated reinforcement frees a slot without reissuing it");
        _root.gameworld[plan.instanceName].hp = 20; frames(200);
        check(_root.__bookSpawns.length == 3, "crossing later phases queues rather than bursts");
        _root.暂停 = true; defeated(_root.__bookSpawns[1]); frames(300);
        check(_root.__bookSpawns.length == 3, "pause prevents scheduled reinforcement");
        _root.暂停 = false; _root.gameworld.hero.hp = 0; frames(300);
        check(_root.__bookSpawns.length == 3, "death pauses reinforcement before explicit revival");
        _root.gameworld.hero.hp = 100; frames(1);
        check(_root.__bookSpawns.length == 4, "revival resumes the same finite queue");
        var active:String = _root.__bookSpawns[2];
        defeated(plan.instanceName); frames(500);
        check(_root.__bookClears == 1 && _root.__bookCloses == 1, "boss death finishes once and closes spawning");
        check(_root.gameworld[active] == undefined && _root.__bookSpawns.length == 4,
            "live adds retire and queued later phases are cancelled");
        setupBoss(plan); _root.__bookDelayed = true;
        _root.gameworld[plan.instanceName].hp = 70; frames(1);
        var late:String = _root.__bookLate;
        defeated(plan.instanceName);
        actor(late, 100);
        _root.gameworld.dispatcher.publish("UnitSpawn", late);
        check(_root.gameworld[late] == undefined && _root.__bookClears == 1,
            "asynchronous spawn arriving after victory is retired without another clear");
        setupBoss(plan); _root.gameworld[plan.instanceName].hp = 20;
        StageManager.instance.isActive = false; frames(1);
        check(_root.__bookSpawns.length == 0 && _root.__bookClears == 0, "retreat cancels rather than winning");
    }
    private static function testGrowthAndPickup():Void {
        var unit:Object = {hp:0,mp:7,hp满血值:100,mp满血值:50,根据等级初始数值:function(level:Number):Void {
            this.hp满血值 = level * 100; this.mp满血值 = level * 50; this.hp = 999; this.mp = 999;
        }};
        LevelUpRecovery.refresh(unit, 2);
        check(unit.hp == 0 && unit.mp == 7 && unit.等级 == 2, "zero-HP level up changes level without revival");
        unit.hp = -20; LevelUpRecovery.refresh(unit, 3);
        check(unit.hp == -20 && unit.mp == 7, "overkill cannot be healed by stat initialization");
        unit.hp = 5; LevelUpRecovery.refresh(unit, 4);
        check(unit.hp == 400 && unit.mp == 200, "living player retains ordinary level-up recovery");
        unit.hp = NaN; LevelUpRecovery.refresh(unit, 5);
        check(unit.hp == 0, "missing life authority fails closed");
        var manager:PickUpManager = new PickUpManager();
        var drop:MovieClip = actor("xpDrop", 1);
        drop.物品名 = "经验值"; drop.数量 = 3000; drop.一次性领取ID = "book.iteration.xp";
        drop.gotoAndPlay = function():Void { _root.__bookConsumed++; };
        _root.__bookConsumed = 0; _root.__bookAcquired = 0;
        _root.singleAcquire = function():Boolean { _root.__bookAcquired++; return true; };
        _root.gameworld.hero.hp = 0;
        manager.pickup(drop, null, false);
        check(_root.__bookAcquired == 0 && _root.__bookConsumed == 0 && !PickUpManager.isOneTimeClaimed(drop.一次性领取ID),
            "dead mouse pickup neither grants XP nor consumes entity/claim");
        _root.gameworld.hero.hp = -3;
        manager.pickup(drop, null, true);
        check(_root.__bookAcquired == 0 && _root.__bookConsumed == 0, "dead keyboard pickup is rejected at the same authority");
    }
    private static function testBookCurrency():Void {
        var manager:PickUpManager=new PickUpManager();
        var randomSource:Object=org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine.instance;
        var beforeCheck:Function=randomSource.randomCheck;
        randomSource.randomCheck=function():Boolean {return true;};
        _root.savePath="book.currency.fixture";
        _root.当前关卡名=BookDefinition.get().stageName;
        _root._saveExt.bookRun={slot:_root.savePath,bookId:BookDefinition.get().id,outcome:"active"};
        _root.等级=1;_root.isEasyMode=function():Boolean {return false;};_root.isChallengeMode=function():Boolean {return true;};
        try {
            var money:Object={};manager.createCollectible("金币",500,10,10,false,money);
            check(money.物品名=="金钱","book coins cannot roll an extra K budget even when the generic random roll always succeeds");
            var fixed:Object={};manager.createCollectible("K点",250,10,10,false,fixed);
            check(fixed.数量==250,"authored book K quantity bypasses low-level caps and challenge halving");
            _root.savePath="ordinary.fixture";
            var ordinary:Object={};manager.createCollectible("金币",500,10,10,false,ordinary);
            check(ordinary.物品名=="K点","foreign slot retains ordinary world currency rules");
        } finally {randomSource.randomCheck=beforeCheck;}
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var keys:Array = ["gameworld","兵种库","暂停","singleAcquire","_saveExt","__bookSpawns","__bookClears","__bookCloses","__bookDelayed","__bookLate","__bookAcquired","__bookConsumed","savePath","当前关卡名","等级","isEasyMode","isChallengeMode"];
        var saved:Object = {};
        for (var i:Number = 0; i < keys.length; i++) saved[keys[i]] = _root[keys[i]];
        var stageClass:Object = StageManager, wheelClass:Object = WaveSpawner;
        var oldStage:Object = stageClass.instance, oldWheel:Object = wheelClass.instance;
        var targetClass:Object = org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var oldFind:Function = targetClass.findHero;
        targetClass.findHero = function():MovieClip { return _root.gameworld.hero; };
        _root.gameworld = undefined; _root._saveExt = {};
        try { testBoss(); testGrowthAndPickup(); testBookCurrency(); }
        finally {
            _root.gameworld.removeMovieClip();
            stageClass.instance = oldStage; wheelClass.instance = oldWheel; targetClass.findHero = oldFind;
            for (i = 0; i < keys.length; i++) _root[keys[i]] = saved[keys[i]];
        }
        trace("BookIterationTest Tests Passed: " + passed);
        trace("BookIterationTest Tests Failed: " + failed);
    }
}
