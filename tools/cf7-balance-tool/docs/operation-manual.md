# CF7 数值平衡工具 — 操作手册

> 版本：0.1.0 | 更新日期：2026-03-07

---

## 一、工具定位

CF7 数值平衡工具是一个**桌面 + CLI 混合平台**，用于：

- 扫描游戏 XML 数据文件中的字段
- 批量预览和修改 XML 数值
- 交互式编辑数值并导出
- 公式计算和数据校验
- 变更追踪和日志审计

---

## 二、启动方式

### 桌面模式（推荐）

双击 `launch.bat`，它会自动：

1. 检测并下载 Electron（首次约 110MB，来自 npmmirror CDN）
2. 检测并构建渲染器（vite build）
3. 检测并打包主进程（esbuild CJS）
4. 启动 Electron 桌面窗口

**桌面模式**下所有按钮可用，可直接读写本地文件。

### 渲染器预览模式

```bash
cd tools/cf7-balance-tool
npx vite dev packages/web --host 127.0.0.1
```

浏览器打开后显示"渲染器预览"，**大部分写操作按钮被禁用**（保存、预览、输出等均不可点击）。仅适合查看已有报告数据和公式计算。

### 判断当前模式

页面顶部有运行模式标识：
- **桌面模式** = Electron 启动，`window.cf7Balance` 已注入
- **渲染器预览** = 浏览器/vite dev，`window.cf7Balance` 未定义

---

## 三、核心概念

### 数据流总览

```
XML 数据文件 (data/items/*.xml, data/enemy_properties/*.xml)
        ↓
   CLI 扫描 (project fields)
        ↓
field-usage-report.json ← 字段盘点（哪些文件有哪些字段）
        ↓
   用户编写修改规则 (payload JSON)
        ↓
   CLI 预览 (project batch-preview)
        ↓
batch-preview-report.json ← 预览报告（每个值的原值和修改后值）
        ↓
   UI 编辑器加载报告 → 用户在表格中微调暂存值
        ↓
   CLI 应用 (project batch-set)
        ↓
   输出镜像 XML 或就地覆写
```

### 关键文件

| 文件 | 说明 |
|------|------|
| `project.json` | 项目配置，定义数据目录路径 |
| `data/field-config.json` | 字段分类注册表（537 个字段） |
| `reports/manual-updates.generated.json` | 当前修改规则（payload） |
| `reports/batch-preview-report.json` | 预览报告（编辑器数据来源） |
| `reports/batch-set-report.json` | 应用报告 |
| `reports/field-usage-report.json` | 字段扫描报告 |
| `reports/changelog.jsonl` | 操作日志 |
| `baseline/baseline-extracted.json` | 基线数据（校验和分级用） |

### 暂存值机制

编辑器中的"暂存值"**仅存在于内存中**，关闭页面即丢失。必须点"保存 JSON"才会写入磁盘。

---

## 四、编辑器为什么显示 0 行？

**这不是 bug，而是设计如此。**

编辑器的数据行来自 `batch-preview-report.json`。该报告由 CLI 的 `batch-preview` 命令生成——它读取 payload（修改规则），对比 XML 源文件，输出每个值的原值和修改后值。

**如果 payload 为空（`[]`），报告就为空（0 个文件、0 行）。**

### 获取数据的方法

#### 方法 A：手写 payload → 刷新预览

1. 编辑 `reports/manual-updates.generated.json`，写入修改规则：

```json
[
  {
    "filePath": "data/items/weapons/guns.xml",
    "xmlPath": "/items/item[@id='gun_01']/damage",
    "value": "120"
  },
  {
    "filePath": "data/items/weapons/guns.xml",
    "xmlPath": "/items/item[@id='gun_01']/price",
    "value": "5000"
  }
]
```

2. 在桌面模式下点击 **"刷新 preview"**
3. CLI 执行 `batch-preview`，生成报告
4. 编辑器自动加载报告，显示对应的数据行

#### 方法 B：导入已有的 preview 报告

1. 如果有之前生成的 preview 报告 JSON 文件
2. 在右侧面板点击 **"导入 preview"**
3. 选择文件，编辑器替换为该报告的数据

