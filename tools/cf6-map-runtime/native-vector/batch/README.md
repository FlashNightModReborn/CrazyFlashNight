# CF6 K3 批量原生矢量调度（A09–A20、A22）

本目录是 K3 施工线独占区。只批量复用现有 `../build-layer.py`（转换器本体只读），不整景栅格化、不逐帧 PNG，纹理只解码原 SVG 内嵌原字节到 `batch/assets/`。CS6 只由 root 操作。

## 状态（2026-10-21 r9 执行轮）

- 新增受限适配器 `pattern_adapter.py`：只覆盖已确认的 floor_lattice 结构（patternUnits=userSpaceOnUse、无 viewBox、单一矢量 `<g>` 子节点、可逆 patternTransform、无变换无 stroke 的 rect 填充）。瓦片内容一次性转换为可复用原生元件并按瓦片窗口裁剪（per-tile 单遍裁剪语义已于 2026-10-21 用真实浏览器引擎以三瓦片半透明探针实证）；瓦片实例按 `patternTransform·T(x+i·w, y+j·h)` 晶格排列覆盖 paint rect，再以原 paint 几何 setMask 遮罩。结构外一律 ValueError 拒绝，不静默删样式、不烘 PNG。
- 新增 wrapper `build-pattern-layer.py`（仿 build-viewport-layer.py 进程内 Candidate 扩展）：ready 合同 fail-closed 核验 → 既有产物 SHA 快照（`batch/snapshots/`，不凭存在重用）→ 调用冻结 build-layer.py 生成 → report 追加 vectorPatterns 展开数、adapter 输入 SHA、冻结 converterBundleSha256 与信号 SHA。
- 夹具 `test-pattern-adapter.py` 14 项通过：tile 覆盖并集/晶格矩阵/负原点/剪切行错位/遮罩接线/符号复用与全部拒绝分支；几何静态验证，不冒充 Flash。
- 四图实际生成结果（exit=0，本轮日志见逐目标 stdout）：A18 40 瓦片（列-1..8×行-2..1）、A19 36（-1..7×-2..1）、A20/A22 各 45（-1..7×-2..2）；产物闭包审计通过（LIBRARY 符号数==report、纹理原字节 sha256/bytes 全核、converter/builder 快照与冻结源一致、tile/lattice/wrapper 符号 setMask 接线在位）。
- `batch-plan.py` 现检测矢量 pattern 并把 4 个目标接上 builder 字段（其余目标出现矢量 pattern 一律 blocked）；重生成 plan 时按 name+source+sha 保留历史 status/gaps/日志字段，r8 失败证据未丢。
- `run-batch.py` 对带 builder 的目标改调专用 wrapper；本轮 `--only <4目标>` 复验结果 4×reused（零重建，其余 13 个 skipped 未动）。
- `run-cs6-batch.ps1` 对带 builder 的目标 assemble 步改调 wrapper `--assemble`；import/publish 不变。实际导入、CS6 编译与视觉复核仍属 root。

## 状态（2026-10-21 r8 执行轮）

