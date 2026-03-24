/**
 * 共享 LCG (Linear Congruential Generator)
 * 参数与 AS2 侧 SeededLinearCongruentialEngine 完全一致
 *
 * 已知风险：a * seed 最大约 5.12e18，超过 Number.MAX_SAFE_INTEGER (2^53)
 * 精度损失行为需与 AS2 对拍验证
 */
function createLCG(seed) {
    const a = 1192433993;
    const c = 1013904223;
    const m = 4294967296; // 2^32
    return {
        next() {
            seed = (a * seed + c) % m;
            return seed;
        }
    };
}

module.exports = { createLCG };
