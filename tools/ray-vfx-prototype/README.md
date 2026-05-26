# 射线视觉原型 (Ray VFX Prototype)

在 AS2 实施前用 Python 快速验证射线渲染器的概念参数。AS2 编译循环 ~30s/轮，Python ~1s/轮，**先在 Python 锁定"概念参数"再下放 AS2**，可节约 20~30 倍迭代时间。

## 适用范围

**Python 能验证**:
- 几何拓扑 (切片数 / 顶点分布 / 连接方式)
- 时序节奏 (爆发帧数 / 律动速度 / 旋转角速度)
- 色彩配比 (亮/暗/中性/发光的相对关系)
- 动效叠加 (旋转 + 律动 + α 调制 是否冲突)

**Python 无法验证, 必须进 AS2**:
- AVM1 矢量渲染的细线抗锯齿表现
- `mc.blendMode = "add"` 加色混合在不同背景上的色彩偏移
- 多发同时渲染的实际帧率影响
- Flash CS6 编译产物的尺寸/性能

## 工作流

```
设计概念  →  Python 原型迭代  →  锁定参数  →  AS2 实施  →  入游戏微调线宽/混色
              ^                                                |
              | (失败/不满意)                                  |
              +----------------------------------------------- + (仅当数值/几何方向错了)
```

锁定参数后, Python 原型只负责"参数考古"（回看为什么选某个值）, 不再迭代。
迭代请去对应的 `AS2 Renderer` + `TeslaRayConfig` + `VfxPresets`。

## 当前归档

### 八门金锁束流 (镇暴霰弹专用)

- [`八门金锁_视觉原型.py`](八门金锁_视觉原型.py) — 主脚本, 头部 `=== 设计参数 ===` 块集中暴露所有可调项
- [`八门金锁_变体扫描.py`](八门金锁_变体扫描.py) — 批量生成对照变体, 用于关键设计决策的 A/B/C 对比

#### 运行

```bash
python 八门金锁_视觉原型.py        # 主基线视频
python 八门金锁_变体扫描.py        # 5 个对照变体一次性生成
```

输出 `*.mp4` 在脚本同目录, 变体在 `变体输出/` 子目录, 都已 git ignore。

#### 实施位置 (AS2 端)

| Python 原型 → AS2 |
|---|
| `draw_frame()` → [`BaguaRodRenderer.render()`](../../scripts/类定义/org/flashNight/arki/render/renderer/BaguaRodRenderer.as) |
| `=== 设计参数 ===` 块 → [`VfxPresets.bagua_rod`](../../scripts/类定义/org/flashNight/arki/render/VfxPresets.as) 预设 |
| 字段定义 → [`TeslaRayConfig.as`](../../scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Config/TeslaRayConfig.as) `VFX_BAGUA_ROD` 段 |
| 注册 → [`RayStyleRegistry.as`](../../scripts/类定义/org/flashNight/arki/render/RayStyleRegistry.as) |
| 用法 → [`bullets_cases.xml`](../../data/items/bullets_cases.xml) 的 `镇暴射线` 弹种 |

## 复用模式

新增射线 renderer 时, 复制 `八门金锁_视觉原型.py` 改名 + 改顶部参数块即可起步。`变体扫描.py` 通过动态 import 复用同一份 `draw_frame()`, 只覆盖参数。

## 依赖

`matplotlib` + `numpy` + 可选 `ffmpeg` (生成 mp4, 缺失时自动 fallback 到 PillowWriter gif)。
