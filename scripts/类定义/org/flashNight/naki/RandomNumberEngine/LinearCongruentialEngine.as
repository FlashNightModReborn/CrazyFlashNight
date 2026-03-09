import org.flashNight.naki.RandomNumberEngine.BaseRandomNumberEngine;

class org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine extends BaseRandomNumberEngine {
    // 静态单例实例
    public static var instance:LinearCongruentialEngine;

    // LCG 常量已烧录为字面量（a=1192433993, c=1013904223, m=2^32）
    // 1/m = 2.3283064365386963e-10（精确值，2^-32）
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

    // 重写 next() 方法生成下一个随机数
    // 使用线性同余生成器算法：Xn+1 = (a * Xn + c) % m
    // @return 下一个随机数
    public function next():Number {
        return seed = (1192433993 * seed + 1013904223) % 4294967296;
    }

    // 重写 nextFloat() 方法，根据线性同余生成器的特性生成 [0, 1) 区间内的浮点数
    // @return 0到1之间的随机浮点数
    public function nextFloat():Number {
        return (seed = (1192433993 * seed + 1013904223) % 4294967296) * 2.3283064365386963e-10;
    }

}
