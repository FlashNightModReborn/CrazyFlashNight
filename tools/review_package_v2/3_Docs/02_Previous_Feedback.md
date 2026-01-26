## 推荐方案

**推荐：把“嵌套路径”提升为一等公民，但仍然沿用现有的 `addProperty + PropertyAccessor + PropertyContainer` 体系，只是把 accessor 安装点从 `BuffManager._target` 改为“路径叶子节点所在对象”。再配套一个“绑定重建（rebind）”机制 + 数据驱动的级联触发调度。**

理由（结合你们现有代码结构）：

1. **最大化复用现有热路径优化与契约**
   你们当前体系的核心优势是：

   * `PropertyContainer` 只负责“buff计算”和“缓存脏标记”
   * `PropertyAccessor` 负责“惰性求值 + 缓存”并通过 `addProperty` 把属性变成透明计算属性（`obj.addProperty(propName, getter, setter)`）
     这套机制已经在 `PropertyContainer` 构造里绑定得很紧：
   * 构造时创建 `PropertyAccessor(target, propertyName, ...)`（`PropertyContainer.as` L78-L107）
   * 最终值读取是 `return Number(this._target[this._propertyName])`（L282-L284），依赖 accessor 生效
   * `BuffManager` 通过 `forceRecalculate()` 在脏属性上**主动触发计算**（`BuffManager.as` L1129-L1134），从而让 `onPropertyChanged` 能在“无人读取属性”的情况下也能触发

   所以最佳做法不是绕开 accessor（方案A原型那种每次 split/resolve 再读写），而是把 accessor 继续用起来，只是“挂到正确的对象上”。

2. **AS2 的 `addProperty()` 限制不是障碍：我们只需要接管叶子字段**
   你们的限制点是“不能跨对象链接管”（确实），但路径 `"长枪属性.power"` 的写入点本质在 `target.长枪属性` 对象上。
   也就是说：

   * 顶层属性：`target.addProperty("速度", ...)` ✅
   * 嵌套属性：`target.长枪属性.addProperty("power", ...)` ✅（只要解决**换装对象替换**）

3. **对象替换（换装）是关键，必须有 rebind**
   换装代码会直接替换整个对象：

   * `target[weaponKeys[equipKey]] = itemData.data`（`DressupInitializer.as` L181-L183）
     这会让旧对象上的 accessor 失效。
     推荐方案将 rebind 设计为 BuffManager 的职责（或至少 manager 统一调度），保证武器对象一旦替换，受影响的路径属性能自动重绑并触发一次强制重算，从而自然带出“刷新射击系统”的级联。

4. **级联触发（武器威力→初始化射击）不要靠散落 if-else，改成“规则表 + 帧内合并”**
   老系统是硬编码：`长枪威力` 变化就 `初始化长枪射击函数()`（旧 buff：`*buff.as` L395-L410）。
   新系统里你们已有 `onPropertyChanged` 回调接口（`PropertyContainer._computeFinalValue` 内触发，L160-L180），但需要：

   * 能对 `"长枪属性.power"` 这类路径名触发
   * **同一帧内**多次属性变化不要重复初始化（射击 init 可能不便宜）

结论：

> **“路径绑定 + rebind + 规则化级联调度”** 是在 AS2/性能/现有架构约束下，最可行且长期维护成本最低的路线。
> Pratt 解析器不适合做这件事（中文标识符、仅求值无赋值、且性能与复杂度都不划算）。

---

## 架构建议

下面是建议的结构改造点，尽量做到**改动集中、对现有一级属性完全兼容**。

### A. 引入“属性绑定（PropertyBinding）”概念，解耦 3 件事

你们当前 `PropertyContainer` 把下面三者合一了：

1. **属性标识符（用于容器 key / 触发回调）**：`_propertyName`
2. **buff 归属目标（用于 BuffContext.target）**：`_target`
3. **accessor 安装点（addProperty 的对象）**：也是 `_target`

这在一级属性成立，但嵌套路径里 **(2) 与 (3) 必须分离**：

* BuffContext.target 应该还是“角色对象”（root target）
* addProperty 必须装到 `target.长枪属性`（叶子所在对象）

**建议新增 `PropertyBinding`（或同名轻量结构）**：

```actionscript
class PropertyBinding {
    public var id:String;        // 例如 "长枪属性.power" (容器key/回调名)
    public var parts:Array;      // ["长枪属性", "power"]
    public var leafKey:String;   // "power"
    public var owner:Object;     // 当前解析到的叶子父对象：target.长枪属性
    public var root:Object;      // BuffManager._target
}
```

并提供：

* `resolveOwner(root:Object):Object`：遍历 parts[0..n-2] 得到 owner
* `readRaw():Number` / `writeRaw(v)`（可选）
* `needsRebind():Boolean`：检测 root 上链路对象是否变了（最低成本可只检测 parts[0]）

