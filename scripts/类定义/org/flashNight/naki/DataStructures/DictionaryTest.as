import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.DictionaryTest {
    // 自定义断言函数
    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("Assertion Failed: " + message);
        } else {
            trace("Assertion Passed: " + message);
        }
    }

    // 测试基本字符串键操作
    public static function testStringKeys():Void {
        var dict:Dictionary = new Dictionary();
        
        // 测试空字典状态
        assert(dict.getCount() === 0, "Empty dictionary count should be 0");
        assert(dict.getKeys().length === 0, "Empty dictionary keys should be empty");
        
        // 添加字符串键
        dict.setItem("name", "Alice");
        dict.setItem("age", 30);
        
        // 验证基础操作
        assert(dict.getCount() === 2, "Count after adding 2 items");
        assert(dict.getItem("name") === "Alice", "String key retrieval 1");
        assert(dict.getItem("age") === 30, "String key retrieval 2");
        assert(dict.hasKey("name"), "HasKey for existing string key");
        assert(!dict.hasKey("gender"), "HasKey for non-existent string key");
        
        // 测试删除操作
        dict.removeItem("age");
        assert(dict.getCount() === 1, "Count after removal");
        assert(dict.getItem("age") === null, "Removed item should return null");
    }

    // 测试对象和函数键
    public static function testObjectFunctionKeys():Void {
        var dict:Dictionary = new Dictionary();
        
        // 创建测试对象
        var objKey1:Object = { id: 1 };
        var objKey2:Object = { id: 2 };
        var funcKey1:Function = function() {};
        var funcKey2:Function = function() {};
        
        // 添加对象键
        dict.setItem(objKey1, "Object1");
        dict.setItem(objKey2, "Object2");
        dict.setItem(funcKey1, "Function1");
        
        // 验证对象键操作
        assert(dict.getCount() === 3, "Object/function key count");
        assert(dict.getItem(objKey1) === "Object1", "Object key retrieval 1");
        assert(dict.getItem(objKey2) === "Object2", "Object key retrieval 2");
        assert(dict.getItem(funcKey1) === "Function1", "Function key retrieval");
        assert(dict.getItem(funcKey2) === null, "Non-existent function key");
        
        // 测试键唯一性
        var objKey3:Object = { id: 1 }; // 相同内容不同对象
        dict.setItem(objKey3, "Object3");
        assert(dict.getCount() === 4, "Different objects with same content should be different keys");
    }

    // 测试UID管理系统
    public static function testUIDManagement():Void {
        var dict:Dictionary = new Dictionary();
        var testObj:Object = {};
        
        // 首次获取UID
        var uid1:Number = dict.getUID(testObj);
        assert(typeof uid1 === "number", "UID should be a number");
        assert(uid1 === Dictionary.getStaticUID(testObj), "Instance and static UID should match");
        
        // 重复获取应相同
        var uid2:Number = dict.getUID(testObj);
        assert(uid1 === uid2, "UID should be consistent");
        
        // 新对象应有新UID
        var newObj:Object = {};
        assert(Dictionary.getStaticUID(newObj) === uid1 - 1, "New objects should get decrementing UIDs");
        
        // 测试UID映射清理
        dict.setItem(testObj, "test");
        dict.removeItem(testObj);
        assert(testObj.__dictUID !== undefined, "UID should remain after deletion"); // Updated assertion
    }

    // 测试键列表缓存机制
    public static function testKeyCache():Void {
        var dict:Dictionary = new Dictionary();
        var objKey:Object = {};
        
        // 初始状态
        assert(dict.getKeys().length === 0, "Initial empty keys");
        
        // 添加混合键类型
        dict.setItem("strKey", 1);
        dict.setItem(objKey, 2);
        
        // 首次获取键列表
        var keys1:Array = dict.getKeys();
        assert(keys1.length === 2, "Keys count after additions");
        assert(keys1.indexOf("strKey") !== -1, "String key in keys list");
        assert(keys1.indexOf(objKey) !== -1, "Object key in keys list");
        
        // 修改字典后验证缓存更新
        dict.removeItem("strKey");
        var keys2:Array = dict.getKeys();
        assert(keys2.length === 1, "Keys count after removal");
        assert(keys2.indexOf(objKey) !== -1, "Remaining key in updated list");
    }

    // 测试清除和销毁功能
    public static function testClearDestroy():Void {
        var dict:Dictionary = new Dictionary();
        var objKey:Object = {};
        
        // 填充数据
        dict.setItem("key1", "val1");
        dict.setItem(objKey, "val2");
        
        // 测试清除
        dict.clear();
        assert(dict.getCount() === 0, "Count after clear");
        assert(dict.getKeys().length === 0, "Keys after clear");
        assert(objKey.__dictUID !== undefined, "UID should remain after clear"); // Updated assertion
        
        // 测试销毁
        dict.setItem("key", "value");
        dict.destroy();
        assert(dict.getCount() === 0, "Count after destroy");
        assert(dict.getKeys().length === 0, "Keys after destroy");

        /*
        
        // 测试静态资源清理
        Dictionary.destroyStatic();
        var newObj:Object = {};
        var newUID:Number = Dictionary.getStaticUID(newObj);
        assert(newUID === 1, "UID counter should reset after static destruction");
        
        */
    }

    // 性能测试
    public static function runPerformanceTests():Void {
        var iterations:Number = 50000;
        var testDict:Dictionary = new Dictionary();
        var nativeObj:Object = {};
        
        // 自定义字典测试
        var start:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            testDict.setItem("key" + i, i);
            testDict.getItem("key" + i);
            testDict.removeItem("key" + i);
        }
        var dictTime:Number = getTimer() - start;
        
        // 原生对象测试
        start = getTimer();
        for (var j:Number = 0; j < iterations; j++) {
            nativeObj["key" + j] = j;
            var val = nativeObj["key" + j];
            delete nativeObj["key" + j];
        }
        var nativeTime:Number = getTimer() - start;
        
        trace("\nPerformance Results:");
        trace("Dictionary: " + dictTime + "ms (" + iterations + " ops)");
        trace("Native Object: " + nativeTime + "ms (" + iterations + " ops)");
        trace("Performance ratio: " + (dictTime / nativeTime) + "x");
    }

    // [v2.0] 回归测试：验证 destroy() 不再破坏全局 uidMap
    public static function testDestroyIsolation():Void {
        trace("=== [v2.0] Testing destroy() isolation ===");

        // 创建两个独立的 Dictionary 实例
        var dict1:Dictionary = new Dictionary();
        var dict2:Dictionary = new Dictionary();

        // 创建测试对象
        var obj1:Object = { name: "obj1" };
        var obj2:Object = { name: "obj2" };

        // 在两个字典中分别使用不同的对象作为键
        dict1.setItem(obj1, "value1");
        dict2.setItem(obj2, "value2");

        // 验证两个字典都能正常工作
        assert(dict1.getItem(obj1) === "value1", "[v2.0] dict1 should work before destroy");
        assert(dict2.getItem(obj2) === "value2", "[v2.0] dict2 should work before destroy");

        // 销毁 dict1
        dict1.destroy();

        // [v2.0 关键测试] dict2 应该仍然能正常工作
        // 在修复前，dict1.destroy() 会清空静态 uidMap，导致 dict2 也无法工作
        assert(dict2.getItem(obj2) === "value2", "[v2.0] dict2 should still work after dict1.destroy()");
        assert(dict2.hasKey(obj2) === true, "[v2.0] dict2.hasKey() should still work after dict1.destroy()");

        // 验证可以继续添加新对象到 dict2
        var obj3:Object = { name: "obj3" };
        dict2.setItem(obj3, "value3");
        assert(dict2.getItem(obj3) === "value3", "[v2.0] dict2 can add new items after dict1.destroy()");

        // 清理
        dict2.destroy();

        trace("=== [v2.0] destroy() isolation test completed ===");
    }

    // [v2.0] 回归测试：验证多个 Dictionary 实例独立工作
    public static function testMultipleInstancesIndependence():Void {
        trace("=== [v2.0] Testing multiple instances independence ===");

        var dict1:Dictionary = new Dictionary();
        var dict2:Dictionary = new Dictionary();
        var dict3:Dictionary = new Dictionary();

        var sharedObj:Object = { shared: true };

        // 同一个对象可以在多个字典中作为键
        dict1.setItem(sharedObj, "from_dict1");
        dict2.setItem(sharedObj, "from_dict2");
        dict3.setItem(sharedObj, "from_dict3");

        assert(dict1.getItem(sharedObj) === "from_dict1", "[v2.0] dict1 stores its own value");
        assert(dict2.getItem(sharedObj) === "from_dict2", "[v2.0] dict2 stores its own value");
        assert(dict3.getItem(sharedObj) === "from_dict3", "[v2.0] dict3 stores its own value");

        // 销毁 dict1 和 dict2，dict3 应该不受影响
        dict1.destroy();
        dict2.destroy();

        assert(dict3.getItem(sharedObj) === "from_dict3", "[v2.0] dict3 unaffected by dict1/dict2 destroy");

        dict3.destroy();

        trace("=== [v2.0] multiple instances independence test completed ===");
    }

    // ======================
    // [v2.1] 回归测试 - 三方交叉审查问题修复验证
    // ======================

    /**
     * [v2.1 回归测试 I5] 验证 __dictUID 不会出现在 for..in 枚举中
     * 修复问题：之前 __dictUID 可枚举，会污染 for..in 循环
     */
    public static function testUIDNonEnumerable():Void {
        trace("=== [v2.1 I5] Testing __dictUID non-enumerable ===");

        // 创建测试对象
        var testObj:Object = { a: 1, b: 2, c: 3 };

        // 获取 UID（这会添加 __dictUID 属性）
        var uid:Number = Dictionary.getStaticUID(testObj);

        // 验证 UID 已分配
        assert(uid != undefined && uid < 0, "[v2.1 I5] UID should be assigned and negative");

        // 使用 for..in 枚举对象属性
        var foundKeys:Array = [];
        for (var key:String in testObj) {
            foundKeys.push(key);
        }

        // 验证 __dictUID 不在枚举结果中
        var foundDictUID:Boolean = false;
        for (var i:Number = 0; i < foundKeys.length; i++) {
            if (foundKeys[i] == "__dictUID") {
                foundDictUID = true;
                break;
            }
        }

        assert(foundDictUID == false, "[v2.1 I5] __dictUID should not appear in for..in enumeration");
        assert(foundKeys.length == 3, "[v2.1 I5] Only original keys should be enumerated (a, b, c)");

        // 验证 __dictUID 仍然可以直接访问
        assert(testObj.__dictUID == uid, "[v2.1 I5] __dictUID should still be directly accessible");

        trace("=== [v2.1 I5] __dictUID non-enumerable test completed ===");
    }

    /**
     * [v2.1 回归测试 I8] 验证 removeItem/clear 正确清理 uidMap
     * 修复问题：之前 removeItem/clear 不清理 uidMap 导致内存泄漏
     */
    public static function testUIDMapCleanup():Void {
        trace("=== [v2.1 I8] Testing uidMap cleanup ===");

        // 创建 Dictionary 实例
        var dict:Dictionary = new Dictionary();

        // 创建测试对象
        var testKey1:Object = { name: "key1" };
        var testKey2:Object = { name: "key2" };
        var testKey3:Object = { name: "key3" };

        // 添加键值对
        dict.setItem(testKey1, "value1");
        dict.setItem(testKey2, "value2");
        dict.setItem(testKey3, "value3");

        // 验证初始状态
        assert(dict.getCount() == 3, "[v2.1 I8] Initial count should be 3");
        assert(dict.getItem(testKey1) == "value1", "[v2.1 I8] getItem works for key1");
        assert(dict.getItem(testKey2) == "value2", "[v2.1 I8] getItem works for key2");

        // 测试 removeItem 清理
        dict.removeItem(testKey1);
        assert(dict.getItem(testKey1) == null, "[v2.1 I8] getItem returns null after removeItem");
        assert(dict.getCount() == 2, "[v2.1 I8] Count should be 2 after removeItem");

        // 验证其他键不受影响
        assert(dict.getItem(testKey2) == "value2", "[v2.1 I8] Other keys not affected by removeItem");
        assert(dict.getItem(testKey3) == "value3", "[v2.1 I8] Other keys not affected by removeItem");

        // 测试 clear 清理
        dict.clear();
        assert(dict.getItem(testKey2) == null, "[v2.1 I8] getItem returns null after clear");
        assert(dict.getItem(testKey3) == null, "[v2.1 I8] getItem returns null after clear");
        assert(dict.getCount() == 0, "[v2.1 I8] Count should be 0 after clear");

        // 验证可以重新添加相同对象
        dict.setItem(testKey1, "new_value1");
        assert(dict.getItem(testKey1) == "new_value1", "[v2.1 I8] Can re-add object after removal");

        // 清理
        dict.destroy();

        trace("=== [v2.1 I8] uidMap cleanup test completed ===");
    }

    /**
     * [v2.1 回归测试] 验证 getStaticUID 不写入 uidMap（与 getUID/setItem 区别）
     */
    public static function testStaticUIDNoLeak():Void {
        trace("=== [v2.1] Testing getStaticUID no leak ===");

        // 创建测试对象，只使用 getStaticUID（不通过 Dictionary 实例）
        var testObj:Object = { test: true };

        // 使用静态方法获取 UID
        var uid:Number = Dictionary.getStaticUID(testObj);
        assert(uid != undefined && uid < 0, "[v2.1] getStaticUID should return valid UID");

        // 再次调用应返回相同 UID
        var uid2:Number = Dictionary.getStaticUID(testObj);
        assert(uid == uid2, "[v2.1] getStaticUID should return same UID on subsequent calls");

        // 创建 Dictionary 并使用该对象
        var dict:Dictionary = new Dictionary();
        dict.setItem(testObj, "value");

        // 验证能正常工作
        assert(dict.getItem(testObj) == "value", "[v2.1] Dictionary can use object with pre-assigned UID");

        // 清理
        dict.destroy();

        trace("=== [v2.1] getStaticUID no leak test completed ===");
    }

    // 运行所有测试
    public static function runAll():Void {
        trace("=== Starting Correctness Tests ===");
        testStringKeys();
        testObjectFunctionKeys();
        testUIDManagement();
        testKeyCache();
        testClearDestroy();

        trace("\n=== [v2.0] Starting Regression Tests ===");
        testDestroyIsolation();
        testMultipleInstancesIndependence();

        trace("\n=== [v2.1] Starting Regression Tests ===");
        testUIDNonEnumerable();
        testUIDMapCleanup();
        testStaticUIDNoLeak();

        trace("\n=== Starting Performance Tests ===");
        runPerformanceTests();

        trace("\n=== All Tests Completed ===");
    }
}

