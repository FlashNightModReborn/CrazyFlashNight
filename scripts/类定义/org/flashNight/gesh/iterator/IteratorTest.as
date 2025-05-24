// File: org/flashNight/gesh/iterator/IteratorTest.as
import org.flashNight.gesh.iterator.ArrayIterator;
import org.flashNight.gesh.iterator.ObjectIterator;
import org.flashNight.gesh.iterator.TreeSetMinimalIterator;

import org.flashNight.naki.DataStructures.TreeSet;
import org.flashNight.naki.DataStructures.TreeNode;

/**
 * IteratorTest 用于验证多种迭代器 (ArrayIterator, ObjectIterator, TreeSetMinimalIterator)
 * 及其继承自 BaseIterator 的方法是否正确工作。
 */
class org.flashNight.gesh.iterator.IteratorTest {

    /**
     * 运行所有测试。
     */
    public function runTests(): Void {
        // 测试 ArrayIterator
        this.testArrayIteratorForEach();
        this.testArrayIteratorMap();
        this.testArrayIteratorFilter();
        this.testArrayIteratorFind();
        this.testArrayIteratorReduce();
        this.testArrayIteratorSome();
        this.testArrayIteratorEvery();

        // 测试 ObjectIterator
        this.testObjectIteratorForEach();
        this.testObjectIteratorMap();
        this.testObjectIteratorFilter();
        this.testObjectIteratorFind();
        this.testObjectIteratorReduce();
        this.testObjectIteratorSome();
        this.testObjectIteratorEvery();

        // 测试 TreeSetMinimalIterator
        this.testTreeSetMinimalIterator();
        
        trace("所有测试已完成。");
    }

    //--------------------------------------------------------------------------
    //
    //  1) ArrayIterator 测试用例
    //
    //--------------------------------------------------------------------------

    private function testArrayIteratorForEach(): Void {
        trace("\n测试: ArrayIterator - forEach");
        var testArray: Array = [1, 2, 3, 4, 5];
        var iterator: ArrayIterator = new ArrayIterator(testArray);

        var sum: Number = 0;
        iterator.forEach(function(value, index) {
            sum += value;
        });

        if (sum === 15) {
            trace("✓ ArrayIterator forEach 测试通过。");
        } else {
            trace("✗ ArrayIterator forEach 测试失败。预期: 15, 实际: " + sum);
        }
    }

    private function testArrayIteratorMap(): Void {
        trace("\n测试: ArrayIterator - map");
        var testArray: Array = [1, 2, 3, 4, 5];
        var iterator: ArrayIterator = new ArrayIterator(testArray);

        var mapped: Array = iterator.map(function(value, index) {
            return value * 2;
        });
        var expected: Array = [2, 4, 6, 8, 10];

        if (this.arraysEqual(mapped, expected)) {
            trace("✓ ArrayIterator map 测试通过。");
        } else {
            trace("✗ ArrayIterator map 测试失败。预期: " + expected + ", 实际: " + mapped);
        }
    }

    private function testArrayIteratorFilter(): Void {
        trace("\n测试: ArrayIterator - filter");
        var testArray: Array = [1, 2, 3, 4, 5];
        var iterator: ArrayIterator = new ArrayIterator(testArray);

        var filtered: Array = iterator.filter(function(value, index) {
            return value % 2 === 0;  // 筛选偶数
        });
        var expected: Array = [2, 4];

        if (this.arraysEqual(filtered, expected)) {
            trace("✓ ArrayIterator filter 测试通过。");
        } else {
            trace("✗ ArrayIterator filter 测试失败。预期: " + expected + ", 实际: " + filtered);
        }
    }

    private function testArrayIteratorFind(): Void {
        trace("\n测试: ArrayIterator - find");
        var testArray: Array = [1, 2, 3, 4, 5];
        var iterator: ArrayIterator = new ArrayIterator(testArray);

        var found = iterator.find(function(value, index) {
            return value > 3;
        });
        var expected = 4;

        if (found === expected) {
            trace("✓ ArrayIterator find 测试通过。");
        } else {
            trace("✗ ArrayIterator find 测试失败。预期: " + expected + ", 实际: " + found);
        }
    }

