interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.IColliderUpdater {
    /**
     * 更新子弹的碰撞器
     * @param target 当前子弹实例
     * @return 如果无需后续处理则返回 true，否则返回 false
     */
    function updateCollider(target:MovieClip):Boolean;
}