import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * ObjectUtilTest 类
 * 全面测试 ObjectUtil 的功能、性能和边界情况
 */
class org.flashNight.gesh.object.ObjectUtilTest {
    private var _testPassed:Number;
    private var _testFailed:Number;

    public function ObjectUtilTest() {
        this._testPassed = 0;
        this._testFailed = 0;
        trace("=== ObjectUtil Test Suite Initialized ===");
    }

    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("=== Running ObjectUtil Tests ===\n");

        // ========== clone 方法测试 ==========
        this.testCloneSimpleObject();
        this.testCloneNestedObject();
        this.testCloneArray();
        this.testCloneDate();
        this.testCloneCircularReference();
        this.testCloneNull();
        this.testClonePrimitives();

        // ========== cloneFast 方法测试 ==========
        this.testCloneFastSimpleObject();
        this.testCloneFastNestedObject();
        this.testCloneFastArray();
        this.testCloneFastDate();

        // ========== cloneParameters 方法测试 ==========
        this.testCloneParametersFromObject();
        this.testCloneParametersFromString();
        this.testCloneParametersStringWithBoolean();
        this.testCloneParametersStringWithNumber();

        // ========== forEach 方法测试 ==========
        this.testForEachBasic();
        this.testForEachWithNull();
        this.testForEachWithEmptyObject();
        this.testForEachIgnoresPrototype();

        // ========== compare 方法测试 ==========
        this.testCompareNumbers();
        this.testCompareStrings();
        this.testCompareArrays();
        this.testCompareObjects();
        this.testCompareWithNull();
        this.testCompareDifferentTypes();
        this.testCompareCircularReference();

        // ========== hasProperties 方法测试 ==========
        this.testHasPropertiesTrue();
        this.testHasPropertiesFalse();

        // ========== isSimple 方法测试 ==========
        this.testIsSimpleNumber();
        this.testIsSimpleString();
        this.testIsSimpleBoolean();
        this.testIsSimpleObject();
        this.testIsSimpleArray();

        // ========== toString 方法测试 ==========
        this.testToStringSimpleObject();
        this.testToStringNestedObject();
        this.testToStringArray();
        this.testToStringCircularReference();
        this.testToStringMaxDepth();
        this.testToStringFunction();
        this.testToStringNull();

        // ========== isInternalKey 方法测试 ==========
        this.testIsInternalKeyTrue();
        this.testIsInternalKeyFalse();

        // ========== copyProperties 方法测试 ==========
        this.testCopyPropertiesBasic();
        this.testCopyPropertiesWithNull();
        this.testCopyPropertiesIgnoresInternalKeys();

        // ========== getKeys 方法测试 ==========
        this.testGetKeysBasic();
        this.testGetKeysEmpty();
        this.testGetKeysIgnoresInternalKeys();

        // ========== toArray 方法测试 ==========
        this.testToArrayWithArray();
        this.testToArrayWithObject();
        this.testToArrayWithNull();
        this.testToArrayWithPrimitive();

        // ========== equals 方法测试 ==========
        this.testEqualsIdentical();
        this.testEqualsDifferent();
        this.testEqualsNestedObjects();
        this.testEqualsArrays();
        this.testEqualsWithNull();
        this.testEqualsCircularReference();

        // ========== size 方法测试 ==========
        this.testSizeBasic();
        this.testSizeEmpty();
        this.testSizeIgnoresInternalKeys();

        // ========== deepEquals 方法测试 ==========
        this.testDeepEqualsBasic();
        this.testDeepEqualsNested();

        // ========== JSON 序列化测试 ==========
        this.testToJSONBasic();
        this.testToJSONPretty();
        this.testFromJSONBasic();
        this.testFromJSONInvalid();
        this.testJSONRoundTrip();

        // ========== Base64 序列化测试 ==========
        this.testToBase64Basic();
        this.testFromBase64Basic();
        this.testBase64RoundTrip();

        // ========== FNTL 序列化测试 ==========
        this.testToFNTLBasic();
        this.testFromFNTLBasic();
        this.testFNTLRoundTrip();
        this.testToFNTLSingleLine();

        // ========== TOML 序列化测试 ==========
        this.testToTOMLBasic();
        this.testFromTOMLBasic();
        this.testTOMLRoundTrip();

        // ========== Compress 序列化测试 ==========
        this.testToCompressBasic();
        this.testFromCompressBasic();
        this.testCompressRoundTrip();

        // ========== 边界情况测试 ==========
        this.testEmptyObject();
        this.testDeeplyNestedObject();
        this.testLargeObject();
        this.testSpecialCharactersInKeys();
        this.testUnicodeValues();

        // ========== 性能测试 ==========
        this.testClonePerformance();
        this.testComparePerformance();
        this.testToStringPerformance();
        this.testSerializationPerformance();

