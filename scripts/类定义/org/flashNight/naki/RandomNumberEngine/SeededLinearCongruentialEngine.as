import org.flashNight.naki.RandomNumberEngine.BaseRandomNumberEngine;

class org.flashNight.naki.RandomNumberEngine.SeededLinearCongruentialEngine extends BaseRandomNumberEngine {
    // 实例变量
    private var a:Number = 1192433993;   // 乘数
    private var c:Number = 1013904223;   // 增量
    private var m:Number = 4294967296;   // 模数
    private var seed:Number;             // 种子

    // 构造函数，允许通过种子直接初始化
    // @param seed: 初始种子
    public function SeededLinearCongruentialEngine(seed:Number) {
        this.seed = seed; // 使用提供的种子进行初始化
    }

    // 初始化生成器参数
    // @param a: 乘数
    // @param c: 增量
    // @param m: 模数
    public function init(a:Number, c:Number, m:Number):Void {
        this.a = a;
        this.c = c;
        this.m = m;
    }

    // 生成下一个随机数
    // 使用线性同余生成器算法：Xn+1 = (a * Xn + c) % m
    // @return 下一个随机数
    public function next():Number {
        seed = (a * seed + c) % m;
        trace("SeededLinearCongruentialEngine next: " + seed);
        return seed;
    }
    
    // 生成一个 [0, 1) 区间内的随机浮点数
    // @return 0到1之间的随机浮点数
    public function nextFloat():Number {
        return next() / m; // 确保结果在 [0, 1) 区间内
    }
}
