class org.flashNight.gesh.func.LazyFunction {
    private var initializer:Function;
    private var initialized:Boolean = false;
    private var targetFunction:Function;

    public function LazyFunction(initializer:Function, targetFunction:Function) {
        if (typeof(initializer) != "function" || typeof(targetFunction) != "function") {
            throw new Error("Invalid parameters: initializer and targetFunction must be functions.");
        }
        this.initializer = initializer;
        this.targetFunction = targetFunction;
    }

    public function execute():Void {
        if (!initialized) {
            try {
                // 调用初始化函数
                initializer.apply(this, arguments);
                initialized = true;
                // 替换 execute 方法为目标函数，直接传递参数避免额外开销
                var self = this;
                this.execute = function() {
                    targetFunction.apply(self, arguments);
                };
            } catch (e:Error) {
                trace("Error during initialization: " + e.message);
                throw e;
            }
        }
        // 调用目标函数
        this.execute.apply(this, arguments);
    }
}
