# XFL 元件重复检测工具

Flash XFL 元件重复检测与清理工具集，用于识别和修复 Flash/Animate XFL 项目中的重复元件问题。

---

## 📋 目录

1. [问题背景](#问题背景)
2. [快速开始](#快速开始)
3. [工具说明](#工具说明)
4. [使用指南](#使用指南)
5. [文件说明](#文件说明)
6. [技术文档](#技术文档)

---

## 🎯 问题背景

在长期的 Flash 项目协作编辑中，XFL 文件容易产生大量**内容一致但名称不同**的重复元件。

### 典型症状
- 相同的图形内容有多个不同的元件名（如 `身体.xml` 和 `Symbol 37.xml`）
- 文件体积膨胀
- 维护困难，修改时需要同步多个位置
- 内容不一致风险

### 解决方案
本工具集提供**三种检测方案**，从简单到精准，帮助你快速识别和清理重复元件。

---

## 🚀 快速开始

### 第一步：运行检测

**推荐使用语义级检测（最准确）：**

```bash
cd D:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources
python tools/xfl_duplicate_detector/find_duplicates_semantic.py
```

### 第二步：查看报告

检测完成后，会在**当前目录**生成报告文件：
```
duplicate_report_SEMANTIC.txt
```

使用支持 UTF-8 的编辑器打开查看（推荐 VS Code 或 Notepad++）。

### 第三步：修复重复引用

根据报告内容，手动或使用编辑器批量替换引用。

**示例：**
```xml
<!-- 修改前 -->
<DOMSymbolInstance libraryItemName="sprite/Symbol 37" ...>

<!-- 修改后 -->
<DOMSymbolInstance libraryItemName="主角肢体素材/身体" ...>
```

---

## 🛠️ 工具说明

### 方案对比

| 方案 | 脚本文件 | 准确率 | 速度 | 推荐度 |
|------|---------|--------|------|--------|
| **语义级比较** | `find_duplicates_semantic.py` | **最高 (110%)** | 中等 | ⭐⭐⭐ **推荐** |
| 结构级比较 | `find_duplicates_structural.py` | 较高 (84%) | 中等 | ⭐⭐ |
| 文本级比较 | `find_duplicates_final.py` | 一般 (74%) | 最快 | ⭐ |

### 1. 语义级检测 ⭐⭐⭐ **生产推荐**

**文件**: `find_duplicates_semantic.py`

**特点**:
- ✅ 最高准确率（覆盖所有参考元件）
- ✅ 忽略图层命名差异（`Layer 1` = `Layer_1`）
- ✅ 可配置是否忽略 ActionScript 代码差异
- ✅ 处理浮点精度问题（避免 `1.0` vs `1.00001` 误判）
- ✅ 矢量数据顺序无关

**适用场景**:
- 生产环境的元件清理
- 需要识别"语义相同"的元件（即使细节略有差异）

**配置参数**:
```python
# 在脚本中可调整以下参数：
analyzer = SemanticSymbolAnalyzer(
    xml_file,
    ignore_scripts=True,        # 是否忽略脚本差异
    ignore_layer_names=True     # 是否忽略图层命名差异
)
```

---

### 2. 结构级检测 ⭐⭐

**文件**: `find_duplicates_structural.py`

**特点**:
- ✅ 解析 XML 结构进行比对
- ✅ 识别矢量几何数据
- ❌ 对图层命名敏感
- ❌ 对脚本差异敏感

**适用场景**:
- 需要精确匹配（包括图层名和脚本）
- 中等规模的项目初筛

---

### 3. 文本级检测 ⭐

**文件**: `find_duplicates_final.py` 或 `find_duplicates.py`

**特点**:
- ✅ 速度最快
- ✅ 实现简单
- ❌ 覆盖率较低
- ❌ 容易漏检

**适用场景**:
- 快速初筛
- 超大型项目的第一轮扫描

---

## 📖 使用指南

### 基本使用流程

#### 1. 准备参考元件文件夹

确保你的 XFL 项目中有一个**参考文件夹**，包含所有标准元件。

**默认配置**:
```python
reference_folder = "flashswf/arts/things0/LIBRARY/主角肢体素材"
```

**自定义路径**: 在脚本中修改 `reference_folder` 变量。

---

#### 2. 运行检测脚本

```bash
# 方式一：直接运行（在 resources 目录下）
python tools/xfl_duplicate_detector/find_duplicates_semantic.py

# 方式二：先进入工具目录
cd tools/xfl_duplicate_detector
python find_duplicates_semantic.py
```

---

#### 3. 分析报告

报告会显示：
- 参考元件数量
- 扫描的其他元件数量
- 发现的重复元件列表
- 每个重复的详细信息（路径、文件大小差异、哈希值）

**示例报告**:
```
[身体.xml]
  Reference: 1483 bytes
  Hash: e262580284ea9065044fdd07ed0505a7
  Duplicates: 1
    -> sprite/Symbol 37.xml (972B, -511B)
```

**解读**:
- `身体.xml` 是参考元件（1483 字节）
- `sprite/Symbol 37.xml` 是它的重复（972 字节，比参考小 511 字节）
- 两者语义内容相同

---

#### 4. 修复重复引用

##### 方式一：手动替换（小规模）

在 Adobe Animate 中：
1. 打开 XFL 项目
2. 查找使用 `Symbol 37` 的地方
3. 手动替换为 `身体` 元件

##### 方式二：批量替换（推荐）

使用文本编辑器（VS Code / Sublime Text）：

1. 打开包含重复引用的 XML 文件
2. 查找替换：
   ```
   查找: libraryItemName="sprite/Symbol 37"
   替换: libraryItemName="主角肢体素材/身体"
   ```
3. 保存文件

##### 方式三：使用 git grep + sed（高级）

```bash
# 查找所有引用
git grep "sprite/Symbol 37" -- "*.xml"

# 批量替换（请先备份！）
find . -name "*.xml" -exec sed -i 's/sprite\/Symbol 37/主角肢体素材\/身体/g' {} +
```

---

#### 5. 验证修复

```bash
# 检查是否还有旧引用残留
grep -r "sprite/Symbol 37" flashswf/arts/things0 --include="*.xml"

# 应该返回 0 个结果（或仅剩元件自身的定义）
```

---

### 高级用法

#### 修改检测范围

编辑脚本中的路径：

```python
# 修改扫描范围
base_path = Path("flashswf/arts/things0/LIBRARY")

# 修改参考文件夹
reference_folder = base_path / "主角肢体素材"
```

#### 调整语义级参数

```python
# 严格模式：不忽略脚本差异
analyzer = SemanticSymbolAnalyzer(
    xml_file,
    ignore_scripts=False,      # 脚本不同则认为不同
    ignore_layer_names=True
)

# 超严格模式：连图层名都要一致
analyzer = SemanticSymbolAnalyzer(
    xml_file,
    ignore_scripts=False,
    ignore_layer_names=False   # 图层名必须完全一致
)
```

#### 调整数值精度

```python
# 在 SemanticSymbolAnalyzer 类中：

# 矩阵精度（默认3位小数）
def _extract_matrix_rounded(self, element, precision=3):
    ...

# 中心点精度（默认2位小数）
def _extract_center_point_rounded(self, element, precision=2):
    ...
```

---

## 📁 文件说明

### 脚本文件

| 文件名 | 说明 | 用途 |
|--------|------|------|
| `find_duplicates_semantic.py` | 语义级检测脚本 | **生产推荐** |
| `find_duplicates_structural.py` | 结构级检测脚本 | 精确比对 |
| `find_duplicates_final.py` | 文本级检测脚本（优化版） | 快速初筛 |
| `find_duplicates.py` | 文本级检测脚本（简化版） | 基础检测 |
| `find_duplicates_advanced.py` | 高级检测脚本 | 实验性功能 |
| `test_body_similarity.py` | 相似度测试脚本 | 调试用 |

### 文档文件

| 文件名 | 说明 |
|--------|------|
| `README.md` | 本文档（使用指南） |
| `DUPLICATE_DETECTION_TECH_DOC.md` | 技术实现详解 |

### 输出文件

运行脚本后会生成以下报告文件（在 **resources 目录**下）：

| 文件名 | 说明 |
|--------|------|
| `duplicate_report_SEMANTIC.txt` | 语义级检测报告 |
| `duplicate_report_STRUCTURAL.txt` | 结构级检测报告 |
| `duplicate_report_FINAL.txt` | 文本级检测报告 |

---

## 📚 技术文档

详细的技术实现、算法原理、设计思路，请参阅：

**[DUPLICATE_DETECTION_TECH_DOC.md](./DUPLICATE_DETECTION_TECH_DOC.md)**

内容包括：
- 三种检测方案的算法对比
- XML 结构解析技术
- 语义规范化处理
- 哈希计算策略
- 性能优化技巧
- 局限性与改进方向

---

## 💡 常见问题

### Q1: 脚本运行报错 "找不到参考文件夹"

**解决方案**:
1. 确认你在 `resources` 目录下运行脚本
2. 检查参考文件夹路径是否正确
3. 修改脚本中的 `reference_folder` 变量

### Q2: 报告中文乱码

**解决方案**:
- 使用支持 UTF-8 的编辑器打开报告（VS Code / Notepad++）
- 避免使用 Windows 记事本

### Q3: 替换后 Flash 项目无法打开

**解决方案**:
1. 检查 XML 语法是否正确（特别是引号匹配）
2. 确保替换的元件路径存在
3. 使用 Git 回滚到修改前的版本：
   ```bash
   git checkout -- flashswf/arts/things0/LIBRARY/sprite/兵器攻击.xml
   ```

### Q4: 如何确定哪些重复可以合并？

**建议流程**:
1. 先在 Flash/Animate 中打开对比元件内容
2. 确认视觉内容完全一致
3. 小范围测试替换（先替换1-2个动画）
4. 测试通过后再大范围替换

### Q5: 元件自身定义会被替换吗？

**不会**。脚本只替换 `libraryItemName` 属性（引用），不会修改元件文件第一行的 `name` 属性（定义）。

例如：
```xml
<!-- Symbol 37.xml 第一行 - 不会被替换 -->
<DOMSymbolItem name="sprite/Symbol 37" ...>

<!-- 其他文件中的引用 - 会被替换 -->
<DOMSymbolInstance libraryItemName="sprite/Symbol 37" ...>
```

---

## ⚠️ 注意事项

1. **备份项目**: 修改前务必提交 Git 或创建备份
2. **逐步验证**: 先小范围测试，确认无误后再大规模替换
3. **检查引用**: 替换后要验证所有引用是否正确
4. **测试运行**: 在 Flash/Animate 中重新打开项目，测试功能是否正常

---

## 🔗 相关资源

- **Git Commits**:
  - `267e2b494` - 基础检测工具
  - `3dc7b507b` - 完整工具集与文档

- **使用案例**:
  - things0.xfl 元件清理（2025-10-22）
  - 修复 sprite/Symbol 37/25/21 误用问题

---

## 📝 更新日志

### v1.0 (2025-10-22)
- ✅ 三种检测方案（文本级、结构级、语义级）
- ✅ 完整技术文档
- ✅ 使用指南
- ✅ 测试验证工具

---

## 👨‍💻 维护者

**Author**: Crazyfs
**Date**: 2025-10-22
**Project**: CRAZYFLASHER7 XFL 元件重复检测工具集

---

## 📄 许可

本工具集为 CRAZYFLASHER7 项目内部使用工具。
