# NPC 对话系统说明

## 概述
NPC对话系统已经从单一的 `npc_dialogues.xml` 文件重构为模块化的多文件结构，使用列表聚合模式加载。

## 文件结构

### 核心文件
- **list.xml** - 主列表文件，定义要加载的所有对话XML文件
- **npc_dialogue_main.xml** - 主要剧情NPC的对话（Andy Law, The Girl, Vanshuther, King, PROPHET）
- **npc_dialogue_shop.xml** - 商店NPC的对话（Shop Girl及其他商贩）
- **npc_dialogue_quest.xml** - 任务相关NPC的对话（Blue, Bard, Guitar, Singer等）
- **npc_dialogue_misc.xml** - 其他杂项NPC的对话

### 原始文件
- **npc_dialogues.xml** - 保留的原始完整文件（备份用途）

## 加载机制

### 新的加载器类
- **位置**: `scripts/类定义/org/flashNight/gesh/xml/LoadXml/NpcDialogueLoader.as`
- **功能**:
  1. 首先读取 `list.xml` 获取文件列表
  2. 依次加载每个XML文件
  3. 合并所有对话数据到统一的数据结构
  4. 返回格式: `{ NPCName: [DialogueArray] }`

### 加载入口
- **文件**: `scripts/asLoader/LIBRARY/asLoader.xml` (Frame 52)
- **调用方式**:
  ```actionscript
  var npcLoader:NpcDialogueLoader = NpcDialogueLoader.getInstance();
  npcLoader.loadNpcDialogues(onSuccess, onError);
  ```

## 数据格式

每个NPC对话文件保持原有XML结构:
```xml
<root>
  <Dialogues>
    <Name>NPC名称</Name>
    <Dialogue id="0">
      <TaskRequirement>...</TaskRequirement>
      <SubDialogue id="0">
        <Name>...</Name>
        <Title>...</Title>
        <Char>...</Char>
        <Text>...</Text>
      </SubDialogue>
    </Dialogue>
  </Dialogues>
</root>
```

## 添加新NPC对话

1. 创建新的XML文件（如 `npc_dialogue_newtype.xml`）
2. 确保使用UTF-8 with BOM编码
3. 在 `list.xml` 中添加文件引用:
   ```xml
   <items>npc_dialogue_newtype.xml</items>
   ```
4. 文件会在下次加载时自动包含

## 兼容性

- 完全兼容原有的 `_root.NPC对话` 数据结构
- 所有依赖函数无需修改:
  - `_root.读取NPC对话()`
  - `_root.读取并组装NPC对话()`
  - UI系统调用保持不变

## 优势

1. **维护性**: 小文件更易编辑和版本控制
2. **性能**: 可并行加载提升速度
3. **扩展性**: 轻松添加新NPC对话文件
4. **组织性**: 按功能分类，结构清晰
5. **一致性**: 采用与enemy_properties相同的成熟模式