> **注意**：不要用 Pratt。你们 PrattLexer 的 identifier 只认 ASCII（`PrattLexer.as` 里 `_isAlpha/_isAlnum` 逻辑决定），且 PrattEvaluator 也没有赋值能力。把它拉进来只会让路径问题变复杂，不会更优。

### B. 改造 `PropertyContainer`：支持 “propertyId 与 accessorTarget 分离”

建议把 `PropertyContainer` 变成“吃 binding”的形态：

* 新字段（命名仅示意）：

  * `_propertyId:String`：完整路径/属性名（用于回调与 context.propertyName）
  * `_ownerTarget:Object`：角色对象（用于 BuffContext.target）
  * `_accessTarget:Object`：addProperty 安装点（一级=角色，嵌套=叶子父对象）
  * `_accessKey:String`：addProperty 字段名（一级=属性名，嵌套=leafKey）
  * `_binding:PropertyBinding`：用于 rebind

* 修改点（对应现有代码行）：

  * 构造里 `new BuffContext(this._propertyName, this._target, ...)`（`PropertyContainer.as` L92-L97）
    → 应变为 `BuffContext(this._propertyId, this._ownerTarget, ...)`
  * 构造里创建 accessor（L99-L107）
    → 目标对象与属性名改为 `_accessTarget` + `_accessKey`
  * `getFinalValue()`（L282-L284）
    → `return Number(this._accessTarget[this._accessKey]);`

这样你们一级属性完全不受影响：

* 一级属性：`_propertyId == _accessKey == propertyName`，`_ownerTarget == _accessTarget == target`

嵌套属性：

* `_propertyId = "长枪属性.power"`
* `_ownerTarget = BuffManager._target`
* `_accessTarget = _ownerTarget["长枪属性"]`
* `_accessKey = "power"`

### C. 在 BuffManager 中集中做“路径解析 + 容器创建”

你们现在 `ensurePropertyContainerExists` 是唯一入口（`BuffManager.as` L1293-L1321），目前只能：

* `raw = this._target[propertyName]`（L1310）
* `new PropertyContainer(this._target, propertyName, baseValue, ...)`（L1319）

建议升级为：

1. 若 propertyName 不含 `.`/`[`：走原逻辑
2. 若含 `.`：走 `PropertyBindingCache.get(propertyName)`，解析 parts，resolve owner，读取 owner[leafKey] 作为 baseValue
3. 创建 `PropertyContainer(ownerTarget=this._target, binding=...)`

同时维护一个列表/映射：

* `_pathContainers:Array`：所有需要 rebind 的容器
* 或 `_pathContainersByRootKey:Object`：按 parts[0] 分桶（便于更快重绑）

### D. rebind 机制：必须解决 “对象替换导致 accessor 丢失”

这是嵌套支持的硬需求。

#### 最推荐的 rebind 策略：**“轻量轮询检测 + 自动重绑”**

原因：

* 你们 `BuffManager.update()` 在 `_isDirty=false` 时不会做任何事（`BuffManager.as` L490-L518 只在 dirty 分支重分配）。
* 但换装（对象替换）通常**不一定会触发 BuffManager 的 dirty**，因为它是外部直接 `target.长枪属性 = ...`。
* 所以如果不加轮询/通知，buff 会继续绑在旧对象上，**新武器不会吃到 buff**。

建议：在 `update()` 开头加入一步：

```actionscript
// before processing dirty redistribution
_syncPathBindings(); // 若发现 owner 变化，执行 rebind + forceRecalculate
```

`_syncPathBindings()` 做的事：

1. 对每个 path container 检测 `binding.resolveOwner(root)` 是否与 container._accessTarget 相同
2. 若不同：

   * **解绑旧对象上的 accessor**（关键：避免内存泄漏/旧对象读到错值）
   * 更新 `_accessTarget` 指向新 owner
   * 用新对象上当前 raw 值作为新的 baseValue（非常关键）
   * 重建 PropertyAccessor（或提供 accessor.rebind 能力）
   * `forceRecalculate()` 触发一次计算与回调（你们现有机制会触发 `onPropertyChanged`）

> 这里“解绑旧对象”不要直接用 `PropertyAccessor.detach()`：
> `detach()` 会读取“当前可见值”（会触发 getter 计算）并固化为最终值（`PropertyAccessor.as` L190-L210）。
> **rebind 场景更想把旧对象恢复到 base，而不是把 buff 后的 final 写回去**，避免旧对象被复用时产生污染。
> 建议提供一个内部用的 `detachToBase(baseValue)`：直接 `delete oldOwner[key]; oldOwner[key] = baseValue;`，同时清理 accessor 引用。

#### 可选补充：显式通知接口（进一步减轻每帧检测）

