interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.IPostHitFinalizer {
    /**
     * 执行命中后整体处理
     */
    function finalizePostHitProcessing(target:MovieClip, shooter:MovieClip, hitCount:Number, shouldGeneratePostHitEffect:Boolean):Void;
}