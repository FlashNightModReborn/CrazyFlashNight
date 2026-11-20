# NPC 对话系统说明

## 概述
`list.xml` 是 NPC 静态对白的加载清单。各 XML 文件按人物或阵营分组，模板和其他对白文件只有列入清单才进入这份 NPC 索引。

## 游戏如何读取

Launcher 的 `XmlDataLoader.LoadNpcDialogues` 读取清单并建立基础索引。`DataQueryTask` 收到 `npc_dialogue` 时先合入当前存档的 Agent 替换和追加，再按主线任务进度返回可用对白组。

Flash 把查询结果组装为当前场景 NPC 的 `默认对话`。与 NPC 交谈时，菜单按原有顺序洗牌、轮播，再把所选组的完整台词以 `inline` 发送给宿主。覆盖层刷新只在查询成功后重绑，正在播放的会话使用进入时的快照。

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
