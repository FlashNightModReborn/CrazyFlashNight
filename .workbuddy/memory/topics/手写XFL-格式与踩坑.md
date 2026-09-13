# 手写 XFL（不开 CS6 GUI 直接改文件）—— 完整实操指引

**状态**：格式兼容性已由 **CS6 原生往返证明**。2026-09-14 盲写 4 个元件后，用户用 CS6 打开、把元件移到 `武器/足球/`、保存成功，无报错、无格式纠正失败。
**参考实现（已归档，不随 tmp 清理）**：`.workbuddy/memory/topics/xfl-参考脚本/`（`gen_football_xfl.py` / `verify_xfl.py` / `render_preview.py`）
**先例产物**：`flashswf/arts/new/瓦巴杰克/LIBRARY/武器/足球/` 下的 `足球图.xml` / `足球.xml` / `手雷-足球.xml` / `图标-足球.xml`

---

## 0. 先看这些，别重新查（参考文档与样本索引）

| 要什么 | 去哪里 |
| --- | --- |
| XFL 编辑总规则、发布归属、四层验证 | `agentsDoc/art-asset-assembly.md` |
| XFL 工具栈分层（Layer 0~4）与投资规则 | `docs/xfl-agent-工具栈-长期路线-2026-05-24.md` |
| **改完 XFL 必跑的体检** | `scripts/tools/xfl/README.md`（audit / rename_a_class / fix_includes） |
| 投掷物骨架（Labels `消失` + Script + `area` 重力） | `flashswf/arts/new/公共素材位0/LIBRARY/其他武器/砖.xml` |
| 手持外观 + `枪口位置` 标记 | 同目录 `手雷-砖.xml` |
| 物品图标两帧结构（帧 1 遮罩特写 / 帧 2 完整展示） | `flashswf/arts/new/瓦巴杰克/LIBRARY/武器/刀剑/图标-舞.xml` |
| 图标第 1 帧的遮罩形状元件 | 同目录 `阴影所用.xml` |
| 图标底影 | `flashswf/arts/new/瓦巴杰克/LIBRARY/图标阴影.xml` |
| 投掷物物理载体（透明 40×40） | `flashswf/arts/new/瓦巴杰克/LIBRARY/area40X40.xml` |
| `枪口位置` 用的空标记 | `flashswf/arts/new/瓦巴杰克/LIBRARY/各种图素材等/Symbol 13.xml` |
| **含曲线的 Edge 权威样本**（小体积、好读） | `flashswf/arts/new/瓦巴杰克/LIBRARY/武器/dominator/素材/枪身文字.xml` |
| 单图层多 DOMShape 样本 | `flashswf/arts/new/公共素材位0/LIBRARY/假小子机枪手/头.xml`（单层 34 个） |
| 大 shape 容量参考 | `flashswf/arts/new/瓦巴杰克/LIBRARY/防具/末日铁拳/末日铁拳拳套/素材/铁拳下臂单独元件.xml`（单帧 259 个 / 740KB） |
| CS6 从 SVG 导入后生成的资源目录长什么样 | `flashswf/arts/new/公共素材位0/LIBRARY/假小子机枪手/*.svg/` |
| 编译 / 发布入口 | `scripts/FlashCS6自动化编译.md` |
| 物品 XML 字段、linkage 对应、素材表重扫 | `.workbuddy/memory/MEMORY.md`「物品数据与素材映射」节 |

---

## 1. 适用范围与边界

**适合**：给已有 XFL 加新元件；形状已经有矢量轮廓（SVG / 几何参数）；只要结构正确、不想开 CS6 也能写。

**不适合**：任意动画编排、人体重绘、复杂骨骼 —— 这些仍要 CS6 原生操作（`art-asset-assembly.md` §5「工具选择与已知阻塞」）。

**判断"该不该自动化"**：本次真正省时间的是 **XFL 结构编辑与几何编码**（几十分钟），不是矢量质量。**位图自动描摹出的 SVG 直接导成 shape，观感一般**；在意观感时人自己用 CS6 导一遍只要几分钟，**不要在这上面硬扛**，把精力留给结构部分。

**不要顺手建通用工具**：`docs/xfl-agent-工具栈-长期路线` §3 明确「同类操作反复消耗时间」才抽到 `tools/`，且不许把含本机绝对路径的临时脚本直接改名入库。本次是一次性任务，脚本留在记忆目录即可。

---

## 2. 结构：新建元件 = 改两处

CS6 XFL（`xflVersion="2.2"`）里，`DOMDocument.xml` 的 `<symbols>` **只存 `<Include>`**，元件实体在 `LIBRARY/<相对路径>.xml`：

```xml
<Include href="武器/足球/足球图.xml" loadImmediate="false" itemID="6f5a0101-0000f001" lastModified="1789322540"/>
```

新建一个元件要做三件事：

