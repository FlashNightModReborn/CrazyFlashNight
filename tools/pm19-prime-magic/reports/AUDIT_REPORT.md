# 19 阶质数幻方 Seed Compiler / Orbit Engine 审计报告

## 0. 最终结论

本专项已经得到真实完整解，不需要启用半幻方 fallback：

| 项目 | 结论 |
| --- | --- |
| 输入半幻方 | 严格有效；公共行列和 `190000361` |
| 原始对角线 | `189975263 / 190092881`，不是完整幻方 |
| 路线 A | 构造性成功；已证明两阶段归约与原双置换问题双向等价 |
| 完整 seed | 正式交付 8 个；每个 361 个互异质数、40 条线精确相等 |
| seed00 canonical SHA-256 | `a5e002e9047e02dba2608428ef7416493a0b1ce9148e6e77f3d57be04084413d` |
| seed00 JSON SHA-256 | `3288ab7a2a18f000dfd86971ca3d0602fda7877edc1526a662785625f3a2f12a` |
| seed00 binary SHA-256 | `5867419cf02b32838f4fd5f369a031a4d552b99153e2f78ee897019fcf6fce61` |
| 单 seed orbit | 精确 `743178240` 个不同状态 |
| 8-seed bank | 精确 `5945425920` 个不同状态；8 个轨道两两不交 |
| TypeScript 热路径 | Node 实测约 `1.1 µs/board`；不需要 WASM |
| 推荐真实棋盘频率 | 默认 `10 Hz`，强干扰阶段 `20–30 Hz`，锁定阶段 `5 Hz` |
| 推荐视觉刷新 | `60–144 Hz` RAF；扫描线、噪声、辉光、扰动全部 shader 化 |
| 已知规格差距 | checkpoint 为 seed-job 粒度，不恢复 in-flight 搜索 frontier/PRNG |

“存在完整幻方”由实际矩阵与独立 witness 证明；性能数字属于本环境实验，不是数学定理。

## 1. 输入审计

### 1.1 文件身份

| 文件 | SHA-256 |
| --- | --- |
| `prime_semimagic_19.json` | `dbc911a354b3d27a1217118a465f17b7633adff76720c4ffb0d6c314e4919dc6` |
| `prime_semimagic_19.txt` | `5525774b72b65bbaf614ff5f0ec42a6d210575818611854bab86786e315babc0` |
| `prime_semimagic_search.py` | `8fc535aae52cbec9003b161d2a2af0d405edf58262223027410a8c0d1f2db3d5` |

JSON 与 TXT 的 361 个矩阵项逐项相同。机器可读结果在 `input_audit.json`。

### 1.2 独立复算

| 检查 | 结果 |
| --- | --- |
| dimension / count | `19×19 / 361` |
| strict integer | 通过；拒绝 bool/float |
| deterministic primality | 361/361 通过 |
| global uniqueness | 361/361 互异 |
| row sums | 19 个均为 `190000361` |
| column sums | 19 个均为 `190000361` |
| main diagonal | `189975263`，误差 `-25098` |
| secondary diagonal | `190092881`，误差 `+92520` |
| prime range | `9666061..10254767` |
| JS safe integer | 元素与全部线和均通过 |
| canonical matrix checksum | `31442f7886f19320a5c1d5992898e9e25e2a473b0a622a963c57ff50714dcd10` |

这里的 primality 由 64 位确定性 Miller–Rabin 使用 bases
`2,325,9375,28178,450775,9780504,1795265022` 完成；适用范围严格限定为 `0 <= p < 2^64`。seed00 又由完全独立的 `isqrt` 穷尽试除交叉验证，避免两个 Miller–Rabin 实现共享错误。

### 1.3 对所附搜索脚本的审阅

直接运行基础环境会因未安装 `sympy` 失败；在隔离环境补齐 SymPy 1.14 后，默认参数逐字节复现附件矩阵，20 次运行输出 SHA 均为 `9238042d...`。

正确部分：

- 先构造 18 条等和质数行，再由列 deficit 强制最后一行；
- 行内交换不破坏已完成行和；最后一行始终由列 deficit 定义；
- 只有通过质数、互异和行列验证的结果才返回，属于 Las Vegas 搜索。

缺陷与边界：

- 未锁定依赖；基础环境不可直接运行；
- `verify()` 不检查维度细节、严格整数、JS safe range、checksum、对角线；
- repair objective 只统计“合法 deficit 数”，只接受严格改善，容易平台；
- `_score()` 在深层候选循环内重复质数判定，存在明显冗余；
- 任意一次 plateau/预算耗尽都不构成无解证明。

