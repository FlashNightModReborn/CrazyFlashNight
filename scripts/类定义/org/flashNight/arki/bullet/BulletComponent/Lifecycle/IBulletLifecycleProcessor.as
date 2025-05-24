/**
 * 1) 子弹生命周期处理器接口
 *    提供核心方法：更新碰撞器 / 碰撞命中处理 / 销毁前处理
 */
interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.IBulletLifecycleProcessor {
    
    /**
     * 每帧调用的核心方法
     */
    function processFrame(target:MovieClip):Void;

    /**
     * 非联弹时使用
     */
    function processFrameWithoutPointCheck(target:MovieClip):Void
}
