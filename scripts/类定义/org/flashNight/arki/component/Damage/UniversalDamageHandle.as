import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * UniversalDamageHandle 类用于处理通用伤害以及躲闪状态的处理器。
 *
 * 【控制流设计】
 * 正向频率分派：破击 → 魔法 → 真伤 → 物理(fallback)
 * 基于最优线性搜索定理，特殊伤害按运行时频率降序排列（破击 > 魔法 > 真伤）。
 * 破击最高频：装备模组系统让任何武器都能通过插件获得破击伤害类型。
 * 物理作为 catch-all fallback（覆盖 undefined/"物理"/空字符串/任何未知类型）。
 *
 * 【惰性求值】
 * 顶部仅预取所有路径共用的 t/power/enemy 三个基元变量。
 * target.防御力/魔法抗性/等级 延迟到各分支内部按需读取，
 * 物理路径（最高频）完全不触碰魔法抗性和等级的 GetMember 开销。
 *
 * 【数学优化】
 * 魔法抗性软上限代数化简：
 *   原式 95+(rv-95)/11 > 100 等价于 rv > 150
 *   95+(rv-95)/11 通分化简为 (rv+950)/11
 * 消除重复除法与加减运算。
 *
 * 【内联策略】
 * defenseDamageRatio 内联为 300/(def+300)：省去 ClassName.staticMethod() 调用税 ~1340ns。
 * 原始公式定义于 DamageResistanceHandler.defenseDamageRatio，修改时需同步。
 * isMagicDamageType 缓存为静态函数引用：从方法调用 ~1340ns 降至函数调用 ~485ns。
 *
 * 【取整策略】
 * 所有伤害值不在此处取整，统一交给后续工序处理。
 */
class org.flashNight.arki.component.Damage.UniversalDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========
    public static var instance:UniversalDamageHandle = new UniversalDamageHandle();

    // ========== 静态函数引用缓存 ==========
    // 缓存 isMagicDamageType 到局部函数引用，消除方法调用的类名查找税
    // 方法调用 ~1340ns → 函数调用 ~485ns [T2 S01]
    private static var _isMagicType:Function = MagicDamageTypes.isMagicDamageType;

    public function UniversalDamageHandle() {
        this.skipCheck = true;
    }

    /** 获取单例实例（饿汉式，直接返回） */
    public static function getInstance():UniversalDamageHandle {
        return instance;
    }

    public function canHandle(bullet:Object):Boolean {
        return true;
    }

    /**
     * 处理子弹伤害的核心方法
     *
     * @param bullet  子弹对象，包含伤害类型、破坏力、魔法伤害属性等
     * @param shooter 射击者对象
     * @param target  目标对象，包含防御力、等级、魔法抗性等
     * @param manager 管理器对象
     * @param result  伤害结果对象，用于设置颜色和特效
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // ========== 阶段一：最小预取（所有路径共用） ==========
        var t:String = bullet.伤害类型;
        var power:Number = bullet.破坏力;
        var enemy:Boolean = bullet.是否为敌人;

        // ========== 阶段二：正向频率分派 ==========
        // 特殊伤害按频率降序：破击 > 魔法 > 真伤
        // 破击最高频：装备模组系统让任何武器都能通过插件获得破击伤害类型

        // ---------- 破击伤害（特殊伤害中最高频，混合物理+魔法） ----------
        if (t == "破击") {
            result._dmgColorId = enemy ? 1 : 2;

            var mAttr2:String = bullet.魔法伤害属性;
            if (!mAttr2) mAttr2 = "能";

            // AS2 安全穿透：undefined[key] → undefined，无需预检 resistTbl
            var rValRaw = target.魔法抗性[mAttr2];

            // 内联 defenseDamageRatio: 300/(def+300)，省去方法调用税 ~1340ns
            var physPart:Number = power * 300 / (target.防御力 + 300);

            // 关键剪枝：仅在抗性存在时才查询魔法属性类型
            if (rValRaw != undefined) {
                // 使用缓存的函数引用，避免 ClassName.method() 调用税
                var isMagicTag:Boolean = _isMagicType(mAttr2);
                var rate:Number = isMagicTag ? 0.1 : 0.5;
                var rVal:Number = Number(rValRaw);
                rVal = ((rVal - rVal) != 0) ? 20
                    : (rVal < -1000 ? -1000
                    : (rVal > 100 ? 100
                    : rVal));

                target.损伤值 = physPart + (power * rate) * (100 - rVal) / 100;

                result._efFlags |= 16; // EF_CRUSH_LABEL
                result._efEmoji = isMagicTag ? "✨" : "☠";
                result._efText = mAttr2;
            } else {
                // 无匹配抗性，退化为纯物理
                target.损伤值 = physPart;
            }
            return;
        }

        // ---------- 魔法伤害 ----------
        if (t == "魔法") {
            result._dmgColorId = enemy ? 5 : 6;
            result._efFlags |= enemy ? 136 : 8; // 常量折叠: 8 | 128 = 136

            var mAttr3:String = bullet.魔法伤害属性;
            result._efText = mAttr3 ? mAttr3 : "能";

            // 惰性求值：仅魔法路径读取抗性表（单次查表，每个 key 最多查一次）
            var resistTbl:Object = target.魔法抗性;
            var rvRaw = mAttr3 ? resistTbl[mAttr3] : undefined;
            if (rvRaw == undefined) {
                rvRaw = resistTbl["基础"];
            }

            var rv:Number;
            if (rvRaw != undefined) {
                rv = Number(rvRaw);
            } else {
                // 终极惰性：等级仅在无任何抗性数据时才读取
                rv = 10 + target.等级 / 2;
            }

            // NaN 极速守卫 [T1a H07] + 代数化简的软上限夹取
            // 原式: rv > 95 ? (95+(rv-95)/11 > 100 ? 100 : 95+(rv-95)/11) : rv
            // 化简: 95+(rv-95)/11 > 100 等价于 rv > 150; 95+(rv-95)/11 = (rv+950)/11
            rv = ((rv - rv) != 0) ? 20
                : (rv < -1000 ? -1000
                : (rv > 150 ? 100
                : (rv > 95 ? (rv + 950) / 11
                : rv)));

            target.损伤值 = power * (100 - rv) / 100;
            return;
        }

        // ---------- 真实伤害（无需任何抗性计算，极简路径） ----------
        if (t == "真伤") {
            result._dmgColorId = enemy ? 3 : 4;
            result._efFlags |= enemy ? 136 : 8;
            result._efText = "真";
            target.损伤值 = power;
            return;
        }

        // ---------- 物理伤害（fallback，运行时最高频） ----------
        // catch-all：未定义/"物理"/空字符串/任何未知类型均走此路径
        result._dmgColorId = enemy ? 1 : 2;
        // 内联 DamageResistanceHandler.defenseDamageRatio: 300/(def+300)
        // 省去 ClassName.staticMethod() 调用税 ~1340ns
        target.损伤值 = power * 300 / (target.防御力 + 300);
    }

    public function toString():String {
        return "UniversalDamageHandle";
    }
}
