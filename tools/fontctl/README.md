# fontctl（C# / Web 字体目录 CLI）

`fontctl` 把 XML/XSD、来源解析、下载、生成物和裸 family 审计收进一个稳定、非交互入口。Gate E 中，`fonts/fonts.xml` 是 C# / Web runtime authority；CLI 与 C# Host 共享同一生成投影和来源优先级。

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
- `scan`：只读扫描 `temporary/custom`、`temporary/cache`、`permanent/runtime`，计算 observed bytes/SHA-256，并读取 TTF/OTF/WOFF 的 name、OS/2、cmap；WOFF2 只做容器识别并报告 metadata partial。发现不等于启用。
- `resolve`：按“来源优先、来源内 face 顺序”输出 `custom → cache → permanent → system/generic`。custom 允许内容覆盖但须是字体容器；cache/permanent 必须匹配声明完整性。
- `audit-usage`：扫描生产 C#、CSS、JS、HTML、JSON、SVG 和 tooltip 数据。未知 family 为 error；由 `CF7FontCatalog` 控制的动态表达式单列为 catalog-bound，不算迁移债。
- `sync`：只从 XML 白名单 HTTPS 主机下载；requested 和每次 redirect 都重新校验。使用唯一 staging、256 MiB 上限、exact length/bytes/hash/font probe 和可恢复原子替换，只写 `fonts/temporary/cache`。`--check` 只检查所选下载集是否已经完整落入 cache，不访问网络；干净仓库故意不提交 cache，因此检查全量 asset 时会报告 missing 并返回 `2`，这不是仓库源码门失败。
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

Node 测试使用 OS 临时目录，不向真实 `fonts/temporary` 写 fixture。Edge 字体 harness 覆盖 1024×576、1600×900、1920×1080，100/125/150/175%，custom/cache/permanent、损坏 cache 和离线 fallback，并验证 CSS role、ordered preset、Canvas 与 rare-CJK 测量。Launcher tests 覆盖 Host 投影 hash、来源优先级、native style fallback 和进程重启边界。

## 写入与证据边界

- `scan / validate / resolve / audit-usage / generate --check / sync --check` 只读。
- `sync` 只写 gitignored cache；`generate` 只写带 generated 标识和 source hash 的版本化投影。
- 普通 XML role/preset 变化不需要修改 C#；Native 已加载 face 要重启进程。
- 自动测试证明结构、选择、加载和几何不崩坏，不能代签字体艺术观感、许可证法律结论、正式 runtime E2E、promotion 或部署。
- 旧 FontPack UI 协议仍读取 generated compatibility manifest；不得把这一兼容层手工修改或误称为第二个人工真源。