如果你们特别敏感于每帧轮询（虽然通常数量很少），可以加一个显式接口：

* `buffManager.notifyObjectReplaced("长枪属性")`
* 或 `buffManager.syncAllPathBindings()`

然后在集中换装点调用一次：

* `DressupInitializer.loadEquipmentData()` 设置武器对象后（`DressupInitializer.as` L181-L183）
* `_root.长枪配置/_root.手枪配置` 这类入口（`*fs*.as` L5-L6 / L16-L18）

最稳妥的做法是：**轮询作为兜底 + 显式接口作为加速**。

### E. 级联触发：用“规则表 + 帧内合并”替代 if-else 硬编码

你们目前的 `onPropertyChanged` 粒度够用，但需要两点增强：

1. **属性名支持路径**（回调里能收到 `"长枪属性.power"`）
2. **同帧合并**：避免 `"长枪属性.power"` 和其他相关属性变化导致重复初始化

建议新增一个轻量 `CascadeDispatcher`（不必引入复杂事件系统）：

* 输入：`onPropertyChanged(propId, newValue)`
* 内部：

  * `propId -> groupId[]` 映射（O(1)）
  * `groupId -> action()`（例如初始化长枪射击函数）
  * 本帧 `dirtyGroups[groupId]=true`
* 每帧末（在你们主循环里，`buffManager.update()` 后）调用 `cascadeDispatcher.flush()`，对 dirtyGroups 执行动作一次

示意：

```actionscript
// 配置
dispatcher.map("长枪属性.power", "longGunReinit");
dispatcher.action("longGunReinit", function(){ target.man.初始化长枪射击函数(); });

// 回调
onPropertyChanged = function(propId, newVal){
    dispatcher.mark(propId);
}

// 帧末
dispatcher.flush();
```

这能复刻老系统语义（旧 buff：`初始化长枪射击函数()`，见 `*buff.as` L395-L410），但不需要散落硬编码。

> 你问的“是否需要属性依赖图”——在 AS2 里我建议不要上完整依赖图（复杂且收益不一定高）。
> 上面这种 **“分组依赖（group dependency）”** 就够覆盖“武器威力→刷新射击系统”“魔抗表重建→刷新护盾派生”等典型需求（你们 DressupInitializer 里就有一个类似通知：`shield.refreshStanceResistance()`，`DressupInitializer.as` L377-L380）。

---

## 实现路线图

按风险与收益拆成 4 个阶段，保证可回滚、不中断现有一级属性系统。

### Phase 1：只做“路径识别 + 叶子接管”，不做自动 rebind（先跑通）

1. `BuffManager.ensurePropertyContainerExists()` 增加 path 识别：若含 `.` 则解析 parts、resolve owner、读取 base（替换现有 `raw = this._target[propertyName]` 逻辑，见 `BuffManager.as` L1310）
2. 改造/新增 `PropertyContainer` 支持 `_propertyId` 与 `_accessTarget/_accessKey` 分离（保持一级属性不变）
3. 能成功：

   * `new PodBuff("长枪属性.power", ADD, 100)`
   * `buffManager.addBuff(...)` 后 `target.长枪属性.power` 读到 buff 后值（ShootInitCore 里读取 `weaponData.power` 会命中 accessor，见 `ShootInitCore.as` L444）

> 这个阶段先别碰换装重绑，只验证核心链路：解析→绑定→计算→写回（通过 accessor）→回调。

### Phase 2：加入 rebind（解决对象替换）

1. 新增 `_pathContainers` 记录所有 path 容器
2. 提供 `buffManager.syncAllPathBindings()`，在外部换装流程里手动调用
3. 让武器替换后，buff 能重新作用于新对象，并触发一次 `forceRecalculate()`（你们 `forceRecalculate()` 机制已成熟，见 `BuffManager.as` L1129-L1134 / `PropertyContainer.as` L289-L292）

### Phase 3：自动兜底（轮询检测）

1. 在 `BuffManager.update()` 开头加入 `_syncPathBindings()`（哪怕 `_isDirty=false` 也跑）
2. 若 rebind 发生：只对该容器 `forceRecalculate()`，并触发 `onPropertyChanged`，不必全量 dirty 重分配
3. 加入 DEBUG trace 统计：本帧重绑次数、耗时（trace 可剔除）

### Phase 4：级联调度与业务迁移

1. 上 `CascadeDispatcher`（规则表+帧末 flush）
2. 配置武器 power 的级联：

   * `"长枪属性.power" -> 初始化长枪射击函数`
   * `"手枪属性.power" -> 初始化手枪射击函数 + 初始化双枪射击函数`
   * `"手枪2属性.power" -> 初始化手枪2射击函数 + 初始化双枪射击函数`
     参考旧系统的行为（`*buff.as` L395-L420）