## 2. 此前容易混淆的数学结论

1. **任意行列置换只自动保行和、列和，不自动保两条对角线。**
2. **原双置换问题是 QAP-like，但存在更强结构归约。**用 `(f,tau)` 可把它拆为 exact-sum assignment 与 exact-weight involution matching。
3. **普通 `2×2` 整数零空间 move 不自动保持原质数集合。**固定 361 个全异标签时需要额外精确加和关系。
4. **`9!*2^9` 只是同步中心化子。**加入单轴反转与 transpose 后是 4 倍而非 8 倍；180° 旋转已在同步子群中。
5. **一般需除稳定子，但本任务不需要。**全局互异值使任何固定矩阵的纯坐标稳定子平凡。
6. **阶数必须是正整数，不是正实数。**`n=2` 已不可能存在全异半幻方，所以不能声称覆盖任意正整数的无条件统一构造。

## 3. 路线 A：为何能实际求解

令 `C=S/n=10000019`。正式搜索使用缩放偏差 `w=(A-C)/2`；除以 2 是严格奇偶不变量，不改变零和条件。

### 阶段一：主对角 exact assignment

寻找列置换 `f`：

`sum_r w[r,f(r)] = 0`。

状态就是长度 19 的列排列；交换两行对应的列可 `O(1)` 更新残差。正式实现使用确定性 iterated local search：全邻域最佳改善、平台 kick、多启动。没有使用未分析的 squared two-dimensional objective。

### 阶段二：副对角 exact involution

寻找循环型 `1^1 2^9` 的 `tau`：

`sum_r w[r,f(tau(r))] = 0`。

状态是一固定点与 9 对 matching。两对 rewire、固定点与 pair endpoint 交换均可 `O(1)` 更新。若启发式预算耗尽，可启用 bounded exact DFS；seed00 的 `f` 上独立测试在 458336 nodes、约 0.268 s 找到精确 `tau`。

### 转回行列置换

把每个 `tau` pair 放在关于位置 9 镜像的两行，固定点放中心；令 `kappa(i)=f(rho(i))`。完整证明见 `MATHEMATICAL_PROOFS.md`。

### 实际稳健性

| 方法 | 当前输入实验 |
| --- | --- |
| 两阶段 ILS + involution | 100/100 成功；search median `70.94 ms`、P99 `292.96 ms` |
| 直接 `(rho,kappa)` VNS | 100×1 秒仅 1/100 命中；幸运 witness 约 28.6 ms |
| 固定 identity 行序 CP-SAT/MILP | 10 秒均为 UNKNOWN/time limit；不代表无解 |
| 全位置线性化 MILP | 10 秒仍在根节点；工程上明显劣于结构归约 |

因此正式选择是“两阶段专用搜索 + 独立验证 + 可选 exact tail”，不是直接 QAP 或纯退火。

## 4. 模型路线比较

| 路线 | 表达能力 | 当前判断 |
| --- | --- | --- |
| Hungarian assignment | 不能表达 exact target equality / 第二对角 | 不适用单独求解 |
| side-constrained assignment | 361 binary + exact weights | 正确；适合 CP-SAT/MILP 对照 |
| QAP / 线性化 MILP | 完整但变量约 1.37 万且对称性大 | 正确、偏重 |
| exact cover | 覆盖容易；权重和仍需 PB/DP | 可作四环模型，不首选 |
| CP-SAT | AllDifferent、权重等式、no-good cuts | 最合适的通用精确尾部 |
| SAT/SMT | 可表达；大整数 PB 编码/对称性成本高 | 次选独立验证模型 |
| MITM | 固定 `f` 的 matching tail 很合适 | 推荐 exact tail 优化 |
| branch-and-bound | 剩余 min/max、gcd/residue 可剪枝 | 推荐与启发式混合 |
| SA/tabu/memetic | witness 发现能力强，失败无证书 | 只作补充，不作存在性判断 |

## 5. 路线 B：trade 的价值和停止证据

当前矩阵不是缺少 trade：完整 MITM 枚举得到 800 个 proper 双行、542 个 proper 双列 trade，其中经典最小 `2×2` 仅 2 个。三步合法 move 把残差

`(-25098,+92520) -> (+22,+52)`，`E1: 117618 -> 74`。