    private function testArrayIteratorReduce(): Void {
        trace("\n测试: ArrayIterator - reduce");
        var testArray: Array = [1, 2, 3, 4, 5];
        var iterator: ArrayIterator = new ArrayIterator(testArray);

        var reduced = iterator.reduce(function(acc, value, index) {
            return acc + value;
        }, 0);
        var expected = 15;

        if (reduced === expected) {
            trace("✓ ArrayIterator reduce 测试通过。");
        } else {
            trace("✗ ArrayIterator reduce 测试失败。预期: " + expected + ", 实际: " + reduced);
        }
    }

    private function testArrayIteratorSome(): Void {
        trace("\n测试: ArrayIterator - some");
        var testArray: Array = [1, 2, 3, 4, 5];
        var iterator: ArrayIterator = new ArrayIterator(testArray);

        var hasEven: Boolean = iterator.some(function(value, index) {
            return value % 2 === 0; // 是否存在偶数
        });
        var expected: Boolean = true;

        if (hasEven === expected) {
            trace("✓ ArrayIterator some 测试通过。");
        } else {
            trace("✗ ArrayIterator some 测试失败。预期: " + expected + ", 实际: " + hasEven);
        }
    }

    private function testArrayIteratorEvery(): Void {
        trace("\n测试: ArrayIterator - every");
        var testArray: Array = [1, 2, 3, 4, 5];
        var iterator: ArrayIterator = new ArrayIterator(testArray);

        var allPositive: Boolean = iterator.every(function(value, index) {
            return value > 0;
        });
        var expected: Boolean = true;

        if (allPositive === expected) {
            trace("✓ ArrayIterator every 测试通过。");
        } else {
            trace("✗ ArrayIterator every 测试失败。预期: " + expected + ", 实际: " + allPositive);
        }
    }

    //--------------------------------------------------------------------------
    //
    //  2) ObjectIterator 测试用例
    //
    //--------------------------------------------------------------------------

    private function testObjectIteratorForEach(): Void {
        trace("\n测试: ObjectIterator - forEach");
        var testObj: Object = {a: 1, b: 2, c: 3};
        var iterator: ObjectIterator = new ObjectIterator(testObj);

        var result: String = "";
        iterator.forEach(function(value, index) {
            // value: { key: "a", value: 1 }等
            result += value.key + "=" + value.value + "; ";
        });
        var expected: String = "a=1; b=2; c=3; ";

        if (result === expected) {
            trace("✓ ObjectIterator forEach 测试通过。");
        } else {
            trace("✗ ObjectIterator forEach 测试失败。预期: " + expected + ", 实际: " + result);
        }
    }
    
    private function testObjectIteratorMap(): Void {
        trace("\n测试: ObjectIterator - map");
        var testObj: Object = {a: 1, b: 2, c: 3};
        var iterator: ObjectIterator = new ObjectIterator(testObj);

        var mapped: Array = iterator.map(function(value, index) {
            return value.key + "=" + (value.value * 2);
        });
        var expected: Array = ["a=2", "b=4", "c=6"];

        if (this.arraysEqual(mapped, expected)) {
            trace("✓ ObjectIterator map 测试通过。");
        } else {
            trace("✗ ObjectIterator map 测试失败。预期: " + expected + ", 实际: " + mapped);
        }
    }
    
    private function testObjectIteratorFilter(): Void {
        trace("\n测试: ObjectIterator - filter");
        var testObj: Object = {a: 1, b: 2, c: 3};
        var iterator: ObjectIterator = new ObjectIterator(testObj);

        var filtered: Array = iterator.filter(function(value, index) {
            // 过滤出 value.value 为偶数的项目
            return value.value % 2 === 0;
        });
        var expected: Array = [{key: "b", value: 2}];

        if (this.arraysEqualOfObjects(filtered, expected)) {
            trace("✓ ObjectIterator filter 测试通过。");
        } else {
            trace("✗ ObjectIterator filter 测试失败。预期: [b=2], 实际: " + filtered);
        }
    }

