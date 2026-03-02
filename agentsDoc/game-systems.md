# 游戏系统索引

> 闪客快打7 各核心游戏系统的概述与入口文件索引。
> 深入某个系统时先查阅此文档定位关键文件。

---

## 1. 子弹系统
- **位置**：`scripts/类定义/org/flashNight/arki/bullet/`
- **核心**：BulletFactory（工厂模式创建和管理子弹实例）
- **审查文档**：无独立 Review Prompt
<!-- TODO: 补充子弹系统的详细架构描述 -->

## 2. Buff/属性系统
- **位置**：`scripts/类定义/org/flashNight/arki/component/`
- **核心**：BuffCalculator 等组件
- **审查文档**：
  - `tools/BuffSystem_Review_Prompt_CN.md`
  - `tools/BuffSystem_NestedProperty_Review_Prompt_CN.md`
  - `tools/BuffSystem_NestedProperty_Review_Prompt_v2_CN.md`
<!-- TODO: 补充 Buff 系统的计算流程 -->

## 3. 事件系统
- **位置**：`scripts/类定义/org/flashNight/neur/`
- **核心**：自定义事件总线、EventDispatcher 模式
- **审查文档**：`tools/EventSystem_Review_Prompt_CN.md`
<!-- TODO: 补充事件系统的使用模式 -->

## 4. 计时器系统
- **位置**：`scripts/类定义/org/flashNight/neur/Timer/`、`scripts/类定义/org/flashNight/neur/ScheduleTimer/`
- **核心**：FrameTimer.as（帧计时器）、EnhancedCooldownWheel.as（冷却轮调度器）
- **惯例**：AS2 原生 `setTimeout`/`setInterval` 可用但一般不使用，优先用帧计时器或 EnhancedCooldownWheel
- **审查文档**：`tools/TimerSystem_Review_Prompt_CN.md`
<!-- TODO: 补充 FrameTimer 与 EnhancedCooldownWheel 的选用场景区分 -->

## 5. 摄像机系统
- **位置**：`scripts/类定义/org/flashNight/arki/camera/`
<!-- TODO: 补充摄像机系统描述 -->

## 6. 音频系统
- **位置**：`scripts/类定义/org/flashNight/arki/audio/`
- **核心**：LightweightSoundEngine（实现 IMusicEngine 接口）
- 音频资源目录：`music/`、`sounds/`
<!-- TODO: 补充音频系统架构 -->

## 7. 物理引擎
- **位置**：`scripts/类定义/org/flashNight/sara/`
- **功能**：粒子系统、物理约束、表面碰撞检测
<!-- TODO: 补充物理引擎的使用范围和限制 -->

## 8. 深度管理（未投入使用）
- **核心文件**：DepthManager.as
- **设计**：基于 AVL 树管理 MovieClip 深度层级
- **状态**：性能测试未通过，当前未投入使用
- **审查文档**：`tools/BalancedTreeSystem_Review_Prompt_CN.md`
<!-- TODO: 记录性能瓶颈的具体原因和优化方向 -->

## 9. 数据结构与算法
- **位置**：`scripts/类定义/org/flashNight/naki/`
- **内容**：高级矩阵运算、随机数引擎（LCG、MersenneTwister）、数据结构
<!-- TODO: 补充各数据结构的使用场景 -->

## 10. 通用工具
- **位置**：`scripts/类定义/org/flashNight/gesh/`
- **内容**：数组工具、字符串解析（EvalParser）、算法实现
<!-- TODO: 补充关键工具函数列表 -->

## 11. 小游戏系统
- **位置**：`scripts/类定义/org/flashNight/hana/`
- **定位**：独立小游戏仓库，可独立运行，主文件可调用加载
<!-- TODO: 补充小游戏的加载和集成方式 -->

## 12. 关卡系统
- **帧脚本**：`scripts/逻辑/关卡系统/`
- **数据**：`data/stages/`
<!-- TODO: 补充关卡系统的运行流程 -->
