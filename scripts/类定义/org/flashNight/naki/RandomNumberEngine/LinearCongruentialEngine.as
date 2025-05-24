import org.flashNight.naki.RandomNumberEngine.BaseRandomNumberEngine;

class org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine extends BaseRandomNumberEngine {
    // 静态单例实例
    public static var instance:LinearCongruentialEngine;

    // 实例变量
    private var a:Number = 1192433993;   // 乘数
    private var c:Number = 1013904223;   // 增量
    private var m:Number = 4294967296;   // 模数
    private var seed:Number;             // 种子

    // 私有构造函数，防止外部直接实例化
    private function LinearCongruentialEngine() {
        // 使用当前时间作为默认种子
        seed = new Date().getTime(); 
    }

    // 静态方法获取单例实例
    // 如果实例不存在则创建一个新的实例
    public static function getInstance():LinearCongruentialEngine {
        if (instance == null) {
            instance = new LinearCongruentialEngine();
            // redefine getInstance to return instance directly
            getInstance = function():LinearCongruentialEngine {
                return instance;
            };
        }
        return instance;
    }

    // 初始化生成器
    // @param a: 乘数
    // @param c: 增量
    // @param m: 模数
    // @param seed: 初始种子
    public function init(a:Number, c:Number, m:Number, seed:Number):Void {
        this.a = a;
        this.c = c;
        this.m = m;
        this.seed = seed;
    }

    // 重写 next() 方法生成下一个随机数
    // 使用线性同余生成器算法：Xn+1 = (a * Xn + c) % m
    // @return 下一个随机数
    public function next():Number {
        return seed = (a * seed + c) % m;
    }
    
    // 重写 nextFloat() 方法，根据线性同余生成器的特性生成 [0, 1) 区间内的浮点数
    // @return 0到1之间的随机浮点数
    public function nextFloat():Number {
        return (seed = (a * seed + c) % m) / m;
    }

}
