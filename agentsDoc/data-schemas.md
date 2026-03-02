# XML/JSON 数据结构规范

> 本项目的数据层规范，涵盖 data/ 和 config/ 目录的文件结构约定。

---

## 1. 数据目录总览

| 目录 | 用途 | 格式 | 修改生效方式 |
|------|------|------|-------------|
| `data/stages/` | 关卡定义 | XML | 运行时加载，重启生效 |
| `data/items/` | 物品配置 | XML | 运行时加载，重启生效 |
| `data/units/` | 单位数据 | XML | 运行时加载，重启生效 |
| `data/dialogues/` | 对话脚本 | XML | 运行时加载，重启生效 |
| `data/environment/` | 环境设置 | XML | 运行时加载，重启生效 |
| `config/` | 系统配置 | XML | 运行时加载，重启生效 |

---

## 2. XML 格式约定

- 声明：`<?xml version="1.0" encoding="UTF-8"?>`
- 缩进：4 空格
- 属性值：双引号
- 注释：中文说明各参数用途

---

## 3. 配置文件索引

### config/ 目录
<!-- TODO: 列举各配置文件及其参数结构 -->
- `PIDControllerConfig.xml` — PID 控制器参数（参阅 `config/PIDController 参数配置与调优指南.md`）
- `WeatherSystemConfig.xml` — 天气系统（昼夜循环、光照级别）

### 根目录配置
- `config.toml` — 运行时配置（Flash 路径、SWF 路径等）
- `config.xml` — 游戏主配置
- `crossdomain.xml` — Flash 跨域策略

---

## 4. 各数据类型 Schema

<!-- TODO: 逐步从实际 XML 文件中提取各类型的结构描述 -->
<!-- 每种数据类型应包含：根元素、必要属性、子元素列表、示例片段 -->

### stages（关卡）
> 待填充

### items（物品）
> 待填充

### units（单位）
> 待填充

### dialogues（对话）
> 待填充

### environment（环境）
> 待填充

---

## 5. 新增数据文件流程

1. 确认数据类型对应的目录
2. 参照该类型现有文件的 XML 结构
3. 使用 UTF-8 编码
4. 添加中文注释说明用途
5. 参阅 `agentsDoc/game-design.md` 确认数值平衡参考
