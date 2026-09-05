# 装备素材度量衡

**文档角色**：度量衡工具的命令、参数、输出与验证入口。装配方法统一见 [美术资产装配](../../agentsDoc/art-asset-assembly.md)，首轮测量依据见 [175 cm 人模调查](../../docs/装备素材度量衡-175cm人模标尺-2026-09-05.md)。

只读 XFL 的局部轮廓和挂载矩阵，帮助把现实长度换成装备元件中的像素。需要 Python 3.10+；使用标准库，不依赖 Pillow、Flash GUI 或 Launcher 进程。`calibrate` 复用仓库 `tools/bake-dressup-offline.py` 的装扮路径解析，不复制另一套骨架定义。

## 文件职责

| 文件 | 负责什么 |
|---|---|
| `measure.py` | `convert` 换算、`symbol` 单元件测量、`calibrate` 当前人模复算 |
| `xfl_geometry.py` | 矩阵累乘、twip / 十六进制定点坐标、二次曲线极值、诊断 SVG |
| `profiles.json` | **制作档位的唯一机器真源**：`weapon`、`body`、`head`，含标定姿势和历史证据指针 |
| `test_measure.py` | 独立几何样本、输入与输出边界、真实 things0 / things 回归 |

## 换算现实长度

路径参数相对**仓库根目录**解析；可从任意工作目录用脚本的绝对路径执行。

```powershell
chcp.com 65001 | Out-Null
python tools/asset-metrology/measure.py convert --profile weapon --length-cm 88 --source-px 1200
```

当前档位下结果是外层 **264 px**、缩放 **22%**。`--source-px` 应量源图中对应物理长度的内容，排除透明边缘与逻辑标记。

```powershell
# 若当前编辑层到武器外层已放大 3.193054 倍，需要把这个倍率除掉。
python tools/asset-metrology/measure.py convert --profile weapon --length-cm 88 --source-px 1200 --nested-scale 3.19305419921875

# 延续既有夸张风格时，独立指定美术倍率；缺省为 1。
python tools/asset-metrology/measure.py convert --profile weapon --length-cm 100 --style-factor 1.5
```

`outerTargetPx` 是直接挂载外层中的目标长度；`editingLayerTargetPx` 是当前编辑层应有的长度；`resizePercent` 是相对于 `sourceContentPx` 的缩放百分比。`--nested-scale` 只接受已经确认的等比倍率；非等比或斜切必须沿目标长度方向使用完整矩阵，不能取两轴平均值。

## 测量已有元件

```powershell
python tools/asset-metrology/measure.py symbol --xfl flashswf/arts/things/things.xfl --symbol "1.枪械相关/长枪/枪-长枪-AK47" --output-dir tmp/asset-metrology/ak47
```

`--symbol` 是 XFL 库中的完整名称，**不是 linkage ID**。`--frame` 使用 Flash 的 1-based 帧号，缺省为第 1 帧；补间中间帧明确报错。嵌套元件取其声明的 `firstFrame`（缺省第 1 帧），不模拟脚本或子 MovieClip 的播放时钟。

默认排除完整实例名 `area`，以及 `枪口位置`、`弹壳位置`、`刀口位置`、`攻击区域` 和这些名称的数字后缀。用 `--include-markers` 可检查标记怎样撑大外框。结果中的 `boundsPx` 顺序为 `[xmin, ymin, xmax, ymax]`；横向枪械可用 `widthPx`，倾斜画稿应量已知方向上的端点长度。

## 复算人模基准

```powershell
python tools/asset-metrology/measure.py calibrate --output-dir tmp/asset-metrology/current
```

从当前 `things0` 的常规男主角重算七种常态，以配置中的放松空手站姿与 175 cm 为共同基准，输出各 holder 的完整矩阵和两轴长度倍率。`rates` 对比实测结果与制作档位，不自动覆盖 `profiles.json`。

骨架、裸体基本款、holder 缩放或身高约定改变时重新运行；确认采用新标尺后才更新配置及其证据指针。修改下臂或姿态造成合法基准变化时，应结合 SVG 和源矩阵更新真实样本回归，不能仅为消除失败放宽断言。女模、巨拳、乘骑与非人形不在本标定命令的覆盖内。

## 输出与边界

- 缺省向 stdout 输出 JSON。指定 `--output-dir` 才写文件，且只允许 `tmp/asset-metrology/` 下；不删除目录，也不改 XFL / FLA / SWF。
- 三个命令均支持 `--dry-run`：执行计算，但即使指定输出目录也不写结果。它不是跳过测量的开关。
- 固定输出 `result.json`；`symbol` 另有 `contours.svg`，`calibrate` 另有 `reference-contours.svg`。不同装配任务使用各自的输出子目录；同目录重跑会替换上述同名结果。
- 测量 JSON 记录实际读取源文件与工具 / 配置的 SHA-256，可用于检查两次复算所用的来源。历史 evidence commit 不代表当前工作树身份。
- SVG 保留局部坐标，只画诊断轮廓；存在描边、滤镜、脚本、隐藏层或透明填充时，轮廓不等于最终可见像素边界。输出会提示脚本 / 滤镜存在；alpha 为零且无 offset 的实例被略过。
- 遮罩、位图、文字、循环引用、缺失元件、未知轮廓语法或不支持的补间帧明确失败，不以近似值冒充完整测量。本工具不是通用 XFL 播放器或 Flash 验收工具。

## 验证

修改本工具或制作档位时运行：

```powershell
python tools/asset-metrology/test_measure.py
node tools/validate-doc-governance.js
```

真实样本已覆盖 things0 男模与 things AK47；测试另外构造小 XFL，检查曲线控制点并非轮廓极值、旋转后的极值、镜像与嵌套缩放、枪口排除、定点负数，以及不支持的输入必须失败。纯换算复用不需要重跑整套换皮、Flash 编译或 runtime 发布门。
