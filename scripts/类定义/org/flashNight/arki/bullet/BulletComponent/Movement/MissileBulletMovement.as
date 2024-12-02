// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.MissileBulletMovement.as

import org.flashNight.neur.StateMachine.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;
import mx.utils.Delegate;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileBulletMovement implements IMovement {
    // 与对象属性无关的参数（英文命名）
    private var baseSpeed:Number = 20;                // 基准速度
    private var acceleration:Number = 0.25;          // 加速度
    private var rotationSpeed:Number = 36;           // 转向速度
    private var flightResistance:Number = 0.02;      // 飞行阻力
    private var turnResistance:Number = 0.05;        // 转向阻力
    private var speedLimit:Number = 5;               // 速度上限
    private var turnPower:Number = 18;               // 转向动力
    private var turnSpeedLowerLimit:Number = 5;      // 转向速度下限
    private var lockDelayInitial:Number = -4;        // 锁定延迟初始值
    private var lockRange:Number = 2000;             // 锁定范围
    private var upwardResistance:Number = 0.4;       // 上抛阻力
    private var launchSpeed:Number = 1;              // 发射速度（默认值，实际应在初始化时设置）

    // 与对象属性相关的参数（谨慎处理）
    private var bulletName:String;                   // 子弹名
    private var rotationAngle:Number;                // 旋转角度
    private var upwardSpeed:Number;                  // 上抛速度
    private var correctionAngle:Number = 0;          // 修正角度
    private var speed:Number = 0;                     // 当前速度
    private var isEnemy:Boolean;                     // 是否为敌人
    private var attackTarget:String = "none";        // 攻击目标
    private var aimPermission:Boolean = false;       // 瞄准许可
    private var initialX:Number = 0;                  // 初始 X 位置
    private var initialY:Number = 0;                  // 初始 Y 位置
    private var missilePosition:Object = {x:0, y:0};  // 导弹当前坐标
    private var lockPosition:Object = {x:0, y:0};     // 锁定坐标
    private var enemyName:String = "none";            // 敌人名称
    private var minDistance:Number = lockRange;        // 最小距离
    private var distance:Number = Number.MAX_VALUE;    // 当前距离
    private var lockDelay:Number = lockDelayInitial;   // 锁定延迟计数

    // 引用子弹影片剪辑
    private var targetBullet:MovieClip;

    // 状态机实例
    private var stateMachine:FSM_StateMachine;

    /**
     * 构造函数
     * @param params:Object 配置参数，可选
     */
    public function MissileBulletMovement(params:Object) {
        // 覆盖默认参数
        if (params != undefined) {
            this.baseSpeed = params.baseSpeed != undefined ? params.baseSpeed : this.baseSpeed;
            this.acceleration = params.acceleration != undefined ? params.acceleration : this.acceleration;
            this.rotationSpeed = params.rotationSpeed != undefined ? params.rotationSpeed : this.rotationSpeed;
            this.flightResistance = params.flightResistance != undefined ? params.flightResistance : this.flightResistance;
            this.turnResistance = params.turnResistance != undefined ? params.turnResistance : this.turnResistance;
            this.speedLimit = params.speedLimit != undefined ? params.speedLimit : this.speedLimit;
            this.turnPower = params.turnPower != undefined ? params.turnPower : this.turnPower;
            this.turnSpeedLowerLimit = params.turnSpeedLowerLimit != undefined ? params.turnSpeedLowerLimit : this.turnSpeedLowerLimit;
            this.lockDelayInitial = params.lockDelayInitial != undefined ? params.lockDelayInitial : this.lockDelayInitial;
            this.lockRange = params.lockRange != undefined ? params.lockRange : this.lockRange;
            this.upwardResistance = params.upwardResistance != undefined ? params.upwardResistance : this.upwardResistance;
            this.launchSpeed = params.launchSpeed != undefined ? params.launchSpeed : this.launchSpeed;
        }

        // 初始化状态机
        this.stateMachine = new FSM_StateMachine(null, null, null);
        this.stateMachine.data = {}; // 数据黑板

        // 创建并添加状态
        var initializeState:InitializeState = new InitializeState(this);
        var searchTargetState:SearchTargetState = new SearchTargetState(this);
        var trackTargetState:TrackTargetState = new TrackTargetState(this);
        var explodeState:ExplodeState = new ExplodeState(this);
        var destroyState:DestroyState = new DestroyState(this);

        this.stateMachine.AddStatus("Initialize", initializeState);
        this.stateMachine.AddStatus("SearchTarget", searchTargetState);
        this.stateMachine.AddStatus("TrackTarget", trackTargetState);
        this.stateMachine.AddStatus("Explode", explodeState);
        this.stateMachine.AddStatus("Destroy", destroyState);

        // 设置初始状态为 Initialize
        this.stateMachine.ChangeState("Initialize");
    }

    /**
     * 更新运动逻辑
     * @param target:MovieClip 要移动的目标对象
     */
    public function updateMovement(target:MovieClip):Void {
        this.targetBullet = target;
        this.stateMachine.onAction();
    }

    /**
     * 初始化子弹运动
     */
    public function initializeMissile():Void {
        this.bulletName = this.targetBullet._name;

        // 随机初始化速度和角度
        this.speed = Math.random() * 3;
        this.rotationAngle = this.targetBullet._rotation + 15 - Math.random() * 30;

        // 随机调整子弹初始位置
        this.targetBullet._x += 30 - Math.random() * 60; // -30 到 +30
        this.targetBullet._y += -Math.random() * 30;      // -30 到 0

        // 初始化上抛速度
        this.upwardSpeed = Math.random() * -5 - 5;

        // 获取发射者信息
        var gameworld = _root.gameworld;
        var bulletObject = gameworld[this.bulletName];
        this.launchSpeed = Math.sqrt(Math.pow(bulletObject.xmov, 2) + Math.pow(bulletObject.ymov, 2));
        bulletObject.xmov = 0;
        bulletObject.ymov = 0;
        this.isEnemy = !bulletObject.子弹敌我属性值;

        // 初始化位置
        this.initialX = this.targetBullet._x + this.targetBullet._parent._x;
        this.initialY = this.targetBullet._y + this.targetBullet._parent._y;
        this.missilePosition.x = this.initialX;
        this.missilePosition.y = this.initialY;
        this.lockPosition.x = this.initialX;
        this.lockPosition.y = this.initialY;
    }

    /**
     * 寻找攻击目标
     * @return Boolean 是否找到目标
     */
    public function findAttackTarget():Boolean {
        var gameworld = _root.gameworld;
        this.minDistance = this.lockRange;
        var found:Boolean = false;

        for (var each in gameworld) {
            var obj = gameworld[each];
            if (typeof obj == "movieclip" && obj != undefined && obj._name != this.bulletName) {
                var enemyAttribute:Boolean = obj.是否为敌人;
                if (this.isEnemy != enemyAttribute && obj.hp > 0) {
                    var enemyX:Number = obj._x;
                    var enemyY:Number = obj._y;
                    var distance:Number = Math.abs(enemyX - this.missilePosition.x) + 5 * Math.abs(enemyY - this.initialY);
                    if (this.minDistance > distance) {
                        this.minDistance = distance;
                        this.attackTarget = obj._name;
                        this.lockPosition.x = enemyX;
                        this.lockPosition.y = enemyY - 30;
                        found = true;
                    }
                }
            }
        }

        if (found) {
            this.aimPermission = true;
            this.acceleration += 1.25;
            this.speedLimit = 80;
            this.upwardSpeed = Math.random() * -5 - 5;
        }

        return found;
    }

    /**
     * 在没有目标时更新导弹位置
     */
    public function updateMovementWithoutTarget():Void {
        // 更新上抛速度
        if (this.upwardSpeed < 0) {
            this.upwardSpeed += this.upwardResistance;
        } else if (this.upwardSpeed > 0) {
            this.upwardSpeed = 0;
        }

        // 更新速度
        if (this.speed < this.speedLimit) {
            this.speed += this.acceleration - this.speed * this.flightResistance;
        }

        // 更新旋转角度
        this.rotationAngle = this.targetBullet._rotation;

        // 计算位移
        var radianAngle:Number = this.rotationAngle * (Math.PI / 180);
        var dx:Number = Math.cos(radianAngle) * this.speed * this.launchSpeed / this.baseSpeed;
        var dy:Number = Math.sin(radianAngle) * this.speed * this.launchSpeed / this.baseSpeed;

        // 更新位置
        this.targetBullet._x += dx;
        this.targetBullet._y += dy + this.upwardSpeed;
    }

    /**
     * 追踪目标的逻辑
     */
    public function trackTarget():Void {
        // 更新上抛速度
        if (this.upwardSpeed < 0) {
            this.upwardSpeed += this.upwardResistance;
        } else if (this.upwardSpeed > 0) {
            this.upwardSpeed = 0;
        }

        // 更新速度
        if (this.speed < this.speedLimit) {
            this.speed += this.acceleration - this.speed * this.flightResistance;
        }

        // 获取锁定目标的位置
        var targetObj = _root.gameworld[this.attackTarget];
        if (targetObj != undefined) {
            this.lockPosition.x = targetObj._x;
            this.lockPosition.y = targetObj._y - 30;
        }

        // 计算角度修正
        var angleToTarget:Number = (Math.atan2(this.lockPosition.y - this.missilePosition.y, this.lockPosition.x - this.missilePosition.x) * (180 / Math.PI) + 360) % 360;
        this.correctionAngle = angleToTarget - this.rotationAngle;

        // 调整修正角度到范围内
        if (this.correctionAngle > this.rotationSpeed) {
            this.correctionAngle = this.rotationSpeed;
        } else if (this.correctionAngle < -this.rotationSpeed) {
            this.correctionAngle = -this.rotationSpeed;
        } else if (!(this.correctionAngle <= this.rotationSpeed && this.correctionAngle >= -this.rotationSpeed)) {
            this.correctionAngle = 0;
        }

        // 调整速度
        if (this.speed > this.turnSpeedLowerLimit) {
            this.speed -= Math.abs(this.correctionAngle * this.turnResistance);
        }

        // 应用修正角度
        this.rotationAngle += this.correctionAngle;
        this.targetBullet._rotation = this.rotationAngle;

        // 计算位移
        var radianAngle:Number = this.rotationAngle * (Math.PI / 180);
        var dx:Number = Math.cos(radianAngle) * this.speed * this.launchSpeed / this.baseSpeed;
        var dy:Number = Math.sin(radianAngle) * this.speed * this.launchSpeed / this.baseSpeed;

        // 更新位置
        this.targetBullet._x += dx;
        this.targetBullet._y += dy + this.upwardSpeed;
    }

    /**
     * 判断是否达到目标
     * @return Boolean 是否达到目标
     */
    public function hasReachedTarget():Boolean {
        var targetObj = _root.gameworld[this.attackTarget];
        if (targetObj != undefined) {
            var distance:Number = Math.sqrt(Math.pow(targetObj._x - this.targetBullet._x, 2) + Math.pow(targetObj._y - this.targetBullet._y, 2));
            return distance < 10; // 设定一个阈值，例如10个单位
        }
        return false;
    }

    /**
     * 执行爆炸效果
     */
    public function explode():Void {
        // 执行爆炸效果，例如播放动画、造成伤害等
        // 示例：播放爆炸动画
        var explosion:MovieClip = this.targetBullet.attachMovie("ExplosionSymbol", "explosion" + _root.gameworld.子弹生成计数, this.targetBullet.getNextHighestDepth());
        explosion._x = 0;
        explosion._y = 0;
        explosion.gotoAndPlay("explode");

        // 可以在动画结束后销毁导弹
        explosion.onEnterFrame = Delegate.create(this, function() {
            if (explosion._currentframe >= explosion._totalframes) {
                explosion.removeMovieClip();
                this.destroy();
            }
        });
    }

    /**
     * 销毁导弹，移除影片剪辑
     */
    public function destroy():Void {
        this.targetBullet.removeMovieClip();
    }

    /**
     * 判断是否需要销毁
     * @return Boolean 是否需要销毁
     */
    public function shouldDestroy():Boolean {
        // 可以根据时间、速度、距离等条件判断是否需要销毁
        // 示例：超过一定速度上限或距离
        return this.speed > 100 || Math.abs(this.targetBullet._x) > 5000 || Math.abs(this.targetBullet._y) > 5000;
    }
}
