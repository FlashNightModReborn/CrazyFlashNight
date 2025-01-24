class org.flashNight.naki.DP.DynamicProgramming {
    private var cache:Object; // 缓存
    private var transitionFunction:Function; // 状态转移方程
    private var problemSize:Object; // 问题规模或边界

    // 构造函数
    public function DynamicProgramming() {
        this.cache = {};
        this.transitionFunction = null;
        this.problemSize = null;
    }

    // 初始化方法
    public function initialize(size:Object, transitionFunc:Function):Void {
        this.cache = {}; // 清空缓存
        this.problemSize = size;
        this.transitionFunction = transitionFunc;
    }

    // 获取结果
    public function solve(state:String):Number {
        // 如果状态已缓存，直接返回结果
        if (this.cache[state] != undefined) {
            return this.cache[state];
        }

        // 检查转移方程是否定义
        if (this.transitionFunction == null) {
            throw new Error("Transition function is not defined.");
        }

        // 调用转移方程计算结果并存入缓存
        var result:Number = this.transitionFunction(state, this.cache);
        this.cache[state] = result;
        return result;
    }

    // 清空缓存
    public function clearCache():Void {
        this.cache = {};
    }

    // 获取当前缓存内容（调试用）
    public function getCache():Object {
        return this.cache;
    }
}
