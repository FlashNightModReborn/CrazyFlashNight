import org.flashNight.arki.merc.MercSpawner;

/**
 * MercSpawner.removeMerc 权威 mercId 删除回归（native-interaction cleanup 2026-09-12）。
 * 场景单位只按 用户ID == mercId 删除；旧 _root.菜单MC对应名 间接路径已退役。
 * 配套验证 custody 拒绝、同伴数据/出战标志同下标压缩、回池 InsertionSort 升序，
 * 世界副本元数据独立拷贝（copyMercMeta 带 库记录id）与解雇回池前的身份复位（prepareForPool），
 * 以及 mercenaries.json nohybrid 的杂交基底门（isHybridBaseLocked）。
 */
class org.flashNight.arki.merc.MercSpawnerTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        trace("=== MercSpawnerTest start ===");
        testRemoveByMercIdOnly();
        testDeployFlagCompaction();
        testPoolResortAndHiddenRouting();
        testCustodyRefusalZeroWrite();
        testNotFoundIsNoop();
        testWorldCopyOwnsItsMetadata();
        testWorldCopyFlowsBackWithRestoredIdentity();
        testHybridBaseLock();
        trace("MercSpawnerTest Tests Passed: " + passed);
        trace("MercSpawnerTest Tests Failed: " + failed);
        trace("=== MercSpawnerTest end ===");
    }

    // mercData 列约定：[0]等级 [1]名字 [2]id [3]身高 [4]脸型 [5]发型
    //   [6..16]装备 [17]性别 [18]价格 [19]元数据
    private static function merc(level:Number, id:String, meta:Object):Array {
        return [level, "测试佣兵", id, 175, "脸型A", "发型A",
            "测试头盔", "", "", "", "", "", "测试长枪A", "", "", "", "",
            "男", 1000, meta];
    }

    /** 模拟 gameworld 子成员：记录 removeMovieClip 调用次数。 */
    private static function mockUnit(uid):Object {
        var u:Object = {用户ID:uid, removeCount:0};
        u.removeMovieClip = function():Void { this.removeCount++; };
        return u;
    }

    private static function saveRoot():Object {
        return {
            同伴数据:_root.同伴数据,
            佣兵是否出战信息:_root.佣兵是否出战信息,
            佣兵个数限制:_root.佣兵个数限制,
            同伴数:_root.同伴数,
            可雇佣兵:_root.可雇佣兵,
            隐藏的可雇佣兵:_root.隐藏的可雇佣兵,
            gameworld:_root.gameworld,
            菜单MC对应名:_root.菜单MC对应名
        };
    }

    private static function restoreRoot(s:Object):Void {
        _root.同伴数据 = s.同伴数据;
        _root.佣兵是否出战信息 = s.佣兵是否出战信息;
        _root.佣兵个数限制 = s.佣兵个数限制;
        _root.同伴数 = s.同伴数;
        _root.可雇佣兵 = s.可雇佣兵;
        _root.隐藏的可雇佣兵 = s.隐藏的可雇佣兵;
        _root.gameworld = s.gameworld;
        _root.菜单MC对应名 = s.菜单MC对应名;
    }

    /**
     * 核心回归：菜单名指向别的单位时，只删 mercId 对应成员。
     * 旧实现会先删 gameworld[菜单MC对应名]（误删菜单最后点击的单位），
     * 再按 用户ID 循环删除；新实现只走 用户ID 权威匹配。
     */
    private static function testRemoveByMercIdOnly():Void {
        var s:Object = saveRoot();
        try {
            var m1:Array = merc(10, "m1", {是否杂交:true});
            var m2:Array = merc(20, "m2", {是否杂交:true});
            var m3:Array = merc(30, "m3", {是否杂交:true});
            _root.同伴数据 = [m1, m2, m3];
            _root.佣兵是否出战信息 = [0, 1, 0];
            _root.佣兵个数限制 = 3;
            _root.同伴数 = 3;
            _root.可雇佣兵 = [];
            _root.隐藏的可雇佣兵 = [];

            var decoy:Object = mockUnit("m3");   // 菜单名指向的单位（用户ID 不是 m2）
            var target:Object = mockUnit("m2");
            var bystander:Object = mockUnit("m1");
            _root.gameworld = {菜单目标:decoy, 同伴1:target, 同伴0:bystander};
            _root.菜单MC对应名 = "菜单目标";

            var r:Object = MercSpawner.removeMerc("m2");
            check(r != undefined && r.success === true,
                "removeMerc 命中返回 {success:true}");
            check(decoy.removeCount == 0,
                "菜单MC对应名 指向的单位不被误删");
            check(target.removeCount == 1,
                "用户ID==mercId 的单位被删除一次");
            check(bystander.removeCount == 0,
                "无关单位不受影响");
            check(_root.同伴数 == 2 && _root.同伴数据.length == 2
                    && _root.同伴数据[0] === m1 && _root.同伴数据[1] === m3,
                "同伴数据压缩且顺序不变");
            check(_root.佣兵是否出战信息.length == 2
                    && _root.佣兵是否出战信息[0] == 0
                    && _root.佣兵是否出战信息[1] == 0,
                "出战标志与同伴数据同下标压缩");
            check(_root.可雇佣兵.length == 0,
                "杂交佣兵不回可雇佣兵池");
        } finally {
            restoreRoot(s);
        }
    }

    /** 出战标志 [1,0,1] 移除中间成员 → [1,1]，验证并行数组不错位。 */
    private static function testDeployFlagCompaction():Void {
        var s:Object = saveRoot();
        try {
            var m1:Array = merc(10, "m1", {是否杂交:true});
            var m2:Array = merc(20, "m2", {是否杂交:true});
            var m3:Array = merc(30, "m3", {是否杂交:true});
            _root.同伴数据 = [m1, m2, m3];
            _root.佣兵是否出战信息 = [1, 0, 1];
            _root.佣兵个数限制 = 3;
            _root.同伴数 = 3;
            _root.可雇佣兵 = [];
            _root.隐藏的可雇佣兵 = [];
            _root.gameworld = {};
            _root.菜单MC对应名 = undefined;

            var r:Object = MercSpawner.removeMerc("m2");
            check(r != undefined && r.success === true, "removeMerc 成功");
            check(_root.佣兵是否出战信息.length == 2
                    && _root.佣兵是否出战信息[0] == 1
                    && _root.佣兵是否出战信息[1] == 1,
                "移除中间后前后成员出战标志各保原值");
        } finally {
            restoreRoot(s);
        }
    }

    /** 回池排序：低等级解雇插回按等级升序；隐藏佣兵同时进隐藏池与可见池。 */
    private static function testPoolResortAndHiddenRouting():Void {
        var s:Object = saveRoot();
        try {
            var pooled:Array = merc(40, "p1", {是否杂交:false});
            var m2:Array = merc(5, "m2", {是否杂交:false});
            var m3:Array = merc(60, "m3", {是否杂交:false, 隐藏:true});
            _root.同伴数据 = [m2, m3];
            _root.佣兵是否出战信息 = [0, 0];
            _root.佣兵个数限制 = 2;
            _root.同伴数 = 2;
            _root.可雇佣兵 = [pooled];
            _root.隐藏的可雇佣兵 = [];
            _root.gameworld = {};
            _root.菜单MC对应名 = undefined;

            MercSpawner.removeMerc("m2");
            check(_root.可雇佣兵.length == 2
                    && _root.可雇佣兵[0] === m2 && _root.可雇佣兵[1] === pooled,
                "解雇回池后按等级升序重排（5 < 40）");

            MercSpawner.removeMerc("m3");
            check(_root.隐藏的可雇佣兵.length == 1
                    && _root.隐藏的可雇佣兵[0] === m3,
                "隐藏佣兵进入隐藏池");
            check(_root.可雇佣兵.length == 3
                    && _root.可雇佣兵[2] === m3,
                "隐藏佣兵同时回可见池且排序后在尾部");
            check(_root.同伴数据.length == 0 && _root.同伴数 == 0,
                "全部移除后同伴数据清空");
        } finally {
            restoreRoot(s);
        }
    }

    /** 托管守卫：有任何托管记录（含损坏占位）时 fail-closed 零写入。 */
    private static function testCustodyRefusalZeroWrite():Void {
        var s:Object = saveRoot();
        try {
            var m:Array = merc(10, "m1", {});
            var corruptSlots:Object = {};
            corruptSlots["12"] = {version:2, item:null};
            m[19].装备托管 = {version:1, loadoutRevision:3, slots:corruptSlots};
            _root.同伴数据 = [m];
            _root.佣兵是否出战信息 = [1];
            _root.佣兵个数限制 = 1;
            _root.同伴数 = 1;
            _root.可雇佣兵 = [];
            _root.隐藏的可雇佣兵 = [];
            var unit:Object = mockUnit("m1");
            _root.gameworld = {同伴0:unit};
            _root.菜单MC对应名 = undefined;

            var r:Object = MercSpawner.removeMerc("m1");
            check(r != undefined && r.success === false
                    && r.error == "custody_not_empty",
                "托管非空时返回 custody_not_empty");
            check(_root.同伴数 == 1 && _root.同伴数据[0] === m
                    && _root.佣兵是否出战信息.length == 1
                    && _root.可雇佣兵.length == 0
                    && unit.removeCount == 0,
                "custody 拒绝为 fail-closed 零写入");
        } finally {
            restoreRoot(s);
        }
    }

    /** 未命中：返回 undefined 且不产生任何写入。 */
    private static function testNotFoundIsNoop():Void {
        var s:Object = saveRoot();
        try {
            var m:Array = merc(10, "m1", {是否杂交:false});
            _root.同伴数据 = [m];
            _root.佣兵是否出战信息 = [0];
            _root.佣兵个数限制 = 1;
            _root.同伴数 = 1;
            _root.可雇佣兵 = [];
            _root.隐藏的可雇佣兵 = [];
            var unit:Object = mockUnit("m1");
            _root.gameworld = {同伴0:unit};
            _root.菜单MC对应名 = undefined;

            var r = MercSpawner.removeMerc("不存在");
            check(r === undefined, "未找到 mercId 返回 undefined");
            check(_root.同伴数 == 1 && _root.同伴数据.length == 1
                    && _root.可雇佣兵.length == 0 && unit.removeCount == 0,
                "未命中零写入");
        } finally {
            restoreRoot(s);
        }
    }

    /**
     * 世界副本元数据：内容与库记录等值，但对象全部新建。共享引用会让运行期写入的
     * merc[19].装备托管 回染库记录，之后同一条库记录刷出的每个 NPC、雇下的每个佣兵
     * 都携带同一份托管物品。
     */
    private static function testWorldCopyOwnsItsMetadata():Void {
        var src:Object = {
            是否杂交: false,
            价格倍率: 5,
            被动技能: {升龙拳: {技能名: "升龙拳", 等级: 10, 启用: true}},
            性格: {勇气: 0.61, 技术: 1},
            对话: [{文本: "虎妙台词", 表情: "微笑"}]
        };
        var copy:Object = MercSpawner.copyMercMeta(src, "5652");

        check(copy !== src && copy.世界副本 === true && copy.库记录id == "5652",
            "世界副本 拿到独立元数据对象，并带 世界副本 标记与改写前的 库记录id");
        check(src.世界副本 === undefined && src.库记录id === undefined,
            "两个副本键只存在于副本上，不回染库记录");
        check(copy.是否杂交 === false && copy.价格倍率 == 5,
            "标量键逐键保留");
        check(copy.被动技能 !== src.被动技能 && copy.被动技能.升龙拳 !== src.被动技能.升龙拳
                && copy.被动技能.升龙拳.技能名 == "升龙拳" && copy.被动技能.升龙拳.等级 == 10,
            "嵌套被动技能是新建对象且内容等值");
        check(copy.性格 !== src.性格 && copy.性格.勇气 == 0.61 && copy.性格.技术 == 1,
            "性格 嵌套对象独立，六维值保留");
        check(copy.对话 !== src.对话 && copy.对话.length == 1 && copy.对话[0] !== src.对话[0]
                && copy.对话[0].文本 == "虎妙台词" && copy.对话[0].表情 == "微笑",
            "对话数组与每条台词对象都是新建的（洗牌只作用于副本）");

        copy.装备托管 = {version: 1, loadoutRevision: 1, slots: {}};
        copy.对话[0].文本 = "改过的台词";
        check(src.装备托管 == undefined && src.对话[0].文本 == "虎妙台词",
            "副本写托管/改台词都不回染库记录");

        var noId:Object = MercSpawner.copyMercMeta({是否杂交: false});
        check(noId.世界副本 === true && noId.库记录id === undefined,
            "不传 libraryId 时只打 世界副本 标记（旧形状副本无从复位身份）");
    }

    /** 池内按 用户ID[2] 计数，用于断言"一条库记录在池里恒为一份"。 */
    private static function countWithId(pool:Array, id:String):Number {
        var n:Number = 0;
        for (var i:Number = 0; i < pool.length; i++) {
            if (pool[i][2] == id) n++;
        }
        return n;
    }

    /**
     * 池流转：解雇必须回池（否则这个人在本次会话里再也刷不出来）。世界副本回池前先复位身份——
     * [2] 还原成 库记录id、清掉 世界副本/库记录id 两个副本键，否则池里留下一条对不上移池口径、
     * 又能被反复雇佣的重复项。复位不了的旧档副本（无 库记录id）照旧不回池；杂交体整段跳过；
     * 同一条库记录被跨批次刷成两个 NPC 且都被雇下时，第二次回池必须被去重门挡住。
     */
    private static function testWorldCopyFlowsBackWithRestoredIdentity():Void {
        var s:Object = saveRoot();
        try {
            var copyA:Array = merc(52, "5652虎妙1234",
                MercSpawner.copyMercMeta({是否杂交:false, 隐藏:true, 价格倍率:5}, "5652"));
            var copyB:Array = merc(53, "5652虎妙9999",
                MercSpawner.copyMercMeta({是否杂交:false, 隐藏:true, 价格倍率:5}, "5652"));
            var legacyCopy:Array = merc(44, "8899旧档777",
                MercSpawner.copyMercMeta({是否杂交:false}));
            var hybridChild:Array = merc(60, "7700杂交体888", {是否杂交:true});
            var pooled:Array = merc(30, "1200", {是否杂交:false});
            var dismissedLibrary:Array = merc(31, "1234", {是否杂交:false});
            _root.同伴数据 = [copyA, copyB, legacyCopy, hybridChild, dismissedLibrary];
            _root.佣兵是否出战信息 = [1, 1, 1, 1, 1];
            _root.佣兵个数限制 = 5;
            _root.同伴数 = 5;
            // 雇佣侧 handleWorldHire 已按 库记录id 把 5652 那条库记录移出池，这里从"池里没有它"起步。
            _root.可雇佣兵 = [pooled];
            _root.隐藏的可雇佣兵 = [];
            _root.gameworld = {};
            _root.菜单MC对应名 = undefined;

            MercSpawner.removeMerc("5652虎妙1234");
            check(countWithId(_root.可雇佣兵, "5652") == 1 && _root.可雇佣兵[1] === copyA,
                "世界副本解雇后回可见池，且按复位后的 库记录id 排序落位");
            check(copyA[2] == "5652" && copyA[19].世界副本 === undefined
                    && copyA[19].库记录id === undefined,
                "回池前身份复位：[2] 还原成 库记录id，两个副本键都清掉");
            check(copyA[19].是否杂交 === false && copyA[19].隐藏 === true
                    && copyA[19].价格倍率 == 5,
                "复位只动身份，authored 元数据原样带回池里");
            check(_root.隐藏的可雇佣兵.length == 1 && _root.隐藏的可雇佣兵[0] === copyA,
                "隐藏副本同时进隐藏池");

            MercSpawner.removeMerc("5652虎妙9999");
            check(countWithId(_root.可雇佣兵, "5652") == 1
                    && countWithId(_root.隐藏的可雇佣兵, "5652") == 1,
                "同一条库记录的第二个副本不再回池（去重门），重复雇佣不会换个方向复发");

            MercSpawner.removeMerc("8899旧档777");
            check(_root.可雇佣兵.length == 2 && legacyCopy[2] == "8899旧档777"
                    && legacyCopy[19].世界副本 === true,
                "旧档副本没有 库记录id：身份无从复位，零写入地照旧不回池");

            MercSpawner.removeMerc("7700杂交体888");
            check(countWithId(_root.可雇佣兵, "7700杂交体888") == 0
                    && _root.隐藏的可雇佣兵.length == 1,
                "杂交体照旧不回池（基底记录不由它消耗）");

            MercSpawner.removeMerc("1234");
            check(_root.可雇佣兵.length == 3 && countWithId(_root.可雇佣兵, "1234") == 1
                    && dismissedLibrary[2] == "1234",
                "面板雇下的库记录本身回池，身份不被改写");
            check(_root.同伴数据.length == 0 && _root.同伴数 == 0,
                "全部解雇后同伴数据压实");
        } finally {
            restoreRoot(s);
        }
    }

    /**
     * mercenaries.json nohybrid → merc[19].不可杂交 的杂交基底门：只认显式 true。
     * 真值在写入侧归一化（MercLibrary.buildMercData 写成字面量 true），读取侧用严格比较，
     * 所以 "true"/1 这类没经过 buildMercData 的脏值不会意外关掉杂交。
     */
    private static function testHybridBaseLock():Void {
        var legacy:Array = merc(30, "lib1", {是否杂交: false});
        legacy.length = 19;
        check(MercSpawner.isHybridBaseLocked(legacy) === false,
            "长度不足 20（无 [19]）的记录不判为锁定");
        check(MercSpawner.isHybridBaseLocked(merc(30, "lib2", {是否杂交: false})) === false,
            "缺 不可杂交 键的库记录照旧可当杂交基底");
        check(MercSpawner.isHybridBaseLocked(merc(30, "lib3", {不可杂交: false})) === false,
            "不可杂交 显式 false 与缺省同义");
        check(MercSpawner.isHybridBaseLocked(merc(30, "lib4", {不可杂交: true})) === true,
            "不可杂交 为 true 即锁住基底");
        check(MercSpawner.isHybridBaseLocked(merc(30, "lib5", {不可杂交: "true"})) === false
                && MercSpawner.isHybridBaseLocked(merc(30, "lib6", {不可杂交: 1})) === false,
            "脏值不锁：字符串 true 与数字 1 都不算显式 true");
        check(MercSpawner.isHybridBaseLocked(null) === false
                && MercSpawner.isHybridBaseLocked(undefined) === false,
            "空记录判为不锁，越界索引仍走原来的返回 null 分支");
        check(MercSpawner.isHybridBaseLocked(merc(52, "5652虎妙1234",
                MercSpawner.copyMercMeta({是否杂交: false, 不可杂交: true}))) === true,
            "标记随 copyMercMeta 的元数据深拷保留");
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            passed++;
            trace("[PASS] " + message);
        } else {
            failed++;
            trace("[FAIL] " + message);
        }
    }
}