1. 写 `LIBRARY/<子目录>/名字.xml`
2. `<symbols>` 里加一条 `<Include href="相对/path.xml" itemID="..." lastModified="..."/>`
3. 若涉及新文件夹，`<folders>` 里补一条 `DOMFolderItem`

硬性规则：

- `itemID` 形如 `6f5a0101-0000f001`（8hex-8hex），**整个 DOMDocument 内唯一**。盲写时 CS6 无法替你分配，只能自编；**用可识别自己来源的连续序号**（本次 `6f5a0101..6f5a0104`），实测 CS6 接受且不会重分配。
- `<DOMSymbolItem name=...>` 必须等于它在库里的**完整相对路径**（`武器/足球/足球图`）；`<DOMTimeline name=...>` 用**末级名**（`足球图`）。把完整路径写进 DOMTimeline 会让 CS6 保存时生成重复嵌套目录。
- linkage：`linkageExportForAS="true" linkageIdentifier="足球"`。
- 元件类型：**省略 `symbolType` = MovieClip**（只有 MovieClip 实例能挂 `onClipEvent`）；`symbolType="graphic"` 用于纯静态图形。
- **`loadImmediate="false"` 只给无 linkage 的内部图形元件**。本次我 4 条都写了，CS6 保存时把 3 个 linkage 元件的该属性**去掉了**，只留 `足球图`：规律是"要 attachMovie 的元件立即加载，纯内部素材才延迟"。

---

## 3. Edge 几何编码（核心）

```xml
<DOMShape>
  <fills><FillStyle index="1"><SolidColor color="#CCCCCC"/></FillStyle></fills>
  <edges><Edge fillStyle1="1" edges="!954 115[963 126 968 139!968 139|974 326..."/></edges>
</DOMShape>
```

- `!x y` 设当前点（moveto）；`|x y` 直线到；`[cx cy px py` 二次贝塞尔到（控制点 + 终点）
- CS6 自己的风格是**每段前重复一次 `!当前点`**（如 `!0 0|800 0!800 0|800 800`），照抄即可
- 坐标单位 **twips（1px = 20）**，样本里都是整数
- `fillStyle0` = 边左侧填充，`fillStyle1` = 边右侧填充
- 可选 `<Edge cubics="...">` 是 CS6 记录的**原始三次曲线**，**不需要手写**；只写 `edges` 的元件库里大量存在
- `<Matrix a= d= tx= ty=/>`：b/c 为 0 时按 CS6 风格**省略**（实测 CS6 保留这种写法）

**⚠ 实测（重要）**：CS6 保存时会把 `fillStyle1` 为主的写法**改写成 `fillStyle0` 为主**（本次 3234 条 `fillStyle0` vs 96 条纯 `fillStyle1`），并且重排轮廓方向。所以**不要追求与 CS6 逐字一致**，只要"语义正确"（见 §4 的绕向归一化）就行；CS6 会自己规整。

---

## 4. 三次贝塞尔 → 二次（Flash 内部只认二次）

SVG 的 `C` 必须细分。**用解析误差上界，别用启发式**：

```
取 q = (3c1 - p0 + 3c2 - p3) / 4      （最优单条二次逼近的控制点）
则 P(t) - Q(t) = t(1-t)(t - 1/2) · B ,  B = p0 - 3c1 + 3c2 - p3
max|t(1-t)(t-1/2)| = 0.0481125224…（极值在 t = 0.2113 / 0.7887）
=> 最大偏差 = 0.0481125 · |B|        B = 0 时三次本身就能被一条二次精确表达
```

本次实测：13896 条三次 → 23438 条二次，**每条上界 ≤ 0.03px**（画布 992px），实际误差远小于像素。

**绕向归一化**：把所有轮廓反成同一走向（本次统一顺时针、只用 `fillStyle1`），就只依赖一条已验证语义，不必去猜 `fillStyle0` 的行为。
反转 = 点序列倒序 + 三次的两个控制点交换；**自检用"双重反转应逐命令等于原序列"**（比"采样点集相等"干净——采样点会因参数镜像而对不上）。

**⚠ 洞会丢**：把一条 path 的多个子路径拆成独立轮廓后，原图靠 nonzero 环绕挖的"洞"就没了。若洞内部会被后续色块覆盖则无所谓；否则要显式构造环形（外圈正走 + 内圈倒走）。

---

## 5. 绘制顺序：用图层承载，不要赌 elements 顺序

- `<layers>` 数组**第 0 项 = Flash 图层列表最上面 = 视觉最前**
- 同一帧 `<elements>` 内多个对象的先后**语义未证实** → **不要依赖它**。本次把 SVG 顺序切成 24 个图层（`01` 最底放白底、`24` 最上），顺序全部由图层承载
- 可行规模：单帧上百个 DOMShape 没问题（见 §0 的容量参考样本）

