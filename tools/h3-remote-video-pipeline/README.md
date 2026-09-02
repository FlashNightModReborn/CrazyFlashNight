# H3 Remote Video Pipeline

把 Windows 编排端与专用 macOS VPIPE/MiniMax H3 工作机连接成可恢复的短视频生成链：冻结输入与种子、远端串行生成、持久状态、SHA-256 预检、自动回收、媒体合同验证和审片衍生。

本工具包来自一次已经完成的七条视频生产/恢复闭环；七条都走到了本地哈希一致、尺寸/帧数合同成立和完整解码通过。这个事实只证明工作流可行，不保证不同 H3/VPIPE 版本、模型、分辨率或硬件有相同画质、耗时和内存行为。

工具包只保留通用合同。没有收录用户名、主机名、IP、SSH 密钥、个人目录、角色专名、项目素材、提示词原文、种子、生成成片或第三方账号信息。

## 目录

| 文件 | 用途 |
|---|---|
| `CREATIVE_PLAYBOOK.md` | 来源权威、提示词、选卡、画质、剪辑、音乐权利与归档经验 |
| `templates/batch-manifest.example.json` | Windows 收集与验证使用的批次合同示例 |
| `templates/queue.example.tsv` | macOS 控制器读取的串行任务队列示例 |
| `templates/remote-controller.sh` | 父任务等待、独占 VPIPE、内存保护和断点跳过模板 |
| `validate-h3-batch.mjs` | 校验 manifest 与 queue 的身份、顺序和参数一致性 |
| `collect-h3-batch.ps1` | 等待远端完成、下载、验哈希、ffprobe、全量解码和生成审片件 |

## 适用边界

- 适用于短 H3 视频批次，当前收集器支持每批 1–6 条；更多任务应拆成独立批次，降低单次失败面。
- 控制器针对 macOS，依赖 `memory_pressure`、`sysctl vm.swapusage`、`caffeinate`、`shasum`、`python3` 和 VPIPE CLI。
- 收集器针对 Windows PowerShell，依赖 OpenSSH `ssh.exe` / `scp.exe`、FFmpeg 和 FFprobe。
- 示例画面合同是 `1280×736 / 56 帧 / 24 fps`；可在 manifest 修改原片合同。内置游戏尺寸衍生只支持已验证的 `1280×736 → 居中裁成 1280×720 → 一次双三次缩放到 1024×576`。
- 脚本不安装模型、不创建 SSH 密钥、不修改 `authorized_keys`、不上传素材，也不启动并行模型进程。
- `tmp/` 生成物、模型缓存和未纳入正式资产闭包的大视频仍不得提交仓库。

## 1. SSH 最小配置

在 Windows 的 OpenSSH config 中使用团队自定别名，且只引用本机私钥；不要把真实主机、用户或公钥写进本目录。

```sshconfig
Host h3-worker
    HostName <worker-host-or-ip>
    User <worker-user>
    IdentityFile ~/.ssh/id_ed25519_h3_worker
    IdentitiesOnly yes
    PreferredAuthentications publickey
    PasswordAuthentication no
    StrictHostKeyChecking yes
    ServerAliveInterval 30
    ServerAliveCountMax 4
```

只读预检：

```powershell
chcp.com 65001 | Out-Null
ssh -o BatchMode=yes -o ConnectTimeout=12 h3-worker `
  "uname -s; uname -m; command -v python3; command -v shasum; memory_pressure -Q | tail -n 1"
