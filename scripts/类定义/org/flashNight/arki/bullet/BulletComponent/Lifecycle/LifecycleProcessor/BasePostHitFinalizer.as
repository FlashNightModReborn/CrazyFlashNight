import org.flashNight.arki.component.Effect.*;      // 特效组件
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
/**
 * 基类：统一命中后处理逻辑，使用模板方法模式
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.BasePostHitFinalizer implements IPostHitFinalizer {
    
    public static var instance:BasePostHitFinalizer = new BasePostHitFinalizer();
    public function BasePostHitFinalizer() { }
    
    /**
     * 模板方法：整体命中后处理流程
     */
    public function finalizePostHitProcessing(target:MovieClip, shooter:MovieClip, hitCount:Number, shouldGeneratePostHitEffect:Boolean):Void {
        if(preProcess(target, shooter, hitCount)) {
            processPostHitEffect(target, shooter, shouldGeneratePostHitEffect);
        }
    }

    /**
     * 执行集合
     * 默认逻辑：如果可执行前置，则执行；否则返回 false
     */
    public function preProcess(target:MovieClip, shooter:MovieClip, hitCount:Number):Boolean {
        if (hitCount > 0) return false;
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
     * 默认逻辑：若目标支持近战检测且不免硬直，则使射手进入硬直状态
     */
    public function processHardening(target:MovieClip, shooter:MovieClip):Void {
        #include "../macros/FLAG_MELEE.as"
        if ((target.flags & FLAG_MELEE) != 0 && !target.不硬直) {
            shooter.硬直(shooter.man, _root.钝感硬直时间);
        }
    }
    
    /**
     * 钩子方法3：处理命中后特效
     * 默认逻辑：若标识为真，则生成特效
     */
    public function processPostHitEffect(target:MovieClip, shooter:MovieClip, shouldGeneratePostHitEffect:Boolean):Void {
        if (shouldGeneratePostHitEffect) {
            EffectSystem.Effect(target.击中后子弹的效果, target._x, target._y, shooter._xscale);
        }
    }
}