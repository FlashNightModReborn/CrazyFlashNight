import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/*
 * PseudoRandomDistribution 伪随机分布（PRD）
 *
 * 核心思想
 * -------------------------------
 * 纯均匀随机会出现"长龙"——名义 20% 概率玩家可能连刷 15 次落空，数学正常但心态崩坏。
 * PRD 维护一张 key → 连续失败次数 N 的计数表，每次判定时让触发概率 = C × (N+1)，
 * 命中即把 N 清零。长期期望不变，但方差被压缩到接近期望，让"运气"贴近"概率"。
 * 业界出处：DotA 2 的暴击/触发、Warframe 部分掉落、若干 ARPG 的稀有掉宝。
 *
 * 参数 C 的来历
 * -------------------------------
 * C 满足 E(trials, C) = 1/P，其中 E(C) = Σ_{n=0..N-1} Π_{k=1..n}(1 - C·k)，
 * N = ⌈1/C⌉。该方程无封闭解，本类用离线（构建期）二分迭代求解后将结果硬编码为
 * P_TABLE / C_TABLE，运行时仅做二分查表 + 线性插值，单次 roll < 10 次浮点运算。
 * 表格在 [0.005, 0.95] 范围内插值误差 < 4%（低 P 区由于 C(P) 曲率大误差略高，
 * 但 4% 的 C 偏差对应不到 4% 的长期触发率偏差，对玩家心态无可感知影响）。
 *
 * 状态外置（与 SaveManager 零 glue）
 * -------------------------------
 * 计数表通过构造函数注入外部 Object 引用，所有 mutation 都发生在同一份引用上。
 * 调用方把存档对象的某个字段（例如 _root.killStats.dropPRD）传进来，
 * SaveManager 既有序列化路径就能直接覆盖，无需引擎实现 export/import。
 *
 * 与具体业务无耦合
 * -------------------------------
 * 引擎只关心字符串 key 和概率 p，不知道"掉落"、"暴击"、"感应力"等概念。
 * Magic-Find 类乘数由调用方在传入 P 前完成（effectiveP = nominalP × (1 + bonus)）。
 */
class org.flashNight.naki.PseudoRandom.PseudoRandomDistribution {

    // 失败计数表：key (String) → 连续失败次数 (Number)
    // 通过构造函数注入外部对象引用；命中清零，未命中递增。
    private var counters:Object;

    // P → C 查表（离线用二分迭代求 E(C)=1/P 得到，构建期一次性写死）
    // 采样在低 P 区加密以匹配 C(P) 曲率。注意：低于 P_TABLE[0] 时按"线性外推到原点"
    // 处理，高于 P_TABLE 末尾时返回末尾值（再上去就接近必中，PRD 意义不大）。
    private static var P_TABLE:Array = [
        0.005,   0.0075,  0.01,    0.0125,  0.015,   0.0175,
        0.02,    0.025,   0.03,    0.035,   0.04,    0.05,
        0.06,    0.07,    0.08,    0.09,    0.10,    0.12,
        0.15,    0.18,    0.20,    0.25,    0.30,    0.35,
        0.40,    0.45,    0.50,    0.55,    0.60,    0.65,
        0.70,    0.75,    0.80,    0.85,    0.90,    0.95
    ];
    private static var C_TABLE:Array = [
        3.913959e-05,  8.7918443e-05, 0.00015604169, 0.00024341416, 0.00034994151,
        0.00047553023, 0.00062008762, 0.00096574158, 0.0013861777,  0.0018806827,
        0.0024485555,  0.0038016583,  0.0054401086,  0.0073587053,  0.0095524157,
        0.012016368,   0.014745845,   0.020983228,   0.032220914,   0.045620135,
        0.055704043,   0.084744092,   0.11894919,    0.1579831,     0.20154741,
        0.249307,      0.30210303,    0.36039785,    0.42264973,    0.48112548,
        0.57142857,    0.66666667,    0.75,          0.82352941,    0.88888889,
        0.94736842
    ];

    /*
     * 构造：注入外部 state 对象作为 counters 后端
     * @param stateRef  外部计数表对象；传 undefined 则用本地新对象（无持久化）
     */
    public function PseudoRandomDistribution(stateRef:Object) {
        counters = (stateRef != undefined) ? stateRef : {};
    }

    /*
     * 重新绑定 state 引用（用于场景切换、读档后重新挂接）
     */
    public function attachState(stateRef:Object):Void {
        counters = (stateRef != undefined) ? stateRef : {};
    }

    /*
     * 返回当前 counters 引用，供调试 / 序列化外检
     */
    public function getState():Object {
        return counters;
    }

    public function getFailCount(key:String):Number {
        var n:Number = counters[key];
        return (n > 0) ? n : 0;
    }

    public function reset(key:String):Void {
        delete counters[key];
    }

    public function resetAll():Void {
        for (var k:String in counters) {
            delete counters[k];
        }
    }

    /*
     * 主入口：按 PRD 判定是否命中
     * @param key  计数表键（例如 "兵种A|物品X"）
     * @param p    名义概率 ∈ [0, 1]；越界自动 clamp
     * @return     是否命中（命中即把 counters[key] 清零）
     */
    public function roll(key:String, p:Number):Boolean {
        // 边界：p ≤ 0 永远不中（不累计失败，否则不可达 key 也会污染表）
        if (!(p > 0)) return false;
        // 边界：p ≥ 1 必中
        if (p >= 1) { delete counters[key]; return true; }

        var c:Number = lookupC(p);
        var n:Number = counters[key];
        if (!(n > 0)) n = 0;
        var pNow:Number = c * (n + 1);
        if (pNow > 1) pNow = 1;

        // 与项目其它判定共用熵源，保持种子单线统一
        if (LinearCongruentialEngine.instance.nextFloat() < pNow) {
            delete counters[key];
            return true;
        }
        counters[key] = n + 1;
        return false;
    }

    /*
     * 偷看下一次的实际触发概率，不消费计数
     * 用于 UI 显示 "已连续 N 次未触发，下次触发率 X%" 等场景
     */
    public function peekProbability(key:String, p:Number):Number {
        if (!(p > 0)) return 0;
        if (p >= 1) return 1;
        var c:Number = lookupC(p);
        var n:Number = counters[key];
        if (!(n > 0)) n = 0;
        var pNow:Number = c * (n + 1);
        return (pNow > 1) ? 1 : pNow;
    }

    /*
     * P → C 查表 + 线性插值
     * 二分定位区间后插值；表外按线性外推 / 末尾 clamp 处理
     */
    private static function lookupC(p:Number):Number {
        var n:Number = P_TABLE.length;
        if (p <= P_TABLE[0]) {
            // 线性外推至原点：在 P→0 时 C/P → 0（保持斜率连续）
            return C_TABLE[0] * p / P_TABLE[0];
        }
        var hi:Number = n - 1;
        if (p >= P_TABLE[hi]) return C_TABLE[hi];

        var lo:Number = 0;
        while (lo + 1 < hi) {
            var mid:Number = (lo + hi) >> 1;
            if (P_TABLE[mid] <= p) lo = mid; else hi = mid;
        }
        var p0:Number = P_TABLE[lo];
        var p1:Number = P_TABLE[hi];
        var c0:Number = C_TABLE[lo];
        var c1:Number = C_TABLE[hi];
        return c0 + (c1 - c0) * (p - p0) / (p1 - p0);
    }
}