```

密码、私钥和二次认证只在对应系统的可信终端处理，不粘贴到聊天、manifest、日志或提交中。

### 跟踪工具与本机私有 profile

推荐采用两层数据：

1. 本目录只跟踪脱敏工具、合同和示例；
2. `tmp/h3-remote-video-pipeline.local-profile.json` 保存本机 SSH 别名、远端工作根、私有素材根和历史 manifest 索引；它受仓库 `/tmp/` 忽略规则保护，但不属于安全存储。

可通过环境变量把约定位置交给其他 Agent 或包装脚本：

```powershell
$env:H3_PIPELINE_PROFILE = 'tmp/h3-remote-video-pipeline.local-profile.json'
```

Agent 只能在当前任务已授权相关素材/远端操作时读取该 profile；profile 的存在不授予上传、启动、删除或外部发布权限。profile 可以包含未公开素材路径和机器别名，但不得包含密码、私钥、Token、恢复码、Cookie 或可直接认证的内容。长期私有真源应位于私有仓库、加密存储或受 ACL 控制的目录，`tmp/` 只作可丢弃工作镜像。

按敏感性分层，不把“被 Git 忽略”等同于“保密”：

| 数据类别 | 推荐位置 | Agent 访问边界 |
|---|---|---|
| 脱敏合同、脚本、经验与示例 | `tools/h3-remote-video-pipeline/` | 可跟踪、可审阅、可复用 |
| 未公开素材、真实路径、机器别名、私有 manifest 与审片标注 | `tmp/private/` 或本项目约定的 `tmp/` profile | 仅在当前任务已授权该项目/机器时读取；不得在输出中回显无关字段 |
| 密码、私钥、Token、Cookie、恢复码 | SSH agent、系统钥匙串、凭据管理器或硬件密钥 | 不进入工作区；脚本只使用别名或注入后的句柄，不读取明文 |
| 不可替代的私有真源 | 私有仓库、加密归档或独立 ACL 目录 | `tmp/` 只留可重建工作副本和哈希索引 |

同一工作区内的 Agent 通常共享同一操作系统账号和文件权限，因此 ACL 不能把一个同账号 Agent 与另一个可靠隔离。如果资料连其他 Agent 都不应看到，就不要放进工作区；把它留在外部受控存储，只在明确授权的任务中提供最小范围的临时句柄。跟踪文档可以公开 profile 的固定入口和字段合同，但不要硬编码真实 IP、用户名、素材绝对路径或凭据。

字段模板见 `templates/local-profile.example.json`。如果团队不需要共享真实本机上下文，可以完全不创建该文件，直接通过命令参数传值。

## 2. 远端目录合同

以下仅是逻辑布局，真实根目录通过 `REMOTE_ROOT` 传入：

```text
<remote-root>/
├─ controllers/run-h3-batch.sh
├─ pipelines/<leaf>/<slug>.vpipeline
├─ input/<batch-specific references>
├─ output/<leaf>/<slug>.mp4
├─ logs/<leaf>/
└─ state/<run-id>/
   ├─ queue.tsv
   ├─ remote-checksums.sha256
   ├─ status.txt
   ├─ progress.tsv
   └─ preflight-checksums.log
```

`run-id` 表示一次不可混淆的执行，`leaf` 表示管线/输出/日志目录，`slug` 同时绑定 queue、pipeline、视频和逐任务日志。三者只允许 ASCII 字母、数字、点、下划线和连字符。

## 3. 准备批次

1. 复制两个模板到 `tmp/<production-run>/`，填写 manifest 和 queue。
2. 每条 `.vpipeline` 的文件名必须是 `<slug>.vpipeline`，输出必须是 `<remote-root>/output/<leaf>/<slug>.mp4`。
3. 输入图、管线、queue 和控制器全部上传后，在远端根目录生成显式 SHA-256 清单；不要用未审阅的递归 glob 把模型缓存或旧任务混入。
4. 运行本地一致性校验：

```powershell
chcp.com 65001 | Out-Null
node tools/h3-remote-video-pipeline/validate-h3-batch.mjs `
  tmp/<production-run>/batch-manifest.json `
  tmp/<production-run>/queue.tsv
```

5. 远端执行：

```sh
cd "<remote-root>"
sh -n controllers/run-h3-batch.sh
shasum -a 256 -c state/<run-id>/remote-checksums.sha256
```

不要把“进程已启动”当成成功。启动前至少要确认脚本语法、模型 sentinel、queue、pipeline、输入和校验清单都存在且字节匹配。

## 4. 启动串行队列

若当前已有父批次，必须等待父批次的 `status.txt` 明确为 `complete`；只等待 VPIPE 进程空档会在父批次两条任务之间误抢模型。

```sh
cd "<remote-root>"
nohup env \
  RUN_ID=<run-id> \
  LEAF=<leaf> \
  REMOTE_ROOT="<remote-root>" \
  VPIPE_BIN="/Applications/Vpipe Manager.app/Contents/Helpers/vpipe" \
  MODEL_SENTINEL="<remote-root>/models/<model>/model-sentinel-file" \
  PARENT_RUN_ID=<optional-parent-run-id> \
  FREE_PERCENT_FLOOR=5 \
  SWAP_LIMIT_MB=6144 \
  caffeinate -dimsu sh controllers/run-h3-batch.sh \
  >logs/<leaf>/controller.stdout.log \
  2>logs/<leaf>/controller.stderr.log </dev/null &
