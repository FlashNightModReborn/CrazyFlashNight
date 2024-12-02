// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.ILifecycle.as

interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.ILifecycle {
    /**
     * 检查对象是否需要被销毁或移除。
     * @param target:MovieClip 要检查的目标对象。
     * @return Boolean 是否需要销毁。
     */
    function shouldDestroy(target:MovieClip):Boolean;
}
