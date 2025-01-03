// 文件: org/flashNight/gesh/array/ArrayUtilTest.as
import org.flashNight.gesh.array.*;

class org.flashNight.gesh.array.ArrayUtilTest {
    
    // ===========================
    // ====== 测试方法入口 =======
    // ===========================
    
    /**
     * 运行所有测试方法。
     */
    public static function runTests():Void {
        trace("===== ArrayUtil Test Start =====");
        
        testIsArray();
        testForEach();
        testMap();
        testFilter();
        testReduce();
        testSome();
        testEvery();
        testFind();
        testFindIndex();
        testFindLast();
        testFindLastIndex();
        testIndexOf();
        testLastIndexOf();
        testIncludes();
        testFill();
        testRepeat();
        testFlat();
        testFlatMap();
        testFrom();
        testOf();
        testUnion();
        testDifference();
        testUnique();
        testCreate();
        testGroupBy();
        testCountBy();
        testPartition();
        testChunk();
        testZip();
        testUnzip();
        testIntersection();
        testXor();
        testShuffle();
        testCompact();
        testRange();
        testSample();
        testMerge();
        
        trace("===== ArrayUtil Test End =====");
    }
    
    // ===========================
    // ====== 辅助方法 ===========
    // ===========================
    
    /**
     * 简单的断言方法，用于比较预期值与实际值。
     * @param description 测试描述。
     * @param expected 预期结果。
     * @param actual 实际结果。
     */
    private static function assertEqual(description:String, expected, actual):Void {
        // 如果是数组，调用 arraysEqual
        if (ArrayUtil.isArray(expected) && ArrayUtil.isArray(actual)) {
            if (arraysEqual(expected, actual)) {
                trace("[PASS] " + description);
            } else {
                trace("[FAIL] " + description + " | Expected: " + formatOutput(expected) + ", Actual: " + formatOutput(actual));
            }
            return;
        }
        
        // 如果都是对象并且非 null
        if (typeof(expected) == "object" && expected != null &&
            typeof(actual) == "object" && actual != null &&
            !ArrayUtil.isArray(expected) && !ArrayUtil.isArray(actual)) {
            
            if (objectsEqual(expected, actual)) {
                trace("[PASS] " + description);
            } else {
                trace("[FAIL] " + description + " | Expected: " + formatOutput(expected) + ", Actual: " + formatOutput(actual));
            }
            return;
        }
        
        // 否则做简单 === 比较
        if (expected === actual) {
            trace("[PASS] " + description);
        } else {
            trace("[FAIL] " + description + " | Expected: " + formatOutput(expected) + ", Actual: " + formatOutput(actual));
        }
    }