3. **迁移所有写入点**：把对这些被托管属性的 `+=` / `=` 改为 `buffManager.addBaseValue / setBaseValue`（见 `BuffManager.as` L1407-L1529）

   * 例如：`DressupInitializer.as` L338-L350 的 `power += 装备枪械威力加成`
   * 例如：`*fs*.as` L6/L17/L26 的 `power = 强化计算(power, lvl)`

---

## 风险与规避

### 1) `+=` 陷阱（最高风险，且你们已经在文档里明确）

**风险来源**：一旦 `power` 被 `addProperty` 接管，`power += x` 会变成：

* 读：getter → final
* 写：setter → base
  导致 base 漂移（你们 BuffManager.md 已写得很清楚）

**现有项目里确实存在大量写入点**，例如：

* 装备加成：`target.长枪属性.power += target.装备枪械威力加成`（`DressupInitializer.as` L341-L344）
* 强化：`人物.长枪属性.power = _root.强化计算(人物.长枪属性.power, 强化等级)`（`*fs*.as` L5-L6）

**规避策略**（推荐组合）：

1. **契约化**：把 `"长枪属性.power"` 等列入“托管属性白名单”，禁止对其直接 `+=`/`=`；统一用：

   * `buffManager.addBaseValue("长枪属性.power", delta)`
   * `buffManager.setBaseValue("长枪属性.power", newBase)`
2. **DEBUG 下强提示**：在 `PropertyContainer._createSetterFunction()` 里（setter 是唯一外部写入入口）加入：

   * 如果当前 `_buffs.length > 0` 且发生 setBaseValue，则 `trace("[WARN] Direct write to managed prop ...")`
     这不能阻止，但能快速定位遗留写入点（trace 可在发布时剔除）
3. **迁移优先级**：先迁移“写入点最少、影响最大”的武器 power，再扩展其他嵌套字段。

### 2) 对象替换导致 accessor 泄漏/错绑

**风险**：旧对象上如果不解绑，getter closure 会继续引用 container，造成：

* 内存泄漏（旧对象被其他引用持有时）
* 读到错误值（旧对象.power 读取时仍会走 buff 计算）

**规避**：rebind 必须做到：

* 在旧 owner 上 `delete power` 并恢复为 base 值（不要固化 final）
* 清理旧 accessor（避免 closure 持有 container）

### 3) 路径解析失败（对象链为 null/undefined）

AS2 读取链条不会抛异常（你们已强调），但**写回**可能出现 silent fail 或逻辑不生效。

**规避**（契约化 + 轻量防守）：

* 契约：path 指向的链路必须存在（至少在 buff 生效期内）
* 防守：resolveOwner 失败时容器进入“未绑定”状态，不做 addProperty；当链路恢复时 rebind 再绑定（配合 Phase 3 的轮询兜底）

### 4) 级联触发重复调用导致性能抖动

如果直接在 `onPropertyChanged` 里调用 `初始化长枪射击函数()`，同一帧多个属性变化会多次 init。

**规避**：用 `CascadeDispatcher` 帧末合并，保证每帧每个系统最多 init 一次。

---

## 性能考量

### 1) 路径解析开销

* **不要 Pratt**：中文标识符 + 仅求值无赋值 + 复杂度都不值
* **不要在每次读写 split**：解析应在容器创建时做一次（缓存 parts）
* 建议做一个 `PropertyPathCache`（`{pathString: partsArray}`），避免重复 split（虽然容器只建一次，但 cache 也便于调试与一致性）

### 2) rebind 检测的开销

推荐轮询兜底时做到“极低成本”：

* 对深度=2 的武器路径，只需比较：`current = target["长枪属性"]` 与 `container._accessTarget`
* 如果你们未来支持更深路径，再做逐段比较

即使每帧检查 10~30 个 path 容器，成本仍然远低于一次射击初始化/一次全量 buff 重分配。

### 3) 计算触发策略

你们现有策略已经很好：

* 只有 dirty 属性才 `forceRecalculate()`（`BuffManager.as` L1129-L1134）
* `PropertyAccessor` 有惰性缓存（`PropertyAccessor.as` L87-L120）

嵌套属性保持同样策略即可：

* rebind 时强制 `forceRecalculate()` 一次
* 其余仍走 dirty 驱动

---

## 其他建议

1. **对外 API：优先字符串路径，其次数组，回调不推荐**

   * 推荐：`"长枪属性.power"`

     * 你们已有以字符串作为 property key 的全套基础设施（`_propertyContainers[propertyName]`，`_dirtyProps[propertyName]` 等）
   * 可选：`["长枪属性","power"]`

     * 适合某些性能敏感或避免拼写错误的地方，但最终仍要 join 成 string 做 key
   * 不推荐：`function(target){...}`

     * AS2 闭包和函数调用开销更高、难缓存、难序列化/调试

