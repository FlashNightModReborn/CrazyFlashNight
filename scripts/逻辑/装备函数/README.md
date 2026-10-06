# 装备函数（装备生命周期脚本）

本目录的 `.as` 是**装备生命周期帧脚本**：每个文件把若干函数注册到 `_root.装备生命周期函数.XXX`，
由物品 XML 的 `<lifecycle>` 节点按装备绑定，在战斗中驱动该装备的动画 / 特效 / 子弹 / buff 等。

> **文档角色**：装备生命周期脚本子系统的就近 hub（用途索引 + API 快查 + 新增/编译流程）。
> 顶层入口只放指针：`AGENTS.md` Context Pack、`agentsDoc/game-systems.md §13`、`docs/asLoader-README.md`。

---

## 0. 这是什么 / 不是什么

- **是**：帧脚本，`#include` 进 asLoader 的 boot 帧编译；运行时挂在 `_root.装备生命周期函数` 上，
  经 `单位函数_fs_装备生命周期配置.as` 的 `装载生命周期函数` 注册为单位的周期任务。
- **不是** `scripts/类定义/org/flashNight/arki/item/equipment/`——那是 **class 化的装备数值计算系统**
  （PropertyOperators / EquipmentCalculator / ModRegistry），跟本目录的帧脚本生命周期是**两套平行系统**，勿混。

---

## 1. ⚠ 编译真源：frame37.as（最易踩的坑）

asLoader 在 2026-06 **塌缩成单帧**后，本目录的 `.as` **不是被直接编译的**。真正的编译清单是：

```
scripts/asLoaderManifest/frame37.as   ← 真源：f37_1..f37_8 八个 chunk，逐个 #include 本目录脚本
   │  (stage-wrap --flatten 当初已把旧 装备函数列表.as 展平到这里；切 chunk 是为绕 AVM1 单函数体 64KB 硬限)
   ▼  BOOT_SOURCES 中 equipment-functions → node tools/assemble-collapsed-frame.js
scripts/asLoaderManifest/_collapsed_frame.as   ← 生成物，勿手改
   ▼  Flash CS6 重编 asLoader.swf（#include 之）
asLoader.swf
```

- **加了 `.as` 却忘在 `frame37.as` 接线 → 编译 0 错、运行无报错、功能静默不生效**（旧 `装备函数列表.as` 不在编译链，改它无效）。
- 这条一致性由 **`tools/validate-equip-fn-coverage.js`** 锁死：本目录 `.as` ≡ `frame37.as` 的 `#include` ≡ 本 README 索引，缺一 `exit 1`（已接入 `node tools/validate-doc-governance.js`）。
- 完整管线与重编步骤：`docs/asLoader-README.md`「装备编译管线」节。

---

## 2. 新增 / 修改一个装备脚本

1. **建文件**：复制现有 `.as` 改名（保 UTF-8 **with BOM**；禁止从零新建——丢 BOM 会被编译器静默跳过）。
2. **写函数**：常规装备注册 `_root.装备生命周期函数.XXX初始化 = function(ref, param){…}` + `.XXX周期 = function(ref, param){…}`；纯初始化装备可以只写 init。
   周期函数**首行**必须 `if (!EquipmentTick.open(ref)) return;`（或 `EquipmentTick.cleanup(ref);`）。
   范例：最简看 `M249.as`，射击动画看 `M134.as`，含弹容/换弹状态的完整范例看 `追月连弩.as`。
3. **绑物品**：在 `data/items/武器_*.xml`（或对应物品文件）该 `<item>` 内、与 `<data>` 同级加：
   ```xml
   <lifecycle>
     <attr_0>
       <skillInteraction>independent</skillInteraction>
       <init><initRoutines>XXX初始化</initRoutines></init>
       <cycle><cycleRoutines>XXX周期</cycleRoutines></cycle>
     </attr_0>
   </lifecycle>
   ```
   `skillInteraction` 按实际行为选择，示例仅表示独立行为；可选 `<initParam>`/`<cycleParam>`/`<bullet>`/`<data>`/`<skill>`，详见 §4。
4. **接线 frame37**：在 `scripts/asLoaderManifest/frame37.as` 选一个未过载的 `f37_N` chunk 加
   `#include "../逻辑/装备函数/XXX.as"`（顺序不影响功能，只是注册顺序）。**这步最易忘**。
5. **登记 README**：在 §6 脚本索引加一行（含 `XXX.as`）——校验门要求。
6. **重生成并核对**：依次运行 `node tools/assemble-collapsed-frame.js`、`node tools/assemble-collapsed-frame.js --check` 与 `node tools/check-bom.js`；后两项分别守字节级可重建与所有 `.as` 的严格 BOM。
7. **自检**：`node tools/validate-equip-fn-coverage.js` 应 `ok`；新增或调整 lifecycle 绑定时另跑 `python -X utf8 tools/lifecycle-skill-metadata/validate.py`，包括进阶覆盖中的绑定。
8. **重编**：仅改外置 `.as` 时直接运行 `powershell -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 180`，再重启游戏（物品 XML 在 boot 阶段加载）；只有改动 asLoader XFL 时间轴 / symbol 结构时才关闭并重开 FLA。没有新鲜 trace、Output Panel 副本或 IDE 复核时，不声称“编译通过”。

