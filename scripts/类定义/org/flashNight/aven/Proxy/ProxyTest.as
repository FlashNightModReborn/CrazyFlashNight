import org.flashNight.aven.Proxy.*;
import flash.utils.getTimer; // 导入 getTimer 方法用于性能测试

// 定义 ProxyTest 类
class org.flashNight.aven.Proxy.ProxyTest {
    // 用于记录测试结果
    private var testsPassed:Number = 0; // 通过的测试数量
    private var testsFailed:Number = 0; // 失败的测试数量
    private var assertFunc:Function; // 引用断言方法

    /**
     * 构造函数，初始化测试。
     * 创建 ProxyTest 实例时，自动运行所有测试并输出结果。
     */
    public function ProxyTest() {
        trace("=== ProxyTest 开始 ===");

        // 保存 assert 方法的引用，供回调函数使用
        this.assertFunc = this.assert;

        // 执行所有测试
        this.runAllTests();

        // 总结测试结果
        trace("=== ProxyTest 结束 ===");
        trace("通过的测试: " + this.testsPassed);
        trace("失败的测试: " + this.testsFailed);
    }

    /**
     * 简单的断言方法。
     * 根据条件判断测试是否通过，并记录结果。
     * @param condition 条件表达式，若为 true 则通过。
     * @param message 断言失败时的消息。
     */
    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            trace("[PASS] " + message);
            this.testsPassed++;
        } else {
            trace("[FAIL] " + message);
            this.testsFailed++;
        }
    }

    /**
     * 运行所有测试方法。
     * 按照预定顺序执行各项测试，确保 Proxy 类的各项功能正常。
     */
    private function runAllTests():Void {
        this.testAddPropertySetterWatcher();
        this.testAddPropertySetterWatcherWithWatch();
        this.testAddPropertyGetterWatcher();
        this.testRemovePropertySetterWatcher();
        this.testRemovePropertyWatcherWithWatch();
        this.testRemovePropertyGetterWatcher();
        this.testMultipleCallbacks();
        this.testFunctionCallWatcher();
        this.testPerformance(); // 性能测试
    }

    /**
     * 测试添加属性 Setter 监视器。
     * 验证在对象属性被修改时，Setter 回调能够被正确触发并接收正确的参数。
     */
    private function testAddPropertySetterWatcher():Void {
        trace("--- 测试: 添加属性 setter 监视器 ---");
        var obj:Object = {}; // 创建一个空对象
        var callbackCalled:Boolean = false; // 标志，记录回调是否被调用
        var expectedNewValue:Number = 100; // 预期的新值
        var expectedOldValue:Number = undefined; // 预期的旧值

        var assertFuncRef:Function = this.assertFunc; // 引用断言方法

        /**
         * Setter 回调函数。
         * 当属性被修改时，此函数被调用，验证接收到的参数是否正确。
         * @param newValue 新的属性值。
         * @param oldValue 旧的属性值。
         */
        function setterCallback(newValue:Number, oldValue:Number):Void {
            trace("[DEBUG] setterCallback 被调用");
            callbackCalled = true;
            assertFuncRef(newValue === expectedNewValue, "Setter 回调接收到正确的新值");
            assertFuncRef(oldValue === expectedOldValue, "Setter 回调接收到正确的旧值");
        }

        // 添加 Setter 监视器
        Proxy.addPropertySetterWatcher(obj, "value", setterCallback);

        // 设置属性值，触发 Setter 回调
        obj.value = expectedNewValue;

        // 断言回调被调用
        this.assert(callbackCalled, "Setter 回调被正确触发");

        // 清理，移除 Setter 监视器
        Proxy.removePropertySetterWatcher(obj, "value", setterCallback);
    }

    /**
     * 测试添加基于 watch 的属性 Setter 监视器。
     * 验证在对象属性被修改时，Setter 回调能够被正确触发并接收正确的参数。
     */
    private function testAddPropertySetterWatcherWithWatch():Void {
        trace("--- 测试: 添加基于 watch 的属性 setter 监视器 ---");
        var obj:Object = {}; // 创建一个空对象
        var callbackCalled:Boolean = false; // 标志，记录回调是否被调用
        var expectedNewValue:Number = 100; // 预期的新值
        var expectedOldValue:Number = undefined; // 预期的旧值

        var assertFuncRef:Function = this.assertFunc; // 引用断言方法

        /**
         * Setter 回调函数。
         * 当属性被修改时，此函数被调用，验证接收到的参数是否正确。
         * @param newValue 新的属性值。
         * @param oldValue 旧的属性值。
         */
        function setterCallback(newValue:Number, oldValue:Number):Void {
            trace("[DEBUG] setterCallbackWithWatch 被调用");
            callbackCalled = true;
            assertFuncRef(newValue === expectedNewValue, "SetterWithWatch 回调接收到正确的新值");
            assertFuncRef(oldValue === expectedOldValue, "SetterWithWatch 回调接收到正确的旧值");
        }

        // 添加 Setter 监视器
        Proxy.addPropertySetterWatcherWithWatch(obj, "value", setterCallback);

        // 设置属性值，触发 Setter 回调
        obj.value = expectedNewValue;

        // 断言回调被调用
        this.assert(callbackCalled, "SetterWithWatch 回调被正确触发");

        // 清理，移除 Setter 监视器
        Proxy.removePropertyWatcherWithWatch(obj, "value");
    }

    /**
     * 测试添加属性 Getter 监视器。
     * 验证在对象属性被访问时，Getter 回调能够被正确触发并接收正确的参数。
     */
    private function testAddPropertyGetterWatcher():Void {
        trace("--- 测试: 添加属性 getter 监视器 ---");
        var obj:Object = { value: 50 }; // 创建一个拥有初始属性的对象
        var callbackCalled:Boolean = false; // 标志，记录回调是否被调用
        var expectedValue:Number = 50; // 预期的属性值

        var assertFuncRef:Function = this.assertFunc; // 引用断言方法

        /**
         * Getter 回调函数。
         * 当属性被访问时，此函数被调用，验证接收到的参数是否正确。
         * @param value 被访问的属性值。
         */
        function getterCallback(value:Number):Void {
            trace("[DEBUG] getterCallback 被调用");
            callbackCalled = true;
            assertFuncRef(value === expectedValue, "Getter 回调接收到正确的值");
        }

        // 添加 Getter 监视器
        Proxy.addPropertyGetterWatcher(obj, "value", getterCallback);

        // 访问属性，触发 Getter 回调
        var val:Number = obj.value;

        // 断言回调被调用
        this.assert(callbackCalled, "Getter 回调被正确触发");

        // 断言返回值正确
        this.assert(val === expectedValue, "Getter 返回正确的值");

        // 清理，移除 Getter 监视器
        Proxy.removePropertyGetterWatcher(obj, "value", getterCallback);
    }

    /**
     * 测试移除属性 Setter 监视器。
     * 验证在移除 Setter 监视器后，属性修改不会再触发回调函数。
     */
    private function testRemovePropertySetterWatcher():Void {
        trace("--- 测试: 移除属性 setter 监视器 ---");
        var obj:Object = {}; // 创建一个空对象
        var callbackCalled:Boolean = false; // 标志，记录回调是否被调用

        var assertFuncRef:Function = this.assertFunc; // 引用断言方法

        /**
         * Setter 回调函数。
         * 此回调在移除监视器后不应被调用。
         * @param newValue 新的属性值。
         * @param oldValue 旧的属性值。
         */
        function setterCallback(newValue:Number, oldValue:Number):Void {
            trace("[DEBUG] setterCallback 被调用");
            callbackCalled = true;
            assertFuncRef(false, "Setter 回调不应被触发");
        }

        // 添加 Setter 监视器
        Proxy.addPropertySetterWatcher(obj, "value", setterCallback);
        // 移除 Setter 监视器
        Proxy.removePropertySetterWatcher(obj, "value", setterCallback);

        // 设置属性值，理论上不应触发 Setter 回调
        obj.value = 200;

        // 断言回调未被调用
        this.assert(!callbackCalled, "Setter 回调已成功移除，未被触发");
    }

    /**
     * 测试移除基于 watch 的属性 Setter 监视器。
     * 验证在移除 Setter 监视器后，属性修改不会再触发回调函数。
     */
    private function testRemovePropertyWatcherWithWatch():Void {
        trace("--- 测试: 移除基于 watch 的属性 setter 监视器 ---");
        var obj:Object = {}; // 创建一个空对象
        var callbackCalled:Boolean = false; // 标志，记录回调是否被调用

        var assertFuncRef:Function = this.assertFunc; // 引用断言方法

        /**
         * Setter 回调函数。
         * 此回调在移除监视器后不应被调用。
         * @param newValue 新的属性值。
         * @param oldValue 旧的属性值。
         */
        function setterCallback(newValue:Number, oldValue:Number):Void {
            trace("[DEBUG] setterCallbackWithWatch 被调用");
            callbackCalled = true;
            assertFuncRef(false, "SetterWithWatch 回调不应被触发");
        }

        // 添加 Setter 监视器
        Proxy.addPropertySetterWatcherWithWatch(obj, "value", setterCallback);
        // 移除 Setter 监视器
        Proxy.removePropertyWatcherWithWatch(obj, "value");

        // 设置属性值，理论上不应触发 Setter 回调
        obj.value = 200;

        // 断言回调未被调用
        this.assert(!callbackCalled, "SetterWithWatch 回调已成功移除，未被触发");
    }

    /**
     * 测试移除属性 Getter 监视器。
     * 验证在移除 Getter 监视器后，属性访问不会再触发回调函数。
     */
    private function testRemovePropertyGetterWatcher():Void {
        trace("--- 测试: 移除属性 getter 监视器 ---");
        var obj:Object = { value: 75 }; // 创建一个拥有初始属性的对象
        var callbackCalled:Boolean = false; // 标志，记录回调是否被调用

        var assertFuncRef:Function = this.assertFunc; // 引用断言方法

        /**
         * Getter 回调函数。
         * 此回调在移除监视器后不应被调用。
         * @param value 被访问的属性值。
         */
        function getterCallback(value:Number):Void {
            trace("[DEBUG] getterCallback 被调用");
            callbackCalled = true;
            assertFuncRef(false, "Getter 回调不应被触发");
        }

        // 添加 Getter 监视器
        Proxy.addPropertyGetterWatcher(obj, "value", getterCallback);
        // 移除 Getter 监视器
        Proxy.removePropertyGetterWatcher(obj, "value", getterCallback);

        // 访问属性，理论上不应触发 Getter 回调
        var val:Number = obj.value;

        // 断言回调未被调用
        this.assert(!callbackCalled, "Getter 回调已成功移除，未被触发");
    }

    /**
     * 测试多个回调函数的注册和触发。
     * 验证当为同一属性注册多个回调函数时，所有回调均被正确触发，并接收正确的参数。
     */
    private function testMultipleCallbacks():Void {
        trace("--- 测试: 多个回调函数的注册和触发 ---");
        var obj:Object = {}; // 创建一个空对象
        var setterCallback1Called:Boolean = false; // 标志，记录回调1是否被调用
        var setterCallback2Called:Boolean = false; // 标志，记录回调2是否被调用

        var assertFuncRef:Function = this.assertFunc; // 引用断言方法

        /**
         * Setter 回调函数1。
         * @param newValue 新的属性值。
         * @param oldValue 旧的属性值。
         */
        function setterCallback1(newValue:Number, oldValue:Number):Void {
            trace("[DEBUG] setterCallback1 被调用");
            setterCallback1Called = true;
            assertFuncRef(newValue === 300, "Setter 回调1接收到正确的新值");
            assertFuncRef(oldValue === undefined, "Setter 回调1接收到正确的旧值");
        }

        /**
         * Setter 回调函数2。
         * @param newValue 新的属性值。
         * @param oldValue 旧的属性值。
         */
        function setterCallback2(newValue:Number, oldValue:Number):Void {
            trace("[DEBUG] setterCallback2 被调用");
            setterCallback2Called = true;
            assertFuncRef(newValue === 300, "Setter 回调2接收到正确的新值");
            assertFuncRef(oldValue === undefined, "Setter 回调2接收到正确的旧值");
        }

        // 为同一属性添加两个 Setter 监视器
        Proxy.addPropertySetterWatcher(obj, "value", setterCallback1);
        Proxy.addPropertySetterWatcher(obj, "value", setterCallback2);

        // 设置属性值，触发所有 Setter 回调
        obj.value = 300;

        // 断言所有回调被调用
        this.assert(setterCallback1Called, "Setter 回调1被正确触发");
        this.assert(setterCallback2Called, "Setter 回调2被正确触发");

        // 清理，移除所有 Setter 监视器
        Proxy.removePropertySetterWatcher(obj, "value", setterCallback1);
        Proxy.removePropertySetterWatcher(obj, "value", setterCallback2);
    }

    /**
     * 测试函数调用监视器。
     * 验证在对象的方法被调用时，函数调用回调能够被正确触发并接收正确的参数。
     */
    private function testFunctionCallWatcher():Void {
        trace("--- 测试: 函数调用监视器 ---");
        var callbackCalled:Boolean = false; // 标志，记录回调是否被调用
        var expectedArg1:String = "TestUser"; // 预期的第一个参数
        var expectedArg2:Number = 25; // 预期的第二个参数

        var obj:Object = {}; // 创建一个空对象
        /**
         * 被监视的方法。
         * @param name 用户名。
         * @param age 用户年龄。
         * @return 欢迎消息。
         */
        obj.greet = function(name:String, age:Number):String {
            return "Hello, " + name + "! You are " + age + " years old.";
        };

        var assertFuncRef:Function = this.assertFunc; // 引用断言方法

        /**
         * 函数调用回调函数。
         * 当被监视的方法被调用时，此函数被触发，验证接收到的参数是否正确。
         * @param name 被调用方法的第一个参数。
         * @param age 被调用方法的第二个参数。
         */
        function functionCallback(name:String, age:Number):Void {
            trace("[DEBUG] functionCallback 被调用");
            callbackCalled = true;
            assertFuncRef(name === expectedArg1, "函数回调接收到正确的第一个参数");
            assertFuncRef(age === expectedArg2, "函数回调接收到正确的第二个参数");
        }

        // 添加函数调用监视器
        Proxy.addFunctionCallWatcher(obj, "greet", functionCallback);

        // 调用被监视的方法，触发函数调用回调
        var message:String = obj.greet(expectedArg1, expectedArg2);

        // 断言回调被调用
        this.assert(callbackCalled, "函数调用回调被正确触发");

        // 断言函数返回值正确
        this.assert(message === "Hello, TestUser! You are 25 years old.", "函数返回值正确");

        // 移除函数调用监视器
        Proxy.removeFunctionCallWatcher(obj, "greet", functionCallback);

        // 重置回调标志
        callbackCalled = false;

        // 再次调用方法，回调不应被触发
        message = obj.greet("AnotherUser", 30);

        // 断言回调未被调用
        this.assert(!callbackCalled, "移除函数调用回调后，回调未被触发");

        // 断言函数返回值正确
        this.assert(message === "Hello, AnotherUser! You are 30 years old.", "函数返回值正确");
    }

    /**
     * 运行所有性能测试方法。
     * 包括现有的性能测试以及新增的基于 watch 的方法性能测试。
     */
    private function testPerformance():Void {
        trace("--- 测试: 性能评估 ---");

        /**
         * 测试1: 添加和触发单一属性的 Setter 回调
         */
        trace("--- 测试1: 单一属性 Setter 回调性能评估 ---");
        var obj1:Object = {}; // 创建一个空对象
        var numCallbacks1:Number = 1000; // 添加的回调数量
        var setterCallbackCount1:Number = 0; // 记录 Setter 回调的调用次数

        /**
         * Setter 回调函数。
         * 每次属性被设置时，此函数被调用，记录调用次数。
         * @param newValue 新的属性值。
         * @param oldValue 旧的属性值。
         */
        function setterCallback1(newValue:Number, oldValue:Number):Void {
            setterCallbackCount1++;
        }

        // 添加一个初始的 Setter 监视器
        Proxy.addPropertySetterWatcher(obj1, "value", setterCallback1);

        // 记录添加大量回调前的时间
        var startAdd1:Number = getTimer();

        // 添加大量 Setter 回调
        for (var i1:Number = 0; i1 < numCallbacks1; i1++) {
            Proxy.addPropertySetterWatcher(obj1, "value", setterCallback1);
        }

        var endAdd1:Number = getTimer();
        var timeAdd1:Number = endAdd1 - startAdd1;

        trace("添加 " + numCallbacks1 + " 个 setter 回调耗时: " + timeAdd1 + " 毫秒");

        // 记录设置属性前的时间
        var startSet1:Number = getTimer();

        // 设置属性值，触发所有 Setter 回调
        obj1.value = 500;

        var endSet1:Number = getTimer();
        var timeSet1:Number = endSet1 - startSet1;

        trace("设置属性触发 " + numCallbacks1 + " 个 setter 回调耗时: " + timeSet1 + " 毫秒");
        trace("Setter 回调总调用次数: " + setterCallbackCount1);

        /**
         * 测试2: 多属性、多回调的 Setter 和 Getter 性能评估
         */
        trace("--- 测试2: 多属性、多回调 Setter 和 Getter 性能评估 ---");
        var obj2:Object = {}; // 创建一个空对象
        var numProperties2:Number = 100; // 被代理的属性数量
        var numCallbacks2:Number = 100; // 每个属性的回调数量
        var setterCallbackCount2:Number = 0; // 记录 Setter 回调的调用次数
        var getterCallbackCount2:Number = 0; // 记录 Getter 回调的调用次数

        /**
         * Setter 回调函数。
         * @param newValue 新的属性值。
         * @param oldValue 旧的属性值。
         */
        function setterCallback2(newValue:Number, oldValue:Number):Void {
            setterCallbackCount2++;
        }

        /**
         * Getter 回调函数。
         * @param value 当前属性值。
         */
        function getterCallback2(value:Number):Void {
            getterCallbackCount2++;
        }

        // 添加多属性代理和回调
        var startAdd2:Number = getTimer();
        for (var i2:Number = 0; i2 < numProperties2; i2++) {
            var propName2:String = "value" + i2;

            // 添加 Setter 和 Getter 代理
            Proxy.addPropertySetterWatcher(obj2, propName2, setterCallback2);
            Proxy.addPropertyGetterWatcher(obj2, propName2, getterCallback2);

            // 添加多个回调
            for (var j2:Number = 0; j2 < numCallbacks2; j2++) {
                Proxy.addPropertySetterWatcher(obj2, propName2, setterCallback2);
                Proxy.addPropertyGetterWatcher(obj2, propName2, getterCallback2);
            }
        }
        var endAdd2:Number = getTimer();

        trace("添加 " + numProperties2 + " 个属性，每个属性 " + numCallbacks2 + " 个回调耗时: " + (endAdd2 - startAdd2) + " 毫秒");

        // 测试设置和读取多个属性的性能
        var startAccess2:Number = getTimer();
        for (var k2:Number = 0; k2 < numProperties2; k2++) {
            var prop2:String = "value" + k2;
            obj2[prop2] = k2 * 10; // 设置属性
            var val2:Number = obj2[prop2]; // 读取属性
        }
        var endAccess2:Number = getTimer();

        trace("访问 " + numProperties2 + " 个属性触发所有回调耗时: " + (endAccess2 - startAccess2) + " 毫秒");
        trace("Setter 回调调用总次数: " + setterCallbackCount2);
        trace("Getter 回调调用总次数: " + getterCallbackCount2);

        /**
         * 测试3: 函数调用代理的性能评估
         */
        trace("--- 测试3: 函数调用代理性能评估 ---");
        var obj3:Object = {
            greet: function(name:String, age:Number):String {
                return "Hello, " + name + "! You are " + age + " years old.";
            }
        };
        var numFunctionCallbacks3:Number = 100; // 每个函数的回调数量
        var numFunctionCalls3:Number = 1000; // 函数调用次数
        var functionCallbackCallCount3:Number = 0; // 记录回调被调用的次数

        /**
         * 函数调用回调函数。
         * @param name 被调用方法的第一个参数。
         * @param age 被调用方法的第二个参数。
         */
        function functionCallback3(name:String, age:Number):Void {
            // trace("[DEBUG] functionCallback3 被调用");
            functionCallbackCallCount3++;
        }

        // 添加函数调用监视器
        Proxy.addFunctionCallWatcher(obj3, "greet", functionCallback3);

        // 添加多个函数调用回调
        for (var i3:Number = 0; i3 < numFunctionCallbacks3; i3++) {
            Proxy.addFunctionCallWatcher(obj3, "greet", functionCallback3);
        }

        // 调用函数，触发回调
        var startCall3:Number = getTimer();
        for (var j3:Number = 0; j3 < numFunctionCalls3; j3++) {
            obj3.greet("TestUser", 25);
        }
        var endCall3:Number = getTimer();

        trace("调用函数 " + numFunctionCalls3 + " 次触发所有回调耗时: " + (endCall3 - startCall3) + " 毫秒");
        trace("函数回调调用总次数: " + functionCallbackCallCount3);

        /**
         * 测试4: 移除大量 Setter 回调的性能评估
         */
        trace("--- 测试4: 移除大量 Setter 回调性能评估 ---");
        var obj4:Object = {}; // 创建一个空对象
        var numProperties4:Number = 50; // 被代理的属性数量
        var numCallbacks4:Number = 100; // 每个属性的回调数量
        var dummyCallback4:Function = function(newValue:Number, oldValue:Number):Void {}; // 虚拟回调函数

        // 添加回调
        var startAdd4:Number = getTimer();
        for (var i4:Number = 0; i4 < numProperties4; i4++) {
            var propName4:String = "value" + i4;
            for (var j4:Number = 0; j4 < numCallbacks4; j4++) {
                Proxy.addPropertySetterWatcher(obj4, propName4, dummyCallback4);
            }
        }
        var endAdd4:Number = getTimer();

        trace("添加 " + numProperties4 + " 个属性的 " + numCallbacks4 + " 个回调耗时: " + (endAdd4 - startAdd4) + " 毫秒");

        // 测试移除回调性能
        var startRemove4:Number = getTimer();
        for (var k4:Number = 0; k4 < numProperties4; k4++) {
            var propRemove4:String = "value" + k4;
            for (var l4:Number = 0; l4 < numCallbacks4; l4++) {
                Proxy.removePropertySetterWatcher(obj4, propRemove4, dummyCallback4);
            }
        }
        var endRemove4:Number = getTimer();

        trace("移除 " + numProperties4 + " 个属性的 " + numCallbacks4 + " 个回调耗时: " + (endRemove4 - startRemove4) + " 毫秒");

        /**
         * 测试5: 嵌套代理的性能评估
         */
        trace("--- 测试5: 嵌套代理性能评估 ---");
        var obj5:Object = {}; // 创建一个空对象
        var numLayers5:Number = 10; // 嵌套层数
        var nestedCallbackCount5:Number = 0; // 回调调用次数

        /**
         * 嵌套 Setter 回调函数。
         * @param newValue 新的属性值。
         * @param oldValue 旧的属性值。
         */
        function nestedCallback5(newValue:Number, oldValue:Number):Void {
            nestedCallbackCount5++;
        }

        // 添加嵌套代理
        var startAdd5:Number = getTimer();
        for (var i5:Number = 0; i5 < numLayers5; i5++) {
            Proxy.addPropertySetterWatcher(obj5, "value", nestedCallback5);
        }
        var endAdd5:Number = getTimer();

        trace("添加 " + numLayers5 + " 层嵌套代理耗时: " + (endAdd5 - startAdd5) + " 毫秒");

        // 设置属性值，触发所有嵌套回调
        var startSet5:Number = getTimer();
        obj5.value = 100;
        var endSet5:Number = getTimer();

        trace("设置属性触发嵌套回调耗时: " + (endSet5 - startSet5) + " 毫秒");
        trace("回调调用总次数: " + nestedCallbackCount5);

        /**
         * 扩展性能测试: Watch vs Proxy vs WatchWithWatch vs AddProperty
         * 测试场景：单属性 Setter、多属性管理、回调触发
         */
        trace("--- 扩展性能测试: Watch vs Proxy vs WatchWithWatch vs AddProperty ---");

        // 测试样例1: 单属性单回调性能
        this.testSinglePropertySingleCallback();

        // 测试样例2: 多属性多回调性能
        this.testMultiplePropertiesMultipleCallbacks();

        // 测试样例3: 高频触发场景
        this.testHighFrequencyTrigger();
    }

    /**
     * 测试样例1: 单属性单回调性能
     * 比较原生 watch、Proxy.addPropertySetterWatcher、Proxy.addPropertySetterWatcherWithWatch 和 addProperty 的性能
     */
    private function testSinglePropertySingleCallback():Void {
        trace("--- 测试样例1: 单属性单回调性能 ---");

        var objWatch:Object = {};
        var objProxy:Object = {};
        var objWatchWithWatch:Object = {};
        var objAddProperty:Object = {};

        var callbackCountWatch:Number = 0;
        var callbackCountProxy:Number = 0;
        var callbackCountWatchWithWatch:Number = 0;
        var callbackCountAddProperty:Number = 0;

        function setterCallbackWatch(prop:String, oldValue:Number, newValue:Number):Void {
            callbackCountWatch++;
        }

        function setterCallbackProxy(newValue:Number, oldValue:Number):Void {
            callbackCountProxy++;
        }

        function setterCallbackWatchWithWatch(newValue:Number, oldValue:Number):Void {
            callbackCountWatchWithWatch++;
        }

        function setterCallbackAddProperty(newValue:Number, oldValue:Number):Void {
            callbackCountAddProperty++;
        }

        var testRounds:Number = 50000; // 测试轮数

        // Watch 添加回调
        var startWatchAdd:Number = getTimer();
        for (var i:Number = 0; i < testRounds; i++) {
            objWatch.watch("value" + i, setterCallbackWatch);
        }
        var endWatchAdd:Number = getTimer();

        // Proxy 添加回调
        var startProxyAdd:Number = getTimer();
        for (var i:Number = 0; i < testRounds; i++) {
            Proxy.addPropertySetterWatcher(objProxy, "value" + i, setterCallbackProxy);
        }
        var endProxyAdd:Number = getTimer();

        // WatchWithWatch 添加回调
        var startWatchWithWatchAdd:Number = getTimer();
        for (var i:Number = 0; i < testRounds; i++) {
            Proxy.addPropertySetterWatcherWithWatch(objWatchWithWatch, "value" + i, setterCallbackWatchWithWatch);
        }
        var endWatchWithWatchAdd:Number = getTimer();

        // AddProperty 添加回调
        var startAddPropertyAdd:Number = getTimer();
        for (var i:Number = 0; i < testRounds; i++) {
            // 使用 addProperty 手动添加 Getter 和 Setter
            var internalPropName:String = "__value" + i + "__";
            objAddProperty[internalPropName] = undefined; // 初始化内部属性

            objAddProperty.addProperty("value" + i, 
                function():Number {
                    // 获取内部属性值
                    var index:Number = arguments.callee.propIndex;
                    return this["__value" + index + "__"];
                },
                function(newValue:Number):Void {
                    // Setter 回调
                    callbackCountAddProperty++;
                    var index:Number = arguments.callee.propIndex;
                    this["__value" + index + "__"] = newValue;
                }
            );

            // 关联 propIndex，以便 Getter 和 Setter 可以访问
            arguments.callee.propIndex = i;
        }
        var endAddPropertyAdd:Number = getTimer();

        // Watch 触发回调
        var startWatchSet:Number = getTimer();
        for (var i:Number = 0; i < 4; i++) {
            objWatch["value" + i] = 500;
        }
        var endWatchSet:Number = getTimer();

        // Proxy 触发回调
        var startProxySet:Number = getTimer();
        for (var i:Number = 0; i < 4; i++) {
            objProxy["value" + i] = 500;
        }
        var endProxySet:Number = getTimer();

        // WatchWithWatch 触发回调
        var startWatchWithWatchSet:Number = getTimer();
        for (var i:Number = 0; i < 4; i++) {
            objWatchWithWatch["value" + i] = 500;
        }
        var endWatchWithWatchSet:Number = getTimer();

        // AddProperty 触发回调
        var startAddPropertySet:Number = getTimer();
        for (var i:Number = 0; i < 4; i++) {
            objAddProperty["value" + i] = 500;
        }
        var endAddPropertySet:Number = getTimer();

        trace("Watch 添加单回调耗时: " + (endWatchAdd - startWatchAdd) + " ms");
        trace("Proxy 添加单回调耗时: " + (endProxyAdd - startProxyAdd) + " ms");
        trace("WatchWithWatch 添加单回调耗时: " + (endWatchWithWatchAdd - startWatchWithWatchAdd) + " ms");
        trace("AddProperty 添加单回调耗时: " + (endAddPropertyAdd - startAddPropertyAdd) + " ms");

        trace("Watch 设置属性耗时: " + (endWatchSet - startWatchSet) + " ms");
        trace("Proxy 设置属性耗时: " + (endProxySet - startProxySet) + " ms");
        trace("WatchWithWatch 设置属性耗时: " + (endWatchWithWatchSet - startWatchWithWatchSet) + " ms");
        trace("AddProperty 设置属性耗时: " + (endAddPropertySet - startAddPropertySet) + " ms");

        trace("Watch 回调调用次数: " + callbackCountWatch);
        trace("Proxy 回调调用次数: " + callbackCountProxy);
        trace("WatchWithWatch 回调调用次数: " + callbackCountWatchWithWatch);
        trace("AddProperty 回调调用次数: " + callbackCountAddProperty);
    }

    /**
     * 测试样例2: 多属性多回调性能
     * 仅针对 Proxy 方法，评估在多属性、多回调情况下的性能。
     */
    private function testMultiplePropertiesMultipleCallbacks():Void {
        trace("--- 测试样例2: 多属性多回调性能 ---");

        var objProxy:Object = {};
        var callbackCountProxy:Number = 0;

        function setterCallbackProxy(newValue:Number, oldValue:Number):Void {
            callbackCountProxy++;
        }

        var numProperties:Number = 300; // 属性数量
        var numCallbacks:Number = 30;  // 每属性回调数量

        // Proxy 添加回调
        var startProxyAdd:Number = getTimer();
        for (var i:Number = 0; i < numProperties; i++) {
            var propName:String = "prop" + i;
            for (var j:Number = 0; j < numCallbacks; j++) {
                Proxy.addPropertySetterWatcher(objProxy, propName, setterCallbackProxy);
            }
        }
        var endProxyAdd:Number = getTimer();

        // Proxy 触发回调
        var startProxySet:Number = getTimer();
        for (var i:Number = 0; i < numProperties; i++) {
            objProxy["prop" + i] = i * 10;
        }
        var endProxySet:Number = getTimer();

        trace("Proxy 添加多回调耗时: " + (endProxyAdd - startProxyAdd) + " ms");
        trace("Proxy 触发多回调耗时: " + (endProxySet - startProxySet) + " ms");
        trace("Proxy 回调调用次数: " + callbackCountProxy);
    }

    /**
     * 测试样例3: 高频触发场景
     * 评估在高频率修改属性值（5,000 次）时，Proxy 类的性能表现。
     */
    private function testHighFrequencyTrigger():Void {
        trace("--- 测试样例3: 高频触发场景 ---");

        var objProxy:Object = {};
        var callbackCountProxy:Number = 0;

        function setterCallbackProxy(newValue:Number, oldValue:Number):Void {
            callbackCountProxy++;
        }

        var numCallbacks:Number = 3000; // 回调数量

        // 添加回调
        Proxy.addPropertySetterWatcher(objProxy, "value", setterCallbackProxy);

        // 高频触发回调
        var startProxySet:Number = getTimer();
        for (var i:Number = 0; i < numCallbacks; i++) {
            objProxy.value = i;
        }
        var endProxySet:Number = getTimer();

        trace("Proxy 高频触发回调耗时: " + (endProxySet - startProxySet) + " ms");
        trace("Proxy 回调调用次数: " + callbackCountProxy);
    }
}
