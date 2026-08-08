# Arena P5 real WebView2 authority journey

先运行：

```powershell
node tools/workbench-live-e2e/arena-live-e2e.self-test.js
node tools/workbench-live-e2e/arena-live-e2e.js --candidate-root <direct-child-candidate-root> --allow-read-only-live-seed
```

runner 把真实 `crazyflasher7_saves.json` 逐字节复制到专用 `cf7_agent_p5_arena_authority`，原槽全程只读。它绑定 candidate 的 PID、build identity、payload closure、当前 attempt 与 CDP endpoint，随后只通过固定 `agent_control openArena` 请求 AS2 的正式 `openArenaForAgent → stage_select_arena_redirect panel_request` 路径。

正向链路的关闭、选卡与确认使用 CDP Input 命中可见元素，其中关闭按钮固定为生产 DOM selector `.arena-panel .workbench-close-btn`，并要求被动观察器捕获 `event.isTrusted=true`。被动观察器允许重开时页面 `snapshot` 请求先于对应 `panel_cmd open` 入账，但只接受晚于本次 opener 且响应晚于该 open 的同 callId exchange；成功 enter 的本地 close 也允许先于对应 response 入账，但必须晚于该 enter request 且携 `dismissReturnStack:true`，避免把真实 WebView 排序竞态误判为失败。这证明输入来自真实 candidate WebView 页面，但不是物理鼠标证明，因此报告固定 `physicalInputAttestation=false`。唯一直接 `Bridge.send` 是重开后旧 cardId 的无写 `preview` 对抗探针；它必须返回 `stale_authority` 且 Flash dispatch 增量为 0，绝不用于成功业务路径。

成功报告固定证明：XML/JSON source digest、10 张标准 session card、关闭重开后 capability 全部轮换、旧 capability fail-closed、Web enter 不携经济字段、Host 重建值与 AS2 接受值一致、真实浏览器截图、原始存档逐字节不变，以及 candidate 受信 shutdown。Host→Flash 增量与重建命令只从 `/logs` 规范化快照的 `records[].line` 读取，旧 `lines[]` 形状不参与证明。完整 save-universe 不变量继续覆盖全部非目标玩家 JSON 与 owned SOL；唯一显式排除的是 Launcher 每次启动按设计重写 `writtenAt` 的内部 `.launcher-version-marker.json`，它不是玩家存档。报告与 transcript 位于 `tmp/workbench-live-e2e/arena/<run>/`。
