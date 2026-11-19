# Runtime v2 四域枚举与请求冻结实测

2026-11-19，在同一台 Windows 11 专业版机器上，用 PowerShell 7.6.9、Git 2.49.0.windows.1 对照旧实现与本轮实现。两份本地工作树以 `5514b0cf1572200f81cbd0e1a2da0bc1482499ac` 为共同输入。早期并发审计使用的基线为 `48eac0b8`，当时四域共 3364 条路径。本次输入的 policy 域多 5 条。

| 本地计时范围 | 次数 | 耗时 |
| --- | ---: | ---: |
| 旧版逐域调用 `Get-Cf7RuntimeV2DomainFiles -Mode Index` 并计算四份路径清单摘要 | 1 | 79.735 秒 |
| 新版建立一次 index 快照，四域共用该快照并计算相同摘要 | 1 | 11.349 秒 |
| 新版在空测试队列运行 `new-runtime-build-request.ps1 -SourceKind Treeish`，从开始冻结到请求在本地队列可见 | 1 | 38.584 秒 |

前两行用 `Stopwatch` 计时。两次输出的四份有序路径清单 SHA-256 逐域相同，共 3369 个不同的相对路径，分属 artifactSource 1087、producerRecipe 13、toolchainLock 3、policy 2266。两次运行先后进行，磁盘缓存与机器后台负载未控制。该差值只对应本机这一组清单枚举样本。

第三行来自请求 `917A7B50012F92A2DD7188FB799595653D0F12F5F3E818488038E3612EE1767E` 的 `request.phases.json`。其计时包括身份计算、构造及验证源码包、请求入队。独立按冻结提交的 3369 条路径、Git 文件模式和对象 ID 重建稀疏树，得到与请求相同的 `f0afd3a00be120eca6ad8b69d7fdaa2d3fe87773`。旧实现缺少同起止点的整段计时。远端取源、构建、双签、正式部署和游戏启动均在这个计时窗口之外。

历史兼容性另以临时 Git index 载入已部署提交 `c34eb00656923f85c3c9b5d3f5eae5eed0d30a54`，运行本轮 `verify-runtime-consensus.ps1 -Staged -HistoricalSource`。历史源 `9da1fd776ef16d889dc74650dca5367cd895761a` 的 43 个部署文件通过校验，签名来自本地 X509 与 GitHub OIDC/Sigstore 两个故障域，返回码为 0。

## 一次真实双机构建的阶段时间

冻结源码 `3a188ef4b79edd0a66a6d3c75ebd9fdb4e001abe` 的请求 `BD4CD24E…` 在本机用时 32.046 秒入队。独立文档提交 `3003684ca4` 在构建期间进入主线。

| 阶段 | 单次实测 |
| --- | ---: |
| 本地 worker 领取请求至发布签名结果 | 236.595 秒 |
| 其中，验证构建身份后至编译完成 | 191.535 秒 |
| GitHub 创建运行至两个作业全部结束 | 8 分 43 秒 |
| 其中，托管构建 / 独立证明作业 | 7 分 42 秒 / 53 秒 |
| 本地完整发布策略，依赖就绪后 | 86.53 秒，50/50 通过 |

两台构建机产出的 43 个文件具有相同的闭包摘要 `9E1E36D96D1D18BD36476B8344F212701FAC986AFA33877C423999C56F27ADB0`。本机首次全检发现隔离工作区缺少锁定版本的 Playwright，从本地缓存恢复后原候选通过全检。两端并行运行，表中耗时不可相加为总用时。该来源的实际记录覆盖构建、签名和发布前验证。[GitHub 构建与签名记录](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/44553442324)
