# Windows 探针首执行证据（2026-09-28，主机侧回填）

**范围**：本目录是 2026-09-27 离线交付（只完成交叉编译 + PE 静态检查）之后的首次实际执行记录。执行环境为**原生 Windows 主机**（ACP/OEMCP=936），不是 Wine / SLR / Steam Deck；本证据只升级"探针可执行、宽字符 API 在原生 Windows 对中文名正常"，不代签 Wine Unix codepage 归因或 #46 闭环。

## 执行命令与结果

夹具由 `python3 replay.py --prepare-fixture <全新目录>` 生成（`ascii.bin` 与 `加载背景.bin` 同内容，payload SHA-256 `423266032ccc73f9cf8ec7e1236028d4d6c82be203f7e4dbce5a7499b2ec3240`，38 字节）。

| 运行 | 退出码 | 关键结果 |
|---|---|---|
| `win-file-probe-x64.exe <夹具目录>` | 0 | 枚举 `found_ascii/found_unicode=true`；两文件 `read_all=true`、`payload_match=true` |
| `win-file-probe-x86.exe <夹具目录>` | 0 | 同上（32 位进程） |
| `win-file-probe-x64.exe --read <仓库内 flashswf/UI/加载背景.swf 绝对路径>` | 0 | `opened/read_all=true`，读到 EOF 共 **4,458,807** 字节，与 ADR §4 记载的 Linux 侧同路径大小逐字节一致；FNV-1a32 `950b23be` |
| `win-file-probe-x86.exe --read <同上>` | 0 | 字节数与 FNV 同 x64 |

四个原始输出 JSON 与本说明同目录。全部输出 `unix_codepage_observed:false`（`GetACP` 不是 Wine Unix codepage）；FNV-1a32 只是轻量诊断值，不是完整性证明。

## 边界

- 未执行 Wine、Proton、SLR、Flash 或游戏；未证明修正编码可解除宿主启动超时；#45/#46 保持开放。
- 探针为只读（枚举 + `CreateFileW`/`ReadFile` 到 EOF），不写文件、不改 registry/prefix/资产。
- 下一步仍是 README §4 的最小闭环：目标 SLR 内探针 + Wine `+nls,+file` 日志 + 同内容英/中夹具 W API 对照 + 原名资源读取 + Flash 握手/scene-ready。
