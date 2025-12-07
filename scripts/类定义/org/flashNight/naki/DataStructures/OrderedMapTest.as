import org.flashNight.naki.DataStructures.*;
import org.flashNight.gesh.iterator.*;
/**
 * @class OrderedMapTest
 * @package org.flashNight.naki.DataStructures
 * @description 全面测试 OrderedMap 类的功能，包括基本操作、批量处理、迭代器和性能
 */
class org.flashNight.naki.DataStructures.OrderedMapTest {
    private var map:OrderedMap;          // 测试用的映射实例
    private var testPassed:Number;       // 通过的测试数量
    private var testFailed:Number;       // 失败的测试数量

    public function OrderedMapTest() {
        testPassed = 0;
        testFailed = 0;
    }

    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            trace("PASS: " + message);
            testPassed++;
        } else {
            trace("FAIL: " + message);
            testFailed++;
        }
    }

    public function runTests():Void {
        trace("\n开始 OrderedMap 测试...");
        testBasicOperations();
        testBatchOperations();
        testTraversalMethods();
        testComparatorChanges();
        testEdgeCases();
        testIterator();
        testPerformance();

        trace("\n测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
    }

    //====================== 基础操作测试 ======================//

    private function testBasicOperations():Void {
        trace("\n[基础操作] 测试 put/get/remove...");
        map = new OrderedMap(stringCompare);

        // 测试插入
        map.put("age", 30);
        map.put("name", "John");
        map.put("email", "john@example.com");
        
        // 验证初始状态
        assert(map.size() == 3, "Size 应变为 3");
        assert(map.getKeySet().size() == 3, "KeySet 大小应为 3");
        
        // 测试更新
        map.put("age", 31);
        assert(map.size() == 3, "更新不应改变 size");
        
        // 测试删除
        assert(map.remove("email"), "应返回删除成功");
        assert(map.size() == 2, "删除后 size 应为 2");
        assert(map.getKeySet().size() == 2, "KeySet 大小应同步更新");
    }


    //====================== 批量操作测试 ======================//

    private function testBatchOperations():Void {
        trace("\n[批量操作] 测试 putAll/loadFromObject...");
        map = new OrderedMap(stringCompare);

        // 测试数组输入
        var arr:Array = [
            {key: "country", value: "USA"},
            {key: "zipcode", value: "10001"}
        ];
        map.putAll(arr);
        assert(map.size() == 2, "数组输入后 size 应为2");
        assert(map.get("country") == "USA", "应正确解析数组输入");

        // 测试Object输入
        var obj:Object = {
            phone: "123-4567",
            address: "Main St."
        };
        map.putAll(obj);
        assert(map.size() == 4, "Object输入后 size 应为4");
        assert(map.get("address") == "Main St.", "应正确解析Object输入");

        // 测试toObject
        var exportObj:Object = map.toObject();
        assert(exportObj.phone == "123-4567", "toObject 应包含所有键值对");
    }

    //====================== 遍历方法测试 ======================//

    private function testTraversalMethods():Void {
        trace("\n[遍历方法] 测试 keys/values/entries...");
        map = new OrderedMap(stringCompare);
        map.putAll({
            a: 1, b: 2, c: 3
        });

        // 测试keys
        var keys:Array = map.keys();
        var expectedKeys:Array = ["a", "b", "c"];
        assert(arraysEqual(keys, expectedKeys), "keys 应返回有序键数组");

        // 测试values
        var values:Array = map.values();
        assert(values[0] == 1 && values[1] == 2, "values 应返回对应值");

        // 测试entries
        var entries:Array = map.entries();
        assert(entries[2].key == "c" && entries[2].value == 3, "entries 应返回完整键值对");

        // 测试forEach
        var count:Number = 0;
        map.forEach(function(k, v) {
            count += v;
        });
        assert(count == 6, "forEach 应遍历所有元素");
    }

    //====================== 比较函数测试 ======================//

    private function testComparatorChanges():Void {
        trace("\n[比较函数] 测试 changeCompareFunction...");
        map = new OrderedMap(stringCompare);
        map.putAll({c:"C", a:"A", b:"B"});

        // 验证初始排序
        var initialKeys:Array = map.keys();
        assert(arraysEqual(initialKeys, ["a","b","c"]), "初始升序排序");

        // 更换为自定义降序比较
        map.changeCompareFunction(function(a:String, b:String):Number {
            if(a > b) return -1;
            if(a < b) return 1;
            return 0;
        });
        
        // 验证新排序
        var keys:Array = map.keys();
        assert(arraysEqual(keys, ["c","b","a"]), "更换后降序排序");
        
        // 验证数据完整性
        assert(map.get("c") == "C", "数据完整性检查");
        assert(map.size() == 3, "数据完整性检查");
        
        // 验证平衡性
        assert(isBalanced(Object(map.getKeySet().getRoot())), "平衡性检查");
    }


    //====================== 边界情况测试 ======================//

    private function testEdgeCases():Void {
        trace("\n[边界情况] 测试极端场景...");
        // 空映射测试
        map = new OrderedMap(stringCompare);
        assert(map.size() == 0, "空映射 size 应为0");
        assert(map.keys().length == 0, "空映射 keys 应为空数组");

        // 删除不存在的键
        assert(!map.remove("nonexistent"), "删除不存在的键应返回false");

        // 最小/最大键测试
        map.putAll({z:1, m:2, a:3});
        assert(map.firstKey() == "a", "firstKey 应返回最小键");
        assert(map.lastKey() == "z", "lastKey 应返回最大键");
    }

    //====================== 迭代器测试 ======================//

    private function testIterator():Void {
        trace("\n[迭代器] 测试 OrderedMapMinimalIterator...");
        map = new OrderedMap(stringCompare);
        map.putAll({a:1, b:2, c:3});

        // 基础迭代测试
        var it:IIterator = map.iterator();
        var count:Number = 0;
        while (it.hasNext()) {
            var entry:Object = it.next()._value;
            count += entry.value;
        }
        assert(count == 6, "迭代器应遍历所有元素");

        // 并发修改检测
        var caughtError:Boolean = false;
        it = map.iterator();
        map.put("d", 4); // 修改映射
        try {
            it.hasNext();
        } catch (e:Error) {
            caughtError = true;
        }
        assert(caughtError, "应检测到并发修改");

        // 重置测试
        it.reset();
        assert(it.hasNext(), "重置后迭代器应重新开始");
    }

    //====================== 性能测试 ======================//

    private function testPerformance():Void {
        trace("\n[性能测试] 评估大规模数据处理...");
        var dataSizes:Array = [100, 1000, 5000];
        var testRounds:Array = [100, 10, 2];

        for (var i:Number = 0; i < dataSizes.length; i++) {
            var size:Number = dataSizes[i];
            var rounds:Number = testRounds[i];
            trace("\n数据量: " + size + " 元素 | 测试轮次: " + rounds);

            var totalInsert:Number = 0;
            var totalLookup:Number = 0;
            var totalIteration:Number = 0;
            var totalConversion:Number = 0;

            for (var j:Number = 0; j < rounds; j++) {
                map = new OrderedMap(stringCompare);

                // 插入性能
                var start:Number = getTimer();
                for (var k:Number = 0; k < size; k++) {
                    map.put("key_" + k, "value_" + k);
                }
                totalInsert += getTimer() - start;

                // 查找性能
                start = getTimer();
                for (k = 0; k < size; k++) {
                    map.get("key_" + k);
                }
                totalLookup += getTimer() - start;

                // 迭代性能
                start = getTimer();
                var it:IIterator = map.iterator();
                while (it.hasNext()) { it.next(); }
                totalIteration += getTimer() - start;

                // 转换性能
                start = getTimer();
                var obj:Object = map.toObject();
                totalConversion += getTimer() - start;
            }

            trace("插入: " + (totalInsert/rounds) + "ms");
            trace("查找: " + (totalLookup/rounds) + "ms");
            trace("迭代: " + (totalIteration/rounds) + "ms");
            trace("转换: " + (totalConversion/rounds) + "ms");
        }
    }

    //====================== 辅助方法 ======================//

    private function stringCompare(a:String, b:String):Number {
        // 手动实现字典序比较
        var len:Number = Math.min(a.length, b.length);
        for (var i:Number = 0; i < len; i++) {
            var charA:Number = a.charCodeAt(i);
            var charB:Number = b.charCodeAt(i);
            if (charA > charB) return 1;
            if (charA < charB) return -1;
        }
        return a.length > b.length ? 1 : (a.length < b.length ? -1 : 0);
    }


    private function arraysEqual(a:Array, b:Array):Boolean {
        if (a.length != b.length) return false;
        for (var i:Number = 0; i < a.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    private function isBalanced(node:TreeNode):Boolean {
        if (node == null) return true;
        
        function checkHeight(n:TreeNode):Number {
            if (n == null) return 0;
            return 1 + Math.max(checkHeight(n.left), checkHeight(n.right));
        }
        
        var leftHeight:Number = checkHeight(node.left);
        var rightHeight:Number = checkHeight(node.right);
        
        if (Math.abs(leftHeight - rightHeight) > 1) return false;
        
        return isBalanced(node.left) && isBalanced(node.right);
    }

}
