import org.flashNight.arki.merc.MercSpawner;

/**
 * MercSpawner.removeMerc 权威 mercId 删除回归（native-interaction cleanup 2026-09-12）。
 * 场景单位只按 用户ID == mercId 删除；旧 _root.菜单MC对应名 间接路径已退役。
 * 配套验证 custody 拒绝、同伴数据/出战标志同下标压缩、回池 InsertionSort 升序。
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
