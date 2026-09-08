import org.flashNight.arki.ui.PlasticSurgeryPanelService;
import org.flashNight.arki.unit.UnitComponent.Dressup.LiveAppearanceUpdater;

/** 使用真实 MovieClip 验证原地刷新和幂等付费；保存与装扮资产边界使用可控替身。 */
class org.flashNight.arki.ui.PlasticSurgeryPanelServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] Surgery: " + message); }
    }
    private static function actor():MovieClip { return _root.gameworld[_root.控制目标]; }
    private static function setup():Void {
        PlasticSurgeryPanelService._resetForTests();
        if (_root.__surgeryWorld) _root.__surgeryWorld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("__surgeryWorld", 9001);
        _root.控制目标 = "surgeryHero";
        var hero:MovieClip = _root.gameworld.createEmptyMovieClip("surgeryHero", 1);
        hero.dressupRegistry = {};
        hero.名字 = "原名字"; hero.性别 = "男"; hero.身高 = 175;
        hero._xscale = -100; hero._yscale = 100; hero.myxscale = 100;
        hero.hp = 37; hero.mp = 12; hero.等级 = 20; hero.version = 11;
        hero.dispatcher = {marker:"dispatcher"}; hero.buffManager = {marker:"food"};
        hero.颈部装备数据 = {data:{title:"固定称号"}};
        hero.上装装备数据 = {data:{dressup:"测试衣服"}};
        hero.上装装备 = {name:"现有上装"}; hero.刀 = {name:"现有兵器"};
        _root.savePath = "surgery-test-slot";
        _root.角色名 = "原名字"; _root.性别 = "男"; _root.身高 = 175;
        _root.脸型 = "男变装-基本脸型"; _root.发型 = "现有发型"; _root.虚拟币 = 20;
        _root.__surgeryRefreshes = 0; _root.__surgerySaves = 0; _root.__surgeryFeed = 0;
        _root.__surgeryFailRefresh = false; _root.__surgeryAllowSave = true;
        _root.装备引用配置 = {刷新所有装扮:function(hero) {
            _root.__surgeryRefreshes++;
            if (_root.__surgeryFailRefresh) throw new Error("injected refresh failure");
        }};
        _root.存档系统 = {
            dirtyMark:false,
            markDirty:function():Void { this.dirtyMark = true; },
            flushDurableNow:function(reason):Boolean {
                _root.__surgerySaves++;
                if (_root.__surgeryAllowSave) this.dirtyMark = false;
                return _root.__surgeryAllowSave;
            }
        };
        _root.记录玩家货币变化 = function(money, points, context):Void {
            _root.__surgeryFeed++;
            _root.__surgeryFeedPoints = points;
            _root.__surgeryFeedToken = context.operationId;
        };
        _root.获取虚拟币值 = function():Void {};
    }
    private static function snapshot():Object { return PlasticSurgeryPanelService.execute("snapshot", {v:1}); }
    private static function draft():Object { return {characterName:"新名字", gender:"female", height:200}; }
    private static function submit(token:String, value:Object):Object {
        return PlasticSurgeryPanelService.execute("commit", {v:1, token:token, draft:value});
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        setup();
        var initial:Object = snapshot();
        check(initial.success && initial.phase == "editing" && initial.cost == 5 && initial.balance == 20, "authoritative price and initial snapshot");
        check(initial.current.characterName == "原名字" && initial.current.height == 175 && initial.current.gender == "male", "initial identity");
        check(initial.portrait.equipment.上装装备 == "现有上装" && initial.portrait.hair == "现有发型", "current equipment and hair preview inputs");
        check(_root.__surgeryRefreshes == 0 && _root.__surgerySaves == 0 && _root.虚拟币 == 20, "reading and abandoning draft are free of player writes");
        var invalid:Array = [
            {characterName:"", gender:"female", height:170},
            {characterName:"                ", gender:"female", height:170},
            {characterName:" ", gender:"female", height:170},
            {characterName:"a\nb", gender:"female", height:170},
            {characterName:"正常", gender:"unknown", height:170},
            {characterName:"正常", gender:"female", height:149},
            {characterName:"正常", gender:"female", height:201},
            {characterName:"正常", gender:"female", height:170.5},
            {characterName:"正常", gender:"female", height:"170"}
        ];
        for (var i:Number = 0; i < invalid.length; i++) check(!submit(initial.token, invalid[i]).success, "invalid draft " + i);
        check(_root.虚拟币 == 20 && _root.__surgeryRefreshes == 0 && _root.__surgerySaves == 0, "invalid drafts preserve currency and actor");
        check(submit(initial.token, initial.current).error == "no_change", "unchanged identity cannot charge");
        check(PlasticSurgeryPanelService.execute("snapshot", {v:2}).error == "unsupported_version", "version gate");
        check(PlasticSurgeryPanelService.execute("bad", {v:1}).error == "unsupported_cmd", "command gate");
        _root.虚拟币 = 4;
        check(submit(initial.token, draft()).error == "insufficient_funds" && _root.角色名 == "原名字", "insufficient balance is atomic");
        _root.虚拟币 = 20; _root.角色名 = "其他操作";
        check(submit(initial.token, draft()).error == "stale_state", "stale baseline rejection");

        setup(); initial = snapshot();
        var hero:MovieClip = actor(); var dispatcher:Object = hero.dispatcher; var buffs:Object = hero.buffManager;
        var equipment:Object = hero.上装装备; var weapon:Object = hero.刀;
        var result:Object = submit(initial.token, draft());
        check(result.success && result.phase == "applied" && result.saved === true && result.changed === true, "success requires durable save");
        check(_root.角色名 == "新名字" && _root.性别 == "女" && _root.身高 == 200 && _root.脸型 == "女变装-基本脸型", "persistent identity fields");
        check(actor() === hero && hero._name == "surgeryHero" && hero.名字 == "新名字" && hero.性别 == "女", "same actor identity and updated live profile");
        check(hero._xscale == -114 && hero._yscale == 114 && hero.myxscale == 114 && hero.体重 == 95, "height preserves facing and updates body weight");
        check(hero.身体 == "女测试衣服身体" && hero.脸型 == "女变装-基本脸型" && hero.发型 == "现有发型", "gender remaps current outfit");
        check(hero.displayName.indexOf("新名字") >= 0 && hero.称号 == "固定称号", "name display preserves title");
        check(hero.hp == 37 && hero.mp == 12 && hero.version == 11 && hero.dispatcher === dispatcher && hero.buffManager === buffs, "preserve resources and component identities");
        check(hero.上装装备 === equipment && hero.刀 === weapon && _root.发型 == "现有发型", "preserve gear references and hair");
        check(_root.虚拟币 == 15 && _root.__surgeryFeed == 1 && _root.__surgeryFeedPoints == -5 && _root.__surgeryFeedToken == initial.token, "charge and feed once");
        check(_root.__surgeryRefreshes == 1 && _root.__surgerySaves == 1, "single refresh and strict save");
        result = submit(initial.token, draft());
        check(result.success && _root.虚拟币 == 15 && _root.__surgerySaves == 1 && _root.__surgeryRefreshes == 1, "duplicate commit replays receipt only");
        var changed:Object = draft(); changed.height = 199;
        check(submit(initial.token, changed).error == "token_conflict", "same token cannot change payload after success");
        var next:Object = snapshot();
        check(next.token != initial.token && submit(next.token, next.current).error == "no_change", "reopen does not repeat charge");

        setup(); initial = snapshot(); _root.__surgeryAllowSave = false;
        result = submit(initial.token, draft());
        check(!result.success && result.phase == "save_pending" && result.changed && !result.saved, "failed save reports applied but not durable");
        check(_root.虚拟币 == 15 && _root.角色名 == "新名字", "pending save retains one accepted mutation");
        var before:Number = _root.__surgerySaves;
        result = PlasticSurgeryPanelService.execute("query", {v:1, token:initial.token});
        check(result.phase == "save_pending" && _root.__surgerySaves == before, "query is read only");
        check(snapshot().token == initial.token, "reopen resumes unresolved operation");
        check(submit(initial.token, changed).error == "token_conflict" && _root.虚拟币 == 15, "pending draft is frozen");
        _root.__surgeryAllowSave = true; result = submit(initial.token, draft());
        check(result.success && result.saved && _root.虚拟币 == 15 && _root.__surgeryFeed == 1 && _root.__surgeryRefreshes == 1, "save retry does not replay economic or visual mutation");

        setup(); initial = snapshot(); _root.__surgeryAllowSave = false;
        submit(initial.token, draft());
        _root.gameworld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("__surgeryNextWorld", 9003);
        var nextHero:MovieClip = _root.gameworld.createEmptyMovieClip("surgeryHero", 1);
        nextHero.dressupRegistry = {};
        check(snapshot().token == initial.token, "same save can resume pending persistence after scene recreation");
        _root.__surgeryAllowSave = true;
        check(submit(initial.token, draft()).saved && _root.虚拟币 == 15 && _root.__surgeryRefreshes == 1,
            "scene recreation does not repeat charge or appearance mutation");

        setup(); initial = snapshot(); _root.__surgeryFailRefresh = true;
        result = submit(initial.token, draft());
        check(result.error == "refresh_failed" && _root.虚拟币 == 20 && _root.__surgeryFeed == 0, "refresh failure is not charged");
        check(_root.角色名 == "原名字" && _root.性别 == "男" && actor().名字 == "原名字" && actor().性别 == "男", "refresh failure restores identity");
        check(actor().hp == 37 && actor().mp == 12, "refresh failure preserves current resources");
        setup(); initial = snapshot(); var html:Object = draft(); html.characterName = "<甲&乙>";
        check(submit(initial.token, html).success && actor().displayName.indexOf("&lt;甲&amp;乙&gt;") >= 0, "player name is literal in Flash rich text");
        trace("PlasticSurgeryPanelServiceTest Tests Passed: " + passed);
        trace("PlasticSurgeryPanelServiceTest Tests Failed: " + failed);
    }
}
