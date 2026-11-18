import org.flashNight.arki.merc.MercLibrary;

class org.flashNight.arki.merc.MercDefinitionCacheTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        trace("=== MercDefinitionCacheTest start ===");
        _root.isEasyMode = function():Boolean { return false; };
        _root.isChallengeMode = function():Boolean { return false; };
        _root.基础身价值 = 1000;
        _root.佣兵个数限制 = 1;
        _root.同伴数据 = [];
        _root.gameworld = {菜单:{removeMovieClip:function():Void {}}};
        _root.脸型库 = {};
        _root.脸型库["face.test"] = "脸-测试";
        _root.发型库 = {};
        _root.发型库["hair.test"] = "发-测试";
        var raw:Object = {
            id:"cache.test", name:"缓存测试", level:20, height:175, gender:"男",
            face:"face.test", hair:"hair.test",
            equipment:{head:"测试头盔"},
            personality:{勇气:2},
            passive:{样本被动:{等级:3}},
            dialogues:["第一句"]
        };

        var first:Array = MercLibrary.buildMercData(raw);
        var second:Array = MercLibrary.buildMercData(raw);
        check(first !== second && first[19] !== second[19],
            "同一原始 ID 返回独立数组和元数据对象");
        check(first[4] === second[4] && first[5] === second[5]
                && first[6] === second[6] && first[19].性格.勇气 === 1,
            "缓存保留脸型、发型、装备和人格归一化结果");
        check(first[19].对话[0].文本 === second[19].对话[0].文本,
            "缓存保留指定对话内容");

        first[19].性格.勇气 = 0;
        first[19].隐藏 = true;
        first[19].对话[0].文本 = "污染";
        first[19].被动技能.样本被动.等级 = 9;
        var third:Array = MercLibrary.buildMercData(raw);
        check(third[19].性格.勇气 === 1,
            "修改首个返回对象的人格不会污染后续定义");
        check(third[19].隐藏 === undefined && third[19].对话[0].文本 === "第一句",
            "修改首个返回对象的隐藏标记和台词不会污染缓存");
        check(raw.personality.勇气 === 2 && raw.dialogues[0] === "第一句",
            "原始定义输入不被任何返回对象改写");

        check(raw.passive.样本被动.等级 === 3 && third[19].被动技能.样本被动.等级 === 3,
            "首次生成与后续缓存副本均隔离原始被动表");

        MercLibrary.loadFromList([raw]);
        var available:Array = _root.可雇佣兵;
        var availableFirst:Array = available[0];
        MercLibrary.loadFromList([raw]);
        var availableSecond:Array = _root.可雇佣兵[0];
        check(available !== _root.可雇佣兵 && availableFirst !== availableSecond,
            "available 池重建保持数组和定义实例独立");
        check(MercLibrary.dialoguesByName(raw.name)[0].文本 === "第一句",
            "名字索引读取的是缓存定义的原始台词");

        raw.hidden = true;
        MercLibrary.loadFromList([raw]);
        check(_root.可雇佣兵.length === 1 && _root.隐藏的可雇佣兵.length === 1
                && _root.可雇佣兵[0] === _root.隐藏的可雇佣兵[0],
            "隐藏定义进入合并候选池，同时保留独立 hidden 索引");
        check(_root.隐藏的可雇佣兵[0][19].隐藏 === true,
            "hidden 标记只落到本次 hidden 池定义");

        raw.dialogues = ["更新"];
        MercLibrary.loadFromList([raw]);
        check(MercLibrary.dialoguesByName(raw.name)[0].文本 === "更新",
            "池重载同时刷新定义缓存和名字索引");

        testInstalledDefinitions();
        trace("MercDefinitionCacheTest Tests Passed: " + passed);
        trace("MercDefinitionCacheTest Tests Failed: " + failed);
        trace("=== MercDefinitionCacheTest end ===");
    }

    private static function testInstalledDefinitions():Void {
        var firstRaw:Object = {id:5528, name:"彗星", level:31, equipment:{primary:"先录武器"}};
        var lastRaw:Object = {id:5528, name:"XV秩律-执裁者", level:64, equipment:{primary:"后录武器"}};
        var hiddenRaw:Object = {id:8, name:"隐藏", level:12, hidden:true};
        MercLibrary.installDefinitions([firstRaw, lastRaw, hiddenRaw]);
        check(MercLibrary.dialoguesByName("缓存测试") === undefined,
            "更换定义源后清理旧的名字索引");

        var called:Boolean = false;
        MercLibrary.refreshPool(function(value):Void { called = value === "刷新"; }, "刷新");
        var normalPool:Array = _root.可雇佣兵;
        check(called && normalPool.length === 3 && normalPool[0][1] === "彗星"
                && normalPool[1][1] === "XV秩律-执裁者",
            "刷新保留同 ID 的两条定义、等级排序与同步回调");
        check(normalPool[0][12] === "先录武器" && normalPool[1][12] === "后录武器",
            "相同 ID 的原始定义不会混用装备缓存");

        var arena:Array = MercLibrary.buildVisibleMercById("05528");
        check(arena[1] === "XV秩律-执裁者" && arena[12] === "后录武器",
            "混编同步索引保留数字回退和同 ID 后录优先");
        check(MercLibrary.buildVisibleMercById("8") === null && MercLibrary.buildVisibleMercById("缺失") === null,
            "混编跳过隐藏记录和未知 ID");
        arena[12] = "战斗覆盖";
        check(lastRaw.equipment.primary === "后录武器" && normalPool[1][12] === "后录武器"
                && MercLibrary.buildVisibleMercById("5528")[12] === "后录武器",
            "战斗实例、候选池和原始定义彼此隔离");

        _root.isEasyMode = function():Boolean { return true; };
        _root.基础身价值 = 900;
        _root.同伴数据 = [arena];
        MercLibrary.refreshPool(undefined, undefined);
        check(_root.可雇佣兵.length === 2 && _root.可雇佣兵[0][1] === "彗星"
                && _root.可雇佣兵[0][18] === 27900 && normalPool[0][18] === 135000,
            "切换角色后沿用定义，按新难度和身价重建并过滤已雇佣兵");
        check(_root.隐藏的可雇佣兵.length === 1 && _root.可雇佣兵[1] === _root.隐藏的可雇佣兵[0]
                && normalPool !== _root.可雇佣兵,
            "角色可变池重建且保留隐藏索引契约");

        MercLibrary.installDefinitions([]);
        MercLibrary.refreshPool(undefined, undefined);
        check(MercLibrary.buildVisibleMercById("5528") === null && _root.可雇佣兵.length === 0
                && _root.隐藏的可雇佣兵.length === 0,
            "更换定义源会释放旧的可查记录并可从空源刷新");
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) passed++;
        else {
            failed++;
            trace("[FAIL] " + message);
        }
    }
}