    private function testObjectIteratorFind(): Void {
        trace("\n测试: ObjectIterator - find");
        var testObj: Object = {a: 1, b: 2, c: 3};
        var iterator: ObjectIterator = new ObjectIterator(testObj);

        var found: Object = iterator.find(function(value, index) {
            return value.key === "b";
        });
        // 期望找到: {key: "b", value: 2}
        if (found != null && found.key === "b" && found.value === 2) {
            trace("✓ ObjectIterator find 测试通过。");
        } else {
            trace("✗ ObjectIterator find 测试失败。预期: b=2, 实际: " + found);
        }
    }

    private function testObjectIteratorReduce(): Void {
        trace("\n测试: ObjectIterator - reduce");
        var testObj: Object = {a: 1, b: 2, c: 3};
        var iterator: ObjectIterator = new ObjectIterator(testObj);

        var reduced: String = iterator.reduce(function(acc, value, index) {
            return acc + value.key + "=" + value.value + "; ";
        }, "");
        var expected: String = "a=1; b=2; c=3; ";

        if (reduced === expected) {
            trace("✓ ObjectIterator reduce 测试通过。");
        } else {
            trace("✗ ObjectIterator reduce 测试失败。预期: " + expected + ", 实际: " + reduced);
        }
    }

    private function testObjectIteratorSome(): Void {
        trace("\n测试: ObjectIterator - some");
        var testObj: Object = {a: 1, b: 2, c: 3};
        var iterator: ObjectIterator = new ObjectIterator(testObj);

        // 是否存在 value.value 大于 2 的键值
        var hasLargerThan2: Boolean = iterator.some(function(value, index) {
            return value.value > 2;
        });
        var expected: Boolean = true;

        if (hasLargerThan2 === expected) {
            trace("✓ ObjectIterator some 测试通过。");
        } else {
            trace("✗ ObjectIterator some 测试失败。预期: " + expected + ", 实际: " + hasLargerThan2);
        }
    }

    private function testObjectIteratorEvery(): Void {
        trace("\n测试: ObjectIterator - every");
        var testObj: Object = {a: 1, b: 2, c: 3};
        var iterator: ObjectIterator = new ObjectIterator(testObj);

        // 是否所有 value.value 都大于 0
        var allPositive: Boolean = iterator.every(function(value, index) {
            return value.value > 0;
        });
        var expected: Boolean = true;

        if (allPositive === expected) {
            trace("✓ ObjectIterator every 测试通过。");
        } else {
            trace("✗ ObjectIterator every 测试失败。预期: " + expected + ", 实际: " + allPositive);
        }
    }

    //--------------------------------------------------------------------------
    //
    //  3) TreeSetMinimalIterator 测试用例
    //
    //--------------------------------------------------------------------------

