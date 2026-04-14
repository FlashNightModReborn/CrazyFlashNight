import org.flashNight.naki.RandomNumberEngine.BaseRandomNumberEngine;

/*
 * LinearCongruentialEngine 线性同余随机数引擎（项目通用引擎）
 *
 * ⚠ 封闭叶类（Sealed Leaf Class），不得被继承
 * -------------------------------
 * 本类的 randomFluctuation / randomOffset / randomFloatOffset / randomInteger /
 * randomIntegerStrict / randomFloat / successRate 共 7 个助手方法，均已把
 * 内部的 nextFloat() 调用硬编码展开成单步 LCG 公式，绕过原型链虚派发以提速。
 *
 * 后果：若任何子类继承本类并覆盖 nextFloat()，上述助手仍会执行 LCG 公式，
 * 直接读写 this.seed 后返回均匀分布——完全绕过子类的 nextFloat()，
 * 导致子类的随机分布特性（如 PinkNoise 的 1/f 频谱）被静默破坏，且无运行时报错。
 *
 * 历史踩坑：PinkNoiseEngine 原继承本类，2026-04 重构改为直接继承 Base。
 * 详见 PinkNoiseEngine.as 顶部"继承关系说明"段落与本目录 README.md。
 *
 * 规则：新增随机数引擎一律直接继承 BaseRandomNumberEngine；若需复用本类算法，
 * 通过常量复制（硬编码 1192433993 / 1013904223 / 4294967296 / 2.3283064365386963e-10）
 * 或 HAS-A 组合实现，禁止 extends LinearCongruentialEngine。
 */
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

    // ==================== 热路径内联重写 ====================
    // 下列方法覆盖 BaseRandomNumberEngine 中的同名继承版本，
    // 将内部对 nextFloat() 的调用直接展开为 seed 更新，
    // 省掉一次原型链方法查找 + 函数调用。调用方代码无需改动。
    // 同步把 /100 等常量除法化为乘法（无回放一致性需求）。

    // 覆盖：伤害/外观波动（ShellSystem 每弹壳每帧、其它特效）
    public function randomFluctuation(fluctuationRange:Number):Number {
        var r:Number = (seed = (1192433993 * seed + 1013904223) % 4294967296) * 2.3283064365386963e-10;
        return 1 + (r * fluctuationRange * 2 - fluctuationRange) * 0.01;
    }

    // 覆盖：整数偏移（BulletFactory 子弹散射角、HitNumberSystem 等）
    public function randomOffset(range:Number):Number {
        var r:Number = (seed = (1192433993 * seed + 1013904223) % 4294967296) * 2.3283064365386963e-10;
        return ((r * (range * 2 + 1)) >> 0) - range;
    }

    // 覆盖：浮点偏移（ShellSystem 弹壳物理、HitNumberSystem）
    public function randomFloatOffset(range:Number):Number {
        var r:Number = (seed = (1192433993 * seed + 1013904223) % 4294967296) * 2.3283064365386963e-10;
        return r * (range * 2) - range;
    }

    // 覆盖：区间随机整数（WaveSpawner / CombatModule / EnemyBehavior 共约 36 个热点调用）
    public function randomInteger(min:Number, max:Number):Number {
        var r:Number = (seed = (1192433993 * seed + 1013904223) % 4294967296) * 2.3283064365386963e-10;
        return ((r * (max - min + 1)) >> 0) + min;
    }

    // 覆盖：randomInteger 的别名（向后兼容接口同样展开）
    public function randomIntegerStrict(min:Number, max:Number):Number {
        var r:Number = (seed = (1192433993 * seed + 1013904223) % 4294967296) * 2.3283064365386963e-10;
        return ((r * (max - min + 1)) >> 0) + min;
    }

    // 覆盖：区间随机浮点（ShellSystem 弹壳轨迹）
    public function randomFloat(min:Number, max:Number):Number {
        var r:Number = (seed = (1192433993 * seed + 1013904223) % 4294967296) * 2.3283064365386963e-10;
        return r * (max - min) + min;
    }

    // 覆盖：百分比成功判定（DodgeHandler 每次伤害 2 次闪避判定）
    public function successRate(probabilityPercent:Number):Boolean {
        var r:Number = (seed = (1192433993 * seed + 1013904223) % 4294967296) * 2.3283064365386963e-10;
        return r * 100 <= probabilityPercent;
    }

}
