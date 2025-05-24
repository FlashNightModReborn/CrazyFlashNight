// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement.as

import org.flashNight.arki.bullet.BulletComponent.Movement.FSMMovement;
import org.flashNight.neur.StateMachine.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.*;
import org.flashNight.neur.Event.Delegate;  // 引入委托类

/**
 * 基础导弹运动类
 * 该类继承自 FSMMovement，并实现了有限状态机（FSM）的功能，用于控制导弹的行为逻辑。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement extends FSMMovement {
    // 导弹参数
    public var speed:Number = 0; // 当前速度
    public var acceleration:Number = 0.5; // 加速度
    public var maxSpeed:Number = 10; // 最大速度
    public var rotationAngle:Number = 0; // 当前旋转角度（以度为单位）
    public var target:Object = null; // 目标引用
    public var hasTarget:Boolean = false; // 是否已经锁定目标
    public var usePreLaunch:Boolean = false; // 是否启用“预发射（PreLaunch）”状态

    // 外部提供的回调方法
    public var onInitializeMissile:Function; // 导弹初始化的回调方法
    public var onSearchForTarget:Function; // 搜索目标的回调方法
    public var onTrackTarget:Function; // 追踪目标的回调方法
    public var onPreLaunchMove:Function; // 发射前的运动逻辑回调方法

    // 使用委托优化后的方法引用
    private var onInitializeMissileDelegate:Function; // 导弹初始化的委托方法
    private var onSearchForTargetDelegate:Function; // 搜索目标的委托方法
    private var onTrackTargetDelegate:Function; // 追踪目标的委托方法
    private var onPreLaunchMoveDelegate:Function; // 发射前运动逻辑的委托方法
    private var isPreLaunchCompleteDelegate:Function; // 判断预发射是否完成的委托方法

    /**
     * 构造函数
     * @param params:Object 包含以下配置参数：
     *  - usePreLaunch:Boolean 是否启用“预发射”状态
     *  - onInitializeMissile:Function 外部提供的初始化方法
     *  - onSearchForTarget:Function 外部提供的搜索目标方法
     *  - onTrackTarget:Function 外部提供的追踪目标方法
     *  - onPreLaunchMove:Function 外部提供的发射前运动方法
     */
    public function BaseMissileMovement(params:Object) {
        super();
        this.usePreLaunch = params.usePreLaunch != undefined ? params.usePreLaunch : false;
        this.onInitializeMissile = params.onInitializeMissile;
        this.onSearchForTarget = params.onSearchForTarget;
        this.onTrackTarget = params.onTrackTarget;
        this.onPreLaunchMove = params.onPreLaunchMove;
        
        // 初始化委托方法
        this.initDelegates();
        
        // 初始化状态
        this.initializeStates();
    }

    /**
     * 初始化委托方法
     * 利用 Delegate 类对外部方法进行绑定，以提高执行效率。
     */
    private function initDelegates():Void {
        // 确保 Delegate 缓存已初始化
        Delegate.init();
        
        // 为每个外部回调方法创建委托
        if (this.onInitializeMissile != null) {
            this.onInitializeMissileDelegate = Delegate.create(this, this.onInitializeMissile);
        }
        if (this.onSearchForTarget != null) {
            this.onSearchForTargetDelegate = Delegate.create(this, this.onSearchForTarget);
        }
        if (this.onTrackTarget != null) {
            this.onTrackTargetDelegate = Delegate.create(this, this.onTrackTarget);
        }
        if (this.onPreLaunchMove != null) {
            this.onPreLaunchMoveDelegate = Delegate.create(this, this.onPreLaunchMove);
            // 为“是否完成”参数创建专用委托
            this.isPreLaunchCompleteDelegate = Delegate.createWithParams(this, this.onPreLaunchMove, ["isComplete"]);
        }
    }

    /**
     * 初始化状态
     * 为有限状态机添加所需的状态，并根据是否启用预发射状态设置初始状态。
     */
    public function initializeStates():Void {
        // 创建状态实例
        var initializeState:InitializeState = new InitializeState(this);
        var searchTargetState:SearchTargetState = new SearchTargetState(this);
        var trackTargetState:TrackTargetState = new TrackTargetState(this);
        var freeFlyState:FreeFlyState = new FreeFlyState(this);

        // 添加状态到状态机
        this.addState("Initialize", initializeState);
        this.addState("SearchTarget", searchTargetState);
        this.addState("TrackTarget", trackTargetState);
        this.addState("FreeFly", freeFlyState);

        // 根据配置决定是否添加预发射状态
        if (this.usePreLaunch) {
            var preLaunchState:PreLaunchState = new PreLaunchState(this);
            this.addState("PreLaunch", preLaunchState);
            // 设置初始状态为“预发射”
            this.changeState("PreLaunch");
        } else {
            // 设置初始状态为“初始化”
            this.changeState("Initialize");
        }
    }

    // 以下方法供状态调用

    /**
     * 初始化导弹参数
     * 调用外部提供的初始化方法。
     */
    public function initializeMissile():Void {
        if (this.onInitializeMissileDelegate != null) {
            this.onInitializeMissileDelegate(); // 无参数
        }
    }

    /**
     * 寻找目标
     * 调用外部提供的搜索目标方法。
     * @return Boolean 是否找到目标
     */
    public function searchForTarget():Boolean {
        if (this.onSearchForTargetDelegate != null) {
            return this.onSearchForTargetDelegate(); // 无参数
        }
        return false;
    }

    /**
     * 追踪目标
     * 调用外部提供的追踪目标方法。
     */
    public function trackTarget():Void {
        if (this.onTrackTargetDelegate != null) {
            this.onTrackTargetDelegate(); // 无参数
        }
    }

    /**
     * 发射前运动逻辑（可选）
     * 调用外部提供的发射前运动方法。
     */
    public function preLaunchMove():Void {
        if (this.onPreLaunchMoveDelegate != null) {
            this.onPreLaunchMoveDelegate(); // 无参数
        }
    }

    /**
     * 判断是否结束 PreLaunch 状态
     * 调用外部提供的逻辑，判断发射前运动是否完成。
     * @return Boolean 是否完成
     */
    public function isPreLaunchComplete():Boolean {
        if (this.isPreLaunchCompleteDelegate != null) {
            return this.isPreLaunchCompleteDelegate(); // 传递预定义参数“isComplete”
        }
        return false;
    }

    /**
     * 自由飞行逻辑
     * 实现导弹的自由飞行逻辑，包括速度更新和位置更新。
     */
    public function freeFly():Void {
        // 输出自由飞行逻辑的执行信息
        trace("执行自由飞行逻辑");

        // 更新速度
        if (this.speed < this.maxSpeed) {
            this.speed += this.acceleration;
        }

        // 更新导弹位置
        var radianAngle:Number = this.rotationAngle * (Math.PI / 180); // 角度转换为弧度
        var vx:Number = Math.cos(radianAngle) * this.speed; // X 轴速度分量
        var vy:Number = Math.sin(radianAngle) * this.speed; // Y 轴速度分量
        this.targetObject._x += vx; // 更新 X 坐标
        this.targetObject._y += vy; // 更新 Y 坐标

        /*
        // 可选逻辑：判断导弹是否飞出视野
        if (Math.abs(this.targetObject._x) > Stage.width || Math.abs(this.targetObject._y) > Stage.height) {
            trace("导弹已离开视野");
            this.changeState("SearchTarget"); // 切换到“搜索目标”状态
        }
        */
    }
}

