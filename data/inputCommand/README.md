# InputCommand 搓招配置 XML 编写指南

## 目录结构

```
data/inputCommand/
├── list.xml                 # 模组列表入口
├── barehand.xml             # 空手搓招配置
├── light_weapon.xml         # 轻武器搓招配置
├── heavy_weapon.xml         # 重武器搓招配置
└── README.md                # 本文档
```

## list.xml 格式

```xml
<?xml version="1.0" encoding="UTF-8"?>
<InputCommandSets>
    <Set id="barehand"    file="data/inputCommand/barehand.xml"  label="空手"/>
    <Set id="lightWeapon" file="data/inputCommand/light_weapon.xml" label="轻武器"/>
</InputCommandSets>
```

| 属性 | 必填 | 说明 |
|------|------|------|
| id | 是 | 模组唯一标识，用于代码引用 |
| file | 是 | XML 文件相对路径（相对于 resources 目录） |
| label | 否 | 显示名称，默认使用 id |

---

## CommandSet XML 格式

### 基本结构

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CommandSet id="barehand" label="空手">
    <Commands>
        <!-- 招式定义 -->
    </Commands>
    <Derivations>
        <!-- 派生关系 -->
    </Derivations>
    <Groups>
        <!-- 分组定义 -->
    </Groups>
</CommandSet>
```

---

## Commands 招式定义

### 完整示例

```xml
<Command name="波动拳" action="波动拳" priority="10">
    <Sequence>
        <Event>DOWN_FORWARD</Event>
        <Event>A_PRESS</Event>
    </Sequence>
    <Tags>
        <Tag>空手</Tag>
        <Tag>远程</Tag>
    </Tags>
    <Requirements>
        <Skill name="内力爆发" minLevel="2"/>
        <MP ratio="0.1"/>
    </Requirements>
</Command>
```

### Command 属性

| 属性 | 必填 | 说明 |
|------|------|------|
| name | 是 | 招式名称，用于显示和引用 |
| action | 否 | 动画帧标签，默认使用 name |
| priority | 否 | 优先级，数值越大越优先匹配，默认 0 |

### Sequence 输入序列

定义触发招式的按键组合，按顺序排列。

### Tags 标签

用于分类和筛选，可选。

### Requirements 技能要求（可选）

| 子元素 | 属性 | 说明 |
|--------|------|------|
| Skill | name, minLevel | 要求的被动技能及最低等级 |
| MP | ratio | 消耗 MP 比例（0.1 = 10%） |

---

## 可用事件名称 (Event)

### 方向键

| 事件名 | 符号 | 说明 |
|--------|------|------|
| FORWARD | → | 前（面朝方向） |
| BACK | ← | 后 |
| DOWN | ↓ | 下 |
| UP | ↑ | 上 |
| DOWN_FORWARD | ↘ | 下前 |
| DOWN_BACK | ↙ | 下后 |
| UP_FORWARD | ↗ | 上前 |
| UP_BACK | ↖ | 上后 |

### 攻击键

| 事件名 | 符号 | 说明 |
|--------|------|------|
| A_PRESS | A | A键（攻击/J键） |
| B_PRESS | B | B键（跳跃/K键） |
| C_PRESS | C | C键（换弹键/R键） |

### 组合键

| 事件名 | 符号 | 说明 |
|--------|------|------|
| DOUBLE_TAP_FORWARD | →→ | 双击前 |
| DOUBLE_TAP_BACK | ←← | 双击后 |
| SHIFT_HOLD | Shift | 按住Shift |
| SHIFT_FORWARD | Shift+→ | Shift+前 |
| SHIFT_BACK | Shift+← | Shift+后 |
| SHIFT_DOWN | Shift+↓ | Shift+下 |

---

## Derivations 派生关系

定义招式之间的连招关系。

```xml
<Derivations>
    <Derive from="波动拳">
        <To>诛杀步</To>
        <To>后撤步</To>
        <To>燃烧指节</To>
    </Derive>
</Derivations>
```

- `from`: 起始招式名称
- `To`: 可派生的目标招式（可多个）

---

## Groups 分组定义

用于批量管理招式。

```xml
<Groups>
    <Group name="空手全部">
        <Member>波动拳</Member>
        <Member>诛杀步</Member>
    </Group>
    <Group name="移动类">
        <Member>诛杀步</Member>
        <Member>后撤步</Member>
    </Group>
</Groups>
```

---

## 常见招式模板

### 下前 + 攻击（波动拳型）

```xml
<Command name="波动拳" priority="10">
    <Sequence>
        <Event>DOWN_FORWARD</Event>
        <Event>A_PRESS</Event>
    </Sequence>
</Command>
```

### 双击前（冲刺型）

```xml
<Command name="诛杀步" priority="5">
    <Sequence>
        <Event>DOUBLE_TAP_FORWARD</Event>
    </Sequence>
</Command>
```

### Shift + 方向（特殊移动）

```xml
<Command name="后撤步" priority="5">
    <Sequence>
        <Event>SHIFT_BACK</Event>
    </Sequence>
</Command>
```

### 方向 + 攻击（简单组合）

```xml
<Command name="燃烧指节" priority="8">
    <Sequence>
        <Event>FORWARD</Event>
        <Event>B_PRESS</Event>
    </Sequence>
</Command>
```

### Shift + 下 + 攻击（蓄力型）

```xml
<Command name="蓄力重劈" priority="8">
    <Sequence>
        <Event>SHIFT_DOWN</Event>
        <Event>A_PRESS</Event>
    </Sequence>
</Command>
```

---

## 注意事项

1. **编码格式**: 必须使用 UTF-8 编码
2. **方向归一化**: 使用 FORWARD/BACK 而非 LEFT/RIGHT，系统会根据角色朝向自动转换
3. **优先级设置**: 复杂输入的招式应设置更高优先级，避免被简单输入抢先匹配
4. **派生完整性**: 确保 Derivations 中引用的招式名称在 Commands 中已定义

---

## 运行时配置

运行时参数在 `data/config/InputCommandRuntimeConfig.xml` 中配置：

```xml
<InputCommandRuntimeConfig>
    <DFA>
        <DefaultTimeout>5</DefaultTimeout>
        <DefaultFrameWindow>15</DefaultFrameWindow>
    </DFA>
    <HistoryBuffer>
        <EventCapacity>64</EventCapacity>
        <FrameCapacity>30</FrameCapacity>
    </HistoryBuffer>
    <Sampler>
        <DoubleTapWindow>12</DoubleTapWindow>
    </Sampler>
</InputCommandRuntimeConfig>
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| DefaultTimeout | 输入超时帧数 | 5 |
| DefaultFrameWindow | 输入窗口帧数 | 15 |
| EventCapacity | 历史事件容量 | 64 |
| FrameCapacity | 历史帧容量 | 30 |
| DoubleTapWindow | 双击检测窗口 | 12 |
