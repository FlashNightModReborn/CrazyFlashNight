# CF7 #46：中文文件名编码离线施工与验证报告

**日期：2026-09-27。范围：离线归因、诊断候选、回归与接班材料。**

**结论：本轮把“UTF-8 文件名被按 CP20127 解释”推进到了真实表数据可重放的机制证据，并交付了启动前检查器、Linux 原生探针、Windows 宽字符文件探针及测试。尚未锁定 9 月 7 日历史运行中是谁注入了错误 locale，也未证明修正编码能够解除 Flash 启动超时。#46 不应据此关闭。**

CF7 冻结源码基线为 `08c4ae100f4daa84bc2ea77991f4f59a016ddcc5`。历史游戏包仍是 `CF7_20260817.7z`，并非当前 HEAD；包 SHA-256 为 `18ce3ffeecfca8759ad84961824886ce2f05ba2829882ce4dda14c1b73c7f951`。公开共享对话本次未取得正文；承接方向来自已有上下文，实质结论重新对照了 GitHub 历史证据与固定上游源码，没有把未读到的上一轮附件当作本轮执行证据。

## 1. 已实际完成的工作

| 工作 | 本轮结果 | 证明边界 / 原始记录 |
|---|---|---|
| 历史乱码重放 | **8/8 检查通过** | 真实 NLS 映射表、原始 UTF-8 字节、独立解析 Wine long/mask 日志；`evidence/replay-and-matrix.json` |
| locale 环境对照 | **16/16 组符合预期** | 原生 C/libc 实际执行；Proton 环境改写是明确标注的源码策略模型，不是运行 Proton |
| 诊断工具回归 | **40/40 测试通过，2.381 秒** | 含反例、拒绝、参数边界、输出拒绝覆盖与夹具保护；`evidence/unittest.log` |
| Linux 探针 | 编译并执行 | C11，警告作为错误；采集 setlocale/CODESET，不用 Python 的文件系统编码替代 |
| Windows x86/x64 探针 | 两个 PE 均已交叉编译、静态检查 | 只有 KERNEL32/SHELL32 导入；**没有在 Windows 或 Wine 执行** |
| 重复构建 | 三个二进制在两个新目录中 SHA-256 一致 | 同一主机、同一源码和工具链；不是独立 builder，不是发布认证 |
| 候选补丁与手册 | 已打包 | 新增工具、回归、来源说明和候选报告；没有向 GitHub 提交或推送 |

计数互不代表独立产品验收：40 个单元测试包含对 16 组环境矩阵及重放的调用；不能把 8+16+40 相加宣传成 64 项游戏通过。编译脚本本身不执行生成物；Linux 运行证据来自独立测试步骤。

交付环境是 Debian 13.3 / Linux x86_64，已有 `C`、`C.utf8`、`POSIX` locale。本轮没有运行 Wine、Steam Linux Runtime、Flash、游戏或远程 Windows，也没有连接 Steam Deck。

## 2. 归因证据加强到了什么程度

### 2.1 不再只验证人为写出的 `byte & 0x7f`

历史摘录记录目标为 `加载背景.swf`，UTF-8 字节：

```text
e5 8a a0 e8 bd bd e8 83 8c e6 99 af 2e 73 77 66
```

本轮从 **Proton 11.0-2 所绑定的 Wine 提交**取得 `nls/c_20127.nls` 的前 540 字节，解析其中 256 项单字节映射。表中每一项都等于相应输入字节与 `0x7f` 的按位与。读取偏移又单独核对了该提交的 `locale_private.h`，不是靠试偏移凑答案。

把原始文件名字节经过真实表转换后，与历史 Wine 目录枚举中 `long` 字段的控制字符、斜杠、后缀**逐字吻合**；独立解析的 `mask` 仍是正确中文。UTF-8 正控恢复原名，英文名对照不变。由此可把 CP20127 错误解释认定为高度吻合的机制候选，而不是泛泛的“Linux 不支持中文”。