2. **命名规范：把“路径属性”当作正式属性名**
   `onPropertyChanged(propId, newValue)` 里让 propId 直接是 `"长枪属性.power"`，别引入别名 `"长枪威力"`，否则你们会长期维护两套映射。

3. **迁移策略：先“武器 power 四件套”**
   你们明确未桥接的就是：

   * `长枪属性.power`
   * `刀属性.power`
   * `手枪属性.power`
   * `手枪2属性.power`
     这四个字段的级联也最明确（旧系统已有参考实现）。优先把这四个跑通，再扩展到更深层路径或更多字段。

4. **给业务侧一份“托管属性写入清单”**
   例如：

   * `DressupInitializer.updateProperties` 中的 `power +=`（L338-L350）
   * `_root.*配置` 中的 `power = 强化计算(...)`（`*fs*.as` L5-L6/L17-L18/L26-L27）
     迁移完成后再启用这些 path 属性的接管（或启用后必须保证这些写入已改造完毕）。

---


下面按你们当前文件结构，把“路径绑定 + rebind + 规则化级联”的推荐方案落到类/方法级的补丁设计清单（仅说明，不编码）。

0) 目标与约束（实现时必须守住）
保留现有一级属性完全兼容：propertyName 不含 . 时行为不变。
路径属性的 key 仍用字符串：容器 key / dirty key / 回调 propId 一律用 "长枪属性.power" 这种完整路径（不再维护 "长枪威力" 别名）。
继续复用 PropertyAccessor 热路径：不会在每次读写 split/resolve；解析只发生在“容器创建”和“rebind 检测”。
rebind 不允许使用 PropertyAccessor.detach()（它会固化 final）：见 PropertyAccessor.as (line 190)。
1) 新概念：把“root target”和“accessor 安装点”分离
对一级属性：

ownerTarget（BuffContext.target）= BuffManager._target
accessTarget（addProperty 安装点）= BuffManager._target
accessKey（被接管字段）= "atk" 等
对路径属性 "长枪属性.power"：

ownerTarget 仍是 BuffManager._target（用于 BuffContext.target）
accessTarget 变为 BuffManager._target["长枪属性"]
accessKey = "power"
propertyId（容器 key/回调名）= "长枪属性.power"
2) PropertyContainer 补丁级改造
文件：PropertyContainer.as

2.1 新增字段（最小侵入做法：在现有字段上补充）
在现有 _target/_propertyName 基础上新增：

_accessTarget:Object：真正 addProperty 的对象（一级= _target；路径= 叶子父对象）
_accessKey:String：真正被接管的字段名（一级= _propertyName；路径= "power"）
_bindingParts:Array（可选）：缓存 ["长枪属性","power"]，用于 rebind（避免每次 split）
_isBound:Boolean（可选）：_accessTarget != null
2.2 构造函数签名（建议“可选参数扩展”，不破坏现有调用）
现有构造：PropertyContainer(target, propertyName, baseValue, changeCallback)（见 PropertyContainer.as (line 78)）

建议扩展为：

仍保留前 4 个参数不变
追加可选参数：accessTarget:Object, accessKey:String, bindingParts:Array
用 arguments.length 做兼容分支：
未传 → _accessTarget = target; _accessKey = propertyName;
传了 → _accessTarget = accessTarget; _accessKey = accessKey; _bindingParts = bindingParts;
2.3 需要改动的方法（按“替换点”列出）
构造里创建 BuffContext：

现状：new BuffContext(this._propertyName, this._target, ...)（PropertyContainer.as (line 92)）
目标：propertyName 仍用完整 propertyId（可继续复用 _propertyName），target 仍用 root target
结论：这里不需要分离，只要保证 _propertyName 可以是 "长枪属性.power"。
构造里创建 PropertyAccessor：

现状：new PropertyAccessor(target, propertyName, ...)（PropertyContainer.as (line 99)）
目标：改为 new PropertyAccessor(_accessTarget, _accessKey, ...)
若 _accessTarget == null：不创建 accessor（容器进入“未绑定”状态），但仍保留 buff 列表和 base。
getFinalValue()：

现状：return Number(this._target[this._propertyName]);（PropertyContainer.as (line 282)）
目标：
已绑定：Number(_accessTarget[_accessKey])
未绑定：返回 _computeFinalValue()（让 forceRecalculate() 仍可触发回调，但不会写回对象）
_markDirtyAndInvalidate()：

现状无空判断：this._accessor.invalidate();（PropertyContainer.as (line 357)）
目标：若 _accessor==null 只置 _isDirty=true（无 invalidate）
2.4 新增 rebind 接口（核心）
新增一个只给 BuffManager 用的方法（命名示例）：

