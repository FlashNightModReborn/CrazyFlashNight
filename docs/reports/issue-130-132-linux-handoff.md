# #130 / #131 / #132 Linux 候选交接

起点 main 精确 SHA：`23ec828cd04c783c86abb016c1f080eb814d41ba`。
容器最初 `work` HEAD 为 `9f1192f1aa932eeac152f98e00882926e3dc3d65`，工作树干净；核对远端后建立唯一候选分支 `codex/inventory-balance-offline-130-132`。保留原 work 分支，未合并或推送 main。

交付是源码/离线候选，三单均保持 **Open**，PR 只用 Refs。没有 runtime 发布、SWF 重编、生产加载切换或真实存档操作。

## 逐单结果

| Issue | 候选范围 | 结果与未完成原因 |
| --- | --- | --- |
| [#130](issue-130-inventory-summary-isolation.md) | 恢复公共严格校验；仅库存响应隔离坏摘要并提示；旧/部分 probe 未解锁时返回失败 | Linux Node/Chromium 通过；Windows Host、全量 Launcher、WebView2/真实 socket 未验证。 |
| [#131](issue-131-offline-projection.md) | 四家族限定静态闭包、保守生成器、完整身份/字节清单及 --check | 1042 节点可在离线候选移除；重名/weapon/未知范围保留。真实正常加载、代表物品和 AVM1 仍待 Windows。 |
| [#132](issue-132-weapon-summary-parity.md) | 可复跑 TS 源码模型/工具对照与全部 612 profile 报告 | 输出差异 0；完整 evidence 门另有 1 残差，8 个 unresolved profile 另有 16 条 validation 错误；真实 AVM1 与生产取舍待独立裁决。 |

三单的 base 均为上面的 main SHA。分主题提交：#130 `db6e856ff4e926d8dd4e2ba48ff84cb1d9136e9a`；#131 `5c162233feabadc84ccfd5b20d96986123bfb43e`；#132 `bd5c444c81362700f082364271ad832798f4ac4b`。远端 draft PR 在最终回包列出；本文件不把自身提交 SHA 写入自身。

## 实际机器验证

仓库根执行：

| 命令 | 本轮真实结果 |
| --- | --- |
| `node tools/test-inventory-runtime.js` | 92/92 通过 |
| `node tools/test-workbench-primitives.js` | 13/13 通过 |
| `node tools/test-inventory-workbench-modules.js` | 38/38 通过 |
| `node tools/test-kshop-presenters.js` | 41/41 通过 |
| `node tools/test-workbench-components.js` | 17/17 通过 |
| `node tools/test-panel-contracts.js` | 70/70 通过 |
| 现有 KShop/NPC harness，经临时 Linux Chromium 驱动 | 1024×576、1366×768、1920×1080 各 157/157 与 133/133；生产 warning 格可见、ARIA 正确、pageerror=0 |
| `node tools/validate-doc-governance.js` | 收口通过；有历史链接/行数非阻断提示。早先未建总交接链接的失败已修正 |
| `git diff --check` | 通过 |

工作目录 `tools/cf7-balance-tool`：

| 命令 | 本轮真实结果 |
| --- | --- |
| `npm run typecheck` | 初始化缺失的本机派生物后通过；前置说明见下 |
| `npm test` | **926 通过、1 失败，共 927**；monster-flags 排序断言在精确 base 独立副本复现同一失败（22 通过、1 失败） |
| `npm test -- packages/xml-io/tests/nonweapon-runtime-projection.test.ts` | 7/7 通过 |
| `npm test -- packages/xml-io/tests/weapon-summary-parity.test.ts` | 22/22 通过 |
| `npm run roundtrip-check` | 109/109 通过 |
| `npm run balance-sync -- --check` | 失败：AMML3/data 缺 ledger，禁止回退 |
| `npm run balance-check` | 失败：373 profile、17 条 failure；详细分项见 #132 报告 |
| `npm run explosives-balance-check` | 39/39 通过 |
| `npm run armor-balance-check` | 失败：3XF特勤头盔未进入防具计划 |
| `npm run melee-balance-check` | 失败：计划中的光刀狮子在当前 XML 找不到 |
| `npm run potion-balance-check` | 失败：台账和九龙药剂摘要漂移 |
| 两个新 CLI generate / `--check` | 通过；最终提交后再生成，使 HEAD 绑定对应候选 |

以上红灯原检查器和作者输入均未被本轮修改，不运行 sync 修数据、不放宽断言。全量测试失败为本地 Node/ICU 排序下首个 partial 行“下线怪/残缺怪”的预期冲突；只证明该失败在基线也存在，未在本任务修复。

fresh checkout 初始化：`npm ci --ignore-scripts --no-audit --no-fund` 的默认 cache 首次因目录权限失败，改用可写 `--cache /tmp/cf7-balance-npm-cache` 成功。旧 tracked tsbuildinfo 缺 dist，执行 `npx tsc -b packages/core packages/xml-io packages/cli --force --pretty false`；Web typecheck 的两个导入报告缺失，按现有 CLI 生成 field-scan 报告与一次真实零操作 batch-preview 报告后通过。报告/缓存不提交；没有修改 tsconfig、validator 或断言。Windows 如已有这些本机报告，不需复制 Linux 绝对路径。

如为全新工具 checkout，先建立内容为 `{"updates":[]}` 的本机临时 JSON，再执行（输出均为工具忽略的本机报告）：

```sh
npm run field-scan -- --project project.json --output reports/field-usage-report.json
npm run batch-preview -- --project project.json --input <该临时JSON路径> --output reports/batch-preview-report.json
npm run typecheck
```

本容器无 dotnet/PowerShell，原 Windows Host focused/full、Edge 原 runner、Flash/AVM1 和 WebView2 均为 **未运行**。Chromium 直接 harness 不等于原 Edge runner 的附加动效/指针/滚动量测，更不代签原生运行。

## 可复跑产物与导入

生成物只在 `tmp/issue-131-projection` 和 `tmp/issue-132/weapon-summary-parity.json`。前者 61 XML + manifest；XML 净省 **928,648 bytes**，计入 manifest 后总产物净省 **337,755 bytes**。不称运行堆、加载速度或 GC 收益。后者逐 profile 及 3724 个输入哈希，保留全部规则/数据残差。

交接目录 `tmp/linux-130-132-handoff` 保存日志、临时 Chromium 驱动、SWF 静态扫描、全量报告、分主题补丁与增量 Git bundle；最终回包附 zip 和 SHA-256。原始 27MB FFDec 导出保留在容器 `/tmp/issue131-asLoader{Shared,Logic}-pcode`，其扫描摘要和导出日志进入证据包。

Windows 最短步骤：

1. 在隔离分支导入 draft PR；不能 fetch 时先取得 base，再 `git bundle verify <candidate.bundle>`、`git fetch <candidate.bundle> codex/inventory-balance-offline-130-132`，或按顺序 `git am <patches>`。先保护本机差异，不覆盖 main。
2. 重跑上述 Linux 门和两个 generate/`--check`，审阅所有已知红灯；按 #130 报告用 exact SDK 10.0.300 跑相关 focused + canonical Launcher 全量和原 Edge harness。新增 Host 用例尚无执行证明。
3. 按 #131 报告仅在隔离资源副本做正常加载/代表物品与身份对账；#132 审阅 QJZ171 残差、unresolved 数据红灯、规则反例，并另外安排真实 AS2 等价验证。生产接入另行裁决。

**Go：** 导入源码候选，进行 Windows 合成验收。**No-go：** 未通过原生回归就合入生产、切生产加载、删原树/字典/缓存、自动重放未知写、发布 runtime 或关闭 #130/#131/#132。任何 Host/Web 锁不一致、新解锁资格或来源/身份变化都应阻止推进。
