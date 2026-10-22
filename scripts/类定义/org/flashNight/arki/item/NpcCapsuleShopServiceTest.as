import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;

/** 真实 AVM1 资格/回收夹具；存档、网络与交易保存沿既有 NPC suite 的内存替身。 */
class org.flashNight.arki.item.NpcCapsuleShopServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var world:MovieClip;
    private static var hero:MovieClip;
    private static var sequence:Number;
    private static var oldWorld;
    private static var oldControl;
    private static var oldSlot;
    private static var oldServer;
    private static var lateProjectile:MovieClip;
    private static var lastProjectile:MovieClip;
    private static var lateId:String;
    private static var lateStart:Number;
    public static var lastWire:String;
    private static var SHOP:String = "迷之盔甲君";
    private static var CAPSULE:String = "谜之胶囊";

    private static function check(value:Boolean, label:String):Void {
        if (value) passed++;
        else { failed++; trace("[NpcCapsuleTest] FAIL " + label); }
    }
    private static function newWorld():Void {
        if (typeof _root.__capsuleFixtureWorld == "movieclip") _root.__capsuleFixtureWorld.removeMovieClip();
        world = _root.createEmptyMovieClip("__capsuleFixtureWorld", _root.getNextHighestDepth());
        world.createEmptyMovieClip("子弹区域", 1);
        hero = world.createEmptyMovieClip("capsuleHero", 2);
        hero.手雷 = CAPSULE;
        hero.是否为敌人 = false;
        _root.gameworld = world;
        _root.控制目标 = hero._name;
        sequence = 0;
    }
    private static function stock(value):Void {
        _root.物品栏.装备栏 = new EquipmentInventory({手雷:new BaseItem(CAPSULE, value, 0)});
    }
    private static function projectile(name:String):MovieClip {
        var clip:MovieClip = world.子弹区域.createEmptyMovieClip(name, ++sequence);
        clip.子弹种类 = CAPSULE;
        clip.发射者 = hero._name;
        return clip;
    }
    private static function readId():String {
        return String(new LiteJSON().parse(lastWire).initData.capsuleOpenId);
    }
    private static function openFresh():String {
        stock(3);
        var clip:MovieClip = projectile("capsule" + sequence);
        lastProjectile = clip;
        var token:Object = NpcCapsuleShopService.registerShot(hero, clip);
        _root.物品栏.装备栏.addValue("手雷", -1);
        if (!NpcCapsuleShopService.confirmShot(token) || !NpcCapsuleShopService.openProjectile(clip)) return "";
        return readId();
    }
    private static function request(openId:String, owner:String):Object {
        return {shopId:SHOP, capsuleOpenId:openId, capsulePanelInstanceId:owner};
    }
    private static function service():Object { return _root.UI系统.NPC商店WebView; }

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        oldWorld = _root.gameworld; oldControl = _root.控制目标;
        oldSlot = _root.savePath; oldServer = _root.server;
        _root.savePath = "cf7_agent_capsule_fixture";
        _root._saveExt = {};
        _root.主角被动技能.口才 = {启用:false,等级:0};
        ItemUtil.itemDataDict[CAPSULE] = {name:CAPSULE, displayname:CAPSULE,
            type:"消耗品", use:"手雷", price:8000, data:{bullet:CAPSULE}};
        _root.shops[SHOP] = _root.shops["测试商店"];
        _root.server = {};
        _root.server.sendSocketMessage = function(payload:String):Boolean {
            org.flashNight.arki.item.NpcCapsuleShopServiceTest.lastWire = payload;
            return true;
        };
        NpcShopAccessFixture.install();
        NpcShopAccessFixture.deny(SHOP, true);
        _root.暂停 = false;
        newWorld();
        testConsumptionAndOpaqueIdentity();
        testQualificationAndTransactions();
        testDeliveryOutcomeBoundary();
        testContextAndRealMovieClipReuse();
        prepareLateBoundary();
    }

    private static function testConsumptionAndOpaqueIdentity():Void {
        stock(3);
        var clip:MovieClip = projectile("real");
        var token:Object = NpcCapsuleShopService.registerShot(hero, clip);
        check(token != null, "real equipped capsule registers actual projectile");
        token.state = "armed";
        check(!NpcCapsuleShopService.openProjectile(clip), "caller mutation cannot arm private record");
        check(!NpcCapsuleShopService.confirmShot(token), "no stock decrement is not a receipt");
        var second:MovieClip = projectile("double");
        check(NpcCapsuleShopService.registerShot(hero, second) == null, "same equipment version cannot fund two projectiles");
        check(!NpcCapsuleShopService.confirmShot({state:"armed"}), "forged object cannot confirm");
        _root.物品栏.装备栏.addValue("手雷", -1);
        check(NpcCapsuleShopService.confirmShot(token), "exact one-item decrement confirms");
        check(!NpcCapsuleShopService.confirmShot(token), "consumption confirmation is one-shot");
        check(NpcCapsuleShopService.openProjectile(clip), "confirmed landing opens once");
        check(!NpcCapsuleShopService.openProjectile(clip), "duplicate landing has no grant");
        check(!NpcShopAccessService.canAccess(SHOP), "capsule does not grant ordinary remote navigation");
        check(!_root.gameCommands["openNpcShop"]({shopId:SHOP,source:"capsule"}), "caller source cannot bypass remote progress");
        var id:String = readId();
        check(!NpcCapsuleShopService.authorize(SHOP,id,"owner.A",false), "preview cannot bind unopened owner");
        check(NpcCapsuleShopService.authorize(SHOP,id,"owner.A",true), "first snapshot binds exact owner");
        check(!NpcCapsuleShopService.authorize(SHOP,id,"owner.B",true), "new owner cannot reuse old opening");
        check(!NpcCapsuleShopService.authorize("书中-迷之盔甲君",id,"owner.A",true), "grant is fixed to ordinary capsule merchant");
        check(!NpcCapsuleShopService.retire(id,"owner.B"), "foreign close cannot retire current owner");
        check(NpcCapsuleShopService.authorize(SHOP,id,"owner.A",false), "foreign close leaves exact owner active");
        check(NpcCapsuleShopService.retire(id,"owner.A"), "exact close retires grant");
        check(!NpcCapsuleShopService.authorize(SHOP,id,"owner.A",true), "closed grant cannot bind again");
        var invalid:Array = [0,-1,1.5,NaN,Infinity,"3"];
        for (var i:Number = 0; i < invalid.length; i++) {
            stock(invalid[i]);
            check(NpcCapsuleShopService.registerShot(hero,projectile("bad" + i)) == null, "invalid quantity " + i);
        }
        stock(1);
        clip = projectile("last");
        token = NpcCapsuleShopService.registerShot(hero,clip);
        _root.物品栏.装备栏.addValue("手雷",-1);
        check(NpcCapsuleShopService.confirmShot(token), "last capsule removal proves two-step equipment revision");
        check(NpcCapsuleShopService.openProjectile(clip), "last owned capsule still opens service");
        id = readId();
        NpcCapsuleShopService.retire(id,"owner.last");
        stock(3);
        clip = projectile("wrong.quantity");
        token = NpcCapsuleShopService.registerShot(hero,clip);
        _root.物品栏.装备栏.addValue("手雷",-2);
        check(!NpcCapsuleShopService.confirmShot(token), "over-consumption cannot masquerade as exact receipt");
        check(!NpcCapsuleShopService.openProjectile(clip), "rejected receipt never opens");
    }

    private static function testQualificationAndTransactions():Void {
        var id:String = openFresh();
        check(id != "", "fresh valid use produces private opening");
        _root.金钱 = 5000;
        _root.物品栏.背包.setItems({});
        var params:Object = request(id,"owner.trade");
        var snapshot:Object = service().execute("snapshot",params);
        check(snapshot.success === true, "capsule qualification reaches production snapshot");
        params.purchases = [{catalogIndex:0,quantity:1}]; params.sales = [];
        var preview:Object = service().execute("tradePreview",params);
        check(preview.success === true && preview.tradeToken != undefined, "capsule qualification reaches production quote");
        var commitParams:Object = request(id,"owner.trade"); commitParams.expectedTradeToken = preview.tradeToken;
        NpcCapsuleShopService.retire(id,"owner.trade");
        var denied:Object = service().execute("tradeCommit",commitParams);
        check(denied.error == "access_denied" && _root.金钱 == 5000,
            "retired qualification rejects at first-write boundary");
        id = openFresh();
        params = request(id,"owner.trade.next");
        snapshot = service().execute("snapshot",params);
        check(snapshot.success === true, "new capsule resets snapshot session identity");
        params.purchases = [{catalogIndex:0,quantity:1}]; params.sales = [];
        preview = service().execute("tradePreview",params);
        commitParams = request(id,"owner.trade.next"); commitParams.expectedTradeToken = preview.tradeToken;
        var committed:Object = service().execute("tradeCommit",commitParams);
        check(committed.success === true && _root.金钱 == 4900, "current capsule permits one real in-memory trade");
        var repeated:Object = service().execute("tradeCommit",commitParams);
        check(repeated.success !== true && _root.金钱 == 4900, "trade token replay cannot charge twice");
        check(!NpcCapsuleShopService.retire("capsule.foreign","owner.trade.next"), "old close cannot retire replacement grant");
        check(NpcCapsuleShopService.authorize(SHOP,id,"owner.trade.next",false), "replacement remains valid after old close");
        NpcCapsuleShopService.retire(id,"owner.trade.next");
    }

    private static function testDeliveryOutcomeBoundary():Void {
        var original:Function = _root.server.sendSocketMessage;
        _root.server.sendSocketMessage = function(payload:String):Boolean {
            org.flashNight.arki.item.NpcCapsuleShopServiceTest.lastWire = payload;
            return false;
        };
        check(openFresh() == "", "definite no-send is not reported as opened");
        var id:String = readId();
        check(!NpcCapsuleShopService.authorize(SHOP,id,"owner.no.send",true), "definite no-send retires pending grant");
        check(_root.物品栏.装备栏.getValue("手雷") == 2, "no-send never replays or refunds the original consumption");
        _root.server.sendSocketMessage = function(payload:String):Boolean {
            org.flashNight.arki.item.NpcCapsuleShopServiceTest.lastWire = payload;
            throw "injected_capsule_delivery_unknown";
            return false;
        };
        check(openFresh() == "", "unknown delivery is not reported as definite success");
        id = readId();
        check(NpcCapsuleShopService.authorize(SHOP,id,"owner.unknown",true), "possibly delivered exact opening can still bind once");
        check(_root.物品栏.装备栏.getValue("手雷") == 2, "unknown delivery never compensates consumption");
        check(!NpcCapsuleShopService.openProjectile(lastProjectile), "unknown opening never retransmits the consumed projectile");
        NpcCapsuleShopService.retire(id,"owner.unknown");
        _root.server.sendSocketMessage = original;
    }

    private static function testContextAndRealMovieClipReuse():Void {
        var id:String = openFresh();
        check(NpcCapsuleShopService.authorize(SHOP,id,"owner.context",true), "context grant is active before authority replacement");
        var previousOwner:Object = _root.存档系统;
        _root.存档系统 = {dirtyMark:false};
        check(!NpcCapsuleShopService.authorize(SHOP,id,"owner.context",true), "save owner replacement invalidates grant");
        _root.存档系统 = previousOwner;
        check(!NpcCapsuleShopService.authorize(SHOP,id,"owner.context",true), "restoring old owner cannot revive retired grant");
        stock(3);
        var clip:MovieClip = projectile("reuse");
        var token:Object = NpcCapsuleShopService.registerShot(hero,clip);
        _root.物品栏.装备栏.addValue("手雷",-1);
        check(NpcCapsuleShopService.confirmShot(token), "reuse witness was genuinely armed");
        clip.removeMovieClip();
        var replacement:MovieClip = world.子弹区域.createEmptyMovieClip("reuse",sequence);
        check(clip === replacement, "real AVM1 old MC reference retargets at same path");
        check(!NpcCapsuleShopService.openProjectile(clip), "independent seal rejects retargeted projectile reference");
        id = openFresh();
        NpcCapsuleShopService.authorize(SHOP,id,"owner.unit",true);
        var oldHero:MovieClip = hero;
        hero.removeMovieClip();
        hero = world.createEmptyMovieClip("capsuleHero",2); hero.手雷 = CAPSULE;
        check(oldHero === hero, "real AVM1 unit reference retargets at same path");
        check(!NpcCapsuleShopService.authorize(SHOP,id,"owner.unit",true), "unit seal rejects old service after rebind");
        newWorld();
        id = openFresh();
        NpcCapsuleShopService.authorize(SHOP,id,"owner.world",true);
        var oldScene:MovieClip = world;
        newWorld();
        check(oldScene === world, "real AVM1 world reference retargets at same path");
        check(!NpcCapsuleShopService.authorize(SHOP,id,"owner.world",true), "scene seal rejects old service after same-path rebuild");
    }

    private static function prepareLateBoundary():Void {
        lateId = openFresh();
        stock(3);
        lateProjectile = projectile("paused.flight");
        var token:Object = NpcCapsuleShopService.registerShot(hero,lateProjectile);
        _root.物品栏.装备栏.addValue("手雷",-1);
        check(NpcCapsuleShopService.confirmShot(token), "paused-flight witness is armed");
        lateStart = getTimer();
        var tick:MovieClip = _root.createEmptyMovieClip("__capsuleLateBoundary", _root.getNextHighestDepth());
        tick.onEnterFrame = function():Void {
            org.flashNight.arki.item.NpcCapsuleShopServiceTest.finishLateBoundary();
        };
    }
    public static function finishLateBoundary():Void {
        if (getTimer() - lateStart < 31000) return;
        _root.__capsuleLateBoundary.removeMovieClip();
        check(!NpcCapsuleShopService.authorize(SHOP,lateId,"owner.late",true), "late first snapshot cannot bind expired opening");
        check(NpcCapsuleShopService.openProjectile(lateProjectile), "armed projectile survives paused wall time in same scene");
        var id:String = readId();
        check(NpcCapsuleShopService.authorize(SHOP,id,"owner.resumed",true), "resumed legitimate landing binds fresh service");
        NpcCapsuleShopService.retire(id,"owner.resumed");
        NpcShopAccessFixture.restore();
        world.removeMovieClip();
        _root.gameworld = oldWorld; _root.控制目标 = oldControl;
        _root.savePath = oldSlot; _root.server = oldServer;
        trace("NpcCapsuleShopServiceTest Tests Passed: " + passed);
        trace("NpcCapsuleShopServiceTest Tests Failed: " + failed);
        _root.__capsuleTestFinished();
        delete _root.__capsuleTestFinished;
    }
}
