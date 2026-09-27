import org.flashNight.arki.merc.MercLibrary;

/**
 * 佣兵数据侧指定对话回归：mercenaries.json 顶层 dialogues → MercLibrary.normalizeDialogues
 * → merc[19].对话 + 名字索引 → MercLibrary.buildDialogueGroups → 待雇 NPC 的 默认对话。
 * 填表说明见 data/merc/mercenaries_README.md。
 */
class org.flashNight.arki.merc.MercDialogueTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        trace("=== MercDialogueTest start ===");
        testNormalizeDialogues();
        testBuildDialogueGroups();
        testBuildMercDataWritesDialogues();
        testNameIndexFollowsPoolReload();
        trace("MercDialogueTest Tests Passed: " + passed);
        trace("MercDialogueTest Tests Failed: " + failed);
        trace("=== MercDialogueTest end ===");
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            passed++;
        } else {
            failed++;
            trace("[FAIL] " + message);
        }
    }

    private static function stubPriceEnv():Void {
        _root.isEasyMode = function():Boolean { return false; };
        _root.isChallengeMode = function():Boolean { return false; };
        _root.基础身价值 = 1000;
    }

    private static function testNormalizeDialogues():Void {
        // 形参注解为 :Object，故意传非数组时用无类型局部变量绕过编译期类型检查
        var unset = undefined;
        var notArray = "一整句台词";
        check(MercLibrary.normalizeDialogues(unset) === undefined,
            "未配置 dialogues 不产生指定对话");
        check(MercLibrary.normalizeDialogues(notArray) === undefined,
            "非数组 dialogues 不产生指定对话");
        check(MercLibrary.normalizeDialogues({text: "对象写法"}) === undefined,
            "整份写成对象而不是数组时不产出台词");
        check(MercLibrary.normalizeDialogues([]) === undefined,
            "空数组不产生指定对话");

        var plain:Array = MercLibrary.normalizeDialogues(["来一壶酒"]);
        check(plain != undefined && plain.length == 1 && plain[0].文本 === "来一壶酒",
            "纯字符串条目即一条台词");
        check(plain != undefined && plain[0].表情 === "普通",
            "缺省表情落到 普通，与 组装单次对话 的默认值一致");

        var withFace:Array = MercLibrary.normalizeDialogues([{text: "拔枪。", expression: "愤怒"}]);
        check(withFace != undefined && withFace[0].文本 === "拔枪。" && withFace[0].表情 === "愤怒",
            "{text, expression} 保留指定表情");

        var blankFace:Array = MercLibrary.normalizeDialogues([{text: "沉默", expression: ""}]);
        check(blankFace != undefined && blankFace[0].表情 === "普通",
            "空表情回落 普通");
        var junkFace:Array = MercLibrary.normalizeDialogues([{text: "数字表情", expression: 3}]);
        check(junkFace != undefined && junkFace[0].表情 === "普通",
            "非字符串表情回落 普通，不把数字塞进立绘查表");

        check(MercLibrary.normalizeDialogues(["", null, 5, {expression: "微笑"}, {text: ""}]) === undefined,
            "没有有效文本的整批条目不产出");
        var mixed:Array = MercLibrary.normalizeDialogues(["甲", "", "乙"]);
        check(mixed != undefined && mixed.length == 2 && mixed[0].文本 === "甲" && mixed[1].文本 === "乙",
            "非法条目只丢弃自身，其余保持原顺序");
    }

    private static function testBuildDialogueGroups():Void {
        var lines:Array = MercLibrary.normalizeDialogues(["甲", {text: "乙", expression: "微笑"}]);
        // target 形参注解为 MovieClip，测试用无类型 mock 绕过编译期类型检查
        var npc = {marker: "待雇NPC"};
        var groups:Array = MercLibrary.buildDialogueGroups(lines, "虎妙", npc);

        check(groups.length == 2,
            "台词条数即轮次数：点一次对话换一句，而不是整段重放");
        check(groups[0].length == 1 && groups[1].length == 1,
            "每条台词自成一组，不塞进同一组随机台词");

        var first:Array = groups[0][0];
        check(first[0] === "虎妙" && first[1] === "佣兵",
            "说话人与身份槽和随机台词同形");
        check(first[2] === "主角模板",
            "立绘角色键固定为 主角模板");
        check(first[3] === "甲" && first[4] === "普通",
            "文本与表情落在位置 3/4");
        check(groups[1][0][3] === "乙" && groups[1][0][4] === "微笑",
            "第二条沿用自己的表情");
        check(first[5] === npc,
            "target 必须是这台 NPC：主角模板 配空 target 会去取主角外观");
        check(first[6] == undefined,
            "不写 imageurl，对话框沿用上一张背景图");
    }

    private static function testBuildMercDataWritesDialogues():Void {
        var savedEasy:Function = _root.isEasyMode;
        var savedChallenge:Function = _root.isChallengeMode;
        var savedBaseValue = _root.基础身价值;
        try {
            stubPriceEnv();

            var plain:Array = MercLibrary.buildMercData({level: 10, name: "对话缺省佣兵", id: "d1"});
            check(plain[19].对话 == undefined,
                "缺省佣兵不写 merc[19].对话");
            check(plain[19].是否杂交 === false,
                "对话缺省时 merc[19] 既有元数据键保留");
            check(MercLibrary.dialoguesByName("对话缺省佣兵") === undefined,
                "未配置的佣兵名查不到指定对话");

            var configured:Array = MercLibrary.buildMercData({
                level: 10, name: "对话配置佣兵", id: "d2",
                dialogues: ["甲", {text: "乙", expression: "微笑"}]
            });
            check(configured[19].对话 != undefined && configured[19].对话.length == 2,
                "dialogues 经 buildMercData 落到 merc[19].对话");
            check(MercLibrary.dialoguesByName("对话配置佣兵") === configured[19].对话,
                "名字索引与 merc[19].对话 是同一份归一化结果");
            check(MercLibrary.dialoguesByName("对话配置佣兵")[1].表情 === "微笑",
                "索引读到的是归一化后的台词，不是 JSON 原文");

            var junk:Array = MercLibrary.buildMercData({
                level: 10, name: "对话非法佣兵", id: "d3", dialogues: ["", 5]
            });
            check(junk[19].对话 == undefined,
                "全非法的 dialogues 不写 merc[19].对话");
        } finally {
            _root.isEasyMode = savedEasy;
            _root.isChallengeMode = savedChallenge;
            _root.基础身价值 = savedBaseValue;
        }
    }

    private static function testNameIndexFollowsPoolReload():Void {
        // 名字索引必须与池同生命周期：JSON 里删掉的记录不能继续吐过期台词。
        var savedEasy:Function = _root.isEasyMode;
        var savedChallenge:Function = _root.isChallengeMode;
        var savedBaseValue = _root.基础身价值;
        var savedPool = _root.可雇佣兵;
        var savedHidden = _root.隐藏的可雇佣兵;
        var savedLimit = _root.佣兵个数限制;
        var savedCompanion = _root.同伴数据;
        try {
            stubPriceEnv();
            _root.佣兵个数限制 = 0;
            _root.同伴数据 = [];

            MercLibrary.loadFromList([
                {level: 20, name: "在册佣兵", id: "r1", dialogues: ["在册台词"]}
            ]);
            check(MercLibrary.dialoguesByName("在册佣兵") != undefined,
                "loadFromList 为有配置的记录登记名字索引");

            MercLibrary.buildMercData({level: 20, name: "仅构建佣兵", id: "r2", dialogues: ["仅构建"]});
            MercLibrary.loadFromList([
                {level: 21, name: "新池佣兵", id: "r3", dialogues: ["新池台词"]}
            ]);
            check(MercLibrary.dialoguesByName("在册佣兵") === undefined,
                "池重建后旧记录的索引被清掉");
            check(MercLibrary.dialoguesByName("仅构建佣兵") === undefined,
                "不在新池里的记录不残留索引");
            check(MercLibrary.dialoguesByName("新池佣兵")[0].文本 === "新池台词",
                "新池记录按 JSON 原文登记台词");
            check(_root.可雇佣兵.length == 1 && _root.可雇佣兵[0][1] === "新池佣兵",
                "索引重置不影响 loadFromList 原有的池重建语义");
        } finally {
            _root.isEasyMode = savedEasy;
            _root.isChallengeMode = savedChallenge;
            _root.基础身价值 = savedBaseValue;
            _root.可雇佣兵 = savedPool;
            _root.隐藏的可雇佣兵 = savedHidden;
            _root.佣兵个数限制 = savedLimit;
            _root.同伴数据 = savedCompanion;
        }
    }
}