syncAccessTarget(newAccessTarget:Object, newRawBase:Number):Boolean
返回值：是否发生了绑定变化（便于 manager 决定要不要 forceRecalculate()）
rebind 时旧对象如何恢复 base（你点名要的细节）：
在 syncAccessTarget 内做以下顺序（关键是“先拆旧 accessor，再写回 base”）：

记录旧绑定：oldOwner=_accessTarget, oldKey=_accessKey, oldBase=_baseValue
若 _accessor 存在：先 accessor.destroy()（它会 delete oldOwner[oldKey]），再 oldOwner[oldKey]=oldBase
这样旧对象不会留下 getter 闭包，也不会固化 final
切换到新绑定：_accessTarget=newAccessTarget
baseValue 刷新为 newRawBase（必须取新对象 raw，避免把旧武器 base 带过去）
若新 _accessTarget != null：重建 PropertyAccessor(_accessTarget,_accessKey,...)
标脏并（若已绑定）invalidate
3) BuffManager 补丁级改造
文件：BuffManager.as

3.1 新增字段
_pathPartsCache:Object：{ "长枪属性.power": ["长枪属性","power"], ... }
_pathContainers:Array：保存“需要 rebind 的容器引用或其 propertyId”
（可选优化）_pathRoots:Object：{ "长枪属性": [container1,container2], ... }，减少每次扫描
3.2 修改 ensurePropertyContainerExists（唯一入口）
位置：BuffManager.as (line 1293)

改造点：

若 propertyName 不含 .：走现有逻辑不动（保持兼容）
若 含 .：
parts = cacheOrSplit(propertyName)
leafKey = parts[parts.length-1]
owner = resolveOwner(this._target, parts[0..len-2])（逐段判空，失败则返回 null owner）
baseValue = safeNumber(owner ? owner[leafKey] : undefined)
new PropertyContainer(this._target, propertyName, baseValue, this._onPropertyChanged, owner, leafKey, parts)
写入 _propertyContainers[propertyName]
把该容器加入 _pathContainers（并可按 parts[0] 分桶）
注意：这里的 PropertyContainer 第 1 个参数仍是 root target（用于 BuffContext.target），而不是 owner。

3.3 update() 插入 _syncPathBindings() 的具体位置
位置：BuffManager.as (line 470)（update 方法）

推荐插入点：在 try 内、_processPendingRemovals() 之后、_updateMetaBuffsWithInjection() 之前，即介于现有步骤 1 和 2 之间（参考当前结构 BuffManager.as (line 481)~BuffManager.as (line 486)）：

原因：
rebind 不是 dirty 驱动（换装直接替换对象引用，可能不触发 _isDirty），必须每次 update 都能跑到
放在重分发之前，可保证接下来 forceRecalculate() 读写的是新对象
3.4 新增 _syncPathBindings()（核心）
职责：检测 target["长枪属性"] 是否换了对象，若换了就触发对应容器的 syncAccessTarget()。

建议行为：

遍历 _pathContainers
对每个容器：
根据其 bindingParts resolve 新 owner
读取新 rawBase（safeNumber(owner[leafKey])）
changed = container.syncAccessTarget(owner, rawBase)
若 changed：container.forceRecalculate()（让 onPropertyChanged("长枪属性.power", newFinal) 自动触发）
兜底要求：resolveOwner 必须逐段判空，否则 AS2 会抛 “Cannot access property … of null/undefined”。

3.5 getBaseValue/setBaseValue/addBaseValue 的路径语义（补丁级说明）
位置：BuffManager.as (line 1445)

建议规则：

若 container 存在：保持现有（直接走 container）
若 container 不存在且是路径：
getBaseValue(path)：只做 raw 读（不要隐式创建容器，避免意外安装 addProperty）
setBaseValue(path,value)：resolve owner 后直接 owner[leafKey]=value（owner 不存在则忽略或缓存；你们可以选择“契约必须存在”）
addBaseValue(path,delta)：setBaseValue(path, getBaseValue(path)+delta)
3.6 unmanageProperty/destroy 需同步维护 _pathContainers
unmanageProperty(propertyName, ...)（BuffManager.as (line 573)）：销毁容器时，把它从 _pathContainers/分桶里移除
destroy()：清理所有容器时，同步清空 _pathContainers 缓存
4) 级联调度（武器威力→刷新射击）落地方式
目标：替代旧系统硬编码（见 主角模板数值buff.as (line 395)），避免同帧重复 init。

4.1 事件来源：onPropertyChanged
你们当前 BuffManagerInitializer 没有传 onPropertyChanged（BuffManagerInitializer.as (line 15)）。

补丁级建议：

