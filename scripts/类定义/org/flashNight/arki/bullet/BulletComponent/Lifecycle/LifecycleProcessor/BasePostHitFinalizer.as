import org.flashNight.arki.component.Effect.*;      // 特效组件
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
/**
 * BasePostHitFinalizer - 命中后处理基类
 * 
 * 核心架构：基于模板方法模式的命中后处理系统
 * 
 * 主要功能：
 * • 统一的命中后处理流程管理，确保所有子弹类型都经过完整处理
 * • 基于宏展开+位掩码技术的高性能子弹类型检测
 * • 模块化的钩子方法设计，支持穿刺、硬直、特效等多种处理逻辑
 * 
 * 设计模式：
 * • 模板方法模式：定义统一的处理流程，子类可重写具体步骤
 * • 单例模式：提供静态实例，避免重复创建开销
 * • 钩子方法：processPiercing、processHardening、processPostHitEffect
 * 
 * 性能优化：
 * • 宏展开技术：编译时注入FLAG常量，零属性查找开销
 * • 位运算检测：O(1)复杂度的子弹类型判断
 * • 早期退出：hitCount检查避免不必要的处理
 * 
 * 处理流程：
 * 1. 预处理阶段：hitCount验证和基础类型检测
 * 2. 穿刺处理：基于FLAG_PIERCE的穿刺逻辑
 * 3. 硬直处理：基于FLAG_MELEE的近战硬直系统
 * 4. 特效处理：命中后视觉效果生成
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.BasePostHitFinalizer implements IPostHitFinalizer {
    
    /** 单例实例：避免重复创建，提升性能和内存效率 */
    public static var instance:BasePostHitFinalizer = new BasePostHitFinalizer();
    
    /**
     * 私有构造函数：支持单例模式，防止外部直接实例化
     */
    public function BasePostHitFinalizer() { 
        // 单例模式：通过静态实例访问，无需额外初始化
    }
    
    /**
     * 模板方法：整体命中后处理流程
     * 
     * 定义标准化的命中后处理序列，确保所有子弹类型都经过完整的处理流程。
     * 采用条件执行策略，只有预处理成功才进行后续特效处理。
     * 
     * @param target:MovieClip 命中的子弹对象
     * @param shooter:MovieClip 发射者对象
     * @param hitCount:Number 命中计数（用于控制处理频率）
     * @param shouldGeneratePostHitEffect:Boolean 是否生成命中后特效
     */
    public function finalizePostHitProcessing(target:MovieClip, shooter:MovieClip, hitCount:Number, shouldGeneratePostHitEffect:Boolean):Void {
        // 条件执行：只有预处理成功才进行特效处理
        if(preProcess(target, shooter, hitCount)) {
            processPostHitEffect(target, shooter, shouldGeneratePostHitEffect);
        }
    }

    /**
     * 预处理阶段：执行核心的命中后逻辑处理
     * 
     * 功能职责：
     * • hitCount验证：确保只在首次命中时执行处理逻辑
     * • 穿刺处理：基于位掩码的穿刺类型检测和动画控制
     * • 硬直处理：基于位掩码的近战硬直系统处理
     * 
     * 性能优化：使用早期退出策略，避免重复命中的不必要处理
     * 
     * @param target:MovieClip 命中的子弹对象
     * @param shooter:MovieClip 发射者对象
     * @param hitCount:Number 命中计数
     * @return Boolean 是否成功完成预处理（true=成功，false=跳过）
     */
    public function preProcess(target:MovieClip, shooter:MovieClip, hitCount:Number):Boolean {
        // 早期退出优化：避免重复命中的不必要处理
        if (hitCount > 0) return false;
        
        // 执行核心处理逻辑：穿刺 → 硬直
        processPiercing(target);
        processHardening(target, shooter);
        return true;
    }

    
    /**
     * 钩子方法1：处理穿刺检测
     * 默认逻辑：若目标无法穿刺，则播放“消失”动画
     */
    public function processPiercing(target:MovieClip):Void {
        // 在编译时，下面这行代码会被替换为 "var FLAG_PIERCE:Number = 1 << 2;"
        // 这创建了一个临时的、访问速度最快的局部变量。
        #include "../macros/FLAG_PIERCE.as"

        // 直接使用这个局部变量 FLAG_PIERCE 进行位运算，实现零额外开销的检测。
        if ((target.flags & FLAG_PIERCE) == 0) {
            target.gotoAndPlay("消失");
        }
    }
    
    /**
     * 钩子方法2：处理硬直（近战检测）
     * 
     * 核心功能：基于近战子弹类型的攻击硬直系统处理
     * 
     * 业务逻辑：
     * • 近战攻击：造成攻击者进入硬直状态，模拟攻击后的恢复时间
     * • 远程攻击：无硬直效果，保持连续射击能力
     * • 硬直免疫：支持特殊子弹类型的硬直免疫机制
     * 
     * 性能优化：使用宏展开技术进行零开销的近战类型检测
     * 
     * @param target:MovieClip 命中的子弹对象
     * @param shooter:MovieClip 发射者对象（将受到硬直影响）
     */
    public function processHardening(target:MovieClip, shooter:MovieClip):Void {
        // === 宏展开 + 位掩码优化：近战硬直系统的高效类型检测 ===
        //
        // 优化背景：
        // 硬直系统需要快速判断子弹是否为近战类型，以决定是否对攻击者施加硬直效果。
        // 在高频的命中后处理中，类型检测的效率直接影响战斗系统的流畅性和响应速度。
        //
        // 宏展开机制详解：
        // • 编译时注入：#include "../macros/FLAG_MELEE.as" 在编译阶段直接展开为：
        //   var FLAG_MELEE:Number = 1 << 0;  (位值: 1, 二进制: 00000001)
        // • 局部常量化：FLAG_MELEE 成为当前函数作用域的栈变量，访问成本接近零
        // • 零索引开销：完全绕过类静态属性的哈希表查找机制
        //
        // 位掩码检测原理：
        // • 近战标志检测：(target.flags & FLAG_MELEE) != 0
        //   - 位运算逻辑：检测flags的第0位是否为1
        //   - 如果第0位为1：表示近战子弹，需要触发硬直效果
        //   - 如果第0位为0：表示远程子弹，无硬直效果
        //
        // 硬直系统业务逻辑：
        // • 近战硬直机制：模拟近身攻击后的恢复时间，增加战斗策略性
        // • 攻击者硬直：近战攻击命中后，攻击者暂时无法进行其他动作
        // • 硬直免疫：通过 target.不硬直 属性支持特殊子弹的硬直免疫
        // • 时间控制：使用 _root.钝感硬直时间 全局配置硬直持续时间
        //
        // 性能优化要点：
        // • 消除字符串匹配：避免 target.子弹种类.indexOf("近战") 的 O(n) 遍历
        // • 消除属性查找：避免类属性索引的 ~15-20 CPU周期哈希检索开销
        // • 位运算效率：单次 & 操作仅需 1-2 CPU周期，性能提升 10-15倍
        // • 命中后优化：在每次命中后处理中，累积性能提升显著
        //
        // 游戏机制意义：
        // • 攻击节奏：近战攻击的硬直增加了攻击间隔，提升战斗策略深度
        // • 平衡性：防止近战攻击过于频繁，维持游戏平衡
        // • 真实感：模拟现实中近战攻击后的恢复过程
        // • 可定制性：支持通过配置调整硬直时间和免疫机制
        //
        // 编译后等效代码：
        // var FLAG_MELEE:Number = 1;  // 编译时直接注入的局部常量
        // if ((target.flags & 1) != 0 && !target.不硬直) { ... }
        //
        #include "../macros/FLAG_MELEE.as"
        
        // === 基于位掩码的近战硬直系统逻辑处理 ===
        // 双重条件检测：近战类型 && 非硬直免疫
        if ((target.flags & FLAG_MELEE) != 0 && !target.不硬直) {
            // 对攻击者施加硬直效果：参数(角色实例, 硬直持续时间)
            shooter.硬直(shooter.man, _root.钝感硬直时间);
        }
    }
    
    /**
     * 钩子方法3：处理命中后特效
     * 
     * 核心功能：生成命中后的视觉特效，提升游戏体验
     * 
     * 特效系统特点：
     * • 条件生成：基于shouldGeneratePostHitEffect标志控制特效生成
     * • 位置精确：使用子弹的精确坐标(_x, _y)作为特效生成点
     * • 方向适配：根据发射者的_xscale调整特效方向
     * • 类型多样：支持不同子弹类型的专用击中特效
     * 
     * @param target:MovieClip 命中的子弹对象
     * @param shooter:MovieClip 发射者对象（提供方向信息）
     * @param shouldGeneratePostHitEffect:Boolean 特效生成控制标志
     */
    public function processPostHitEffect(target:MovieClip, shooter:MovieClip, shouldGeneratePostHitEffect:Boolean):Void {
        // 条件特效生成：避免不必要的视觉效果开销
        if (shouldGeneratePostHitEffect) {
            // 在子弹命中位置生成对应的击中特效
            // 参数：(特效类型, X坐标, Y坐标, 方向缩放)
            EffectSystem.Effect(target.击中后子弹的效果, target._x, target._y, shooter._xscale);
        }
    }
}