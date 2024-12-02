interface org.flashNight.arki.bullet.BulletComponent.Movement.IMovement {
    /**
     * 更新运动逻辑。
     * @param target:MovieClip 要移动的目标对象。
     * @param deltaTime:Number 时间增量，用于实现时间步进。
     */
    function updateMovement(target:MovieClip):Void;
    
    /**
     * 检查对象是否需要被销毁或移除。
     * @param target:MovieClip 要检查的目标对象。
     * @return Boolean 是否需要销毁。
     */
    function shouldDestroy(target:MovieClip):Boolean;
}
