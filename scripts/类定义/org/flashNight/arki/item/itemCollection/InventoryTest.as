import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * Inventory及其附属类的测试类
 * 负责测试Inventory及其附属类的各种功能
 */
class org.flashNight.arki.item.itemCollection.InventoryTest {

    private var testPassed:Number;   // 通过的测试数量
    private var testFailed:Number;   // 失败的测试数量

    public function InventoryTest() {
        testPassed = 0;
        testFailed = 0;
    }

    /**
     * 简单的断言函数
     * 根据条件判断测试是否通过，并记录结果。
     * @param condition 条件表达式
     * @param message 测试描述信息
     */
    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            trace("PASS: " + message);
            testPassed++;
        } else {
            trace("FAIL: " + message);
            testFailed++;
        }
    }

    /**
     * 运行所有测试
     * 包括正确性测试和性能测试（这里暂不涉及性能）。
     */
    public function runTests():Void {
        trace("开始 Inventory 测试...");

        // 原有基础功能测试
        testBasic();
        testRequirement();

        // 新增的覆盖范围更广的测试（边界、异常、Inventory 新方法等）
        testEdgeCases();
        testSearchAndValueMethods();
        testMoveMergeSwap();

        trace("测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
    }

    /**
     * 测试 add, remove, 等基础方法
     * 原有测试逻辑，保留并可适度增补。
     */
    private function testBasic():Void {
        trace("\n===> 测试 testBasic (add/remove) ...");
        var inventory = new ArrayInventory(null, 5);
        inventory.add(0, { name:"普通hp药剂", value:5 });
        inventory.add(2, { name:"普通mp药剂", value:5 });
        inventory.add(3, { name:"匕首", value:{ level:1 } });
        inventory.add(4, { name:"AK47", value:{ level:7 } });
        inventory.add(1, { name:"牛肉罐头", value:2 });

        // 输出 add 后的物品栏和索引表
        trace(ObjectUtil.toString(inventory.getItems()));
        trace(ObjectUtil.toString(inventory.getIndexes()));
        assert(inventory.getFirstVacancy() == -1, "添加物品后，首个空格应为 -1");

        trace("\n测试 remove 方法...");
        inventory.remove(1);
        inventory.remove(4);

        // 输出 remove 后的物品栏和索引表
        trace(ObjectUtil.toString(inventory.getItems()));
        trace(ObjectUtil.toString(inventory.getIndexes()));
        assert(inventory.getFirstVacancy() == 1, "移除物品后，首个空格应为 1");
    }

    /**
     * 测试添加与提交物品函数
     * 原有测试逻辑，保留
     */
    private function testRequirement():Void {
        trace("\n===> 测试 testRequirement (acquire/submit) ...");

        // 初始化 _root 作为模拟的全局数据容器
        _root.物品栏 = {
            背包: new ArrayInventory(null, 5)
        };
        _root.收集品栏 = {
            材料: new DictCollection(null),
            情报: new DictCollection(null)
        };

        // 测试 acquire
        var array1 = [
            ["匕首",1],
            ["资料",1],
            ["牛肉罐头",3],
            ["战术导轨",2],
            ["普通hp药剂",5]
        ];
        var itemArray = ItemUtil.getRequirement(array1);
        assert(ItemUtil.acquire(itemArray), "添加 3 个物品，1 个材料和 1 个情报");

        var array2 = [
            ["普通hp药剂",5],
            ["普通mp药剂",5],
            ["牛肉罐头",1]
        ];
        itemArray = ItemUtil.getRequirement(array2);
        assert(ItemUtil.acquire(itemArray), "添加 3 个物品，其中 2 个物品可叠加");

        var array3 = [
            ["普通mp药剂",5],
            ["AK47",1],
            ["AK47",1]
        ];
        itemArray = ItemUtil.getRequirement(array3);
        assert(!ItemUtil.acquire(itemArray), "添加 3 个物品，其中 1 个物品可叠加，应由于空间不足而添加失败");

        var array4 = [
            ["普通hp药剂",5],
            ["普通mp药剂",5],
            ["战术导轨",1]
        ];
        // 输出 acquire 后背包的物品
        trace(ObjectUtil.toString(_root.物品栏.背包.getItems()));
        trace(ObjectUtil.toString(_root.物品栏.背包.getIndexes()));

        itemArray = ItemUtil.getRequirement(array4);
        // 测试 submit
        assert(ItemUtil.submit(itemArray), "提交 3 个物品和 1 个材料");

        var array5 = [
            ["普通hp药剂",10],
            ["牛肉罐头",1]
        ];
        itemArray = ItemUtil.getRequirement(array5);
        assert(!ItemUtil.submit(itemArray), "提交 2 个物品，应由于物品不足而提交失败");

        // 输出 submit 后背包的物品
        trace(ObjectUtil.toString(_root.物品栏.背包.getItems()));
        trace(ObjectUtil.toString(_root.物品栏.背包.getIndexes()));
    }

    /**
     * 新增：测试边界情况和异常输入处理
     */
    private function testEdgeCases():Void {
        trace("\n===> 测试 testEdgeCases (边界与异常) ...");
        var inventory = new ArrayInventory(null, 3); // 容量 3

        // 1. 添加 null / 无效 item
        var result1 = inventory.add(0, null);
        assert(!result1, "不能添加 null 物品");

        var result2 = inventory.add(0, { value: 10 }); // name 缺失
        assert(!result2, "物品没有 name 字段应被拒绝添加");

        var result3 = inventory.add(0, { name:"不合法物品", value: null });
        assert(!result3, "物品 value 为 null，应该被拒绝添加");

        // 2. 超出容量时的 add 测试
        inventory.add(0, { name:"物品A", value:1 });
        inventory.add(1, { name:"物品B", value:2 });
        inventory.add(2, { name:"物品C", value:3 });
        assert(inventory.getFirstVacancy() == -1, "已占满，首个空格应为 -1");

        // 再次尝试添加
        var result4 = inventory.add(3, { name:"物品D", value:4 });
        assert(!result4, "超出容量的添加应失败");

        // 3. 移除不存在或越界格子
        var removeResult1 = inventory.remove(10);
        assert(!removeResult1, "移除 index 越界物品应失败");
        var removeResult2 = inventory.remove(-1);
        assert(!removeResult2, "移除 index 负数物品应失败");

        // 4. 添加负数或 NaN value
        var addNeg = inventory.add(1, { name:"负数物品", value:-5 });
        assert(!addNeg, "负数 value 应判为不合法，添加失败");

        var addNaN = inventory.add(1, { name:"NaN物品", value: parseFloat("abc") });
        assert(!addNaN, "NaN value 应判为不合法，添加失败");
    }

    /**
     * 新增：测试 Inventory 中的搜索和数值修改相关方法
     */
    private function testSearchAndValueMethods():Void {
        trace("\n===> 测试 testSearchAndValueMethods (searchFirstKey, searchKeys, addValue) ...");

        var inventory = new ArrayInventory(null, 5);
        inventory.add(0, { name:"AK47", value:2 });
        inventory.add(1, { name:"AK47", value:1 });
        inventory.add(2, { name:"牛肉罐头", value:5 });

        // 测试 searchFirstKey
        var firstKey = inventory.searchFirstKey("AK47");
        assert(firstKey == "0", "searchFirstKey 返回应为第一个 AK47 的格子 (key=0)" + firstKey);

        var noneKey = inventory.searchFirstKey("不存在的物品");
        assert(noneKey == undefined, "searchFirstKey 对不存在的物品应返回 undefined");

        // 测试 searchKeys
        var keys = inventory.searchKeys("AK47");
        assert(keys.length == 2, "searchKeys('AK47') 返回应为 [0, 1] 共 2 个格子");
        var emptyKeys = inventory.searchKeys("没有的物品");
        assert(emptyKeys.length == 0, "searchKeys 对没有物品返回空数组");

        // 测试 addValue
        inventory.addValue("0", 3);  // 把 "AK47" 的 value 从 2 增加到 5
        assert(inventory.getItem("0").value == 5, "addValue(3) 后物品数量应变为 5");

        // 测试 addValue 导致物品数量归零并自动 remove
        inventory.addValue("1", -1); // 把格子 1 的 AK47 value 从 1 减到 0
        // 格子 1 应被移除
        var item1 = inventory.getItem("1");
        assert(item1 == null, "当物品 value <= 0 时应自动 remove");
    }

    /**
     * 新增：测试 move, merge, swap 等物品移动操作
     */
    private function testMoveMergeSwap():Void {
        trace("\n===> 测试 testMoveMergeSwap (move/merge/swap) ...");

        var invA = new ArrayInventory(null, 3);
        var invB = new ArrayInventory(null, 3);

        // 准备测试数据
        invA.add(0, { name:"匕首", value:1 });
        invA.add(1, { name:"普通hp药剂", value:5 });

        invB.add(0, { name:"普通hp药剂", value:5 });
        invB.add(1, { name:"牛肉罐头", value:2 });

        // 1. move 测试：将 invA[1] 的物品移动到 invB[2]
        var moveResult = invA.move(invB, "1", "2");
        assert(moveResult, "move 成功，匕首不受影响");
        assert(invB.getItem("2").name == "普通hp药剂", "目标格子应成功接收 普通hp药剂");
        assert(invA.getItem("1") == null, "源格子应被清空");

        // 再次移动到一个已存在物品的格子 -> 应失败
        var failMoveResult = invA.move(invB, "0", "0");  // invB[0] 已有物品
        assert(!failMoveResult, "move 到已占用格子应失败");

        // 2. merge 测试：将 invB[2] 的 hp药剂合并到 invB[0] 的 hp药剂
        var mergeResult = invB.merge(invB, "2", "0");
        assert(mergeResult, "merge 同名可叠加物品成功");
        // invB[0] 的 value 应该是 10
        assert(invB.getItem("0").value == 10, "merge 后物品数量应累加为 10");
        assert(invB.getItem("2") == null, "源格子被清空");

        // merge 不同名物品应失败
        var failMerge = invA.merge(invB, "0", "1"); // "匕首" vs "牛肉罐头"
        assert(!failMerge, "merge 不同物品应失败");

        // 3. swap 测试：交换 invA[0] (匕首) 和 invB[1] (牛肉罐头)
        var swapResult = invA.swap(invB, "0", "1");
        assert(swapResult, "swap 应该成功");
        assert(invA.getItem("0").name == "牛肉罐头", "invA[0] 应变成牛肉罐头");
        assert(invB.getItem("1").name == "匕首", "invB[1] 应变成匕首");

        // swap 条件不足，应失败
        // 比如尝试 swap invA[1] (null) 和 invB[0] (hp药剂)
        var failSwap = invA.swap(invB, "1", "0");
        assert(!failSwap, "swap 空格子或不存在物品应失败");
    }
}
