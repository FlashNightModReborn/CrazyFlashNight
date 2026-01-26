# ActionScript 2.0 Buff系统级联属性支持 - 架构设计审查

## 审查请求

请对附件中的Buff系统进行架构级评审，重点关注**让Buff系统支持嵌套/级联属性路径**（如 `"长枪属性.power"`）的设计方案。我们需要专家级意见来评估实现可行性、架构影响和最佳实践。

---

## 技术背景

**语言：** ActionScript 2.0 (Flash Player 32)

### AS2语言特性（重要认知校正）

**容错机制：**
- AS2对无效引用**极其宽容**，访问`null`或`undefined`的属性**不会抛出异常**，只会静默返回`undefined`
- 例如：`obj.foo.bar.baz` 即使`obj`为`null`也不会报错，整个表达式返回`undefined`

**性能约束（核心设计原则）：**
- AS2的执行性能**仅为AS3或现代JavaScript的约1/10**
- **任何设计决策都必须将性能作为最高优先级**
- 无法承受的运行时安全检查必须通过**契约化设计**转嫁给调用方

**关键语言限制：**
- **`addProperty()` 只能接管某个对象的某个属性名，无法跨对象链**
- 无原生`Map`、`Set`——只有`Object`（哈希表）和`Array`
- 无`const`、无块级作用域——只有函数作用域的`var`
- 单线程、事件驱动执行模型
- 帧驱动游戏循环（通常30 FPS）

**调试代码处理：**
- `trace()`语句在SWF编译时**可配置自动剔除**，不构成性能问题

---

## 核心问题陈述

### 当前系统能力边界

1. **BuffManager/PropertyContainer 当前只支持一级属性**
   - `BuffManager` 读写 target 都是 `this._target[propertyName]` 这一层
   - `PropertyContainer` 的最终值读取也是 `this._target[this._propertyName]`
   - `PropertyAccessor` 只做 `obj.addProperty(propName, ...)`，天然只"接管某个对象的某个字段"，不理解"路径"

2. **现有嵌套属性处理方式（老buff系统）**
   ```actionscript
   // 老系统直接操作嵌套属性
   this.自机.长枪属性.power = 基础值 * 倍率 + 加算;
   this.自机.刀属性.power = ...;
   this.自机.手枪属性.power = ...;
   ```

3. **当前桥接状态**
   - ✅ 已桥接到BuffManager的简单属性：`空手攻击力`, `伤害加成`, `防御力`, `韧性系数`, `内力`, `速度`
   - ❌ 嵌套属性未桥接：`长枪属性.power`, `刀属性.power`, `手枪属性.power`, `手枪2属性.power`

### 期望的目标形态

```actionscript
// 期望能够这样使用
var podBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 100);
buffManager.addBuff(metaBuff, "长枪威力增幅");

// BuffManager 内部自动：
// 1. 解析路径 "长枪属性.power"
// 2. 读取 target.长枪属性.power 作为 base 值
// 3. 应用 buff 计算
// 4. 写回 target.长枪属性.power
```

---

## 需要解决的核心挑战

### 挑战 1：路径解析与访问

**问题：** 如何将字符串路径 `"长枪属性.power"` 转换为实际的读写操作？

**现有技术储备：Pratt解析器**
- 项目中有完整的Pratt表达式解析系统（PrattLexer/PrattParser/PrattExpression）
- 已支持属性访问（`.`运算符）和数组访问（`[]`运算符）
- **但**：Lexer的标识符只认ASCII字母，中文标识符（如`长枪属性`）不会被识别为`IDENTIFIER`
- **但**：Pratt是表达式求值器，没有赋值运算，对"路径写入/接管"帮助有限

**备选方案：简单 `split(".")` 路径分割**
```actionscript
function resolvePath(target, path) {
    var parts = path.split(".");
    var obj = target;
    for (var i = 0; i < parts.length - 1; i++) {
        obj = obj[parts[i]];
    }
    return {parent: obj, key: parts[parts.length - 1]};
}
```

### 挑战 2：AS2 的 addProperty 限制

**问题：** `addProperty()` 只能在**单个对象**上为**单个属性名**安装 getter/setter，无法跨越对象链。

**具体限制：**
```actionscript
// ✅ 可行：接管 target.速度
target.addProperty("速度", getter, setter);

// ❌ 不可行：无法直接接管 target.长枪属性.power
// 因为 power 属于 长枪属性 对象，不属于 target
```

