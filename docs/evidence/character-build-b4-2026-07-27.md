# Character Build B4 隔离候选 E2E 证据

**状态**：`e2e_verified / NOT_DEPLOYED`

**日期**：2026-07-27（UTC+08）

**隔离存档槽**：`cf7_agent_character_build_b4`

本文是受 Git 跟踪的持久审计索引。截图、JSON、SOL 与候选二进制仍位于本机 `tmp/`，不纳入仓库；它们即使日后被清理，本文保留的候选身份、行为时序、关键字段和逐文件哈希仍可用于核对原始件。本文不授予 promotion 或发布权。

## 1. 候选身份与部署边界

- Candidate root：`tmp/runtime-candidates/v2/c-82821b0020bc-08846e81b3-20260727t082058481z-31b9b691`
- Core SHA-256：`356D26D96C6CEDEFE47B033581FDE93658A2F8FAD864AB07BC582B4F36BEBB80`
- Build identity：`82821B0020BC0925E04A241B00AEFA0ADB234E4D328580B858CA7E31F7DFEAC2`
- Payload closure：`6F9D5474A02333BA0299B91889298904D5FA0E2F4DDAC50E9789C6D10F92513D`
- Artifact source：`2795242C42816A8CBB799ED81D092CDE8EF1AEF7E08828579DF92BB22E579381`
- Metadata createdAtUtc：`2026-07-27T08:21:39.1431275Z`
- 正式 runtime Core 在验收后仍为 SHA-256 `15E22D10B450A8616766D25F709D761C20B5A773BA60314680060348B7970EC2`。

常规 prepare 首先拒绝了与本票无关、既存的 `launcher/web/modules/arena-unit-param-presets.js` 派生差异；该用户改动被保留。随后以 `launcher/build.ps1 -BuilderId local-dev -SkipPrepare -SkipPolicy` 只生成隔离候选。构建结果明确为 `NOT_DEPLOYED`，没有替换正式 runtime。

## 2. 首次真实写入与安全退出

Attempt：`fe8ba09416d94b3280cba885d7b622e1`。

1. 从 `launcher_snapshot:sol` 载入真实克隆槽。
2. 装备往返：背包 `等离子切割机` 装入长枪槽，再恢复 `M4A1战术版`。
3. 药剂往返：药剂 I 改为 `加强mp药剂 ×87`，再恢复 `加强抗生素药剂 ×117`。
4. embedded tuning 使用 exact worn-loadout source，提交 `M4A1战术版 +3 → +4`。
5. 强化石 `208689 → 208680`；成就计数 `装备强化次数 1 → 2`。
6. 同一个 density toggle DOM 在 Character Build candidates 与 embedded tuning 间迁移；compact/full 均零横向溢出、零 authority 请求。
7. Character Build finalize 返回 `persistence.success=true`、`changed=true`、`liveChanged=true`、`loadoutRevision=3`、`liveRevision=3`、`drugRevision=3`。
8. SAFEEXIT 在观察到 fresh `Shadow saved`、`sv:1|sv:1|q:77|sv:2` 与 `shadow confirm: true` 后才发送 `EXIT_CONFIRM`；shutdown fence pass，Flash exit code 0。

关键日志时间：

- build snapshot accepted：`16:26:57.636`
- tuning commit：`16:34:46.609`
- finalize success：`16:35:26.162`
- final save：`16:37:27.384`
- shutdown fence pass：`16:37:27.479`
- Flash exit code 0：`16:37:29.088`

## 3. 同候选重启读回

Attempt：`3374f7c04fd948b3be8bd16de55d1f88`。

- 使用完全相同的 candidate 与隔离槽再次启动。
- Character Build 独立读回 `M4A1战术版 +4` 与 `加强抗生素药剂 ×117`。
- embedded tuning 独立读回 `M4A1战术版 +4`、强化石 `208680`、下一目标 `+5`。
- density 偏好仍为 `full`，页面只有一个 toggle。
- 无写关闭返回 `persistence.success=true`、`changed=false`、`liveChanged=false`。
- 第二次 SAFEEXIT 再次取得 fresh shadow save、shutdown fence pass 与 Flash exit code 0；Guardian PID 27144 终止，`launcher_ports.json` 被移除。

关键日志时间：

- build snapshot accepted：`16:39:05.452`
- tuning snapshot confirmed：`16:39:35.820`
- no-op finalize：`16:39:47.734`
- final save：`16:40:07.152`
- shutdown fence pass：`16:40:07.242`
- Flash exit code 0：`16:40:08.900`

最终 JSON/SOL 字段：

- `inventory.装备栏.长枪.name = M4A1战术版`
- `inventory.装备栏.长枪.value.level = 4`
- `inventory.药剂栏.0.name = 加强抗生素药剂`
- `inventory.药剂栏.0.value = 117`
- `collection.材料.强化石 = 208680`
- `ext.成就.cnt.装备强化次数 = 2`