#### 方法 C：导入已有的 payload

1. 在右侧面板点击 **"导入 payload"**
2. 选择 payload JSON 文件
3. 匹配的行更新暂存值，不匹配的行保持原样

---

## 五、界面布局与功能详解

### 5.1 顶部 Hero 区

| 元素 | 说明 |
|------|------|
| 标题 | "数值平衡工作台" |
| 运行模式标识 | "桌面模式" 或 "渲染器预览" |
| 版本信息 | Node / Electron / Chrome 版本号 |
| 字段报告时间 | field-usage-report.json 的生成时间 |
| 预览报告时间 | batch-preview-report.json 的生成时间 |

### 5.2 模块状态卡片（4 个）

| 卡片 | 含义 | 正常状态 |
|------|------|----------|
| 字段盘点 | field-usage-report 是否有数据 | 显示扫描文件数和字段数 |
| XML Round-Trip | XML 读写是否保真 | 显示"通过" |
| 批量预览 | batch-preview-report 是否有数据 | 显示操作数 |
| Electron 桥接 | 桌面 IPC 是否可用 | 桌面模式显示"已接入" |

### 5.3 已锁定边界（V1 共识）

4 条只读决策，说明当前版本的功能边界：

- 插件范围：v1 仅 CRUD，无公式插件
- 公式输出：只读参考值，不回写 XML
- 前端语言：中文优先
- 变更追踪：Git diff + 结构化报告

### 5.4 字段扫描指标（4 个统计卡片）

| 指标 | 来源 |
|------|------|
| 扫描文件 | field-usage-report 中的文件数 |
| 字段名 | 去重后的字段名数量 |
| 字段出现次数 | 所有字段的总出现次数 |
| 未分类字段 | 未在 field-config.json 中注册的字段数 |

---

### 5.5 批量编辑台（主工作区）

这是核心编辑区域，由三部分组成：左侧边栏 + 中央编辑区 + 右侧操作面板。

#### 左侧：文件导航侧边栏

- **搜索框**：按文件名或路径过滤
- **"全部文件"按钮**：显示所有数据行
- **文件夹树**：按源文件路径分组，点击文件名可筛选到单文件
- **变更计数**：显示 `已改数/总数`
- 可通过"隐藏侧栏"按钮折叠

#### 中央：编辑器工具栏

**第一行工具栏：**

| 元素 | 功能 |
|------|------|
| 搜索框 | 搜索路径、文件、值（模糊匹配） |
| "仅看已变更"复选框 | 只显示暂存值 ≠ 原值的行 |
| "恢复报告建议" | 全部行的暂存值恢复为报告建议值 |
| "全部回退原值" | 全部行的暂存值恢复为 XML 原始值 |

**第二行工具栏：**

| 元素 | 功能 |
|------|------|
| 卡片 / 表格 | 切换视图模式 |
| 隐藏侧栏 / 显示侧栏 | 折叠/展开左侧文件导航 |
| 撤销（Ctrl+Z） | 撤销上一步编辑 |
| 重做（Ctrl+Y） | 重做已撤销的编辑 |
| 批量替换 | 展开/收起批量查找替换栏 |

**批量替换栏（展开后）：**

| 元素 | 功能 |
|------|------|
| 下拉菜单 | 选择匹配目标："匹配暂存值" 或 "匹配原值" |
| 查找输入框 | 输入要查找的值 |
| 替换输入框 | 输入替换后的值 |
| "全部替换"按钮 | 对所有匹配行执行替换 |

#### 中央：数据表格（表格模式）

| 列名 | 宽度 | 说明 |
|------|------|------|
| 文件 | 18% | 源 XML 文件路径 |
| 路径 | 22% | XML 节点路径（XPath） |
| 行 | 5% | 源文件中的行号 |
| 原值 | 15% | XML 中的原始值 |
| 建议值 | 15% | preview 报告给出的建议值 |
| 暂存值 | 25% | **可编辑** — 当前暂存的修改值 |

