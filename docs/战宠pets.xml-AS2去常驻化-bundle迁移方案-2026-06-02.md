# 战宠 pets.xml 的 AS2 去常驻化 — bundle 迁移方案

**状态**：✅ Phase 1 已施工（C# 验证通过、AS2/JS 欠 compile_test+手测）。⛔ **Phase 2 经施工期复核被否决**——`宠物库` 是运行态权威表，无法瘦身。详见 §9（重要更正）。开放问题拍板见 §8。
**目标**：削减 AS2 端常驻内存、降低 GC 压力——`data/merc/pets.xml`（57775 B）当前**整局常驻**于 AS2，解析为 `_root.宠物库` + `_root.宠物商城列表`，多数字段仅面板用得到。
**范式先例**：佣兵配置 `merc_bundle`（已落地，见 [MercLibrary.as](../scripts/类定义/org/flashNight/arki/merc/MercLibrary.as) + [DataQueryTask.cs](../launcher/src/Tasks/DataQueryTask.cs) + [DataCache.cs](../launcher/src/Data/DataCache.cs) + [XmlDataLoader.cs](../launcher/src/Data/XmlDataLoader.cs)）。
**关联**：[战宠数据权威-JS到XML-迁移设计提案-2026-05-31.md](战宠数据权威-JS到XML-迁移设计提案-2026-05-31.md)（JS→删除，已施工）；本方案是其下一步——**把 AS2 侧的 XML 常驻也卸掉**。

---

## 1. 现状依赖图（调研结论）

