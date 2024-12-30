// LazyFunctionTest.as
import org.flashNight.gesh.func.LazyFunction;

class org.flashNight.gesh.func.LazyFunctionTest {
    private var testCount:Number;
    private var initCount:Number;
    private var targetCount:Number;

    public function LazyFunctionTest() {
        testCount = 0;
        initCount = 0;
        targetCount = 0;
    }

    /**
     * 内置断言方法。
     * @param condition 条件表达式。
     * @param message 断言失败时的错误信息。
     */
    private function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("Assertion failed: " + message);
        }
    }

    /**
     * 测试懒初始化功能。
     */
    public function testLazyInitialization():Void {
        var initializerExecuted:Boolean = false;
        var targetExecuted:Boolean = false;

        var lazyFunc:LazyFunction = new LazyFunction(
            function() {
                initializerExecuted = true;
            },
            function() {
                targetExecuted = true;
            }
        );

        // 在初始化前，初始化函数未执行
        assert(!initializerExecuted, "Initializer should not execute before first call.");

        // 执行第一次调用，初始化函数应执行
        lazyFunc.execute();
        assert(initializerExecuted, "Initializer should execute on first call.");
        assert(targetExecuted, "Target function should execute on first call.");
    }

    /**
     * 测试参数传递功能。
     */
    public function testParameterPassing():Void {
        var receivedArgs:Array = [];

        var lazyFunc:LazyFunction = new LazyFunction(
            function() {},
            function(arg1, arg2) {
                receivedArgs.push(arg1);
                receivedArgs.push(arg2);
            }
        );

        lazyFunc.execute("hello", 123);
        assert(receivedArgs.length == 2, "Should receive two arguments.");
        assert(receivedArgs[0] == "hello", "First argument should be 'hello'.");
        assert(receivedArgs[1] == 123, "Second argument should be 123.");
    }

    /**
     * 测试多次调用不重复初始化。
     */
    public function testMultipleCalls():Void {
        var initExecutionCount:Number = 0;
        var targetExecutionCount:Number = 0;

        var lazyFunc:LazyFunction = new LazyFunction(
            function() {
                initExecutionCount++;
            },
            function() {
                targetExecutionCount++;
            }
        );

        // 第一次调用
        lazyFunc.execute();
        assert(initExecutionCount == 1, "Initializer should execute once on first call.");
        assert(targetExecutionCount == 1, "Target function should execute once on first call.");

        // 第二次调用
        lazyFunc.execute();
        assert(initExecutionCount == 1, "Initializer should not execute again.");
        assert(targetExecutionCount == 2, "Target function should execute again.");
    }

    /**
     * 运行所有测试。
     */
    public function runTests():Void {
        testLazyInitialization();
        trace("testLazyInitialization passed.");

        testParameterPassing();
        trace("testParameterPassing passed.");

        testMultipleCalls();
        trace("testMultipleCalls passed.");

        trace("All LazyFunction tests passed successfully.");
    }
}
