import org.flashNight.arki.item.ItemSortUtil;
import org.flashNight.arki.item.itemCollection.ArrayInventory;

/**
 * ItemSortUtil 的测试类，验证排序功能是否正确
 */
class org.flashNight.arki.item.ItemSortUtilTest {

    private var testPassed:Number;
    private var testFailed:Number;

    public function ItemSortUtilTest() {
        testPassed = 0;
        testFailed = 0;
    }

    /**
     * 断言函数
     * @param condition 条件
     * @param message 测试描述
     * @param details 错误详情（可选）
     */
    private function assert(condition:Boolean, message:String, details:String):Void {
        if (condition) {
            trace("PASS: " + message);
            testPassed++;
        } else {
            trace("FAIL: " + message);
            if (details) trace("DETAILS: " + details);
            testFailed++;
        }
    }

    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("开始 ItemSortUtil 测试...");

        testDefaultSort();
        testSortByName();
        testSortByType();
        testSortByValue();
        testEmptyInventory();
        testEdgeCases();

        trace("测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个");
    }

    /**
     * 测试默认排序（不改变顺序，仅压缩空格）
     */
    private function testDefaultSort():Void {
        trace("\n===> 测试 testDefaultSort ...");
        var inv:ArrayInventory = new ArrayInventory(null, 5);
        inv.add(2, {name:"C", value:3});
        inv.add(4, {name:"A", value:1});
        inv.add(1, {name:"B", value:2});

        // 默认排序应保持原序，但压缩空格
        ItemSortUtil.sortInventory(inv, "default");
        var items:Array = inv.getItemArray();
        var names:Array = items.map(function(item) { return item.name; });

        assert(
            names.join(",") == "C,B,A",
            "默认排序应保持原序并压缩空格",
            "实际顺序: " + names.join(",") + "，预期: C,B,A"
        );
    }

    /**
     * 测试按名称排序
     */
    private function testSortByName():Void {
        trace("\n===> 测试 testSortByName ...");
        var inv:ArrayInventory = new ArrayInventory(null, 5);
        inv.add(0, {name:"Zebra", value:1});
        inv.add(1, {name:"Apple", value:2});
        inv.add(2, {name:"Banana", value:3});

        // 按名称升序
        ItemSortUtil.sortInventory(inv, "sortByNameAsc");
        var items:Array = inv.getItemArray();
        var names:Array = items.map(function(item) { return item.name; });

        assert(
            names.join(",") == "Apple,Banana,Zebra",
            "按名称升序排列",
            "实际顺序: " + names.join(",")
        );

        // 按名称降序
        ItemSortUtil.sortInventory(inv, "sortByNameDesc");
        items = inv.getItemArray();
        names = items.map(function(item) { return item.name; });

        assert(
            names.join(",") == "Zebra,Banana,Apple",
            "按名称降序排列",
            "实际顺序: " + names.join(",")
        );
    }

    /**
     * 测试按类型排序（假设类型在 itemDataDict 中定义）
     */
    private function testSortByType():Void {
        trace("\n===> 测试 testSortByType ...");
        // 假设已初始化 ItemUtil.itemDataDict（如武器、消耗品等）
        var inv:ArrayInventory = new ArrayInventory(null, 5);
        inv.add(0, {name:"AK47", value:1});      // 类型：武器
        inv.add(1, {name:"牛肉罐头", value:2});   // 类型：消耗品
        inv.add(2, {name:"匕首", value:3});       // 类型：武器

        // 按类型排序（武器在前）
        ItemSortUtil.sortInventory(inv, "sortByType");
        var items:Array = inv.getItemArray();
        var types:Array = items.map(function(item) {
            return ItemUtil.itemDataDict[item.name].type;
        });

        assert(
            types.join(",") == "武器,武器,消耗品",
            "按类型排序（武器在前）",
            "实际类型顺序: " + types.join(",")
        );
    }

    /**
     * 测试按数值 Value 排序
     */
    private function testSortByValue():Void {
        trace("\n===> 测试 testSortByValue ...");
        var inv:ArrayInventory = new ArrayInventory(null, 5);
        inv.add(0, {name:"A", value:10});
        inv.add(1, {name:"B", value:5});
        inv.add(2, {name:"C", value:20});

        // 按 Value 降序
        ItemSortUtil.sortInventory(inv, "sortByValueDesc");
        var values:Array = inv.getItemArray().map(function(item) { return item.value; });

        assert(
            values.join(",") == "20,10,5",
            "按 Value 降序排列",
            "实际顺序: " + values.join(",")
        );

        // 按 Value 升序
        ItemSortUtil.sortInventory(inv, "sortByValueAsc");
        values = inv.getItemArray().map(function(item) { return item.value; });

        assert(
            values.join(",") == "5,10,20",
            "按 Value 升序排列",
            "实际顺序: " + values.join(",")
        );
    }

    /**
     * 测试空物品栏排序
     */
    private function testEmptyInventory():Void {
        trace("\n===> 测试 testEmptyInventory ...");
        var inv:ArrayInventory = new ArrayInventory(null, 5);

        ItemSortUtil.sortInventory(inv, "sortByNameAsc");
        assert(
            inv.size() == 0,
            "空物品栏排序后应保持为空",
            "实际物品数量: " + inv.size()
        );
    }

    /**
     * 测试边界情况（如相同名称、相同 Value）
     */
    private function testEdgeCases():Void {
        trace("\n===> 测试 testEdgeCases ...");
        var inv:ArrayInventory = new ArrayInventory(null, 5);
        inv.add(0, {name:"A", value:5});
        inv.add(1, {name:"A", value:5}); // 相同名称和 Value
        inv.add(2, {name:"B", value:5}); // 相同 Value 不同名称

        // 按名称升序 + Value 降序
        ItemSortUtil.sortInventory(inv, "sortByNameAscValueDesc");
        var items:Array = inv.getItemArray();
        var keys:Array = inv.getIndexes();

        // 预期顺序：A(5) -> A(5) -> B(5)
        assert(
            items[0].name == "A" && items[1].name == "A" && items[2].name == "B",
            "相同名称和 Value 时应保持原序",
            "实际顺序: " + items.map(function(item) { return item.name; }).join(",")
        );
    }
}