**⚠ 实测**：CS6 保存时**把 24 个图层压成 1 个图层、1323 个 DOMShape 合并成 1 个 DOMShape**（见 §7）。但它按图层顺序合并，**视觉顺序保住了**。结论：图层顺序是**我用来表达意图的手段**，不是需要长期维持的结构。

---

## 6. 落盘格式：CRLF + 无 BOM

- XFL 全库是 **CRLF**。Python 写回必须 `open(..., newline='')` 并保持 `\r\n`；**读也不能用默认 `newline=None`**（会把 CRLF 吃成 LF）
- 本次第一版用 LF 写出 → **整个 DOMDocument diff**，白改
- 改完主文档要做"**只多几行**"的 diff 自检，别只看自己新加的行

---

## 7. ⚠ 交给 CS6 之后会发生什么（2026-09-14 实测，最该记的一节）

CS6 打开并保存后，磁盘内容与写入时**结构性不同**。已观察到的重组：

| 行为 | 本次实测 |
| --- | --- |
| 合并图层 | `足球图.xml` 24 层 → **1 层**（重命名为 `图层 2`） |
| 合并 shape | 1323 个单色 DOMShape → **1 个 DOMShape**，改用一个共享 `fills` 表 |
| 颜色保留 | `fills` 1116 条、索引 1..1116 连续、去重色 1116（输入 1123 种，损失可忽略） |
| 改 fillStyle 侧 | 以 `fillStyle1` 改写成 `fillStyle0` 为主，方向重排 |
| 补写 `cubics` | 9102 条 Edge 带 `cubics`（记录原始三次），形如 `<Edge cubics="!-331 70(;-332,69 -332,68 -332,67q-331 70Q-332 69q-332 67);"/>`，**纯 cubics 的 Edge 可以没有 `edges` 属性** |
| 更新 `lastModified` | 改为真实保存时间戳 |
| 建文件夹 | 用户移动元件后自动补 `DOMFolderItem name="武器/足球"`，并把父级 `武器` 标成 `isExpanded="true"` |
| 同步 Include href | 文件移动后 href 自动更新（audit 报 missing=0）；`<PublishItem>` 历史滚动（新增几条、旧记录被挤出） |
| 保持 name 规则 | `DOMSymbolItem.name` 仍是完整库路径 `武器/足球/足球图` |
| 内联实例 | **只有 `足球.xml`** 的画层从"引用 `足球图` 的实例"变成**内联 DOMShape**（写法 `<DOMShape selected="true" isFloating="true">`，12936 条 Edge / 1113 色），图层重建为 Flash 默认色 `#9933CC` 的 `图层 2`。同批的 `手雷-足球.xml` / `图标-足球.xml` 仍**完好引用** `武器/足球/足球图`（各 2 处，未内联） |
| **判定**（2026-09-14 补实） | 那处内联带着 `selected="true" isFloating="true"` —— 这是**人工在 CS6 里进入 / 分离该层**留下的痕迹，**不是 CS6 自动展开**。⇒ **共享图形元件在 CS6 往返后是可靠保留的**，可以放心用"一份矢量 + 多处 linkage 引用"来省体积（本次 1.68MB 的 `足球图` 被 3 个元件共用） |
| 记录 UI 状态 | CS6 会把界面状态一并写进文件：图层 `current="true" isSelected="true"`、文件夹 `isExpanded="true"`、被选中元素 `selected="true" isFloating="true"`。**是噪声，不是格式错误**；这些属性 diff 出来别慌 |
| 保留自编 `itemID` | 我自编的 `6f5a0101..6f5a0104-0000f00N` 被原样保留、**未重分配**（CS6 给新文件夹自建的才是自己那套 `6aa6e41e-...`）⇒ §2 的自编方案成立 |

**结论**：写进去的结构是"给 CS6 的输入"，不是最终形态。追求"我写的会被原样保留"是错的；追求"语义正确 + CS6 能读懂"才对。

---

## 8. 验证清单（按成本从低到高，命令可直接抄）

```bash
cd "E:/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/project/CrazyFlashNight"

# ① XML 可解析 + 主文档登记核对（秒级）
python -c "import xml.etree.ElementTree as ET; ET.parse(r'flashswf/arts/new/瓦巴杰克/LIBRARY/武器/足球/足球图.xml')"

# ② 【必跑】Layer 0 体检：重名 / linkage 撞车 / 失效 Include / Include↔itemID 错配 / 孤儿文件
python -X utf8 -B scripts/tools/xfl/audit.py flashswf/arts/new/瓦巴杰克
#   期望：所有项 0；[6] 的 broken 只应剩仓库既有项（本次为 各种图素材等/位图 88/89/91.png）
#   退出码 0 = 结构通过；非 0 = 需要结构修复

# ③ 主文档 diff（应先备份 DOMDocument.xml）
diff <备份> flashswf/arts/new/瓦巴杰克/DOMDocument.xml

# ④ 反向渲染：从【落盘后】的 XML 解析 edges 再画一遍，比对原图
#    脚本：.workbuddy/memory/topics/xfl-参考脚本/verify_xfl.py（改成新路径可用）

# ⑤ CS6 打开核对（人工，最后一道）：元件在不在 / 图形对不对 / linkage 勾没勾
#    动手前先确认 Flash.exe 没在跑：tasklist | grep -i flash

# ⑥ publish 之后（agent 可做）：刷新素材映射，否则运行时 attachMovie 找不到符号
python tools/linkage_scanner/scan_linkage.py --xml-only
python tools/bake-icons-offline.py --name <裸名>
```