**潜在解决思路：**
1. 在 `target.长枪属性` 对象上安装 accessor（而非 target 上）
2. 不使用 addProperty，改用显式的 get/set 方法调用
3. 混合方案：顶层属性用 addProperty，嵌套属性用路径解析

### 挑战 3：对象链会被替换

**问题：** 玩家换装/换武器会直接把 `人物.长枪属性 = ...data` 整个对象替换掉。

```actionscript
// 换装时的典型代码
人物.长枪属性 = 新武器数据;  // 整个对象被替换
```

**影响：**
- 如果 accessor 挂在旧的 `长枪属性` 对象上，换装后立刻失效
- 需要机制来处理"父对象替换时自动重绑"或"换装前 reset BuffManager"

### 挑战 4：+= 陷阱会扩散到嵌套字段

**问题：** 现有代码对 `*.power` 有大量 `+=` 操作。

```actionscript
// 装备加成、技能临时改值等场景
武器属性.power += 装备加成;
武器属性.power += 技能临时效果;
```

**一旦 power 被接管（安装getter/setter）：**
- `武器属性.power += 100` 变成 `读final值` + `写base值`
- 导致"读final写base"的漂移风险（BuffManager文档已明确列为高风险）

### 挑战 5：级联触发（最关键）

**问题：** 武器威力变化后必须刷新射击系统，否则子弹属性是旧值。

**当前射击框架机制：**
- 子弹威力是初始化时**一次性算好**并缓存到 `target.子弹属性`
- 开火热路径**不重算**（性能优化）
- 所以武器威力的 buff 想实时生效，仍然需要"级联触发"

**老系统的做法：**
```actionscript
// 主角模板数值buff.as 第395-410行
if (属性名 == '长枪威力') {
    this.自机.长枪属性.power = this.基础值.长枪威力 * 倍率 + 加算;
    if(this.自机.man.初始化长枪射击函数){
        this.自机.man.初始化长枪射击函数();  // 级联触发
    }
}
```

**即便解决了嵌套接管，仍需级联：**
- buff 改了 `长枪属性.power` 也不会立即体现在 `target.子弹属性.子弹威力` 上
- 除非：开火时重算 或 在 `onPropertyChanged` 回调里刷新射击系统

---

## 现有系统架构

### BuffManager 体系结构

```
BuffManager
├── _target: Object                    // 宿主对象（如玩家单位）
├── _propertyContainers: Object        // {属性名: PropertyContainer}
├── _buffs: Array                      // 所有Buff（MetaBuff + 独立PodBuff）
└── 核心方法
    ├── addBuff(buff, buffId)          // 添加Buff
    ├── removeBuff(buffId)             // 移除Buff
    ├── update(deltaFrames)            // 每帧更新
    └── ensurePropertyContainerExists(propertyName)  // 确保容器存在

PropertyContainer
├── _target: Object                    // 目标对象
├── _propertyName: String              // 属性名（当前只支持一级）
├── _baseValue: Number                 // 基础值
├── _buffs: Array                      // 影响此属性的PodBuff列表
├── _accessor: PropertyAccessor        // 属性访问器（getter/setter）
└── 核心方法
    ├── addBuff(buff)                  // 添加Buff到此属性
    ├── getFinalValue()                // 获取最终计算值
    └── setBaseValue(value)            // 设置基础值

PodBuff
├── _targetProperty: String            // 目标属性名（当前是简单字符串）
├── _calculationType: String           // 计算类型（ADD/MULTIPLY/PERCENT/OVERRIDE）
├── _value: Number                     // Buff值
└── applyEffect(calculator, context)   // 应用效果
```

### Pratt 解析系统（技术储备）

```
PrattLexer
├── 词法分析，将源码分解为Token流
├── 支持：数字、字符串、标识符、运算符
├── T_DOT (".") 属性访问运算符
└── **限制：标识符只认ASCII字母**

PrattParser
├── 语法分析，构建AST
├── registerInfix(".", propertyAccess())  // 已支持属性访问
└── registerInfix("[", arrayAccess())     // 已支持数组访问

PrattExpression
├── PROPERTY_ACCESS 类型
├── evaluate(context) 递归求值
└── _evaluatePropertyAccess()
    return objVal[property];  // 支持级联访问

PrattEvaluator
├── createForBuff() 工厂方法
├── 内置Buff专用函数（SET_BASE, ADD_FLAT等）
└── **限制：只支持读取，无赋值运算**
```

