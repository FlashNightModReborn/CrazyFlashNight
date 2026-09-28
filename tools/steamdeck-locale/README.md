# Steam Deck 文件名编码诊断工具（#46）

**状态：离线诊断候选。** Linux 原生探针和回归已执行；Proton/Wine/Steam Deck/Flash/游戏没有运行过。Windows x86/x64 探针已于 2026-09-28 在原生 Windows 主机完成首次执行（夹具枚举/读取与原名资源只读均通过，见 [evidence/windows-first-run-20260928](evidence/windows-first-run-20260928/README.md)），尚未在 Wine/SLR 内执行。此目录不接入游戏运行包、不安装到 Steam、不改变更新器职责，不作为 runtime promotion 门。

## 1. 构建和重放

依赖仅在构建阶段使用：Linux x86_64、Python 3.10+、C 编译器；交叉编译 Windows 探针另需 Clang 和 lld-link。本轮版本见交付包 `evidence/build-a.json`。工具不会自动安装任何依赖。

在本目录执行，`/tmp/cf7-locale-build-new` 必须不存在：

```sh
python3 build.py --out /tmp/cf7-locale-build-new
# 只需要 Linux 工具时可追加 --linux-only。
export CF7_LOCALE_PROBE=/tmp/cf7-locale-build-new/locale-probe-linux-x86_64
python3 replay.py --matrix-probe "$CF7_LOCALE_PROBE" --output /tmp/cf7-locale-replay-new.json
python3 tests/test_locale.py
```

`replay.py` 使用固定 SHA-256 的 **540 字节 NLS 前缀**，其中包含完整 256 项单字节→Unicode 表。它不是完整 `.nls` 文件，也不能替代已安装 Proton 产物核验。源代码表格式已对照冻结 Wine `locale_private.h`：表起点为 `(header_words + 1) * 2`。出处在 `fixtures/provenance.json`。

本轮 16 组环境矩阵依赖当前 libc 提供 `C.UTF-8` 和 `C.utf8`；它是指定环境的回归配方，不是所有 Linux 发行版的通用通过保证。其他环境失败须保留原输出，不能改期望值掩盖差异。

交付 ZIP 已带 `bin/locale-probe-linux-x86_64`。该二进制为动态链接 ELF，当前符号需求最高 `GLIBC_2.34`；不能视为 SLR/SteamOS 通用二进制。目标环境优先从源码重建，不在不兼容时替换系统 libc。

## 2. 原生探针与启动前检查

```sh
"$CF7_LOCALE_PROBE" --stage target-runtime
sh proton-locale-guard.sh --check
# 示例值须在目标运行环境内实际通过探针；不只检查 locale 名称后缀。
sh proton-locale-guard.sh --locale C.UTF-8 --check
```

`locale_probe.c` 实际执行 `setlocale(LC_CTYPE, "")` 和 `nl_langinfo(CODESET)`。退出码：`0`=成功选择 UTF-8；`20`=成功选择非 UTF-8；`21`=setlocale 失败；`2`=参数/输出等错误。只记录选定的 locale/Python 环境变量，不导出所有环境或凭据。`environment_bytes` 按原始字节转义；还原时按每个 JSON 字符的 0–255 值取字节，不当作已经 UTF-8 解码的自然语言字符串。

`proton-locale-guard.sh` **默认只检查**。指定 `--locale` 只修改此次调用及其子进程的 `HOST_LC_ALL`/`LC_ALL`；不改父 shell、登录配置、注册表或系统 locale。非空 HOST_LC_ALL 覆盖 LC_ALL，否则删除 LC_ALL，是已核对的两个 Proton 版本的源码策略模型。

**检查器必须位于目标 Steam Linux Runtime 内、真正的 Proton 入口之前。** 在 SSH 外层检查后再进入 SLR，不能证明 SLR 内仍相同。即使检查器输出 `PASS_MODEL_ONLY`，也没有运行完整 Proton Python/user_settings/进程初始化，不能代签 Wine 实际 CODESET。Python 自身 locale coercion、后续环境改写仍可能造成差异。

显式执行模式语法如下；示例路径均是占位，不能直接当成本机路径：

```sh
# 此命令必须已经在目标 SLR 内。由调用者明确提供本次隔离的 compatdata 和运行器路径。
CF7_LOCALE_PROBE=/absolute/path/locale-probe \
  sh /absolute/path/proton-locale-guard.sh --locale C.UTF-8 -- \
  /absolute/path/to/proton run /absolute/path/to/win-file-probe-x86.exe 'Z:\absolute\fixture-path'
```