前缀 SHA-256：`543e11ac0d685983e53e97d3d7411f0d1d9912d0ab179099d85866b6f9ff426e`。它只证明所取表片段身份；不等于核验了 Deck 当时安装的完整 `.nls`、Wine 可执行文件或整个 Proton 闭包。

### 2.2 必须纠正“locale 不可用就变成 ASCII”的概括

冻结 Wine 源码在 `setlocale(LC_CTYPE, "")` **失败时选择 UTF-8 回退**；成功选中 `C`/`POSIX`、并从 CODESET 获得 `ANSI_X3.4-1968`，才会尝试加载 CP20127 表。表加载失败也不会自动让初始 UTF-8 表变成 CP20127。

因此必须区分：

- **成功选中 C/POSIX**：符合本轮 CP20127 路径；
- **请求的 locale 无效或不可加载**：该 Wine 版本的源码走 UTF-8 回退，不能用“缺 locale”直接解释同一乱码。

检查器仍拒绝无效 locale，是为了要求候选配置在当前环境可验证，并非声称 Wine 的回退一定坏。16 组矩阵与回归明确覆盖了这个反例。

### 2.3 `LC_ALL=UTF-8` 在外层正确，并不意味着送进 Wine 仍正确

已逐一核对 `proton-10.0-4b` 与 `proton-11.0-2` 的 `init_wine`：非空 `HOST_LC_ALL` 会替换 `LC_ALL`，否则删除 `LC_ALL`。

实际 C 探针加源码策略模型复现了这些反例：

| 输入条件 | 处理前原生结果 | 经过 Proton locale 策略模型后的原生结果 |
|---|---|---|
| `LC_ALL=C.UTF-8`，`LC_CTYPE=C`，无 HOST | UTF-8 | ASCII；ALL 被删，CTYPE 生效 |
| `HOST_LC_ALL=POSIX`，外层 ALL/LANG 为 UTF-8 | UTF-8 | ASCII；HOST 覆盖 ALL |
| `HOST_LC_ALL=C.UTF-8`，其他相关值为 C | ASCII | UTF-8 |
| 无效 HOST locale | 取决于外层 | setlocale 失败；冻结 Wine 源码预测 UTF-8 回退，guard 拒绝 |

另外，Python `sys.getfilesystemencoding()` 可以显示 UTF-8，而同组显式原生环境仍选择 ASCII。Python UTF-8 模式不能替代 native libc/Wine 证据。完整 Proton Python 初始化、locale coercion、user_settings 及 SLR 环境传递未在本轮执行，所以表中后半列始终标为**策略模型后的 native 实测**，不是 Wine 实测。

## 3. 最小施工落点与已交付候选

当前 `tools/cf7-packer/sfx/install-unix.sh` 只负责目录发现和复制更新内容，不启动 Proton。因此不往安装器里随手加一个 `export LANG` 当作修复，也不把此次诊断扩大成跨平台更新器施工。

候选位于 `tools/steamdeck-locale/`：原生 `locale_probe.c`，显式 `proton-locale-guard.sh`，`replay.py`，40 项回归，`win_file_probe.c`，离线 `build.py` 和中文 README。guard 必须放在**目标 SLR 内、真正 Proton 入口之前**；默认只检查，显式传入命令才执行，不触碰全局 locale。

Windows 探针提供英文/中文同内容 W API 枚举与读取，以及原资源绝对路径的只读打开。输出文件名 UTF-16 十六进制，避免终端显示制造假证据；`GetACP` 不充当 Unix CODESET。夹具逐字节核对预期内容；原文件 FNV-1a32 明确是非密码学诊断值，不代替 SHA-256。

Linux 交付二进制的最高 glibc 符号需求是 `GLIBC_2.34`，不能直接承诺兼容 SLR 的 libc；目标环境应从源码重建或实际验证依赖，不替换系统 libc。Windows PE 仅说明编译成立，不代签 API 行为。

候选补丁只增加文件，不自动修改既有 ADR、安装器、启动入口、`.as`、SWF、原资源名、manifest、运行包或存档。`patches/ADR-建议补充.md` 给出唯一权威 ADR 的同步段落，等待正常入库流程；**GitHub 仓内文档本轮没有被远程提交更新**。

