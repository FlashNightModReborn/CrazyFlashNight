interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.ITargetRetriever {
    /**
     * 根据发射者及伤害类型获取潜在目标
     */
    function getPotentialTargets(target:MovieClip):Array;
}