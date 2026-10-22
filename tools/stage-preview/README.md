# 关卡缩略图候选与验收

本目录保存关卡缩略图的选择清单、冻结底稿和定点精修生成器。`stages.json` 是本批交付的唯一选择入口，每关只选一张图。当前选图已于 2026-10-22 经用户验收，精确像素身份记录在 [accepted.json](accepted.json)，通过现有 `bannerUrl` 接入选关界面；运行资源清单位于 [高清资源 manifest](../../launcher/web/assets/stage-select/previews/hd/manifest.json)。

生成器仍将新输出标为 `candidate_pending_human_review`，不会把本次验收泛化到未来改图。接入工具只接受已验收的相同像素；后续改图需要更新对应人类验收记录。

本批接入结果、三视口回归及单独记录的既有审计失败见 [验收与接入报告](../../docs/reports/关卡缩略图精修接入与验收-2026-10-22.md)。

## 源与产物归属

| 文件 | 作用 |
| --- | --- |
| [stages.json](stages.json) | 关卡 ID、现役旧图、V6 底稿、当前选择、真实主体、构图与修改原因 |
| `sources/v6/*.webp` | 从上一轮 V6／Boss 主选 PNG 无损导入的冻结底稿，保留原像素；不是旧版游戏 JPG |
| `sources/alternates/*.webp` | 清单明确引用的已有备用构图；未选中的 A/B 试验不属于交付 |
| [native-sources.json](native-sources.json) | 精修所需的原生 SWF／现役敌人头像路径、SHA-256、sprite、帧号、缩放、静态层选择和导出像素摘要 |
| [prepare.py](prepare.py) | 从仓库内原生资源重建缓存；核对源身份及 RGBA 像素，不写回 SWF |
| [refine.py](refine.py) | 按关卡明确设置取景、主体大小、遮挡与调色；保留原生人物结构 |
| [build.py](build.py) | 构建候选图片、实寸图、主体遮罩及选择 manifest |
| [accepted.json](accepted.json)、[integrate.py](integrate.py) | 已验收图片身份、无损 WebP 装配、限定 `bannerUrl` 接线及 `--check` |
| [check.py](check.py) | 检查完整选择集、来源、像素、真实出怪与重复构图 |
| [verify-browser.js](verify-browser.js) | 在独立 Edge 与模拟 Host 中检查现有选关面板、图片解码及验收页 |
| [review-server.js](review-server.js)、[review.html](review.html) | 仅监听本机的旧图／V6／候选三栏验收页 |

原生人物使用现役敌人头像目录或对应 SWF 的指定动画帧。酒吧仅提取背景与两组桌椅；兽王仅保留指定帧的人物与红巾层，去除遮挡身份特征的闪光、烟雾层。层列表属于渲染配方，不会修改原始动画文件。

核电站采用冷却池地标，指挥部外围采用已有 NOAH 徽章构图；二者不再依赖尚未证实在该关出现的手工补充 Boss。旧 B 栏中的露头试验没有被选入交付，也不再沿用“零露头备用”声明。废城环线按用户选定方向，以当前实际出怪的兽化变种为主怪。

`preserve_v6` 明确表示保持 V6 像素。对应关卡不重新运行旧的统一头像模板，避免在修复少数问题时改变已认可的构图。需要继续精修时，在 `stages.json` 中改为 `refined` 并增加明确配方，保留原底稿供对比。

## 构建与检查

在仓库根目录运行。使用本机已有 Python、Pillow、JDK、Node 和 Edge；不自动安装依赖。本轮验证环境为 Python 3.12.10、Pillow 12.2.0。FFDec 来自仓库 `tools/ffdec/ffdec.jar`，摘要由原生源清单约束。JDK 优先读取 `JAVA_HOME`，再查本机已安装的 Animate JDK 或 PATH。

```powershell
chcp.com 65001
python -X utf8 -B tools/stage-preview/prepare.py
python -X utf8 -B tools/stage-preview/prepare.py --check
python -X utf8 -B tools/stage-preview/build.py --output tmp/stage-preview-candidate
python -X utf8 -B tools/stage-preview/check.py tmp/stage-preview-candidate
python -X utf8 -B tools/stage-preview/verify-negative.py tmp/stage-preview-candidate
node tools/stage-preview/verify-browser.js tmp/stage-preview-candidate
node tools/stage-preview/review-server.js tmp/stage-preview-candidate
```

