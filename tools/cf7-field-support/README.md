# CF7 现场诊断助手（#105 候选工具）

**状态：独立 Windows x64 工具已交付 0.1.3 候选，完成本机检查和限定双机/热点验收；剩余验收随后续 A 开发、B 测试的施工继续。尚未证明真实测试员兼容性，未解决 #106。**

本工具由 C# / .NET 10 / WinForms、CLI 连接代理与 Go `tsnet` 用户态网络组件组成。与游戏正式 runtime 独立构建。完整问答、探针传输、测试文件替换/恢复和 RuntimeBundleV2 候选导入均在首包范围。

0.1.3 补齐断连诊断：A 端 `broker.json` 收尾保留会话、底层异常、最后收包/心跳时间及是否请求结束；B 端记录连接/结束时间，GUI 区分连接断开、授权到期和双方主动结束。结束时清除“等待维护者继续”的旧提示、回到滚动区域顶部，并提供重新准备入口，仍需重新明确授权与新票据。0.1.2 已实际完成手机移动数据热点下的直连和 1 MiB 往返哈希校验，但随后出现 `connection_closed`，旧 A 端日志不足以确定根因。此次修正不宣称跨网断连根因已解决，仍待复验。

0.1.2 增加 GUI 内的五步引导：准备、网络、配对、协作、收尾。窗口顶部始终显示当前行动、下一位操作人和主按钮；测试员不需要打开本说明。新网络申请、配对文件、身份核对与新问题各提醒一次；声音可关闭，后台可显示不激活窗口的短暂提醒，任务栏同时闪烁。提醒点击后定位当前步骤，取消/到期的旧问题不会继续提醒。结束后自动列出本机登记的待恢复文件，无需寻找 JSON。当前包的真实跨网和人类听感验收仍待执行。

0.1.1 修复首轮 B 机验收发现的显示问题：问答正文由保底高度承载，不再被选项/输入框挤成细线；正文和许可说明随内容布局，超出窗口的中间区域可滚动，“立即结束”固定在窗口顶部。连接后显示已连接状态。构建增加填入真实长度问题/选项的原生界面检查及模拟控件缩放检查。维护者已在双机同一局域网完成问答目视/文字回复、文件替换恢复、冲突保护及游戏候选启动/正常关闭；这只是局域网切片，不代表 #105 完整验收。历史结果见仓内 `docs/evidence/field-support-lan-acceptance-2026-09-21.json`，下一轮提醒增强与不同网络范围见 `acceptance.md`。

## B 机：测试员的操作

1. 解压整个 ZIP，不单独抽出 EXE。双击 `启动现场助手.cmd`（或 `cf7-support.exe`）。不需要 .NET SDK、Go、Tailscale 系统客户端或 SSH 服务。
2. 选择游戏文件夹；首轮只测工具时可选一个专用空目录。阅读授权范围，选择有效期，点击“开启本次诊断”。默认普通用户运行，不要求管理员。
3. 首次联网出现“复制连接申请”时，把申请通过双方已有聊天渠道私下交给维护者。维护者在 A 机浏览器登录自己的 Tailscale 网络并批准新节点。B 机无需登录账号、输入网络密钥、设置路由器或开放入站端口。此申请不是公开分享链接，不发公开群。
4. 网络准备完毕后，点击“保存配对文件”，再用“打开票据文件夹”找到文件，把 `.cf7ticket` 文件私下交给维护者，无需打开文件。维护者导入后，核对双方显示的连接指纹，再点“核对一致，允许连接”。聊天中回复同意不替代本机按钮；票据泄露也不能代替这一步本机身份确认。
5. 收到问题时选择答案或填写文字，也可拒绝。点击“立即结束诊断”撤销本次连接、停止本轮受控任务。关闭助手也结束诊断。不会关闭启动工具前已经运行的游戏、聊天软件等进程。
6. 用窗口底部“查看实验记录”查看本轮记录。临时文件替换不自动无条件回滚：正常结束前由维护者恢复；异常结束后可“查看待恢复文件”，自动汇总本机记录，再逐项核对恢复。仅当前字节匹配本轮替换版本时恢复原件；已经是原件时只更新记录，发生其他修改则保留并报告冲突。

底部可分别关闭“提示音”和“后台提醒窗口”，也可点击“试听提示音”。偏好和游戏目录保存在本机，下次打开沿用。每个新问题只提示一次；后台提醒 12 秒后消失，未答问题仍在主窗口。提醒的“稍后”不会回答问题或同意连接；只有主动点击“查看当前步骤”才切回助手。系统静音时仍有视觉提示。授权说明、问题正文和恢复冲突均在 GUI 中可读，README 仅供维护者参考。