        // 最终报告
        this.printFinalReport();
    }

    /**
     * 断言函数
     */
    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            this._testPassed++;
            trace("[PASS] " + message);
        } else {
            this._testFailed++;
            trace("[FAIL] " + message);
        }
    }

    /**
     * 时间测量辅助函数
     */
    private function measureTime(func:Function, iterations:Number):Number {
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            func.call(this);
        }
        return getTimer() - startTime;
    }

    // ==================== clone 方法测试 ====================

    private function testCloneSimpleObject():Void {
        trace("\n--- Test: clone - Simple Object ---");
        var obj:Object = {name: "Test", age: 25};
        var cloned:Object = ObjectUtil.clone(obj);

        this.assert(cloned != obj, "Cloned object is a different reference");
        this.assert(cloned.name == "Test", "Cloned name property correct");
        this.assert(cloned.age == 25, "Cloned age property correct");

        // 修改原对象不影响克隆
        obj.name = "Modified";
        this.assert(cloned.name == "Test", "Clone is independent from original");
    }

    private function testCloneNestedObject():Void {
        trace("\n--- Test: clone - Nested Object ---");
        var obj:Object = {
            name: "Parent",
            child: {
                name: "Child",
                value: 100
            }
        };
        var cloned:Object = ObjectUtil.clone(obj);

        this.assert(cloned.child != obj.child, "Nested object is deep cloned");
        this.assert(cloned.child.name == "Child", "Nested property correct");

        obj.child.name = "Modified Child";
        this.assert(cloned.child.name == "Child", "Deep clone is independent");
    }

    private function testCloneArray():Void {
        trace("\n--- Test: clone - Array ---");
        var arr:Array = [1, 2, 3, {x: 10}];
        var cloned:Object = ObjectUtil.clone(arr);

        this.assert(cloned != arr, "Cloned array is different reference");
        this.assert(cloned.length == 4, "Array length preserved");
        this.assert(cloned[0] == 1, "Array element correct");
        this.assert(cloned[3].x == 10, "Nested object in array cloned");
        this.assert(cloned[3] != arr[3], "Nested object is deep cloned");
    }

    private function testCloneDate():Void {
        trace("\n--- Test: clone - Date ---");
        var date:Date = new Date(2024, 0, 15, 12, 30, 45);
        var cloned:Object = ObjectUtil.clone(date);

        this.assert(cloned != date, "Cloned date is different reference");
        this.assert(cloned.getTime() == date.getTime(), "Date time value preserved");
    }

    private function testCloneCircularReference():Void {
        trace("\n--- Test: clone - Circular Reference ---");
        var obj:Object = {name: "Root"};
        obj.self = obj;

        var cloned:Object = ObjectUtil.clone(obj);

        this.assert(cloned.name == "Root", "Root property cloned");
        this.assert(cloned.self == cloned, "Circular reference preserved in clone");
        this.assert(cloned.self != obj, "Circular reference points to clone, not original");
    }

    private function testCloneNull():Void {
        trace("\n--- Test: clone - Null ---");
        var result:Object = ObjectUtil.clone(null);
        this.assert(result == null, "Cloning null returns null");
    }

    private function testClonePrimitives():Void {
        trace("\n--- Test: clone - Primitives ---");
        this.assert(ObjectUtil.clone(42) == 42, "Number cloned correctly");
        this.assert(ObjectUtil.clone("hello") == "hello", "String cloned correctly");
        this.assert(ObjectUtil.clone(true) == true, "Boolean cloned correctly");
    }

    // ==================== cloneFast 方法测试 ====================

    private function testCloneFastSimpleObject():Void {
        trace("\n--- Test: cloneFast - Simple Object ---");
        var obj:Object = {name: "Test", age: 25};
        var cloned:Object = ObjectUtil.cloneFast(obj);

        this.assert(cloned != obj, "CloneFast: different reference");
        this.assert(cloned.name == "Test", "CloneFast: name correct");
        this.assert(cloned.age == 25, "CloneFast: age correct");

        obj.name = "Modified";
        this.assert(cloned.name == "Test", "CloneFast: independent copy");
    }

    private function testCloneFastNestedObject():Void {
        trace("\n--- Test: cloneFast - Nested Object ---");
        var obj:Object = {outer: {inner: {value: 100}}};
        var cloned:Object = ObjectUtil.cloneFast(obj);

        this.assert(cloned.outer != obj.outer, "CloneFast: nested is deep cloned");
        this.assert(cloned.outer.inner.value == 100, "CloneFast: nested value correct");

        obj.outer.inner.value = 999;
        this.assert(cloned.outer.inner.value == 100, "CloneFast: nested is independent");
    }

    private function testCloneFastArray():Void {
        trace("\n--- Test: cloneFast - Array ---");
        var arr:Array = [1, 2, {x: 10}, [3, 4]];
        var cloned:Object = ObjectUtil.cloneFast(arr);

        this.assert(cloned != arr, "CloneFast: array different reference");
        this.assert(cloned.length == 4, "CloneFast: array length correct");
        this.assert(cloned[2].x == 10, "CloneFast: nested object in array");
        this.assert(cloned[3][0] == 3, "CloneFast: nested array correct");
    }

    private function testCloneFastDate():Void {
        trace("\n--- Test: cloneFast - Date ---");
        var date:Date = new Date(2024, 5, 15);
        var cloned:Object = ObjectUtil.cloneFast(date);

        this.assert(cloned != date, "CloneFast: date different reference");
        this.assert(cloned.getTime() == date.getTime(), "CloneFast: date value preserved");
    }

    // ==================== cloneParameters 方法测试 ====================

    private function testCloneParametersFromObject():Void {
        trace("\n--- Test: cloneParameters - From Object ---");
        var target:Object = {existing: "value"};
        var params:Object = {newProp: 123, nested: {a: 1}};

        ObjectUtil.cloneParameters(target, params);

        this.assert(target.newProp == 123, "New property added");
        this.assert(target.nested.a == 1, "Nested property cloned");
        this.assert(target.existing == "value", "Existing property preserved");
    }

    private function testCloneParametersFromString():Void {
        trace("\n--- Test: cloneParameters - From String ---");
        var target:Object = {};
        var paramString:String = "name:Test,value:100";

        ObjectUtil.cloneParameters(target, paramString);

        this.assert(target.name == "Test", "String property parsed");
        this.assert(target.value == 100, "Number value parsed from string");
    }

    private function testCloneParametersStringWithBoolean():Void {
        trace("\n--- Test: cloneParameters - String with Boolean ---");
        var target:Object = {};
        var paramString:String = "enabled:true,disabled:false";

        ObjectUtil.cloneParameters(target, paramString);

        this.assert(target.enabled === true, "Boolean true parsed");
        this.assert(target.disabled === false, "Boolean false parsed");
    }

    private function testCloneParametersStringWithNumber():Void {
        trace("\n--- Test: cloneParameters - String with Number ---");
        var target:Object = {};
        var paramString:String = "count:42,ratio:3.14,text:hello";

        ObjectUtil.cloneParameters(target, paramString);

        this.assert(target.count == 42, "Integer parsed");
        this.assert(target.ratio == 3.14, "Float parsed");
        this.assert(target.text == "hello", "Text preserved as string");
    }

    // ==================== forEach 方法测试 ====================

    private function testForEachBasic():Void {
        trace("\n--- Test: forEach - Basic ---");
        var obj:Object = {a: 1, b: 2, c: 3};
        var sum:Number = 0;
        var keys:Array = [];

        ObjectUtil.forEach(obj, function(key:String, value:Object):Void {
            sum += Number(value);
            keys.push(key);
        });

        this.assert(sum == 6, "All values iterated and summed");
        this.assert(keys.length == 3, "All keys visited");
    }

    private function testForEachWithNull():Void {
        trace("\n--- Test: forEach - With Null ---");
        var callCount:Number = 0;

        ObjectUtil.forEach(null, function(key:String, value:Object):Void {
            callCount++;
        });

        this.assert(callCount == 0, "Callback not called for null object");
    }

    private function testForEachWithEmptyObject():Void {
        trace("\n--- Test: forEach - Empty Object ---");
        var callCount:Number = 0;

        ObjectUtil.forEach({}, function(key:String, value:Object):Void {
            callCount++;
        });

        this.assert(callCount == 0, "Callback not called for empty object");
    }

    private function testForEachIgnoresPrototype():Void {
        trace("\n--- Test: forEach - Ignores Prototype ---");
        var obj:Object = {ownProp: "value"};
        var keys:Array = [];

        ObjectUtil.forEach(obj, function(key:String, value:Object):Void {
            keys.push(key);
        });

        this.assert(keys.length == 1, "Only own properties iterated");
        this.assert(keys[0] == "ownProp", "Own property found");
    }

    // ==================== compare 方法测试 ====================

    private function testCompareNumbers():Void {
        trace("\n--- Test: compare - Numbers ---");
        this.assert(ObjectUtil.compare(10, 20, null) == -1, "10 < 20");
        this.assert(ObjectUtil.compare(20, 10, null) == 1, "20 > 10");
        this.assert(ObjectUtil.compare(15, 15, null) == 0, "15 == 15");
    }

    private function testCompareStrings():Void {
        trace("\n--- Test: compare - Strings ---");
        this.assert(ObjectUtil.compare("abc", "xyz", null) == -1, "abc < xyz");
        this.assert(ObjectUtil.compare("xyz", "abc", null) == 1, "xyz > abc");
        this.assert(ObjectUtil.compare("hello", "hello", null) == 0, "hello == hello");
    }

    private function testCompareArrays():Void {
        trace("\n--- Test: compare - Arrays ---");
        this.assert(ObjectUtil.compare([1, 2], [1, 2, 3], null) == -1, "Shorter array < longer array");
        this.assert(ObjectUtil.compare([1, 2, 3], [1, 2], null) == 1, "Longer array > shorter array");
        this.assert(ObjectUtil.compare([1, 2, 3], [1, 2, 3], null) == 0, "Equal arrays");
        this.assert(ObjectUtil.compare([1, 2, 3], [1, 2, 4], null) == -1, "Element comparison");
    }

    private function testCompareObjects():Void {
        trace("\n--- Test: compare - Objects ---");
        var obj1:Object = {a: 1, b: 2};
        var obj2:Object = {a: 1, b: 3};
        var obj3:Object = {a: 1, b: 2};

        this.assert(ObjectUtil.compare(obj1, obj2, null) == -1, "obj1 < obj2 (different values)");
        this.assert(ObjectUtil.compare(obj1, obj3, null) == 0, "obj1 == obj3 (same values)");
    }

    private function testCompareWithNull():Void {
        trace("\n--- Test: compare - With Null ---");
        this.assert(ObjectUtil.compare(null, {a: 1}, null) == -1, "null < object");
        this.assert(ObjectUtil.compare({a: 1}, null, null) == 1, "object > null");
        this.assert(ObjectUtil.compare(null, null, null) == 0, "null == null");
    }

    private function testCompareDifferentTypes():Void {
        trace("\n--- Test: compare - Different Types ---");
        var result:Number = ObjectUtil.compare("string", 123, null);
        this.assert(result != 0, "Different types are not equal");
    }

    private function testCompareCircularReference():Void {
        trace("\n--- Test: compare - Circular Reference ---");
        var obj1:Object = {name: "A"};
        obj1.self = obj1;
        var obj2:Object = {name: "A"};
        obj2.self = obj2;

        // 应该能处理循环引用而不崩溃
        var result:Number = ObjectUtil.compare(obj1, obj2, null);
        this.assert(result == 0, "Circular references handled in comparison");
    }

    // ==================== hasProperties 方法测试 ====================

    private function testHasPropertiesTrue():Void {
        trace("\n--- Test: hasProperties - True ---");
        var obj:Object = {a: 1};
        this.assert(ObjectUtil.hasProperties(obj) == true, "Object with properties returns true");
    }

    private function testHasPropertiesFalse():Void {
        trace("\n--- Test: hasProperties - False ---");
        var obj:Object = {};
        this.assert(ObjectUtil.hasProperties(obj) == false, "Empty object returns false");
    }

    // ==================== isSimple 方法测试 ====================

    private function testIsSimpleNumber():Void {
        trace("\n--- Test: isSimple - Number ---");
        this.assert(ObjectUtil.isSimple(42) == true, "Number is simple");
        this.assert(ObjectUtil.isSimple(3.14) == true, "Float is simple");
    }

    private function testIsSimpleString():Void {
        trace("\n--- Test: isSimple - String ---");
        this.assert(ObjectUtil.isSimple("hello") == true, "String is simple");
        this.assert(ObjectUtil.isSimple("") == true, "Empty string is simple");
    }

    private function testIsSimpleBoolean():Void {
        trace("\n--- Test: isSimple - Boolean ---");
        this.assert(ObjectUtil.isSimple(true) == true, "True is simple");
        this.assert(ObjectUtil.isSimple(false) == true, "False is simple");
    }

    private function testIsSimpleObject():Void {
        trace("\n--- Test: isSimple - Object ---");
        this.assert(ObjectUtil.isSimple({}) == false, "Object is not simple");
        this.assert(ObjectUtil.isSimple({a: 1}) == false, "Object with props is not simple");
    }

    private function testIsSimpleArray():Void {
        trace("\n--- Test: isSimple - Array ---");
        this.assert(ObjectUtil.isSimple([]) == false, "Array is not simple");
        this.assert(ObjectUtil.isSimple([1, 2, 3]) == false, "Array with elements is not simple");
    }

    // ==================== toString 方法测试 ====================

    private function testToStringSimpleObject():Void {
        trace("\n--- Test: toString - Simple Object ---");
        var obj:Object = {name: "Test", value: 42};
        var str:String = ObjectUtil.toString(obj, null, 0);

        this.assert(str.indexOf("name") != -1, "Contains name key");
        this.assert(str.indexOf("Test") != -1, "Contains name value");
        this.assert(str.indexOf("42") != -1, "Contains number value");
    }

    private function testToStringNestedObject():Void {
        trace("\n--- Test: toString - Nested Object ---");
        var obj:Object = {outer: {inner: "value"}};
        var str:String = ObjectUtil.toString(obj, null, 0);

        this.assert(str.indexOf("outer") != -1, "Contains outer key");
        this.assert(str.indexOf("inner") != -1, "Contains inner key");
    }

    private function testToStringArray():Void {
        trace("\n--- Test: toString - Array ---");
        var arr:Array = [1, 2, 3];
        var str:String = ObjectUtil.toString(arr, null, 0);

        this.assert(str.indexOf("[") == 0, "Starts with [");
        this.assert(str.indexOf("1") != -1, "Contains first element");
    }

    private function testToStringCircularReference():Void {
        trace("\n--- Test: toString - Circular Reference ---");
        var obj:Object = {name: "Root"};
        obj.self = obj;

        var str:String = ObjectUtil.toString(obj, null, 0);

        this.assert(str.indexOf("[Circular]") != -1, "Circular reference marked");
    }

    private function testToStringMaxDepth():Void {
        trace("\n--- Test: toString - Max Depth ---");
        // 创建适度嵌套对象（不超过 Flash 的 256 递归限制）
        var obj:Object = {level: 0};
        var current:Object = obj;
        for (var i:Number = 1; i < 50; i++) {
            current.next = {level: i};
            current = current.next;
        }

        // 通过传入较高的初始 depth 值来测试 MAX_DEPTH 逻辑
        // MAX_DEPTH = 256，传入 250 意味着只能再递归 6 层就会触发限制
        var str:String = ObjectUtil.toString(obj, null, 250);
        this.assert(str.indexOf("[Max Depth Reached]") != -1, "Max depth handled");
    }

    private function testToStringFunction():Void {
        trace("\n--- Test: toString - Function ---");
        var func:Function = function():Void {};
        var str:String = ObjectUtil.toString(func, null, 0);

        this.assert(str.indexOf("func:") == 0, "Function formatted with func: prefix");
    }

    private function testToStringNull():Void {
        trace("\n--- Test: toString - Null ---");
        var str:String = ObjectUtil.toString(null, null, 0);
        this.assert(str == "null", "Null converted to 'null' string");
    }

    // ==================== isInternalKey 方法测试 ====================

    private function testIsInternalKeyTrue():Void {
        trace("\n--- Test: isInternalKey - True ---");
        this.assert(ObjectUtil.isInternalKey("__dictUID") == true, "__dictUID is internal");
        this.assert(ObjectUtil.isInternalKey("__proto__") == true, "__proto__ is internal");
    }

    private function testIsInternalKeyFalse():Void {
        trace("\n--- Test: isInternalKey - False ---");
        this.assert(ObjectUtil.isInternalKey("name") == false, "name is not internal");
        this.assert(ObjectUtil.isInternalKey("_private") == false, "_private is not internal");
    }

    // ==================== copyProperties 方法测试 ====================

    private function testCopyPropertiesBasic():Void {
        trace("\n--- Test: copyProperties - Basic ---");
        var source:Object = {a: 1, b: 2};
        var dest:Object = {};

        ObjectUtil.copyProperties(source, dest);

        this.assert(dest.a == 1, "Property a copied");
        this.assert(dest.b == 2, "Property b copied");
    }

    private function testCopyPropertiesWithNull():Void {
        trace("\n--- Test: copyProperties - With Null ---");
        var dest:Object = {existing: "value"};

        ObjectUtil.copyProperties(null, dest);

        this.assert(dest.existing == "value", "Destination unchanged when source is null");
    }

    private function testCopyPropertiesIgnoresInternalKeys():Void {
        trace("\n--- Test: copyProperties - Ignores Internal Keys ---");
        var source:Object = {normal: "value"};
        source["__internal"] = "hidden";
        var dest:Object = {};

        ObjectUtil.copyProperties(source, dest);

        this.assert(dest.normal == "value", "Normal property copied");
        this.assert(dest["__internal"] == undefined, "Internal key not copied");
    }

    // ==================== getKeys 方法测试 ====================

    private function testGetKeysBasic():Void {
        trace("\n--- Test: getKeys - Basic ---");
        var obj:Object = {a: 1, b: 2, c: 3};
        var keys:Array = ObjectUtil.getKeys(obj);

        this.assert(keys.length == 3, "Got 3 keys");
    }

    private function testGetKeysEmpty():Void {
        trace("\n--- Test: getKeys - Empty ---");
        var keys:Array = ObjectUtil.getKeys({});
        this.assert(keys.length == 0, "Empty object has no keys");
    }

    private function testGetKeysIgnoresInternalKeys():Void {
        trace("\n--- Test: getKeys - Ignores Internal Keys ---");
        var obj:Object = {normal: "value"};
        obj["__internal"] = "hidden";
        var keys:Array = ObjectUtil.getKeys(obj);

        this.assert(keys.length == 1, "Only normal key returned");
        this.assert(keys[0] == "normal", "Correct key returned");
    }

    // ==================== toArray 方法测试 ====================

    private function testToArrayWithArray():Void {
        trace("\n--- Test: toArray - With Array ---");
        var arr:Array = [1, 2, 3];
        var result:Array = ObjectUtil.toArray(arr);

        this.assert(result == arr, "Array returned as-is");
    }

    private function testToArrayWithObject():Void {
        trace("\n--- Test: toArray - With Object ---");
        var obj:Object = {a: 1};
        var result:Array = ObjectUtil.toArray(obj);

        this.assert(result.length == 1, "Object wrapped in array");
        this.assert(result[0] == obj, "Object is first element");
    }

    private function testToArrayWithNull():Void {
        trace("\n--- Test: toArray - With Null ---");
        var result:Array = ObjectUtil.toArray(null);

        this.assert(result.length == 0, "Null returns empty array");
    }

    private function testToArrayWithPrimitive():Void {
        trace("\n--- Test: toArray - With Primitive ---");
        var result:Array = ObjectUtil.toArray(42);

        this.assert(result.length == 1, "Primitive wrapped in array");
        this.assert(result[0] == 42, "Primitive is first element");
    }

    // ==================== equals 方法测试 ====================

    private function testEqualsIdentical():Void {
        trace("\n--- Test: equals - Identical ---");
        var obj:Object = {a: 1, b: 2};
        this.assert(ObjectUtil.equals(obj, obj, null) == true, "Same reference equals");
    }

    private function testEqualsDifferent():Void {
        trace("\n--- Test: equals - Different ---");
        var obj1:Object = {a: 1};
        var obj2:Object = {a: 2};
        this.assert(ObjectUtil.equals(obj1, obj2, null) == false, "Different values not equal");
    }

    private function testEqualsNestedObjects():Void {
        trace("\n--- Test: equals - Nested Objects ---");
        var obj1:Object = {outer: {inner: 1}};
        var obj2:Object = {outer: {inner: 1}};
        var obj3:Object = {outer: {inner: 2}};

        this.assert(ObjectUtil.equals(obj1, obj2, null) == true, "Equal nested objects");
        this.assert(ObjectUtil.equals(obj1, obj3, null) == false, "Different nested values");
    }

    private function testEqualsArrays():Void {
        trace("\n--- Test: equals - Arrays ---");
        var arr1:Array = [1, 2, 3];
        var arr2:Array = [1, 2, 3];
        var arr3:Array = [1, 2, 4];

        this.assert(ObjectUtil.equals(arr1, arr2, null) == true, "Equal arrays");
        this.assert(ObjectUtil.equals(arr1, arr3, null) == false, "Different arrays");
    }

    private function testEqualsWithNull():Void {
        trace("\n--- Test: equals - With Null ---");
        this.assert(ObjectUtil.equals(null, null, null) == true, "null == null");
        this.assert(ObjectUtil.equals(null, {}, null) == false, "null != object");
        this.assert(ObjectUtil.equals({}, null, null) == false, "object != null");
    }

    private function testEqualsCircularReference():Void {
        trace("\n--- Test: equals - Circular Reference ---");
        var obj1:Object = {name: "A"};
        obj1.self = obj1;
        var obj2:Object = {name: "A"};
        obj2.self = obj2;

        this.assert(ObjectUtil.equals(obj1, obj2, null) == true, "Equal circular references");
    }

    // ==================== size 方法测试 ====================

    private function testSizeBasic():Void {
        trace("\n--- Test: size - Basic ---");
        var obj:Object = {a: 1, b: 2, c: 3};
        this.assert(ObjectUtil.size(obj) == 3, "Size is 3");
    }

    private function testSizeEmpty():Void {
        trace("\n--- Test: size - Empty ---");
        this.assert(ObjectUtil.size({}) == 0, "Empty object size is 0");
    }

    private function testSizeIgnoresInternalKeys():Void {
        trace("\n--- Test: size - Ignores Internal Keys ---");
        var obj:Object = {normal: "value"};
        obj["__internal"] = "hidden";
        this.assert(ObjectUtil.size(obj) == 1, "Internal keys not counted");
    }

    // ==================== deepEquals 方法测试 ====================

    private function testDeepEqualsBasic():Void {
        trace("\n--- Test: deepEquals - Basic ---");
        var obj1:Object = {a: 1, b: 2};
        var obj2:Object = {a: 1, b: 2};
        this.assert(ObjectUtil.deepEquals(obj1, obj2) == true, "Deep equals works");
    }

    private function testDeepEqualsNested():Void {
        trace("\n--- Test: deepEquals - Nested ---");
        var obj1:Object = {x: {y: {z: 1}}};
        var obj2:Object = {x: {y: {z: 1}}};
        this.assert(ObjectUtil.deepEquals(obj1, obj2) == true, "Deep nested equals");
    }

    // ==================== JSON 序列化测试 ====================

    private function testToJSONBasic():Void {
        trace("\n--- Test: toJSON - Basic ---");
        var obj:Object = {name: "Test", value: 42};
        var json:String = ObjectUtil.toJSON(obj, false);

        this.assert(json != null, "JSON string created");
        this.assert(json.indexOf("Test") != -1, "JSON contains value");
    }

    private function testToJSONPretty():Void {
        trace("\n--- Test: toJSON - Pretty ---");
        var obj:Object = {name: "Test"};
        var json:String = ObjectUtil.toJSON(obj, true);

        this.assert(json != null, "Pretty JSON created");
    }

    private function testFromJSONBasic():Void {
        trace("\n--- Test: fromJSON - Basic ---");
        var json:String = '{"name":"Test","value":42}';
        var obj:Object = ObjectUtil.fromJSON(json);

        this.assert(obj != null, "Object parsed from JSON");
        this.assert(obj.name == "Test", "Name property parsed");
        this.assert(obj.value == 42, "Value property parsed");
    }

    private function testFromJSONInvalid():Void {
        trace("\n--- Test: fromJSON - Invalid ---");
        var json:String = '{"invalid json';
        var obj:Object = ObjectUtil.fromJSON(json);

        this.assert(obj == null, "Invalid JSON returns null");
    }

    private function testJSONRoundTrip():Void {
        trace("\n--- Test: JSON - Round Trip ---");
        var original:Object = {
            name: "Test",
            numbers: [1, 2, 3],
            nested: {value: true}
        };

        var json:String = ObjectUtil.toJSON(original, false);
        var parsed:Object = ObjectUtil.fromJSON(json);

        this.assert(parsed.name == original.name, "Round trip preserves name");
        this.assert(parsed.numbers.length == 3, "Round trip preserves array");
        this.assert(parsed.nested.value == true, "Round trip preserves nested");
    }

    // ==================== Base64 序列化测试 ====================

    private function testToBase64Basic():Void {
        trace("\n--- Test: toBase64 - Basic ---");
        var obj:Object = {name: "Test", value: 42};
        var base64:String = ObjectUtil.toBase64(obj, false);

        this.assert(base64 != null, "Base64 string created");
        this.assert(base64.length > 0, "Base64 string not empty");
    }

    private function testFromBase64Basic():Void {
        trace("\n--- Test: fromBase64 - Basic ---");
        var obj:Object = {name: "Test", value: 42};
        var base64:String = ObjectUtil.toBase64(obj, false);
        var parsed:Object = ObjectUtil.fromBase64(base64);

        this.assert(parsed != null, "Object parsed from Base64");
        this.assert(parsed.name == "Test", "Name property restored");
    }

    private function testBase64RoundTrip():Void {
        trace("\n--- Test: Base64 - Round Trip ---");
        var original:Object = {
            text: "Hello World",
            number: 123.456,
            array: [1, 2, 3]
        };

        var base64:String = ObjectUtil.toBase64(original, false);
        var parsed:Object = ObjectUtil.fromBase64(base64);

        this.assert(ObjectUtil.equals(original, parsed, null), "Base64 round trip preserves data");
    }

    // ==================== FNTL 序列化测试 ====================

    private function testToFNTLBasic():Void {
        trace("\n--- Test: toFNTL - Basic ---");
        var obj:Object = {name: "Test", value: 42};
        var fntl:String = ObjectUtil.toFNTL(obj, false);

        this.assert(fntl != null, "FNTL string created");
    }

    private function testFromFNTLBasic():Void {
        trace("\n--- Test: fromFNTL - Basic ---");
        var obj:Object = {name: "Test", value: 42};
        var fntl:String = ObjectUtil.toFNTL(obj, false);
        var parsed:Object = ObjectUtil.fromFNTL(fntl);

        this.assert(parsed != null, "Object parsed from FNTL");
    }

    private function testFNTLRoundTrip():Void {
        trace("\n--- Test: FNTL - Round Trip ---");
        var original:Object = {
            player: {name: "Hero", level: 10},
            items: ["sword", "shield"]
        };

        var fntl:String = ObjectUtil.toFNTL(original, false);
        var parsed:Object = ObjectUtil.fromFNTL(fntl);

        this.assert(parsed.player.name == "Hero", "FNTL round trip preserves nested");
    }

    private function testToFNTLSingleLine():Void {
        trace("\n--- Test: toFNTLSingleLine ---");
        var obj:Object = {a: 1, b: 2};
        var singleLine:String = ObjectUtil.toFNTLSingleLine(obj, true);

        this.assert(singleLine != null, "Single line FNTL created");
        // 单行格式不应包含真正的换行符
        this.assert(singleLine.indexOf("\n") == -1 || singleLine.indexOf("\\n") != -1,
            "Single line format correct");
    }

    // ==================== TOML 序列化测试 ====================

    private function testToTOMLBasic():Void {
        trace("\n--- Test: toTOML - Basic ---");
        var obj:Object = {title: "Test", enabled: true, count: 42};
        var toml:String = ObjectUtil.toTOML(obj, false);

        this.assert(toml != null, "TOML string created");
    }

    private function testFromTOMLBasic():Void {
        trace("\n--- Test: fromTOML - Basic ---");
        var tomlString:String = 'title = "Test"\ncount = 42\n';
        var parsed:Object = ObjectUtil.fromTOML(tomlString);

        this.assert(parsed != null, "Object parsed from TOML");
        this.assert(parsed.title == "Test", "TOML title parsed");
        this.assert(parsed.count == 42, "TOML count parsed");
    }

    private function testTOMLRoundTrip():Void {
        trace("\n--- Test: TOML - Round Trip ---");
        var original:Object = {
            title: "Game Config",
            enabled: true,
            score: 1000
        };

        var toml:String = ObjectUtil.toTOML(original, false);
        var parsed:Object = ObjectUtil.fromTOML(toml);

        this.assert(parsed.title == "Game Config", "TOML round trip preserves string");
        this.assert(parsed.score == 1000, "TOML round trip preserves number");
    }

    // ==================== Compress 序列化测试 ====================

    private function testToCompressBasic():Void {
        trace("\n--- Test: toCompress - Basic ---");
        var obj:Object = {name: "Test", value: 42};
        var compressed:String = ObjectUtil.toCompress(obj, false);

        this.assert(compressed != null, "Compressed string created");
    }

    private function testFromCompressBasic():Void {
        trace("\n--- Test: fromCompress - Basic ---");
        var obj:Object = {name: "Test", value: 42};
        var compressed:String = ObjectUtil.toCompress(obj, false);
        var parsed:Object = ObjectUtil.fromCompress(compressed);

        this.assert(parsed != null, "Object parsed from compressed");
        this.assert(parsed.name == "Test", "Name property restored");
    }

    private function testCompressRoundTrip():Void {
        trace("\n--- Test: Compress - Round Trip ---");
        var original:Object = {
            text: "Hello World",
            numbers: [1, 2, 3, 4, 5]
        };

        var compressed:String = ObjectUtil.toCompress(original, false);
        var parsed:Object = ObjectUtil.fromCompress(compressed);

        this.assert(ObjectUtil.equals(original, parsed, null), "Compress round trip preserves data");
    }

    // ==================== 边界情况测试 ====================

    private function testEmptyObject():Void {
        trace("\n--- Test: Edge Case - Empty Object ---");
        var empty:Object = {};

        var cloned:Object = ObjectUtil.clone(empty);
        this.assert(ObjectUtil.size(cloned) == 0, "Empty object cloned");

        var str:String = ObjectUtil.toString(empty, null, 0);
        this.assert(str == "{}", "Empty object toString is {}");
    }

    private function testDeeplyNestedObject():Void {
        trace("\n--- Test: Edge Case - Deeply Nested ---");
        var obj:Object = {level: 0};
        var current:Object = obj;
        for (var i:Number = 1; i < 50; i++) {
            current.next = {level: i};
            current = current.next;
        }

        var cloned:Object = ObjectUtil.clone(obj);
        this.assert(cloned.level == 0, "Deep object cloned - level 0");

        // 遍历验证深层克隆
        current = cloned;
        var depth:Number = 0;
        while (current.next != undefined) {
            current = current.next;
            depth++;
        }
        this.assert(depth == 49, "Deep clone preserves all levels");
    }

    private function testLargeObject():Void {
        trace("\n--- Test: Edge Case - Large Object ---");
        var obj:Object = {};
        for (var i:Number = 0; i < 100; i++) {
            obj["prop" + i] = i * 10;
        }

        var cloned:Object = ObjectUtil.clone(obj);
        this.assert(ObjectUtil.size(cloned) == 100, "Large object cloned completely");
        this.assert(cloned.prop50 == 500, "Large object values correct");
    }

    private function testSpecialCharactersInKeys():Void {
        trace("\n--- Test: Edge Case - Special Characters in Keys ---");
        var obj:Object = {};
        obj["key with spaces"] = "value1";
        obj["key-with-dashes"] = "value2";
        obj["key_with_underscores"] = "value3";

        var cloned:Object = ObjectUtil.clone(obj);
        this.assert(cloned["key with spaces"] == "value1", "Space in key preserved");
        this.assert(cloned["key-with-dashes"] == "value2", "Dashes in key preserved");
    }

    private function testUnicodeValues():Void {
        trace("\n--- Test: Edge Case - Unicode Values ---");
        var obj:Object = {
            chinese: "中文测试",
            japanese: "日本語",
            emoji: "Hello"  // AS2 可能不支持 emoji
        };

        var cloned:Object = ObjectUtil.clone(obj);
        this.assert(cloned.chinese == "中文测试", "Chinese characters preserved");
        this.assert(cloned.japanese == "日本語", "Japanese characters preserved");
    }

    // ==================== 性能测试 ====================

    private function testClonePerformance():Void {
        trace("\n--- Test: Performance - Clone ---");
        var obj:Object = {a: 1, b: 2, c: {d: 3, e: [1, 2, 3]}};
        var iterations:Number = 1000;

        // 标准 clone（带循环引用检测）
        var time:Number = this.measureTime(function() {
            ObjectUtil.clone(obj);
        }, iterations);

        // 快速 clone（无循环引用检测）
        var timeFast:Number = this.measureTime(function() {
            ObjectUtil.cloneFast(obj);
        }, iterations);

        var speedup:Number = Math.round((time / timeFast) * 100) / 100;
        trace("Clone Performance: " + time + "ms (standard), " + timeFast + "ms (fast), speedup: " + speedup + "x");
        this.assert(time < 5000, "Clone performance acceptable");
        this.assert(timeFast <= time, "CloneFast is faster or equal to Clone");
    }

    private function testComparePerformance():Void {
        trace("\n--- Test: Performance - Compare ---");
        var obj1:Object = {a: 1, b: 2, c: {d: 3}};
        var obj2:Object = {a: 1, b: 2, c: {d: 3}};
        var iterations:Number = 1000;

        var time:Number = this.measureTime(function() {
            ObjectUtil.compare(obj1, obj2, null);
        }, iterations);

        trace("Compare Performance: " + time + "ms for " + iterations + " iterations");
        this.assert(time < 5000, "Compare performance acceptable");
    }

    private function testToStringPerformance():Void {
        trace("\n--- Test: Performance - ToString ---");
        var obj:Object = {a: 1, b: "test", c: [1, 2, 3], d: {nested: true}};
        var iterations:Number = 1000;

        var time:Number = this.measureTime(function() {
            ObjectUtil.toString(obj, null, 0);
        }, iterations);

        trace("ToString Performance: " + time + "ms for " + iterations + " iterations");
        this.assert(time < 5000, "ToString performance acceptable");
    }

    private function testSerializationPerformance():Void {
        trace("\n--- Test: Performance - Serialization ---");
        var obj:Object = {
            name: "Test Object",
            values: [1, 2, 3, 4, 5],
            nested: {a: 1, b: 2}
        };
        var iterations:Number = 100;

        // JSON 性能
        var jsonTime:Number = this.measureTime(function() {
            var json:String = ObjectUtil.toJSON(obj, false);
            ObjectUtil.fromJSON(json);
        }, iterations);

        trace("JSON Round Trip: " + jsonTime + "ms for " + iterations + " iterations");
        this.assert(jsonTime < 5000, "JSON serialization performance acceptable");
    }

    // ==================== 报告生成 ====================

    private function printFinalReport():Void {
        trace("\n=== FINAL TEST REPORT ===");
        trace("Tests Passed: " + this._testPassed);
        trace("Tests Failed: " + this._testFailed);
        var total:Number = this._testPassed + this._testFailed;
        var rate:Number = (total > 0) ? Math.round((this._testPassed / total) * 100) : 0;
        trace("Success Rate: " + rate + "%");

        if (this._testFailed == 0) {
            trace("ALL TESTS PASSED! ObjectUtil implementation is robust.");
        } else {
            trace("Some tests failed. Please review the implementation.");
        }

        trace("\n=== TEST COVERAGE ===");
        trace("- clone: Deep cloning with circular reference handling");
        trace("- cloneParameters: Object and string parameter parsing");
        trace("- forEach: Object iteration");
        trace("- compare: Object comparison");
        trace("- hasProperties: Property existence check");
        trace("- isSimple: Type checking");
        trace("- toString: String representation");
        trace("- isInternalKey: Internal key detection");
        trace("- copyProperties: Property copying");
        trace("- getKeys: Key extraction");
        trace("- toArray: Array conversion");
        trace("- equals/deepEquals: Equality checking");
        trace("- size: Object size calculation");
        trace("- JSON serialization: toJSON/fromJSON");
        trace("- Base64 serialization: toBase64/fromBase64");
        trace("- FNTL serialization: toFNTL/fromFNTL");
        trace("- TOML serialization: toTOML/fromTOML");
        trace("- Compress serialization: toCompress/fromCompress");
        trace("========================");
    }
}