### Property 访问系统

```
PropertyAccessor
├── obj.addProperty(propName, getter, setter)
├── 惰性求值 + 缓存优化
├── invalidate() 使缓存失效
└── **限制：只能接管某个对象的某个属性名**
```

---

## 代码结构

```
BuffSystem/                            # Buff系统核心
├── Core/
│   ├── BuffManager.as                 # Buff管理器 v2.9
│   ├── PropertyContainer.as           # 属性容器 v2.5
│   ├── PodBuff.as                     # 最小Buff单元
│   ├── MetaBuff.as                    # 组合Buff
│   ├── BaseBuff.as                    # Buff基类
│   ├── IBuff.as                       # Buff接口
│   ├── BuffCalculator.as              # Buff计算器
│   ├── IBuffCalculator.as             # 计算器接口
│   ├── BuffCalculationType.as         # 计算类型枚举
│   ├── BuffContext.as                 # Buff上下文
│   └── StateInfo.as                   # 状态信息
├── Component/                         # Buff组件
│   ├── IBuffComponent.as
│   ├── TimeLimitComponent.as          # 限时组件
│   ├── StackLimitComponent.as         # 叠加限制
│   ├── ConditionComponent.as          # 条件组件
│   ├── TickComponent.as               # 周期组件
│   ├── CooldownComponent.as           # 冷却组件
│   ├── DelayedTriggerComponent.as     # 延迟触发
│   └── EventListenerComponent.as      # 事件监听
└── Docs/
    └── BuffManager.md                 # 设计文档

PrattParser/                           # 表达式解析系统（技术储备）
├── PrattLexer.as                      # 词法分析器
├── PrattParser.as                     # 语法分析器
├── PrattExpression.as                 # AST节点/求值
├── PrattEvaluator.as                  # 求值器
├── PrattToken.as                      # Token定义
└── PrattParselet.as                   # 解析策略

Property/                              # 属性访问系统
├── PropertyAccessor.as                # 属性访问器
├── IProperty.as                       # 属性接口
└── BaseProperty.as                    # 属性基类

Business/                              # 业务代码（受影响模块）
├── 主角模板数值buff.as                 # 老Buff系统（级联实现参考）
├── ShootInitCore.as                   # 射击初始化（子弹威力缓存）
├── WeaponFireCore.as                  # 武器开火（热路径）
├── DressupInitializer.as              # 换装初始化（对象替换）
├── 单位函数_lsy_主角射击函数.as         # 射击函数初始化
└── 单位函数_fs_玩家装备配置.as          # 装备配置（对象替换）
```

---

## 待评审的设计方案

### 方案 A：扩展 PropertyContainer 支持路径

**思路：** 在 PropertyContainer 层面增加路径解析能力

```actionscript
// 新增 NestedPropertyContainer
class NestedPropertyContainer extends PropertyContainer {
    private var _pathParts:Array;      // ["长枪属性", "power"]
    private var _parentRef:Object;     // 父对象引用

    function resolveParent():Object {
        var obj = _target;
        for (var i = 0; i < _pathParts.length - 1; i++) {
            obj = obj[_pathParts[i]];
        }
        return obj;
    }

    function getBaseValue():Number {
        var parent = resolveParent();
        return parent[_pathParts[_pathParts.length - 1]];
    }

    function setFinalValue(value):Void {
        var parent = resolveParent();
        parent[_pathParts[_pathParts.length - 1]] = value;
    }
}
```

**优点：** 改动集中，向后兼容
**缺点：** 无法使用 addProperty 接管，每次读写都需路径解析

### 方案 B：Pratt 解析器路径求值

**思路：** 利用 Pratt 的 PROPERTY_ACCESS 求值能力

**问题：**
- 中文标识符不被识别
- 只支持读取，不支持赋值
- 需要修改 Lexer 或使用 `["中文"]` 下标语法

### 方案 C：显式级联组件

**思路：** 不改变 BuffManager，通过 CascadeComponent 在 onPropertyChanged 回调中处理