但从该状态完整枚举一步与两步邻域仍无精确命中；初态 delta 的 Smith 格为 `2Z^2`，目标修正属于该格，所以没有静态模障碍，阻塞来自组合/状态依赖。结论是：

- trade 很适合 large-neighborhood 与局部修复；
- bounded-support move 图连通性未知；
- `E1=74` 不是“几乎证明存在”，深度 2 失败也不是“证明无解”；
- 路线 A 已精确成功后，继续投入 trade 不再改变产品决策。

## 6. 路线 C：从零构造的严格边界

本次不需要用路线 C 才得到 seed，但仍作如下决策：

| 方法 | 存在性 | 理论终止 | `n=19` 实用性 | Web 实用性 |
| --- | --- | --- | --- | --- |
| 半幻方生成 + 路线 A | 当前实例已有 witness | 启发式发现非必终止；验证必终止 | **已实测可用** | 只离线 |
| bounded prime pool + CP-SAT/MILP | solver 可给有限模型证书 | 是 | 直接 361-cell 模型偏重 | 否 |
| 普通整数幻方 + 361 项质数 AP | 需要实际长 AP，不由普通幻方保证 | 条件性 | 不实用 | 否 |
| 对称质数对/中心互补 | 只能降低部分约束 | 条件性 | 可作新构造模板，未完成一般证明 | 否 |
| 全枚举 | 若给定有限质数池则终止 | 是 | 不可接受 | 否 |

不能拿 Green–Tao 一类存在性定理替代具体 361 项 AP、数值范围和生成耗时。本专项只证明所附具体 prime set 的 19 阶完整解存在，不声称任意阶或任意半幻方都可升级。

## 7. 搜索目标函数

初始误差 `(e1,e2)=(-25098,92520)`：

- `E1=117618`；尺度直观但有大菱形平台；
- `E2=9189860004`；强迫优先压最大残差，但远端单轴容易支配，推广时还可能越过 `2^53`。

正式路线不用二维 `E1/E2` 作主目标，而用阶段化 lexicographic objective：

1. 第一 assignment 残差绝对值；精确到 0 后冻结 `f`；
2. involution residual 绝对值；精确到 0 后结束；
3. tie-break 只用于选择等价改善，不牺牲已满足的精确等式。

精确尾部建议同时使用：

- 奇偶/gcd 预缩放；
- 小质数 residue bitset，仅作必要过滤；
- 剩余边贡献 min/max；
- 剩余 delta gcd；
- matching memo / MITM；
- 先走接近目标的边顺序。

平方目标可用于直接 VNS 的远域导航，但必须先除严格 gcd、用宽整数，并在末端切换 exact residual，而不能仅靠“很小的平方误差”停止。

## 8. 离线编译器工程审计

正式 Python 实现只依赖标准库；原脚本的 SymPy 只保留为 fixture/provenance。

具备：

- PCG32 可序列化确定性随机流；bounded draw 使用 rejection，无 modulo bias；
- `--workers` spawn multiprocessing；每个 worker 独立派生 stream，汇总时确定性选最低 worker id；
- checkpoint 对 source SHA、algorithm、随机种子、worker 数、全部预算参数、output dir 做完整 fingerprint；已完成 seed job 不会重复；
- JSONL 记录 moves/s、接受率、目标改善 trace、最佳误差、最长 plateau、重启数、exact nodes、RSS；
- 这里的 `acceptance_rate` 明确定义为“选中的改善 move / 被评估邻居数”，kick 单列；best-improvement 全邻域扫描不存在 SA 式逐提案接受概率；
- seed JSON 不包含 wall-clock/RSS，故相同输入/config 的 seed JSON 与 binary 可字节级复现；统计只在 manifest/log；
- CLI 在搜索前和每个输出后都跨进程调用独立验证器；composite 输入无法被提升为 prime seed；
- manifest 使用相对路径，绑定每个 JSON/bin file SHA、canonical SHA 与验证结果；`verify_manifest.py` 可整体复核。

checkpoint 粒度为“完成的 seed job”；突发中断至多重做当前 in-flight job。当前 100 样本最慢 search 约 0.358 s。若未来把单 job 扩成小时级精确搜索，应把 DFS frontier/PRNG state 降到节点级 checkpoint，而不能沿用当前粒度。这是当前实现相对“节点级不重复”的明确规格差距，而非隐藏成已完成能力。

## 9. 完整 seed 与序列化

