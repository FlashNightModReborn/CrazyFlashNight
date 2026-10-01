import org.flashNight.arki.ui.GaragePurchasePanelService;

/** 真实 MovieClip + 受控保存替身；只在独立 TestLoader 中验证购车。 */
class org.flashNight.arki.ui.GaragePurchasePanelServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] GaragePurchase: " + message); }
    }
    private static function setup():Void {
        GaragePurchasePanelService._resetForTests();
        if (_root.__garageWorld != undefined) _root.__garageWorld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("__garageWorld", 9002);
        _root.控制目标 = "garageHero";
        _root.gameworld.createEmptyMovieClip("garageHero", 1);
        _root.savePath = "u13-focused-test";
        _root.金钱 = 600000;
        _root.主角被动技能 = {驾驶:{等级:2}};
        _root.基建系统 = {infrastructure:{自行车:0,摩托车:0,越野车:0},dict:{
            自行车:{Level:[{id:0,Price:8000,Description:"自行车出行"},{id:1,Description:"地图出行：近途快旅\n材料导航：前往商店",Price:1}]},
            摩托车:{Level:[{id:0,Price:35000,Description:"摩托车出行",Skill:[{Name:"驾驶",Level:1}]},{id:1,Description:"地图出行：覆盖近途和中途\n材料导航：前往合成"}]},
            越野车:{Level:[{id:0,Price:500000,Description:"跨区域出行\n追加战备箱",Skill:[{Name:"驾驶",Level:2}]},{id:1,Description:"后勤扩容：战备箱开放后增加一页（40格）"}]}}};
        _root.__garageSaves = 0; _root.__garageFeeds = 0; _root.__garageSaveOK = true;
        _root.存档系统 = {dirtyMark:false,markDirty:function():Void { this.dirtyMark = true; },
            flushDurableNow:function(reason):Boolean {
                _root.__garageSaves++; _root.__garageSaveReason = reason;
                if (_root.__garageSaveOK) this.dirtyMark = false;
                return _root.__garageSaveOK;
            }};
        _root.记录玩家货币变化 = function(money, points, context):Void {
            _root.__garageFeeds++; _root.__garageDelta = money; _root.__garageFeedToken = context.operationId;
        };
        _root.server = {sendSocketMessage:function(value):Boolean { _root.__garageWire = value; return true; }};
    }
    private static function snapshot(id:String):Object {
        GaragePurchasePanelService.openPanel(id);
        return GaragePurchasePanelService.execute("snapshot",{v:1,vehicleId:id});
    }
    private static function commit(initial:Object, id:String):Object {
        return GaragePurchasePanelService.execute("commit",{v:1,token:initial.token,draft:{vehicleId:id}});
    }
    private static function query(initial:Object):Object {
        return GaragePurchasePanelService.execute("query",{v:1,token:initial.token});
    }
    private static function threeVehicles():Void {
        var ids:Array = ["bicycle","motorcycle","offroad"];
        var names:Array = ["自行车","摩托车","越野车"];
        var costs:Array = [8000,35000,500000];
        for (var i:Number = 0; i < ids.length; i++) {
            setup();
            var initial:Object = snapshot(ids[i]);
            check(initial.cost == costs[i] && initial.vehicleId == ids[i] && initial.requiredDrivingLevel == i, "XML quote projection " + ids[i]);
            check(initial.description == _root.基建系统.dict[names[i]].Level[1].Description, "purchased XML benefits " + ids[i]);
            check(_root.金钱 == 600000 && _root.__garageSaves == 0 && _root.__garageFeeds == 0, "open is read-only " + ids[i]);
            var result:Object = commit(initial,ids[i]);
            check(result.success && result.saved && result.phase == "applied", "purchase saved " + ids[i]);
            check(_root.金钱 == 600000-costs[i] && _root.基建系统.infrastructure[names[i]] == 1, "money and flag " + ids[i]);
            check(_root.__garageFeeds == 1 && _root.__garageDelta == -costs[i] && _root.__garageFeedToken == initial.token, "currency receipt once " + ids[i]);
            result = commit(initial,ids[i]);
            check(result.saved && _root.__garageSaves == 1 && _root.__garageFeeds == 1 && _root.金钱 == 600000-costs[i], "duplicate returns receipt " + ids[i]);
        }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        threeVehicles();
        setup(); _root.基建系统.dict.自行车.Level.pop();
        check(snapshot("bicycle").description == "自行车出行", "presentation fallback preserves valid quote");
        setup();
        check(!GaragePurchasePanelService.execute("snapshot",{v:1,vehicleId:"bicycle"}).success, "production opener required");
        check(!GaragePurchasePanelService.openPanel("tank"), "closed vehicle enum");
        check(GaragePurchasePanelService.execute("snapshot",{v:1,vehicleId:"tank"}).error == "invalid_vehicle", "invalid vehicle rejected");
        check(GaragePurchasePanelService.execute("snapshot",{v:2,vehicleId:"bicycle"}).error == "unsupported_version", "version rejected");
        var initial:Object = snapshot("bicycle");
        check(_root.__garageWire.indexOf('"vehicleId":"bicycle"') >= 0 && _root.__garageWire.indexOf('"panel":"garage"') >= 0, "real opener envelope");
        _root.金钱 = 7999;
        check(commit(initial,"bicycle").error == "insufficient_funds" && _root.金钱 == 7999 && _root.基建系统.infrastructure.自行车 == 0, "fresh balance refusal");
        setup(); initial = snapshot("motorcycle"); _root.主角被动技能.驾驶.等级 = 0;
        check(commit(initial,"motorcycle").error == "driving_required" && _root.__garageSaves == 0 && _root.金钱 == 600000, "fresh driving refusal");
        setup(); _root.主角被动技能.驾驶.等级 = 1; initial = snapshot("offroad");
        check(!initial.canPurchase && commit(initial,"offroad").error == "driving_required", "offroad needs level two");
        setup(); _root.主角被动技能 = {}; initial = snapshot("bicycle");
        check(initial.canPurchase && commit(initial,"bicycle").saved, "bicycle needs no license");
        setup(); initial = snapshot("bicycle"); _root.基建系统.infrastructure.自行车 = 1;
        var result:Object = commit(initial,"bicycle");
        check(result.phase == "owned" && !result.changed && _root.金钱 == 600000 && _root.__garageSaves == 0, "fresh owned check prevents charge");
        check(query(initial).phase == "owned" && _root.__garageFeeds == 0, "owned receipt query");
        setup(); _root.基建系统.infrastructure.越野车 = 1; initial = snapshot("offroad");
        check(initial.phase == "owned" && !initial.canPurchase && !initial.changed, "already-owned snapshot");
        setup(); initial = snapshot("bicycle");
        check(commit(initial,"offroad").error == "token_conflict" && _root.金钱 == 600000, "token bound to chosen vehicle");
        _root.基建系统.dict.自行车.Level[0].Price = 9000;
        check(commit(initial,"bicycle").error == "catalog_changed" && _root.金钱 == 600000, "changed quote refused");
        setup(); _root.基建系统.dict.自行车.Level[0].Price = 0;
        check(snapshot("bicycle").error == "catalog_invalid", "missing or invalid catalog cannot sell");
        setup(); initial = snapshot("offroad"); _root.__garageSaveOK = false;
        result = commit(initial,"offroad");
        check(!result.success && result.phase == "save_pending" && result.changed && !result.saved, "applied versus saved");
        check(_root.金钱 == 100000 && _root.基建系统.infrastructure.越野车 == 1 && _root.存档系统.dirtyMark, "failed save retains exact applied state");
        result = query(initial);
        check(result.phase == "save_pending" && _root.__garageSaves == 1, "query is read-only");
        check(snapshot("bicycle").token == initial.token, "reopen preserves pending purchase");
        _root.__garageSaveOK = true; result = commit(initial,"offroad");
        check(result.saved && _root.__garageSaves == 2 && _root.__garageFeeds == 1 && _root.金钱 == 100000, "save retry never charges again");
        check(_root.__garageSaveReason == "ui.garage_purchase_paid" && !_root.存档系统.dirtyMark, "canonical save reason");
        check(commit(initial,"bicycle").error == "token_conflict", "receipt cannot change vehicle");
        setup(); initial = snapshot("bicycle");
        _root.gameworld.removeMovieClip(); _root.gameworld = _root.createEmptyMovieClip("__garageWorld",9002);
        _root.gameworld.createEmptyMovieClip("garageHero",1);
        check(commit(initial,"bicycle").error == "context_changed" && _root.金钱 == 600000, "same-path world recreation rejects stale purchase");
        setup(); initial = snapshot("bicycle"); _root.__garageSaveOK = false; commit(initial,"bicycle");
        _root.gameworld.removeMovieClip(); _root.gameworld = _root.createEmptyMovieClip("__garageWorld",9002);
        _root.gameworld.createEmptyMovieClip("garageHero",1); _root.__garageSaveOK = true;
        check(commit(initial,"bicycle").saved && _root.__garageFeeds == 1, "pending save resumes after scene recreation");
        setup(); initial = snapshot("bicycle"); _root.savePath = "another-test-slot";
        check(commit(initial,"bicycle").error == "context_changed" && _root.金钱 == 600000, "slot switch rejects old command");
        setup(); initial = snapshot("bicycle"); commit(initial,"bicycle"); _root.savePath = "another-test-slot";
        check(query(initial).error == "context_changed", "receipt stays with original slot");
        trace("GaragePurchasePanelServiceTest Tests Passed: " + passed);
        trace("GaragePurchasePanelServiceTest Tests Failed: " + failed);
    }
}
