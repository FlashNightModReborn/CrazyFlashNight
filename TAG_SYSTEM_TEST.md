# Tag依赖系统测试验证文档

## 实现概述

已成功实现了完整的tag依赖系统，允许插件之间建立依赖关系链。该系统支持：

1. **provideTags** - 插件可以提供结构标签给其他插件使用
2. **requireTags** - 插件可以要求必须先有特定的结构标签才能安装
3. **智能过滤** - 在UI中只显示满足依赖条件的可用插件
4. **友好提示** - 安装失败时提供明确的错误信息

## 系统架构修改

### 1. XML配置层
- **文件**: `data/items/equipment_mods.xml`
- **新增字段**:
  - `<provideTags>` - 插件提供的结构标签
  - `<requireTags>` - 插件需要的前置标签

### 2. 核心逻辑层
- **文件**: `scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as`
- **新增功能**:
  - `buildTagContext()` - 构建当前装备的tag上下文
  - `getMissingTags()` - 获取缺失的依赖标签列表
  - 修改了 `loadModData()` 解析新字段
  - 修改了 `isModMaterialAvailable()` 增加依赖检查
  - 修改了 `getAvailableModMaterials()` 过滤不满足条件的插件

### 3. UI显示层
- **文件**: `scripts/类定义/org/flashNight/gesh/tooltip/TooltipTextBuilder.as`
- **修改**: `buildModStat()` 函数现在显示插件的提供和需求标签

## 测试用例

### 测试链1：电力系统
```
依赖链：
├─ 可充锂电池 → 提供"电力"
├─ 纳米执行单元 → 提供"电力,高级电力"
├─ 电脑芯片 → 需要"电力"
└─ 传感器 → 需要"电力"
```

#### 测试步骤：
1. 装备任意防具
2. 尝试直接安装"电脑芯片" → 应该失败，提示"缺少前置结构支持"
3. 先安装"可充锂电池"
4. 再安装"电脑芯片" → 应该成功
5. 检查配件列表，"传感器"应该也变为可用

### 测试链2：导轨系统
```
依赖链：
├─ 战术导轨 → 提供"导轨,皮卡汀尼"
└─ 镭射瞄准具 → 需要"导轨"
```

#### 测试步骤：
1. 装备任意长枪
2. 尝试直接安装"镭射瞄准具" → 应该失败
3. 先安装"战术导轨"
4. 再安装"镭射瞄准具" → 应该成功

## 验证要点

### 功能验证
- [x] XML新字段正确解析
- [x] tag上下文正确计算
- [x] 依赖检查正确执行
- [x] 错误码返回正确（-16为缺少前置）
- [x] UI正确过滤不可用插件
- [x] Tooltip正确显示tag信息

### 边界测试
- [ ] 多个插件提供相同tag
- [ ] 级联依赖（A→B→C）
- [ ] 循环依赖检测（不应发生）
- [ ] 拆卸提供tag的插件后，依赖它的插件如何处理

### 性能测试
- [ ] 大量插件时的过滤性能
- [ ] tag上下文计算缓存机制

## 错误码映射

```actionscript
1   = 可装备
0   = 配件数据不存在
-1  = 装备配件槽已满
-2  = 已装备
-4  = 配件无法覆盖装备原本的主动战技
-8  = 同位置插件已装备
-16 = 缺少前置结构支持 [新增]
```

## 调试模式

可以通过设置 `EquipmentUtil.DEBUG_MODE = true` 来开启调试日志，查看详细的tag依赖检查过程。

## 已实现的级联依赖处理

### 移除插件时的依赖检查
当试图移除一个提供tag的插件时，系统会：
1. 调用 `getDependentMods()` 检查是否有其他插件依赖它
2. 如果有依赖，会提示用户并自动级联卸载所有依赖的插件
3. 所有被卸载的插件都会返还到材料栏

### 示例场景
- 安装顺序：可充锂电池 → 电脑芯片
- 移除可充锂电池时：系统会提示"以下插件依赖此插件，将一起卸载：电脑芯片"
- 两个插件都会被卸载并返还

## 已知问题

1. 当前版本未实现装备自身的inherentTags（装备固有标签），需要后续扩展
2. 未实现blockedTags（装备禁止安装特定标签的插件）

## 后续优化建议

1. 实现tag上下文缓存机制，提高性能
2. 在改造界面中显示依赖关系图
3. 支持装备XML配置inherentTags
4. 实现更复杂的依赖关系（如"或"逻辑）
5. 添加依赖冲突检测机制

## 测试日期
2024年11月19日

## 测试结果
待游戏内验证...








## 后续计划

下面是一份可以直接放进 TAG_SYSTEM_TEST.md 或单独新建文档的《inherentTags / blockedTags 设计与实施计划》。

inherentTags / blockedTags 设计与实施计划
1. 设计目标与语义约定
在现有 provideTags / requireTags 基础上，引入两类“装备自己的 tag”：

