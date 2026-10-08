# 荒漠运行资源导出与纳管

首轮默认输入为已经恢复并审阅的 `R24 + R25 B + R28 v6` 可编辑场景。导出器默认校验源 SHA-256 为
`a6242048e490c11d5e5c81edd6800fb6f231e2d71967c976d5f83016103da524`，只读源文件，完成后再次核对身份。
它不覆盖 Blend、原 ZIP 或现役资源。B 的水平比例和全部保留对象的世界变换不变。
后续细化或多分区源按各自构建报告显式传入 `--source-sha256`，不把旧基底哈希代作新源身份。

## 导出

在仓库根目录使用本机已有便携 Blender 4.3.2；无需安装组件：

```powershell
chcp.com 65001
$desertHandoff = 'C:\Users\fs\Documents\Codex\2026-10-07\task\CF7-desert-handoff-20261007'
& "$desertHandoff\tools\blender-4.3.2-windows-x64\blender.exe" `
  --factory-startup --disable-autoexec `
  --background "$desertHandoff\local-review\model\R24-R25B-R28-local-review.blend" `
  --threads 4 --python-exit-code 1 --python tools/desert-runtime/export_blender.py -- `
  --out tmp/desert-runtime-candidate `
  --design docs/design-data/desert-spatial-draft.json --road-repairs
