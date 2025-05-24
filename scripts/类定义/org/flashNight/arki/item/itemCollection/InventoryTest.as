import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * Inventory及其附属类的测试类
 * 负责测试Inventory及其附属类的各种功能，
 * 当测试失败时输出详细的中间状态信息，以便确定问题所在。
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
     * 如果断言失败则输出附加的详细信息
     * @param condition 条件表达式
     * @param message 测试描述信息
     * @param details 详细信息（当断言失败时输出）
     */
    private function assert(condition:Boolean, message:String, details:String):Void {
        details = details || "";
        if (condition) {
            trace("PASS: " + message);
            testPassed++;
        } else {
            trace("FAIL: " + message);
            if (details != "") {
                trace("DETAILS: " + details);
            }
            testFailed++;
        }
    }

    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("开始 Inventory 测试...");


        trace("初始化测试数据...");
        // 初始化测试所需的物品数据
        // 创建 itemDataDict 对象
        ItemUtil.itemDataDict = {};

        // 手动为每个物品添加属性
        ItemUtil.itemDataDict["匕首"] = {};
        ItemUtil.itemDataDict["匕首"]["type"] = "武器";
        ItemUtil.itemDataDict["匕首"]["use"] = "武器";

        ItemUtil.itemDataDict["资料"] = {};
        ItemUtil.itemDataDict["资料"]["type"] = "情报";
        ItemUtil.itemDataDict["资料"]["use"] = "情报";

        ItemUtil.itemDataDict["牛肉罐头"] = {};
        ItemUtil.itemDataDict["牛肉罐头"]["type"] = "消耗品";
        ItemUtil.itemDataDict["牛肉罐头"]["use"] = "食品";

        ItemUtil.itemDataDict["战术导轨"] = {};
        ItemUtil.itemDataDict["战术导轨"]["type"] = "材料";
        ItemUtil.itemDataDict["战术导轨"]["use"] = "材料";

        ItemUtil.itemDataDict["普通hp药剂"] = {};
        ItemUtil.itemDataDict["普通hp药剂"]["type"] = "消耗品";
        ItemUtil.itemDataDict["普通hp药剂"]["use"] = "药剂";

        ItemUtil.itemDataDict["普通mp药剂"] = {};
        ItemUtil.itemDataDict["普通mp药剂"]["type"] = "消耗品";
        ItemUtil.itemDataDict["普通mp药剂"]["use"] = "药剂";

        ItemUtil.itemDataDict["AK47"] = {};
        ItemUtil.itemDataDict["AK47"]["type"] = "武器";
        ItemUtil.itemDataDict["AK47"]["use"] = "武器";

        ItemUtil.itemDataDict["负数物品"] = {};
        ItemUtil.itemDataDict["负数物品"]["type"] = "垃圾";
        ItemUtil.itemDataDict["负数物品"]["use"] = "无效"

        ItemUtil.itemDataDict["NaN物品"] = {};
        ItemUtil.itemDataDict["NaN物品"]["type"] = "垃圾";
        ItemUtil.itemDataDict["NaN物品"]["use"] = "无效";

        // 创建 itemNamesByID 对象
        ItemUtil.itemNamesByID = {};

        // 手动为每个 ID 添加属性
        ItemUtil.itemNamesByID[0] = "匕首";
        ItemUtil.itemNamesByID[1] = "资料";
        ItemUtil.itemNamesByID[2] = "牛肉罐头";
        ItemUtil.itemNamesByID[3] = "战术导轨";
        ItemUtil.itemNamesByID[4] = "普通hp药剂";
        ItemUtil.itemNamesByID[5] = "普通mp药剂";
        ItemUtil.itemNamesByID[6] = "AK47";

        ItemUtil.maxID = 6;
        ItemUtil.informationMaxValueDict = {}; // 根据测试需要添加情报上限

        testBasic();
        testRequirement();
        testEdgeCases();
        testSearchAndValueMethods();
        testMoveMergeSwap();
        testRebuildOrder();

        trace("测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
    }

    /**
     * 测试 add、remove 等基础方法
     */
    private function testBasic():Void {
        trace("\n===> 测试 testBasic (add/remove) ...");
        var inventory = new ArrayInventory(null, 5);
        inventory.add(0, { name:"普通hp药剂", value:5 });
        inventory.add(2, { name:"普通mp药剂", value:5 });
        inventory.add(3, { name:"匕首", value:{ level:1 } });
        inventory.add(4, { name:"AK47", value:{ level:7 } });
        inventory.add(1, { name:"牛肉罐头", value:2 });
        
        var itemsStr:String = ObjectUtil.toString(inventory.getItems());
        var indexesStr:String = ObjectUtil.toString(inventory.getIndexes());
        trace("After add: items: " + itemsStr);
        trace("After add: indexes: " + indexesStr);
        
        var firstVacancy:Number = inventory.getFirstVacancy();
        assert(firstVacancy == -1, 
            "添加物品后，首个空格应为 -1", 
            "实际 firstVacancy: " + firstVacancy + ", items: " + itemsStr + ", indexes: " + indexesStr);

        trace("\n测试 remove 方法...");
        inventory.remove(1);
        inventory.remove(4);

        itemsStr = ObjectUtil.toString(inventory.getItems());
        indexesStr = ObjectUtil.toString(inventory.getIndexes());
        trace("After remove: items: " + itemsStr);
        trace("After remove: indexes: " + indexesStr);
        
        firstVacancy = inventory.getFirstVacancy();
        assert(firstVacancy == 1, 
            "移除物品后，首个空格应为 1", 
            "实际 firstVacancy: " + firstVacancy + ", items: " + itemsStr + ", indexes: " + indexesStr);
    }

    /**
     * 测试 acquire 与 submit 函数
     */
    private function testRequirement():Void {
        trace("\n===> 测试 testRequirement (acquire/submit) ...");

        // 初始化全局 _root 模拟物品栏与收集品栏
        _root.物品栏 = { 背包: new ArrayInventory(null, 5) };
        _root.收集品栏 = { 
            材料: new DictCollection(null), 
            情报: new DictCollection(null) 
        };

        // 测试 acquire——array1
        var array1:Array = [
            ["匕首", 1],
            ["资料", 1],
            ["牛肉罐头", 3],
            ["战术导轨", 2],
            ["普通hp药剂", 5]
        ];
        var itemArray:Array = ItemUtil.getRequirement(array1);
        var resultAcquire1:Boolean = ItemUtil.acquire(itemArray);
        assert(resultAcquire1, 
            "添加 3 个物品，1 个材料和 1 个情报", 
            "acquire(array1) 返回 false");

        // 测试 acquire——array2（部分物品可叠加）
        var array2:Array = [
            ["普通hp药剂", 5],
            ["普通mp药剂", 5],
            ["牛肉罐头", 1]
        ];
        itemArray = ItemUtil.getRequirement(array2);
        var resultAcquire2:Boolean = ItemUtil.acquire(itemArray);
        assert(resultAcquire2, 
            "添加 3 个物品，其中 2 个物品可叠加", 
            "acquire(array2) 返回 false");

        // 测试 acquire——array3：应因空间不足而添加失败
        var array3:Array = [
            ["普通mp药剂", 5],
            ["AK47", 1],
            ["AK47", 1]
        ];
        itemArray = ItemUtil.getRequirement(array3);
        var resultAcquire3:Boolean = ItemUtil.acquire(itemArray);
        assert(!resultAcquire3, 
            "添加 3 个物品，其中 1 个物品可叠加，应由于空间不足而添加失败", 
            "acquire(array3) 返回 true，背包状态: " + ObjectUtil.toString(_root.物品栏.背包.getItems()));

        // 输出当前背包状态
        var bpItemsStr:String = ObjectUtil.toString(_root.物品栏.背包.getItems());
        var bpIndexesStr:String = ObjectUtil.toString(_root.物品栏.背包.getIndexes());
        trace("背包状态 after acquire: items: " + bpItemsStr + ", indexes: " + bpIndexesStr);

        // 测试 submit——array4
        var array4:Array = [
            ["普通hp药剂", 5],
            ["普通mp药剂", 5],
            ["战术导轨", 1]
        ];
        itemArray = ItemUtil.getRequirement(array4);
        var resultSubmit1:Boolean = ItemUtil.submit(itemArray);
        assert(resultSubmit1, 
            "提交 3 个物品和 1 个材料", 
            "submit(array4) 返回 false，背包状态: " + ObjectUtil.toString(_root.物品栏.背包.getItems()));

        // 测试 submit——array5：应因物品不足而提交失败
        var array5:Array = [
            ["普通hp药剂", 10],
            ["牛肉罐头", 1]
        ];
        itemArray = ItemUtil.getRequirement(array5);
        var resultSubmit2:Boolean = ItemUtil.submit(itemArray);
        assert(!resultSubmit2, 
            "提交 2 个物品，应由于物品不足而提交失败", 
            "submit(array5) 返回 true，背包状态: " + ObjectUtil.toString(_root.物品栏.背包.getItems()));

        bpItemsStr = ObjectUtil.toString(_root.物品栏.背包.getItems());
        bpIndexesStr = ObjectUtil.toString(_root.物品栏.背包.getIndexes());
        trace("背包状态 after submit: items: " + bpItemsStr + ", indexes: " + bpIndexesStr);
    }

    /**
     * 测试边界情况和异常输入处理
     */
    private function testEdgeCases():Void {
        trace("\n===> 测试 testEdgeCases (边界与异常) ...");
        var inventory = new ArrayInventory(null, 3);

        // 1. 添加 null 物品
        var result1:Boolean = inventory.add(0, null);
        assert(!result1, 
            "不能添加 null 物品", 
            "尝试添加 null, 当前 inventory: " + ObjectUtil.toString(inventory.getItems()));

        // 2. 添加没有 name 字段的物品
        var result2:Boolean = inventory.add(0, { value: 10 });
        assert(!result2, 
            "物品没有 name 字段应被拒绝添加", 
            "当前 inventory: " + ObjectUtil.toString(inventory.getItems()));

        // 3. 添加 value 为 null 的物品
        var result3:Boolean = inventory.add(0, { name:"不合法物品", value: null });
        assert(!result3, 
            "物品 value 为 null，应该被拒绝添加", 
            "当前 inventory: " + ObjectUtil.toString(inventory.getItems()));

        // 4. 测试库存已满时的添加
        inventory.add(0, { name:"物品A", value:1 });
        inventory.add(1, { name:"物品B", value:2 });
        inventory.add(2, { name:"物品C", value:3 });
        var firstVacancy:Number = inventory.getFirstVacancy();
        assert(firstVacancy == -1, 
            "已占满，首个空格应为 -1", 
            "实际 firstVacancy: " + firstVacancy + ", inventory: " + ObjectUtil.toString(inventory.getItems()));

        var result4:Boolean = inventory.add(3, { name:"物品D", value:4 });
        assert(!result4, 
            "超出容量的添加应失败", 
            "尝试添加超出容量, inventory: " + ObjectUtil.toString(inventory.getItems()));

        // 5. 移除不存在或越界的索引
        var removeResult1:Boolean = inventory.remove(10);
        assert(!removeResult1, 
            "移除 index 越界物品应失败", 
            "remove(10) 后 inventory: " + ObjectUtil.toString(inventory.getItems()));
        var removeResult2:Boolean = inventory.remove(-1);
        assert(!removeResult2, 
            "移除 index 负数物品应失败", 
            "remove(-1) 后 inventory: " + ObjectUtil.toString(inventory.getItems()));

        // 6. 添加负数 value 的物品
        var addNeg:Boolean = inventory.add(1, { name:"负数物品", value:-5 });
        assert(!addNeg, 
            "负数 value 应判为不合法，添加失败", 
            "尝试添加负数 value, inventory: " + ObjectUtil.toString(inventory.getItems()));

        // 7. 添加 NaN value 的物品
        var addNaN:Boolean = inventory.add(1, { name:"NaN物品", value: parseFloat("abc") });
        assert(!addNaN, 
            "NaN value 应判为不合法，添加失败", 
            "尝试添加 NaN value, inventory: " + ObjectUtil.toString(inventory.getItems()));
    }

    /**
     * 测试搜索与数值修改相关方法
     */
    private function testSearchAndValueMethods():Void {
        trace("\n===> 测试 testSearchAndValueMethods (searchFirstKey, searchKeys, addValue) ...");
        var inventory = new ArrayInventory(null, 5);
        inventory.add(0, { name:"AK47", value:2 });
        inventory.add(1, { name:"AK47", value:1 });
        inventory.add(2, { name:"牛肉罐头", value:5 });

        var firstKey:String = inventory.searchFirstKey("AK47");
        assert(firstKey == "0", 
            "searchFirstKey 返回应为第一个 AK47 的格子 (key=0)", 
            "实际返回: " + firstKey);

        var noneKey = inventory.searchFirstKey("不存在的物品");
        assert(noneKey == undefined, 
            "searchFirstKey 对不存在的物品应返回 undefined", 
            "实际返回: " + noneKey);

        var keys:Array = inventory.searchKeys("AK47");
        assert(keys.length == 2, 
            "searchKeys('AK47') 返回应为 [0, 1] 共 2 个格子", 
            "实际返回: " + ObjectUtil.toString(keys));

        var emptyKeys:Array = inventory.searchKeys("没有的物品");
        assert(emptyKeys.length == 0, 
            "searchKeys 对没有物品返回空数组", 
            "实际返回: " + ObjectUtil.toString(emptyKeys));

        // 测试 addValue 增加数量
        inventory.addValue("0", 3);
        var item0:Object = inventory.getItem("0");
        assert(item0.value == 5, 
            "addValue(3) 后物品数量应变为 5", 
            "item0.value: " + item0.value);

        // 测试 addValue 导致数量归零自动 remove
        inventory.addValue("1", -1);
        var item1:Object = inventory.getItem("1");
        assert(item1 == null, 
            "当物品 value <= 0 时应自动 remove", 
            "item1: " + ObjectUtil.toString(item1));
    }

    /**
     * 测试 move、merge、swap 等物品移动操作
     */
    private function testMoveMergeSwap():Void {
        trace("\n===> 测试 testMoveMergeSwap (move/merge/swap) ...");
        var invA = new ArrayInventory(null, 3);
        var invB = new ArrayInventory(null, 3);

        // 准备数据
        invA.add(0, { name:"匕首", value:1 });
        invA.add(1, { name:"普通hp药剂", value:5 });
        invB.add(0, { name:"普通hp药剂", value:5 });
        invB.add(1, { name:"牛肉罐头", value:2 });

        // 1. move 测试：将 invA[1] 移动到 invB[2]
        var moveResult:Boolean = invA.move(invB, "1", "2");
        assert(moveResult, 
            "move 成功，匕首不受影响", 
            "move(invA[1] -> invB[2]) 失败, invA: " + ObjectUtil.toString(invA.getItems()) + ", invB: " + ObjectUtil.toString(invB.getItems()));
        var itemInvB2:Object = invB.getItem("2");
        assert(itemInvB2 != null && itemInvB2.name == "普通hp药剂", 
            "目标格子应成功接收 普通hp药剂", 
            "invB[2]: " + ObjectUtil.toString(itemInvB2));
        assert(invA.getItem("1") == null, 
            "源格子应被清空", 
            "invA[1]: " + ObjectUtil.toString(invA.getItem("1")));

        // 再次尝试移动到已占用的格子应失败
        var failMoveResult:Boolean = invA.move(invB, "0", "0");
        assert(!failMoveResult, 
            "move 到已占用格子应失败", 
            "尝试 move(invA[0] -> invB[0]) 应失败, invB[0]: " + ObjectUtil.toString(invB.getItem("0")));

        // 2. merge 测试：将 invB[2] 的 hp药剂合并到 invB[0]
        var mergeResult:Boolean = invB.merge(invB, "2", "0");
        assert(mergeResult, 
            "merge 同名可叠加物品成功", 
            "merge(invB[2] -> invB[0]) 失败, invB: " + ObjectUtil.toString(invB.getItems()));
        var invB0:Object = invB.getItem("0");
        assert(invB0.value == 10, 
            "merge 后物品数量应累加为 10", 
            "invB[0].value: " + invB0.value);
        assert(invB.getItem("2") == null, 
            "merge 后源格子应被清空", 
            "invB[2]: " + ObjectUtil.toString(invB.getItem("2")));

        // merge 不同物品应失败
        var failMerge:Boolean = invA.merge(invB, "0", "1");
        assert(!failMerge, 
            "merge 不同物品应失败", 
            "尝试 merge(invA[0] 与 invB[1]) 应失败, invA[0]: " + ObjectUtil.toString(invA.getItem("0")) + ", invB[1]: " + ObjectUtil.toString(invB.getItem("1")));

        // 3. swap 测试：交换 invA[0] 和 invB[1]
        var swapResult:Boolean = invA.swap(invB, "0", "1");
        assert(swapResult, 
            "swap 应该成功", 
            "swap(invA[0] 与 invB[1]) 失败, invA: " + ObjectUtil.toString(invA.getItems()) + ", invB: " + ObjectUtil.toString(invB.getItems()));
        var invA0:Object = invA.getItem("0");
        var invB1:Object = invB.getItem("1");
        assert(invA0 != null && invA0.name == "牛肉罐头", 
            "swap 后 invA[0] 应变成牛肉罐头", 
            "invA[0]: " + ObjectUtil.toString(invA0));
        assert(invB1 != null && invB1.name == "匕首", 
            "swap 后 invB[1] 应变成匕首", 
            "invB[1]: " + ObjectUtil.toString(invB1));

        // swap 条件不足，应失败
        var failSwap:Boolean = invA.swap(invB, "1", "0");
        assert(!failSwap, 
            "swap 空格子或不存在物品应失败", 
            "尝试 swap(invA[1] 与 invB[0]) 应失败, invA[1]: " + ObjectUtil.toString(invA.getItem("1")) + ", invB[0]: " + ObjectUtil.toString(invB.getItem("0")));
    }

    /**
     * 测试排序重建方法
     */

    private function testRebuildOrder():Void {
        trace("\n===> 测试 testRebuildOrder ...");
        
        // 场景1：空物品栏重建
        var emptyInv = new ArrayInventory(null, 5);
        emptyInv.rebuildOrder(null);
        assert(emptyInv.getIndexes().length == 0, 
            "空物品栏重建后应保持为空", 
            "indexes: " + ObjectUtil.toString(emptyInv.getIndexes()));

        // 场景2：无排序函数的致密化重建
        var sparseInv = new ArrayInventory(null, 5);
        sparseInv.add(2, {name:"A", value:1});
        sparseInv.add(4, {name:"B", value:2});
        sparseInv.rebuildOrder(null);
        
        var expectedIndexes:Array = [0,1];
        var actualItems:Array = sparseInv.getItemArray();
        var actualNames:Array = [];
        for (var i:Number = 0; i < actualItems.length; i++) {
            actualNames.push(actualItems[i].name);
        }
        assert(actualNames.join(",") == "A,B", 
            "无排序重建应保持原序并压缩空格", 
            "结果: " + actualNames.join(",") + " 预期: A,B");
        assert(sparseInv.getIndexes().toString() == "0,1", 
            "索引应重新映射为连续", 
            "实际索引: " + sparseInv.getIndexes());

        // 场景3：带排序函数的重建（按名称倒序）
        var sortFunc:Function = function(a, b):Number {
            // 修正比较函数，处理所有情况
            if (a.name > b.name) return -1;
            if (a.name < b.name) return 1;
            return 0;
        };
        var sortedInv = new ArrayInventory(null, 5);
        sortedInv.add(0, {name:"C", value:3});
        sortedInv.add(1, {name:"A", value:1});
        sortedInv.add(3, {name:"B", value:2});
        sortedInv.rebuildOrder(sortFunc);
        
        var sortedItems:Array = sortedInv.getItemArray();
        var sortedNames:Array = [];
        for (i = 0; i < sortedItems.length; i++) {
            sortedNames.push(sortedItems[i].name);
        }
        assert(sortedNames.join(",") == "C,B,A", 
            "应按名称倒序排列", 
            "实际顺序: " + sortedNames.join(","));

        // 场景4：容量溢出测试
        var overflowInv = new ArrayInventory(null, 3);
        overflowInv.add(0, {name:"X", value:1});
        overflowInv.add(2, {name:"Y", value:2});
        overflowInv.rebuildOrder(null);
        assert(overflowInv.size() <= 3, 
            "重建后物品数量不应超过容量", 
            "实际数量: " + overflowInv.size());

        // 场景5：混合类型排序（数值型value优先）
        var mixedInv = new ArrayInventory(null, 5);
        mixedInv.add(1, {name:"M", value: {type:"装备"}});
        mixedInv.add(3, {name:"N", value: 15});
        mixedInv.rebuildOrder(function(a, b):Number {
            // 数值value优先
            var aVal = typeof a.value == "number" ? 0 : 1;
            var bVal = typeof b.value == "number" ? 0 : 1;
            return aVal - bVal;
        });
        var mixedTypes:Array = [];
        var mixedItems:Array = mixedInv.getItemArray();
        for (i = 0; i < mixedItems.length; i++) {
            mixedTypes.push(typeof mixedItems[i].value);
        }
        assert(mixedTypes.join(",") == "number,object", 
            "数值类型应排在前面", 
            "实际类型顺序: " + mixedTypes.join(","));

        // 场景6：完全填充后的顺序保持
        var fullInv = new ArrayInventory(null, 3);
        fullInv.add(0, {name:"1", value:1});
        fullInv.add(1, {name:"2", value:2});
        fullInv.add(2, {name:"3", value:3});
        fullInv.rebuildOrder(function(a, b) { return b.value - a.value; }); // 降序
        var descendingValues:Array = [];
        var itemsArray:Array = fullInv.getItemArray();
        for (i = 0; i < itemsArray.length; i++) {
            descendingValues.push(itemsArray[i].value);
        }
        assert(descendingValues.join(",") == "3,2,1", 
            "满容量应按value降序排列", 
            "实际值: " + descendingValues.join(","));
    }


}
