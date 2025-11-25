# EquipmentUtil 重构迁移指南

## 概述
EquipmentUtil 已从1420行的"上帝类"重构为模块化架构。原类现在作为薄代理层，保持100%向后兼容。

## 迁移选项

### 选项1：无需改动（推荐）
继续使用原有的 EquipmentUtil 接口，系统会自动路由到新模块。

```actionscript
// 原有代码无需修改
EquipmentUtil.calculateData(item, itemData);
EquipmentUtil.getAvailableModMaterials(item);
```

### 选项2：直接使用新模块（可选）
对于新代码，可以直接调用特定模块以获得更好的性能和清晰度。

```actionscript
// 直接使用新模块
import org.flashNight.arki.item.equipment.*;

// 属性运算
PropertyOperators.add(prop, addProp, 0);

// 进阶系统
TierSystem.getAvailableTierMaterials(item);

// 配件管理
ModRegistry.getModData(modName);

// 标签依赖
TagManager.checkModAvailability(item, itemData, modName);
```

## 关键改进

### 1. 性能优化
- **useSwitch匹配**：O(n^4) → O(n)
- **查找表优化**：预构建索引，O(1)查找

### 2. 代码组织
```
原始：EquipmentUtil (1420行)
  ↓
新架构：
├── PropertyOperators (250行) - 属性运算
├── EquipmentCalculator (320行) - 数值计算
├── EquipmentConfigManager (280行) - 配置管理
├── ModRegistry (430行) - 配件注册
├── TagManager (380行) - 标签依赖
├── TierSystem (260行) - 进阶系统
└── EquipmentUtil (440行) - 代理层
```

### 3. 测试支持
```actionscript
// 运行完整测试套件
EquipmentUtil.quickTest();

// 查看重构信息
trace(EquipmentUtil.getRefactoringInfo());
```

## 数据流程

### 装备计算流程
```
1. EquipmentUtil.calculateData(item, itemData)
   ↓
2. TierSystem.applyTierData() // 进阶数据
   ↓
3. EquipmentCalculator.calculate() // 核心计算
   ├── buildBaseMultiplier() // 强化倍率
   ├── accumulateModifiers() // 配件修改器
   └── applyOperatorsInOrder() // 运算符应用
```

### 配件可用性检查
```
1. EquipmentUtil.getAvailableModMaterials(item)
   ↓
2. ModRegistry.getModsByUseType() // 基础筛选
   ↓
3. 武器类型检查 // weapontype匹配
   ↓
4. TagManager.filterAvailableMods() // 标签过滤
   ├── requireTags检查
   └── blockedTags检查
```

## 常见问题

### Q: 需要修改现有代码吗？
A: 不需要。所有原有接口保持不变。

### Q: 性能会受影响吗？
A: 不会。实际上性能有显著提升，特别是useSwitch匹配。

### Q: 如何回滚？
A: 恢复备份文件 `EquipmentUtil.as.backup` 即可。

### Q: 新模块在哪里？
A: 在 `org/flashNight/arki/item/equipment/` 目录下。

## 调试技巧

```actionscript
// 开启调试模式
EquipmentUtil.DEBUG_MODE = true;

// 各模块也支持独立调试
PropertyOperators.setDebugMode(true);
ModRegistry.setDebugMode(true);
TagManager.setDebugMode(true);
TierSystem.setDebugMode(true);
```

## 版本信息
- 原版本：1.0.0
- 重构版本：2.0.0
- 重构日期：2024
- 代码行数：1420 → 2360（但模块化、可维护）

## 联系支持
如遇到问题，请检查：
1. 测试套件结果：`EquipmentUtil.quickTest()`
2. 备份文件：`EquipmentUtil.as.backup`
3. 重构文档：`REFACTORING_ROADMAP.md`