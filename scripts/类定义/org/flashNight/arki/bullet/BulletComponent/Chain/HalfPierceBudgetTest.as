import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.bullet.BulletComponent.Loader.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.Shield;
import org.flashNight.arki.component.StatHandler.DodgeHandler;
import org.flashNight.arki.render.ChainVisualBridge;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

class org.flashNight.arki.bullet.BulletComponent.Chain.HalfPierceBudgetTest {
    private static var passed:Number, failed:Number, waitFrames:Number, runIndex:Number;
    private static var done:Boolean, ready:Boolean;
    private static var driver:MovieClip, world:MovieClip, shooter:MovieClip;
    private static var loader:MovieClipLoader, listener:Object;
    private static var guns:Array, assetZones:Array, cache:Object, traces:Array;
    private static var rng:LinearCongruentialEngine, pink:Object;
    private static var events:Array;
    private static var hookCalls:Number;
    private static var lynxParams:Object, killEvents:Array, magazineEvents:Array, killedBy:Object, t181Totals:Object;
    private static var pendingVanishingName:String;
    private static var pendingVanishingFrames:Number;
    private static var nativeFlight:Boolean = false;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else {
            failed++;
            var failure:String = "[TEST_FAIL] HalfPierceBudgetTest: " + label;
            traces[traces.length] = failure;
            trace(failure);
        }
    }

    private static function ensure(ok:Boolean, label:String):Void {
        if (!ok) throw new Error(label);
    }

    public static function runAllTests():Void {
        passed = failed = waitFrames = runIndex = 0;
        done = ready = false;
        guns = [];
        traces = [];
        var server:Object = org.flashNight.neur.Server.ServerManager;
        server.instance = {sendServerMessage:ignoreMessage, isSocketConnected:false};
        trace("[I257_PLAYER] " + System.capabilities.version);
        verifyBudget();
        driver = _root.createEmptyMovieClip("issue257Driver", _root.getNextHighestDepth());
        driver.onEnterFrame = function():Void { HalfPierceBudgetTest.advance(); };
        loadXml(0);
    }

    private static function loadXml(index:Number):Void {
        var doc = new XML();
        doc.ignoreWhite = true;
        doc.issue257Index = index;
        doc.onLoad = function(ok:Boolean):Void {
            if (done) return;
            try {
                var index:Number = this.issue257Index;
                ensure(ok && this.firstChild != null, "load production XML " + index);
                var data:Object = XMLParser.parseXMLNode(this.firstChild);
                if (data.item != undefined) {
                    var rows:Array = XMLParser.configureDataAsArray(data.item);
                    var slots:Object = {SPAS12:0, P90:2, GM6_LYNX:3, T181C:4, MP40:5, G11:6, G111:7};
                    slots["XM556-Microgun"] = 1;
                    slots["Killer 7"] = 8;
                    for (var item:Number = 0; item < rows.length; item++) {
                        var row:Object = rows[item];
                        var slot = slots[row.name];
                        if (slot === undefined) continue;
                        guns[slot] = row.data;
                        guns[slot].profileName = row.name;
                        guns[slot].weapontype = row.weapontype;
                        guns[slot].weaponSlot = row.use;
                        if (slot == 3) lynxParams = row.lifecycle.attr_0.init.initParam;
                        if (slot == 7) check(row.skill.bullet == "铁枪磁轨弹", "G111 charged shot has its own type");
                    }
                    loadXml(index + 1);
                    return;
                }
                for (var i:Number = 0; i < 9; i++) ensure(guns[i] != null, "find weapon profile " + i);
                ensure(lynxParams.bossReward == 5, "find GM6 real reward tiers");
                var attrs:Object = {attributeData:{},shellData:{},movementData:{}};
                var parser:AttributeLoader = new AttributeLoader();
                rows = XMLParser.configureDataAsArray(data.bullet);
                var templates:Array = XMLParser.configureDataAsArray(data.chainTemplate);
                for (var ti:Number = 0; ti < templates.length; ti++) {
                    checkConfiguredTier(templates[ti].attributeOverride, templates[ti].prefix);
                }
                for (var bulletIndex:Number = 0; bulletIndex < rows.length; bulletIndex++) {
                    checkConfiguredTier(rows[bulletIndex].attribute, rows[bulletIndex].name);
                    var attr:Object = parser.load(rows[bulletIndex]);
                    if (attr != null) attrs.attributeData[rows[bulletIndex].name] = attr;
                }
                ChainBulletConfigResolver.resolve(data, attrs);
                var initializer:Object = BulletInitializer;
                initializer.attributeMap = attrs.attributeData;
                loadLibrary();
            } catch (error:Error) {
                failAndFinish(String(error));
            }
        };
        var paths:Array = ["../data/items/武器_长枪_霰弹枪.xml", "../data/items/武器_长枪_压制机枪.xml",
            "../data/items/武器_手枪_冲锋枪.xml", "../data/items/武器_长枪_反器材武器.xml",
            "../data/items/武器_长枪_突击步枪.xml", "../data/items/武器_手枪_特殊.xml", "../data/items/bullets_cases.xml"];
        ensure(doc.load(paths[index]), "start production XML " + index);
    }

    private static function loadLibrary():Void {
        assetZones = [];
        listener = {onLoadInit:loadNextLibrary, onLoadError:libraryFailed};
        loader = new MovieClipLoader();
        loader.addListener(listener);
        loadNextLibrary();
    }

    private static function loadNextLibrary():Void {
        if (done) return;
        var files:Array = ["原版素材库-子弹", "new/雾人整合特效", "new/PTXOA馆长_JohnWick系列"];
        var index:Number = assetZones.length;
        if (index == files.length) {
            world = assetZones[0];
            loaded(world);
            return;
        }
        var zone:MovieClip = _root.createEmptyMovieClip("issue257Assets" + index, _root.getNextHighestDepth());
        assetZones.push(zone);
        if (!loader.loadClip("../flashswf/arts/" + files[index] + ".swf", zone)) libraryFailed(zone, files[index]);
    }

    private static function libraryFailed(clip:MovieClip, code:String):Void {
        failAndFinish("bullet library " + code);
    }

    private static function loaded(clip:MovieClip):Void {
        if (done) return;
        try {
            _root.gameworld = world;
            world.子弹区域 = world;
            _root.暂停 = false;
            _root.帧计时器 = {当前帧数:0, 帧率:30, eventBus:new EventDispatcher()};
            _root.对象浅拷贝 = shallow;
            _root.随机偏移 = spread;
            _root.受击变红 = paletteFeedback;
            _root.发布消息 = ignoreMessage;
            _root.成功率 = successRate;
            _root.Xmin = -1800; _root.Xmax = 1800;
            _root.Ymin = -1000; _root.Ymax = 1000;
            FactionManager.initialize();
            DamageManagerFactory.init();
            ColliderFactoryRegistry.init();
            BulletQueueProcessor.initialize();
            var api:Object = TargetCacheManager;
            api.acquireEnemyCache = acquireEnemies;
            cache = {data:[],leftValues:[],rightValues:[],rightMaxValues:[]};
            ChainUnitManager.getLayer().onEnterFrame = null;
            rng = LinearCongruentialEngine.getInstance();
            pink = PinkNoiseEngine.getInstance();
            EnhancedCooldownWheel.I().每帧毫秒 = 1000 / 30;
            shooter = world.createEmptyMovieClip("issue257Shooter", world.getNextHighestDepth());
            shooter._x = 0;
            shooter._y = shooter.Z轴坐标 = 200;
            shooter.是否为敌人 = false;
            shooter.等级 = 50;
            shooter.命中率 = 10000;
            shooter.伤害加成 = 0;
            shooter.被动技能 = {};
            shooter.dispatcher = new EventDispatcher();
            check(guns[0].split == 10 && guns[0].velocity == 35 && guns[0].weapontype == "霰弹枪", "actual SPAS12 configuration");
            check(guns[1].split == 5 && guns[1].interval == 180, "actual XM556-Microgun configuration");
            check(guns[2].split == 1 && guns[2].bullet == "加强普通子弹", "actual P90 standalone configuration");
            check(BulletInitializer.getAttributeData("加强普通子弹") != null, "loaded canonical bullet attributes");
            check(BulletInitializer.getAttributeData(guns[0].bullet).continuationChance == 50
                && BulletInitializer.getAttributeData(guns[1].bullet).continuationChance == 50
                && BulletInitializer.getAttributeData(guns[2].bullet).continuationChance == 50, "derived and direct enhanced chance");
            check(BulletInitializer.getAttributeData(guns[3].bullet).continuationChance == 100
                && BulletInitializer.getAttributeData(guns[4].bullet).continuationChance == 75, "anti-materiel probabilities from XML");
            var reused:Object = {子弹种类:guns[3].bullet};
            BulletInitializer.initializeBulletProperties(reused);
            reused.子弹种类 = "普通子弹";
            BulletInitializer.initializeBulletProperties(reused);
            check(reused.continuationChance === undefined, "changed type drops old chance");
            ready = failed == 0;
            if (!ready) finish();
        } catch (error:Error) {
            failAndFinish("setup " + error);
        }
    }

    private static function shallow(source:Object):Object {
        var copy:Object = {};
        for (var key:String in source) copy[key] = source[key];
        return copy;
    }

    private static function spread(span:Number):Number { return rng.randomOffset(span); }
    private static function paletteFeedback(duration:Number, unit:MovieClip):Void {}
    private static function ignoreMessage(message:String):Void {}
    private static function acquireEnemies(unit:Object, interval:Number):Object { return cache; }

    private static function newTarget(name:String, x:Number, z:Number, width:Number, hp:Number, shield:Boolean):MovieClip {
        var unit:MovieClip = world.createEmptyMovieClip(name, world.getNextHighestDepth());
        unit._x = x;
        unit._y = unit.Z轴坐标 = z;
        unit.中心高度 = 80;
        unit.hp = unit.hp满血值 = hp;
        unit.防御力 = 17;
        unit.等级 = 50;
        unit.重量 = 30;
        unit.躲闪率 = unit.懒闪避 = 0;
        unit.damageTakenMultiplier = 1;
        unit.魔法抗性 = {基础:0};
        unit.是否为敌人 = true;
        unit.flags = 0;
        unit.dispatcher = new EventDispatcher();
        unit.dispatcher.subscribe("hit", receiveHit, unit);
        unit.dispatcher.subscribe("kill", receiveKill, unit);
        unit.shield = new Shield(shield ? 100000 : 0, shield ? 100000 : 0, 0, 0, "probe", "default");
        var shape:MovieClip = unit.createEmptyMovieClip("area", 1);
        unit.area = shape;
        var edge:Number = width * 0.5;
        shape.beginFill(0x9eabbc);
        shape.moveTo(-edge,-125);
        shape.lineTo(edge,-125);
        shape.lineTo(edge,0);
        shape.lineTo(-edge,0);
        shape.lineTo(-edge,-125);
        shape.endFill();
        var factory:Object = ColliderFactoryRegistry.getFactory("AABB");
        unit.aabbCollider = factory.createFromUnitArea(unit);
        return unit;
    }

    private static function receiveHit(target:MovieClip, actor:MovieClip, bullet:Object, collision:Object, damage:Object):Void {
        if (DamageResult.hasActualHit(damage)) {
            var effective:Number = damage.actualScatterUsed;
            if (damage.scatterModelEnabled === true) effective -= damage.scatterMissCount;
            target.issue257Effective = (target.issue257Effective | 0) + effective;
            if (events != null) events[events.length] = target._name;
        }
    }

    private static function receiveKill(target:MovieClip):Void { target._killed = true; }

    private static function makeCache(unitList:Array):Void {
        var sorted:Array = unitList.slice();
        sorted.sort(compareUnits);
        var left:Array = [], right:Array = [], prefixRight:Array = [];
        var maximum:Number = -Infinity;
        for (var index:Number = 0; index < sorted.length; index++) {
            var shape:Object = sorted[index].aabbCollider;
            left[index] = shape.left;
            right[index] = shape.right;
            prefixRight[index] = maximum = Math.max(maximum, shape.right);
        }
        cache = {data:sorted,leftValues:left,rightValues:right,rightMaxValues:prefixRight};
    }

    private static function compareUnits(first:MovieClip, second:MovieClip):Number {
        return first.aabbCollider.left - second.aabbCollider.left;
    }

    private static function successRate(chance:Number):Boolean { return rng.successRate(chance); }

    private static function createHitHook():Function {
        return function():Void {
            var bullet:Object = this;
            if (bullet.hitTarget === bullet.命中对象 && bullet.hitTarget != null) HalfPierceBudgetTest.hookCalls++;
            if (bullet.issue257Stop) bullet.gotoAndPlay("消失");
            if (bullet.issue257Once) bullet.击中时触发函数 = null;
        };
    }

    private static function fire(profile:Object, direction:Number, kind:String):Object {
        var options:Array = [];
        for (var key:String in profile) options[key] = profile[key];
        var hand:String = profile.weaponSlot;
        shooter[hand + "数据"] = options;
        var bullet:Object = ShootInitCore.generateBulletProps(shooter, hand, options, {伤害类型:profile.damagetype || "物理", 魔法伤害属性:profile.magictype});
        if (kind == "normal" || kind == "pierce") {
            var prefix:String = profile.profileName == "P90" ? "" : String(bullet.子弹种类).split("-")[0] + "-";
            bullet.子弹种类 = prefix + (kind == "normal" ? "普通子弹" : "穿刺子弹");
        }
        if (kind == "miss") bullet.命中率 = -10000;
        if (kind == "modded" || kind == "stop-hook" || kind == "once-hook" || kind == "miss") {
            bullet.击中时触发函数 = createHitHook();
            bullet.issue257Stop = kind == "stop-hook";
            bullet.issue257Once = kind == "once-hook";
        }
        if (kind == "modded") {
            bullet.吸血 = 15;
            bullet.血量上限击溃 = 1;
            bullet.斩杀 = 2;
            bullet.毒 = 4;
        }
        bullet.shootX = 0;
        bullet.shootY = 125;
        bullet.shootZ = 200;
        bullet.发射间隔毫秒 = profile.interval;
        BulletFactory.prepareBulletData(bullet, shooter);
        // 仅夹具构造同武器、同素材的 0% 配对参照。生产没有模式开关。
        if (kind == "anti-control") bullet.continuationChance = 0;
        return BulletFactory.createBullet(bullet, shooter, direction > 0 ? 0 : 180);
    }

    private static function initializeNoise(seed:Number):Void {
        rng.restoreState(seed);
        pink.seed = seed;
        pink.reset();
        HalfPierceBudget.seed(seed);
    }

    private static function prepareNativeFlight():Void {
        ChainVisualBridge.configure({version:1,mode:"native",maxUnits:15360,
            styles:[{gunChainUnitLinkage:"单元体-加强普通子弹"}],
            gunChainPrefixes:["横向联弹","横向机枪联弹","横向手枪联弹","纵向联弹","纵向机枪联弹","纵向手枪联弹"]});
        nativeFlight = true;
    }

    private static function cleanRun(units:Array):Void {
        for (var index:Number = 0; index < units.length; index++) {
            var unit:MovieClip = units[index];
            unit.dispatcher.destroy();
            unit.removeMovieClip();
        }
        makeCache([]);
        BulletQueueProcessor.reset();
        ChainUnitManager.resetAll();
        ChainUnitManager.getLayer().onEnterFrame = null;
    }

    private static function checkConfiguredTier(attribute:Object, name:String):Void {
        var raw = attribute.continuationChance;
        if (raw !== undefined) {
            check(typeof raw == "number" && raw == AttributeLoader.parseContinuationChance(raw), "configured continuation tier " + name);
        }
    }

    private static function verifySegmentSequence():Void {
        // 旧版固定种子向量。每行依次为档位、16 次单段结果、33/65 段结果、随后 32 次单发的低位。
        var cases:Array = [
            [0,   0x0000,  0,  0, 0xE742F9CC],
            [25,  0x90CA,  6, 13, 0x4D7CCEED],
            [50,  0xE742, 14, 35, 0x3981E26B],
            [75,  0xF9FA, 25, 55, 0x4D7CCEED],
            [100, 0xFFFF, 33, 65, 0xE742F9CC]
        ];
        for (var i:Number = 0; i < cases.length; i++) {
            var row:Array = cases[i], rate:Number = row[0];
            HalfPierceBudget.seed(0x13579BDF);
            var first:Number = 0, following:Number = 0;
            for (var j:Number = 0; j < 16; j++) first = (first << 1) | HalfPierceBudget.sample(1,rate);
            var group33:Number = HalfPierceBudget.sample(33,rate);
            var group65:Number = HalfPierceBudget.sample(65,rate);
            for (j = 0; j < 32; j++) following = (following << 1) | (HalfPierceBudget.rollSingle(50) ? 1 : 0);
            check(first == row[1] && group33 == row[2] && group65 == row[3] && following == (row[4] | 0),
                "one segment, final partial word and subsequent RNG at " + rate);
        }
    }

    private static function verifyBudget():Void {
        HalfPierceBudget.seed(1);
        check(HalfPierceBudget.sample(0, 50) == 0, "zero first hits draw nothing");
        check(HalfPierceBudget.sample(32, 50) == 4, "all 32 bits, fixed seed");
        HalfPierceBudget.seed(1);
        check(HalfPierceBudget.sample(33, 50) == 5, "partial second word, fixed seed");
        var parser:AttributeLoader = new AttributeLoader();
        var invalid:Array = [-1,1,24,26,37,49,51,74,76,99,101,7.5,"bad","75%",true,[25]];
        for (var i:Number = 0; i < invalid.length; i++)
            check(parser.load({attribute:{continuationChance:invalid[i]}}).continuationChance === 0, "inactive value " + invalid[i]);
        HalfPierceBudget.seed(1);
        check(!HalfPierceBudget.rollSingle(37) && HalfPierceBudget.sample(1,37) == 0
            && HalfPierceBudget.sample(33,37) == 0 && HalfPierceBudget.sample(32,50) == 4, "off-tier input consumes no draws");
        verifySegmentSequence();
        var rates:Array = [0,25,50,75,100];
        for (i = 0; i < rates.length; i++) {
            var rate:Number = rates[i], sum:Number = 0, singles:Number = 0;
            check(parser.load({attribute:{continuationChance:rate}}).continuationChance === rate
                && AttributeLoader.parseContinuationChance(String(rate)) === rate, "accepted continuation tier " + rate);
            HalfPierceBudget.seed(289);
            for (var trial:Number = 0; trial < 1024; trial++) {
                var n:Number = HalfPierceBudget.sample(33, rate);
                if (HalfPierceBudget.rollSingle(rate)) singles++;
                sum += n;
            }
            check(Math.abs(sum-33792*rate/100) < 425 && Math.abs(singles-1024*rate/100) < 62, "single and group distribution at " + rate);
        }
        HalfPierceBudget.seed(1);
        check(HalfPierceBudget.sample(33,100) == 33 && HalfPierceBudget.rollSingle(100)
            && !HalfPierceBudget.rollSingle(0) && HalfPierceBudget.sample(32,50) == 4, "endpoints consume no continuation draws");
        var total:Number = 0;
        var kinds:Object = {};
        for (var loop:Number = 0; loop < 2048; loop++) {
            var drawn:Number = HalfPierceBudget.sample(6, 50);
            total += drawn;
            kinds[drawn] = true;
        }
        check(total > 5880 && total < 6408 && kinds[0] && kinds[6] && kinds[3],
            "50 percent mean and partial group continuation");
        var front:Object = {};
        var rear:Object = {};
        var deep:Object = {};
        var budget:HalfPierceBudget = new HalfPierceBudget(0, 50, false);
        HalfPierceBudget.seed(1);
        check(budget.settle(front, 5, 1, 0) == 1 && budget.lockedCarry(front) == 1, "first grants one protected credit");
        check(budget.settle(rear, 5, 4, 4) == 0 && budget.carry == 1, "full MISS burns first segments only");
        check(budget.settle(deep, 1, 1, 0) == 0 && budget.carry == 0, "second settlement cannot grant a third");
        HalfPierceBudget.seed(1);
        budget.settle(front, 3, 1, 0);
        HalfPierceBudget.seed(1);
        budget.settle(rear, 3, 1, 0);
        check(budget.carry == 2 && budget.lockedCarry(front) == 1 && budget.lockedCarry(rear) == 1,
            "independent source budgets");
        check(budget.settle(front, 2, 1, 0) == 0 && budget.lockedCarry(front) == 1
            && budget.lockedCarry(rear) == 0, "spend only the other target's credit");
        budget.trimTo(0);
        check(budget.carry == 0, "terrain retirement cannot leave credits alive");
    }

    private static function runScene(family:Number, sample:Number, count:Number, situation:String):Object {
        var direction:Number = situation == "left" ? -1 : 1;
        _root.collisionLayer = world.mapMask;
        initializeNoise(12792 + sample * 2801);
        var single:Boolean = String(guns[family].bullet).indexOf("联弹-") < 0;
        var visualAudit:Boolean = family == 1 && situation == "close";
        // 9762 的前三次抽样低五位为零，覆盖近距打空而补弹尚未完成的间隙。
        if (count == 1) HalfPierceBudget.seed(visualAudit ? 9762 : 1);
        hookCalls = 0;
        shooter.暴击率 = situation == "modded" ? 100 : 0;
        shooter.hp = 100;
        shooter.hp满血值 = 100000;
        var savedDodgeMax:Number = DodgeHandler.DODGE_SYSTEM_MAX;
        if (_root.collisionLayer == null) {
            world.mapMask = world.createEmptyMovieClip("mapMask", world.getNextHighestDepth());
            _root.collisionLayer = world.mapMask;
        }
        var map:MovieClip = world.mapMask;
        map.clear();
        if (situation == "wall") {
            map.beginFill(0x555555);
            map.moveTo(152,194); map.lineTo(242,194); map.lineTo(242,207);
            map.lineTo(152,207); map.lineTo(152,194); map.endFill();
        }
        var hp:Number = 10000000;
        var frontX:Number = family == 1 ? 125 : 93;
        if (family >= 3) frontX = guns[family].velocity * 2;
        var rewardCase:Boolean = situation == "lynx-double" || situation == "lynx-cap";
        if (rewardCase) hp = 1;
        if (situation == "close") frontX = 24;
        var targets:Array = [];
        var front:MovieClip, rear:MovieClip, deep:MovieClip, wrong:MovieClip;
        if (situation != "empty") {
            front = newTarget("front", direction * frontX,200,family >= 3 ? 90 : (visualAudit ? 76 : 40),hp,situation == "shield");
            targets.push(front);
            if (situation == "lynx-cap") front.魔法抗性.首领 = 0;
            if (situation == "miss") {
                front.等级 = 300;
                front.重量 = 0;
                front.躲闪率 = 0.02;
                DodgeHandler.DODGE_SYSTEM_MAX = 100;
            }
            if (situation == "null") front.无敌 = true;
        }
        if (situation != "empty" && situation != "single" && situation != "close" && situation != "miss"
                && situation != "null" && situation != "late-entry") {
            var rearX:Number = (situation == "wall" || family == 1) ? 262 : 168;
            if (situation == "left") rearX = frontX + 40;
            if (family >= 3) rearX = guns[family].velocity * 4;
            rear = newTarget("rear", direction * rearX,200,family >= 3 ? 90 : 38,hp,false);
            if (situation == "lynx-double") rear.魔法抗性.精英 = 0;
            if (situation == "lynx-cap") rear.魔法抗性.首领 = 0;
            deep = newTarget("deep", direction * (situation == "range" ? 1100 : 420),200,38,hp,false);
            // 反器材弹各有自己的 Z 判定宽度。负对照靶必须在该武器的行外。
            var otherZ:Number = family >= 3 ? 200 + Number(guns[family].bulletsize) + 10 : 295;
            wrong = newTarget("wrongRow",direction * 190,otherZ,180,hp,false);
            targets.push(rear, deep, wrong);
            if (situation == "dense") {
                for (var i:Number = 0; i < 12; i++) {
                    targets.push(newTarget("extra" + i, 465 + 24*i,200 + ((i & 1) * 20),22,hp,false));
                }
            }
        }
        makeCache(targets);
        events = count == 1 ? [] : null;
        var projectiles:Array = [];
        var liveSingles:Array = single ? [] : null;
        var samples:Array = [];
        var launched:Number = 0;
        var first:Object, group:ChainGroup;
        var selected:Number = 0;
        var maxBorn:Number = 0;
        var maxCarry:Number = 0;
        var asset:Boolean = false;
        var loadout:String;
        var finishTick:Number = 0;
        var spentMs:Number = 0;
        var visualRetired:Number = 0;
        var visualOk:Boolean = true;
        var sawEmptyVisual:Boolean = false;
        var magazine:Boolean = family == 4;
        // EnhancedCooldownWheel 按每个射击周期向上取整；135 ms 在 30 FPS 下为五帧。
        var intervalFrames:Number = magazine ? Math.ceil(guns[family].interval * _root.帧计时器.帧率 / 1000) : 0;
        var steps:Number = magazine ? (count-1)*intervalFrames + 36 : 86;
        for (var step:Number = 0; step < steps; step++) {
            if (situation == "late-entry" && step == (family == 0 ? 4 : 8)) {
                rear = newTarget("rear", family == 0 ? 168 : 420, 200, 50, hp, false);
                targets.push(rear);
                makeCache(targets);
            }
            // 模拟连续射击后的稳定区间，覆盖弹群活跃、空窗、补弹和自然退场。
            if (magazine || step < 36) {
                var goal:Number = magazine ? Math.min(count,1+Math.floor(step/intervalFrames))
                    : ((step + 1) * count / 36) | 0;
                if (count == 1) goal = 1;
                while (launched < goal) {
                    var bullet:Object = fire(guns[family], direction, situation);
                    if (rewardCase) killedBy = bullet;
                    group = bullet.chainGroup;
                    if (group.halfPierce != null || bullet.__halfPierceSingle !== undefined) selected++;
                    projectiles[launched++] = bullet;
                    if (single) liveSingles[liveSingles.length] = bullet;
                    if (first == null) {
                        first = bullet;
                        if (family >= 3) loadout = bullet.子弹种类 + "/" + bullet.baseAsset + "/" + bullet.flags
                            + "/" + bullet.continuationChance + "/" + bullet.__halfPierceSingle;
                        asset = single ? bullet.area != null && bullet._parent != undefined
                            : group.单元体列表.length > 0
                                && (group.nativeGroupOwned || group.单元体列表[0].mc._parent != undefined);
                    }
                }
            }
            _root.帧计时器.当前帧数++;
            var stamp:Number = getTimer();
            ChainUnitManager.tick();
            if (single) {
                for (var flying:Number = liveSingles.length - 1; flying >= 0; flying--) {
                    bullet = liveSingles[flying];
                    if (bullet._parent != undefined && bullet._currentframe == 1 && bullet.aabbCollider != null) {
                        bullet.onEnterFrame();
                    } else {
                        var last:Number = liveSingles.length - 1;
                        if (flying < last) liveSingles[flying] = liveSingles[last];
                        liveSingles.length = last;
                    }
                }
            } else if (first != null && !first.__chainDead) {
                group = first.chainGroup;
                if (group.count > maxBorn) maxBorn = group.count;
            }
            BulletQueueProcessor.processQueue();
            var elapsed:Number = getTimer() - stamp;
            samples[step] = elapsed;
            spentMs += elapsed;
            if (!single && first != null && !first.__chainDead) {
                group = first.chainGroup;
                if (group.halfPierce.carry > maxCarry) maxCarry = group.halfPierce.carry;
                if (visualAudit && group.halfPierce != null) {
                    var hidden:Number = group.halfPierce.visualStart;
                    var list:Array = group.单元体列表;
                    visualRetired = Math.max(visualRetired, hidden);
                    visualOk = visualOk && group.count == list.length && list.length - hidden == first.霰弹值;
                    for (var member:Number = 0; member < list.length; member++) {
                        visualOk = visualOk && (member < hidden ? list[member].nativeLive === false && list[member].mc == null
                            : list[member].nativeLive === true && (nativeFlight || list[member].mc._parent != undefined));
                    }
                    if (nativeFlight) {
                        var packet:String = ChainVisualBridge.flush();
                        var carried:Boolean = packet != null && packet.indexOf("G," + group.nativeGroupId + ",") >= 0;
                        visualOk = visualOk && (carried == (hidden < list.length));
                        if (!carried && hidden == list.length && group.count < group.halfPierce.birthTotal) sawEmptyVisual = true;
                    }
                }
            } else if (first != null && finishTick == 0
                    && (!single || first._parent == undefined || first._currentframe != 1)) finishTick = step + 1;
        }
        var result:Object = {selected:selected, asset:asset, loadout:loadout, intervalFrames:intervalFrames, born:maxBorn, carry:maxCarry,
            front:front.issue257Effective|0, rear:rear.issue257Effective|0, deep:deep.issue257Effective|0, wrong:wrong.issue257Effective|0,
            frontHP:front == null ? 0 : (hp - front.hp), rearHP:rear == null ? 0 : (hp - rear.hp),
            shieldLoss:situation == "shield" ? (100000 - front.shield.getCapacity()) : 0,
            remaining:ChainUnitManager.getActiveGroupCount(), ticks:finishTick, ms:spentMs, frames:samples, events:events,
            visualRetired:visualRetired, visualOk:visualOk, sawEmptyVisual:sawEmptyVisual,
            hookCalls:hookCalls, healed:shooter.hp - 100, reducedMax:hp - front.hp满血值};
        for (var index:Number = 0; index < projectiles.length; index++) {
            bullet = projectiles[index];
            if (single ? bullet._parent != undefined : !bullet.__chainDead) {
                if (single && situation == "left" && !nativeFlight && bullet._currentframe != 1) {
                    pendingVanishingName = bullet._name;
                    pendingVanishingFrames = 0;
                } else {
                    bullet.removeMovieClip();
                }
            }
        }
        DodgeHandler.DODGE_SYSTEM_MAX = savedDodgeMax;
        shooter.暴击率 = 0;
        cleanRun(targets);
        return result;
    }

    private static function writeResult(family:Number, situation:String, sample:Number, result:Object):Void {
        var row:String = "[I257_ROW] gun=" + guns[family].profileName + " scene=" + situation + " pair=" + sample
            + " mode=50 view=" + (nativeFlight ? "native" : "flash") + " selected=" + result.selected
            + " born=" + result.born + " carry=" + result.carry
            + " front=" + result.front + " rear=" + result.rear + " deep=" + result.deep + " wrong=" + result.wrong
            + " frontHP=" + result.frontHP + " rearHP=" + result.rearHP + " shieldLoss=" + result.shieldLoss
            + " remaining=" + result.remaining + " ticks=" + result.ticks + " ms=" + result.ms
            + " frames=" + result.frames.join(",");
        traces[traces.length] = row;
        trace(row);
    }

    private static function verifyScene(family:Number, name:String, result:Object, count:Number):Void {
        var label:String = guns[family].profileName + " " + name;
        check(result.asset && result.wrong == 0, label + " real assets, no wrong lane");
        var eligible:Boolean = name != "normal" && name != "pierce";
        check(result.selected == (eligible ? count : 0), label + " default behavior, selected=" + result.selected);
        if (!eligible || count != 1) return;
        check(result.remaining == 0 && result.ticks > 0, label + " retires");
        if (name == "close") {
            check(result.born == guns[family].split, label + " no removal of upcoming births");
            check(result.front <= result.born, label + " no repeated second hit on its source");
            check(result.visualOk && result.visualRetired > 0, label + " visual budget only; all geometry retained");
            if (nativeFlight) check(result.sawEmptyVisual, label + " native packet omits temporarily empty display group");
        }
        if (name == "wall") check(result.front > 0 && result.rear == 0 && result.deep == 0, label + " wall");
        if (name == "range") check(result.deep == 0, label + " range");
        if (name == "null" || name == "miss") check(result.front == 0 && result.carry == 0 && result.hookCalls == 0,
            label + " no credit or callback from ineffective hit");
        if (name == "shield") check(result.front > 0 && result.frontHP == 0 && result.shieldLoss > 0, label + " shield settlement");
        if (name == "left") check(result.front > 0 && result.events[0] == "front", label + " front first for left travel");
        if (family == 2) {
            check(result.front <= 1 && result.front + result.rear + result.deep <= 2, label + " one sequel at most");
            if (name == "shield") check(result.rear == 1, label + " shield hit grants standalone continuation");
        }
    }

    private static function verifyCompatibility():Void {
        for (var family:Number = 0; family < 3; family++) {
            var label:String = guns[family].profileName;
            var mods:Object = runScene(family, 57, 1, "modded");
            check(mods.selected == 1 && mods.front > 0 && mods.rear > 0, label + " modified loadout can penetrate");
            check(mods.healed > 0 && mods.reducedMax > 0 && mods.hookCalls == mods.events.length,
                label + " native effect handlers and callback receiver");
            var once:Object = runScene(family, 57, 1, "once-hook");
            check(once.selected == 1 && once.rear > 0 && once.hookCalls == 1, label + " self-clearing callback fires once");
            var stopping:Object = runScene(family, 57, 1, "stop-hook");
            check(stopping.selected == 1 && stopping.front > 0 && stopping.rear == 0 && stopping.hookCalls == 1,
                label + " callback-driven disappearance owns lifetime");
            var appearing:Object = runScene(family, 57, 1, "late-entry");
            check(appearing.front > 0 && appearing.rear > 0, label + " continuation finds a target added after an empty window");
        }
        var row:String = "[I257_COMPAT] view=" + (nativeFlight ? "native" : "flash") + " real SPAS12 XM556 P90";
        trace(row);
        traces[traces.length] = row;
    }

    private static function registerKill(target:MovieClip, bullet:Object):Void {
        killEvents.push((bullet === killedBy ? "" : "wrong:") + target._name);
    }

    private static function registerAmmo(owner:Object, state:String, rounds:Number):Void {
        magazineEvents.push(rounds);
    }

    private static function verifyLynx():Void {
        var lynx:Object = guns[3];
        shooter.长枪属性 = lynx;
        shooter.长枪弹匣容量 = lynx.capacity;
        _root.装备生命周期函数.GM6_LYNX初始化({自机:shooter}, lynxParams);
        shooter.dispatcher.subscribe("enemyKilled", registerKill);
        shooter.dispatcher.subscribe("updateBullet", registerAmmo);
        for (var i:Number = 0; i < 2; i++) {
            shooter.长枪 = {value:{shot:0}};
            WeaponAmmoRuntime.ensure(shooter,"长枪");
            if (i == 1) WeaponAmmoRuntime.addReward(shooter,"长枪",4);
            WeaponAmmoRuntime.consume(shooter,"长枪");
            var value:Object = shooter.长枪.value;
            var afterShot:Number = lynx.capacity - value.shot;
            killEvents = [];
            magazineEvents = [];
            var result:Object = runScene(3, 70+i, 1, i == 0 ? "lynx-double" : "lynx-cap");
            var expected:String = i == 0 ? "5,8" : "10,10";
            check(result.asset && result.selected == 1 && result.front == 1 && result.rear == 1 && result.deep == 0,
                "GM6 single projectile reaches two different targets");
            check(killEvents.join(",") == "front,rear" && magazineEvents.join(",") == expected
                && afterShot == (i == 0 ? 4 : 8) && lynx.capacity-value.shot == (i == 0 ? 8 : 10)
                && value.ammoState.reward == (i == 0 ? 3 : 5), "GM6 two real kill rewards, ammo and cap " + i);
            var row:String = "[I257_GM6] case=" + i + " afterShot=" + afterShot + " kills=" + killEvents
                + " ammo=" + magazineEvents + " reward=" + value.ammoState.reward + " deep=" + result.deep;
            traces.push(row); trace(row);
        }
        shooter.dispatcher.unsubscribe("enemyKilled", registerKill);
        shooter.dispatcher.unsubscribe("updateBullet", registerAmmo);
        t181Totals = {controlFront:0, controlRear:0, controlDamage:0, front:0, rear:0, deep:0, frontDamage:0, rearDamage:0};
    }

    // 每次用真实弹容和 135 ms 基础间隔模拟一匣，下一帧才开始下一次配对。
    private static function verifyT181Magazine(pair:Number):Void {
        var n:Number = guns[4].capacity;
        var reference:Object = runScene(4,80+pair,n,"anti-control");
        var candidate:Object = runScene(4,80+pair,n,"anti-live");
        check(n == 45 && guns[4].interval == 135 && reference.asset && candidate.asset && candidate.intervalFrames == 5
            && reference.selected == 0 && candidate.selected == n && reference.wrong == 0 && candidate.wrong == 0,
            "T181C XML magazine and paired real assets " + pair);
        var detail:String = "[I257_T181C_PAIR] pair=" + pair + " shots=" + n + " interval=" + guns[4].interval
            + " control=" + reference.loadout + " live=" + candidate.loadout + " asset=" + reference.asset + "/" + candidate.asset
            + " selected=" + reference.selected + "/" + candidate.selected + " front=" + reference.front + "/" + candidate.front
            + " rear=" + reference.rear + "/" + candidate.rear + " wrong=" + reference.wrong + "/" + candidate.wrong;
        traces.push(detail); trace(detail);
        var v:Object = t181Totals;
        v.controlFront += reference.front;
        v.controlRear += reference.rear;
        v.controlDamage += reference.frontHP;
        v.front += candidate.front;
        v.rear += candidate.rear;
        v.deep += candidate.deep;
        v.frontDamage += candidate.frontHP;
        v.rearDamage += candidate.rearHP;
        if (pair != 11) return;
        check(v.controlFront == 540 && v.front == v.controlFront && v.controlRear == 0 && v.rear > 359 && v.rear < 451
            && v.rearDamage > 0 && v.deep == 0, "T181C first hits and rear damage at 75%");
        var row:String = "[I257_T181C] shots=540 controlFront=" + v.controlFront + " controlRear=" + v.controlRear
            + " front=" + v.front + " rear=" + v.rear + " deep=" + v.deep + " frontDamage=" + v.frontDamage + " rearDamage=" + v.rearDamage + " controlDamage=" + v.controlDamage;
        traces.push(row); trace(row);
    }

    private static function verifyAdditionalAmmo(index:Number):Void {
        var family:Number = 5 + index;
        var zone:Number = [1, 0, 0, 2][index];
        var expected:Number = [25, 25, 25, 50][index];
        var gun:Object = guns[family];
        world.子弹区域 = assetZones[zone];
        var control:Object = runScene(family, 100 + index, 64, "anti-control");
        var test:Object = runScene(family, 100 + index, 64, "live");
        world.子弹区域 = world;
        var tier:Number = BulletInitializer.getAttributeData(gun.bullet).continuationChance;
        check(tier == expected && control.asset && test.asset && control.selected == 0 && test.selected == 64,
            gun.profileName + " real linkage and configured tier");
        check(control.front > 0 && test.front == control.front && control.rear == 0 && test.rear > 0
            && test.rearHP > 0 && test.deep == 0 && test.wrong == 0, gun.profileName + " second target only");
        if (index == 2) check(gun.split == 3 && BulletInitializer.getAttributeData("铁枪磁轨弹").continuationChance === undefined,
            "G111 three-part burst and separate charged shot");
        var detail:String = "[I257_AMMO] gun=" + gun.profileName + " bullet=" + gun.bullet + " tier=" + tier
            + " selected=" + control.selected + "/" + test.selected + " asset=" + control.asset + "/" + test.asset
            + " front=" + control.front + "/" + test.front + " rear=" + control.rear + "/" + test.rear
            + " damage=" + test.rearHP + " deep=" + test.deep + " wrong=" + test.wrong;
        traces.push(detail); trace(detail);
    }

    private static function advance():Void {
        if (done) return;
        if (!ready) {
            if (++waitFrames > 450) failAndFinish("XML/assets timed out");
            return;
        }
        try {
            if (pendingVanishingName != null) {
                var pending:MovieClip = world[pendingVanishingName];
                if (pending._parent != undefined && ++pendingVanishingFrames < 3) return;
                check(pending._parent == undefined, "P90 disappearance frame actually releases MovieClip");
                if (pending._parent != undefined) pending.removeMovieClip();
                pendingVanishingName = null;
            }
            var performanceScenes:Array = ["empty", "single", "dense"];
            var pairs:Number = 5;
            var perFamily:Number = pairs * performanceScenes.length;
            var performanceCount:Number = perFamily * 3;
            var edgeScenes:Array = ["shield","left","wall","range","miss","null","normal","pierce"];
            var edgeCount:Number = edgeScenes.length * 3 + 1;
            var scene:String, family:Number, pair:Number, count:Number;
            if (runIndex == 0) verifyCompatibility();
            var laneIndex:Number = runIndex % (performanceCount + edgeCount);
            var extraCase:Number = runIndex - 2 * (performanceCount + edgeCount);
            if (extraCase >= 0) {
                if (extraCase == 0) verifyLynx();
                else if (extraCase <= 12) verifyT181Magazine(extraCase - 1);
                else if (extraCase <= 16) verifyAdditionalAmmo(extraCase - 13);
                else { finish(); return; }
                runIndex++;
                return;
            }
            if (runIndex >= performanceCount + edgeCount && !nativeFlight) {
                prepareNativeFlight();
                verifyCompatibility();
            }
            if (laneIndex < performanceCount) {
                family = (laneIndex / perFamily) | 0;
                var offset:Number = laneIndex % perFamily;
                pair = (offset / performanceScenes.length) | 0;
                scene = performanceScenes[(offset + pair) % performanceScenes.length];
                count = 108;
            } else {
                var edgeIndex:Number = laneIndex - performanceCount;
                var isClose:Boolean = edgeIndex == edgeScenes.length * 3;
                family = isClose ? 1 : ((edgeIndex / edgeScenes.length) | 0);
                scene = isClose ? "close" : edgeScenes[edgeIndex % edgeScenes.length];
                pair = 38 + edgeIndex;
                count = 1;
            }
            var result:Object = runScene(family, pair, count, scene);
            writeResult(family, scene, pair, result);
            verifyScene(family, scene, result, count);
            runIndex++;
        } catch (error:Error) {
            failAndFinish("case " + runIndex + ": " + error);
        }
    }

    private static function failAndFinish(label:String):Void {
        check(false,label);
        finish();
    }

    private static function finish():Void {
        if (done) return;
        done = true;
        ChainVisualBridge.disconnect();
        if (driver != null) driver.removeMovieClip();
        if (loader != null) loader.removeListener(listener);
        trace("HalfPierceBudgetTest Tests Passed: " + passed);
        trace("HalfPierceBudgetTest Tests Failed: " + failed);
        if (String(_root._url).indexOf("http://127.0.0.1:") == 0 &&
            _root._url.indexOf("/issue257-player20/") >= 0 &&
            typeof _root.issue257ReplayToken == "string" && _root.issue257ReplayToken.length == 32) {
            var reply:LoadVars = new LoadVars();
            var result:LoadVars = new LoadVars();
            result.token = _root.issue257ReplayToken;
            result.report = System.capabilities.version + "\nHalfPierceBudgetTest Tests Passed: " + passed +
                "\nHalfPierceBudgetTest Tests Failed: " + failed + "\n" + traces.join("\n");
            result.sendAndLoad("../receipt",reply,"POST");
        }
        _root.issue257BattleComplete();
    }
}
