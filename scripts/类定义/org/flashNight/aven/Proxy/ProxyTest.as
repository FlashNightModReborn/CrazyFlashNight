import org.flashNight.aven.Proxy.*;

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
        this.testAddPropertyGetterWatcher();
        this.testRemovePropertySetterWatcher();
        this.testRemovePropertyGetterWatcher();
        this.testMultipleCallbacks();
        this.testFunctionCallWatcher();
        this.testPerformance(); // 性能测试暂时注释
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
     * 性能测试。
     * 测试在大量添加和调用回调时的性能开销。
     * 注意：此测试可能会消耗较多资源，建议在需要时启用。
     */
    private function testPerformance():Void {
        trace("--- 测试: 性能评估 ---");
        var obj:Object = {}; // 创建一个空对象
        var numCallbacks:Number = 1000; // 添加的回调数量
        var setterCallbackCount:Number = 0; // 记录 Setter 回调的调用次数

        var assertFuncRef:Function = this.assertFunc; // 引用断言方法

        /**
         * Setter 回调函数。
         * 每次属性被设置时，此函数被调用，记录调用次数。
         * @param newValue 新的属性值。
         * @param oldValue 旧的属性值。
         */
        function setterCallback(newValue:Number, oldValue:Number):Void {
            setterCallbackCount++;
        }

        // 添加一个初始的 Setter 监视器
        Proxy.addPropertySetterWatcher(obj, "value", setterCallback);

        // 记录添加大量回调前的时间
        var startAdd:Number = getTimer();

        // 添加大量 Setter 回调
        for (var i:Number = 0; i < numCallbacks; i++) {
            Proxy.addPropertySetterWatcher(obj, "value", setterCallback);
        }

        var endAdd:Number = getTimer();
        var timeAdd:Number = endAdd - startAdd;

        trace("添加 " + numCallbacks + " 个 setter 回调耗时: " + timeAdd + " 毫秒");

        // 记录设置属性前的时间
        var startSet:Number = getTimer();

        // 设置属性值，触发所有 Setter 回调
        obj.value = 500;

        var endSet:Number = getTimer();
        var timeSet:Number = endSet - startSet;

        trace("设置属性触发 " + numCallbacks + " 个 setter 回调耗时: " + timeSet + " 毫秒");
        trace("Setter 回调总调用次数: " + setterCallbackCount);

        // 记录移除回调前的时间
        var startRemove:Number = getTimer();

        // 移除所有 Setter 回调
        for (var j:Number = 0; j < numCallbacks; j++) {
            Proxy.removePropertySetterWatcher(obj, "value", setterCallback);
        }

        var endRemove:Number = getTimer();
        var timeRemove:Number = endRemove - startRemove;

        trace("移除 " + numCallbacks + " 个 setter 回调耗时: " + timeRemove + " 毫秒");

        // 断言性能在合理范围内（具体值可根据实际环境调整）
        this.assert(timeAdd < 1000, "添加回调的性能在合理范围内");
        this.assert(timeSet < 1000, "触发回调的性能在合理范围内");
        this.assert(timeRemove < 1000, "移除回调的性能在合理范围内");
    }
}