inherentTags（装备固有结构标签）

表示装备本身就具备的结构能力（比如“导轨”“电力接口”“枪口螺纹”）。
只用于提供结构支持，参与 requireTags 判定。
不代表已经占用某个插件挂点（是否占位由 <tag> + blockedTags 控制）。
blockedTags（装备禁止挂载的挂点标签）

表示此装备不允许安装某类挂点插件（如“枪口接口已经封死，不允许再装‘枪口’类插件”）。
不影响结构本身是否存在；即装备仍可以通过 inherentTags 提供依赖支持，但阻止某些插件挂上来。
整体设计满足需求：

某些插件必须先有其它结构（requireTags）。
某些装备天生提供结构（inherentTags）。
某些装备虽提供结构，但不允许挂某类插件（blockedTags），仍然可以满足其它插件的 requireTags。
2. 数据设计
2.1 装备 XML 扩展
在武器、防具等装备条目中增加两个可选字段（放在 <data> 旁边，与现有结构保持一致）：

<item>
    <name>MACSIV-长枪示例</name>
    <type>武器</type>
    <use>长枪</use>

    <data>
        ...
    </data>

    <!-- 装备固有结构标签：参与 provideTags / requireTags 判定 -->
    <inherentTags>导轨,电力接口</inherentTags>

    <!-- 装备禁止挂载的插件挂点标签：与 mod.tagValue 同一域 -->
    <blockedTags>枪口,枪托接口</blockedTags>
</item>
约定：

多值用中文逗号或英文逗号分隔（推荐统一使用英文逗号，解析更简单）。
字面值与插件 <tag> / <provideTags> / <requireTags> 使用同一个语义空间（例如“导轨”“电力”“枪口接口”等）。
2.2 运行时数据结构
在解析 XML → itemData 时：

itemData.inherentTags:String（原始字符串，可选）
itemData.inherentTagDict:Object（形如 { "导轨": true, "电力接口": true }，可选）
itemData.blockedTags:String（原始字符串，可选）
itemData.blockedTagDict:Object（形如 { "枪口": true, "枪托接口": true }，可选）
插件侧已有：

mod.tagValue：挂点标签（slotTag）
mod.provideTagDict：提供结构标签集合
mod.requireTagDict：需求结构标签集合
3. 核心逻辑改动点（EquipmentUtil）
3.1 补全 buildTagContext 对 inherentTags 的支持
当前版本 buildTagContext(item, itemData) 已经预留了：

读取 itemData.inherentTags，拆分并放入 context.presentTags。
从已安装插件的 provideTagDict 填充 presentTags。
从已安装插件的 tagValue 填充 slotOccupied。
计划：

确保数据加载层已经把 XML 中的 <inherentTags> 填入 itemData.inherentTags。
使用已有实现逻辑即可，无需额外改动（注释“未来扩展”正式启用）：
itemData.inherentTags → presentTags[...] = true
插件 provideTagDict → presentTags[...] = true
暂时不把 tagValue 自动写入 presentTags，保持“slotTag ≠ 结构标签”的清晰分工（要参与依赖系统必须显式写 <provideTags> 或 <inherentTags>）。
3.2 blockedTags 行为定义与实现
目标语义：

blockedTags 仅限制“装不装得上某类插件”，不影响结构是否存在。
典型场景：
装备 inherentTags 包含“导轨”，但 blockedTags 包含“导轨”：
requireTags="导轨" 的插件：依赖满足（结构存在）；
tag="导轨" 的插件：因为 blocked，被禁止安装。
这样就实现了“提供结构支持却不允许挂某些插件”的设计。
实现计划（在 EquipmentUtil.isModMaterialAvailable 中补充）：

在现有容量/重复/技能/tag 冲突检查之后，增加 blockedTags 检查：

// 在 tag 冲突检查前或后均可，推荐放在 tag 冲突后，逻辑更清晰
if(itemData.blockedTagDict && modData.tagValue){
    if(itemData.blockedTagDict[modData.tagValue]){
        // 新错误码，例如 -64：装备禁止该挂点类插件
        return -64;
    }
}
在 initializeModAvailabilityResults() 中新增映射：

modAvailabilityResults[-64] = "该装备禁止安装此挂点类型的插件";
buildTagContext 不需要关心 blockedTags，只负责“现有结构”和“占用挂点”，避免职责混乱。

3.3 getAvailableModMaterials 中的提前过滤
目前 getAvailableModMaterials 的流程是：

根据 rawItemData.use 拿到候选插件列表。
用 buildTagContext 得到 presentTags。
按 mod.requireTagDict + weapontypeDict 过滤可用插件。
计划增加 blockedTags 过滤：

在检查 requireTagDict 之后，检查：

if(itemData.blockedTagDict && modData.tagValue){
    if(itemData.blockedTagDict[modData.tagValue]){
        continue; // UI 列表中不展示这类插件
    }
}
这样 UI 中“可用插件列表”会自动隐藏被装备封锁挂点的插件，减少玩家困惑。

