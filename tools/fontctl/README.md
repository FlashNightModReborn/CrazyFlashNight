# fontctl（C# / Web 字体目录 CLI）

`fontctl` 把 XML/XSD、来源解析、下载、生成物和裸 family 审计收进一个稳定、非交互入口。Gate E 中，`fonts/fonts.xml` 是 C# / Web runtime authority；CLI 只建模同一生成投影、face-major 候选顺序和静态完整性，不是 Host 实际 parser 的替代权威。

## 前置条件

- Node.js；CLI 本身没有 npm 依赖。
- Python 3 + `lxml`，用于独立 XSD 1.0 校验。可用 `CF7_FONTCTL_PYTHON` 指定解释器。

PowerShell 先执行 `chcp.com 65001 | Out-Null`。默认从仓库根读取 `fonts/fonts.xml`、`fonts/fonts.xsd` 和 `fonts/`。

## 命令

```powershell
node tools/fontctl/cli.js validate
node tools/fontctl/cli.js scan
node tools/fontctl/cli.js resolve --role web.intelligence.title --preset intelligence.diary --explain
node tools/fontctl/cli.js audit-usage
node tools/fontctl/cli.js sync --group expressive-handwriting
node tools/fontctl/cli.js generate
node tools/fontctl/cli.js generate --check
```

- `validate`：XSD、ID/cross-reference、fallback cycle、target/format、下载 host/URL/hash/bytes、residency、family 分类、preset 授权和 face 可达性。对 canonical XML 还核对两项 permanent 实体的格式/bytes/hash，以及生成兼容 manifest 的 source hash、schema 和 14-asset 闭包。
- `scan`：只读扫描 `temporary/custom`、`temporary/cache`、`permanent/runtime`，计算 observed bytes/SHA-256，并读取 TTF/OTF/WOFF 的 glyph 目录、outline、name、OS/2、cmap；WOFF 展开受声明长度与 256 MiB 总量双重约束，cmap format 4 先校验 segment 严格有序/不重叠并受总工作预算约束，CFF/CFF2 至少闭合 header、INDEX、Top DICT、CharStrings 与 `maxp` 数量。WOFF2 只做容器识别并报告 metadata partial。这里的 `validFont` 只表示通过 Node 结构/元数据门，发现不等于运行时启用。
- `resolve`：按 runtime 的 face-major 顺序输出候选：先取 role/preset 的第一个 face，并在该 face 内依次检查 `custom → cache → permanent`；只有该 face 无可用项才进入下一个 face，最后才是 system/generic。较晚 face 的 cache 不得越过较早 face 的 permanent。Node 零依赖路径不能代签 Launcher 的 Skia/Native 实际解析，因此，只有出现在静态首选之前的 TTF/OTF/WOFF custom `runtime-probe-required` 才会把 `selected` 降为 `provisional-node-fallback`；首选之后的未决 custom 不影响本次静态结论。Node 也不探测本机 system family，选到 system fallback 时固定为 `provisional-system-availability`。输出给出 `candidateOrder=face-major`、有界 `parityScope` 和恒为 false 的 `hostExactSelection`；其中 `authoritative=true` 只表示没有上述未决项的 Node 静态来源模型，绝不表示 Host parser/render exact selection。local custom WOFF2 固定 `unsupported-custom-font`；cache/permanent 必须匹配声明完整性。
- `audit-usage`：扫描生产 C#、CSS、JS、HTML、JSON、SVG 和 tooltip 数据。未知 family 为 error；由 `CF7FontCatalog` 控制的动态表达式单列为 catalog-bound，不算迁移债。
- `sync`：只从 XML 白名单 HTTPS 主机下载；requested 和每次 redirect 都重新校验。使用唯一 staging、256 MiB 上限、exact length/bytes/hash/glyph 结构门和可恢复原子替换，只写 `fonts/temporary/cache`。它不声称执行了 Launcher 实际 parser；`--check` 只检查所选下载集是否已经完整落入 cache，不访问网络。干净仓库故意不提交 cache，因此检查全量 asset 时会报告 missing 并返回 `2`，这不是仓库源码门失败。
- `generate`：确定性生成 `launcher/web/generated/font-catalog.{json,css,js}` 与 `launcher/web/assets/fonts/font-pack-manifest.json`。`--check` 不写文件，任一投影漂移都返回错误；使用 `--output-root` 时四项生成物写入隔离输出根。

`sync` 可用 `--asset id1,id2` 或 `--group group1,group2` 缩小范围。所有命令支持 `--json`、`--catalog PATH`、`--schema PATH`、`--project-root PATH` 和 `--font-root PATH`；`generate` 另支持 `--output-root PATH`。

## 输出与退出码

JSON 固定为 `schemaVersion=1`，诊断分为 `errors`、`warnings` 和 `pilotDebt`，按 severity、文件、行列与 code 排序。

- `0`：无阻断错误；warning / pilot debt 仍保留。
- `2`：XML、XSD、目录语义、完整性、生成漂移、扫描或审计错误。
- `64`：命令行用法错误。
- `70`：未预期的工具内部错误。

## 回归入口

```powershell
node --test tools/fontctl/tests/fontctl.test.js
node tools/run-font-catalog-harness.js
node tools/run-intelligence-harness.js --viewport 1024x576 --scale 1.75
powershell -File launcher/tests/run_tests.ps1
```

Node 测试使用 OS 临时目录，不向真实 `fonts/temporary` 写 fixture。Edge 字体 harness 明示为 `browser-fixture-non-authoritative`，只使用隔离的项目根目录合同，不读取已退役的 `%LOCALAPPDATA%/CF7FlashNight/fonts/`；本机若仍留有旧字体文件，它们只是惰性残留，不进入测试或运行时选择。矩阵覆盖 1024×576、1600×900、1920×1080，100/125/150/175%，face-major、custom 的 Node 延后裁决及 provisional 标记、cache/permanent、损坏 cache 和离线 fallback，并验证 CSS role、ordered preset、Canvas 与 rare-CJK 测量。Launcher tests 才覆盖 custom TTF/OTF/WOFF 的 Skia/Native 实际正负例、已验证字节快照、Web 成功解析缓存/未命中后下载可见、hash ETag 重验证、native style fallback 和进程重启边界；FontPack 定向测试另锁定 catalog/hash 后同字节实际探针，WOFF2 Web-only 只允许显式 `pinned-web-structure-only`，Native 必须拒绝。

## 写入与证据边界

- `scan / validate / resolve / audit-usage / generate --check / sync --check` 只读。
- `sync` 只写 gitignored cache；`generate` 只写带 generated 标识和 source hash 的版本化投影。
- 普通 XML role/preset 变化不需要修改 C#；Native 已加载 face 要重启进程。
- Node 门只证明结构、完整性与浏览器 fixture；Launcher tests 证明实际 parser 和同一已验证字节的消费。两者都不能代签字体艺术观感、许可证法律结论、正式 runtime E2E、promotion 或部署。
- 旧 FontPack UI 协议仍读取 generated compatibility manifest；不得把这一兼容层手工修改或误称为第二个人工真源。