```actionscript
// WeaponCascadeComponent
class WeaponCascadeComponent {
    function onPropertyChanged(propName, newValue) {
        if (propName == "长枪威力") {
            target.长枪属性.power = newValue;
            target.man.初始化长枪射击函数();
        }
    }
}
```

**优点：** 最小改动，与老系统兼容
**缺点：** 需要为每个嵌套属性写级联逻辑，维护成本高

### 方案 D：代理对象模式

**思路：** 为嵌套对象创建代理，在代理上安装 accessor

```actionscript
// 创建长枪属性的代理
var 长枪属性代理 = new PropertyProxy(target.长枪属性);
target.长枪属性 = 长枪属性代理;
长枪属性代理.addProperty("power", powerGetter, powerSetter);
```

**问题：** 换装时对象被替换，代理失效

---

## 审查重点

请**独立评估**以下方面：

### 1. 架构可行性

- 哪种方案在AS2的限制下最可行？
- 是否有我们未考虑到的更好方案？
- 路径解析应该在哪个层级进行（BuffManager/PropertyContainer/PodBuff）？

### 2. 性能影响

- 路径解析的性能开销是否可接受？
- 是否需要缓存路径解析结果？
- 对热路径（如 update() 每帧调用）的影响？

### 3. 级联触发设计

- 如何优雅地处理"武器威力变化→刷新射击系统"的级联需求？
- onPropertyChanged 回调的粒度是否足够？
- 是否需要引入"属性依赖图"的概念？

### 4. 对象替换处理

- 换装时整个武器对象被替换，buff 如何处理？
- 是否需要"换装前清理，换装后重建"的机制？
- 有没有更透明的自动重绑方案？

### 5. += 陷阱防护

- 如何防止或警告"读final写base"的漂移风险？
- 是否应该禁止对被托管属性使用 +=？
- 提供专用 API（如 addBaseValue）是否足够？

### 6. API 设计

- 用户应该如何指定嵌套路径？
  - 字符串形式 `"长枪属性.power"`？
  - 数组形式 `["长枪属性", "power"]`？
  - 回调形式 `function(target) { return target.长枪属性.power; }`？

### 7. 向后兼容性

- 现有的简单属性 buff 是否不受影响？
- 老系统（主角模板数值buff）的迁移路径？

---

## 输出格式

请按以下结构组织你的评审意见：

```
## 推荐方案
[你认为最佳的实现方案及其理由]

## 架构建议
[对整体架构的建议，包括需要新增的类、修改的类、接口设计]

## 实现路线图
[建议的分阶段实现步骤]

## 风险与规避
[潜在风险及其规避措施]

## 性能考量
[性能优化建议]

## 其他建议
[任何其他值得关注的点]
```

---

## 审查原则

- **深入细致：** 仔细阅读代码，理解现有系统的设计意图
- **具体明确：** 引用实际代码，而非泛泛而谈
- **务实导向：** 关注在AS2约束下真正可行的方案
- **性能意识：** 任何建议都要考虑AS2的性能约束

**请特别注意：**
1. AS2 的 `addProperty()` 限制是硬性约束，无法绕过
2. 性能是最高优先级，不能为了架构优雅牺牲性能
3. 级联触发是必须的功能需求，不是可选优化
4. 换装时的对象替换是现有业务逻辑，改动成本极高

---

## 附件清单

| 目录 | 文件数 | 说明 |
|------|--------|------|
| BuffSystem/Core/ | 11个 | Buff系统核心实现 |
| BuffSystem/Component/ | 8个 | Buff组件 |
| BuffSystem/Docs/ | 1个 | BuffManager设计文档 |
| PrattParser/ | 6个 | 表达式解析系统（技术储备） |
| Property/ | 3个 | 属性访问系统 |
| Business/ | 6个 | 受影响的业务代码 |

**总计约35个文件**

---

## 背景补充：为什么需要支持嵌套属性

游戏中存在大量"武器威力buff"的需求场景：
- 技能效果：+20% 长枪威力持续10秒
- 装备属性：+100 手枪威力
- 状态效果：-30% 所有武器威力（debuff）

当前实现方式是通过老buff系统硬编码处理，维护成本高且无法享受新BuffManager的优势（如自动生命周期管理、buff叠加计算、状态机等）。

统一到新系统后的期望收益：
1. 统一的Buff管理API
2. 自动的buff冲突处理和叠加计算
3. 可视化的buff状态调试
4. 更低的维护成本
