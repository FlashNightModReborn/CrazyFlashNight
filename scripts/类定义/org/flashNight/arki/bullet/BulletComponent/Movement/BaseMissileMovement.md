# **BaseMissileMovement 组件使用文档**

---

## **目录**

1. [概述](#1-概述)
2. [组件结构](#2-组件结构)
3. [实现逻辑](#3-实现逻辑)
4. [使用指南](#4-使用指南)
   - [4.1 创建导弹对象](#41-创建导弹对象)
   - [4.2 定义回调函数](#42-定义回调函数)
   - [4.3 初始化导弹运动组件](#43-初始化导弹运动组件)
   - [4.4 绑定导弹对象](#44-绑定导弹对象)
   - [4.5 启动运动](#45-启动运动)
5. [示例代码](#5-示例代码)
6. [注意事项](#6-注意事项)
7. [扩展与优化](#7-扩展与优化)

---

## **1. 概述**

`BaseMissileMovement` 是一个基于有限状态机（FSM）的导弹运动组件，旨在简化导弹在游戏或应用中的运动逻辑控制。该组件负责管理导弹的速度、加速度、旋转角度以及目标追踪等核心运动行为。通过预定义的状态和回调函数，用户可以轻松定制导弹的运动模式，实现复杂的运动效果。

---

## **2. 组件结构**

### **2.1 类继承**

- **父类**: `FSMMovement`
- **子类**: `BaseMissileMovement`

### **2.2 属性**

| **属性名**               | **类型**     | **默认值** | **说明**                                 |
|--------------------------|--------------|------------|------------------------------------------|
| `speed`                  | `Number`     | `0`        | 当前导弹速度                             |
| `acceleration`           | `Number`     | `0.5`      | 导弹加速度                               |
| `maxSpeed`               | `Number`     | `10`       | 导弹最大速度                             |
| `rotationAngle`          | `Number`     | `0`        | 当前旋转角度（以度为单位）               |
| `target`                 | `Object`     | `null`     | 当前目标引用                             |
| `hasTarget`              | `Boolean`    | `false`    | 是否已经锁定目标                         |
| `usePreLaunch`           | `Boolean`    | `false`    | 是否启用“预发射（PreLaunch）”状态        |
| `onInitializeMissile`    | `Function`   | `null`     | 导弹初始化回调方法                       |
| `onSearchForTarget`      | `Function`   | `null`     | 搜索目标回调方法                         |
| `onTrackTarget`          | `Function`   | `null`     | 追踪目标回调方法                         |
| `onPreLaunchMove`        | `Function`   | `null`     | 发射前运动回调方法                       |

### **2.3 委托属性**

为了优化性能，组件使用了委托函数，将回调方法预先绑定到组件的作用域：

| **委托属性名**                 | **说明**                                 |
|--------------------------------|------------------------------------------|
| `onInitializeMissileDelegate`  | 优化后的导弹初始化回调方法               |
| `onSearchForTargetDelegate`    | 优化后的搜索目标回调方法                 |
| `onTrackTargetDelegate`        | 优化后的追踪目标回调方法                 |
| `onPreLaunchMoveDelegate`      | 优化后的发射前运动回调方法               |
| `isPreLaunchCompleteDelegate`  | 判断预发射是否完成的回调方法（带参数）   |

---

## **3. 实现逻辑**

### **3.1 构造函数**

构造函数接受一个参数对象，用于配置是否启用预发射状态以及外部提供的回调方法。

```actionscript
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
```

### **3.2 委托方法绑定**

使用 `Delegate` 类将回调方法绑定到组件的作用域，提升执行效率。

```actionscript
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
```

### **3.3 状态初始化**

通过 `initializeStates` 方法将各个状态添加到状态机，并设置初始状态。

```actionscript
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
```

### **3.4 状态对应的方法**

组件提供多个方法，供不同状态调用以执行相应的逻辑。这些方法通过预先绑定的委托函数调用外部回调。

```actionscript
/**
 * 初始化导弹参数
 */
public function initializeMissile():Void {
    if (this.onInitializeMissileDelegate != null) {
        this.onInitializeMissileDelegate(); // 无参数
    }
}

/**
 * 寻找目标
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
 */
public function trackTarget():Void {
    if (this.onTrackTargetDelegate != null) {
        this.onTrackTargetDelegate(); // 无参数
    }
}

/**
 * 发射前运动逻辑（可选）
 */
public function preLaunchMove():Void {
    if (this.onPreLaunchMoveDelegate != null) {
        this.onPreLaunchMoveDelegate(); // 无参数
    }
}

/**
 * 判断是否结束 PreLaunch 状态
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
```

---

## **4. 使用指南**

### **4.1 创建导弹对象**

首先，需要在舞台上创建一个导弹的 `MovieClip` 对象，并为其赋予视觉形象。

```actionscript
// 创建导弹对象
var missile:MovieClip = _root.createEmptyMovieClip("missile", _root.getNextHighestDepth());
missile.beginFill(0xFF0000); // 红色填充
missile.moveTo(-5, -5);
missile.lineTo(5, -5);
missile.lineTo(5, 5);
missile.lineTo(-5, 5);
missile.lineTo(-5, -5);
missile.endFill();

// 设置导弹初始位置
missile._x = 200;
missile._y = 400;
```

### **4.2 定义回调函数**

根据组件需要，实现导弹运动的各个阶段的逻辑。这些函数将被传递给 `BaseMissileMovement` 组件。

#### **4.2.1 导弹初始化逻辑**

```actionscript
function initializeMissile():Void {
    trace("初始化导弹...");
    _root.missileMovement.speed = 5; // 设置初始速度
    _root.missileMovement.rotationAngle = 90; // 设置初始角度（向上）
}
```

#### **4.2.2 搜索目标逻辑**

```actionscript
function searchForTarget():Boolean {
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
```

#### **4.2.3 追踪目标逻辑**

```actionscript
function trackTarget():Void {
    var missile:Object = _root.missileMovement.targetObject;
    var target:Object = _root.missileMovement.target;

    if (target) {
        var dx:Number = target._x - missile._x;
        var dy:Number = target._y - missile._y;
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
```

#### **4.2.4 发射前运动逻辑**

```actionscript
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
```

### **4.3 初始化导弹运动组件**

将回调函数传递给 `BaseMissileMovement` 组件，并实例化该组件。

```actionscript
// 初始化导弹运动组件并赋值给全局引用
_root.missileMovement = new BaseMissileMovement({
    usePreLaunch: true, // 启用 PreLaunch 状态
    onInitializeMissile: initializeMissile,
    onSearchForTarget: searchForTarget,
    onTrackTarget: trackTarget,
    onPreLaunchMove: preLaunchMove
});
```

### **4.4 绑定导弹对象**

将舞台上的导弹 `MovieClip` 绑定到组件的 `targetObject` 属性，以便组件能控制导弹的位置和旋转。

```actionscript
// 绑定导弹对象到运动组件
_root.missileMovement.targetObject = missile;
```

### **4.5 启动运动**

调用初始化逻辑，并在每帧更新导弹的运动。

```actionscript
// 初始化导弹的速度分量
initializeMissile();

// 更新导弹运动
missile.onEnterFrame = function() {
    _root.missileMovement.updateMovement(missile);
};
```

---

## **5. 示例代码**

以下是一个完整的示例，展示如何使用 `BaseMissileMovement` 组件控制导弹的运动。

```actionscript
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

```

### **5. 注意事项**

1. **委托缓存初始化**:
   - 在使用 `Delegate` 类前，确保已正确初始化缓存。组件内部已调用 `Delegate.init()`，无需额外操作。

2. **回调函数的有效性**:
   - 确保传递给组件的回调函数 (`onInitializeMissile` 等) 是有效的函数，且逻辑正确。

3. **状态机的正确切换**:
   - 组件通过状态机自动管理导弹的状态切换，用户无需手动干预。确保各个状态的逻辑能正确触发状态切换条件。

4. **目标对象绑定**:
   - 导弹的运动将直接影响 `targetObject` 的位置和旋转。确保 `targetObject` 已正确绑定到导弹的 `MovieClip` 对象。

5. **性能优化**:
   - 委托机制已优化回调调用，但在高频调用或大量导弹实例时，仍需注意整体性能，避免不必要的资源消耗。

---

## **6. 扩展与优化**

### **6.1 多导弹支持**

若需要在场景中管理多个导弹实例，可为每个导弹创建独立的 `BaseMissileMovement` 实例，并分别绑定各自的导弹 `MovieClip`。

```actionscript
// 创建多个导弹
for (var i:Number = 0; i < 5; i++) {
    var missile:MovieClip = _root.createEmptyMovieClip("missile" + i, _root.getNextHighestDepth());
    // 设置导弹外观和初始位置
    // ...

    // 初始化运动组件
    var missileMovement:BaseMissileMovement = new BaseMissileMovement({
        usePreLaunch: true,
        onInitializeMissile: initializeMissile,
        onSearchForTarget: searchForTarget,
        onTrackTarget: trackTarget,
        onPreLaunchMove: preLaunchMove
    });

    // 绑定导弹对象
    missileMovement.targetObject = missile;

    // 启动运动
    missile.onEnterFrame = function() {
        missileMovement.updateMovement(missile);
    };
}
```

### **6.2 自定义状态**

若需要新增导弹的行为状态，可继承 `BaseMissileMovement` 并扩展状态机。

```actionscript
// 定义新的状态类
class ExplodeState extends State {
    private var movement:BaseMissileMovement;

    public function ExplodeState(movement:BaseMissileMovement) {
        super();
        this.movement = movement;
    }

    public function execute():Void {
        // 实现爆炸逻辑
        trace("导弹爆炸！");
        // 移除导弹对象
        this.movement.targetObject.removeMovieClip();
        // 停止状态机
        this.movement.stop();
    }
}

// 在 BaseMissileMovement 中添加新状态
public function initializeStates():Void {
    // 现有状态初始化
    // ...

    // 添加爆炸状态
    var explodeState:ExplodeState = new ExplodeState(this);
    this.addState("Explode", explodeState);
}
```

### **6.3 调试与日志**

在关键逻辑处添加 `trace` 语句，输出当前状态、速度、位置等信息，便于调试和监控导弹行为。

```actionscript
public function freeFly():Void {
    trace("状态: FreeFly, 速度: " + this.speed + ", 位置: (" + this.targetObject._x + ", " + this.targetObject._y + ")");
    // 现有自由飞行逻辑
    // ...
}
```

---

## **7. 总结**

`BaseMissileMovement` 组件通过有限状态机和委托机制，为导弹的运动逻辑提供了高效、模块化的解决方案。用户只需定义必要的回调函数，并通过简单的配置即可实现复杂的导弹行为控制。组件的设计确保了职责清晰，易于扩展，适用于各类需要导弹运动控制的项目。

通过本指南，用户应能够快速上手 `BaseMissileMovement` 组件，灵活定制导弹的运动逻辑，提升项目的开发效率和性能表现。