网络加入与本次诊断是两层状态：网络采用临时 tsnet 节点，结束后停止节点；诊断始终需要本轮票据与本机确认。旧票据不能在重启/断网恢复后复活会话。网络设备列表中的临时节点可能稍后才清理，不代表仍有诊断权限。

## A 机：维护者与 Agent

A 机首包使用已登录同一 tailnet 的 Tailscale 系统客户端（维护者侧依赖）；B 端不需要安装客户端。Tailscale 账号、网络批准和必要的 ACL 由维护者管理，工具不创建账号、不修改 tailnet 全局策略，也不打包 OAuth/API key。A→B 的 TCP 38475 必须被该 tailnet 现有访问策略允许。跨网直连失败时由 Tailscale 使用 DERP 中继；没有可达的控制服务/中继时如实失败，不降级成公网无认证访问。

从包目录在 PowerShell 中调用 `./cf7-support.exe`。命令结果是 JSON，失败退出码为 1。授权、票据不作为命令行字符串传入。

```powershell
./cf7-support.exe connect --ticket-file C:\Private\field.cf7ticket --developer 维护者
./cf7-support.exe status
./cf7-support.exe exec --script-file .\examples\probe.ps1
./cf7-support.exe operation --id <operationId>
./cf7-support.exe ask --request-file .\examples\ask.json
./cf7-support.exe question --id <questionId>
./cf7-support.exe put --file C:\Work\probe.ps1
./cf7-support.exe get --remote <远端文件绝对路径> --local C:\Evidence\new-file.json
./cf7-support.exe finish
```

`connect` 返回连接代理状态文件路径、PID 和待核对指纹。B 确认后代理保持连接；CLI 退出或 Agent 换对话不会结束它。下一 Agent 首先调用 `status`，核对当前 session、运行身份、未结操作和变更，不从接班文件恢复权限。一次只接受一个 CLI 修改流程；只读状态、取消与结束不受长任务阻塞。

`exec` 接受 PowerShell 脚本文件，异步返回 operationId。`operation` 查询输出尾部、退出状态及 PID；完整输出在 B 会话目录内，stdout/stderr 分别最多保存约 4 MiB。脚本默认以实验目录为工作目录、当前交互用户身份执行。退出码 0 不证明业务成功；超时、取消、网络异常后的写入结果可能未知，先核对状态和现场，不能盲重放。

`cancel --id` 停止指定受控操作；`ask.cancel --id` 取消问题。问答只有明确答复才进入 answered；拒绝、超时、取消均不是同意。旧问题的迟到答复不用于新实验。RPC 可指定稳定 requestId 重查同一 exec/replace/import 的原响应；不将未知请求自动重试成一个新写操作。

上传分块校验偏移，完成后校验全文件 SHA-256；partial 文件不会成为可用上传。下载后同样核对全文件哈希，且不覆盖已有本地目标。首包单文件上限 2 GiB；跨会话自动续传未交付。大文件使用中继时速度取决于现场链路。

## 临时替换与恢复

先用 `get.info` RPC 或诊断脚本读取目标 SHA-256，上传新文件后，把下列 JSON 写成文件传给 `replace --request-file`：

```json
{"uploadId":"上传结果中的id","target":"scripts/asLoader.swf","expectedSha256":"替换前目标SHA256"}
```

返回 change id 后，用 `restore --id <id>` 恢复。替换/恢复前正常退出目标游戏；备份、原/新哈希、替换状态写在本机 `changes.json`。包装器拒绝真实存档、`.sol`、正式 runtime、根 bootstrap 与发布 consensus。通用 shell 仍具有当前用户权限，不能把包装器规则描述为恶意代码沙箱。

## C# 候选跨机实验

1. A 机先通过项目现有 producer 构建候选。`candidate.pack --root <候选根> --output <新ZIP>` 复核 identity、closure 和逐文件哈希，只打包 manifest 声明的文件及 metadata，不携带运行日志或真实存档。
2. `put` 上传 ZIP；`candidate.import --upload-id <id>` 严格解压与校验，在 B 游戏根下 `tmp/runtime-candidates/v2/c-*` 原子发布新目录，不覆盖已有候选或正式 runtime。
3. 将以下 JSON 写入文件，用 `candidate.launch --request-file` 启动：

