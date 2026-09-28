import org.flashNight.arki.merc.MercSpawner;

/**
 * MercSpawner.removeMerc 权威 mercId 删除回归（native-interaction cleanup 2026-09-12）。
 * 场景单位只按 用户ID == mercId 删除；旧 _root.菜单MC对应名 间接路径已退役。
 * 配套验证 custody 拒绝、同伴数据/出战标志同下标压缩、回池 InsertionSort 升序，
 * 世界副本元数据独立拷贝（copyMercMeta）与 世界副本 的池流转门控，
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
        testWorldCopyDoesNotFlowIntoPools();
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
        var copy:Object = MercSpawner.copyMercMeta(src);

        check(copy !== src && copy.世界副本 === true,
            "世界副本 拿到独立元数据对象并带 世界副本 标记");
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
    }

    /**
     * 池流转门控：世界副本解雇后既不进可见池也不进隐藏池（它的库记录本来就在池里，
     * 回池只会塞一份 [2] 已被 createMercData 改写的重复项）；无标记的库记录照旧回池。
     */
    private static function testWorldCopyDoesNotFlowIntoPools():Void {
        var s:Object = saveRoot();
        try {
            var worldCopy:Array = merc(52, "5652虎妙1234",
                MercSpawner.copyMercMeta({是否杂交: false, 隐藏: true, 价格倍率: 5}));
            var libraryRecord:Array = merc(30, "lib1", {是否杂交: false});
            _root.同伴数据 = [worldCopy, libraryRecord];
            _root.佣兵是否出战信息 = [1, 1];
            _root.佣兵个数限制 = 2;
            _root.同伴数 = 2;
            _root.可雇佣兵 = [];
            _root.隐藏的可雇佣兵 = [];
            _root.gameworld = {};
            _root.菜单MC对应名 = undefined;

            MercSpawner.removeMerc("5652虎妙1234");
            check(_root.可雇佣兵.length == 0 && _root.隐藏的可雇佣兵.length == 0,
                "世界副本解雇后不进任何池（含隐藏分支）");

            MercSpawner.removeMerc("lib1");
            check(_root.可雇佣兵.length == 1 && _root.可雇佣兵[0] === libraryRecord,
                "无标记的库记录照旧回池，门控只挡世界副本");
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
