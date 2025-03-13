interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.IDestructionFinalizer {
    /**
     * 执行销毁前的检查与后续处理
     */
    function finalizeDestruction(target:MovieClip, isPointSet:Boolean):Void;
    /**
     * 执行销毁前的检查与后续处理，不检查pointset
     */
    function finalizeDestructionWithoutPointCheck(target:MovieClip):Void;
}