- 点击列头可排序（升序/降序切换）
- 点击"暂存值"单元格进入内联编辑
- Enter 确认编辑，Escape 取消
- 每页 100 行，底部有"加载更多"

#### 中央：卡片视图（卡片模式）

每行数据显示为一张卡片，包含所有 6 个字段的标签和值，以及"恢复建议"和"还原原值"按钮。

#### 中央：选中行详情

点击某行后，底部显示详情：
- XML 路径 + 属性名
- 状态标识（已变更/无变更）
- 源文件路径 + 行号
- 写入模式
- 原值 vs 暂存值对比

---

### 5.6 右侧：桌面动作面板

#### 统计指标（4 个卡片）

| 指标 | 说明 |
|------|------|
| 当前可见行 | 经过搜索/筛选后的行数 |
| 有效文件 | 当前可见行涉及的文件数 |
| 暂存变更 | 暂存值 ≠ 原值的行数 |
| 输出模式 | preview / in-place / mirrored-output |

#### 三个核心操作按钮

| 按钮 | 功能 | 说明 |
|------|------|------|
| **保存 JSON** | 将当前暂存值保存为 payload JSON | 写入 `generatedInputPath` |
| **刷新 preview** | 保存 + 运行 CLI batch-preview | 重新生成预览报告并刷新编辑器 |
| **输出镜像 XML** | 保存 + 运行 CLI batch-set | 将修改写入 XML 文件（镜像或就地） |

> 仅桌面模式可用。渲染器预览模式下这三个按钮被禁用。

#### 状态消息

按钮下方显示操作结果，例如：
- "已保存：45 条 → reports/manual-updates.generated.json"
- "preview 已刷新：reports/batch-preview-report.json"
- "镜像 XML 已输出：reports/batch-set-report.json"

#### 输出路径配置

4 个可配置路径：

| 路径 | 默认值 | 说明 |
|------|--------|------|
| 手动 payload 路径 | `reports/manual-updates.generated.json` | payload JSON 保存位置 |
| preview 报告路径 | `reports/batch-preview-report.json` | 预览报告保存位置 |
| batch-set 报告路径 | `reports/batch-set-report.json` | 应用报告保存位置 |
| 镜像输出目录 | `reports/batch-output/` | 镜像 XML 输出目录 |

每个路径旁有浏览按钮（打开文件/文件夹选择对话框）。底部有"保存路径配置"和"恢复默认路径"按钮。

#### 导入区

| 按钮 | 功能 |
|------|------|
| **导入 preview** | 打开文件对话框，选择一个 preview 报告 JSON → 替换编辑器全部数据 |
| **导入 payload** | 打开文件对话框，选择一个 payload JSON → 覆盖匹配行的暂存值 |

导入 payload 后会提示匹配数和未匹配数。

#### 按文件审阅

展开后按文件分组显示变更摘要：
- 每个文件显示：源文件路径、输出路径、变更项数/总条目数
- 前 3 条变更的预览（路径、原值 → 暂存值）
- 超过 3 条显示"还有 N 项"
- **"只看此文件"**：将编辑器筛选到该文件
- **"清除筛选"**：恢复显示全部文件

#### 输出状态（产物卡片）

4 个产物的实时状态：

| 产物 | 说明 |
|------|------|
| 手动 payload | payload JSON 文件是否存在 |
| preview 报告 | 预览报告是否存在 |
| batch-set 报告 | 应用报告是否存在 |
| 镜像输出目录 | 输出目录是否存在、包含多少文件 |

每个产物显示：状态（已就绪/未生成）、更新时间、大小/文件数。可复制路径或在资源管理器中定位。

---

### 5.7 最近产物（历史面板）

- 筛选标签：全部 | payload | preview 报告 | apply 报告 | 镜像 XML | JSON
- 按修改时间倒序排列，最多 18 条
- 每条显示：相对路径、类别、更新时间、大小
- 可复制路径或在资源管理器中定位

### 5.8 操作日志（Changelog）

- 读取 `reports/changelog.jsonl`
- 最多显示最近 50 条，最新在前
- 每条显示：操作类型（批量写入/批量预览/保存 payload）、时间戳、总数/已应用数、输出目录

