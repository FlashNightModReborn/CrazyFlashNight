interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.ITargetFilter {
    /**
     * 根据 Z 轴距离与“防止无限飞”等条件判断是否跳过当前目标
     */
    function shouldSkipHitTarget(target:MovieClip, hitTarget:MovieClip, zOffset:Number):Boolean;
}
