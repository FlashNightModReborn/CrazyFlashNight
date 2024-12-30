// LazyFunction.as
class org.flashNight.gesh.func.LazyFunction {
    private var initializer:Function;
    private var initialized:Boolean = false;
    private var targetFunction:Function;

    public function LazyFunction(initializer:Function, targetFunction:Function) {
        this.initializer = initializer;
        this.targetFunction = targetFunction;
    }

    public function execute():Void {
        if (!initialized) {
            initializer.apply(null, arguments);
            initialized = true;
            // 替换 execute 方法为目标函数
            this.execute = targetFunction;
        }
        // 调用目标函数
        this.execute.apply(null, arguments);
    }
}