```

正常完成输出 `scene.glb`、`places.json`、`export-report.json`、`source-object-map.json`。
`source-inspection.json` 和 `inspect_blender.py` 仅用于诊断，不属于运行生成输入。
导出生成器的精确输入为 `export_blender.py`、`material_eval.py`、`glb_writer.py`、`forest_lod.py`，哈希写入报告。
启用 `--road-repairs` 时还包括 `road_repairs.py`：只在内存中尝试废城末端接路，几何检查不通过则保留原路并报告 deferred。
生成输入在开始时锁定哈希，结束时再次核对，避免运行途中代码变化与收据不一致。
GLB 先写临时文件后更名；最后的报告确认源文件未变、内置 glTF importer 回读通过。
不要把只有 GLB、没有完成报告的中断输出当作已验证候选。

主仓纳管由 `tools/import-stage-select-desert.py <exportdir> --check` 负责；它不由本目录隐式触发。

## 无损压缩存储

原始导出仍是完整自包含的 `scene.glb`，导出报告继续记录该原始文件的SHA、体积、网格和回读统计。
十一子图版本原始GLB为105,993,764字节，超过GitHub普通Git单文件100 MiB上限；
主仓导入器用Python标准库生成 `scene.glb.gz`，不安装解码库、不引入外部存储服务，也不修改几何、材质、贴图或分段。
边界见 [GitHub大文件说明](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github)。

压缩使用level 9、`mtime=0`、空原文件名和固定OS字节255；不采用可能把平台OS字节写入头部的旧版
`gzip.compress(mtime=0)`快路径。导入时断言解压结果与原导出逐字节相同，`--check`另验证确定性再压缩结果。
每个实际纳管文件必须不超过100 MiB。该限制针对存储文件，不能伪造原始导出报告中的decoded体积。

- `config.json.sceneTransport` 记录固定路径 `scene.glb.gz`、`encoding: gzip`、压缩SHA/bytes与`decodedBytes`。
- `assetHashes['scene.glb']` 始终绑定解压后原GLB；浏览器先核存储字节和SHA，再解压并核原GLB身份/自包含闭包。
- `manifest.files` 枚举压缩文件，`manifest.audit` 和原 `export-report.json` 仍描述解压后GLB；
  `sceneTransport`、`transportAudit` 单独记录存储编码与无损回验，不把两层统计混为一谈。
- 导入器输出目录必须精确包含 `scene.glb.gz`、`places.json`、`export-report.json`、`config.json`、
  `source-object-map.json`、`manifest.json` 六项。迁移时只删除已验证身份的旧派生 `scene.glb`，保留导出目录中的完整原文件。

完整可编辑源包及其原始GLB导出链保持有效，不因主仓的无损存储编码而重新封包。
源包状态仍由维护配置明确记录为本地待上传；提交运行资源不表示该ZIP已上传到云端。

## 首屏裁剪与呈现合同

- 显式读取 view-layer/collection 的渲染可见性；实例按依赖图及可见 instancer 展开，不按“隐藏对象数”批删源数据。
- 不导出明确归档集合、隐藏/排除对象、显示地形底板。保留当前城市、R28 两个地形层和全部正式地点。
- 公社仅保留地表首屏：完全处于源 Z=0 以下的对象不进入运行包，穿越该面三角形做插值裁剪。地下农业仍保留于原工程。
- 森林保留每棵树的位置、树干和树冠包络；树冠以原模板四个重叠象限的低面凸包表示，保留极值。
  首屏移除次级枝条与根部支脉；原树、细叶和集合实例仍在源文件，舰体不参与树冠简化。
- 按地点、基色纹理、透明和双面合同合批；每块最多六万个面角顶点，索引固定 Uint16。
- 原有烘焙城市颜色和原始打包基色纹理保留，不再叠方向光。普通材质采用方向＋环境填充的顶点照明；不宣称做了物理 AO。
- 黑基色发光窗/招牌的真实 Emission 输入转入 unlit 颜色路径；有界颜色保留可读发光色，HDR辉光/曝光等价留实际画面检查。
- 首轮为 `KHR_materials_unlit` 静态展示，不评估 normal/roughness 微表面纹理。其他无法完全映射的材质运算在报告中逐项列出。
- 纹理按原始压缩字节 SHA 去重；没有丢失“编辑源”或把贴图名称相似当成内容相同。

## 坐标与验证边界

统一转换为 `[源 X, 源 Z, -源 Y] × 0.001`，即 glTF X 东、Y 上、Z 负北。
这是现有区域显示单位的换算，未声明全世界真实米制。
`places.json` 给出既有地点的锚点、可见包围盒和源镜头参考；`overviewBounds` 排除巨大背景地形，服务总览取景。

导出报告证明源身份、裁剪记录、标准 GLB 结构与本机回读；不证明真实 WebView2 性能、玩家视觉接受或正式上线。
源归档保留恢复配方和原始文件；运行包的删减不是对源模型的永久删除。

## 2026-10-07 首轮候选 v4 实测

本轮输出在 `tmp/desert-runtime-candidate/v4/`，源文件始终保持上述 SHA。

- `scene.glb`：84,047,200 字节，SHA-256 `2d7446c0549b2f3f49a6af694723db1929ffe70a033df7de9622f529c6d978eb`。
- 237 个合批网格、88 个运行材质、83 张内嵌图，1,746,419 三角形；全部索引 Uint16。
  这是资产统计，不能直接称为 GPU draw calls 或帧率。
- 较历史 R24 的 181,246,120 字节整景 GLB 减少 53.63%；合成来源/显示方案不同，保留该比较口径。
- 森林从初次完整展开的 8,232,485 三角形降到 396,997；本轮复用12个树冠模板的低面版本，保留1,246个实例树的位置、密度和树干，完整船体不参与简化。
- 显式剔除2,663个输出 Float32 下零面积面、538个同属性不透明双面重复三角形；未放宽回读计数门。
- 内置 glTF importer 回读得到同237网格、同1,746,419三角形，包围盒误差0；脚本阶段约121秒，回读约1.91秒。
- 21个发光材质已折入可见颜色；五对原图/Alpha图的压缩字节不同，但尺寸、active UV、采样及逐像素Alpha等价断言通过。
- 本轮接路修补结果为 `deferred`：有限候选走廊会覆盖既有城市结构，原引道保持。不能据已导出声称两城道路连接已修复。

生成输入与回读证据详见该目录的 `export-report.json`；失败尝试仅是诊断候选，不能与本轮完成报告混用。

## 选关候选接入与验证

生产 Web 注册增加荒漠适配器；既有11个关卡身份、3个导航及原进关请求均保留。
9个地点提供三维聚焦，虫洞两关使用二维定位，虫洞子页可返回荒漠。
显示层读取 `launcher/web/assets/stage-diorama/desert-region/config.json`，按其传输合同读取压缩文件，
解压后对原GLB执行SHA与自包含闭包校验，再交给GLTFLoader解析。
镜头与标签的维护输入为 `config/stage-select-desert.json`，运行目录的配置和manifest由导入器生成，不能手补。
该首轮配置独立于前三张地图的精修相机预设；荒漠 `minSpan=1.5`，旧图默认仍为5。

```powershell
python -B -X utf8 tools/import-stage-select-desert.py --check
node tools/test-stage-select-desert.js
node tools/test-stage-select-desert-transport.js
node tools/test-stage-select-desert-transport-browser.js
node tools/test-stage-select-desert-browser.js
node tools/run-stage-select-harness.js --browser edge
node tools/test-stage-select-focus.js
node tools/test-stage-select-navigation.js
```

荒漠真实浏览器检查覆盖全部入口、局部画布实际尺寸、难度选择零写、外交请求、虫洞二维往返、
静止不持续出帧、重开资源数量稳定、上下文丢失后的二维回退及重试。
结果位于 `tmp/stage-select-desert/report.json`；这里的请求由模拟Host接收，不是实际Flash进关。

扩大巡检发现两项既有问题，未在本次视觉变更中修改或标为通过：
`audit-diplomacy-stage-select-links.js` 的返回断言仍匹配旧直传形态，当前未改的AS2源码已委托
`StageReturnFlow.destination`；`derive-stage-select-intel.py --check` 的来源哈希陈旧，但实际stages内容相同，
相关输入与派生文件均与HEAD一致。具体记录为 `tmp/stage-select-desert/baseline-validation-findings.json`。

完整源包的名称、校验值和本地待上传状态保存在维护配置及运行manifest；未创建云端仓库、Release或上传副本。
上述首轮接入记录不代表正式runtime晋级或真实宿主验收，也未涉及真实玩家存档。两城接路保持独立的未完成事项。

## 六关局部细化与展示边界（2026-10-07）

用户反馈后逐一核对了袭杀与圈套、临时补给点、难民营地、军阀据点、前线基地及军阀外交。
原源对象均已进入首轮导出，未发现整片丢失或完全埋地；稀疏主要来自原建模内容。
核对采用当前 gk17/gk18/gk19/gk21/gk22 各实际子关卡背景，以及当前外交 SWF 的完整123号导出实例。
背景 SWF 的默认550×400画布会裁掉超框内容；先导出 frame SVG、根据顶层 use 的完整变换包络扩大衍生视框，
再查看全幅。此操作不改原SWF，也不是Flash运行视觉等价证明。

- `ambush_details.py`：以矩形门洞、非对称断墙、倒墙、零散碎块、旧帐篷和房车替换4个占位体。
- `civil_details.py`：营地沿用深绿旧帐与有限生活物件，补给点沿用浅灰大帐、穹顶帐、房车及分组容器；
  102个不符合完整背景的旧围墙/门柱仅隐藏，原件保留。
- `military_details.py`：保留已有帐篷、通信塔、车辆，补足据点营房/维修区、前线保障设施、小型外交营帐群；
  外交只隐藏4个明确方盒占位，不扩大成另一座巨型堡垒。
- `build_local_details.py`：从原冻结Blend重新执行上述可编辑增补，保存新完整Blend及配方哈希；
  原对象没有删除，原世界变换和所有 PLACE 地理锚点逐一保持。

新增物件通过邻域真实道路三角形投影检查；废墟五处门前也留出了可见净空。
矩形门框和断墙的27个闭合体经有向体积检查修正朝外，244个废墟物件的世界顶点和无方向面签名与先前通路合格版完全一致。
这些检查只约束本轮显示几何，不证明全域游戏碰撞或导航。

重建命令（从原冻结源启动，`--out` 必须是尚未存在该候选模型的新目录）：

```powershell
& "$desertHandoff\tools\blender-4.3.2-windows-x64\blender.exe" `
  --factory-startup --disable-autoexec `
  --background "$desertHandoff\local-review\model\R24-R25B-R28-local-review.blend" `
  --threads 4 --python-exit-code 1 --python tools/desert-runtime/build_local_details.py -- `
  --out "$desertHandoff\local-detail-new" `
  --audit tmp/desert-detail-audit/terrain-and-export-audit.json
```