/*

import org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement;

// 定义全局引用
_root.missileMovement = null;

// 定义舞台宽高常量
var STAGE_WIDTH:Number = Stage.width;
var STAGE_HEIGHT:Number = Stage.height;
var EDGE_BUFFER:Number = 50; // 边缘缓冲距离
var REPULSION_FORCE:Number = 5; // 边缘斥力强度

// 定义反弹处理函数
function handleBounce(obj:Object):Void {
    // 左或右墙壁碰撞
    if (obj._x <= 0) {
        obj._x = 0;
        obj.vx = Math.abs(obj.vx); // 向右反弹
    } else if (obj._x >= STAGE_WIDTH) {
        obj._x = STAGE_WIDTH;
        obj.vx = -Math.abs(obj.vx); // 向左反弹
    }

    // 上或下墙壁碰撞
    if (obj._y <= 0) {
        obj._y = 0;
        obj.vy = Math.abs(obj.vy); // 向下反弹
    } else if (obj._y >= STAGE_HEIGHT) {
        obj._y = STAGE_HEIGHT;
        obj.vy = -Math.abs(obj.vy); // 向上反弹
    }

    // 更新旋转角度 based on new velocity
    obj.rotationAngle = Math.atan2(obj.vy, obj.vx) * (180 / Math.PI);
    obj.rotationAngle = (obj.rotationAngle + 360) % 360; // 规范化角度
    obj._rotation = obj.rotationAngle;
}

// 定义边缘斥力函数
function applyEdgeRepulsion(obj:Object):Void {
    if (obj._x < EDGE_BUFFER) {
        obj.vx += REPULSION_FORCE; // 推离左边缘
    } else if (obj._x > STAGE_WIDTH - EDGE_BUFFER) {
        obj.vx -= REPULSION_FORCE; // 推离右边缘
    }

    if (obj._y < EDGE_BUFFER) {
        obj.vy += REPULSION_FORCE; // 推离上边缘
    } else if (obj._y > STAGE_HEIGHT - EDGE_BUFFER) {
        obj.vy -= REPULSION_FORCE; // 推离下边缘
    }
}

// 定义导弹初始化逻辑
function initializeMissile():Void {
    trace("导弹初始化中...");
    _root.missileMovement.speed = 5;
    _root.missileMovement.rotationAngle = _root.missileMovement.targetObject._rotation;
    // 初始化速度分量
    var radianAngle:Number = _root.missileMovement.rotationAngle * (Math.PI / 180);
    _root.missileMovement.vx = Math.cos(radianAngle) * _root.missileMovement.speed;
    _root.missileMovement.vy = Math.sin(radianAngle) * _root.missileMovement.speed;
}

// 定义寻找目标逻辑
function searchForTarget():Boolean {
    trace("正在寻找目标...");
    _root.missileMovement.target = _root.findNearestTarget();
    if (_root.missileMovement.target != null) {
        _root.missileMovement.hasTarget = true;
        trace("找到目标: " + _root.missileMovement.target._name);
        return true;
    } else {
        _root.missileMovement.hasTarget = false;
        trace("未找到目标");
        return false;
    }
}

// 定义追踪目标逻辑
function trackTarget():Void {
    trace("追踪目标中... [" + missile._x + " , " + missile._y + "]");
    if (_root.missileMovement.target != null) {
        var missile:Object = _root.missileMovement.targetObject;
        var target:Object = _root.missileMovement.target;

        var dx:Number = target._x - missile._x;
        var dy:Number = target._y - missile._y;
        var distance:Number = Math.sqrt(dx * dx + dy * dy);

        var angleToTarget:Number = Math.atan2(dy, dx) * (180 / Math.PI);
        _root.missileMovement.rotationAngle = angleToTarget;
        _root.missileMovement._rotation = _root.missileMovement.rotationAngle;

        if (_root.missileMovement.speed < _root.missileMovement.maxSpeed) {
            _root.missileMovement.speed += _root.missileMovement.acceleration;
        }

        // 更新速度分量
        var radianAngle:Number = _root.missileMovement.rotationAngle * (Math.PI / 180);
        _root.missileMovement.vx = Math.cos(radianAngle) * _root.missileMovement.speed;
        _root.missileMovement.vy = Math.sin(radianAngle) * _root.missileMovement.speed;

        missile._x += _root.missileMovement.vx;
        missile._y += _root.missileMovement.vy;

        // 限制导弹在舞台范围内并处理反弹
        handleBounce(missile);
    } else {
        _root.missileMovement.changeState("SearchTarget");
    }
}

// 定义发射前运动逻辑
function preLaunchMove(param:String):Boolean {
    if (param == "isComplete") {
        return _root.missileMovement.targetObject._y <= 300;
    } else {
        trace("执行发射前运动...");
        _root.missileMovement.speed += _root.missileMovement.acceleration;
        _root.missileMovement.targetObject._y -= _root.missileMovement.speed;
        // 处理发射前的反弹
        handleBounce(_root.missileMovement.targetObject);
        return false;
    }
}

// 模拟一个目标查找函数
_root.findNearestTarget = function():MovieClip {
    return _root.target || null;
};

// 创建目标对象
var target:MovieClip = _root.createEmptyMovieClip("target", _root.getNextHighestDepth());
target.beginFill(0x00FF00);

// 定义绘制圆形的方法
target.drawCircle = function(x:Number, y:Number, radius:Number):Void {
    this.moveTo(x + radius, y);
    this.curveTo(x + radius, y - radius, x, y - radius);
    this.curveTo(x - radius, y - radius, x - radius, y);
    this.curveTo(x - radius, y + radius, x, y + radius);
    this.curveTo(x + radius, y + radius, x + radius, y);
};

// 绘制目标
target.drawCircle(0, 0, 10);
target.endFill();

// 设置目标名称和初始位置
target._name = "target";
target._x = Math.random() * STAGE_WIDTH;
target._y = Math.random() * (STAGE_HEIGHT / 2);

// 初始化目标速度分量
target.vx = 5;
target.vy = 5;

// 目标的逃离逻辑
target.onEnterFrame = function() {
    var missile:Object = _root.missileMovement.targetObject;
    if (missile != null) {
        var dx:Number = this._x - missile._x;
        var dy:Number = this._y - missile._y;
        var distance:Number = Math.sqrt(dx * dx + dy * dy);

        // 当距离小于一定值时，目标加速移动
        var speed:Number = distance < 100 ? 15 : 5;
        var angleAway:Number = Math.atan2(dy, dx); // 反方向移动
        this.vx = Math.cos(angleAway) * speed;
        this.vy = Math.sin(angleAway) * speed;
    }

    // 应用边缘斥力
    applyEdgeRepulsion(this);

    // 更新位置
    this._x += this.vx;
    this._y += this.vy;

    // 限制目标在舞台范围内并处理反弹
    handleBounce(this);
};

// 创建导弹对象
var missile:MovieClip = _root.createEmptyMovieClip("missile", _root.getNextHighestDepth());
missile.beginFill(0xFF0000);
missile.moveTo(-5, -5);
missile.lineTo(5, -5);
missile.lineTo(5, 5);
missile.lineTo(-5, 5);
missile.lineTo(-5, -5);
missile.endFill();

// 设置导弹初始位置
missile._x = 200;
missile._y = 400;

// 初始化导弹运动组件并赋值给全局引用
_root.missileMovement = new BaseMissileMovement({
    usePreLaunch: true, // 启用 PreLaunch 状态
    onInitializeMissile: initializeMissile,
    onSearchForTarget: searchForTarget,
    onTrackTarget: trackTarget,
    onPreLaunchMove: preLaunchMove
});

// 绑定导弹对象到运动组件
_root.missileMovement.targetObject = missile;

// 初始化导弹的速度分量
initializeMissile();

// 更新导弹运动
missile.onEnterFrame = function() {
    _root.missileMovement.updateMovement(missile);
};

*/