- `converter-ready.json` 已到（Astra 拥有，本线只读）：schema `cf6-native-converter-ready.v1`，status `ready_for_K3_source_preparation`，generation `source-preparation-r1b`。依赖闭包为 **files 数组**（6 项：build-layer.py、build-a01.py、build.py、native_xfl.py、svg_to_xfl_legacy.py、DejaVuSans-Bold.ttf），与 build-layer.py 实际 import 闭包逐项核对一致；build.py 与字体均已在闭包内，无需等待新信号。
- `ready_contract.py`：fail-closed 校验器。缺字段/未知 files 字段/重复路径/路径逃逸/bytes 或 sha256 不符/status 或 schema 不符/jobs 与实况 map-input、源 SVG 不符，一律拒绝执行；不再接受“字段不存在就跳过”。
- `plan.json`（schema v2）已锁定：17 个目标 = 13 图 × map-input 实有层，与 ready jobs 双向一致；全批去重纹理 33 张，全部位于 `batch/assets/`。
- 已执行 `run-batch.py`：**13 个 source-generated（exit=0），4 个 failed（exit=1），无中止**。每目标前后已重核 6 依赖文件 + 信号本体 + map-input + 该目标源 SVG，全部未变；逐目标真实退出码与日志在 `logs/batch-20261021-171053.log` 及各目标日志。
- 13 个成功目标产物闭包已核：report/texture-manifest/converter.source.py/builder.source.py/import-textures.jsfl/timeline.xml + LIBRARY 符号数与 report.nativeSymbols 一致；manifest 内纹理原字节 sha256/bytes 与 `batch/assets/` 实况逐一相符。
- 4 个失败目标（A18/A19/A20/A22 的 BG）：精确缺口为矢量 pattern 填充——`<pattern id="n2floor_lattice_{1959,1978,1986}">` 唯一子节点是矢量 `<g>` 而非单张内嵌 image，被某 rect 以 `fill="url(#…)"` 引用；转换器 `build-a01.py` `paint()` 仅支持单图 intrinsic pattern。未改转换器、未删任何图形、未做整景 PNG 回退；失败证据保留在 plan 目标 gaps（featureGap=`vector-pattern-fill`）与 `logs/`。空壳层目录不含 report/manifest，不会被误判为 reused。
- elevator-scroll 连字符已被 root 的 `import-native.ps1` 现行 ValidatePattern（`[A-Za-z0-9_-]+`）接受，本轮两个 elevator-scroll 目标已正常生成。

## 确切命令

无写计划检查（只写 `batch/plan.json`，违规退出非零）：

```powershell
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/batch/batch-plan.py --check
```

批量源生成（缺信号/合同违例直接拒绝；逐目标前后核依赖与输入，变动即整批中止不混身份；逐目标失败保留日志继续其余独立目标；复用必须快照+manifest+纹理原字节全核，零纹理目标另核已装配 XFL 闭包；带 builder 字段的 4 个 floor_lattice 目标改调专用 wrapper）：

```powershell
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/batch/run-batch.py
```

floor_lattice 四图专用 wrapper（单独生成/重新生成某一图；其余目标不受影响）：

```powershell
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/batch/build-pattern-layer.py --map A18   # A18/A19/A20/A22
```

适配器几何夹具：

```powershell
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/batch/test-pattern-adapter.py
```

root 手动串行 CS6 队列（本线永不执行；消费锁定 plan 并与 ready 信号交叉核验，逐目标重核依赖/信号/map-input/源 SVG；复用 import-native.ps1 与 compile_test.ps1，PublishOnly+VerifySwf；首败即停并留证据于 `batch/logs/cs6-<时间戳>/`；assemble 步带 `--asset-dir`）：

```powershell
& .\tools\cf6-map-runtime\native-vector\batch\run-cs6-batch.ps1            # 全部非 failed/blocked 目标
& .\tools\cf6-map-runtime\native-vector\batch\run-cs6-batch.ps1 -Only CF6_A09_BG_VectorCandidate01
```

## 边界

- 可写仅本目录（含 assets/logs/snapshots）与 plan 所列同名 `layers/CF6_A{09..22}_*`、`flashswf/backgrounds/cf6/CF6_A{09..22}_*` 候选目录；A01–A08、A21、三门、转换器与 orchestration 全部只读。
- 本线不写 `converter-ready.json`、不改转换器、不静默删 SVG 图形/滤镜；不支持的元素按报错原文记入 plan 目标 gaps 与 `logs/`。
- 本轮只产候选源，不安装 canonical，不清 marker/锁，不手改 SWF，不提交不推送。
- A18–A20、A22 的 floor_lattice 矢量 pattern 已由 `pattern_adapter.py` + `build-pattern-layer.py` 落地（见 r9 状态）；结构外的新矢量 pattern 仍按拒绝处理。root 串行队列直接消费锁定 plan：`run-cs6-batch.ps1 -Only CF6_A18_BG_VectorCandidate01 ...` 会对这 4 个目标自动改用 wrapper 的 assemble。