## 4. 自动门与异构审阅

- Launcher Release：`1536/1536`。
- Character Build workbench：三视口主矩阵 `591/591`，storage hidden-body `4/4`，合计 `595/595`；pageerror 0、非预期 requestfailed 0。
- Character Build standalone：`193/193`；dressup：`211/211`。
- Equipment tuning：三视口 `249/249`（各 `83/83`）；pageerror/requestfailed 0。
- Item-grid visual matrix：`17/17`；strict workbench atlas：`48/48`。
- 核心 Web 单测：session 22、tuning runtime 25、tuning model 51、inventory runtime 24、workbench modules 13、safe exit 7、lifecycle 8、focus 11、focus integration 12、components 7、inspection viewport 4，全部通过。
- strict UI audit：0 errors / 0 warnings。
- CSS bundle：18 imports、16,887 行、SHA-256 `BCCE7F2F27113F4DD864CE9C1F4D7DF763AED9E42399E6EA8E715A015591A5BD`。
- 文档治理通过；`git diff --check` 无 whitespace error。

最终 Kimi Code k3 审阅使用 `--thinking --plan --max-steps-per-turn 100`，没有降级模型或关闭 thinking。session `450b3f7a-73c9-47f9-bcc9-98a0703720f8` 的裁决为 GO，`0 Blocker / 0 High / 0 Medium / 5 Low`。五项 Low 是零余量行数 ratchet、缺进入调制失败注入、无用 `data-density`、早期失败时少量装饰字段陈旧、26/28px density 按钮；均不要求扩大本轮实现。

此前 AS2 focused 六套件的本机原始 Output Panel 副本位于 `tmp/flash-character-build-final-20260726-1910/compile_output.txt`，SHA-256 `9E8699823508B323444D0730C4C2619ABD9EA709189A61A275B0B18E90DB6D7A`，结果为 529/529、Compiler Errors/Warnings 0/0。本 UI 密度轮没有改 AS2，因此没有把该记录误称为 2026-07-27 重新编译。

## 5. 本机原始件哈希

本机证据根：`tmp/character-build/e2e/20260727T082058-final-density-candidate`。

`logs/launcher.log` 在闭环后的大小为 1,190,692 bytes，SHA-256 `B9533B45165C0D53677763393D36F868122CC7F650F52A9BF01C5BE3FA5AA5C3`。

| 文件 | Bytes | SHA-256 |
|---|---:|---|
| `before-final-density.json` | 32660 | `85921FCBE85A526E552AF18BDF5FB9B46B5D3CD228453500D5848A38D24E5709` |
| `before-final-density.sol` | 41211 | `ECDD4416FA75828CB0E325CA82F6D3820CF315347F914C1E8A6DD04C4171AEA8` |
| `tuning-compact-real.png` | 671870 | `333FBD216FF6A492BB64C671098B7B4C0DD04DDB9D074816BEF3014E4FE341FB` |
| `tuning-full-real.png` | 691290 | `210F372C9BB2A693AAD1F306EAAFA7BC97ABDD683EB572E9097814DC5D7663C1` |
| `tuning-after-real-enhance.png` | 677459 | `890C08BB36CC2AEF38166C34745387C111A1F7B6C87BEA1FC577D81A93BF9407` |
| `build-before-finalize.png` | 555766 | `F04911130F63D9DC991B03972D7F8BB2F5E851DE0BA6CEC5B72E89264A064195` |
| `after-save-before-restart.json` | 32660 | `F32B9BD74DC117C71459717C95C6D944763A8BC316BE81DE1B0008C4FDAFDCF0` |
| `after-save-before-restart.sol` | 41211 | `4CDF2BA234A5C688975726CB962276E7C1C75B1A432BD637A276E14D1B9CC566` |
| `restart-readback-build.png` | 567268 | `A72F1C9B54A2581E28962C7EE7F7CDCFA879C2550F0B4AB6446E983B46568375` |
| `restart-readback-tuning.png` | 687013 | `5BE3B95D4128C4B9A46CFB1E02DFAA2C4C32E86E0F617F91DF4F97740B24C15F` |
| `after-restart-readback.json` | 32660 | `044A17AF0CCCBB15DD17056272FA84159A904831EA2B0C388223E465C76FDDDD` |
| `after-restart-readback.sol` | 41211 | `909EF18FC0DB7921CA7B72DFC12BBE069B789537D6DF4637C2310DF6367C7903` |
| `runtime-build-metadata.v2.json` | 624 | `570DBCE7FDAEF2969823276A32156BBDB86BAA77E0943EB90F362D78A8789F6F` |