正式 seed bank 在 `seeds/`：8 组 JSON、PM19 binary、每 seed 验证报告与 manifest。

Binary v1：

- magic `PM19`：4 bytes；
- version：U16LE；
- size：U16LE；
- magic sum：U64LE；
- 361 个 row-major U32LE；
- 总长度 `16 + 361*4 = 1460 bytes`。

Binary 的外部完整 SHA-256 由 manifest 绑定；JSON 同时包含 canonical matrix SHA。`manifest_verification.json` 已对全部 8 对 JSON/bin 重算 file SHA、canonical SHA、值等价和全部不变量。

## 10. 数值策略

当前数据：

- `max element = 10254767 < 2^24`，即便 float32 也可精确表示；正式仍用 U32 integer；
- `magic sum = 190000361 < 2^32 < 2^53`；JS number 精确；
- verifier 用 Python arbitrary-precision integer 累加，故更大 line sum 即使超过 `2^53` 仍不会在离线误算；
- primality 的当前确定性实现仅承诺 `<2^64`，超出时明确拒绝，不退化成未标注 probable-prime。

推广策略：

1. 元素仍 `<=U32`、仅 line sum 超 `2^53`：runtime 仍搬 U32；离线用 Python int/BigInt；UI 的 magic sum 预先序列化字符串，不在热路径求和。
2. 元素 `>U32` 且 `<U64`：binary v2/BigUint64Array，或运行时搬 `Uint16` label index + 静态 decimal glyph 数据；WebGL2 可拆成 two-U32。
3. 元素 `>=2^64`：必须换有证明范围的确定性算法或理论可终止试除；不能沿用当前 7-base MR 声称确定性。

## 11. Orbit 与运行时架构

默认每次独立均匀直采群元素：

- 9 个镜像 pair Fisher–Yates；
- 9 个独立 orientation bit；
- 1 个单轴反转 bit；
- 1 个 transpose bit；
- 361 次 U32 搬运到调用方 buffer。

热路径没有质数判定、行列复验、对象字典、`map`、闭包、字符串或 backing-store 分配。引擎提供 caller-owned `nextInto` 与内部双缓冲 `nextView`；PRNG 状态可保存恢复。8-seed wrapper 只在 8 个已验证引擎间均匀选择。

独立有放回采样单 seed 时，连续重复概率 `1/743178240`；约 50% 出现任意历史碰撞需约 32098 帧。历史碰撞不是短周期。若产品要求绝不重复，可对 mixed-radix rank 做 keyed permutation 后无放回遍历；默认没有必要。

## 12. 性能结论

### 离线

同一 AMD EPYC 9V74 / Python 3.12 环境：

| 流程 | Samples | Median | P95 | P99 | Max |
| --- | ---: | ---: | ---: | ---: | ---: |
| 原半幻方脚本 | 20 | 0.9875 s | 1.0178 s | 1.0293 s | 1.0322 s |
| 路线 A search core | 100 | 0.0708 s | 0.2459 s | 0.2911 s | 0.3135 s |
| 独立双格式验证 | 100 | 0.0767 s | 0.0866 s | 0.0933 s | 0.1109 s |
| 完整升级 e2e | 100 | 0.1497 s | 0.3257 s | 0.3710 s | 0.3902 s |

所以对当前生成器，完整幻方相对半幻方的**审计后增量**中位约 `15.16%`；只算数学搜索约 `7.17%`。半幻方生成加完整升级的中位时间约 `1.1372 s`。这是同机当前实例的工程比值，不是复杂度定理。

### Runtime CPU

最终真实 seed、Node 24/V8 13.6、250000 samples、25000 warmup：

| 操作 | Median | P95 | P99 | boards/s |
| --- | ---: | ---: | ---: | ---: |
| 单 seed orbit + 361 U32 copy | 1.091 µs | 1.172 µs | 1.572 µs | 849247 |
| 8-seed bank + orbit | 1.172 µs | 1.252 µs | 1.612 µs | 775469 |

30 Hz 真实切换只消耗约 `35 µs/s` 量级。Worker 消息/调度成本通常高于计算；默认留主线程，只有整个 renderer 移入 OffscreenCanvas Worker 或主线程已有尖峰时才启用 SharedArrayBuffer 双缓冲。

浏览器端基准设计与未执行项见 `PERFORMANCE_REPORT.md`。云端 Chromium 的安全策略拒绝访问容器 localhost，故本环境没有 GPU/DOM/Canvas/Worker 数字；任何未执行的 UA/GPU/GC 项均明确标记，不用 Node 数据冒充。