    private function testTreeSetMinimalIterator(): Void {
        trace("\n测试: TreeSetMinimalIterator");

        // 定义一个简单的对象数组，用于插入到 TreeSet
        var people:Array = [
            {id: 3, name: "C"},
            {id: 1, name: "A"},
            {id: 2, name: "B"},
            {id: 5, name: "E"},
            {id: 4, name: "D"}
        ];

        // 以 "按 id 升序" 的逻辑创建 TreeSet
        var compareFn:Function = compareObjectsById;
        var treeSet:TreeSet = TreeSet.buildFromArray(people, compareFn);

        // 获取迭代器
        var iterator:TreeSetMinimalIterator = new TreeSetMinimalIterator(treeSet);

        // 1) 测试 forEach
        var result:String = "";
        iterator.forEach(function(obj, idx) {
            // obj 即插入的对象 {id, name}
            // 按 id 升序访问: 1->2->3->4->5
            result += obj.id + obj.name + " ";
        });
        // 预期: "1A 2B 3C 4D 5E "
        var expected:String = "1A 2B 3C 4D 5E ";
        if (result === expected) {
            trace("✓ TreeSetMinimalIterator forEach 测试通过。");
        } else {
            trace("✗ TreeSetMinimalIterator forEach 测试失败。预期: " + expected + ", 实际: " + result);
        }

        // 2) 测试 map
        iterator.reset();
        var names:Array = iterator.map(function(obj, idx) {
            return obj.name;
        });
        // 预期: ["A", "B", "C", "D", "E"]
        var nameExpected:Array = ["A", "B", "C", "D", "E"];
        if (this.arraysEqual(names, nameExpected)) {
            trace("✓ TreeSetMinimalIterator map 测试通过。");
        } else {
            trace("✗ TreeSetMinimalIterator map 测试失败。预期: " + nameExpected + ", 实际: " + names);
        }

        // 3) 测试 filter
        iterator.reset();
        var filtered:Array = iterator.filter(function(obj, idx) {
            // 取 id 为偶数的对象
            return (obj.id % 2) === 0;
        });
        // 预期: [{id:2, name:"B"}, {id:4, name:"D"}]
        var filteredOK:Boolean = (filtered.length === 2 && filtered[0].id === 2 && filtered[1].id === 4);
        if (filteredOK) {
            trace("✓ TreeSetMinimalIterator filter 测试通过。");
        } else {
            trace("✗ TreeSetMinimalIterator filter 测试失败。");
        }

        // 4) 测试 find
        iterator.reset();
        var found:Object = iterator.find(function(obj, idx) {
            return obj.id === 4;
        });
        if (found != null && found.id === 4 && found.name === "D") {
            trace("✓ TreeSetMinimalIterator find 测试通过。");
        } else {
            trace("✗ TreeSetMinimalIterator find 测试失败。");
        }

        // 5) 测试 reduce
        iterator.reset();
        var idSum:Number = iterator.reduce(function(acc, obj, idx) {
            return acc + obj.id;
        }, 0);
        // 1+2+3+4+5 = 15
        if (idSum === 15) {
            trace("✓ TreeSetMinimalIterator reduce 测试通过。");
        } else {
            trace("✗ TreeSetMinimalIterator reduce 测试失败。预期: 15, 实际: " + idSum);
        }

        // 6) 测试 some
        iterator.reset();
        var hasNameB:Boolean = iterator.some(function(obj, idx) {
            return obj.name === "B";
        });
        if (hasNameB === true) {
            trace("✓ TreeSetMinimalIterator some 测试通过。");
        } else {
            trace("✗ TreeSetMinimalIterator some 测试失败。应存在 name=B");
        }

        // 7) 测试 every
        iterator.reset();
        var allValid:Boolean = iterator.every(function(obj, idx) {
            // 简单检查 id >= 1
            return obj.id >= 1;
        });
        if (allValid === true) {
            trace("✓ TreeSetMinimalIterator every 测试通过。");
        } else {
            trace("✗ TreeSetMinimalIterator every 测试失败。");
        }
    }

    //--------------------------------------------------------------------------
    //
    //  工具方法
    //
    //--------------------------------------------------------------------------

    /**
     * 比较函数示例：按对象的 id 升序比较。
     * 如果对象没有 id，则退化为字符串比较。
     */
    private function compareObjectsById(a:Object, b:Object):Number {
        // 缺少 id => 退化为字符串比较
        if (a.id == undefined || b.id == undefined) {
            var as:String = String(a);
            var bs:String = String(b);
            if (as < bs) return -1;
            if (as > bs) return 1;
            return 0;
        }

        // 按 id 升序
        if (a.id < b.id) return -1;
        if (a.id > b.id) return 1;
        return 0;
    }

    /**
     * 辅助方法：比较两个纯值数组是否相等。
     */
    private function arraysEqual(arr1: Array, arr2: Array): Boolean {
        if (arr1.length !== arr2.length) {
            return false;
        }
        for (var i: Number = 0; i < arr1.length; i++) {
            if (arr1[i] !== arr2[i]) {
                return false;
            }
        }
        return true;
    }

    /**
     * 辅助方法：比较两个「对象数组」的长度与 key/value 是否相同。
     * （仅适用于小规模测试示例）
     */
    private function arraysEqualOfObjects(arr1: Array, arr2: Array): Boolean {
        if (arr1.length !== arr2.length) {
            return false;
        }
        for (var i: Number = 0; i < arr1.length; i++) {
            var o1:Object = arr1[i];
            var o2:Object = arr2[i];
            // 简易比对
            if (o1.key !== o2.key || o1.value !== o2.value) {
                return false;
            }
        }
        return true;
    }
}