## 4. 剩余问题与停止条件

**历史注入层仍未锁定。** SSH、Python、Steam、SLR 与 Proton 的逐层原始环境记录不在仓内摘要里；历史原始 ZIP 也未取得。不能在没有这些材料时把某一层写成已经证实的责任方。

下一次可用环境只需做一条有界 A/B 取证链：同一个隔离 prefix 与同内容夹具，记录外层 → SLR 原生 → Wine `+nls` 的有效值和进程身份；A 保留原配置，B 使用经目标 libc 验证的 UTF-8；随后跑两种位数的 W API 探针。失败必须保留原始失败，不以重试或另换 prefix 消除证据。

若 W API 的中文名仍失败，停止宣称 locale 修复成立，继续查路径映射/编码转换；若夹具成功，再只读原名 `加载背景.swf`。若原名能读而 Flash 仍超时，转查共享脚本库、Flash 本地信任/Socket policy、URL 转换、localhost 及宿主对等检查，不扩写成“编码是唯一根因”。

只有继续取得 Flash 连接、握手与 scene-ready 证据，才算把编码和业务启动连成因果链。关卡、测试存档与 Gaming Mode 的手柄/声音/睡眠恢复仍属之后的人验，本轮全部未测。用户当前的 Steam Deck 游戏用途不受影响，无需为了本轮交付腾出掌机。

## 5. 证据、应用和回退

完整 ZIP 的 `evidence/` 保存实际命令、退出码、重放 JSON、单元测试、PE 检查、环境和重复构建记录；`sources/source-index.json` 保存固定引用、blob 身份及未取得材料声明。`MANIFEST.sha256` 用于检查交付文件内容。测试通过只对随包源码与二进制身份负责。

`patches/issue46-offline-tools.patch` 是新文件候选补丁。在真实仓库首先执行 `git apply --check`；工作树变化导致冲突时停止并正常合并，不能使用覆盖式拷贝吞掉他人修改。包内干净目录应用校验不等于已经在用户正在施工的工作树里应用。撤回只需不再调用候选工具；已经新建的测试目录和证据保留到调查归档，不清理真实 prefix 或资产。

本轮没有 commit/push、发布或关闭 #46；GitHub 阶段性回填应引用本报告和原有 ADR，保持待现场闭环，而不是把离线交付记成游戏兼容验收通过。

## 6. 固定来源

- CF7 历史摘录：[steamdeck-install-20260907.json](https://github.com/FlashNightModReborn/CrazyFlashNight/blob/08c4ae100f4daa84bc2ea77991f4f59a016ddcc5/docs/evidence/steamdeck-install-20260907.json)。
- CF7 安装脚本：[install-unix.sh](https://github.com/FlashNightModReborn/CrazyFlashNight/blob/08c4ae100f4daa84bc2ea77991f4f59a016ddcc5/tools/cf7-packer/sfx/install-unix.sh)。
- Proton 10.0-4b：[冻结脚本](https://github.com/ValveSoftware/Proton/blob/e91ca2be0df2cef4c230cbbc0b86604d73a0bbf6/proton#L1515-L1523)。
- Proton 11.0-2：[冻结脚本](https://github.com/ValveSoftware/Proton/blob/db9e6ffbf24a95b104fb699dd62532c70a2f9a51/proton#L1530-L1538)。
- Wine locale 初始化：[env.c](https://github.com/ValveSoftware/wine/blob/dc26e61847081a1b5cb0733dc30feba6ee575482/dlls/ntdll/unix/env.c#L280-L323)。
- Wine NLS 格式：[locale_private.h](https://github.com/ValveSoftware/wine/blob/dc26e61847081a1b5cb0733dc30feba6ee575482/dlls/ntdll/locale_private.h#L191-L219)；[CP20127 表](https://github.com/ValveSoftware/wine/blob/dc26e61847081a1b5cb0733dc30feba6ee575482/nls/c_20127.nls)。
