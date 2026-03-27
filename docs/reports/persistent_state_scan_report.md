# 持久状态扫描报告

**扫描日期**: 2025-12-01
**项目路径**: `CRAZYFLASHER7StandAloneStarter/resources`
**扫描文件数**: 1375 个 .as 文件

---

## 一、执行摘要

### 核心问题
> 在使用 `loadMovieNum(..., 0)` 重载主文件时，哪些状态不会被自动清空，从而有"跨局生命周期"，需要专门防护或重构？

### 关键发现

| 类别 | 数量 | 风险等级 |
|-----|------|---------|
| 高风险持久状态 | 5 | 🔴 需要修复 |
| 中风险持久状态 | 6 | 🟡 需要监控 |
| 低风险持久状态 | 4+ | 🟢 可接受 |
| 循环引用 | 2 组 | 🔴 需要切断 |

### 架构结论

**✅ asLoader 不会跨局常驻**
- gameworld 使用 `attachMovie` 从库加载，非独立 level
- 未发现 `loadMovieNum` / `unloadMovieNum` 调用
- asLoader.swf 存在但未在代码中直接引用为常驻模块

---

## 二、高风险持久状态（必须处理）

### 2.1 StageManager 单例
**文件**: `scripts/类定义/org/flashNight/arki/scene/StageManager.as`

```
风险点:
├─ 持有 gameworld:MovieClip 强引用
├─ 持有 SceneManager, WaveSpawner, StageEventHandler 单例引用
├─ 与 WaveSpawner 形成循环引用
├─ 访问 23+ 处 _root 属性
└─ dispose_called_on_restart = false
```

**_root 引用清单**:
- `_root.当前为战斗地图`
- `_root.d_倒计时显示`
- `_root.加载背景列表`
- `_root.天气系统.关卡环境设置`
- `_root.Xmax`, `Xmin`, `Ymax`, `Ymin`
- `_root.无限过图计时器`
- `_root.帧计时器`
- `_root.soundEffectManager`

**现有清理方法**: `closeStage()`, `clear()`
**问题**: 清理方法存在但游戏重启时未调用

---

### 2.2 SceneManager 单例
**文件**: `scripts/类定义/org/flashNight/arki/scene/SceneManager.as`

```
风险点:
├─ 持有 gameworld:MovieClip 强引用
├─ 创建 BitmapData 对象 (layers[0], layers[2])
└─ 需要调用 dispose() 释放位图资源
```

**现有清理方法**: `removeGameWorld()`
```actionscript
public function removeGameWorld():Void {
    gameworld.dispatcher.destroy();
    gameworld.dispatcher = null;
    gameworld.deadbody.layers[0].dispose();
    gameworld.deadbody.layers[2].dispose();
    gameworld.removeMovieClip();
    gameworld = null;
}
```

---

### 2.3 WaveSpawner 单例
**文件**: `scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as`

```
风险点:
├─ 持有 gameworld:MovieClip 强引用
├─ 与 StageManager 形成循环引用
├─ 访问 15+ 处 _root 属性
└─ ❌ 缺少完整的 reset/dispose 方法
```

**_root 引用清单**:
- `_root.d_剩余敌人数`
- `_root.无限过图计时器`
- `_root.帧计时器`
- `_root.难度等级`
- `_root.Xmin`, `Xmax`, `Ymin`, `Ymax`
- `_root.加载游戏世界人物()`

---

### 2.4 EventBus 单例
**文件**: `scripts/类定义/org/flashNight/neur/Event/EventBus.as`

```
风险点:
├─ 饿汉式初始化 (类加载时创建)
├─ 使用 1024 槽位对象池
├─ ❌ 订阅者累积无清理机制
└─ 长期运行可能堆积死亡对象
```

**初始化方式**:
```actionscript
public static var instance:EventBus = new EventBus();  // 饿汉式
```

---

### 2.5 Stage 监听器
**文件**: `scripts/通信/通信_fs_帧计时器.as:664`

```actionscript
var stageWatcher:Object = {};
stageWatcher.onFullScreen = function(nowFull:Boolean):Void {
    EventBus.getInstance().publish("FlashFullScreenChanged", nowFull);
};
stageWatcher.onResize = function():Void {
    _root.发布消息("Flash 大小状态变更");
};
Stage.addListener(stageWatcher);  // ❌ 无对应 removeListener
```

---

## 三、中风险持久状态（需要监控）

### 3.1 _global.__HOLO_STRIPE__
**文件**: `scripts/展现/UI交互/UI交互_lsy_对话框UI.as:51`

