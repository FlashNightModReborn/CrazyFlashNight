class org.flashNight.arki.bullet.BulletComponent.Movement.Util.DefaultMissileCallbacks
{
    /**
     * 返回一组在测试期可直接使用的回调。
     * @param shooter  MovieClip  发射者
     * @return Object{ onInitializeMissile, onSearchForTarget, onTrackTarget, onPreLaunchMove }
     */
    public static function build(shooter:MovieClip):Object
    {
        // 1) 初始化：给一点初速度、角度指向 shooter 面朝方向
        function _init():Void
        {
            this.speed         = 4;
            this.rotationAngle = shooter._rotation;
        }

        // 2) 寻敌：用项目已有的“寻找攻击目标基础函数”
        function _search():Boolean
        {
            _root.寻找攻击目标基础函数(this);   // 复用你的全局函数
            if (this.攻击目标 == "无") return false;

            this.target    = _root.gameworld[this.攻击目标];
            this.hasTarget = (this.target != null);
            return this.hasTarget;
        }

        // 3) 追踪：简单朝向目标旋转并加速
        function _track():Void
        {
            if (!this.target) { this.changeState("SearchTarget"); return; }

            var dx:Number = this.target._x - this.targetObject._x;
            var dy:Number = this.target._y - this.targetObject._y;
            this.rotationAngle = Math.atan2(dy, dx) * 180/Math.PI;
            if (this.speed < this.maxSpeed) this.speed += this.acceleration;
        }

        // 4) 预发射：先垂直上升 60px
        function _preLaunch(flag:String):Boolean
        {
            if (flag == "isComplete") return (this.targetObject._y <= shooter._y - 60);
            this.targetObject._y -= 3;
            return false;
        }

        return {
            onInitializeMissile : _init,
            onSearchForTarget   : _search,
            onTrackTarget       : _track,
            onPreLaunchMove     : _preLaunch
        };
    }
}