### 5.9 公式计算器（Formula Bar）

- 下拉选择公式引擎：枪械 / 护甲 / 近战 / 爆炸物 / 物理伤害 / 魔法伤害 / 药水 / 怪物
- 选择后显示该类别的输入参数（例如枪械：等级、子弹威力、射击间隔...）
- 修改输入参数后**实时计算**输出（例如平均 DPS、推荐金币价格）
- 纯参考功能，不直接修改编辑器数据

### 5.10 分级总览（Tier View）

- 下拉选择类别：枪械 / 护甲 / 近战 / 爆炸物 / 怪物 / 药水
- 按等级/阶段分组显示物品
- 每组显示：等级标签、物品数、平均关键指标、排名列表
- 数据来源：`baseline/baseline-extracted.json`

### 5.11 数据校验（Validation Panel）

- **"运行校验"按钮**：调用 CLI `calibrate` 命令
- 对比 baseline 中的缓存值与公式重新计算值
- 显示：总问题数、错误数（红色）、警告数（黄色）
- 每条问题显示：物品名、字段名、严重度、值和阈值对比

> 仅桌面模式可用。

### 5.12 字段分类管理（Field Config Panel）

- 管理 `data/field-config.json` 中的字段注册表
- 字段类型：numeric / string / boolean / passthrough / nested numeric / item-level / attribute / computed / numeric suffixes
- **添加字段**：输入名称 + 选择类型 + 点"添加"
- **搜索/过滤**：按名称和类型
- **删除**：每个字段旁有删除按钮
- **统计**：每种类型的字段数
- 最多显示前 200 个结果

### 5.13 底部面板

| 面板 | 说明 |
|------|------|
| 命令模板 | 显示完整 CLI 命令，可复制到终端手动执行 |
| 导出 JSON | 以 JSON 格式显示当前 payload，可复制 |
| 待继续收拾（高频未分类字段） | 前 6 个高频未分类字段及出现次数 |
| 已识别样本（高频字段参考） | 前 6 个高频已分类字段及类型 |

---

## 六、典型操作流程

### 流程 1：首次使用——从零开始修改数值

**前置条件**：已通过 `launch.bat` 启动桌面模式。

1. **创建修改规则**

   编辑 `reports/manual-updates.generated.json`：
   ```json
   [
     {
       "filePath": "../../data/items/weapons.xml",
       "xmlPath": "/items/item[@id='weapon_01']/damage",
       "value": "150"
     }
   ]
   ```

   > `filePath` 相对于 `project.json` 所在目录，也可以用绝对路径。
   > `xmlPath` 是标准 XPath 表达式，指向要修改的节点。

2. **点击"刷新 preview"**
   - CLI 读取 payload + XML 源文件
   - 生成预览报告
   - 编辑器加载数据行（现在不再是 0 行了）

3. **在表格中微调**
   - 点击"暂存值"列进入编辑
   - 或使用"批量替换"功能批量修改
   - 支持撤销/重做（Ctrl+Z / Ctrl+Y）

4. **审阅变更**
   - 右侧"按文件审阅"查看每个文件的变更摘要
   - 勾选"仅看已变更"只看修改过的行

5. **保存或应用**
   - "保存 JSON"：仅保存 payload，不修改 XML
   - "输出镜像 XML"：将修改写入镜像目录的 XML 副本

### 流程 2：导入已有报告查看数据

1. 点击右侧 **"导入 preview"**
2. 选择一个之前生成的 `batch-preview-report.json`
3. 编辑器加载该报告中的所有数据行
4. 可以在此基础上继续编辑

### 流程 3：校验基线数据

1. 滚动到 **数据校验** 面板
2. 点击 **"运行校验"**
3. 查看结果：红色错误需要修复，黄色警告可接受
4. 结合 **公式计算器** 手动验证异常值

### 流程 4：使用公式计算器

1. 滚动到 **公式计算器** 面板
2. 选择类别（如"枪械"）
3. 调整输入参数
4. 查看实时输出（DPS、推荐价格等）
5. 将计算结果手动填入编辑器暂存值