```actionscript
if (_global.__HOLO_STRIPE__ == undefined) {
    var bd:BitmapData = new BitmapData(2, 2, true, 0x00000000);
    bd.setPixel32(0, 0, 0x77FFFFFF);
    bd.setPixel32(1, 0, 0x77FFFFFF);
    _global.__HOLO_STRIPE__ = bd;
}
```

**评估**: 2x2 像素 BitmapData，内存占用极小，但无清理机制

---

### 3.2 WaveSpawnWheel 单例
**文件**: `scripts/类定义/org/flashNight/arki/scene/WaveSpawnWheel.as`

```
状态:
├─ ✅ 有 clear() 方法
├─ 持有 slots:Array, minHeap:Array, eventDict:Object
└─ ⚠️ 与 WaveSpawner 形成循环引用
```

---

### 3.3 KeyManager 静态类
**文件**: `scripts/类定义/org/flashNight/arki/key/KeyManager.as`

```
状态:
├─ 纯静态类 (所有字段/方法都是 static)
├─ 在 _root 上创建 keyPollMC 用于每帧轮询
└─ ❌ keyPollMC 无清理机制
```

```actionscript
_root.createEmptyMovieClip("keyPollMC", _root.getNextHighestDepth());
_root.keyPollMC.onEnterFrame = function() { ... };
```

---

### 3.4 Key.TileManager 监听器
**文件**: `scripts/类定义/org/flashNight/sara/util/TileManager.as:228`

```actionscript
Key.addListener({
    onKeyDown: function() { ... },
    onKeyUp: function() { ... }
});  // ❌ 无对应 removeListener
```

---

## 四、低风险持久状态（可接受）

### 4.1 SharedObject 存档系统
**用途**: 游戏存档的预期持久化

| SharedObject Key | 用途 | 文件位置 |
|-----------------|------|---------|
| `mydata[存盘名]` | 主角完整存档 | 通信_lsy_原版存档系统.as |
| `战宠` | 宠物数据 | 引擎_lsy_战宠系统.as |
| `tasks_to_do` | 当前任务 | 通信_鸡蛋_任务系统.as |
| `tasks_finished` | 完成记录 | 通信_鸡蛋_任务系统.as |
| `商城已购买物品` | 已购物品 | UI交互_lsy_商城系统.as |

**结论**: 这是预期行为，不需要在游戏重启时清理

---

### 4.2 伤害处理器单例（12个）
**位置**: `scripts/类定义/org/flashNight/arki/component/Damage/`

```
BaseDamageHandle, BasicDamageHandle, CritDamageHandle, ExecuteDamageHandle,
LifeStealDamageHandle, MagicDamageHandle, NanoToxicDamageHandle,
TrueDamageHandle, UniversalDamageHandle, ...
```

**评估**: 无状态纯处理器，无全局引用，无需清理

---

### 4.3 子弹生命周期处理器（10个）
**位置**: `scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/`

```
BasePostHitFinalizer, ColliderUpdater, CollisionAndHitProcessor,
DestructionFinalizer, HitResultProcessor, NonPointCollisionDetector,
PointCollisionDetector, PostHitFinalizer, TargetFilter, TargetRetriever
```

**评估**: 无状态，高频调用性能关键路径，无需清理

---

## 五、循环引用分析

### 5.1 StageManager ↔ WaveSpawner
```
StageManager.instance
    └─ spawner: WaveSpawner ──┐
                              │
WaveSpawner.instance          │
    └─ stageManager ──────────┘
```

**风险**: 两个单例互相引用，需主动切断才能 GC

---

### 5.2 WaveSpawner ↔ WaveSpawnWheel
```
WaveSpawner.instance
    └─ waveSpawnWheel: WaveSpawnWheel ──┐
                                        │
WaveSpawnWheel.instance                 │
    └─ waveSpawner ─────────────────────┘
```

---

## 六、_root 注入属性汇总

### 永久保留的属性
| 属性名 | 类型 | 来源 |
|-------|------|-----|
| `_root.帧计时器` | Object | 通信_fs_帧计时器.as |
| `_root.服务器` | Object+ServerManager | 通信_fs_本地服务器.as |
| `_root.units` | Array | 兵种系统_兼容.as |
| `_root.mercs_list` | Array | 佣兵系统_兼容.as |
| `_root.物品属性列表` | Object | ItemDataLoader |
| `_root.keyPollMC` | MovieClip | KeyManager |

### 启动后清理的属性
| 属性名 | 清理位置 |
|-------|---------|
| `_root.preloaders` | 逻辑系统分区_最终化3.as |
| `_root.loaders` | 逻辑系统分区_最终化3.as |
| `_root.loaderkillers` | 逻辑系统分区_最终化3.as |
| `_root.LogicSystems` | 逻辑系统分区_最终化3.as |