源审计 JSON 随新源包保存；换机时将 `--audit` 指向解包后的对应报告。
随后按 `detail-build-report.json` 的 `sourceBlend` 和 `sourceBlendSha256` 调用导出器，
加 `--source-sha256 <该精确SHA>`，再由导入器更新维护配置所绑定的运行资源。
目前最终可编辑源身份、源包名称及SHA均以 `config/stage-select-desert.json` 为准；新的源包包含基底Blend、
细化Blend、重建配方和验证资料，独立解包、只读复开与109张内嵌图片检查通过。未上传云端。

运行层 `stage-select-desert-surround.js` 沿原地形562个真实周界点接出相同土壤纹理的展示围边，
仅隐藏经顶点位置、材质与高度共同识别的矩形外框侧壁；不改原地形、两城挡墙、坐标或B比例。
局部取景只在加载时按真实owner网格顶点预计算，避免高天线把整个空包围盒放大；共享相机API保持兼容。
三种16:9总览和六处局部均进入 `test-stage-select-desert-browser.js` 检查，外交仍按原业务直接进图，
其局部画面仅由可逆内部测试观察，不新增玩家操作。

最终细化运行GLB约87.84MB，相比首轮约84.05MB增加约3.79MB。统计与严格回读结果读取运行manifest和export-report；
前轮的截图或源包不能替代当前模型身份。两城接路仍保持未完成状态，本轮未扩入其工程修复。