### 流程 5：管理字段分类

1. 滚动到 **字段分类管理** 面板
2. 搜索目标字段名
3. 添加新字段或修改现有分类
4. 保存后影响字段扫描的统计口径

---

## 七、Payload JSON 格式规范

```json
[
  {
    "filePath": "string — XML 文件路径（相对或绝对）",
    "xmlPath": "string — XPath 节点路径",
    "value": "string — 新值",
    "attribute": "string? — 可选，属性名（省略则修改文本内容）"
  }
]
```

**示例：修改属性值**
```json
[
  {
    "filePath": "data/items/armor.xml",
    "xmlPath": "/items/item[@id='armor_01']",
    "attribute": "defense",
    "value": "200"
  }
]
```

**示例：修改文本内容**
```json
[
  {
    "filePath": "data/items/armor.xml",
    "xmlPath": "/items/item[@id='armor_01']/name",
    "value": "钢铁护甲"
  }
]
```

---

## 八、CLI 命令参考

在工具根目录（`tools/cf7-balance-tool/`）下执行。

### 项目扫描

```bash
# 列出所有 XML 文件
npx tsx packages/cli/src/index.ts project scan --project project.json

# 扫描所有字段及出现频次
npx tsx packages/cli/src/index.ts project fields --project project.json

# XML 读写保真校验
npx tsx packages/cli/src/index.ts project roundtrip-check --project project.json
```

### 批量操作

```bash
# 预览（不修改文件）
npx tsx packages/cli/src/index.ts project batch-preview \
  --project project.json \
  --input reports/manual-updates.generated.json \
  --output reports/batch-preview-report.json \
  --output-dir reports/batch-output

# 应用修改（写入镜像 XML）
npx tsx packages/cli/src/index.ts project batch-set \
  --project project.json \
  --input reports/manual-updates.generated.json \
  --output reports/batch-set-report.json \
  --output-dir reports/batch-output
```

### 单文件操作

```bash
# 读取单个值
npx tsx packages/cli/src/index.ts xml get \
  --file data/items/weapons.xml \
  --path "/items/item[@id='gun_01']/damage"

# 设置单个值（输出到新文件）
npx tsx packages/cli/src/index.ts xml set \
  --file data/items/weapons.xml \
  --path "/items/item[@id='gun_01']/damage" \
  --value "120" \
  --output output/weapons.xml
```

### 校验和计算

```bash
# 数据校验
npx tsx packages/cli/src/index.ts validate \
  --input baseline/baseline-extracted.json \
  --output reports/validation-report.json

# 公式计算
npx tsx packages/cli/src/index.ts calc weapons --input data.json

# 数据查询
npx tsx packages/cli/src/index.ts query weapons \
  --input baseline/baseline-extracted.json \
  --sort averageDPS --limit 10
```

---

## 九、快捷键

| 快捷键 | 功能 |
|--------|------|
| Ctrl+Z | 撤销编辑 |
| Ctrl+Y | 重做编辑 |
| Enter | 确认内联编辑 |
| Escape | 取消内联编辑 |
| 点击列头 | 排序（升序/降序切换） |

---

## 十、配置文件说明

### project.json

```json
{
  "version": "0.1.0",
  "dataDirs": {
    "items": "../../data/items",
    "mods": "../../data/items/equipment_mods",
    "enemies": "../../data/enemy_properties"
  },
  "fieldConfig": "./data/field-config.json"
}
```

`dataDirs` 定义数据目录的别名和相对路径，CLI 扫描和批量操作都基于这些路径。

### settings/output-paths.json

可通过 UI 面板配置，也可手动编辑：

```json
{
  "generatedInputPath": "reports/manual-updates.generated.json",
  "previewReportPath": "reports/batch-preview-report.json",
  "batchSetReportPath": "reports/batch-set-report.json",
  "batchOutputDir": "reports/batch-output"
}
```

### data/field-config.json

字段分类注册表，9 种类型共 537 个字段。可通过 UI 的"字段分类管理"面板增删改。

---