默认原生缓存为 `tmp/stage-preview-cache`。自定义缓存时，`prepare.py --cache <路径>` 与后续运行的 `CFN_STAGE_PREVIEW_CACHE` 必须指向同一目录。`--only stage_0_5,stage_18_6` 仅用于局部迭代；正式候选必须重新构建全量，局部目录不能通过完整覆盖检查。每次迭代优先使用新输出目录，保留旧候选与失败记录。

生成尺寸为 **644 × 276**，实寸图为 **161 × 69**，均保持相同比例。高清图和实寸图以 PNG 输出；冻结底稿使用无损 WebP。当前底稿资产为 100 个文件、12,527,090 字节；候选体积以生成 manifest 的 `imageBytes` 为准。缓存、Java class、截图、日志与失败尝试留在 `tmp/`，不作为源文件提交。

原生导出缓存可以丢失后重建；冻结底稿与配方必须保留。来源摘要或导出像素不符时应停止并审查变化，不改摘要掩盖漂移。`prepare.py` 的独立运行日志保存在缓存 `.runs/` 中。

本目录的源文本与验收记录固定为 UTF-8、LF，运行资源 manifest 也固定 LF；局部 `.gitattributes` 保证 Git 在 Windows 检出时不把摘要输入转换成 CRLF。编辑配方或生成持久元数据时保持该行尾，PNG／WebP 按二进制处理。首批验收记录保留行尾归一化前的来源摘要，并以重新生成的相同 PNG 绑定规范化后的源身份。

`verify-negative.py` 在新的临时副本中分别注入漏关、清单主体错配、冻结图像素变化与近似重复构图，确认检查器会拒绝；原候选保持不变，反例及报告保留在 `tmp/stage-preview-negative/`。

## 接入已验收选图

```powershell
python -X utf8 -B tools/stage-preview/integrate.py tmp/stage-preview-candidate
python -X utf8 -B tools/stage-preview/integrate.py tmp/stage-preview-candidate --check
node tools/stage-preview/verify-browser.js tmp/stage-preview-candidate --integrated
node tools/audit-stage-select-layout.js --json
node tools/run-stage-select-harness.js --browser edge
```

`integrate.py` 把已验收 PNG 转成逐像素相同的无损 WebP，文件名带内容摘要，防止新图沿用旧缓存。运行资源只保留一份高清图，现有 CSS 负责等比显示；旧 `previewUrl` 仍留在权威选关数据中，便于追溯与回退。只修改选定 ID 的 `bannerUrl`，不改变关卡、坐标、入口类型、出怪、交互或难度语义。

接入后，选关数据本身的摘要会变化。需要刷新候选源检查报告时重新运行 `build.py` 与 `check.py`；重建像素仍必须与 `accepted.json` 一致。`--integrated` 使用磁盘上的真实运行资源和选关配置，不再拦截图片请求或注入候选 URL；报告与截图单独保存为 `integrated-browser-report.json`、`integrated-consumer/`。

## 验证范围

- 全量选择必须与当前七个目标区域的选关注册表完全一致，禁止重复 ID、漏关和额外交付图片；manifest 中的选择也必须与 `stages.json` 一致。
- 核对原生资源、头像消费者映射、环境配置、单位表、选关注册表及生成器身份；检查实际打开的缓存集合与注册输入集合相同。
- 高清图、实寸图、冻结底稿各有摘要；未修改项保持 V6 原像素，实寸图必须由对应高清图缩小生成。
- 全部实际选图参与同区 dHash 检查，距离小于 8 报错。该检查用于发现近似重复，不等于构图审美验收。
- 选用敌人必须出现在当前关卡 XML 中；战斗背景核对关卡配置，外交地图核对现役 `rootFadeTransitionFrame`。
- 新精修人物按实际合成遮罩检查亮度与对比，武器关键点按源图坐标映射检查安全边距。统计门槛不证明五官、身份或防剧透效果，仍需看图。
- 浏览器验证为候选 URL 的内存替换，使用现有选关 DOM/CSS 和模拟 Host，不操作真实游戏或玩家存档。菲尼克斯 Lv10 属于现役直达副本入口，没有预览图展示面；报告明确记录该例外，仅验证素材解码，不伪称完成面板视觉验收。

验收页默认只显示本轮调整，取消勾选可查看全部关卡。截图按钮只读取与当前 manifest 身份匹配、哈希一致的浏览器证据。机器检查报告不替代人类验收；本批人类批准范围以 `accepted.json` 对应的用户授权为准。该资产接入不改变 native/runtime 部署字节，也不声称真实游戏进关链已经复验。
