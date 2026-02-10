# **基于有限状态机的运动组件使用指南**

## **目录**

1. [引言](#引言)
2. [有限状态机概述](#有限状态机概述)
   - 2.1 [什么是有限状态机](#什么是有限状态机)
   - 2.2 [有限状态机的组成部分](#有限状态机的组成部分)
3. [FSMMovement 类结构详解](#FSMMovement-类结构详解)
   - 3.1 [类的定义](#类的定义)
   - 3.2 [核心属性与方法](#核心属性与方法)
4. [如何使用 FSMMovement 创建自定义运动组件](#如何使用-fsmmovement-创建自定义运动组件)
   - 4.1 [创建自定义移动类](#创建自定义移动类)
   - 4.2 [定义状态类](#定义状态类)
   - 4.3 [添加状态到状态机](#添加状态到状态机)
   - 4.4 [在对象中使用运动组件](#在对象中使用运动组件)
5. [示例：创建一个简单的子弹运动组件](#示例创建一个简单的子弹运动组件)
   - 5.1 [创建 BulletMovement 类](#创建-bulletmovement-类)
   - 5.2 [定义状态](#定义状态)
   - 5.3 [整合与使用](#整合与使用)
6. [总结](#总结)
7. [附录：完整代码示例](#附录完整代码示例)

---

## **引言**

在游戏开发中，移动逻辑往往是最为基础且复杂的部分之一。为了实现更加灵活和可扩展的移动行为，我们引入了**有限状态机（Finite State Machine，FSM）**的概念。本文将详细介绍如何使用基于 FSM 的 `FSMMovement` 类，帮助开发者创建复杂的移动组件，即使您对状态机不熟悉，也能轻松上手。

---

## **有限状态机概述**

### **什么是有限状态机**

有限状态机是一种用于建模离散系统行为的数学模型。它由一组**有限的状态**、一组**输入事件**、一组**输出事件**、以及一组**状态转移函数**组成。系统根据输入事件和当前状态，通过状态转移函数转换到下一个状态，并可能产生输出事件。

### **有限状态机的组成部分**

- **状态（State）**：系统在某一时刻的情况。
- **事件（Event）**：触发状态转换的条件或输入。
- **转移（Transition）**：从一个状态到另一个状态的变化过程。
- **动作（Action）**：在状态转换过程中执行的操作。

通过将系统的行为划分为不同的状态，可以更清晰地组织和管理复杂的逻辑，尤其适用于游戏中的角色行为、AI、移动等模块。

---

## **FSMMovement 类结构详解**

### **类的定义**

`FSMMovement` 是一个基于有限状态机的运动组件基类，旨在为各种移动对象提供统一的状态管理和移动逻辑。它实现了 `IMovement` 接口，确保具备更新移动逻辑的能力。

```actionscript
class org.flashNight.arki.bullet.BulletComponent.Movement.FSMMovement implements IMovement {
    // 状态机实例
    public var stateMachine:FSM_StateMachine;

    // 引用移动对象（例如子弹的影片剪辑）
    public var targetObject:MovieClip;

    // 构造函数
    public function FSMMovement() {
        // 初始化状态机
        this.stateMachine = new FSM_StateMachine(null, null, null);
        this.stateMachine.data = {}; // 数据黑板
        // 初始化状态
        this.initializeStates();
    }

    // 初始化状态（供子类覆盖）
    public function initializeStates():Void {
        // 子类实现，添加状态和状态转换
    }

    // 更新移动逻辑，每帧调用
    public function updateMovement(target:MovieClip):Void {
        this.targetObject = target;
        this.stateMachine.onAction();
    }

    // 状态切换方法
    public function changeState(stateName:String):Void {
        this.stateMachine.ChangeState(stateName);
    }

    // 获取当前状态名
    public function getCurrentStateName():String {
        return this.stateMachine.getActiveStateName();
    }

    // 添加状态到状态机
    public function addState(stateName:String, state:FSM_Status):Void {
        // superMachine/name/data 由 AddStatus 内部统一赋值，无需预设
        this.stateMachine.AddStatus(stateName, state);
    }
}
```

> **重要**：`FSMMovement` 的 `_started` 门控机制
>
> 状态机在调用 `start()` 之前处于**构建期**：
> - `changeState()` 仅移动内部指针，不触发 `onEnter`/`onExit` 生命周期。
> - `updateMovement()`（即 `onAction()`）会被阻断，不执行任何逻辑。
>
> 子类必须在构建完成后调用 `this.stateMachine.start()` 来启动状态机。

### **核心属性与方法**

- **stateMachine**：`FSM_StateMachine` 实例，管理状态和状态转换。
- **targetObject**：移动对象的引用，通常是一个 `MovieClip` 实例。
- **initializeStates()**：初始化状态的方法，供子类覆盖。
- **updateMovement(target:MovieClip)**：每帧调用，更新移动逻辑。需先调用 `start()`。
- **changeState(stateName:String)**：切换到指定状态。未 `start()` 时仅移指针。
- **getCurrentStateName()**：获取当前状态的名称。
- **addState(stateName:String, state:FSM_Status)**：将状态添加到状态机（`superMachine`/`name`/`data` 由内部赋值）。

---

## **如何使用 FSMMovement 创建自定义运动组件**

### **创建自定义移动类**

要创建自定义的运动组件，首先需要继承 `FSMMovement` 类，并实现 `initializeStates()` 方法。

```actionscript
class CustomMovement extends FSMMovement {
    public function CustomMovement() {
        super(); // 调用 initializeStates()（构建期）
        // 启动状态机：统一触发首次 onEnter
        this.stateMachine.start();
    }

    public function initializeStates():Void {
        // 添加自定义状态
    }
}
```

### **定义状态类**

状态类需要继承自 `FSM_Status`，并实现 `onEnter()`、`onAction()` 和 `onExit()` 方法。这些方法分别在状态进入、每帧更新和状态退出时被调用。

```actionscript
class CustomState extends FSM_Status {
    private var movement:CustomMovement;

    public function CustomState(movement:CustomMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        // 状态进入时的逻辑
    }

    public function onAction():Void {
        // 每帧更新的逻辑
    }

    public function onExit():Void {
        // 状态退出时的逻辑
    }
}
```

### **添加状态到状态机**

在 `initializeStates()` 方法中，创建状态实例并添加到状态机中，然后设置初始状态。

```actionscript
public function initializeStates():Void {
    var state1:CustomState = new CustomState(this);
    var state2:AnotherState = new AnotherState(this);

    this.addState("State1", state1);
    this.addState("State2", state2);

    // 构建期：仅移指针，不触发 onEnter（start() 由构造函数统一调用）
    this.changeState("State1");
}
```

### **在对象中使用运动组件**

创建移动对象（如子弹的 `MovieClip` 实例），并在 `onEnterFrame` 事件中调用 `updateMovement()` 方法。

```actionscript
var mc:MovieClip = _root.createEmptyMovieClip("mc", _root.getNextHighestDepth());
// 绘制或加载图形
mc._x = 100;
mc._y = 100;

var movement:CustomMovement = new CustomMovement();
// start() 已在 CustomMovement 构造函数中调用

mc.onEnterFrame = function() {
    movement.updateMovement(this);
};
```

---

## **示例：创建一个简单的子弹运动组件**

### **创建 BulletMovement 类**

```actionscript
class BulletMovement extends FSMMovement {
    public function BulletMovement() {
        super(); // 调用 initializeStates()（构建期）
        // 启动状态机：触发 Fly.onEnter
        this.stateMachine.start();
    }

    public function initializeStates():Void {
        var flyState:FlyState = new FlyState(this);
        var explodeState:ExplodeState = new ExplodeState(this);

        this.addState("Fly", flyState);
        this.addState("Explode", explodeState);

        // 构建期：仅移指针
        this.changeState("Fly");
    }
}
```

### **定义状态**

#### **FlyState**

```actionscript
class FlyState extends FSM_Status {
    private var movement:BulletMovement;

    public function FlyState(movement:BulletMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        // 初始化飞行速度
        this.movement.targetObject.speed = 10;
    }

    public function onAction():Void {
        // 更新位置
        this.movement.targetObject._x += this.movement.targetObject.speed;

        // 条件满足时切换状态
        if (this.movement.targetObject._x > 500) {
            this.superMachine.ChangeState("Explode");
        }
    }

    public function onExit():Void {
        // 清理或重置
    }
}
```

#### **ExplodeState**

```actionscript
class ExplodeState extends FSM_Status {
    private var movement:BulletMovement;

    public function ExplodeState(movement:BulletMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        // 显示爆炸效果
        trace("Bullet exploded!");
        // 移除子弹
        this.movement.targetObject.removeMovieClip();
    }

    public function onAction():Void {
        // 爆炸后的逻辑（如果有）
    }

    public function onExit():Void {
        // 清理或重置
    }
}
```

### **整合与使用**

```actionscript
var bullet:MovieClip = _root.createEmptyMovieClip("bullet", _root.getNextHighestDepth());
// 绘制子弹
bullet.beginFill(0xFFFFFF);
bullet.drawCircle(0, 0, 5);
bullet.endFill();
bullet._x = 100;
bullet._y = 200;

var bulletMovement:BulletMovement = new BulletMovement();
// start() 已在 BulletMovement 构造函数中调用

bullet.onEnterFrame = function() {
    bulletMovement.updateMovement(this);
};
```

---

## **总结**

通过以上步骤，我们成功地使用 `FSMMovement` 类创建了一个自定义的子弹运动组件。借助有限状态机的强大功能，我们可以轻松管理复杂的移动逻辑，并实现高度可扩展和可维护的代码结构。

**关键点：**

- **状态机管理状态和转换**，使逻辑清晰明了。
- **`FSMMovement` 提供了基础框架**，方便创建自定义的运动组件。
- **状态类实现具体的行为逻辑**，可以根据需求添加任意状态。

---

## **附录：完整代码示例**

### **FSMMovement.as**

```actionscript
class org.flashNight.arki.bullet.BulletComponent.Movement.FSMMovement implements IMovement {
    public var stateMachine:FSM_StateMachine;
    public var targetObject:MovieClip;

    public function FSMMovement() {
        this.stateMachine = new FSM_StateMachine(null, null, null);
        this.stateMachine.data = {};
        this.initializeStates();
    }

    public function initializeStates():Void {
        // 子类实现
    }

    public function updateMovement(target:MovieClip):Void {
        this.targetObject = target;
        this.stateMachine.onAction();
    }

    public function changeState(stateName:String):Void {
        this.stateMachine.ChangeState(stateName);
    }

    public function getCurrentStateName():String {
        return this.stateMachine.getActiveStateName();
    }

    public function addState(stateName:String, state:FSM_Status):Void {
        // superMachine/name/data 由 AddStatus 内部统一赋值，无需预设
        this.stateMachine.AddStatus(stateName, state);
    }
}
```

### **BulletMovement.as**

```actionscript
class BulletMovement extends FSMMovement {
    public function BulletMovement() {
        super(); // 调用 initializeStates()（构建期）
        // 启动状态机：触发 Fly.onEnter
        this.stateMachine.start();
    }

    public function initializeStates():Void {
        var flyState:FlyState = new FlyState(this);
        var explodeState:ExplodeState = new ExplodeState(this);

        this.addState("Fly", flyState);
        this.addState("Explode", explodeState);

        // 构建期：仅移指针
        this.changeState("Fly");
    }
}
```

### **FlyState.as**

```actionscript
class FlyState extends FSM_Status {
    private var movement:BulletMovement;

    public function FlyState(movement:BulletMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        this.movement.targetObject.speed = 10;
    }

    public function onAction():Void {
        this.movement.targetObject._x += this.movement.targetObject.speed;

        if (this.movement.targetObject._x > 500) {
            this.superMachine.ChangeState("Explode");
        }
    }

    public function onExit():Void {
        // 清理或重置
    }
}
```

### **ExplodeState.as**

```actionscript
class ExplodeState extends FSM_Status {
    private var movement:BulletMovement;

    public function ExplodeState(movement:BulletMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        trace("Bullet exploded!");
        this.movement.targetObject.removeMovieClip();
    }

    public function onAction():Void {
        // 爆炸后的逻辑
    }

    public function onExit():Void {
        // 清理或重置
    }
}
```

### **主程序**

```actionscript
var bullet:MovieClip = _root.createEmptyMovieClip("bullet", _root.getNextHighestDepth());
bullet.beginFill(0xFFFFFF);
bullet.drawCircle(0, 0, 5);
bullet.endFill();
bullet._x = 100;
bullet._y = 200;

var bulletMovement:BulletMovement = new BulletMovement();
// start() 已在 BulletMovement 构造函数中调用

bullet.onEnterFrame = function() {
    bulletMovement.updateMovement(this);
};
```

---