游戏内表现异常时，先直接在生命周期初始化、周期和事件回调记录现场，再根据日志扩大排查范围。动画需同时看期望帧、实际帧、目标 MovieClip 引用和版本；下一周期开始时的读数能帮助发现写入后又被重置的情况。`枪械射击动画.as` 已提供默认关闭的 `initParam.debug`，具体用法见 [动画工具](../../../tools/weapon-animation/README.md#原生脚本与验证边界)。

> 生成器会用 canonical LF、剥 BOM 的口径报告源闭包；`70,000 B` 只是人工复核提示线，不是修改防增长 hard gate，也不维护 exact no-growth 表。当前 `f37_7=76,380 B` 属于优先调查候选：修改时应结合实际 `codeSize`、副作用边界与 fresh 行为证据判断是否移到更空的 `f37_N` 或继续拆分，不能仅因注释 / 格式增长阻断构建。

---

## 3. 生命周期与绑定流程

`装载生命周期函数(生命周期信息, 装备类型)`（`单位函数_fs_装备生命周期配置.as`）遍历 `<lifecycle>` 的每个 `attr_N`：

1. 构造 **`ref`（反射对象）**（见 §5 字段表），含 `自机`/`装备类型`/`装备名称`/`标签名`/`子弹配置` 等。
2. 有 `<skill>` → `装载主动战技`；有 `<bullet>` → 逐 `bullet_N` 经 `子弹属性初始化` 建 `ref.子弹配置[...]`；有 `<data>` → 存 `ref.data`。
3. 有 `<init>` 时，调 `_root.装备生命周期函数[initRoutines](ref, initParam || {})`。
4. 有 `<cycle>` 时，把 `_root.装备生命周期函数[cycleRoutines]` 经 `帧计时器.taskManager.addLifecycleTask` 注册为每帧任务，传 `[ref, cycleParam || {}]`。
5. 周期任务注册卸载回调进 `自机.生命周期函数列表`——装备切换/版本变更时自动卸载（`EquipmentTick.open/cleanup` 内含 `移除异常周期函数` 检测）。整只单位被主动重建或移除时，调用方应先执行 `DressupInitializer.teardownLifeCycles(unit)`，再 `removeMovieClip()`；二次清理安全。

`<init>` 与 `<cycle>` 独立可选，但一个 `attr_N` 至少应声明其中之一。loader 对既有 init-only 节点使用空 routine 名生成稳定标签，不再访问缺失的 `cycle.cycleRoutines`。

函数签名：
```actionscript
_root.装备生命周期函数.XXX初始化 = function(ref:Object, param:Object) { /* param = initParam */ };
_root.装备生命周期函数.XXX周期   = function(ref:Object, param:Object) {
    if (!EquipmentTick.open(ref)) return;   // 异常清理 + 同帧去重
    var 自机:MovieClip = ref.自机;
    /* … 每帧逻辑，全部经 ref 读字段，不依赖全局（除 _root） … */
};
```

---

## 4. 物品 XML `<lifecycle>` schema

```xml
<lifecycle>
  <attr_0>
    <skillInteraction>independent</skillInteraction> <!-- 必填审计元数据，按下节分类 -->
    <init>
      <initRoutines>函数名初始化</initRoutines>   <!-- init 存在时必填，精确匹配注册键 -->
      <initParam> … 任意键，原样传入 init 的 param … </initParam>
    </init>
    <cycle>
      <cycleRoutines>函数名周期</cycleRoutines>     <!-- cycle 存在时必填；init-only 可省略整个 cycle -->
      <cycleParam> … 任意键，原样传入 周期 的 param … </cycleParam>
    </cycle>
    <bullet>                                       <!-- 可选；无射击机制可省 -->
      <bullet_0>
        <power>100%</power>   <!-- 末尾带 % = 相对威力基数(刀/长枪/空手基础伤害)；否则绝对值 -->
        <bullet>子弹种类</bullet><split>1</split><diffusion>5</diffusion><velocity>6</velocity>
        <sound/><muzzle/><bullethit/><range>300</range><impact>1</impact><knockback>0</knockback>
        <damagetype/><magictype/>
      </bullet_0>
    </bullet>
    <skill> … 可选，主动战技配置 … </skill>
    <data> … 可选，备用武器数据，存入 ref.data … </data>
  </attr_0>
  <!-- 可有多个 attr_N，各自独立注册一对 init/cycle -->
</lifecycle>
```

<a id="skill-interaction"></a>
### 4.1 `skillInteraction`：与战技的关系

这是每个 `lifecycle/attr_*` 的审计元数据。分类单位是**一次绑定及其参数、可达回调与清理链**，不是整件装备，也不是脚本文件名。基础绑定和进阶中完整替换的 lifecycle 都要填写；同一函数可能因参数或套装条件具有不同关系。

| 值 | 判定依据 |
|---|---|
| `independent` | 不提供或管理主动战技，不参与某个指定战技的专用数据、许可或动作协议。动画、手电、激光、通用射击/状态反馈通常属于此类；伤害、耗蓝、改弹药本身不意味着战技槽竞争。 |
| `fallback` | 仅由本 attr 的直接子节点 `<skill>`，通过 loader 在对应战技槽为空时提供默认战技；routine 不存在更强的依赖或管理行为。 |
| `bound` | 参与指定战技的专用参数、许可、动作协议，或直接调用固定的专用技能/战技动作；包括协议的生产端与消费端，但不主动改写战技定义或选择列表。 |
| `managed` | 可达路径注册、替换、清空、恢复主动战技槽，改写战技选择索引，或接管 NPC 战技列表/路由选择。只有部分进阶、套装或 NPC 分支生效，也需要标出。 |

同一 attr 同时具有多种关系时取 `managed > bound > fallback > independent`。`managed` 不保证管理的是本装备对应槽，例如剑圣腿甲会装载空手战技；直接执行一个固定动作也不等于改写战技槽，应归入 `bound` 并记录动作协议。

通用 `WeaponSkill(mode)` 由成功的普通主动战技统一发布。仅监听它、且不限定战技名称或读取专用参数，不足以标为 `bound`。例如斩马刀的通用激活窗口与剑圣胸甲的肩炮触发可标 `independent`；剑圣手甲限定“刀剑乱舞”、G111 的充能值供“突击者之怒”判定，则属于 `bound`。公共组件暴露可选 API 供其他战技调用，也不自动让该组件的全部绑定成为 `bound`。

**本体标签不直接决定安装准入。** `independent` 只说明这一条生命周期与战技的关系，不解除根层 `item.skill`、`subweapon`、`skillLocked` 或插件槽位规则；`bound` 也不自动表示不能替换战技。它不证明不同生命周期之间的显隐、按键、资源或卸载行为完全兼容。

插件的顶层 `lifecycle` 由 `EquipmentLifecyclePolicy` 校验和合成：所有 attr 必须明确为 `independent`，至少有一个非空 init/cycle 回调，且不能直接声明 `skill` 或 `setGate`。`TagManager` 对不支持的插件生命周期返回 `-1024`；无生命周期的旧插件沿用原准入。功能插件可与本体战技共存，提供战技或副武器的插件仍受原锁与槽位规则约束。

`EquipmentCalculator` 先应用进阶覆盖，再深拷贝并合成插件生命周期。稳定命名包含插件名与 attr 名，`__modName` 标记来源；重算先剥除旧插件投影，卸下后不会残留，原物品与插件模板不被修改。loader 将来源映射为 `ref.来源插件`，仍通过原有生命周期卸载链执行。缺标或非法插件不能靠存档中的旧安装记录绕过这一执行门。

静态覆盖与 XML 字节保留检查见 [lifecycle-skill-metadata 工具](../../../tools/lifecycle-skill-metadata/README.md)。分类需沿实际代码复核；检查器不能替代这一步，也不证明运行行为或视觉效果。

### 4.2 装备光源参数与所有权

`装备光源初始化` / `装备光源周期` 使用独立 lifecycle。`initParam.kind` 为 `flashlight` 或 `laser`；可配置 `anchor`（点分路径）、`beamPath`（现有光束实例）、`fallbackVisual`（缺素材时是否生成 Flash 光束）、`channel`（逻辑发射器，默认 `primary`），以及 `length`、`halfWidth`、`energy`、`color`、`lightColor`。默认手电长度/半宽/能量为 1000/260/1.45，激光为 750/28/0.85；单位为世界坐标与能量倍数。`color` 只控制生成束体的 RGB 整数，`lightColor` 控制 native 材质照明，默认手电 16773584、激光 16737872（#FF6650）；激光束体仍保持细红线。

手电还可配置 `nearRadius` / `nearEnergy`，默认 140/1.15，二者须同为正数或同为 0。近身光中心由 AS2 按 `UnitUtil.calculateCenterOffset` 和持灯者真实位置计算；每单位只发送一份近身光，双持仍各自保留前照。近身光从中心连续衰减，前照从这片亮区平滑展开并逐渐回到枪口轴线；没有近身光时仍从枪口出光。两者放在同一条记录、共用一个预算名额，以有界平滑并集融合，避免等亮圆盘、接缝和重叠过曝。激光不携带近身光，横向柔光由窄核心快速衰减。

手电优先取 `手电口`，激光优先取 `激光发射器.出光位置`，缺失时取 `枪口位置`；两者都缺失则熄灭。长枪只以 `攻击模式 == "长枪"` 判断持用，换弹仍保持；手枪槽沿用手枪/双枪模式。实例身份、存活、显示链、版本及插件集合仍须有效。完整两点变换处理旋转与镜像。

已有光束保留形状、滤镜、颜色与透明度，由外部生命周期控制显隐；新插件没有素材时生成可用的 Flash 光束。AS2 始终拥有业务状态和束体，native 只叠加环境照明，能力撤销不移交玩法。相同单位/槽/种类/channel 内置优先于插件，独立发射器必须显式使用不同 channel。暂停保留，切场景/断连/死亡/卸载清理；光束整体在屏外时不占原生预算。传输与常驻预算见[战斗表现资源合同](../../../data/combat_visuals/README.md)。

战术手电插件可声明 `evasionBonus` 与 `electricEvasionBonus`（现役为 20/5），电力资格经 `TagManager` 的真实结构标签计算。`EquipmentLightDefense` 只接受来源明确的手电插件；当前持用并开灯时，同单位取最高加成，经一个独立 BuffManager Pod 修正反向躲闪率，保留原装备基值与其他 Buff。收枪、死亡、换装、卸载均移除；native 能力、屏外裁剪和灯预算不改变该玩法加成。内置手电不因此获赠插件数值，仍使用 `independent` 分类。

回归入口：`scripts/run-equipment-lifecycle-policy-tests.ps1`、`scripts/run-equipment-light-tests.ps1`、`scripts/run-equipment-light-defense-tests.ps1`；实际 XML、两把手电枪、M4A1 插件安装与生产接线跑 `scripts/run-equipment-light-asset-tests.ps1`，已接入的钛合金激光仍跑 `scripts/run-weapon-laser-tests.ps1`。

### 4.3 防具与兵器自发光

`装备自发光初始化` 使用独立 lifecycle；配置唯一真源为物品 XML 的 `initParam`。`group=body` 用于头部装备/上装装备/手部装备/下装装备/脚部装备，只需初始化及清理，不建立逐件逐帧任务；`group=blade` 用于刀，必须配套 `装备自发光周期`。参数为世界半径 `radius`（1–320）、`energy`（0–2）、RGB 整数 `color`，以及可选 `adapter`、`anchor`（单个刀口实例名，默认 `刀口位置1`）和 `channel`。缺刀口时使用实际兵器本体中心，不改动原素材显隐或战斗字段。

同单位身体贡献归并一盏：半径取最大值，强度为最强来源加受限补充（补充至多为最强来源的 25%），主来源决定颜色。参数在贡献变化时重算；位置、存活、可见性、装备实例/版本/插件内容仍在快照中验证。身体与近处同色刀光可合并，异色兵器保留独立小灯；较强手电近身光完全覆盖身体时抑制重复弱光，保留手电颜色和第三轮复合形状。刀光只给既有兵器源一个至多 18%、4 tick 衰减的包络，不按刀口或残影段数建灯。

常驻径向光以普通“枪火”的强度 1.5 为同角色装备组合峰值。同色近身合并直接补充能量并封顶；异色分灯时用两点光衰减的保守上界限制重叠峰值，不相交时恢复各自基础强度。刀光包络也包含在该限额内。配置 RGB 保持原色，输出色向白色混合 20%，以改善暗处材质辨认并保留色向；手电、镭射与原枪火色值不走该混合。点光软衰减、16 灯预算和逐帧状态更新保持。

`EquipmentLightingInfoBuilder` 从物品最终 `lifecycle` 生成【照明效果】，共用现有 Flash/native/Web 注释出口。它识别自发光、通用手电/镭射及旧 `枪械激光初始化`，按兵器适配器说明真实发光条件；相同功能去重。安装后的装备读取进阶/插件合成结果，插件自身显示适配说明；闪避只来自插件来源，内置手电不借用插件的 20/25 加成。旧 `lifecyle.description` 展示入口保留。此生成过程不进入战斗逐帧路径。

`adapter` 为 `static`、`blood`、`vocalist`、`libra`、`inductor`、`lion`、`capricorn`。后六种通过 `EquipmentEmissionState` 读取原初始化函数注册的生命周期 ref；新光效不写回形态、过载、计时、战技或存档。血剑读持用状态，主唱读光剑形态和展开程度，天秤读三态/CD，电感读展开和过载，狮子/摩羯读已有激活窗口。原生命周期的 `bound/managed` 等关系保持原义，新增光效自身为 `independent`。

AS2 原始贡献安全上限为 256，角色/用途组使用稳定 id，输出前按玩家、功能光源、距离选择至多 16 灯；同级有 8 tick 最短驻留及距离迟滞。原始注册表满载时也优先保障后来进入的玩家。身体静态绑定保留到装备或身份失效，断连仅撤销投影，重连可恢复；武器采样保留 2 tick 心跳期限。暂停冻结强度与包络，可见性、死亡和卸载仍立即生效。注册/注销操作不修改正在遍历的共享清理队列。

新能力 `equipmentRadialLights=1` 与既有 `equipmentLights=2` 分开协商，旧 Host 不会收到新点光记录。防具/兵器不获得战术手电的闪避加成。配置检查见 [equipment-emissive](../../../tools/equipment-emissive/README.md)，行为与实际素材分别运行 `scripts/run-equipment-emissive-tests.ps1`、`scripts/run-equipment-emissive-asset-tests.ps1`。

---

## 5. API 快查

### 5.1 `ref`（反射对象）字段
框架注入：
- `自机` — 装备所属单位 MovieClip（=this）
- `装备类型` — `刀`/`长枪`/`手枪`/`手枪2`/`手雷`/`头部装备`/`上装装备`/… （槽位）
- `装备名称` / `装备种类` — 来自 `this[装备类型].name` / `this[装备类型+数据].use`
- `是否为主角` — `this._name === _root.控制目标`
- `标签名` — 周期任务唯一标识（`装备名称_装备类型_周期函数名+attrN`）
- `生命周期任务ID` / `生命周期函数列表` / `版本号` — 任务管理与异常卸载
- `子弹配置` — `{bullet_0, bullet_1, …}`，由 `<bullet>` 节点初始化
- `data` — `<data>` 节点内容
- `来源插件` — 合成插件生命周期的来源名称；本体绑定为 `undefined`

通用 helper 约定字段（按需）：
- `成功率`(默认3，配 `_root.成功率`)、`身高修正比`、`获得刀口`(配 `解析刀口`)
- `config`(变形：`instanceContainer`/`animationTarget`)、`animationDuration`/`currentFrame`/`animationTarget`
- `actionFunc`/`actionFuncParam`、`updateFunc`/`updateFuncParam`（`自机状态检测` 系列）
- `basicStyle`/`position`（刀光/拖影/特效刀口）

### 5.2 公共 helper / 类
生命周期框架：
- `EquipmentTick.open(ref):Boolean` — 周期开场（异常清理 + 同帧去重）；`false` 即 `return`
- `EquipmentTick.cleanup(ref):Void` — 仅异常清理（无视觉去重的装备用）
- `VisualSync.beginTick(ref):Boolean` — 同帧去重底层
- `RuntimeEquipmentProjection.reserveEmptySlotAlias(ref, targetSlot)` → 装备完成目标槽属性配置后调用 `commitSlotAlias(intent)`；失败调用 `cancelSlotAlias(intent)` — lifecycle owner 对 canonical 空槽的唯一运行态借用入口。只允许 `ref.装备类型` 的 exact 装备引用、同一单位 `version` 与空目标槽，冲突/过期 intent fail-closed；禁止脚本直接写 `自机.刀 = 自机.长枪` 等跨槽 alias
- `_root.装备生命周期函数.移除周期函数(ref)` / `移除异常周期函数(ref)` — 卸载 / 版本失配检测
- `_root.装备生命周期函数.解析刀口(ref, param)` / `获得身高修正比(ref)`

通用行为（直接在 XML 指为 initRoutines/cycleRoutines，多数装备无需写新 .as）：
- `初期特效初始化` / `初期特效周期` — 兵器攻击按概率发 `MuzzleWorldShoot` + 子弹
- `通用变形初始化` / `通用变形周期` — 动画帧驱动的形态切换（配 `config`）
- `长枪射击动画初始化` / `长枪射击动画周期` — 成功主长枪射击驱动的有限帧动作（配 `fireStart` / `fireEnd` / 可选 `animationTarget` / `instanceContainer`）；制作和原生验证见 [weapon-animation](../../../tools/weapon-animation/README.md)
- `自机状态检测` / `自机状态更新` / `反转自机属性` — 状态判定 + 按键触发 + 持久化到 item.value
- `通用刀光周期` / `通用拖影周期` / `通用特效刀口初始化`+`通用特效刀口周期`

视觉 / dressup：
- `PlacementVisual.hookVisualUpdate(target, refName, ref, updateFn)` — placement 后钩视觉更新
- `DressupSubscriber.onPlacement / onReady / onRefreshed(unit, refName, handler[, scope])` — 三档装扮就绪通道
- `WeaponAnimationTarget.resolve(ref):MovieClip` — 解析 `自机[instanceContainer][animationTarget]`
- `BladeFireSpinController.tick(ref, gunAnim)` — 加特林族连射计数 → 浮点帧推进
- `StaleRefCache.snapshot(target, saber, position)` — 刀口坐标快照（stale window 回落）
- `KeyEdgeTrigger.onRise(ref, unit, keyName, wasKeyPropName):Boolean` — 按键上升沿
- `EquipmentFireIntent.isMainLongGunProcessShot / isMainLongGunUpdateBullet / publishMainLongGunUpdateBullet` — 装备订阅 `processShot` / `updateBullet` 时判断“主长枪开火”意图，兼容旧 4 参数 `updateBullet`

战斗 / 工具：
- `MuzzleWorldShoot.populate(刀口, 自机, 子弹属性[, xOff, yOff, 身高修正比])` — 写 shootX/Y/Z
- `_root.子弹区域shoot传递(子弹属性)` — 投递子弹生成
- `_root.兵器攻击检测(自机)` / `兵器使用检测(自机)` / `成功率(倍数)` / `按键输入检测(自机, 键名)`
- `ShootCore.continuousShoot/startShooting` — 射击核心（`dispatcher.publish(攻击模式+"射击")` 的发源）

### 5.3 运行期数据路径（高频）
- 武器实例：`自机.长枪_引用` / `自机.刀_引用[刀口位置N]` / `自机.手枪_引用` / `自机.X装备_引用`
- 弹药：`自机.长枪弹匣容量`(Number) · `自机.长枪.value.shot`(已射发数) → 剩余 = 容量 − shot
- 事件：`自机.dispatcher.subscribe("长枪射击" | "updateBullet" | "WeaponSkill" | "enemyKilled" | …)`
- 状态：`自机.攻击模式`(长枪/兵器/空手) · `自机.状态` · `自机.man`(角色 MC) · `自机.方向` · `自机.身高`
- 系统：`自机.buffManager`(addBuff/removeBuff) · `自机.主动战技` · `_root.控制目标` · `_root.gameworld`
- 计时：`_root.帧计时器.taskManager`(addLifecycleTask/removeLifecycleTask) · `_root.帧计时器.当前帧数`

---

## 6. 脚本索引

> 共 64 个装备脚本 + 1 个共享库。新增脚本必须在此登记（校验门强制）。

### 共享库
- `通用装备函数.as` — 通用行为 helper 库（初期特效 / 通用变形 / 通用刀光 / 通用拖影 / 通用特效刀口 / 自机状态检测 系列）+ `移除周期函数`/`解析刀口`/`获得身高修正比` 等框架函数。

### A. 加特林连射族（转轴/转盘连续旋转）
- `M134.as` — M134加特林 · 成功 `processShot`/旧射击事件产生主长枪旋转意图，旋转控制器驱动当前活动 `man` 的规范装扮引用，射击加速/停射衰减；副武器隔离
- `枪械射击动画.as` — 可复用的主长枪有限射击动画；按游戏帧时钟推进、连发重新对齐、切姿态回位、placement 同步及换装精确退订，首个配置为 QJZ171
- `枪械激光瞄准.as` — 以实体发射器的出光位置动态挂载独立光束；支持手枪双持和长枪、镜像与旋转、姿态显隐、换装精确退订，静态烘焙保留硬件外观
- `装备光源.as` — 手电/激光与防具/兵器自发光入口；实际锚点、角色贡献归并、条件状态观察、稳定预算和清理由通用控制器管理
- `M134暴力版.as` — M134加特林（NPC自动版） · 非玩家单位按时间间隔自动射击 + 距离判定
- `XM214-CageFrame.as` — XM214 笼式框架加特林 · 霰弹值驱动转速，自动衰减 + 双环抖动反馈
- `XM556_Microgun.as` — XM556 微型加特林 · 转盘连续旋转，射击加速/停射减速的视觉惯性
- `XM556_H_Stinger.as` — XM556_H Stinger 激光制导微加特林 · 继承 XM556 核心 + 激光模组模式联动显隐
- `僵尸割草机.as` — 僵尸割草机（长枪）· 连射增转速，加特林式连射视觉

### B. 兵器·刀光 / 拖影 / 刀口特效
- `刀口触发特效.as` — 十文字大剑/黑铁的剑/主唱光剑/烬灭裁决/秋月 · 按刀口段位触发追加子弹特效（概率+MP）
- `黑铁的剑.as` — 黑铁的剑 · 经通用刀口初始化绑定段位特效
- `光刀狮子.as` — 光刀狮子 · 战技触发刀光，落日鎏金风格
- `光刃摩羯.as` — 光刃摩羯 · 战技后 150 帧刀光，翠绿疾影，自然衰减
- `杀戮风暴.as` — 杀戮风暴 · 连射速度驱动刀光旋转，速度滞回 + 衰减
- `电感切割刃.as` — 电感切割刃（刀）· 电能积累 + 过载自动锁定射线 + 刀光
- `贯空天盖手套.as` — 贯空天盖手套（手套）· 空手战技菜单循环 + 登星拖尾

### C. 防具技能（挂载部件 / buff / 肩炮等）
- `剑圣套装.as` — 剑圣五件套共享 context 生产者与 gated 事务资源登记 helper
- `钛合金套装.as` — 五甲门控的机甲能源入口；共享class管理满血免费初始盾、付费治疗/战斗修盾、负重伺服、破盾增伤、夜视、手枪基础返还/原子补弹与171条件快照，胸甲为唯一周期；P90额外发电归自身装备生命周期
- `Mark3.as` — Mark3手甲 · 按键切换能量电池消耗模式，影响空手攻击
- `剑圣头部装甲.as` — 剑圣头部装甲 · 低光夜视与常驻近敌扫描/躲闪 debuff 相互独立
- `剑圣手甲.as` — 剑圣手甲 · 挂腕刃，常驻空手加成，刀剑乱舞切爆发态 +70%，坐标跟随左下臂
- `剑圣胸甲.as` — 剑圣胸甲 · 挂肩炮，冷却/启动/待机/发射/收回状态机，三阶+击杀减CD，战技发追踪导弹
- `剑圣腿甲.as` — 剑圣腿甲 · 挂剑匣，装载刀剑乱舞战技（CD递减），剑匣跟随身体旋转
- `剑圣装甲鞋.as` — 剑圣装甲鞋 · 阶段性速度 buff，一文字落雷增强追踪/反弹
- `毒液蜘蛛侠.as` — 毒液蜘蛛侠 · 防具技能发蜘蛛网子弹，命中施减速 buff
- `红外夜视仪.as` — 红外夜视仪（玩家专属）· 向天气系统注册夜视视觉预设

### D. 武器变形 / 形态切换 / 状态机
- `G111.as` — G111步枪 · 充能键累积驱动枪口变形 + 激光模组状态切换
- `G1111.as` — G1111（步枪/导弹双形态）· 形态切换 + 磁轨自瞄 + 充能真伤狙击 + 激光锁定
- `GM6_LYNX.as` — GM6 LYNX 狙击枪 · 互斥状态机展开/待机/射击，击杀按精英等级反馈弹药
- `Jackhammer.as` — Jackhammer 霰弹枪 · 充能状态在两战技间切换 + 枪口/激光视觉同步
- `RPG28.as` — RPG28 · 按攻击模式切外观帧
- `RShG4Я.as` — RShG4（应急双发）· 收纳/展开/开火/装填四态循环，帧参数可配 + 反向播放
- `XM556-OC-Overlord.as` — XM556-OC Overlord 双联装机炮 · 双枪/手枪模式自动展开 + 射击帧循环
- `wa90变形款.as` — WA90 双形态自动步枪 · 变形键切两形态，平滑过渡 + 枪口/激光联动
- `主唱光剑.as` — 主唱光剑（光剑/话筒）· 光刃发射 + 红色音符叠 buff + 猩红增幅治疗 + 伙伴召唤
- `光剑天秤.as` — 光剑天秤 · 三态（默认/攻势/守御）切换，攻击积 buff，战技伤害按切换次数倍增
- `血色光剑天秤.as` — 保留两路逐帧自损/血系子弹；R04独立光效定帧、placement去重与卸载清理
- `双面雷神.as` — 双面雷神 · 步枪/狙击双形态无缝变形 + 属性切换
- `吉他喷火.as` — 吉他喷火 · 喷火器/机枪双形态 + 通过 `RuntimeEquipmentProjection` 借用空刀槽 + 机枪过热 + 音符 buff
- `死者之手.as` — 死者之手 · 通过同一 intent API 借用空长枪槽 + 枪-刀复合多部件展开 + 超载模式切换
- `火药燃气液压打桩机.as` — 原版打桩机 · 保留展开-收缩枪动画，空刀槽借用590物理锋利度普通狂野锤；三个运行态刀口、词条继承及精确卸载由 `PileBunkerClassicController` 接管
- `打桩机M7.as` — 重锤进阶生命周期 · Q切换副喷火/过载、12格燃料共用、按余弹三档清匣、独立锋利度、插件词条继承、完整出桩判定与锤战技燃爆窗口；两形态主仓换弹延迟+200%，翻滚换弹沿原链
- `炎魔斩new.as` — 炎魔斩（刀）· 刀/链锯形态切换 + 各形态特效与子弹
- `烬灭裁决.as` — 烬灭裁决（长柄/双刀）· 双形态切换 + 战技路由动画 + 属性/战技重算
- `牙狼剑.as` — 牙狼剑（刀）· 剑/斩马刀形态快切 + 关联动作与战技
- `等离子切割机.as` — 等离子切割机（长枪）· 展开-射击动画 + 击杀回血 + 追加子弹
- `铁枪.as` — 铁枪（长枪）· BFG/UNMAYKR 形态切换 + 枪身零件/轮盘旋转
- `键盘镰刀.as` — 键盘镰刀（刀）· 镰刀/键盘双形态 + 空中跳砍追踪充能 + 多层子弹特效
- `雷铁斩斧.as` — 雷铁斩斧 · 变形键切两种斧头形态 + 视觉帧动画

### E. 长枪·弹匣 / 弹容显示同步
- `AR57.as` — AR57步枪 · 弹匣容量与枪口动画帧同步（`MagazineFrameSync`）
- `M249.as` — M249 · 订阅射击播放枪动画 + 按弹匣状态控可见性
- `NEGEV.as` — NEGEV · 订阅射击播放枪动画 + 按弹匣/模式控动画与激光可见性
- `P90.as` — P90 · 双枪模式弹匣动画帧与当前射击弹匣同步
- `PF98A.as` — PF98A · 按弹匣容量与攻击模式控弹头可见性与枪帧

### F. 长枪·枪口 / 弹头外观
- `G11.as` — G11步枪 · 订阅长枪射击触发枪口动画
- `RPG.as` — RPG · placement 回调驱动周期，控火箭弹头可见性
- `RShG4.as` — RShG4 · 弹头可见性 + 攻击模式帧 + 按朝向同步文字方向
- `Six12_Matryoshka.as` — Six12 Matryoshka 套筒双管霰弹 · 连射计数轮换两枪口位置（左右交替）

### G. 锁定 / 追踪 / 制导
- `XM25.as` — XM25 自动榴弹发射器 · 四级渐进锁定 + 激光自动追踪 + 旋转限制破锁

### H. 召唤 / 宠物 / 复活
- `九命猫妖.as` — 九命猫妖 · 复活上限/概率管理，血量低触发扭转乾坤；`九命猫妖初始化`（真猫妖头套挂载）另含所有虎妙共用配置：独立声库（静音默认）/ 空手技能库覆写 / HeroUnarmed 独立 AI 迁移 / Z 轴精确对齐每帧任务；`真九命猫妖初始化`（九命猫妖项链挂载）= 复活上限/概率 + 退场计时器（项链专属，勿迁）

### I. buff / 战技联动
- `光斧金牛.as` — 光斧金牛（斧）· 监测打怪掉钱机率，效果结束发金牛之力视觉子弹
- `公社爆燃钻矛.as` — 公社爆燃钻矛（矛）· 耗燃料罐战技连发 + 兵器五段单发 + 魔法热伤窗口金属件特效

### J. 外观 / 夜视 / 视觉
- `外观类挂载.as` — 披风/后发等外观挂载 · 同步背景物件位置朝向与镜像
- `喷气背包.as` — 喷气背包 · 视觉挂载 + 喷火显示逻辑

### K. 长枪·射击动画 / 可见性 / 超载
- `MACSIII.as` — MACSIII · 超载模式状态机 + 自伤 + 紧急停机 + 斩杀吸血
- `混凝土切割机.as` — 混凝土切割机 · 钻头旋转动画 + 超载视觉淡出
- `追月连弩.as` — 追月连弩（连弩）· 监听射击/换弹增量驱动后坐乒乓动画 + 箭筒弹容档位显示

### Z. 其他 / 特殊
- `斩马刀.as` — 斩马刀 · 兵器攻击持续消弹 + 周期碎石飞扬特殊子弹
- `烈焰斩马刀.as` — 烈焰斩马刀（刀）· 耗蓝武器技能窗口激活 + 多段子弹
- `镜之虎彻.as` — 镜之虎彻 · 周期镜闪特效 + 反射弹幕（耗 MP）

---

## 7. 相关文档
- 编译管线 / 重编 asLoader：`docs/asLoader-README.md`
- 装备系统在游戏系统索引中的位置：`agentsDoc/game-systems.md §13`
- 新增脚本编码约定（BOM / 命名 / ref 约定）：`agentsDoc/coding-standards.md`、`agentsDoc/as2-anti-hallucination.md`
- 一致性巡检：`tools/validate-equip-fn-coverage.js`（已接入 `tools/validate-doc-governance.js`）

钛合金五甲使用 `TitaniumSetRuntime`，P90固有发电使用 `EquipmentUtil/P90EnergyGenerator`。171激光从同一运行态读取火控进度并映射透明度，不发布切枪报数。真实 `processShot(owner, slot, muzzle, props, firedWeapon)` 的第五参绑定提交时武器实例；旧四参订阅者可忽略，双枪发电必须校验槽位和实例。`ReloadManager` 的开始/提交/结束代次用于中央补弹二次复核；任何MP/shot更新先于HUD事件。专项验证与编译产物边界见[套装ADR](../../../docs/钛合金61式装甲套装-玩法设计-ADR-2026-07-27.md#16-2026-09-08-s1s2本地接线与验证)。