### 场景切换时替换的属性
| 属性名 | 说明 |
|-------|-----|
| `_root.gameworld` | attachMovie 新 gameworld 时自动替换 |

---

## 七、监听器与定时器汇总

### 监听器风险表

| 类型 | 数量 | 清理机制 | 风险等级 |
|-----|------|---------|---------|
| Stage.addListener | 1 | ❌ 无 | 🔴 高 |
| Key.addListener | 3 | ⚠️ 部分 | 🟡 中 |
| EventBus.subscribe | 多 | ❌ 无全局清理 | 🔴 高 |
| FrameImpulse监听 | 多 | ✅ 有方法 | 🟡 中 |
| 自定义监听器数组 | 多 | ✅ 多数有 | 🟢 低 |

### EventBus 订阅清单（无清理）
```actionscript
eventBus.subscribe("frameUpdate", function():Void { ... }, this);
EventBus.getInstance().subscribe("SceneChanged", StaticInitializer.onSceneChanged);
EventBus.getInstance().subscribe("SceneChanged", SceneCoordinateManager.update);
// ... 更多订阅
```

---

## 八、建议的清理流程

### 场景切换时（推荐顺序）
```actionscript
// 1. 关闭关卡状态
StageManager.getInstance().clear();

// 2. 清理事件处理
StageEventHandler.getInstance().clear();

// 3. 清理时间轮
WaveSpawnWheel.getInstance().clear();

// 4. 移除游戏世界
SceneManager.getInstance().removeGameWorld();

// 5. 关闭刷怪器
WaveSpawner.getInstance().close();
```

### 游戏重启时（完整清理）
```actionscript
// 执行上述所有清理，然后：

// 6. 移除 Stage 监听器
Stage.removeListener(stageWatcher);

// 7. 清空 EventBus 订阅（需新增方法）
EventBus.getInstance().clear();  // 建议新增

// 8. 停止所有音效
SoundEffectManager.stopAll();

// 9. 移除键盘轮询
_root.keyPollMC.removeMovieClip();
```

---

## 九、建议的代码改进

### 9.1 为 EventBus 添加清理方法
```actionscript
// EventBus.as 新增方法
public function clear():Void {
    this.listeners = {};
    this.pool = new Array(1024);
    this.availSpace = [];
    for (var i:Number = 0; i < 1024; i++) {
        this.availSpace.push(i);
    }
}
```

### 9.2 为 WaveSpawner 添加完整 dispose
```actionscript
// WaveSpawner.as 新增方法
public function dispose():Void {
    this.close();
    this.gameworld = null;
    this.spawner = null;
    this.sceneManager = null;
    this.stageManager = null;
    this.waveSpawnWheel = null;
}
```

### 9.3 创建全局清理入口
```actionscript
// 建议在 _root 或 GameManager 中添加
_root.cleanupForRestart = function():Void {
    // 1. 移除监听器
    Stage.removeListener(stageWatcher);

    // 2. 清理单例
    StageManager.getInstance().clear();
    StageEventHandler.getInstance().clear();
    WaveSpawnWheel.getInstance().clear();
    SceneManager.getInstance().removeGameWorld();
    WaveSpawner.getInstance().dispose();

    // 3. 清理 EventBus
    EventBus.getInstance().clear();

    // 4. 移除 _root 上的临时对象
    _root.keyPollMC.removeMovieClip();

    // 5. 清理 _global
    if (_global.__HOLO_STRIPE__) {
        _global.__HOLO_STRIPE__.dispose();
        delete _global.__HOLO_STRIPE__;
    }
};
```

---

## 十、总结

### 安全的纯工具类（无需处理）
- `ObjectUtil`, `StringUtils` 等工具类
- 伤害处理器单例（12个）
- 子弹生命周期处理器（10个）
- `LinearCongruentialEngine` 随机数引擎

### 必须设计 reset/dispose 的状态模块
- `StageManager` - 已有但需确保调用
- `SceneManager` - 已有 removeGameWorld()
- `WaveSpawner` - **缺少**，需新增
- `EventBus` - **缺少**，需新增

### 跨局持久且无清理机制的高危点
1. **Stage.stageWatcher** - 需添加 removeListener 调用点
2. **EventBus 订阅累积** - 需添加 clear() 方法
3. **StageManager ↔ WaveSpawner 循环引用** - 需在清理时主动断开
4. **_root.keyPollMC** - 需在重启时移除

### 建议从 _global 移回主文件的对象
- `_global.__HOLO_STRIPE__` - 可移至 UI 模块内部管理

### 需要在"重启游戏"前调用的统一清理函数
建议创建 `_root.cleanupForRestart()` 作为统一入口，按上述第九节的顺序执行清理。

---

**报告结束**