**四层验证不能互相代替**（`art-asset-assembly.md` / 路线图 §3）：源结构 → CS6 原生产物 → 装配消费者（纸娃娃/图标/掉落/Web 烘焙）→ 人的观感验收。

---

## 9. 硬约束 / 红线

- **动手前必须确认 CS6 没开着同一项目** —— 它的自动保存会盖掉磁盘改动（`tasklist | grep -i flash`）
- **改前备份 `DOMDocument.xml`**（本次留了 `DOMDocument.xml.bak-足球前`）
- **不手改 SWF**；`publish_done.marker` 单独出现不算发布成功
- `itemID` 必须唯一；`linkageIdentifier` 撞车**只能人工在 CS6 修**（`rename_a_class` 会跳过，不自动改）
- 文件行尾 CRLF、无 BOM
- 不批改其他作者的库；`asset_source_map.xml` 是 auto-generated，**禁止手改**

---

## 10. 本次踩过的坑（速查）

1. **LF 写出 → 整文件 diff**：XFL 全 CRLF，必须 `newline=''`
2. **`area` 宿主要用透明元件**（`area40X40`）：拿图形元件顶替会叠出第二个球
3. **月牙/环形要显式给"绕短弧"角度**：`crescent(355, 115)` 会按 240° 绕远路跑到另一侧，要写 `crescent(355, 475)`
4. **环/扇环的黑块圆心角取"顶点方向"**，取"边中方向"会连成一圈黑环
5. **三角形/多条子路径拼进同一个 polygon** 会因 nonzero 填实 → 每根各自成多边形
6. **零面积退化轮廓**（SVG 自带）无害，CS6/Flash 会忽略；不必为它调参
7. **校验方法本身要有自洽性判据**：本次用"双重反转自逆"和"bbox 容差比较"（精确相等会被浮点舍入打败）
8. **`loadImmediate` 只给内部图形元件**（见 §2）
9. **别把 `cubics` 当成必须项**（见 §3）

---

## 11. 配套脚本（已归档）

路径：`.workbuddy/memory/topics/xfl-参考脚本/`

| 脚本 | 用途 |
| --- | --- |
| `gen_football_xfl.py` | **主参考实现**：SVG → edges 编码 → 4 个元件 → Include 登记。20KB，含 `save_text()`（CRLF）、`sym_item()`/`layer_xml()`/`frame_xml()`/`inst_xml()` 模板、`cubic_to_quads()` 解析细分、`normalize_ops()` 绕向归一、`updated_document()` 幂等登记 |
| `verify_xfl.py` | 从落盘 XML 反向解析 edges 并渲染，验证"写进文件的能还原出图形" |
| `render_preview.py` | 由中间数据渲染预览（白底/暗底） |
| `足球手雷-接入说明（历史）.md` | 当次交给人看的接入说明 |

**使用前必须改的地方**（逐个核对，漏一个就白跑）：

1. `ROOT` / `SVG_SRC` / `XFL_DIR` / `LIB_DIR` / `OUT_DIR` —— 全部绝对路径，必须换成本次目标库
2. **`PREFIX`** —— 归档值仍是旧的 `"特效与子弹/"`（实际落点是 `武器/足球/`）。⚠ **改 `PREFIX` 前必须先删掉主文档里旧路径的同名 `<Include>`**：`updated_document()` 只按**新** href 去重，旧路径残留它不管 → 会同时存在两份同名元件
3. `ITEM_IDS` —— 换一组未占用的 `<8hex>-<8hex>`（自编连续序号，实测 CS6 不会重分配）
4. `TS` —— 硬编码时间戳，改成当前秒；纯为 diff 干净，不影响 CS6 读取
5. `N_LAYERS`、四个 `build_*()` 里的元件名与 linkage、三处 `SCALE_*`（投掷物 50/992、手持 30/992、图标遮罩 22/992、图标大图 0.12）—— 按新素材尺寸重算

**跑完必做**：§8 的 ② audit + ③ 主文档 diff（应只有新 Include + 可能的新 `DOMFolderItem`，多一行都要查）。
