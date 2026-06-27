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
   ▼  node tools/assemble-collapsed-frame.js
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
2. **写函数**：`_root.装备生命周期函数.XXX初始化 = function(ref, param){…}` + `.XXX周期 = function(ref, param){…}`。
   周期函数**首行**必须 `if (!EquipmentTick.open(ref)) return;`（或 `EquipmentTick.cleanup(ref);`）。
   范例：最简看 `M249.as`，射击动画看 `M134.as`，含弹容/换弹状态的完整范例看 `追月连弩.as`。
3. **绑物品**：在 `data/items/武器_*.xml`（或对应物品文件）该 `<item>` 内、与 `<data>` 同级加：
   ```xml
   <lifecycle>
     <attr_0>
       <init><initRoutines>XXX初始化</initRoutines></init>
       <cycle><cycleRoutines>XXX周期</cycleRoutines></cycle>
     </attr_0>
   </lifecycle>
   ```
   （可选 `<initParam>`/`<cycleParam>`/`<bullet>`/`<data>`/`<skill>`，详见 §4。）
4. **接线 frame37**：在 `scripts/asLoaderManifest/frame37.as` 选一个未过载的 `f37_N` chunk 加
   `#include "../逻辑/装备函数/XXX.as"`（顺序不影响功能，只是注册顺序）。**这步最易忘**。
5. **登记 README**：在 §6 脚本索引加一行（含 `XXX.as`）——校验门要求。
6. **重生成**：`node tools/assemble-collapsed-frame.js`。
7. **重编**：CS6 重开 asLoader FLA → 编译 → 重启游戏（物品 XML 在 boot 阶段加载）。
8. **自检**：`node tools/validate-equip-fn-coverage.js` 应 `ok`。

> chunk 撑爆 64KB 由 `tools/swf-function-sizes.js` 拦（编译验证步内）；真撑爆就把脚本挪到更空的 `f37_N`。

---

## 3. 生命周期与绑定流程

`装载生命周期函数(生命周期信息, 装备类型)`（`单位函数_fs_装备生命周期配置.as`）遍历 `<lifecycle>` 的每个 `attr_N`：

1. 构造 **`ref`（反射对象）**（见 §5 字段表），含 `自机`/`装备类型`/`装备名称`/`标签名`/`子弹配置` 等。
2. 有 `<skill>` → `装载主动战技`；有 `<bullet>` → 逐 `bullet_N` 经 `子弹属性初始化` 建 `ref.子弹配置[...]`；有 `<data>` → 存 `ref.data`。
3. 调 `_root.装备生命周期函数[initRoutines](ref, initParam || {})`。
4. 把 `_root.装备生命周期函数[cycleRoutines]` 经 `帧计时器.taskManager.addLifecycleTask` 注册为每帧任务，传 `[ref, cycleParam || {}]`。
5. 注册卸载回调进 `自机.生命周期函数列表`——**装备切换/版本变更时自动卸载，无需手工清理**（`EquipmentTick.open/cleanup` 内含 `移除异常周期函数` 检测）。

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
    <init>
      <initRoutines>函数名初始化</initRoutines>   <!-- 必填，精确匹配 _root.装备生命周期函数 上的键 -->
      <initParam> … 任意键，原样传入 init 的 param … </initParam>
    </init>
    <cycle>
      <cycleRoutines>函数名周期</cycleRoutines>     <!-- 必填 -->
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
- `_root.装备生命周期函数.移除周期函数(ref)` / `移除异常周期函数(ref)` — 卸载 / 版本失配检测
- `_root.装备生命周期函数.解析刀口(ref, param)` / `获得身高修正比(ref)`

通用行为（直接在 XML 指为 initRoutines/cycleRoutines，多数装备无需写新 .as）：
- `初期特效初始化` / `初期特效周期` — 兵器攻击按概率发 `MuzzleWorldShoot` + 子弹
- `通用变形初始化` / `通用变形周期` — 动画帧驱动的形态切换（配 `config`）
- `自机状态检测` / `自机状态更新` / `反转自机属性` — 状态判定 + 按键触发 + 持久化到 item.value
- `通用刀光周期` / `通用拖影周期` / `通用特效刀口初始化`+`通用特效刀口周期`

视觉 / dressup：
- `PlacementVisual.hookVisualUpdate(target, refName, ref, updateFn)` — placement 后钩视觉更新
- `DressupSubscriber.onPlacement / onReady / onRefreshed(unit, refName, handler[, scope])` — 三档装扮就绪通道
- `WeaponAnimationTarget.resolve(ref):MovieClip` — 解析 `自机[instanceContainer][animationTarget]`
- `BladeFireSpinController.tick(ref, gunAnim)` — 加特林族连射计数 → 浮点帧推进
- `StaleRefCache.snapshot(target, saber, position)` — 刀口坐标快照（stale window 回落）
- `KeyEdgeTrigger.onRise(ref, unit, keyName, wasKeyPropName):Boolean` — 按键上升沿

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

> 共 63 个装备脚本 + 1 个共享库。新增脚本必须在此登记（校验门强制）。

### 共享库
- `通用装备函数.as` — 通用行为 helper 库（初期特效 / 通用变形 / 通用刀光 / 通用拖影 / 通用特效刀口 / 自机状态检测 系列）+ `移除周期函数`/`解析刀口`/`获得身高修正比` 等框架函数。

### A. 加特林连射族（转轴/转盘连续旋转）
- `M134.as` — M134加特林 · 连射计数+旋转控制器驱动转轴动画，射击加速/停射衰减
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
- `Mark3.as` — Mark3手甲 · 按键切换能量电池消耗模式，影响空手攻击
- `剑圣头部装甲.as` — 剑圣头部装甲 · 低光自动扫近敌施躲闪 debuff，进阶控视觉强度
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
- `双面雷神.as` — 双面雷神 · 步枪/狙击双形态无缝变形 + 属性切换
- `吉他喷火.as` — 吉他喷火 · 喷火器/机枪双形态 + 刀枪复用 + 机枪过热 + 音符 buff
- `死者之手.as` — 死者之手 · 枪-刀复合多部件展开 + 超载模式切换
- `火药燃气液压打桩机.as` — 火药燃气液压打桩机（长枪）· 射击时装置展开-收缩动画状态机
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
- `九命猫妖.as` — 九命猫妖 · 复活上限/概率管理，血量低触发扭转乾坤

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
