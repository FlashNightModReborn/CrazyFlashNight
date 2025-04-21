class org.flashNight.arki.bullet.BulletComponent.Movement.Util.DefaultMissileCallbacks
{
    private var shooter:MovieClip;
    /**
     * 返回一组在测试期可直接使用的回调。
     * @param shooter  MovieClip  发射者
     * @return Object{ onInitializeMissile, onSearchForTarget, onTrackTarget, onPreLaunchMove }
     */
    public static function build(shooter:MovieClip,
                                 velocity:Number,
                                 angleRadians:Number):Object
    {
        // 1) 初始化：给一点初速度、角度指向 shooter 面朝方向
        function _init():Void
        {
            _root.服务器.发布服务器消息("_init");
            
            this.speed         = velocity;
            this.shooter       = shooter._name;
            this.rotationAngle = angleRadians;
        }

        // 2) 寻敌：用项目已有的“寻找攻击目标基础函数”
        function _search():Boolean
        {
            _root.服务器.发布服务器消息("_search");

            var gw:MovieClip = _root.gameworld;
            var shooter:MovieClip = gw[this.shooter];
            var attackTargetName:String = shooter.攻击目标;
            var attackTarget:MovieClip = gw[attackTargetName];

            _root.服务器.发布服务器消息("start_search " + shooter);

            if(attackTarget == "无" || gw[attackTarget].hp <= 0) {
                var distance:Number = Infinity;
                var name:String = undefined;

                var map:Array = _root.帧计时器.获取敌人缓存(shooter, 30); 

                for (var i = 0; i < map.length; i++) 
                {
                    var target:MovieClip = map[i];
                    var d:Number = Math.abs(target._x - this.targetObject._x);
                    if (d < distance) 
                    {
                        distance = d;
                        name = target._name;
                    }
                }

                this.target = gw[name];
            } else {
                this.target = attackTarget;
            }

            _root.服务器.发布服务器消息("target " + this.target);
            
            if (!this.target) return false;

            _root.服务器.发布服务器消息("lock " + this.target);

            this.hasTarget = (this.target != null);
            return this.hasTarget;
        }

        // 3) 追踪：简单朝向目标旋转并加速
        function _track():Void
        {
            if (!this.target) {
                this.changeState("SearchTarget");  // 如果没有目标，回到搜索状态
                return;
            }

            var targetObject = this.targetObject;
            var dx:Number = this.target._x - targetObject._x;
            var coefficient:Number = targetObject.身高 / 175;
            var yOffset:Number = targetObject.中心高度 ? targetObject.中心高度 * coefficient :
                                 targetObject.状态 == "倒地"? 35 : 75;
            var dy:Number = this.target._y - targetObject._y - yOffset;

            // 计算目标的角度
            var targetAngle:Number = Math.atan2(dy, dx) * 180 / Math.PI;

            // 计算当前角度与目标角度的差值
            var angleDifference:Number = targetAngle - this.rotationAngle;

            // 确保角度差值在 -180 到 180 范围内
            if (angleDifference > 180) {
                angleDifference -= 360;
            } else if (angleDifference < -180) {
                angleDifference += 360;
            }

            // 缓慢调整当前角度，加入旋转速度控制
            var rotationSpeed:Number = 10;  // 控制旋转的速度（可以调节）
            this.rotationAngle += Math.min(Math.max(angleDifference, -rotationSpeed), rotationSpeed);
            targetObject.yOffset = yOffset;
            // 更新速度
            if (this.speed < this.maxSpeed) {
                this.speed += this.acceleration;
            }

            //_root.服务器.发布服务器消息("dx: " + dx + "dy: " + dy + "targetAngle: " + targetAngle + "rotationAngle: " + this.rotationAngle);
        }


        // 4) 预发射：先垂直上升 60px
        function _preLaunch(flag:String):Boolean
        {
            _root.服务器.发布服务器消息("_preLaunch");
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
