# Portrait Worker P1

本目录只验证 **Codex CLI → Luna Max → JSONL / JSON Schema → controller 严格闭包** 是否可用。当前不是 FFDec 头像生成器，也不读写生产 portrait manifest、`enemy_properties`、`pets.xml`、PetPanel wire 或任何现役头像。

## 固定边界

- CLI 必须由 `--codex-exe` 或 `CF7_PORTRAIT_CODEX_EXE` 显式传入绝对路径；不扫描 `PATH`，也不把 VS Code 版本目录写进仓库。
- 每个角色使用一个新的 `codex exec` 进程；固定请求 `gpt-5.6-luna`、`reasoning_effort=max`、ephemeral、ignore user config/rules、read-only sandbox 和 `approval_policy=never`。
- stdout 只按 JSONL 解析。controller 取唯一 `turn.completed` 前的最后一个 `agent_message`，并再次校验 schema、batch/input/prompt/role 闭包、任务全集、候选白名单、frame 和 crop。CLI 在 WebSocket 失败后成功回退 HTTPS 时会先发可恢复的 `error` / `item.error`；只有随后存在唯一成功 `turn.completed` 与合法最终消息才可接收，同时必须把这些诊断逐条 hash 记入 run。`turn.failed`、完成后 error 或缺少成功终态仍 fail-closed。
- `proposal` 与 `independent_review` 不共享上次结果，必须取得不同 PID、不同 role prompt digest 和相同 fixture 语义结果。
- 格式或瞬态失败最多重试一次且必须创建新进程；认证失败、模型不可用、静态能力缺失和孤儿进程失败不重试。
- timeout 只终止本次 exact PID 进程树并验证已发现的子 PID 不残留，不按进程名清理。
- report 与 stdout/stderr artifacts 不覆盖既有证据；它们记录 CLI 绝对路径、版本/hash、probe、PID、输入/图片/prompt/schema/stdout/result digest、退出码、timeout 和重试。

## 验证

纯本地 fail-closed 测试不调用真实模型：

```powershell
node tools/portrait-worker/test-codex-cli-luna-worker.js
```

只探测显式 CLI：

```powershell
node tools/portrait-worker/run-capability-pilot.js --codex-exe "C:\absolute\path\to\codex.exe" --probe-only
```

运行 P1 的两个独立 Luna Max 角色：

```powershell
node tools/portrait-worker/run-capability-pilot.js --codex-exe "C:\absolute\path\to\codex.exe"
```

默认证据写入 `tmp/portrait-worker/capability-pilot-<timestamp>/`。成功状态 `capability_verified` 只证明固定 12 项 fixture、单张小图、传输与 controller 闭包；它不等于 P2 头像 pilot、艺术验收、promotion、消费者验证或生产可用。

路线、身份并集和后续 phase 见 [`docs/怪物头像统一资产与Luna-CLI-Worker路线评估备忘-2026-08-05.md`](../../docs/怪物头像统一资产与Luna-CLI-Worker路线评估备忘-2026-08-05.md)。