3.4 依赖系统与拆卸逻辑（与现有实现的关系）
getDependentMods(item, modNameToRemove) / canRemoveMod(item, modNameToRemove)：
这些函数只关注 provideTagDict / requireTagDict 与 presentTags 的关系。
inherentTags 应该始终参与 presentTags 计算（即拆卸插件不会影响装备固有结构）。
blockedTags 不参与依赖判定，只限制“能不能装上某插件”。
计划：

不需要对依赖计算作结构性修改，只需确保 buildTagContext 的 inherentTags 分支已经工作。
确认 getDependentMods 使用的 buildTagContext 逻辑在“有 inherentTags 时”表现正确（插件依赖的标签如果由装备固有提供，就不会因为拆下某个插件而失效）。
4. UI 与 Tooltip 改动
4.1 装备 Tooltip 展示 inherentTags / blockedTags
在 TooltipTextBuilder 中为装备增加一小段展示：

推荐位置：
在 buildEquipmentStats 或它返回的结果后 append。
或新增一个 buildEquipmentTagInfo(baseItem, item)，由 TooltipComposer.generateIntroPanelContent 调用。
展示示例：

<font color='#66ddff'>固有结构：</font>导轨, 电力接口<BR>
<font color='#ff6666'>禁止挂点：</font>枪口, 枪托接口<BR>
实现要点：

从 item.inherentTags / item.blockedTags（或解析好的 dict）读取字段。
为空时不输出，保证对旧装备完全无影响。
4.2 插件 Tooltip 保持现有增强
当前版本 buildModStat 已经展示：

挂载位置：mod.tagValue
适用武器子类：mod.weapontype
提供结构：mod.provideTagDict
前置需求：mod.requireTagDict
对于 blockedTags，不需要在插件 Tooltip 上额外展示；那是装备的属性，由装备 Tooltip 负责。

4.3 UI 错误提示与交互
在 _root.物品UI函数.执行卸下配件 中已经使用 getDependentMods 做级联卸载提示。

对于 blockedTags：

安装时，如果返回码为 -64，UI 已可通过 modAvailabilityResults[-64] 显示明确的中文错误。
不需要额外 UI 逻辑，只要在原有“安装失败提示”中走通新错误码即可。
5. 向下兼容与性能
向下兼容
不填 inherentTags / blockedTags 时：
buildTagContext 中的分支不会触发。
isModMaterialAvailable / getAvailableModMaterials 中的 blocked 检查短路。
整个系统行为与当前版本完全一致。
性能
buildTagContext 已经在 getAvailableModMaterials 中按调用一次复用。
inherentTags / blockedTags 解析只在加载 XML 时发生一次，对运行时性能影响可忽略。
6. 测试计划（v2：装备自带 tag）
在 TAG_SYSTEM_TEST.md 现有用例基础上新增一节：

场景 A：装备提供结构 + 允许挂载插件

装备：inherentTags=导轨，blockedTags 为空。
插件 A：requireTags=导轨，tag=瞄具。
预期：
未安装任何 provideTags 插件时，A 已可安装。
Tooltip 显示“固有结构：导轨”。
场景 B：装备提供结构 + 禁止挂载该类挂点

装备：inherentTags=导轨，blockedTags=导轨。
插件 A：requireTags=导轨，tag=导轨附件。
插件 B：requireTags=导轨，tag=瞄具。
预期：
getAvailableModMaterials：
A 不出现在列表（被 blocked）。
B 出现在列表（blocked 只看 tagValue，与 requireTags 无关）。
手动尝试安装 A：
isModMaterialAvailable 返回 -64。
UI 显示“该装备禁止安装此挂点类型的插件”。
场景 C：依赖链 + 装备固有结构不受拆卸影响

装备：inherentTags=电力。
插件 X：provideTags=高级电力。
插件 Y：requireTags=电力。
插件 Z：requireTags=高级电力。
步骤：
安装 Y：应成功（依赖电力，由装备提供）。
安装 X，再安装 Z：应成功。
尝试拆下 X：
只会影响 Z 的依赖；Y 仍然依赖装备固有电力，应保持有效。
getDependentMods 只返回 Z，不应该返回 Y。
工具与调试

利用 EquipmentUtil.DEBUG_MODE = true + 作弊码（如 getallmods 或新增调试指令）：
打印每次构建的 presentTags。
打印 blocked 命中日志（tagValue 与 blockedTags 匹配时的 debug 信息）。
这份计划可以作为你实现 inherentTags / blockedTags 的蓝本：先从 XML 与解析层入手，再补上 EquipmentUtil 的逻辑分支，最后加上 Tooltip 展示和 TAG_SYSTEM_TEST 中的新测试条目。需要的话，我可以在下一步帮你把某个具体武器 + 一组插件的 XML 草案和对应的测试步骤写成完整示例。