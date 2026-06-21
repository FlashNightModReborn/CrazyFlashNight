# 玩家信息界面 → C# NativeHud：只读镜像迁移 架构设计（阶段0 行为基线 + 停止线裁决）

**文档角色**：把 `flashswf/UI/玩家信息界面` 从「Flash MovieClip 承载显示 + 输入 + 冷却逻辑」迁移到「C# 启动器常驻只读 HUD + AS2 保留状态权威与隐形逻辑层」的**纲领设计 / ADR**。本轮只完成**阶段0：行为基线盘点 + 停止线对抗审计**，尚未开工编码。后续阶段在 §5 给出经阶段0结论修正的路线。

**最后核对代码基线**：commit `e1a78474f2`（2026-06-21，代码树）；本文 §2/§3 的全部断言来自 13-agent 代码级盘点 + 4 视角对抗审计 workflow（实际打开 `.as`/`.xml` 核对，非记忆/非 JSON 推断），证据均带 `file:line`。

**前置必读 / 关键定位修正**：
- 本迁移**不走 Web Panel snapshot+command 范式**（merc/pet/arena/kshop 那条），而走 **`FrameBroadcaster.pushUiState` 快车道 + GDI+ `INativeHudWidget` 只读镜像**。详见 §4。
- [agentsDoc/as2-web-panel-migration.md](../agentsDoc/as2-web-panel-migration.md) 只在**总线协议字段闭环、验证门槛、文档同步**这几节适用；其 panel 生命周期 / WebView2 / open-close 部分**不适用**于本 native HUD 迁移，勿误用。
- 跨栈稳定性硬约束（AS2 `.as` BOM、Flash CS6 编译表述边界、终端编码）一律以 [AGENTS.md](../AGENTS.md) 为准，本文不复制。
- 快车道前缀协议与 C# 处理成本基线见 [launcher/README.md](../launcher/README.md) 与 [docs/protocol-latency-baseline.md](protocol-latency-baseline.md)。

---

## 0. 状态

- 阶段：**阶段0 完成，停止线已触发**（详见 §3）。尚未进入任何 C# 复刻或 AS2 重构编码。
- **核心裁决（颠覆早期"纯展示层"判断）**：`玩家信息界面` SWF **不是只读 HUD**。它在 MovieClip 时间轴里承载了三条战斗输入主链（技能/战技/药剂的 `Key.isDown` 轮询触发释放）、**手动玩家唯一的冷却权威状态机**（`Symbol 1791.冷却` 布尔，引擎侧 `释放技能/释放主动战技` 完全不做冷却判定）、装备/被动技能回写、消耗品库存扣减。（注：早期审计把 `frameEnd` 性能心跳也列入本 SWF——**经核对为误报**，详见 §3 误报更正。）
- **直接后果**：不能把整个 symbol 一并搬走或停止实例化。迁移范围必须**沿"显示 vs 逻辑"切线重切**——只读显示层进 C#，输入/冷却逻辑层留在 AS2（或在 C# 化前先从 MC 时间轴**剥离重写**成 AS2 类）。最小可行形态是**双轨**：C# 画只读条 + AS2 保留隐形逻辑壳，而非"用纯 Object facade 顶替"。
- 已确认可安全只读迁移的显示层：HP / MP / 韧性 / 经验 / 等级 / 弹药数 / 攻击模式视图 / 角色名 / SP / buff 图标条（见 §2.1）。
- hover 注释明确为**第一阶段放弃项**（计划既定）。
- 排序原则：state-first（AS2 先重构、全功能壳作"贬值中的视觉 oracle"），含两条排序无关硬约束（缓动入 `cur/target` 契约、frameEnd 批量发布）。详见 §4，已记入 agent 记忆。

---

## 0.1 施工定位约定（耐重构）

对齐 [物品系统-双栏工作台-架构设计-2026-06-15.md](物品系统-双栏工作台-架构设计-2026-06-15.md) §0.1：本文不把行号/帧号当 canonical 施工入口。定位统一用**仓库根搜索锚点 + 路径提示**：

```bash
rg -n -F '<唯一符号/协议字面量/语义标记>' . -g '!docs/**'
```

行号只作一次性审阅快照（基线 commit `e1a78474f2`）。XFL/XML 优先用稳定 symbol/linkage/实例名定位（中文实例名是稳定锚）。下表为后续施工的核对锚点：

