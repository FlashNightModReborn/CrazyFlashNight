/**
 * 文件路径: org/flashNight/naki/DP/DynamicProgramming.as
 */
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * 通用的动态规划类（Top-Down + Memoization）。
 * 使用时通过 initialize(...) 指定:
 *    - problemSize: 全局的上下文/规模信息
 *    - transitionFunction: 状态转移方程
 * 然后通过 solve(context, param) 来递归求解子问题。
 */
class org.flashNight.naki.DP.DynamicProgramming {
    private var cache:Dictionary;           // 缓存结构
    private var transitionFunction:Function; // 状态转移方程
    private var problemSize:Object;         // 问题规模/上下文信息

    /**
     * 构造函数
     */
    public function DynamicProgramming() {
        this.cache = new Dictionary();
        this.transitionFunction = null;
        this.problemSize = null;
    }

    /**
     * 初始化 DP
     * @param size           问题规模或其它上下文信息（如 items, 字符串，网格等）
     * @param transitionFunc 状态转移方程 function(context:Object, param:Object, dp:DynamicProgramming):Number
     */
    public function initialize(size:Object, transitionFunc:Function):Void {
        this.cache.clear();
        this.problemSize = size;
        this.transitionFunction = transitionFunc;
    }

    /**
     * 生成稳定键的内部方法：
     * 如果 context 是 string 或 number，直接转为 String；否则根据其 key-value 对拼成字符串。
     */
    private function generateKey(context:Object):String {
        var t:String = typeof(context);
        if (t == "string" || t == "number") {
            // 如果就是数字或字符串，则直接返回
            return String(context);
        }

        // 对象情况：将 key-value 收集到数组后排序并拼接，防止键顺序导致冲突
        var keyParts:Array = [];
        for (var prop in context) {
            keyParts.push(prop + "=" + context[prop]);
        }
        keyParts.sort();
        return keyParts.join("|");
    }

    /**
     * DP 求解方法
     * @param context  当前子问题标识（可为 number / string / {字段...}）
     * @param param    额外参数，用于传递到 transitionFunction
     * @return         DP 计算结果
     */
    public function solve(context:Object, param:Object):Number {
        // 基于 context 生成可重复的 Key
        var uid:String = generateKey(context);

        // 如果缓存中已有结果，直接返回
        var cachedValue:Object = this.cache.getItem(uid);
        if (cachedValue != undefined) {
            return Number(cachedValue);
        }

        // 如果没有定义 transitionFunction，抛出异常
        if (this.transitionFunction == null) {
            throw new Error("Transition function is not defined.");
        }

        // 计算结果
        var result:Number = this.transitionFunction(context, param, this);

        // 存入缓存
        this.cache.setItem(uid, result);
        return result;
    }

    /**
     * 清空缓存
     */
    public function clearCache():Void {
        this.cache.clear();
    }

    /**
     * 获取当前缓存（调试用）
     */
    public function getCache():Dictionary {
        return this.cache;
    }

    /**
     * 获取问题规模/上下文
     */
    public function getProblemSize():Object {
        return this.problemSize;
    }
}