## 13. 渲染决策

| 路线 | 决策 |
| --- | --- |
| 361 DOM nodes | 仅调试；正式拒绝，避免字符串/layout/paint/GC |
| Canvas2D | 兼容 fallback；离屏 glyph atlas，棋盘更新时重绘，RAF 只合成 |
| WebGL2 | 默认；361 instances、每次 1444-byte integer upload、1 draw |
| WebGPU | 仅当主 renderer 已是 WebGPU 或批量数千棋盘；不为本效果单独引入 |

shader：扫描线、辉光/色偏、cell noise、亮度脉冲、轻微 UV 抖动、FAULT 遮罩、残差染色。CPU：状态机、低频合法 board、少量 uniform 与 U32 buffer。

建议状态机：

| 状态 | 数学数据 | 视觉表达 | 建议时长/频率 |
| --- | --- | --- | --- |
| SCRAMBLE | 仍只显示合法 orbit，可叠假残差 UI | 高频跳变、噪声、局部遮罩 | 0.4–0.8 s / 20–30 Hz |
| ROW ACQUISITION | 合法 board；逐行 reveal checksum | 行扫描闭合 | 0.5 s / 10 Hz |
| COLUMN COHERENCE | 合法 board；逐列 reveal | 列锁定栅格 | 0.5 s / 10 Hz |
| DIAGONAL LOCK | 合法 board | 两条对角依次点亮 | 0.25–0.5 s / 5–10 Hz |
| MATRIX SYNCHRONIZED | 显示 `190000361` | 中心同步脉冲、低噪声 | 1–3 s / 5 Hz |
| FAULT INJECTION | board 仍合法；错误残差只是独立 overlay | 红色偏移、短暂错误读数 | 0.15–0.4 s / 20 Hz |
| RESCRAMBLE | 换 orbit/seed | tearing/glitch 后重入 | 0.2–0.5 s / 20–30 Hz |

若确实要显示“数学上错误的临时矩阵”，应把它定义为不可交互的 visual-only fault layer，不能覆盖 authoritative board buffer；这样不会让 debug/截图误把假矩阵当 seed。

## 14. 最终十项决策

1. **完整幻方增加多少离线成本：**当前同机 e2e median `149.7 ms`，约为原半幻方生成 median 的 `15.16%`；search-only `70.8 ms / 7.17%`。
2. **是否得到真实 19 阶完整质数幻方：**是，正式 8 张；另有独立第 9 个 witness。
3. **是否值得用于电子战背景：**值得。离线增量小，运行时与半幻方同阶；双对角锁定能转化为玩家可见的最后同步事件。
4. **运行时能否达到目标刷新率：**CPU 余量极大；实际瓶颈只可能在 fragment fill-rate/后处理，不在数学变换。
5. **是否需要 WASM：**不需要。
6. **推荐多少 seed：**交付并推荐 8；约 11.7 KiB binary 数据，轨道状态 `5.945e9`。若包体极端敏感，4 个也足够。
7. **推荐真实变换频率：**默认 10 Hz；稳定 5 Hz；故障/重洗 20–30 Hz。不要把 144 Hz shader RAF 等同于 144 次 board copy。
8. **哪些放 shader：**扫描线、噪声、辉光、色偏、脉冲、UV 扰动、FAULT mask；CPU 只更新合法整数 buffer/phase uniform。
9. **继续用高能力模型的任务：**新阶数/新 prime set 的可达性证明、CP-SAT/精确尾部重构、seed-specific automorphism 审计、渲染瓶颈跨层诊断。
10. **可交给低成本模型的冻结任务：**按既定配置批量 farm seed、运行 verifier/manifest audit、checksum/binary 打包、固定测试矩阵、目标机 benchmark 收集与 shader 参数扫表。

## 15. 验收材料索引

- `MATHEMATICAL_PROOFS.md`：正式证明；
- `ROUTE_A.md`：求解归约、模型、独立交叉验证；
- `ORBIT_AND_TRADES.md`：群、trade、局部盆地完整细节；
- `STAGE_LOG.md`：每阶段证明/实验/阻塞/停止证据；
- `PERFORMANCE_REPORT.md`：Node/Chromium/渲染性能；
- `code_audit/review.md`：独立实现审计、反例回放与 checkpoint 限制；
- `input_audit.json`、`manifest_verification.json`、`seed00_cross_validation.json`：机器可读验收。