## 三关按完整子地图扩容

随后收到的体量反馈要求按整关的多幅地图重建。`docs/design-data/desert-multistage-expansion.json`
逐项记录现役背景与子关卡顺序：临时补给点3段、军阀据点4段、前线基地4段。
完整关卡体量通过新增营区、车辆组、物资场和连接空地形成；帐篷等原物件不整体放大，原地理锚点不变。
分区的三维方位、功能名与连接地面是显示重建方案，游戏中的右侧出口并不规定地理正东。

`build_multistage.py` 从已验证的六关细化源调用 `depot_multistage.py` 和 `military_multistage.py`，
检查原对象变换、可见性和锚点保持，再另存完整可编辑源。不得覆盖先前Blend或归档：

```powershell
& "$desertHandoff\tools\blender-4.3.2-windows-x64\blender.exe" `
  --factory-startup --disable-autoexec `
  --background "$desertHandoff\local-detail-v2\model\desert-six-place-detail-v1.blend" `
  --threads 4 --python-exit-code 1 --python tools/desert-runtime/build_multistage.py -- `
  --out "$desertHandoff\local-multistage-new"
```

后续导出使用构建报告给出的新源精确SHA和 `--source-sha256`；导入器更新运行资源后执行 `--check`。
新增物件按真实道路和设施足印避让；军事营区还为连接道预留空间，地面分片避开原主路。
这些几何约束不证明真实游戏碰撞或通行。

每段通过 `placeId + submapIndex` 保持自己的网格身份，合批不得跨段。
运行配置的 `subareas` 按原关卡顺序保存3/4/4段，其包围盒与中心来自实际源对象；
浏览器再按真实分段顶点计算镜头。局部面板的“观察范围”只切换整关/分段镜头，
不新增进关ID、不跳过关卡流程、不改变难度，也不保存为用户镜头。
荒漠使用新的镜头版本键，旧小营区预设仍保留但不会覆盖扩大后的默认镜头。
有观察条的整关和分段按实际左视口与条高预留底部安全区，复用加载时的真实顶点投影范围重新取景；
检查几何投影底边位于按钮条上方，不能只证明几何仍处于整个画布内。

除原有荒漠与选关回归外，执行 `node tools/test-stage-select-desert-subareas-browser.js`，
要求11段均命中真实网格、取景完整且各自不同，并覆盖键盘、快照刷新、游览返回、二维回退和重开。
`--fixture-subareas` 仅供界面生命周期调试，其合成分区不能作为真实模型验证。

本轮入库身份、维护者对所展示布局的认可范围及待办见
[提交验证摘要](../../docs/evidence/desert-stage-select-2026-10-08.json)。源包仍是本地可恢复归档，未上传云端。