## 十一、功能清单（校验用）

以下是所有应支持的功能，用于逐项校验：

### 启动与环境

- [ ] `launch.bat` 双击启动，自动下载 Electron
- [ ] `launch.bat` 自动构建渲染器和主进程
- [ ] 桌面模式运行标识显示"桌面模式"
- [ ] Vite dev 模式运行标识显示"渲染器预览"

### 模块状态卡片

- [ ] 字段盘点：显示扫描文件数和字段数
- [ ] XML Round-Trip：显示校验结果
- [ ] 批量预览：显示操作数
- [ ] Electron 桥接：桌面模式显示"已接入"

### 编辑器核心

- [ ] 搜索框：按路径、文件、值过滤行
- [ ] "仅看已变更"复选框过滤
- [ ] "恢复报告建议"按钮
- [ ] "全部回退原值"按钮
- [ ] 表格视图：显示 6 列数据
- [ ] 卡片视图：切换到卡片模式
- [ ] 列头排序（升序/降序）
- [ ] 内联编辑暂存值（Enter 确认，Escape 取消）
- [ ] 撤销/重做（Ctrl+Z / Ctrl+Y）
- [ ] 批量替换（查找 + 替换）
- [ ] 分页加载（100 行/页，加载更多）
- [ ] 选中行详情面板

### 文件导航侧边栏

- [ ] 文件夹树分组显示
- [ ] 搜索过滤文件
- [ ] 点击文件筛选编辑器
- [ ] "全部文件"恢复全部显示
- [ ] 变更计数显示
- [ ] 隐藏/显示侧边栏

### 桌面动作（仅桌面模式）

- [ ] "保存 JSON"按钮：保存 payload
- [ ] "刷新 preview"按钮：运行 batch-preview
- [ ] "输出镜像 XML"按钮：运行 batch-set
- [ ] 状态消息显示操作结果
- [ ] "导入 preview"按钮：导入外部报告
- [ ] "导入 payload"按钮：导入外部 payload
- [ ] 输出路径配置：4 个路径可编辑
- [ ] 输出路径浏览按钮（文件对话框）
- [ ] "保存路径配置"按钮
- [ ] "恢复默认路径"按钮

### 审阅与产物

- [ ] 按文件审阅：分文件变更摘要
- [ ] "只看此文件"筛选
- [ ] "清除筛选"恢复
- [ ] 4 个产物状态卡片（已就绪/未生成）
- [ ] 复制路径按钮
- [ ] "定位产物"按钮（打开资源管理器）

### 历史与日志

- [ ] 最近产物列表（最多 18 条）
- [ ] 按类别筛选（payload / preview / apply / XML / JSON）
- [ ] 操作日志（最多 50 条）

### 辅助面板

- [ ] 公式计算器：选择类别 + 输入参数 + 实时输出
- [ ] 分级总览：按等级分组显示物品
- [ ] 数据校验："运行校验"按钮 + 问题列表
- [ ] 字段分类管理：增/删/搜索/保存
- [ ] 命令模板：显示 CLI 命令
- [ ] 导出 JSON：显示 payload
- [ ] 高频未分类字段
- [ ] 高频已分类字段

---

## 十二、常见问题

| 问题 | 原因 | 解决方法 |
|------|------|----------|
| 编辑器显示 0 行 | payload 为空，没有修改规则 | 编写 payload 后点"刷新 preview"，或"导入 preview" |
| 按钮灰色不可点 | 渲染器预览模式 | 用 `launch.bat` 启动桌面模式 |
| "运行校验"不可点 | 渲染器预览模式 | 同上 |
| 暂存值丢失 | 关闭页面未保存 | 编辑后及时点"保存 JSON" |
| 导入 payload 显示"未匹配 N" | filePath 或 xmlPath 不匹配 | 检查 payload 中的路径是否与当前报告一致 |
| Electron 启动白屏 | 渲染器未构建 | 检查 `packages/web/dist/renderer/index.html` 是否存在 |
| "CLI entry was not found" | CLI 未编译 | 运行 `npm run build` 或检查 tsx 是否安装 |