| 要核对的事实 | 稳定搜索锚点 | 当前路径提示 |
|---|---|---|
| 主实例帧脚本 bootstrap | `_root.UI系统.初始化玩家信息界面.call(this)` | flashswf/UI/玩家信息界面/LIBRARY/玩家信息界面.xml |
| 六个刷新函数 + onEnterFrame 缓动器 | `_root.UI系统.血条刷新显示 = function` | [UI交互_fs_玩家信息界面.as](../scripts/展现/UI交互/UI交互_fs_玩家信息界面.as) |
| 数据源 hero 解析 | `findHero` / `_root.gameworld[_root.控制目标]` | [TargetCacheManager.as](../scripts/类定义/org/flashNight/arki/component/TargetCacheManager.as) |
| 技能施放输入循环（停止线#1） | `释放技能` + `Key.isDown` | flashswf/UI/玩家信息界面/LIBRARY/sprite/技能控制器.xml |
| 战技施放输入循环 | `释放主动战技` + `_root.武器技能键` | flashswf/UI/玩家信息界面/LIBRARY/sprite/战技控制器.xml |
| 药剂使用 + 库存扣减 | `_root.使用药剂` + `addValue` | flashswf/UI/玩家信息界面/LIBRARY/sprite/药剂控制器.xml |
| 手动冷却权威状态机（停止线#2） | `冷却开始` + `总步数` | flashswf/UI/玩家信息界面/LIBRARY/sprite/Symbol 1791.xml |
| 引擎侧释放不判冷却（关键不变量） | `释放技能 = function` | [单位函数_fs_aka_玩家模板迁移.as](../scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as) |
| AI 走逻辑层时间制冷却（非 UI） | `上次使用时间` + `冷却*1000` | [SkillCandidateStrategy.as](../scripts/类定义/org/flashNight/arki/unit/UnitAI/combat/strategies/SkillCandidateStrategy.as) |
| 取消装备技能回写技能表/被动 | `取消装备技能` | flashswf/UI/玩家信息界面/LIBRARY/sprite/快捷技能界面.xml |
| frameEnd 心跳（**活跃源已在主 FLA**，非本 SWF） | `frameend事件发生器`（主 FLA 舞台 placed 实例，`lastModified=1775140070`） | CRAZYFLASHER7MercenaryEmpire/LIBRARY/frameend事件发生器/frameend事件发生器.xml + DOMDocument.xml:1666 |
| frameEnd 消费端（FPS 调度） | `eventBus.subscribe("frameEnd"` | [通信_fs_帧计时器.as](../scripts/通信/通信_fs_帧计时器.as) |
| 攻击模式视图状态机（帧标签） | `刷新(攻击模式)` + 帧标签集合 | flashswf/UI/玩家信息界面/LIBRARY/sprite/玩家必要信息界面.xml |
| 弹药显示写入（~60 散点） | `玩家必要信息界面.子弹数` / `[playerBulletField]` | flashswf/arts/things0/** + scripts/逻辑/装备函数/** |
| buff 图标条（主 FLA，非本 SWF） | `初始化玩家buff界面` / `DetailedIconBar` | [DetailedIconBar.as](../scripts/类定义/org/flashNight/arki/component/Buff/IconBar/DetailedIconBar.as) |
| 角色名直绑文本 | `variableName="_root.角色名"` | flashswf/UI/玩家信息界面/LIBRARY/UI重构/姓名动画.xml |
| facade 范本（参考，非可直接套用） | `MouseProxy` | [MouseProxy.as](../scripts/类定义/org/flashNight/arki/cursor/MouseProxy.as) |
| 升级瞬间强写经验条满帧 | `主角经验值显示界面.frame = 100` | [引擎_lsy_等级与经验值.as](../scripts/引擎/引擎_lsy_等级与经验值.as) |

---

## 1. 背景与迁移目标

### 1.1 迁移源形态

`_root.玩家信息界面` = 主 FLA（CRAZYFLASHER7MercenaryEmpire）舞台上 `linkageIdentifier=玩家信息界面` 的**单实例**（DOMDocument 常驻放置，脚本里无 `attachMovie`/`loadMovie` 创建它）。其 as 层 frame0 调 `_root.UI系统.初始化玩家信息界面.call(this)`，把六个刷新方法 + onEnterFrame 缓动挂到实例上。直接子实例：`主角hp显示界面 / 主角mp显示界面 / 主角韧性显示界面 / 主角经验值显示界面 / 快捷技能界面 / 快捷药剂界面 / 玩家必要信息界面 / 功能按钮界面 / 性能帧率显示器`。

`_root.玩家必要信息界面`（裸顶层别名）**全仓库无任何赋值点**（`rg '玩家必要信息界面\s*='` 0 命中）。权威路径恒为 `_root.玩家信息界面.玩家必要信息界面`；裸别名的 31 处调用绝大多数落在弃用/legacy 美术帧脚本（写入悬空对象 = 静默失效），仅 `dominator.xml` 武器疑似活跃，迁移前需真机确认（见 §6 风险 R5）。

### 1.2 迁移目标形态

```
旧 AS2 调用方
  → _root.玩家信息界面 / 玩家必要信息界面 facade（保留 MovieClip 语义的隐形逻辑壳）
      → PlayerInfoState（AS2 状态对象，cur/target 双量）
          → FrameBroadcaster.pushUiState（frameEnd 批量）
              → C# NativeHud PlayerInfoWidget（只读位图镜像）
      → AS2 隐形逻辑层（技能/战技/药剂输入循环 + 冷却状态机 + frameEnd 心跳，不进 C#）
```

C# 层只负责**常驻只读 HUD 显示**；AS2 端保留**游戏状态权威 + 输入/冷却逻辑 + 旧 API 兼容**。

---

## 2. 阶段0：行为基线盘点

### 2.1 显示层职责清单（可安全只读迁移）

全部为「引擎/全局 → HUD」单向推送，HUD 不反写游戏态。C# 端须 1:1 复刻下列**取整、格式、帧映射、缓动**语义。

| 子系统 | 数据源（权威） | 显示映射 / 公式 | 一致性要点（易错） | 建议发布字段 |
|---|---|---|---|---|
| HP 条 | `findHero().hp` / `.hp满血值` | 128 格逆向：`frame = max(1, 129 - floor(ratio*128))`；满血=1、空血=129 | `HP百分比.text = floor(ratio*100)` **无 % 后缀**；isNaN 早退 | `pi_hp` `pi_hpMax`（发原值，C# 自算帧） |
| MP 条 | `findHero().mp` / `.mp满血值` | 100 格逆向 `frame = max(1,101-floor(ratio*100))`；含 morph 形变遮罩（连续插值非纯离散） | `MP数据显示.text = NNNNN/NNNNN`（5 位补零）；`MP百分比.text` **带 % 后缀**（与 HP 不同！） | `pi_mp` `pi_mpMax` |
| 韧性 | `findHero().nonlinearMappingResilience` = `1 - sqrt(remainingImpactForce / 韧性上限)` | 30 格逆向 `frame = max(1,31-floor(poise*30))`；31 帧含多阶段破韧美术动画 | 写 `.poise` 变量绑定文本（非 `.text` 路径）；`+ "%"` | `pi_poise`（0..1 原值） |
| 经验条 | `_root.经验值` / `_root.升级需要经验值` / `_root.上次升级需要经验值` | `progress = floor((经验-上次)/(需要-上次)*100)` 裁 0-100；`gotoAndStop(100-progress)`，**不走缓动** | 除零防御 `denom<=0→1`；升级瞬间引擎硬写 `.frame=100` 做"涨满闪光" | `pi_exp` `pi_expNeed` `pi_expPrev` |
| 等级 | `_root.等级`（**非** `玩家等级` 字段名） | `padStart(等级,3,'0')`（如 5→`005`） | renderAsHTML=true；上限 等级限制=100/最大等级=60 | `pi_level` |
| 弹药 | 武器/技能容器帧脚本写 `子弹数 = capacity - shot` | `variableName` 绑定文本 + 透明组件每帧 `_parent.子弹数 → text` | 四字段 `子弹数/子弹数_2/弹夹数/弹夹数_2` 都须可写（~60 散点写入，见 §6 R1） | `pi_ammo` 系列 |
| 攻击模式 | 单位 `this.攻击模式`，经 `刷新攻击模式` 推送 | `gotoAndStop(帧标签)`：{手枪@1, 手枪2@6, 长枪@12, 兵器@17, 手雷@22, 空手@27, 双枪@32} | 未知标签 AS2 **静默不跳**（不回退空手，回退仅 load 时一次）→ C# 须明确边界（见 §2.4） | `pi_mode` |
| 角色名 | `_root.角色名`（存档第 0 项，对话 `$PC` 替换） | `variableName="_root.角色名"` 直绑，无格式化 | **早期被误判为纯装饰** | `pi_charName` |
| SP 技能点 | `_root.技能点数` | DynamicText 直绑 | 与 等级/经验/角色名 同属 `_root` 全局通道，应合并发布 | `pi_sp` |
| Buff 图标条 | `buffManager`（走事件总线，**不走中央刷新函数**） | `DetailedIconBar`：26 帧倒计时 `targetFrame=((25*remain/total)|0)+1`；28px 间距排布；对象池复用 | **整子系统早期漏盘**；装配在**主 FLA**（玩家buff界面素材），非独立 SWF | `pi_buffs[]`（id/比例） |
| 平滑缓动器 | onEnterFrame（HP/MP/韧性三条，**经验排除**） | 读 `clip._currentframe` 朝影子字段 `clip.frame` 逼近：**最大过渡 30 帧 / 最小步长 1 / 每帧最多移动剩余距离 20%** | 纯视觉；C# 不复刻则双轨对比恒红 | （C# 端自跑 Lerp） |

### 2.2 隐藏游戏逻辑清单（停止线 —— 不可只读迁移）

下列职责活在 UI MovieClip 时间轴里，**不是显示**。整体搬走或停止实例化会造成功能回归。

| # | 隐藏逻辑 | 证据位置 | 后果（若随 HUD 移除而不补偿） | 处置 |
|---|---|---|---|---|
| 1 | **技能/战技/药剂施放输入循环**：透明控件 enterFrame 每帧 `Key.isDown(扳机键)`（门控 `!暂停 && 当前玩家总数==1 && 已装备名!="" && 进度条.冷却`），命中跳"已扣扳机"帧调 `释放技能/释放主动战技/使用药剂` | 技能控制器.xml:19-37,76-122；战技控制器.xml:27-33,75-108；药剂控制器.xml:29-57,100-127 | 手动玩家**完全无法施放**技能/战技/药剂 | 留 AS2 或先剥离成类 |
| 2 | **手动玩家唯一冷却权威**：`Symbol 1791.冷却` 布尔 + `冷却开始(CD)` → `总步数=ceil(CD/33.333)` + `帧计时器.添加冷却任务` 逐格推进。引擎 `释放技能/释放主动战技/使用药剂` **完全不判冷却** | Symbol 1791.xml:11-48；玩家模板迁移.as:1710-1759 | **技能无冷却连发**（冷却 gate 丢失） | 留 AS2 或 facade 自建冷却状态机 |
| ~~3~~ | ~~frameEnd 性能心跳~~ → **误报更正：已不在本 SWF**。活跃心跳是主 FLA 舞台上独立的 `frameend事件发生器` symbol；玩家信息界面 库内 `性能帧率显示器` 仅为空层 leftover（玩家信息界面.xml:15-21 `<elements/>`，全 SWF 零放置）。见 §3 误报更正 | 玩家信息界面.xml:15-21（空层）；主 FLA DOMDocument.xml:1666（活跃 placed） | **无**（已解耦） | 无需处理 |
| 4 | **取消装备技能** 写回游戏态：改 `主角技能表[i][2]/[4]=false`、清 `快捷技能栏N`、`更新主角被动技能()` + 写 `gameworld[控制目标].被动技能` | 快捷技能界面.xml:29-44 | 装备/被动技能管理逻辑丢失 | 留 AS2 或剥离成命令 |
| 5 | **药剂控制器库存扣减**：`icon.collection.addValue(icon.index,-1)`，耗尽 `_root[控制参数]=""` 解除装备 | 药剂控制器.xml:29-57 | 消耗品不扣减 / 快捷栏不清空 | 随 #1 一起处置 |
| 6 | **快捷药剂 hitTest 拖放落点**：`快捷药剂界面.hitTest(_xmouse,_ymouse,true)` 判断药剂拖入；`attachMovie` 图标容器 | InventoryIcon.as:152；快捷药剂界面.xml:12-13 | 拖放装药失效 | 留 AS2 真 MC，或 DOM 矩形命中替代 |
| 7 | **显示列表引擎 by-reference 驱动装饰孙级动画**：`默认播放动画(玩家信息界面.主角hp显示界面.血槽内动画 / .网格动画 / 快捷药剂界面.姓名框.网格动画)` 按性能等级 play | 显示列表引擎.as:73-77 | 装饰动画全停 / 路径解析 undefined | 装饰可砍（纯外观），路径需重设计 |

> **关键不变量（load-bearing，写进注释勿丢）**：引擎侧释放函数信任 UI 门控——`释放技能/释放主动战技/使用药剂` 只判 hp/mp 可负担与释放条件、扣 mp（战技另扣 hp），**整条手动路径的冷却门控唯一存在于 `Symbol 1791.冷却`**。**范围限定**：此 gate 只管"手动人类玩家"（所有透明控件带 `当前玩家总数==1` 守卫）；AI（ActionArbiter/各 strategy）与佣兵 ai 走逻辑层独立时间制冷却 `nowMs - 上次使用时间 <= 冷却*1000`（单位秒），**不读 UI**。故 facade 只需为手动玩家这一条路径补偿冷却状态机（12 技能栏 + 4-5 药剂栏 + 1 战技栏的 `冷却` 布尔与倒计时）。

### 2.3 旧入口清单（全调用点普查）

**总计 161 处**（主路径 `_root.玩家信息界面.*` 130 + 裸别名 `_root.玩家必要信息界面.*` 31）；剔除 1 处 `.md`、1 处 JSDoc、2 处注释掉的刷新后，**真实可执行 ≈ 157**。

| 类别 | 计数 | 访问模式 | 分布要点 |
|---|---|---|---|
| 弹药（子弹数/弹夹数显示） | **60** | 写字段 | **散落在 SWF 美术帧脚本**（things0/技能容器/动画层 + 装备函数）→ 无法用 AS2 类 setter 拦截（见 §6 R1） |
| 战技（图标刷新/攻击模式） | 18 | 方法 + gotoAndStop | 装备函数 ×6 + 玩家模板迁移 + DressupInitializer + 怪物/翅膀帧脚本 |
| 战斗（HP/MP/韧性刷新） | 13 | 方法调用 | 等级经验/场景转换/HitUpdater/ImpactUpdater/Respawn + 两个控制器 |
| 经验等级 | 10 | 方法 + 写 `.frame=100` | 等级经验/作弊码/场景转换/防御性兜底 |
| 物品药剂（寻址/hitTest） | 10 | 读 + hitTest/gotoAndPlay | 物品栏UI/显示列表引擎/InventoryIcon/Heal/Regen + 3 处 unused |
| 技能（快捷技能栏刷新/冷却） | 8 | 读写 `冷却时间/消耗mp/数量` + 方法 | 技能系统/作弊码/技能图标 |
| 视觉引擎（装饰动画注册） | 5 | 读子 MC 路径 | 显示列表引擎 |
| 作弊调试（无限火力） | 2 | 读写冷却时间夹紧 | 作弊码 |

**写语义关键点**：弹药四字段写点（~60）在美术帧脚本里靠 `variableName` 绑定文本生效——facade 化后**必须以 `addProperty`/动态字段兜底**，否则弹药显示静默失效（无法靠类 setter 拦截，因写点不在 `scripts/`）。

### 2.4 一致性验收表（迁移后必须一致）

C# 镜像与 AS2 原壳**双轨同屏对比**时逐项核验（计划阶段6）：

| 场景 | 验收判据 | 阶段0 已锁定的易错细节 |
|---|---|---|
| 受伤 / 回血 | HP 条平滑过渡到目标、文本/百分比同步 | 缓动公式（30/1/20%）；HP 百分比无 % |
| 耗蓝 / 回蓝 | MP 条 + `NNNNN/NNNNN` 5 位补零 | MP 百分比带 %（与 HP 相反） |
| 韧性变化 | 破韧/恢复，sqrt 非线性 | `.poise` 变量绑定；多阶段动画可降级为比例 |
| 升级 / 经验变化 | 经验条无缓动直跳；升级瞬间"涨满闪光"再回落 | `.frame=100` 强写语义须保留 |
| 攻击模式切换 | 视图切到对应模式 | **未知模式：AS2 静默保持上一帧** → C# 须对齐（保持 vs 回退空手，需拍板） |
| 弹药变化 | 子弹数/弹夹数实时 | 四字段全可写；双枪用 `_2` 后缀 |
| 技能 / 战技 / 药剂冷却 | 冷却条逐格 + gate 生效 | **属逻辑层（§2.2#2），不是只读镜像** |
| 药剂消耗 | 库存 -1、耗尽清栏 | **属逻辑层（§2.2#5）** |
| 暂停 / 场景切换 / 面板开关 | HUD 不错乱、控制目标锚一致 | HUD 以 `_root.控制目标` 为单一锚 |
| **切人物（控制目标变化）** | HP/MP/韧性 随 `findHero` 自动跟随；**buff 栏/攻击模式需显式重绑** | 现 standalone 实为单控制目标（固定"玩家0"），但 buff 栏 `initialize` 按 `控制目标` 一次性门控，不随 findHero 动态跟随（恢复切人物时要补重绑） |
| 角色名 / SP | 顶部显示玩家名、SP 数 | `_root` 全局通道，与等级/经验合并发布 |
| Buff 图标条 | 图标动态增删、26 帧倒计时、28px 排布 | 走 buffManager 事件总线 |

---

## 3. 停止线裁决与范围重切

**裁决：停止线触发。** 四个对抗审计视角（战斗态突变 / 技能门控 / 场景存档 / facade 破坏）**独立收敛到同一结论**：`玩家信息界面` symbol 混入了纯显示之外的 load-bearing 游戏逻辑（§2.2），**不能直接 1:1 复刻成"常驻只读 HUD"，也不能在阶段8直接停止实例化整个 symbol，更不能在阶段7用纯 Object facade 顶替**。

但"停止线触发"**不等于放弃**——它的意义是**强制沿"显示 vs 逻辑"切线重切范围**：

- **进 C#（只读显示层）**：§2.1 全部——HP/MP/韧性/经验/等级/弹药/攻击模式视图/角色名/SP/buff 显示 + 缓动。
- **留 AS2（隐形逻辑层）**：§2.2 全部——技能/战技/药剂输入循环、手动冷却状态机、取消装备技能、库存扣减、拖放 hitTest。
- **最终形态 = 双轨**：C# 画只读条（可见层）；AS2 保留一个**不可见的逻辑壳**（继续承载输入/冷却）。计划原阶段8"不再实例化重的 symbol"必须改写为"**隐藏可见图层、保活隐形逻辑壳**"。

**这正是阶段0的价值**：它在写一行 C# 之前就拦下了会造成严重回归的陷阱——技能无冷却连发 / 技能完全无法施放（冷却权威丢失）/ 键盘施放链路被切断。

### 3.1 误报更正：frameEnd 性能心跳已不在本 SWF（2026-06-21，人类指认 + 核对）

早期 census 的"完整性批判"把 `frameEnd` 心跳列为本 SWF 的 load-bearing 停止线项，**这是误报**。批判 agent 读到的是 `玩家信息界面/LIBRARY/性能-帧率显示器/性能帧率显示器.xml` 这个**库符号定义**（含 `publish("frameEnd")`），未核实它是否被实例化。实测：

- 玩家信息界面 symbol 的 `性能帧率显示器` 图层 frame0 是 `<elements/>`（**空层，无实例**，玩家信息界面.xml:15-21）；全 SWF `rg 'libraryItemName="性能-帧率显示器/性能帧率显示器"'` **0 命中**——库符号是死重，未加载。
- 活跃 frameEnd 源已迁移为主 FLA 的独立 symbol `frameend事件发生器`（CRAZYFLASHER7MercenaryEmpire/LIBRARY/frameend事件发生器/frameend事件发生器.xml，`lastModified=1775140070`），**placed 在主舞台时间轴**（DOMDocument.xml:1666，图层 @1662，duration 211）→ 它才是运行时心跳。

**结论**：frameEnd 与玩家信息界面 SWF 已解耦。停止线裁决不依赖它（其余 §2.2 项仍触发停止线）；下文 §4 C4、§5 阶段0.5、§6 R3 相应作废。**教训**：XFL 里"库存在符号定义"≠"运行时被实例化"，停止线判定必须核实 placement（`<elements/>` 空层 = 未加载）。

### 3.2 反常现象根因：技能图标为何在 asLoader 重构故障时仍加载（阶段1 误导规避）

**现象**：2026-06-17 asLoader P5 单帧塌缩首测出问题、"大部分游戏功能瘫痪"时，快捷技能栏的技能图标**依旧正常显示**。这条反常路径的根因必须查清，否则阶段1 会被它误导。经 4-agent 调查 + 对抗验证（verdict=**partial**，原假设机制被部分证伪）：

- **真正的健壮机制（不是帧标签！）**：`技能图标` symbol **只有两个帧标签** `空@0` / `默认图标@4`（技能图标.xml:7,10）——**没有 per-skill 技能名帧标签**。真技能恒走 `gotoAndStop("默认图标")` + **`图标壳.attachMovie("图标-"+技能名)`**（技能图标.xml:139-149），符号取自 art 库 `素材库-物品技能图标`（每个 `图标-XXX` 带 `linkageExportForAS=true`，placed 进主 FLA → 主 SWF 字符字典）。整条"出图载体"= **放置实例 onClipEvent(load) + 原生库 attachMovie**，是 SWF 原生时间轴/原生库自驱，**完全不过 BootSequencer 的 staged 函数/chunk 调度这道门**——这才是它幸存的结构性原因。
- **boot 阶段分层（幸存 vs 瘫痪同源）**：那次瘫痪根因是 `s7_syncLogic` 调 base `f36/f37/f41` 但这三帧是被切的 chunk 帧、只有 `fN_1..fN_k` 无 base `fN` → 调用 no-op → 单位函数(f36)/装备(f37)/UI(f41) 三大帧从不执行（asLoader-BootSequencer-构建标准-2026-06-16.md:23）。**而技能图标读的数据落在 boot 最稳的环节**：`_root.主角技能表` 由 SaveManager（编进 asLoader.swf 的类，S2 读盘恢复）+ 引擎_lsy_技能系统.as（`f2`/`S1_SYNC_CODE` 最早同步批）populate，`已装备名=_root.快捷技能栏N` 同由 SaveManager 读档——**这些恰好都不在塌掉的 s7 里**。
- **"图标能加载"的精确含义**：挂的是**真技能图标 + 真等级/数量**（非空槽、非默认占位）。**唯独退化**的是 CD/MP（来自 `_root.技能表对象`，由 SkillDataLoader `f58 ∈ s7` populate → undefined）以及 技能释放（`f36`）/ 键位显示（`f41`）/ 冷却条——**这些与瘫痪功能同源同脆，一起坏了**。

> **⚠️ 阶段1 最关键的误导规避**：**"图标能加载" ≠ "技能子系统健壮"**。健壮的只是【显示载体】（放置实例化 + `attachMovie("图标-"+名)` + 空槽分支 + 从 主角技能表 回填等级/数量），且其数据依赖恰在 boot 最稳环节；【数据增强与交互】（CD/MP、释放技能、键位、冷却条）全在 `s7_syncLogic`，与当年瘫痪功能同源、**同样是 asLoader 硬执行依赖**。阶段1 评估这些子能力时必须按 asLoader 依赖项对待，不可因图标幸存而推断它们也健壮。

派生的阶段1 戒律（并入 §6 R8）：① 不要把图标出图载体（onClipEvent + 原生 attachMovie linkage）改成跑 `_root.UI系统`/staged 函数才出图——那会把一条健壮链变脆；facade 化须等价复刻 attachMovie 出图 + 空槽分支 + 等级回填。② "换技能图"靠 linkage ID（art 库 `图标-XXX`），**不靠帧标签**——别去动 技能图标 时间轴帧找 per-skill 标签。③ `快捷技能栏N`/`主角技能表` 由 **SaveManager**（读盘槽位 `装备储存数据[16..27]` / `mydata[5]`）populate，不是 staged 帧函数/`_root.UI系统`——改 HUD/存档形状须同步核对 SaveManager。④ HUD 是主 Scene1 frame index130 的放置实例，仅在 asLoader 握手 + 读档进基地后实例化——"图标健壮"隐含前置 = boot 已推进到 base 帧。

### 3.3 快捷药剂第 5 格：结构/实例齐全但无数据接入（迁移注意）

人类指认 + 核对：HUD 快捷药剂区**视觉 5 格，实际仅 4 格接入逻辑**，第 5 格用途未定、是保留位。但真相比"4 实例 + 1 占位图"更微妙、更易误判——

- **结构层 placed 了完整 5 套实例**：控制器0-4 / 进度条0-4 / 位置示意0-4 / 快捷道具格子×5（快捷药剂界面.xml）。`控制器4` 的 onClipEvent **已完整参数化**（`扳机键="快捷物品栏键5"` / `控制参数="快捷物品栏4"` / `控制参数2="进度条4"`，快捷药剂界面.xml:155-159）——它**不是背景图，是一个会跑 enterFrame 的真 `药剂控制器` 实例**。
- **数据层硬上限 4**：`初始化药剂栏图标`（物品栏UI.as:341）**硬截 4**——`if(快捷药剂界面.药剂图标列表.length == 4) return`（:343），只为槽 0-3 绑 `new DrugIcon(..., _root.物品栏.药剂栏, i, ...)`（:367，`DrugInventory` 容量 4）。故 `控制器4` 永远拿不到 `.药剂栏` 图标、`_root.快捷物品栏4`/`快捷物品栏键5` 永不 populate → `控制器4` 轮询恒 no-op。
- **净效果**：第 5 格 = **视觉在、控制器在、数据不在**的保留位，等未来功能定调再接。

**迁移注意（本质 = 视觉/实例数 ≠ 功能数）**：
- C# HUD **功能槽数以数据层为准（4），不要按视觉/实例数（5）推断**——否则会误布 5 个功能槽，超出 `DrugInventory` 容量 4。
- 第 5 格是否在 C# 渲染为可见空位是产品决策（保留占位 vs 暂隐）；**无论如何不要给它接逻辑**（用途未讨论）。
- PlayerInfoState 发 4 个药剂槽数据；第 5 格若要可见，作纯占位字段（无 drug 绑定），注释标"保留位，用途未定"。

> **本轮第三次"存在 ≠ 生效"**（前两次：§3.1 frameEnd 空层、§3.2 技能图标幸存≠健壮）。共同教训：本 SWF 大量 symbol/实例/脚本"摆着但不生效"，**迁移的功能真相必须读数据/逻辑层（容量 / `length==N return` cap / boot 阶段），不能按视觉、库符号、实例数推断**。

---

## 4. 排序原则（state-first）与硬约束

**结论：AS2 facade/state 重构前置于 C# 镜像**（计划原阶段 1→2→7 在前，3→6 在后，8→9 收尾）。理由：

1. **全功能 AS2 壳是会贬值的视觉 oracle**：现在 1:1 渲染所有行为，重构出回归人眼/Output panel 立刻抓到，**无需 C# 镜像先存在**。越往后壳越被掏空，oracle 越弱——故趁壳最完整时改 AS2。
2. **此刻改动栈最浅**：回滚 = `git checkout`、下游零依赖，回滚成本最低。
3. **state-first 省返工**：阶段2 先立 `PlayerInfoState`，legacy renderer + 阶段3 `pushUiState` 从**同一 state 对象**发 = 单一发布点；mirror-first 会先把 `pushUiState` 焊到 6+ 个未重构刷新函数再迁回 state setter（一次性发布器造了又拆）。

**两条排序无关的硬约束（无论先后都钉进计划）**：

- **C1 — `PlayerInfoState` 显式分 `cur`/`target`**：把 onEnterFrame 缓动（30/1/20%，§2.1 末行）纳入 renderer 契约。只发终值的话 C# 无从复刻 Lerp，阶段6 对比恒红。经验条特例：不缓动（直跳 + 升级闪满）。
- **C2 — 阶段3 发布钉死 `frameEnd` 批量推送**，勿逐字段挂 watch：C# 侧处理仅 1.25μs/帧、带宽零压力；瓶颈只可能在 AS2/AVM1 侧（20+ watch 压调用栈）。state 对象当帧聚合脏字段、frameEnd 一次性 flush，天然批量。

**经阶段0 修正的两条额外约束**：

- **C3 — 阶段1 不只是"时间轴脚本外置"，必须同时把 §2.2 的输入/冷却逻辑从 MC 时间轴剥离成 AS2 类**。范本：`PlayerTemplateUnitFixture` 已把"刷新攻击模式"经 `dpsInvalidator` 钩子解耦——证明"先把游戏逻辑从 MC 抽到类/钩子，facade 才成立"。不先剥离就做阶段7/8 必炸。
- **C4 —（作废，误报）frameEnd 心跳迁出**：经核对 frameEnd 心跳已是主 FLA 舞台上独立的 `frameend事件发生器` symbol，玩家信息界面 库内为空层 leftover（见 §3.1）。**无需迁出动作**。

### 4.1 为后续治理留空间：键位显示脱钩（设计钩子，本轮不修）

已知长期脆弱点：玩家改键后，技能槽 HUD 显示的键 与 实际触发键 常不同步。经 4-agent 追踪定性——**这是单源投影失效（缓存陈旧），不是双存储分裂**，故新架构能结构性消除它，无需当下专门修 bug，只需把取数语义钉对。

- **键位唯一权威 = `_root.键值设定`**（35 项 `[显示名, 键名, 键码]`，UI交互_fs_按键设定.as:15-51）；`KeyManager.refreshKeySettings` 从它同步派生 `_root[键名]` 全局 + `keySettingsCache`。
- **脱钩发生地 = 技能控制器（快捷技能栏×12）**：帧0 把键码**一次性快照**进实例字段 `扳机键值`（技能控制器.xml:19），按下判定/显示/释放都用快照，唯独松开读 live `_root[扳机键]`。改键刷新链（系统UI.xml:22-33）只重灌 live 投影、**漏刷该快照** → 旧键滞留。战技/药剂控制器全读 live，**不脱钩**。
- **第二条更隐蔽的脱钩源**：`SaveManager.as:1386` 读档 `_root.键值设定 = 主角储存数据[10]` 后**不调** `刷新键值设定()`（全仓仅 2 处调用：启动 + 改键 UI）→ 自定义键档载入后 live 投影整体陈旧，**行为与显示双双停旧值**（这条连行为都错，非仅显示）。

**新架构是天然解药（state→projection 模型）**。设计钩子（现在就留，让后续治理变便宜，本轮不必修完）：

| 钩子 | 要点 | 不留的代价 |
|---|---|---|
| H1 | **PlayerInfoState 持「键名」而非算好的字母**（C# 每次重画时映射码→字母） | 只发字母 = 在 C# 侧复刻帧0快照失效模式，根因未动 |
| H2 | **改键刷新链末端加一步「标脏 PlayerInfoState 键位字段」**，经 pushUiState（frameEnd 批量, C2）全槽重发 | 退回"槽 MC 帧0 一次性"老问题，后续要新接发布触发路径 |
| H3 | **读档路径（SaveManager:1386）补一次 `刷新键值设定()` 并纳入键位字段发布触发集** | 自定义键档玩家读档进图行为就错，且易误归因为 HUD 迁移回归 |
| H4 | **把不变量写进 PlayerInfoState/协议注释**：「显示读 = 行为读 = 同一 SOT 派生的 live 值」（load-bearing，对齐外部结论自包含落注释纪律） | 后续有人再缓存键码，脱钩以新形态复发且无注释可对照判错 |

**本轮明确不做（留后续治理）**：① 技能控制器行为侧快照（按下 `Key.isDown(扳机键值)` 改读 live）——涉改 SWF 时间轴 + 重编译 + 真机逐键验证；② 移动键侧潜在第二脱钩（`_root.按键设定表` 仅 12 项 vs `_root.键值设定` 35 项）；③ 木偶版 vs 主角函数版 `获取键值` 语义不一致。这些与本迁移正交，单独治。

> **⚠️ 治理顺序风险**：若**只治显示侧**（PlayerInfoState 发 live 键）而**不同批治行为侧快照**，会出现"HUD 显示新键、技能却按旧键"——比现状（HUD 与按下都用旧键、玩家槽内看不出）**更刺眼**。故显示侧与行为侧治理需**同批，或显式记账先后**，避免治一半反而暴露。

### 4.2 跨主线依赖：装备/卸载交互 ↔ 双栏工作台（主线B）

玩家当前给药剂/技能"装备"= 从技能/背包界面把图标**拖到 HUD 槽**，"卸载"= 点槽上的叉（技能）/ 冷却态点槽（药剂）。HUD 槽既是【显示目标】（本主线A）又是【拖放落点 + 卸载控件】（本质属物品/技能管理域 = 主线B [物品系统-双栏工作台-架构设计-2026-06-15.md](物品系统-双栏工作台-架构设计-2026-06-15.md)）。**回答"是否必须先完成双栏才能干净迁 HUD"：否，但有一条精确的末端依赖。**

事实（角度1/2 核实）：装/卸的**落点/控件物理上就是 HUD 槽 MC**（药剂=`快捷药剂界面.hitTest`+`药剂图标列表[i].area.hitTest` InventoryIcon.as:152/156；技能=`快捷技能界面.hitTest`+`快捷技能栏i.hitTest` 技能图标.xml:325/331；技能卸载=12 个叉 button `on(release) 取消装备技能(N)` 快捷技能界面.xml:308-467；药剂卸载无叉=`DrugIcon.Press` 冷却态 + 耗尽自动卸）。**但这是实现耦合非本质耦合**——所有写权威（`物品栏.药剂栏`/`快捷技能栏N`/`主角技能表`/`主角被动技能`/`gameworld[控制目标].被动技能`）全在 HUD MC 之外、由 SaveManager 落盘；HUD MC 只是落点+显示+触发重绘。

依赖分层：

| HUD 阶段 | 对主线B 的依赖 |
|---|---|
| 1-6 只读镜像 + 双轨 | **零依赖，并行**。双轨保留 AS2 隐形逻辑壳（hitTest 落点 + 叉），装/卸照旧 |
| 7-8 facade / 隐藏可见层 | **不阻塞，但有硬约束**：隐藏 = `_visible=0` on **真 MC**，**绝不可** facade→Object / 停 placement（否则 hitTest + 叉 on(release) 全失效，见 R4）；且 AS2 隐形 hitTest MC 必须与 C# 可见槽**坐标对齐**，拖放才落对槽 |
| 9 彻底删壳 / 移除 §2.2#6 停止线 | **软依赖 B 的 SkillView/EquipView（Step6）**：装/卸搬进 panel 后 HUD 槽退化纯显示，才能删 AS2 壳 + 移 #6 |

**结论与建议**：A、B 并行；A 的**彻底退场**（删壳）软依赖 B 的"装备到快捷栏"切片。双栏 §8 把技能栏排在 Step6 末（KShop/仓库/NPC商店/装备栏 之后），A 若等整条 B 链会被拖住 → **建议在 B 里前置一个最小"装备药剂/技能到快捷栏"切片**作为两线收敛点，而非等 B 全做完。**概念上：equip/unequip 不属于 HUD 显示，是物品/技能管理动作借 HUD 当落点——应随主线B 迁移，不应阻塞主线A 的显示迁移。**

**留给 B 接手时补的接口缺口（记此备查，不在本主线修）**：① 双栏 §4.3 容器表注册 `快捷技能栏N`/`快捷物品栏N` 为可寻址 owned 容器（equip 目标）；② §4.1 `equip/unequip` 补 payload schema + "装到几号槽"槽寻址；③ 药剂 unequip 补冷却门控 + 耗尽清栏语义（无叉）；④ equip/unequip 活体副作用（`gameworld[控制目标].被动技能` + `获取键值()`）必须留 AS2 重裁决，Web/C# 不可漏；⑤ `技能图标` 多份同源 symbol 且 equip 写逻辑已分叉，**运行态激活份与我此前的假设相反**（详见双栏 doc §4.4）：`attachMovie("技能图标")` 按 linkage 取符号，而**带 linkage 导出的是 `arts/things` 旧结构版（仅 1-6 槽、死路径 `_root.快捷技能界面`、字符串 `[2]="true"`、第6格 `="ture"` 笔误、无被动 `[4]`）**；12 槽新结构（被动联动、`玩家信息界面.快捷技能界面` 路径）在**无 linkage 的 UI 副本**里、以及**主 FLA 本体（也带 linkage → 与 things 构成静默覆盖竞态）**。现行引擎按新结构写就，但谁覆盖谁无法静态判 → **迁移前须真机/反编译确认运行态实际跑哪份（装第 7-12 格 + 被动技能看是否生效）**；迁移语义一律以新结构为蓝本，绝不照抄 things 旧 1-6 版。

---

## 5. 经修正的迁移路线（相对原9阶段计划的差异）

| 阶段 | 原计划 | 阶段0 后修正 |
|---|---|---|
| 0 | 行为基线盘点 | ✅ 本文完成；停止线触发 |
| ~~0.5~~ | — | **作废（误报）**：frameEnd 心跳已迁出主 FLA（见 §3.1），无需新增阶段 |
| 1 | AS2 外部脚本化（仅 bootstrap） | **扩展**：同时剥离 §2.2 输入/冷却逻辑成 AS2 类（C3） |
| 2 | 建立 PlayerInfoState | 不变；显式 `cur/target`（C1）；先收 HP/MP/exp/mode/ammo，技能/药剂/战技后置 |
| 3 | UiData 发布 | 不变；frameEnd 批量（C2）；新增 `pi_charName/pi_sp/pi_buffs` |
| 4 | 资源管线 | 不变；静态图标复用 `launcher/web/icons`；装饰动画（血槽网格/光效）可砍 |
| 5 | C# PlayerInfoWidget 只读 | 不变；照抄 ComboWidget；复刻缓动 Lerp |
| 6 | 双轨对比 | 不变；按 §2.4 验收表 |
| 7 | facade 化 | **前提**：§2.2 逻辑已剥离（C3）；facade 仅承显示层 + 保留 §6 列出的 MC 能力 |
| 8 | 隐藏 AS2 可见 UI | **改写**：隐藏可见图层、**保活隐形逻辑壳**（不能停止实例化整个 symbol） |
| 9 | 清理旧依赖 | 不变；长期收敛 161 调用点 |

---

## 6. 风险登记

| ID | 风险 | 等级 | 缓解 |
|---|---|---|---|
| R1 | **弹药 ~60 写点在 SWF 美术帧脚本**（variableName 绑定），无法类 setter 拦截 | 高 | facade 用 `addProperty`/动态字段兜底；阶段6 专项核验弹药显示不静默失效 |
| R2 | **手动冷却权威唯一在 UI**（§2.2#2），剥离/复刻错位 = 无冷却连发或无法施放 | 高 | C3 先剥离成 AS2 冷却状态机类；保留 `当前玩家总数==1` 守卫；AI 路径不受影响 |
| ~~R3~~ | ~~frameEnd 心跳随 HUD 砍 = FPS 调度断源~~ → **已解除（误报）**：心跳是主 FLA 独立 symbol，本 SWF 为空层 leftover（见 §3.1） | — | 无需处理 |
| R4 | **阶段7 facade 破坏面**：onEnterFrame/`_currentframe`/gotoAndStop 帧标签/命名 TextField/variableName 绑定/深层子 MC 路径/attachMovie/hitTest/`_visible` 九类 MC 能力 | 高 | facade 最小必须保留这九类能力（见盘点 facade 视角清单）；或先剥离逻辑后 facade 仅承显示 |
| R5 | **裸别名 `_root.玩家必要信息界面`**：dominator 武器/暴走怪攻击模式帧脚本可能依赖 | 中 | 真机确认是否已失效；活跃则重定向到 `_root.玩家信息界面.玩家必要信息界面` |
| R6 | **buff 栏在主 FLA 非独立 SWF**，且按 `控制目标` 一次性绑定 | 中 | 迁移一并规划；C# 监听 `_root.控制目标` 变化作统一刷新锚 |
| R7 | 攻击模式未知标签 AS2 静默不跳，C# 行为需对齐 | 低 | §2.4 拍板：保持上一帧 vs 回退空手 |
| R8 | **误把"技能图标 asLoader 故障幸存"当成"技能子系统健壮"**（§3.2）：健壮的只是 SWF 原生出图载体 + 稳态 boot 数据；CD/MP/释放/键位/冷却同在 s7、同样脆 | 中 | 阶段1 区分【显示载体（原生 attachMovie linkage，勿改走 staged 函数）】vs【数据/交互（按 asLoader 依赖对待）】；换图靠 linkage ID 非帧标签；populate 源是 SaveManager |
| R9 | **键位显示脱钩治理顺序**（§4.1）：只治显示侧（发 live 键）不同批治行为侧快照 → "HUD 显示新键、技能按旧键"比现状更刺眼；又：PlayerInfoState 若发"算好的字母"而非键名 = 把帧0快照失效搬进 C# | 中 | 留 H1-H4 设计钩子（发键名/改键标脏/读档纳入触发集/注释钉不变量）；显示侧与行为侧治理同批或显式记账先后 |
| R10 | **快捷药剂第 5 格结构齐全但无数据**（§3.3）：按视觉/实例数（5）推断功能槽 → 误布 5 槽超 `DrugInventory` 容量 4；控制器4 是真实例易被当成已接逻辑 | 中 | 功能槽数以数据层（`初始化药剂栏图标` cap 4 / `DrugInventory` 容量 4）为准；第 5 格作保留占位，勿接逻辑 |
| R11 | **装备/卸载交互末端跨主线依赖**（§4.2）：A 彻底删壳软依赖 B（双栏）的"装备到快捷栏"切片；阶段8 隐藏若用 facade→Object/停 placement 而非 `_visible=0` 真 MC → hitTest+叉失效 | 中 | A/B 并行；删壳留到 B SkillView/EquipView 接管后；隐藏用 `_visible=0`+坐标对齐；建议 B 前置 equip 切片做收敛点 |

---

## 7. 四支柱地面真相与难度分层

| 支柱 | 成熟度 | 结论 |
|---|---|---|
| C# NativeHud | ★★★★★ 生产就绪 | `INativeHudWidget`/`IUiDataConsumer` + 5 widget + GDI+ layered window + 点击穿透全 ready，新 widget ~90% 复用 ComboWidget 范式 |
| UiData 通道 | ★★★★☆ | `FrameBroadcaster.pushUiState` 在跑，加 20-30 字段协议零破坏、C# 处理 1.25μs/帧 |
| 资源管线 | ★★★★☆ | FFDec CLI 内置；静态图标 100% 复用 `launcher/web/icons`；多帧/矢量/动态文字需 C# 新建 |
| AS2 玩家信息界面 | ★★☆☆☆ | **非纯展示层**：显示层薄而清晰，但混入输入/冷却/心跳逻辑 + 161 调用点 + onEnterFrame 缓动 |

**难度分层**：
- **只读 C# 显示镜像（阶段3-6 核心）**：中等偏低、低风险（基础设施成熟）。
- **完整迁移（含逻辑剥离 + facade + 退场）**：**中等偏高**，风险集中在 C3（逻辑剥离）、R1（弹药散点）、R2（冷却权威）。
- **建议**：先做一个最小纵切（HP/MP 显示双轨对比），验证镜像保真与 state-first 链路，再决定是否投入逻辑剥离。

---

## 8. 关联文档与文档治理

- [agentsDoc/as2-web-panel-migration.md](../agentsDoc/as2-web-panel-migration.md)：迁移护栏（仅协议/验证/文档同步节适用）
- [launcher/README.md](../launcher/README.md)：快车道前缀协议 SOT
- [docs/protocol-latency-baseline.md](protocol-latency-baseline.md)：通道延迟基线
- [物品系统-双栏工作台-架构设计-2026-06-15.md](物品系统-双栏工作台-架构设计-2026-06-15.md)：同期 AS2 UI 外迁主线（doc 风格范本）
- [agentsDoc/documentation-governance.md](../agentsDoc/documentation-governance.md)：文档治理

**文档治理**：本文为新 canonical 设计 doc，已运行 `node tools/validate-doc-governance.js`（ok）。**本文为时效性的阶段0 探索成果，暂不钉入 AGENTS.md 核心加载层**——触达靠 docs/ 可搜 + agent 记忆索引 + 既有「AS2 UI → Web Panel 迁移」包的「按需补…对应文档」catch-all（参照物品系统双栏工作台 ADR 同样未单独钉路由的先例）。**待本迁移转为持久工作流（开工编码）再钉 AGENTS.md 路由**。后续进入编码阶段时，按改动面更新本文 §5 路线与 §6 风险，行号锚点随重构刷新。

---

## 附：阶段0 方法学

本盘点由 13-agent workflow 完成：8 路并行深读（生命条组 / 攻击模式+弹药 / 快捷技能 / 快捷药剂 / 战技+冷却 / 按键+装饰 / onEnterFrame+初始化链 / 全调用点普查）+ 4 路对抗审计（战斗态突变 / 技能门控 / 场景存档 / facade 破坏）+ 1 路完整性批判。完整性批判捕获 3 个疑似整子系统级遗漏（buff 栏 / 角色名 / frameEnd 心跳）：buff 栏、角色名属实并入正文；**frameEnd 心跳经人类指认 + placement 核对为误报**（库符号定义存在但未实例化，已迁出主 FLA，见 §3.1）。教训：自动审计读到"库符号定义/字段写法"不等于"运行时被实例化/被调用"，停止线判定须核实 placement 与活跃调用。所有正文断言基于实际打开源文件核对。
