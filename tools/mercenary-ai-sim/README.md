# 佣兵 AI 寻路模拟器

外部 Python 模拟环境，用于离线测试和优化 `MecenaryBehavior.as` 的寻路逻辑。

## 问题背景

佣兵 NPC 需要在场景中找到"门"（出生点）并走过去卸载。当前寻路依赖 `Mover.isReachable` 的 **3 条 L 路径**（直线 / 先横后纵 / 先纵后横）判定可达性，遇到复杂碰撞体（U形、Z字走廊、错位双墙等）时全部失败，佣兵只能靠随机漫游碰运气，表现为长时间迷茫或超时卡死。

## 架构

```
mercenary-ai-sim/
├── map_model.py      # 地图模型：XML 解析 + 随机生成 + 对抗性地图
├── collision.py      # 碰撞检测：精确复刻 AS2 Mover.isReachable 的 L-path 逻辑
├── mercenary_ai.py   # AI 状态机：精确复刻 MecenaryBehavior FSM
├── visualize.py      # matplotlib 可视化：地图 + 轨迹 + 统计面板
├── run_sim.py        # CLI 主入口
├── requirements.txt  # Python 依赖
└── results/          # 输出图片和 JSON 统计
```

## 快速开始

```bash
# 安装依赖
pip install -r requirements.txt

# 跑对抗性测试（默认模式）—— 验证当前 AI 在刁钻地图上的表现
python run_sim.py

# 跑真实地图（从 scene_environment.xml 加载碰撞数据）
python run_sim.py --real

# 跑随机生成地图
python run_sim.py --random --difficulty hard --n-maps 10

# 全部模式 + 保存结果（不弹窗）
python run_sim.py --real --random --adversarial --no-show --save-dir results/

# 固定随机种子保证可复现
python run_sim.py --adversarial --seed 42 --n-agents 100
```

## CLI 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `--real` | off | 加载真实地图 |
| `--random` | off | 随机生成测试地图 |
| `--adversarial` | off | 对抗性测试地图（5种 pattern） |
| `--xml PATH` | 自动定位 | scene_environment.xml 路径 |
| `--map-name NAME` | 全部 | 按名称过滤真实地图 |
| `--difficulty` | medium | 随机地图难度：easy/medium/hard |
| `--n-maps` | 5 | 随机地图数量 |
| `--n-agents` | 50 | 每张地图的佣兵数量 |
| `--n-doors` | 2 | 每张地图的门数量 |
| `--max-ticks` | 1000 | 每个佣兵最大模拟步数 |
| `--seed` | 随机 | 随机种子 |
| `--no-show` | off | 不弹窗显示图表 |
| `--save-dir DIR` | 不保存 | 结果输出目录 |

## 对抗性地图 Pattern

| Pattern | 拓扑 | 击败 L-path 的原理 |
|---|---|---|
| `wall_gap` | 单道纵墙 + 中间缺口 | 直线和两种 L 都被墙挡，需绕到缺口 |
| `zigzag` | 两道错位纵墙 | 需 S 形绕行，任何单次 L 转弯都不够 |
| `u_trap` | U 形障碍，门在内部 | 需绕到 U 的开口进入 |
| `spiral` | 嵌套 C 形，门在中心 | 需多次转弯穿越两层 |
| `double_wall` | 平行双墙缺口不对齐 | 同 zigzag，更紧凑 |

## Baseline 测试结果（当前 AI, seed=42, n=100）

| Pattern | Exit Rate | Avg Exit Frames |
|---|---|---|
| u_trap | 77% | 949 |
| spiral | 77% | 945 |
| zigzag | 85% | 777 |
| double_wall | 89% | 761 |
| wall_gap | 95% | 752 |

真实地图（门放在边界）：100%，因为边界位置 L-path 基本可达。

## Baseline vs Grid BFS 对比（seed=42, n=100）

```
python run_sim.py --compare --seed 42 --n-agents 100
```

| Pattern | Baseline | BFS | Rate Delta | Frame Delta |
|---|---|---|---|---|
| u_trap | 72% | **93%** | **+21%** | **-175f** |
| spiral | 76% | **84%** | **+8%** | -0f |
| zigzag | 83% | **85%** | +2% | +17f |
| double_wall | 92% | **93%** | +1% | +16f |
| wall_gap | 93% | 91% | -2% | -10f |

**结论**：Grid BFS 在 L-path 结构性失败的场景（u_trap, spiral）上提升显著。
简单场景两者接近，BFS 不会引入退化。

## 迭代工作流

1. **建立 baseline**：用当前 AI 跑对抗性测试集，记录 exit rate 和帧数
2. **实现改进算法**：在 `collision.py` / `mercenary_ai.py` 中新增寻路策略
3. **跑 `--compare` 对比**：exit rate 提升 + 帧数下降 = 有效改进
4. **生成新的对抗性 pattern**：针对新算法的弱点构造更难场景
5. **验证通过后移植回 AS2**

## AS2 移植路径

碰撞层（`_root.collisionLayer`）是运行时绘制的画布，部分障碍物无顶点数据，
因此只能使用**基于 hitTest 点查询**的寻路算法（Grid BFS / A*），
不能使用需要几何顶点的算法（visibility graph）。

**现有技术储备**：`org.flashNight.neur.Navigation.AStarGrid`

已经有完善的 AS2 栅格 A* 实现（二叉堆、8方向、防穿角、searchId 复用），
集成步骤：

1. **场景加载时**：对 `collisionLayer` 按 cell_size 格栅做 `hitTest` 采样
   → `AStarGrid.setWalkableMatrix()`（可分帧执行）
2. **佣兵 `think()` 中**：L-path 失败时调用 `AStarGrid.find(sx, sy, gx, gy)`
   → 缓存 waypoint 列表到 `UnitAIData`
3. **佣兵 `walk()` 中**：逐 waypoint 移动，到达一个推进到下一个
4. **动态障碍**：`CollisionLayerChanged` 事件触发时，增量更新 `setWalkable()`

| Python 模块 | AS2 文件 |
|---|---|
| `collision.py` → `is_reachable()` | `Mover.as` → `isReachable()` |
| `collision.py` → `is_point_valid()` | `Mover.as` → `isPointValid()` |
| `collision.py` → `NavigationGrid` | `AStarGrid.as` |
| `mercenary_ai.py` → `MercenarySimulator` | `MecenaryBehavior.as` |
| `mercenary_ai.py` → `BFSMercenarySimulator` | `MecenaryBehavior.as`（改进版） |
| `mercenary_ai.py` → `AIConfig` | `MecenaryBehavior.as` 静态常量 |
| `map_model.py` → `load_real_maps()` | `scene_environment.xml` |

## 注意事项

- 墙壁厚度必须 > `isReachable` 步长（50px），否则采样会跳过薄墙
- 每次 tick = AS2 中 4 帧（action 间隔），`alive_frames` 按 ×4 累计
- 真实地图的门位置在 SWF 内，XML 中没有；模拟器在边界附近随机放门
- 碰撞检测用 shapely 多边形替代 Flash hitTest，精度一致
- Grid BFS 的 cell_size=20px 是一个平衡精度和性能的选择；更小更精确但更慢
