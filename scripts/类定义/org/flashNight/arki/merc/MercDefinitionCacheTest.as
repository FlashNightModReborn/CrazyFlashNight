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
        _root.脸型库 = {"face.test": "脸-测试"};
        _root.发型库 = {"hair.test": "发-测试"};
        var raw:Object = {
            id:"cache.test", name:"缓存测试", level:20, height:175, gender:"男",
            face:"face.test", hair:"hair.test",
            equipment:{head:"测试头盔"},
            personality:{勇气:2},
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
        var third:Array = MercLibrary.buildMercData(raw);
        check(third[19].性格.勇气 === 1,
            "修改首个返回对象的人格不会污染后续定义");
        check(third[19].隐藏 === undefined && third[19].对话[0].文本 === "第一句",
            "修改首个返回对象的隐藏标记和台词不会污染缓存");
        check(raw.personality.勇气 === 2 && raw.dialogues[0] === "第一句",
            "原始定义输入不被任何返回对象改写");

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
        check(_root.可雇佣兵.length === 0 && _root.隐藏的可雇佣兵.length === 1,
            "hidden 池与 available 池数量独立");
        check(_root.隐藏的可雇佣兵[0][19].隐藏 === true,
            "hidden 标记只落到本次 hidden 池定义");

        raw.dialogues = ["更新"];
        MercLibrary.loadFromList([raw]);
        check(MercLibrary.dialoguesByName(raw.name)[0].文本 === "更新",
            "池重载同时刷新定义缓存和名字索引");

        trace("MercDefinitionCacheTest Tests Passed: " + passed);
        trace("MercDefinitionCacheTest Tests Failed: " + failed);
        trace("=== MercDefinitionCacheTest end ===");
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) passed++;
        else {
            failed++;
            trace("[FAIL] " + message);
        }
    }
}