在 createManager() 的 callbacks 里补上 onPropertyChanged(propId,newValue)，仅做“mark”，不直接 init。
4.2 flush 的位置（二选一）
方案 A（更符合“帧末合并”）：在 UpdateEventComponent 中 buffManager.update(4) 后调用 cascade.flush()
文件：UpdateEventComponent.as (line 88)
方案 B（让 addBuffImmediate → update(0) 也能触发级联）：在 BuffManager.update() 结束（_inUpdate=false 之后）调用 cascade.flush()
注意避免 flush 内再递归调用 update()
4.3 规则表最小集（先把四件套跑通）
"长枪属性.power" → target.man.初始化长枪射击函数()
"手枪属性.power" → 初始化手枪射击函数() + 初始化双枪射击函数()
"手枪2属性.power" → 初始化手枪2射击函数() + 初始化双枪射击函数()
"刀属性.power" → 通常无需射击 init（按你们旧逻辑）
射击 init 函数定义位置参考：单位函数_lsy_主角射击函数.as (line 23)

5) “写入点迁移清单”（否则必踩 读-final 写-base 漂移）
只要你开始接管 *.power，下面这些写法都会变成风险点（你当前 active tab 也命中）：

装备数值阶段的 +=：DressupInitializer.as (line 338)
强化/配置阶段的“读后写”：单位函数_fs_玩家装备配置.as (line 6)
主动战技直接改刀威力：单位函数_雾人_aka_fs_主动战技.as (line 1206)
补丁级迁移原则（实现时）：

所有对托管路径属性的 += / -= / x = f(x) 改为 buffManager.addBaseValue("刀属性.power", delta) 或 getBaseValue+setBaseValue（参见你们 BuffManager v2.9 API，BuffManager.as (line 1445)）。

---

## 6) 实现修正点（内部评审补充）

以下是对 GPT Pro 原方案的修正，实现时必须遵守：

### 6.1 getFinalValue() 未绑定状态的处理（严重）

**原方案问题**：
GPT Pro 建议"未绑定时返回 `_computeFinalValue()`"，但 `_computeFinalValue()` 内部会触发 `_changeCallback`（PropertyContainer.as L148-154）。
未绑定时不应该触发回调，否则会导致级联调度器收到通知并尝试初始化不存在的武器。

**修正方案**：
```actionscript
public function getFinalValue():Number {
    if (this._accessTarget != null) {
        // 已绑定：走 accessor（热路径）
        return Number(this._accessTarget[this._accessKey]);
    } else {
        // 未绑定：直接返回 base，不触发回调
        // 因为没有 accessor，buff 效果本来就无法体现在任何对象上
        return this._baseValue;
    }
}
```

### 6.2 _syncPathBindings() 性能优化（建议）

**原方案**：每次 update 都遍历 _pathContainers 检测引用变化。

**优化方案**：引入版本号快速路径
```actionscript
// BuffManager 新增字段
private var _pathBindingsVersion:Number = 0;
private var _lastSyncedVersion:Number = 0;

// 外部通知接口（换装时调用）
public function notifyPathRootChanged(rootKey:String):Void {
    _pathBindingsVersion++;
}

// _syncPathBindings 加快速路径
private function _syncPathBindings():Void {
    if (_lastSyncedVersion == _pathBindingsVersion) {
        return;  // 快速路径：版本未变，跳过
    }
    _lastSyncedVersion = _pathBindingsVersion;
    // 慢路径：实际检测...
}
```

**换装入口调用**：
```actionscript
// DressupInitializer.as L181-183 之后
buffManager.notifyPathRootChanged(weaponKeys[equipKey]);
```

### 6.3 CascadeDispatcher 防递归（严重）

**原方案问题**：
方案 B 在 `_inUpdate=false` 后调用 `flush()`，但 flush 内的 init 函数可能调用 `addBuffImmediate()`，
导致 `update(0)` → `flush()` → 递归。

**修正方案**：CascadeDispatcher 必须自己防递归
```actionscript
class CascadeDispatcher {
    private var _dirtyGroups:Object = {};
    private var _isFlushing:Boolean = false;

    public function flush():Void {
        if (_isFlushing) {
            return;  // 防递归：执行期间的新 dirty 等下一帧
        }
        _isFlushing = true;

        // 快照当前 dirty，清空后再执行
        var toFlush:Object = _dirtyGroups;
        _dirtyGroups = {};

        for (var groupId:String in toFlush) {
            var action:Function = _groupActions[groupId];
            if (action) action();
        }

        _isFlushing = false;
    }
}
```

---

## 7) 实现阶段划分

| 阶段 | 内容 | 风险 | 状态 |
|------|------|------|------|
| Phase 1 | PropertyContainer 字段分离 + BuffManager 路径识别 | 低 | ✅ 已完成 |
| Phase 2 | rebind 接口 + _syncPathBindings | 中 | ✅ 已完成 |
| Phase 3 | CascadeDispatcher + 规则表配置 | 低 | ✅ 已完成 |
| Phase 4 | 业务写入点迁移 | 高（需逐个验证） | ⏳ 待测试验证后推进 |