```json
{"path":"导入结果中的B端绝对路径","startScriptSha256":"A端已审阅automation/start.ps1的SHA256"}
```

4. B 必须已有完整游戏安装及现有 `automation/start.ps1` / `tools/dotnet-runtime-detect.ps1`，入口脚本哈希不同时先核对差异。工具调用该规范入口；bootstrap 和 Core 继续执行原有候选验证，不关校验。游戏候选所需 .NET Desktop Runtime 仍由游戏现有依赖负责，工具自包含不等于为游戏安装了 runtime。
5. 查看 operation 输出中的实际 `isolated_candidate` 路径、PID、Core SHA-256、build identity、payload closure 与预期是否一致，再开展业务实验。导入或启动请求成功不代签 `candidate_executed` / E2E。

候选启动产生的进程属于本次实验 Job，结束诊断会终止它们。应先正常退出游戏并确认保存/未知写状态，再结束诊断；强制停止不是安全保存。正式发布保持独立授权与现有发布协议。

## 数据位置、结束和恢复

本机记录在 `%LOCALAPPDATA%\CF7FieldSupport\sessions\<sessionId>`，目录 ACL 限当前用户与 SYSTEM。包含操作脚本/有界输出、上传、备份、变更记录和 `handoff.json`。这些可能含现场资料，不提交 Git、不默认整包上传。`network-private` 是短期组网状态，不作为诊断证据导出。

开发机代理资料在 `%LOCALAPPDATA%\CF7FieldSupport\controller-private`；导入票据在配对成功后从代理私有副本删除，原接收文件由维护者保管或删除。接班摘要不含票据或私钥。长连接关闭、90 秒无消息、授权到期、助手退出均撤销本次会话；旧权限不会因恢复网络自动生效。

关闭通道和 Job Object 管理不能撤回已经发生的持久修改，也不保证清理经系统服务/计划任务等外部代理创建的任务。首包通用实验禁止创建这类脱离进程树的任务；确需此类实验时先明确登记和恢复方案。已授权通用 shell 不是隐私沙箱。

## 开发与验证

源码属于 `tools/cf7-field-support/`，不依赖 Launcher 程序集。主工程 C#、组网辅助 Go，共两个实现栈；Go 仅做用户态网络转发，不解释诊断命令。使用固定 .NET SDK 10.0.300、Go 1.27.1、Tailscale 1.102.4；依赖由 `packages.lock.json` 和 `network/go.sum` 固定。

```powershell
powershell -NoProfile -File tools/cf7-field-support/build.ps1 -DotnetExe <dotnet.exe> -GoExe <go.exe>
```

默认工具链位置分别为当前用户的 Microsoft/dotnet 与仓库 `tmp/field-support-build/go`。Go 官方 ZIP 为 `go1.27.1.windows-amd64.zip`，SHA-256：`A3911B5E0E1B1053F25ED0675F4C1C6AAD1E2BFCF253DF2B9BE4CAABD2EDD95D`。构建只使用该便携工具链，不修改系统 PATH 或安装服务。

构建输出到 `tmp/field-support-packages`，执行分发 EXE 的隔离 selftest，生成源码快照身份、逐文件 manifest、第三方许可和 ZIP。`verify-package.ps1` 检查完整性；包哈希应由维护者通过可信渠道提供，包内 manifest 本身不是发行者签名。工具源码尚未提交时，`build-info.json` 明确标记未提交候选，不借旧 HEAD 冒充本包源码。

本地 selftest 使用真实 TLS、隔离目录和本轮进程树；不能代签双开发机、真实断网、跨洲延迟、用户目视或完整游戏候选运行。双机按随包 `双机验收清单.md` 验证，仓内对应文件为 `acceptance.md`。

`cf7-support.exe connection-check --output <新目录> --seconds 210` 做超出三分钟配对窗口的本机持续 TLS/心跳检查，允许 190–600 秒，使用隔离目录且不加入外部网络。输出 `connection-report.json`；它不证明 tsnet 或真实热点链路稳定。

独立工具改动不触发游戏 runtime 发布。维护者于 2026-09-21 授权本轮源码、脚本、说明及限定验收回执集中提交推送，并将 #105 以待验收状态归档、保持开放；剩余项并入后续双机施工。当前 0.1.3 ZIP 是提交前构建的已测候选，仍使用自身源码快照身份，不追认为提交后的重新构建。后续候选构建不自动授予 commit/push、外部服务开通或真实存档写入权限。双机施工与单次授权边界见仓内 ADR §9。