    /**
     * 比较两个对象是否拥有相同的键和值（忽略键的顺序）。
     */
    private static function objectsEqual(obj1:Object, obj2:Object):Boolean {
        // 收集 obj1 全部键
        var keys1:Array = [];
        for (var k1 in obj1) {
            keys1.push(k1);
        }
        // 收集 obj2 全部键
        var keys2:Array = [];
        for (var k2 in obj2) {
            keys2.push(k2);
        }
        // 如果键数不同，直接返回 false
        if (keys1.length != keys2.length) {
            return false;
        }
        // 对键进行排序后挨个比较
        keys1.sort();
        keys2.sort();
        for (var i:Number = 0; i < keys1.length; i++) {
            if (keys1[i] != keys2[i]) {
                return false;
            }
            // 再比较对应值
            var val1 = obj1[keys1[i]];
            var val2 = obj2[keys2[i]];
            // 若是数组，需要 arraysEqual；若是对象，需要 objectsEqual；否则简单 ===
            if (ArrayUtil.isArray(val1) && ArrayUtil.isArray(val2)) {
                if (!arraysEqual(val1, val2)) {
                    return false;
                }
            } else if (typeof(val1) == "object" && val1 != null &&
                    typeof(val2) == "object" && val2 != null) {
                if (!objectsEqual(val1, val2)) {
                    return false;
                }
            } else {
                if (val1 !== val2) {
                    return false;
                }
            }
        }
        return true;
    }

    
    /**
     * 比较两个数组是否相等。
     * @param arr1 第一个数组。
     * @param arr2 第二个数组。
     * @return 如果两个数组长度相同且对应元素相等，则返回 true，否则返回 false。
     */
    private static function arraysEqual(arr1:Array, arr2:Array):Boolean {
        if (arr1.length != arr2.length) {
            return false;
        }
        for (var i:Number = 0; i < arr1.length; i++) {
            if (ArrayUtil.isArray(arr1[i]) && ArrayUtil.isArray(arr2[i])) {
                if (!arraysEqual(arr1[i], arr2[i])) {
                    return false;
                }
            } else if (arr1[i] !== arr2[i]) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * 格式化输出对象，用于更清晰地显示测试结果。
     * @param obj 要格式化的对象。
     * @return 格式化后的字符串。
     */
    private static function formatOutput(obj:Object):String {
        if (ArrayUtil.isArray(obj)) {
            return "[" + obj.join(", ") + "]";
        } else if (typeof(obj) == "object" && obj !== null) {
            var str:String = "{ ";
            for (var key in obj) {
                str += key + ": " + obj[key] + ", ";
            }
            str += "}";
            return str;
        } else {
            return String(obj);
        }
    }
    
    // ===========================
    // ====== 测试方法 ===========
    // ===========================
    
    private static function testIsArray():Void {
        trace("--- Testing isArray ---");
        assertEqual("isArray with Array", true, ArrayUtil.isArray([1,2,3]));
        assertEqual("isArray with Object", false, ArrayUtil.isArray({a:1}));
        assertEqual("isArray with String", false, ArrayUtil.isArray("test"));
        assertEqual("isArray with null", false, ArrayUtil.isArray(null));
        assertEqual("isArray with undefined", false, ArrayUtil.isArray(undefined));
    }
    
    private static function testForEach():Void {
        trace("--- Testing forEach ---");
        var arr:Array = [1, 2, 3, 4, 5];
        var result:Array = [];
        ArrayUtil.forEach(arr, function(element:Object, index:Number, array:Array):Void {
            result.push(element * 2);
        });
        assertEqual("forEach multiplies elements by 2", [2,4,6,8,10], result);
    }
    
    private static function testMap():Void {
        trace("--- Testing map ---");
        var arr:Array = [1, 2, 3, 4, 5];
        var mapped:Array = ArrayUtil.map(arr, function(element:Object, index:Number, array:Array):Object {
            return element * 3;
        });
        assertEqual("map multiplies elements by 3", [3,6,9,12,15], mapped);
    }
    
    private static function testFilter():Void {
        trace("--- Testing filter ---");
        var arr:Array = [1, 2, 3, 4, 5, 6];
        var filtered:Array = ArrayUtil.filter(arr, function(element:Object, index:Number, array:Array):Boolean {
            return element % 2 === 0;
        });
        assertEqual("filter even numbers", [2,4,6], filtered);
    }
    
    private static function testReduce():Void {
        trace("--- Testing reduce ---");
        var arr:Array = [1, 2, 3, 4, 5];
        var sum:Object = ArrayUtil.reduce(arr, function(acc:Object, curr:Object, index:Number, array:Array):Object {
            return acc + curr;
        }, 0);
        assertEqual("reduce sum with initial value 0", 15, sum);
        
        var sumNoInitial:Object = ArrayUtil.reduce(arr, function(acc:Object, curr:Object, index:Number, array:Array):Object {
            return acc + curr;
        });
        assertEqual("reduce sum without initial value", 15, sumNoInitial);
        
        // 测试空数组和无初始值
        var emptyArr:Array = [];
        try {
            var reduceEmpty:Object = ArrayUtil.reduce(emptyArr, function(acc:Object, curr:Object, index:Number, array:Array):Object {
                return acc + curr;
            });
            trace("[FAIL] reduce empty array without initial value did not throw error");
        } catch (e:Error) {
            trace("[PASS] reduce empty array without initial value threw error");
        }
    }
    
    private static function testSome():Void {
        trace("--- Testing some ---");
        var arr:Array = [1, 3, 5, 7, 8];
        var hasEven:Boolean = ArrayUtil.some(arr, function(element:Object, index:Number, array:Array):Boolean {
            return element % 2 === 0;
        });
        assertEqual("some checks for even numbers", true, hasEven);
        
        var arr2:Array = [1, 3, 5, 7];
        var hasEven2:Boolean = ArrayUtil.some(arr2, function(element:Object, index:Number, array:Array):Boolean {
            return element % 2 === 0;
        });
        assertEqual("some checks for even numbers in all odd array", false, hasEven2);
    }
    
    private static function testEvery():Void {
        trace("--- Testing every ---");
        var arr:Array = [2, 4, 6, 8];
        var allEven:Boolean = ArrayUtil.every(arr, function(element:Object, index:Number, array:Array):Boolean {
            return element % 2 === 0;
        });
        assertEqual("every checks all elements are even", true, allEven);
        
        var arr2:Array = [2, 4, 5, 8];
        var allEven2:Boolean = ArrayUtil.every(arr2, function(element:Object, index:Number, array:Array):Boolean {
            return element % 2 === 0;
        });
        assertEqual("every checks all elements are even with one odd", false, allEven2);
        
        var emptyArr:Array = [];
        var allTrue:Boolean = ArrayUtil.every(emptyArr, function(element:Object, index:Number, array:Array):Boolean {
            return false;
        });
        assertEqual("every on empty array returns true", true, allTrue);
    }
    
    private static function testFind():Void {
        trace("--- Testing find ---");
        var arr:Array = [1, 3, 5, 7, 8];
        var found:Object = ArrayUtil.find(arr, function(element:Object, index:Number, array:Array):Boolean {
            return element > 5;
        });
        assertEqual("find first element > 5", 7, found);
        
        var notFound:Object = ArrayUtil.find(arr, function(element:Object, index:Number, array:Array):Boolean {
            return element > 10;
        });
        assertEqual("find element > 10 in array", null, notFound);
    }
    
    private static function testFindIndex():Void {
        trace("--- Testing findIndex ---");
        var arr:Array = [1, 3, 5, 7, 8];
        var index:Number = ArrayUtil.findIndex(arr, function(element:Object, index:Number, array:Array):Boolean {
            return element > 5;
        });
        assertEqual("findIndex first element > 5", 3, index);
        
        var notFoundIndex:Number = ArrayUtil.findIndex(arr, function(element:Object, index:Number, array:Array):Boolean {
            return element > 10;
        });
        assertEqual("findIndex element > 10 in array", -1, notFoundIndex);
    }
    
    private static function testFindLast():Void {
        trace("--- Testing findLast ---");
        var arr:Array = [1, 3, 5, 7, 8, 9];
        var found:Object = ArrayUtil.findLast(arr, function(element:Object, index:Number, array:Array):Boolean {
            return element % 2 === 0;
        });
        assertEqual("findLast even element", 8, found);
        
        var arr2:Array = [1, 3, 5, 7, 9];
        var notFound:Object = ArrayUtil.findLast(arr2, function(element:Object, index:Number, array:Array):Boolean {
            return element % 2 === 0;
        });
        assertEqual("findLast even element in all odd array", null, notFound);
    }
    
    private static function testFindLastIndex():Void {
        trace("--- Testing findLastIndex ---");
        var arr:Array = [1, 3, 5, 7, 8, 9];
        var index:Number = ArrayUtil.findLastIndex(arr, function(element:Object, index:Number, array:Array):Boolean {
            return element % 2 === 0;
        });
        assertEqual("findLastIndex even element", 4, index);
        
        var arr2:Array = [1, 3, 5, 7, 9];
        var notFoundIndex:Number = ArrayUtil.findLastIndex(arr2, function(element:Object, index:Number, array:Array):Boolean {
            return element % 2 === 0;
        });
        assertEqual("findLastIndex even element in all odd array", -1, notFoundIndex);
    }
    
    private static function testIndexOf():Void {
        trace("--- Testing indexOf ---");
        var arr:Array = [1, 2, 3, 2, 1];
        var index:Number = ArrayUtil.indexOf(arr, 2);
        assertEqual("indexOf first occurrence of 2", 1, index);
        
        var notFound:Number = ArrayUtil.indexOf(arr, 4);
        assertEqual("indexOf element not in array", -1, notFound);
    }
    
    private static function testLastIndexOf():Void {
        trace("--- Testing lastIndexOf ---");
        var arr:Array = [1, 2, 3, 2, 1];
        var index:Number = ArrayUtil.lastIndexOf(arr, 2);
        assertEqual("lastIndexOf last occurrence of 2", 3, index);
        
        var notFound:Number = ArrayUtil.lastIndexOf(arr, 4);
        assertEqual("lastIndexOf element not in array", -1, notFound);
    }
    
    private static function testIncludes():Void {
        trace("--- Testing includes ---");
        var arr:Array = [1, 2, 3, NaN];
        var includesTwo:Boolean = ArrayUtil.includes(arr, 2);
        assertEqual("includes element 2", true, includesTwo);
        
        var includesFour:Boolean = ArrayUtil.includes(arr, 4);
        assertEqual("includes element 4", false, includesFour);
        
        var includesNaN:Boolean = ArrayUtil.includes(arr, NaN);
        assertEqual("includes NaN", true, includesNaN);
        
        var includesUndefined:Boolean = ArrayUtil.includes(arr, undefined);
        assertEqual("includes undefined", false, includesUndefined);
    }
    
    private static function testFill():Void {
        trace("--- Testing fill ---");
        var arr:Array = [1, 2, 3, 4, 5];
        var filled:Array = ArrayUtil.fill(arr, 0, 1, 3);
        assertEqual("fill array with 0 from index 1 to 3", [1,0,0,4,5], filled);
        
        var filledFull:Array = ArrayUtil.fill([1,2,3], 9);
        assertEqual("fill entire array with 9", [9,9,9], filledFull);
    }
    
    private static function testRepeat():Void {
        trace("--- Testing repeat ---");
        var arr:Array = [1, 2];
        var repeated:Array = ArrayUtil.repeat(arr, 3);
        assertEqual("repeat [1,2] three times", [1,2,1,2,1,2], repeated);
        
        var emptyRepeated:Array = ArrayUtil.repeat([], 5);
        assertEqual("repeat empty array five times", [], emptyRepeated);
    }
    
    private static function testFlat():Void {
        trace("--- Testing flat ---");
        var nested:Array = [1, [2, [3, 4]], 5];
        var flattened1:Array = ArrayUtil.flat(nested, 1);
        assertEqual("flat nested array with depth 1", [1,2,[3,4],5], flattened1);
        
        var flattened2:Array = ArrayUtil.flat(nested, 2);
        assertEqual("flat nested array with depth 2", [1,2,3,4,5], flattened2);
        
        var flattenedInfinite:Array = ArrayUtil.flat(nested);
        assertEqual("flat nested array with default depth 1", [1,2,[3,4],5], flattenedInfinite);
    }
    
    private static function testFlatMap():Void {
        trace("--- Testing flatMap ---");
        var arr:Array = [1, 2, 3];
        var flatMapped:Array = ArrayUtil.flatMap(arr, function(element:Object, index:Number, array:Array):Array {
            return [element, element * 2];
        });
        assertEqual("flatMap doubles elements", [1,2,2,4,3,6], flatMapped);
        
        var flatMappedNonArray:Array = ArrayUtil.flatMap(arr, function(element:Object, index:Number, array:Array):Object {
            return element * 2;
        });
        assertEqual("flatMap with non-array return", [2,4,6], flatMappedNonArray);
    }
    
    private static function testFrom():Void {
        trace("--- Testing from ---");
        var iterable:String = "hello";
        var fromArr:Array = ArrayUtil.from(iterable);
        assertEqual("from string to array", ["h","e","l","l","o"], fromArr);
        
        var obj:Object = {a:1, b:2, c:3};
        var fromObj:Array = ArrayUtil.from(obj);
        assertEqual("from object to array", [1,2,3], fromObj);
        
        var arr:Array = [4,5,6];
        var fromArrCopy:Array = ArrayUtil.from(arr);
        assertEqual("from array to array (copy)", [4,5,6], fromArrCopy);
    }
    
    private static function testOf():Void {
        trace("--- Testing of ---");
        var ofArr:Array = ArrayUtil.of(1, "a", true);
        assertEqual("of creates array with elements 1, 'a', true", [1, "a", true], ofArr);
        
        var emptyOf:Array = ArrayUtil.of();
        assertEqual("of with no arguments creates empty array", [], emptyOf);
    }
    
    private static function testUnion():Void {
        trace("--- Testing union ---");
        var unionArr:Array = ArrayUtil.union([1, 2], [2, 3], [3, 4]);
        assertEqual("union of [1,2], [2,3], [3,4]", [1,2,3,4], unionArr);
        
        var unionArr2:Array = ArrayUtil.union([], [1], [1,2]);
        assertEqual("union with empty array", [1,2], unionArr2);
    }
    
    private static function testDifference():Void {
        trace("--- Testing difference ---");
        var diffArr:Array = ArrayUtil.difference([1,2,3,4], [2,4]);
        assertEqual("difference [1,2,3,4] - [2,4]", [1,3], diffArr);
        
        var diffArr2:Array = ArrayUtil.difference([1,2,3], []);
        assertEqual("difference [1,2,3] - []", [1,2,3], diffArr2);
    }
    
    private static function testUnique():Void {
        trace("--- Testing unique ---");
        var arr:Array = [1,2,2,3,4,4,5];
        var uniqueArr:Array = ArrayUtil.unique(arr);
        assertEqual("unique [1,2,2,3,4,4,5]", [1,2,3,4,5], uniqueArr);
        
        var arr2:Array = [];
        var uniqueArr2:Array = ArrayUtil.unique(arr2);
        assertEqual("unique on empty array", [], uniqueArr2);
    }
    
    private static function testCreate():Void {
        trace("--- Testing create ---");
        var createdArr:Array = ArrayUtil.create(5, "x");
        assertEqual("create array of length 5 filled with 'x'", ["x","x","x","x","x"], createdArr);
        
        var createdArr2:Array = ArrayUtil.create(0, "y");
        assertEqual("create array of length 0", [], createdArr2);
    }
    
    private static function testGroupBy():Void {
        trace("--- Testing groupBy ---");
        var arr:Array = [6.1, 4.2, 6.3];
        var grouped:Object = ArrayUtil.groupBy(arr, function(num:Number) {
            return Math.floor(num);
        });
        var expected:Object = new Object();
        expected[4] = [4.2];
        expected[6] = [6.1, 6.3];
        assertEqual("groupBy floored numbers", expected, grouped);
    }
    
    private static function testCountBy():Void {
        trace("--- Testing countBy ---");
        var arr:Array = [6.1, 4.2, 6.3];
        var counts:Object = ArrayUtil.countBy(arr, function(num:Number) {
            return Math.floor(num);
        });
        var expected:Object = new Object();
        expected[4] = [1];
        expected[6] = [2];
        assertEqual("countBy floored numbers", expected, counts);
    }
    
    private static function testPartition():Void {
        trace("--- Testing partition ---");
        var arr:Array = [1,2,3,4,5,6];
        var partitioned:Array = ArrayUtil.partition(arr, function(num:Number):Boolean {
            return num % 2 === 0;
        });
        var expected:Array = [[2,4,6], [1,3,5]];
        assertEqual("partition even and odd numbers", expected, partitioned);
    }
    
    private static function testChunk():Void {
        trace("--- Testing chunk ---");
        var arr:Array = [1,2,3,4,5,6,7];
        var chunked:Array = ArrayUtil.chunk(arr, 3);
        var expected:Array = [[1,2,3], [4,5,6], [7]];
        assertEqual("chunk array into size 3", expected, chunked);
        
        var chunked2:Array = ArrayUtil.chunk(arr, 0);
        assertEqual("chunk array with size 0", [], chunked2);
    }
    
    private static function testZip():Void {
        trace("--- Testing zip ---");
        var zipped:Array = ArrayUtil.zip([1,2], ["a","b"], [true, false]);
        var expected:Array = [[1, "a", true], [2, "b", false]];
        assertEqual("zip [1,2], ['a','b'], [true,false]", expected, zipped);
        
        var zipped2:Array = ArrayUtil.zip([1,2,3], ["a","b"], [true]);
        var expected2:Array = [[1, "a", true], [2, "b", undefined], [3, undefined, undefined]];
        assertEqual("zip arrays of different lengths", expected2, zipped2);
    }
    
    private static function testUnzip():Void {
        trace("--- Testing unzip ---");
        var grouped:Array = [[1, "a", true], [2, "b", false]];
        var unzipped:Array = ArrayUtil.unzip(grouped);
        var expected:Array = [[1,2], ["a","b"], [true, false]];
        assertEqual("unzip [[1,'a',true],[2,'b',false]]", expected, unzipped);
        
        var grouped2:Array = [];
        var unzipped2:Array = ArrayUtil.unzip(grouped2);
        var expected2:Array = [];
        assertEqual("unzip empty array", expected2, unzipped2);
    }
    
    private static function testIntersection():Void {
        trace("--- Testing intersection ---");
        var inter:Array = ArrayUtil.intersection([1,2,3], [2,3,4], [3,4,5]);
        assertEqual("intersection of [1,2,3], [2,3,4], [3,4,5]", [3], inter);
        
        var inter2:Array = ArrayUtil.intersection([1,2], [3,4]);
        assertEqual("intersection of [1,2], [3,4]", [], inter2);
    }
    
    private static function testXor():Void {
        trace("--- Testing xor ---");
        var xorRes:Array = ArrayUtil.xor([1,2], [2,3], [3,4]);
        assertEqual("xor of [1,2], [2,3], [3,4]", [1,4], xorRes);
        
        var xorRes2:Array = ArrayUtil.xor([1,1,2], [2,3,3]);
        assertEqual("xor of [1,1,2], [2,3,3]", [1,3], xorRes2);
    }
    
    private static function testShuffle():Void {
        trace("--- Testing shuffle ---");
        var arr:Array = [1,2,3,4,5];
        var shuffled:Array = ArrayUtil.shuffle(arr.concat()); // 复制数组
        var isDifferent:Boolean = !arraysEqual(arr, shuffled);
        trace("[INFO] shuffle produces different order: " + isDifferent);
        // 由于 shuffle 是随机的，无法断言具体结果，只检查顺序是否可能改变
    }
    
    private static function testCompact():Void {
        trace("--- Testing compact ---");
        var arr:Array = [0, 1, false, 2, "", 3, null, 4, undefined, NaN];
        var compacted:Array = ArrayUtil.compact(arr);
        var expected:Array = [1, 2, 3, 4];
        assertEqual("compact removes falsy values", expected, compacted);
        
        var arr2:Array = [false, 0, "", null, undefined, NaN];
        var compacted2:Array = ArrayUtil.compact(arr2);
        var expected2:Array = [];
        assertEqual("compact removes all falsy values", expected2, compacted2);
    }
    
    private static function testRange():Void {
        trace("--- Testing range ---");
        var rangeArr:Array = ArrayUtil.range(0, 5);
        var expected:Array = [0,1,2,3,4];
        assertEqual("range from 0 to 5 with default step", expected, rangeArr);
        
        var rangeArr2:Array = ArrayUtil.range(5, 0, -1);
        var expected2:Array = [5,4,3,2,1];
        assertEqual("range from 5 to 0 with step -1", expected2, rangeArr2);
        
        var rangeArr3:Array = ArrayUtil.range(0, 10, 2);
        var expected3:Array = [0,2,4,6,8];
        assertEqual("range from 0 to 10 with step 2", expected3, rangeArr3);
        
        var rangeArr4:Array = ArrayUtil.range(0, 5, 0);
        var expected4:Array = [];
        assertEqual("range with step 0 returns empty array", expected4, rangeArr4);
    }
    
    private static function testSample():Void {
        trace("--- Testing sample ---");
        var arr:Array = [1,2,3,4,5];
        var singleSample:Object = ArrayUtil.sample(arr);
        trace("[INFO] single sample: " + singleSample);
        // 无法断言具体值，只检查是否在数组内
        var containsSample:Boolean = ArrayUtil.includes(arr, singleSample);
        assertEqual("sample single element is in array", true, containsSample);
        
        var multiSample:Object = ArrayUtil.sample(arr, 3);
        if (ArrayUtil.isArray(multiSample) && multiSample.length == 3) {
            var allIncluded:Boolean = true;
            for (var i:Number = 0; i < multiSample.length; i++) {
                if (!ArrayUtil.includes(arr, multiSample[i])) {
                    allIncluded = false;
                    break;
                }
            }
            assertEqual("sample three elements are in array", true, allIncluded);
        } else {
            trace("[FAIL] sample three elements did not return correct array");
        }
    }
    
    private static function testMerge():Void {
        trace("--- Testing merge ---");
        var target:Array = [1, 2];
        var merged:Array = ArrayUtil.merge(target, [3,4], {a:5, b:6});
        var expected:Array = [1,2,3,4,5,6];
        assertEqual("merge [1,2] with [3,4] and {a:5, b:6}", expected, merged);
        
        var target2:Array = [];
        var merged2:Array = ArrayUtil.merge(target2, [1], {a:2});
        var expected2:Array = [1,2];
        assertEqual("merge empty target with [1] and {a:2}", expected2, merged2);
        
        var target3:Array = [0];
        var merged3:Array = ArrayUtil.merge(target3, [], {a:1});
        var expected3:Array = [0,1];
        assertEqual("merge [0] with empty array and {a:1}", expected3, merged3);
    }
    
    // ===========================
    // ====== 执行测试 ===========
    // ===========================
    
    // 立即运行测试
    private static function init():Void {
        runTests();
    }
    
    // AS2 类初始化
    private function ArrayUtilTest() {
        // 构造函数留空
    }
}