检查拒绝时不运行命令；通过时使用 `exec "$@"`，不使用 eval。检查器不负责创建/验证 compatdata，也不提供超时或自动重试；这些由本次被授权的隔离运行器负责。不要指向真实游戏 prefix，不做全局 `pkill wine`。本轮显式执行模式只用无害测试子进程验证了参数和退出码，没有调用 Proton。

特别注意：冻结 Wine 在 `setlocale()` 失败时采用 UTF-8 回退。本检查器仍拒绝失败的 locale，是为了让候选配置可验证，而不是认为 Wine 一定会在这种情况下使用 ASCII。

## 3. Windows 宽字符文件探针

创建一个**全新**英文/中文同内容夹具目录，不覆盖现有目录：

```sh
python3 replay.py --prepare-fixture /tmp/cf7-filename-fixture-new
```

得到 `ascii.bin`、`加载背景.bin` 与 `fixture.json`；两个 `.bin` 内容相同且 manifest 带 SHA-256。它们是测试文件，不是伪造 SWF。

在被授权的 Windows/Wine 环境内执行对应位数探针，参数使用绝对 Windows 路径：

```text
win-file-probe-x86.exe "Z:\tmp\cf7-filename-fixture-new"
win-file-probe-x64.exe "Z:\tmp\cf7-filename-fixture-new"
win-file-probe-x86.exe --read "Z:\absolute\payload\resources\flashswf\UI\加载背景.swf"
```

夹具模式真正使用 `FindFirstFileW`/`FindNextFileW`、`CreateFileW`/`ReadFile`；要求枚举找到两种名字，并把两份内容逐字节和预期 payload 比较。原资源模式只读打开并读到 EOF，不执行 Flash。输出 UTF-16 十六进制名字，避免控制台编码使“看起来正常/乱码”变成错误依据。

`GetACP`/`GetOEMCP` 只是 Windows API 侧数值，**不是 Wine Unix 文件名代码页**；输出显式标记 `unix_codepage_observed:false`。文件 FNV-1a32 仅作轻量诊断，不是密码学完整性证明；原包/原资源完整性仍使用独立 SHA-256 和实际 identity/closure。

每文件上限 512 MiB，枚举上限 256 项，超过直接失败；用于最小夹具，不扫描整个资源树。退出码 `0`=该次文件探针通过，`22`=文件/枚举/内容失败，`2`=参数或输出异常。交付轮 **没有实际运行两个 EXE**，只确认生成 PE、系统 DLL 导入名及相同环境重复构建一致；2026-09-28 已在原生 Windows 主机完成首次执行（夹具与原名资源只读均通过，证据见 [evidence/windows-first-run-20260928](evidence/windows-first-run-20260928/README.md)），Wine/SLR 内执行仍待现场。

## 4. 下一次取证的最小闭环

先在同一个隔离环境保存原配置 A 与显式验证过的 UTF-8 配置 B；分别采集外层、SLR 内原生探针和 Wine `WINEDEBUG=+nls,+file` 的有界日志。要求 Wine 的 `Unix LC_CTYPE ... using ... codeset` 行、文件探针进程/命令、输入哈希来自同次运行。不能仅凭 guard 的策略模型预测替代该日志。

先看英文/中文夹具 W API 对照，再只读原名 `加载背景.swf`。这些通过后，才能进入共享脚本库、Flash 连接/握手/scene-ready；再之后才是关卡、测试存档、Gaming Mode 的手柄/声音/睡眠恢复。某一步失败时停在其边界，不把下游列成通过。

本轮没有要求腾出 Steam Deck。现场工作保持待验证。

## 5. 退出与回退

工具不改现有生产文件；回退是停止使用候选调用链并恢复本次调用的原环境，保留 A/B 证据。不要全局清除 locale 或杀死其他 Wine 游戏。候选补丁是新增源码/文档，不含 SWF、运行时发布文件、真实存档或二进制进 Git。

第三方 NLS 前缀取自 Wine。随附 `fixtures/LGPL-2.1.txt` 与 provenance；这不是微软 NLS 文件，也不是自制字符表。新增工具代码的最终入库许可沿用项目审定规则，本候选不替项目变更许可证。
