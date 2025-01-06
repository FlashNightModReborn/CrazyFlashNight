import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * Inventory及其附属类的测试类
 * 负责测试Inventory及其附属类的测试类的各种功能
 */

class org.flashNight.arki.item.itemCollection.InventoryTest{

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
     * 包括正确性测试和性能测试。
     */
    public function runTests():Void {
        trace("开始 Inventory 测试...");
        testBasic();
        testRequirement();

        trace("测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
    }

    /**
     * 测试 add, remove, 等基础方法
     */
    private function testBasic():Void {
        trace("\n测试 add 方法...");
        var inventory = new ArrayInventory(null,5);
        inventory.add(0,{name:"普通hp药剂",value:5});
        inventory.add(2,{name:"普通mp药剂",value:5});
        inventory.add(3,{name:"匕首",value:{level:1}});
        inventory.add(4,{name:"AK47",value:{level:7}});
        inventory.add(1,{name:"牛肉罐头",value:2});
        //输出 add 后的物品栏和索引表
        trace(ObjectUtil.toString(inventory.getItems()));
        trace(ObjectUtil.toString(inventory.getIndexes()));
        assert(inventory.getFirstVacancy() == -1,"添加物品后，首个空格 应为-1");
        trace("\n测试 remove 方法...");
        inventory.remove(1);
        inventory.remove(4);
        //输出 remove 后的物品栏和索引表
        trace(ObjectUtil.toString(inventory.getItems()));
        trace(ObjectUtil.toString(inventory.getIndexes()));
        assert(inventory.getFirstVacancy() == 1,"移除物品后，首个空格 应为1");
    }

    /**
     * 测试添加与提交物品函数
     */
    private function testRequirement():Void {
        _root.物品栏 = {
            背包:new ArrayInventory(null,5)
        };
        _root.收集品栏 = {
            材料:new DictCollection(null),
            情报:new DictCollection(null)
        }
        //测试acquire
        var array1 = [
            ["匕首",1],
            ["资料",1],
            ["牛肉罐头",3],
            ["战术导轨",2],
            ["普通hp药剂",5]
        ];
        var itemArray = ItemUtil.getRequirement(array1);
        assert(ItemUtil.acquire(itemArray),"添加3个物品，1个材料和1个情报");
        var array2 = [
            ["普通hp药剂",5],
            ["普通mp药剂",5],
            ["牛肉罐头",1]
        ];
        itemArray = ItemUtil.getRequirement(array2);
        assert(ItemUtil.acquire(itemArray),"添加3个物品，其中2个物品可叠加");
        var array3 = [
            ["普通mp药剂",5],
            ["AK47",1],
            ["AK47",1]
        ];
        itemArray = ItemUtil.getRequirement(array3);
        assert(ItemUtil.acquire(itemArray),"添加3个物品，其中1个物品可叠加，应由于空间不足而添加失败");
        var array4 = [
            ["普通hp药剂",5],
            ["普通mp药剂",5],
            ["战术导轨",1]
        ];
        //输出 acquire 后的物品栏和索引表
        trace(ObjectUtil.toString(_root.物品栏.背包.getItems()));
        trace(ObjectUtil.toString(_root.物品栏.背包.getIndexes()));
        itemArray = ItemUtil.getRequirement(array4);
        //测试submit
        assert(ItemUtil.submit(itemArray),"提交3个物品和1个材料");
        var array5 = [
            ["普通hp药剂",10],
            ["牛肉罐头",1]
        ];
        itemArray = ItemUtil.getRequirement(array5);
        assert(ItemUtil.submit(itemArray),"提交2个物品，应由于物品不足而提交失败");
        //输出 submit 后的物品栏和索引表
        trace(ObjectUtil.toString(_root.物品栏.背包.getItems()));
        trace(ObjectUtil.toString(_root.物品栏.背包.getIndexes()));
        itemArray = ItemUtil.getRequirement(array4);
    }
}
