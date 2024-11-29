class org.flashNight.arki.bullet.BulletComponent.Collider.CollisionResult {
    public var isColliding:Boolean;       // 碰撞是否发生（必要字段）
    public var additionalInfo:Object;    // 额外碰撞信息（可选字段）

    // 构造函数
    public function CollisionResult(isColliding:Boolean, additionalInfo:Object) {
        this.isColliding = isColliding;
        this.additionalInfo = additionalInfo || {}; // 如果未提供额外信息，默认为空对象
    }

    // 添加额外信息的快捷方法
    public function addInfo(key:String, value):Void {
        this.additionalInfo[key] = value;
    }
}