`_root.加载并配置宠物信息(xml文件地址)`（[XML数据解析.as:527](../scripts/通信/通信_fs_lsy_XML数据解析.as#L527)）在启动时异步加载 pets.xml，产出两份**整局常驻**的全局：

| 常驻全局 | 内容 | 消费方 | 运行时（战斗）必需？ |
|---|---|---|---|
| **`_root.宠物库`** | `<Pet>` 数组（~110 项，全字段：Identifier/Name/Height/Price/KPrice/Unlock*/…） | 战宠系统(出战)、等级经验、刷怪系统、PetPanelService | ✅ 出战时应用 |
| **`_root.宠物商城列表`** | `<PetStore><Category>`（分类名 + List 二维网格） | **仅** PetPanelService | ❌ 纯面板/领养 |

**战斗侧实际只读 3 个字段**（关键发现，决定 Phase 2 可行性）：
- [战宠系统.as:104](../scripts/引擎/引擎_lsy_战宠系统.as#L104) 出战：`宠物数据.Identifier` / `.Name` / `.Height`
- [等级与经验值.as:133](../scripts/引擎/引擎_lsy_等级与经验值.as#L133) 升级提示：`宠物库[...].Name`
- [关卡系统_lsy_非人形佣兵刷新系统.as:164](../scripts/逻辑/关卡系统/关卡系统_lsy_非人形佣兵刷新系统.as#L164) 刷怪：`宠物库[战宠编号]`（同样只取 Identifier/Name/Height 一类）

> 宠物**初始战斗属性**（HP/攻击等）来自 `敌人属性表[兵种=Identifier]`（敌人属性 XML），战宠系统不从 pets.xml 自存——这意味着战斗侧对 pets.xml 的依赖**仅是 id→兵种/名字/身高 的轻量映射**，重字段（价格/解锁/商城网格）全是面板用。

**启动加载入口的特殊性**：`加载并配置宠物信息` 在 .as 源码中**无调用点**（grep 全仓 0 命中除定义外）——它由主 SWF 时间轴帧脚本调用。改加载路径会触及"帧脚本 vs asLoader 类层"的发布摩擦（见 [MEMORY 战宠 panel 帧脚本需重发布 SWF] 同类约束）。

---

## 2. merc_bundle 范式（照搬模板）

```
AS2  MercLibrary.ensureBundleLoaded(cb)        ← 懒加载 + session 缓存 + pending 队列
       └─ DataQueryService.query("merc_bundle") ← AS2→C# socket
C#   DataQueryTask.QueryMercBundle()
       └─ DataCache.GetMercBundle()             ← 双检锁 + _attempted 一次性，失败缓存错误
            └─ XmlDataLoader.LoadMercBundle()    ← 读 data/hybrid_mercenaries/*.xml → JObject
消费  MercHybridizer/Spawner 直接读 MercLibrary.bundle（不再读 _root.X）
```

要点（[MercLibrary.as:41-68](../scripts/类定义/org/flashNight/arki/merc/MercLibrary.as#L41)）：
- session 级缓存、不主动失效；C# 侧 `_mercAttempted` 保证只解析一次（[DataCache.cs:67](../launcher/src/Data/DataCache.cs#L67)）。
- 加载失败 → `success:false`，AS2 走 legacy fallback。
- 字段名在 C# 侧精确匹配 AS2 属性名（[XmlDataLoader.cs:161](../launcher/src/Data/XmlDataLoader.cs#L161) 注释）。

宠物可 1:1 照搬这套缝。

---

## 3. Phase 1：商城数据（`宠物商城列表`）去 AS2 常驻

**最小、零战斗风险**——商城数据只有 PetPanelService 用。

### 3.1 C# 侧
- `XmlDataLoader.LoadPetBundle(projectRoot)`：读 `data/merc/pets.xml`，产出
  ```jsonc
  { "store": [ {name, list:[[id|null,...],...]}, ... ],   // <PetStore><Category>
    "petLib": [ {id, Identifier, Name, Height, Price, KPrice, IncreasePrice,
                 UnlockLevel, UnlockTask, Unique, ...}, ... ] }  // <Pet> 全字段
  ```
- `DataCache.GetPetBundle()`：复制 merc 的双检锁 + `_petAttempted`/`_petError`。
- `DataQueryTask`：`case "pet_bundle": return QueryPetBundle();`

### 3.2 AS2 侧
- 新增 `PetLibrary.as`（镜像 MercLibrary）：`ensureBundleLoaded(cb)` + `static get bundle()`。
  > ⚠️ 新建 .as 文件须 `cp` 现有类继承 BOM，**不要 Write 裸建**（见 MEMORY 文件编码铁律）。从 `MercLibrary.as` cp 最合适。
- `PetPanelService`：
  - snapshot 的商城分类（[:223,:261](../scripts/类定义/org/flashNight/arki/merc/PetPanelService.as#L223)）改读 `PetLibrary.bundle.store`，不再读 `_root.宠物商城列表`。
  - snapshot 入口先 `PetLibrary.ensureBundleLoaded` 再建包（面板打开是异步可接受点）。
- `加载并配置宠物信息`：**停止解析 `<PetStore>` 段**、不再写 `_root.宠物商城列表`（[:535-553](../scripts/通信/通信_fs_lsy_XML数据解析.as#L535)）。

### 3.3 收益 / 风险
- 收益：商城网格结构（二维数组 + 分类对象）退出常驻，面板关闭后可 GC。
- 风险：低。仅面板取数路径变化；战斗不碰。
- **开放问题①**：web 面板是否有**直连 C# 的数据通道**？若有，store 数据可 web↔launcher 直取、**完全不经 AS2**（AS2 连 `PetLibrary.store` 都不必持有）；若无，则经 AS2 snapshot 中转（仍需 AS2 短暂持有）。需先确认 [bootstrap/bridge] 通道能力——这决定 Phase 1 能做到"AS2 零持有"还是"AS2 短暂持有"。

---

## 4. Phase 2：`宠物库` → 轻量常驻 + 按需重字段（GC 主收益）

战斗侧只要 `id→{Identifier,Name,Height}`，面板才要全字段。据此拆分：

### 推荐：方案 2B — 战斗投影常驻 + 面板按需
- C# `pet_bundle` 已含全 `petLib`。AS2 启动时（或首次需要时）只缓存一份**瘦投影** `_root.宠物库瘦 = [{Identifier,Name,Height}, ...]`（按 index 对齐 `宠物信息[0]`）。
- 战斗三处消费改读瘦投影（字段名不变，照样 `.Identifier/.Name/.Height`）——**出战 `设置宠物出战` 保持同步返回 Boolean，调用契约零改动**。
- 面板重字段（价格/解锁/商城）走 Phase 1 的 `PetLibrary.bundle.petLib`，面板关闭后可释放。
- 删除 `加载并配置宠物信息` 对 `<Pet>` 全字段的常驻；改为只在 C# 投影后吃瘦版（或 AS2 收到 bundle 后自行投影并丢弃重字段引用）。

| | 2A 全按需异步 | **2B 瘦投影常驻（推荐）** | 2C 懒加载全量缓存 |
|---|---|---|---|
| 出战路径 | 改异步（侵入大，破坏 Boolean 契约） | **保持同步** | 同步（首次后） |
| AS2 常驻 | ~0 | **~110×3 小字段（极小）** | 全量（不省，只挪解析到 C#） |
| GC 主收益 | 最大但风险高 | **大且低风险** | 小 |
| 复杂度 | 高 | 中 | 低 |

> 2B 用极小常驻换同步契约，是 GC 目标与改动风险的最佳折中。2A 把 `设置宠物出战` 改异步会波及所有出战调用方（含 PetPanelService.handleDeploy 的 success 回滚），不值。

### 风险 / 回退
- 风险：中（碰战斗出战 + 刷怪 + 升级三条读取路径，及启动加载链）。
- 回退：bundle 加载失败 → AS2 保留 legacy `加载并配置宠物信息` 直读 pets.xml 作 fallback（与 merc 同策略），首版双轨并存、灰度后再删 legacy。
- **开放问题②**：启动加载入口在 SWF 帧脚本。改链路要么改帧脚本重发布主 SWF，要么把加载迁入经 asLoader 单独编译的类（`PetLibrary` 自身在首个消费点触发 `ensureBundleLoaded`，绕开帧脚本）。倾向后者——与 MercLibrary 一致、免重发布主 SWF。

---

## 5. 验证门槛（按迁移护栏）

| 改动面 | 必跑 |
|---|---|
| C# `LoadPetBundle`/`DataCache`/`DataQueryTask` | C# 构建 + `pet_bundle` 回包字段对照 pets.xml |
| AS2 `PetLibrary` 新类 + PetPanelService/加载链改取数 | `scripts/compile_test.ps1` fresh trace（0 错误）|
| 战斗读取（出战/刷怪/升级） | **游戏内端到端手测**：出战宠物外观/名字/身高正确、刷怪含战宠正常、升级提示名字正确 |
| 面板取数 | browser harness + 商店分类/价格/领养逐项对照 AS2 真值 |
| bundle 失败 fallback | 断 socket / 缺 pets.xml → 验证 legacy 直读兜底不崩 |

重点回归：瘦投影的 index 对齐（`宠物信息[0]` = `宠物库数组号`）必须与原 `_root.宠物库` 一致，错位会导致出战错宠。

---

## 6. 待你拍板

1. **Phase 1 的 AS2 持有度**（开放问题①）：web 面板能否直连 C# 取 store 数据（AS2 零持有），还是经 AS2 snapshot 中转？需先核 bridge/launcher 数据通道能力。
2. **Phase 2 方案**：确认 2B（瘦投影常驻、保同步契约）为施工目标。
3. **加载入口**（开放问题②）：确认走"PetLibrary 类内首消费触发 ensureBundleLoaded"（免重发布主 SWF），还是改帧脚本。
4. **施工顺序**：建议 Phase 1 先行落地验证范式，再上 Phase 2；双轨 fallback 灰度后再删 legacy `加载并配置宠物信息`。

---

## 8. 拍板决议（2026-06-02）

- **开放问题①（web 直连 C#）→ 确认：有，照 `IntelligenceTask` 范式。** Web 静态目录数据由 C# 直接读 XML 后 `PostToWeb`，**完全不经 Flash/AS2**（见 [IntelligenceTask.cs](../launcher/src/Tasks/IntelligenceTask.cs) `RespondCatalog`/`RespondGlossaryCatalog`：纯 C# 读文件回包；仅存档运行态才 `RequestFlash`）。`PetTask` 当前是纯 Flash 透传，将改为：静态 `adopt_list` 走 C# 直答，其余（snapshot/adopt/deploy/advance…运行态）继续透传 Flash。
- **开放问题②（加载入口在 SWF 帧脚本）→ 无所谓。** 不涉及服务器/存档的类可只在 asLoader 内编译完成、主文件与其无关。Phase 2 的 `PetLibrary` 走 asLoader，无需重发布主 SWF。

### Phase 1 具体改动（store 静态数据 web 直连，三层协同）

`handleAdoptList`（[PetPanelService.as:255](../scripts/类定义/org/flashNight/arki/merc/PetPanelService.as#L255)）已确认 **100% 静态**——只读 `宠物商城列表` + `宠物库` 展示字段，零存档态。改动：

1. **C#（本次施工，可编译验证）**：
   - 新增 `launcher/src/Data/PetCatalogLoader.cs`：读 `data/merc/pets.xml` → 分类(name+网格行) + 宠物展示定义(by id)。
   - `PetTask`：新增 projectRoot 构造 + 懒加载目录缓存（仿 `IntelligenceTask.EnsureCatalogLoaded`）；`adopt_list` 改 **C# 直答** `{categories, adoptable}`（不经 Flash、不需 client ready——顺带消除"进店早于 snapshot 时页签空白"竞态）。其余 cmd 透传不变。
   - 单测 `PetTaskTests`：补 adopt_list 直答用例。
2. **JS（pet-panel.js）**：store 页分类改读 `adopt_list` 回包的 `categories`（存 `_storeCategories`），不再依赖 `_snapshot.categories`；删 [:299](../launcher/web/modules/pet-panel.js#L299) 的 snapshot 补渲染（已无意义）。
3. **AS2（去常驻）**：
   - `PetPanelService`：删 `handleAdoptList` + 注册（[:38](../scripts/类定义/org/flashNight/arki/merc/PetPanelService.as#L38)）；snapshot 去掉 `categories` 字段（[:221-239](../scripts/类定义/org/flashNight/arki/merc/PetPanelService.as#L221)）。
   - `加载并配置宠物信息`：停止解析 `<PetStore>`、不再写 `_root.宠物商城列表`（[:535-553](../scripts/通信/通信_fs_lsy_XML数据解析.as#L535)）→ 商城网格结构退出 AS2 常驻。
   - `宠物库` 仍保留（snapshot.petLib + 战斗用），Phase 2 处理。

> 验证状态：C# 编译 + 单测可在此环境验证；AS2 须 `compile_test.ps1` + 游戏内手测（进店分类/价格/领养逐项对照）；JS 须 browser harness。

---

## 9. 重要更正（2026-06-02，Phase 2 施工期复核）

实装 Phase 2 前逐一核对 `宠物库` 字段消费方，**推翻了 §1「战斗侧只读 3 字段」的前提**：

| 消费方 | 读取字段 | 性质 |
|---|---|---|
| 战宠系统 出战 | Identifier/Name/Height | 运行态 |
| 等级经验 | Name | 运行态 |
| **刷怪系统 计算可雇用敌人价格** ([:164](../scripts/逻辑/关卡系统/关卡系统_lsy_非人形佣兵刷新系统.as#L164)) | **Price/KPrice/IncreasePrice** | 运行态（漏看） |
| **handleAdopt 购买** ([:255](../scripts/类定义/org/flashNight/arki/merc/PetPanelService.as#L255)) | **Price/KPrice/IncreasePrice/InitialLevel/Unique**，且 `Price += IncreasePrice` 原地涨价 | 运行态（漏看） |

**结论：`宠物库` 是运行态权威的「经济+战斗」表，不是静态展示数据。** 仅 `UnlockLevel/UnlockTask` 是纯面板字段（且已由 C# adopt_list 承担）。瘦身只能省 2 个字段/宠物，且 `Price` 会被运行时改写——slim 投影既无意义又会破坏涨价语义。

**且 GC 收益本就微弱**：`宠物库` ≈110 个配置对象，pets.xml 中占 97.5%（PetStore 仅 2.5%，已 Phase 1 移除），但相对战斗期数千子弹/单位的堆，110 个常驻配置对象对 GC 扫描的压力可忽略。**故 Phase 2（宠物库去常驻）否决。**

### Phase 1 副作用（施工期发现，待定）
`宠物库.Price` 的 `IncreasePrice` 涨价是 **AS2 会话内** 改写（不入存档，重启复位）。Phase 1 后商城价格改由 C# 读 XML **基础价**——5 个 `IncreasePrice>0` 的宠物（学姐/重锤/精锐重装兵/精锐掠夺少女/试验体α）在本场购买后，商城显示价会停留在基础价（偏低）。**实际扣费仍正确**（handleAdopt 用 AS2 当前价校验+扣费），仅显示偏差。
- 修法（可选，小）：snapshot 携带 `priceOverrides:{petId:当前价}`（仅 `IncreasePrice>0` 且已涨价的宠物），web 商城网格叠加覆盖。约 AS2 +10 行 / JS +3 行。

### 「真·Phase 2」（petLib 移 C#）— ✅ 已施工（2026-06-02，C# 验证通过）
把 snapshot 的 `petLib`（110 宠全字段序列化，每次开面板分配一次）移到 C# `pet_lib` web 直答，减少开面板瞬时分配、统一价格源到 pets.xml。
- C#：`PetCatalogLoader` 重构为 typed `PetDef`（含 InitialLevel/IncreasePrice/Promotions），双投影 `ToAdoptJObject`(petId)/`ToLibJObject`(id)；`PetTask` 加 `pet_lib` web 直答（按 id 升序）。
- JS：`_petLib` session 缓存，开面板 `requestPetLib()` 拉一次；`getPetLibDef` 改读 `_petLib`（不再 `_snapshot.petLib`）。
- AS2：snapshot 删 `petLib` 序列化（不再遍历 `_root.宠物库` 下发全字段）。
- 验证：`PetCatalogTests` 10/10 通过。欠 AS2 `compile_test` + 游戏内进阶页手测。

### 涨价显示 — ✅ 已施工（持久模型，2026-06-02）
拍板「持久涨价」。实现避开了改 SaveManager/C# 的高风险存档管线，改用既有的存档预留命名空间：
- **存储**：`_root._saveExt.宠物购买次数 = {petId:次数}`。`_saveExt` 随 `mydata.ext` 往返（AS2 save :1226 / load :1480，`validateMydata` 不校验、C# `SaveMigrator` 不重建不剥离）——**零存档管线改动、零坏档风险**（最坏退化为不持久，不会坏档）。
- **权威价格函数**（引擎 `战宠系统.as`，主 SWF）：`_root.获取宠物当前售价(petId) = 基础价 + IncreasePrice×已购次数`。商城购买与刷怪雇佣价**同一口径**调它。
- **购买**（PetPanelService，asLoader）：`handleAdopt` 用该价校验+扣费，购买后 `incrementPetPurchaseCount`，**删除 `宠物库.Price += IncreasePrice` 的配置改写**（配置恢复只读=基础价）。`getPetCurrentPrice` 委托 `_root.获取宠物当前售价`（带 inline fallback 防 asLoader 早于主 SWF 的过渡期）。
- **显示**：snapshot 下发 `priceOverrides:{petId:当前价}`（仅 IncreasePrice>0 宠物）；JS `renderStoreGrid` 据此覆盖显示价 + 可购判定。
- **刷怪雇佣价耦合 = 有意设计（已保留并升级为持久）**：`IncreasePrice` 宠物买得越多，商城价**与**刷怪可雇用价同步越贵——抑制堆同质化战宠。旧实现靠改写配置 Price 在会话内联动；现 `计算可雇用敌人价格`（刷怪系统）改调 `_root.获取宠物当前售价`，联动从「会话内」升级为「持久」。
- 验证：JS 语法通过；欠 AS2 `compile_test`（主 SWF + asLoader 都要重发布）+ 游戏内手测：买涨价宠→商城价累积→重启仍保留→**刷怪可雇用价同步上涨**。

---

## 10. 进阶置灰回归修复（2026-06-04，玩家反馈触发）

玩家反馈「侦察队员到等级了，强化药剂仍灰、点不了」。排查后定位为 **web 迁移引入的回归 + 一处 pets.xml 填表错误**，与本方案的「数据权威迁移」同源，故记于此。

### 10.1 三件套 = 体质档进阶链（原设计澄清）

`战宠进阶函数`（`单位函数_aka_战宠进阶.as`）的 **基础训练→强化药剂→超级血清** 是一条共用计数器 `当前宠物属性.基础训练.次数`（1/2/3=各档完成）的链。三档 flavor 对应单位体质：基础训练=「体质较弱」、强化药剂=「中等」、超级血清=「较强」。

**关键：`进阶方案`（ctx）原设计是「该宠物自己的方案子集」，不是全局表。** pets.xml 每宠 `<Promotion>` 列表 = 它的**起步体质档**：
- 弱（狗狗）：含基础训练 → 从头练起；
- 中（侦察队员）：强化药剂+超级血清，**不含基础训练** → 从中档起步；
- 强（巨臂僵尸）：仅超级血清 → 直接注血清。

条件函数的守卫 `if(进阶方案.基础训练 && …)` / `if((进阶方案.基础训练 || 进阶方案.强化药剂) && …)` 的本意，是「**仅当本宠链里确有更低阶前置时才强制 `次数条件`**」——若 `进阶方案` 是全局表（恒含全部），这些 `&&` 守卫恒真，是废代码。战斗 `单位进阶执行`（`敌人模板迁移.as`）按 `次数==N || flag` 累加各档属性，故中体质宠只得强化+超级两档、**不白拿基础训练档**。

### 10.2 Bug：迁移误传全局表

`PetPanelService` 把 4 处 ctx 的 `进阶方案` 一律传了全局 `_root.战宠进阶函数` → 守卫恒真 → 中/强体质宠（promotion 缺基础训练）的强化药剂/超级血清**永久置灰，到等级也锁**。`isSchemeLocked` 独立犯同样的越权强制。全量扫描命中 **29 个中后期宠**（侦察队员/精锐突击/狙击/弹药/重装兵/黑铁三件/铁血战士小弟/学姐/重锤/Tomboy/… 详见排查），都是冷门晚主线宠，测试覆盖盲区。

### 10.3 修复（恢复 per-pet 子集，零新增状态/零平衡变更）

- `buildPetSchemeSet`/`filterSchemeSet`：构本宠 promotion 子集；4 处 ctx（`handleAdvance` 执行条件 / `handlePreviewAdvance` / `handleTooltip` / `buildSchemePerPetDesc`）改用子集 → 守卫对缺档宠正确短路。已核：条件/描述函数对缺失方案全部 `&&` 短路，安全。
- `isSchemeLocked` → `schemeLockReason`：返回 `""`/`"level"`/`"prereq"`，且**体质感知**——仅当本宠链有更低阶前置（基础训练/强化药剂）时才强制次数。
- JS `renderPromotions`：前置锁显「需先完成前置训练」，不再对已够级宠误显「需Lv.X」。
- 结果（逐宠 trace）：狗狗仍需先基础训练；侦察队员强化药剂直接可点→链推进→超级血清；巨臂僵尸直接注血清。无残留死链（无「超级血清+基础训练但缺强化药剂」形状）。

### 10.4 顺带：pets.xml 重复 `<id>107`

兽化变种/巨臂僵尸 都填了 `<id>107`，导致体育老师/电波 的 `<id>` 与**数组下标**错位。AS2 全程按数组下标（=战宠编号=`info[0]`）访问 `宠物库[idx]`、**从不读 `<id>`**，故旧全-AS2 体系无害；C# `PetCatalogLoader` 改按 `<id>` 键后会静默拿错宠物（getPetLibDef/adopt 投影）。已修正为 0..110 连续、`id==下标`，并在 loader 加重复 `<id>` 告警防回归。

**验证状态**：C# 编译通过、`PetCatalogTests` 5 绿；AS2 仅静态核验，欠 asLoader 重编译 + 游戏内手测（见 §10.3 三档抽查）。

---

## 7. 不在本方案范围
- 进阶方案逻辑/数值（`战宠进阶函数`）：留 AS2，见 2026-05-31 提案 B1。
- 宠物初始战斗属性（`敌人属性表[兵种]`）：另案，不动。
- JS 侧数据双写：已在 2026-05-31 提案删除（pet-data.js 已删）。