---

## 8) Phase 4 待迁移业务写入点清单

以下写入点在启用路径属性托管后必须迁移，否则会触发"读-final 写-base"漂移问题。

**【优先级说明】**
- P0: 高频调用，必须首批迁移
- P1: 装备/强化流程，影响数值正确性
- P2: 低频或边缘场景

### 8.1 装备加成（P1）

| 文件 | 行号 | 当前写法 | 迁移后写法 |
|------|------|----------|------------|
| DressupInitializer.as | L338-350 | `target.长枪属性.power += 装备枪械威力加成` | `buffManager.addBaseValue("长枪属性.power", 装备枪械威力加成)` |
| DressupInitializer.as | L341-344 | 同上（刀属性、手枪属性等） | 同上 |

### 8.2 强化系统（P1）

| 文件 | 行号 | 当前写法 | 迁移后写法 |
|------|------|----------|------------|
| 单位函数_fs_玩家装备配置.as | L5-6 | `人物.长枪属性.power = _root.强化计算(人物.长枪属性.power, 强化等级)` | `buffManager.setBaseValue("长枪属性.power", _root.强化计算(buffManager.getBaseValue("长枪属性.power"), 强化等级))` |
| 单位函数_fs_玩家装备配置.as | L16-18 | 同上（手枪属性） | 同上 |
| 单位函数_fs_玩家装备配置.as | L26-27 | 同上（刀属性） | 同上 |

### 8.3 主动战技（P2）

| 文件 | 行号 | 当前写法 | 迁移后写法 |
|------|------|----------|------------|
| 单位函数_雾人_aka_fs_主动战技.as | L1206 | 直接修改刀威力 | 需要具体分析上下文 |

### 8.4 级联触发规则配置（与 CascadeDispatcher 配套）

启用路径属性后，需要在 BuffManagerInitializer 中配置：

```actionscript
// 示例配置
cascadeDispatcher.map("长枪属性.power", "longGunReinit");
cascadeDispatcher.map("手枪属性.power", "pistolReinit");
cascadeDispatcher.map("手枪属性.power", "dualGunReinit");
cascadeDispatcher.map("手枪2属性.power", "pistol2Reinit");
cascadeDispatcher.map("手枪2属性.power", "dualGunReinit");

cascadeDispatcher.action("longGunReinit", function(){ target.man.初始化长枪射击函数(); });
cascadeDispatcher.action("pistolReinit", function(){ target.man.初始化手枪射击函数(); });
cascadeDispatcher.action("pistol2Reinit", function(){ target.man.初始化手枪2射击函数(); });
cascadeDispatcher.action("dualGunReinit", function(){ target.man.初始化双枪射击函数(); });
```

### 8.5 换装入口通知点

需要在换装代码中添加 `notifyPathRootChanged` 调用：

| 文件 | 行号 | 位置说明 |
|------|------|----------|
| DressupInitializer.as | L181-183 之后 | `target[weaponKeys[equipKey]] = itemData.data` 后调用 |

```actionscript
// 在 target[weaponKeys[equipKey]] = itemData.data 之后添加
buffManager.notifyPathRootChanged(weaponKeys[equipKey]);
```

---

## 9) 测试验证清单

在推进 Phase 4 之前，必须通过以下测试：

### 9.1 基础功能测试
- [ ] 一级属性 buff 添加/移除/计算（回归测试，确保未破坏）
- [ ] 路径属性创建容器（`ensurePropertyContainerExists("长枪属性.power")`）
- [ ] 路径属性 buff 添加/移除/计算
- [ ] 路径属性 getFinalValue() 正确返回

### 9.2 rebind 测试
- [ ] 对象替换后 `_syncPathBindings()` 检测到变化
- [ ] rebind 后旧对象恢复 base 值（不是 final）
- [ ] rebind 后新对象 accessor 正确安装
- [ ] `notifyPathRootChanged()` 触发版本号递增

### 9.3 边界条件测试
- [ ] 路径解析失败（中间对象为 null）→ 容器进入未绑定状态
- [ ] 未绑定状态 `getFinalValue()` 返回 `_baseValue`，不触发回调
- [ ] 重复 rebind 到同一对象 → 返回 false，无操作

### 9.4 CascadeDispatcher 测试
- [ ] `map()` / `action()` 配置正确
- [ ] `mark()` 标记 dirty
- [ ] `flush()` 执行动作且帧内只执行一次
- [ ] `flush()` 防递归（嵌套调用不重入）

### 9.5 性能测试
- [ ] 无换装时 `_syncPathBindings()` 快速路径跳过
- [ ] 路径缓存 `_pathPartsCache` 命中