```

队列按以下状态演进：

```text
waiting_for_parent_run → waiting_for_vpipe_slot → running:<slug> → complete
                                                        └──────→ failed
```

同一个 run 可以安全重进：已经存在且通过 MP4 容器检查的输出记为 `SKIPPED_VALID`，不会重跑；失败输出不会被视为完成。恢复同一 run 时保留原始 `progress.tsv` 和首因日志。

## 5. Windows 自动回收

```powershell
chcp.com 65001 | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tools/h3-remote-video-pipeline/collect-h3-batch.ps1 `
  -SshHost h3-worker `
  -RemoteRoot '<remote-root>' `
  -ManifestPath 'tmp/<production-run>/batch-manifest.json' `
  -OutputRoot 'tmp/<production-run>/collected'
```

收集完成条件同时包含：

1. 远端 `status.txt == complete`；
2. 每条远端输出可计算 SHA-256；
3. 下载后 SHA-256 与远端相同；
4. FFprobe 的宽、高、帧率和帧数符合 manifest；
5. FFmpeg 能从头到尾解码；
6. 启用目标尺寸衍生时，衍生件也满足尺寸/帧数并完整解码；
7. 最终 `manifest.json` 和 `collector-status.txt=complete` 已落盘。

结果包含 `raw/`、可选 `target-1024x576/`、逐条四时刻接触表、末段稳定帧、最多六条的比较网格和顺序审片视频。审片件是派生浏览材料，不是生成真源。

## 6. 监控与内存解释

Apple Silicon 使用统一内存。某些监控面板显示的是 Metal/虚拟分配量，可能高于物理内存容量；这个数字单独不能证明 OOM，也不能证明安全。优先观察：

- `memory_pressure -Q` 的系统空闲百分比；
- `sysctl vm.swapusage` 的实际 swap；
- VPIPE 日志是否持续推进；
- 进程是否存活、输出是否增长；
- 单条历史耗时是否发生数量级漂移。

模板默认连续三次、每次相隔 10 秒命中“空闲内存不高于阈值或 swap 超阈值”后终止当前 VPIPE，并保留 `memory-critical.txt`。阈值是机器政策，不是模型通用常量；首次换硬件或分辨率必须重新做单条 smoke。

## 7. 已验证的失败模式

- **无 BOM UTF-8 JSON**：Windows PowerShell 必须使用 `Get-Content -Raw -Encoding UTF8`，否则中文可能被错误解码并导致 `ConvertFrom-Json` 报假语法错误。
- **远端多层引号**：复杂命令容易被 PowerShell、SSH 和远端 shell 三层重解释。优先上传无 BOM、LF 结尾的脚本并运行；状态查询保持单一用途。
- **父任务竞态**：任务间 VPIPE 短暂退出不代表父批次完成。后继控制器必须看父 `status.txt=complete`。
- **显存读数误导**：GUI 的分配数字不能替代 `memory_pressure`、swap 和实际进度。
- **生成完成但未交付**：远端有 MP4 不等于本地可用；只有哈希、媒体合同和完整解码都通过才称“已回收”。
- **后处理反噬**：动漫超分、锐化或光流可能放大脸、手和乐器结构错误；默认保留原片并允许旁路。
- **中间件误归档**：比较网格、代理、contact sheet 和失败修复不是最终素材真源。

## 8. 安全与归档

- 控制器只允许操作由 `REMOTE_ROOT`、`RUN_ID` 和 `LEAF` 精确定位的目录；不要把 `/`、用户主目录或未解析变量用作清理目标。
- 模板不执行递归删除。需要清理时，先只读解析绝对路径并确认仍位于本批次目录。
- 长期保留实际进入剪辑的原始生成片段、pipeline、提示词、种子、模型标识、输入/输出哈希、剪辑时间线、音乐权利记录和人类取舍；未使用抽卡与代理只在成片锁定且最小可重剪闭包通过哈希后删除。
- 模型、VPIPE 和节点实现会变化；同一种子不保证未来逐字节重建。

创作与选卡策略见 [CREATIVE_PLAYBOOK.md](CREATIVE_PLAYBOOK.md)。
