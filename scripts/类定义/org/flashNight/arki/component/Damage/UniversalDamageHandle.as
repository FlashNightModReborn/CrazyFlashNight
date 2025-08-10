import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * UniversalDamageHandle 类用于处理通用伤害以及躲闪状态的处理器。
 * - 完全复制原有脚本的逻辑，确保功能一致。
 * - 后续可进行优化，如减少重复代码、提高性能等。
 */
class org.flashNight.arki.component.Damage.UniversalDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========
    public static var instance:UniversalDamageHandle = new UniversalDamageHandle();

    /**
     * 构造函数。
     * 初始化时设置 skipCheck 为 true，表示始终处理伤害和躲闪状态。
     */
    public function UniversalDamageHandle() {
        this.skipCheck = true;
    }

    /**
     * 获取 UniversalDamageHandle 的单例实例 (闭包优化)。
     */
    public static function getInstance():UniversalDamageHandle {
        if (instance == null) {
            instance = new UniversalDamageHandle();
            getInstance = function():UniversalDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    /**
     * 始终返回 true，表示可处理所有子弹。
     */
    public function canHandle(bullet:Object):Boolean {
        return true;
    }

    /**
     * 处理子弹伤害的核心方法 - 高性能优化版本
     * 
     * 【设计原理】
     * 本方法基于"频率导向的分支优化"设计，将最常见的物理伤害放在第一个分支，
     * 通过早退机制实现均摊O(1)复杂度。后续分支按伤害类型频率排序：破击 > 魔法 > 真伤。
     * 
     * 【执行流程概览】
     * 1. 预取变量，减少对象属性访问开销
     * 2. 设置默认物理伤害颜色
     * 3. 物理伤害快速路径（1次if + 早退）
     * 4. 非物理伤害二分路由（破击 vs 魔法/真伤）
     * 5. 每个分支内部避免无效计算，按需执行
     * 
     * 【性能优化策略】
     * - 分支预测友好：最频繁路径分支数最少
     * - 早退机制：避免不必要的后续计算
     * - 内联优化：用三元表达式替代函数调用（AS2环境友好）
     * - 零无效计算：每个分支只执行必要的操作
     * - 变量预取：减少点链操作和重复对象属性访问
     * 
     * 【伤害类型处理详解】
     * 物理伤害：defense_ratio计算，不取整
     * 破击伤害：检查目标是否有匹配的魔法抗性
     *   - 有抗性：物理部分 + 魔法部分的混合伤害，显示属性标识
     *   - 无抗性：回退为纯物理伤害，不显示属性标识
     * 魔法伤害：按属性抗性 > 基础抗性 > 默认抗性的优先级计算
     * 真实伤害：无视所有抗性，直接使用破坏力数值
     * 
     * 【取整策略】
     * 所有伤害值计算结果均不在此处取整，统一交给后续工序处理，
     * 以保持数值精度和计算的一致性。
     * 
     * @param bullet  子弹对象，包含伤害类型、破坏力、魔法伤害属性等
     * @param shooter 射击者对象
     * @param target  目标对象，包含防御力、等级、魔法抗性等
     * @param manager 管理器对象
     * @param result  伤害结果对象，用于设置颜色和特效
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // ========== 第一阶段：变量预取与初始化 ==========
        // 预取本地变量，避免重复的对象属性访问，在AS2解释执行环境中性能提升明显
        var t:String = bullet.伤害类型;
        var enemy:Boolean = bullet.是否为敌人;
        var power:Number = bullet.破坏力;
        var def:Number = target.防御力;
        var lvl:Number = target.等级;
        var resistTbl:Object = target.魔法抗性;
        
        // 先设定默认物理伤害颜色，避免在分支中重复设置
        var defaultDamageColor:String = enemy ? "#FF0000" : "#FFCC00";
        result.setDamageColor(defaultDamageColor);
        
        // ========== 第二阶段：物理伤害快速路径（最高频） ==========
        // 【关键优化】物理伤害是游戏中最常见的伤害类型，放在第一个分支
        // 仅需1次复合条件判断即可确定，然后立即早退，实现O(1)复杂度
        if (t != "真伤" && t != "魔法" && t != "破击") {
            // 物理伤害计算：破坏力 × 防御比率，不取整交给后续工序
            target.损伤值 = power * DamageResistanceHandler.defenseDamageRatio(def);
            return; // 早退，避免后续所有计算
        }
        
        // ========== 第三阶段：非物理伤害二分路由 ==========
        // 剩余的三种伤害类型按频率分为两组：破击 vs (魔法+真伤)
        if (t == "破击") {
            // ---------- 破击伤害：混合物理+魔法机制 ----------
            // 破击伤害的核心逻辑：检查目标是否具有与子弹魔法属性匹配的抗性
            var magicAttr:String = bullet.魔法伤害属性 ? bullet.魔法伤害属性 : "能";
            var rValRaw:Number = resistTbl[magicAttr];
            
            // 【业务逻辑关键】根据抗性存在性和属性类型确定混合比率
            // 魔法类属性：0.1倍率，非魔法标签：0.5倍率，无抗性：0倍率（回退纯物理）
            var isMagicTag:Boolean = MagicDamageTypes.isMagicDamageType(magicAttr);
            var rate:Number = (rValRaw != undefined) ? (isMagicTag ? 0.1 : 0.5) : 0;
            
            // 计算物理伤害部分（始终存在）
            var physPart:Number = power * DamageResistanceHandler.defenseDamageRatio(def);
            
            // 【性能优化】只在需要混合伤害时才计算抗性值和魔法部分
            if (rate > 0) {
                // 抗性值处理：用嵌套三元表达式替代Math.min/max函数调用
                var rVal:Number = Number(rValRaw);
                rVal = isNaN(rVal) ? 20 : (rVal < -1000 ? -1000 : (rVal > 100 ? 100 : rVal));
                
                // 计算魔法伤害部分并合成最终伤害
                var magicPart:Number = (power * rate) * (100 - rVal) / 100;
                target.损伤值 = physPart + magicPart;
                
                // UI效果：只有发生混合伤害时才显示属性标识
                var emoji:String = isMagicTag ? "✨" : "☠";
                result.addDamageEffect('<font color="#66bcf5" size="20"> ' + emoji + magicAttr + '</font>');
            } else {
                // 无匹配抗性，使用纯物理伤害
                target.损伤值 = physPart;
            }
            return; // 早退，避免后续计算
        }
        
        // ========== 第四阶段：魔法与真伤合并处理 ==========
        // 【设计决策】魔法伤害和真伤在UI表现上不同，但计算流程相似
        // 通过三元表达式合并处理，避免额外的if分支，保持代码紧凑
        var isTrue:Boolean = (t == "真伤");
        
        // 根据伤害类型和敌友关系设置颜色
        var color:String = isTrue ? (enemy ? "#660033" : "#4A0099")    // 真伤：深紫色系
                                : (enemy ? "#AC99FF" : "#0099FF");     // 魔法：蓝色系
        result.setDamageColor(color);
        
        // 设置伤害类型标识的UI效果
        var magicAttr2:String = bullet.魔法伤害属性 ? bullet.魔法伤害属性 : "能";
        var effectHTML:String = isTrue
            ? ('<font color="' + color + '" size="20"> 真</font>')      // 真伤显示"真"字
            : ('<font color="' + color + '" size="20"> ' + magicAttr2 + '</font>');  // 魔法显示属性
        result.addDamageEffect(effectHTML);
        
        // 【关键优化】真伤早退：真伤无需计算抗性，直接使用破坏力
        if (isTrue) {
            target.损伤值 = power;
            return;
        }
        
        // ---------- 魔法伤害抗性计算（只有魔法伤害执行到这里） ----------
        // 【抗性优先级】专属属性抗性 > 基础抗性 > 默认抗性(10+等级/2)
        var magicAttr3:String = bullet.魔法伤害属性;
        var rv:Number;
        
        // 优先查找专属属性抗性
        if (magicAttr3 && resistTbl && (resistTbl[magicAttr3] || resistTbl[magicAttr3] == 0)) {
            rv = resistTbl[magicAttr3];
        } else {
            // 回退到基础抗性或默认值
            rv = (resistTbl && (resistTbl["基础"] || resistTbl["基础"] == 0)) 
                ? resistTbl["基础"] 
                : (10 + lvl / 2);
        }
        
        // 【数值校验】使用三元表达式实现范围夹取，避免函数调用开销
        rv = isNaN(rv) ? 20 : (rv < -1000 ? -1000 : (rv > 100 ? 100 : rv));
        
        // 魔法伤害最终计算：破坏力 × (100 - 抗性值) / 100
        // 不取整，交给后续工序统一处理
        target.损伤值 = power * (100 - rv) / 100;
    }

    public function toString():String {
        return "UniversalDamageHandle";
    }
}
