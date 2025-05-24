// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.LinkedBulletLifecycle.as
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.ILifecycle;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.NormalBulletLifecycle;

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LinkedBulletLifecycle implements ILifecycle {
    private var normalLifecycle:NormalBulletLifecycle;

    /**
     * 构造函数
     * @param 射程阈值:Number 子弹的射程限制。
     */
    public function LinkedBulletLifecycle(射程阈值:Number) {
        normalLifecycle = new NormalBulletLifecycle(射程阈值);
    }

    /**
     * 检查对象是否需要被销毁或移除。
     * 采用组合方式委托给普通子弹生命周期，并可在此基础上添加额外逻辑。
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        // 如有需要，可以在这里加入联弹专属的判断逻辑
        return normalLifecycle.shouldDestroy(target);
    }

    /**
     * 为目标对象绑定生命周期逻辑。
     * 采用组合方式先绑定普通子弹逻辑，再附加联弹特有的逻辑。
     */
    public function bindLifecycle(target:MovieClip):Void {
        normalLifecycle.bindLifecycle(target);
        if(target.联弹检测) {
            bindLinkedBulletLogic(target);
        }
    }

    /**
     * 绑定联弹特有的逻辑。
     */
    private function bindLinkedBulletLogic(target:MovieClip):Void {
        // 例如：设置特定属性或调用联弹相关的全局逻辑
        target.linkedBulletEnabled = true;
        _root.联弹逻辑.call(target);
    }
}
