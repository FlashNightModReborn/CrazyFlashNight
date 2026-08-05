# Prime Magic 19：Python 编译器与 seed bank 独立严格复审

## 最终结论

本快照中的 8 张 `19x19` seed 全部是真实完整质数幻方；未发现会推翻 seed、双置换 witness、二进制产物或运行时输入正确性的 blocker。

当前 `n=19` 实用流水线结论为 **PASS WITH ONE DOCUMENTED LIMITATION**：已完成 seed job 的 checkpoint 恢复可靠，但 checkpoint 不保存正在执行的 seed 内部搜索状态。若按用户原规格“中断后不重复已经探索的状态”逐字验收，这一项仍为 **PARTIAL/FAIL**。这不影响现有 8 张 seed 的正确性。

最终审阅快照 SHA-256：

- `python/prime_magic/compiler.py`: `b8de2d548a824ae1dcca7029577fd0f4034686f1ae58c835e3adc5c4f6ae7d8f`
- `python/prime_magic/verify.py`: `c353b863a9a8f7cf73dfcb20a9c2ead5de1141ad44f7fd75c04a41269b6eed51`
- `python/verify_manifest.py`: `e3b8f67d9a15f4377466edccbdfd096db337d1789e755f5a3eb24a7b26c1d676`
- `python/tests/test_prime_magic.py`: `7f2f8650f809243e674165ec1dec3efb5683208eba4139e4a6f68b996042b1fa`
- `seeds/checkpoint.json`: `fd861f63f789006097f53c9ff0ba6e7b009899b9ea51fc8fefca5721be3a0827`
- `seeds/manifest.json`: `4972fc83323d14ee5d9e97de5490136da03bd24eb671388241594dc7aa056f10`
- 独立证据脚本 `agents/code_audit/independent_verify.py`: `da200a8d91c2fbbee2d0cf1375751e742c9969dea7c9617e69cca66c41f3d18f`
- 独立结果 `agents/code_audit/independent_verification.json`: `26a951fca34da3c5fd471b7666985262343f99918a63a64d5d67bd557e4cc066`

| 审阅对象 | 结论 |
|---|---|
| 现有 8 张完整幻方的数学正确性 | PASS |
| JSON / binary 逐项一致、checksum、manifest 绑定 | PASS |
| 编译 witness 与两阶段归约 | PASS |
| PCG32、无偏 bounded sampling、确定性复现 | PASS |
| `<2^64` 确定性 Miller--Rabin、当前数值安全 | PASS |
| 已完成 job 的 checkpoint 产物与元数据恢复校验 | PASS |
| exact involution DFS 的小阶正确性与状态诊断 | PASS |
| seed 内 active-search checkpoint | PARTIAL/FAIL（唯一明确原规格差距） |

## 独立输入与 seed 验证

证据脚本没有导入 `prime_magic`；它另行实现穷尽试除、PM19 binary 解码、canonical SHA-256、矩阵线和与 compiler witness 重建。

输入三份上传文件与项目 fixture 的内容 SHA 一致：

- JSON: `dbc911a354b3d27a1217118a465f17b7633adff76720c4ffb0d6c314e4919dc6`
- TXT: `5525774b72b65bbaf614ff5f0ec42a6d210575818611854bab86786e315babc0`
- Python: `8fc535aae52cbec9003b161d2a2af0d405edf58262223027410a8c0d1f2db3d5`

独立复算输入结果：

- 维度 `19x19`，元素数 361；
- 361 个值均为严格整数、全局互异，并经穷尽试除确认为质数；
- 19 行和与 19 列和全部为 `190000361`；
- 主对角和 `189975263`，相对公共和误差 `-25098`；
- 副对角和 `190092881`，相对公共和误差 `+92520`。

8 张正式 seed 的复验结果：

- 每张的 19 行、19 列、两条对角线共 40 条线都严格等于 `190000361`；
- 每张仍恰好使用原来的 361 个互异质数；
- 8 个 binary 均为 1460 bytes，独立解码后与对应 JSON 的 361 个值逐项相同；
- 8 个 canonical checksum 全部不同；JSON file SHA、binary file SHA、canonical SHA 均与 manifest 相同；
- 8 组 `rowPermutation`、`columnPermutation`、`mainAssignment`、`rowInvolution` 都是合法 witness，且逐项重建原半幻方到对应 seed；
- checkpoint 内嵌 manifest 与正式 manifest 一致，configuration SHA 正确；sidecar verification 绑定当前 JSON file SHA；给定 `--source` 时 manifest verifier 还独立重建全部 route-A witness；
- 官方 verifier：8 JSON 均在 `--require-checksum` 下退出 0；8 binary 均在 binary 模式退出 0。binary v1 本身不嵌 canonical checksum，因此其 canonical/file SHA 由 manifest verifier 绑定；
- `verify_manifest.py` 返回 `valid=true`、`seedCount=8`、`distinctCanonicalChecksums=8`、`errors=[]`；
- Python 单元测试 12/12 通过。

Seed 00 的关键标识：

- compiler seed: `7114379524547582761`
- canonical checksum: `a5e002e9047e02dba2608428ef7416493a0b1ce9148e6e77f3d57be04084413d`
- JSON SHA-256: `3288ab7a2a18f000dfd86971ca3d0602fda7877edc1526a662785625f3a2f12a`
- binary SHA-256: `5867419cf02b32838f4fd5f369a031a4d552b99153e2f78ee897019fcf6fce61`

在最终 compiler SHA 上，用 base seed `20260805`、workers `1`、正式预算独立运行两次；两次 JSON、binary 以及现有 Seed 00 三者均逐字节相同。Manifest 含时长和绝对 output directory，因此 manifest 本身按设计不承诺跨目录字节复现；不可变 seed JSON/bin 已满足字节级复现。

## 两阶段模型的等价性

令新矩阵为

`B[i,j] = A[rho(i), kappa(j)]`，并令 `R(i)=n-1-i`。

对任意双置换解定义

`f = kappa o rho^{-1}`，`tau = rho o R o rho^{-1}`。

把主对角的索引改写为旧行索引 `r=rho(i)`，其和是

`sum_r A[r, f(r)]`。

副对角的列索引为

`kappa(R(i)) = f(rho(R(rho^{-1}(r)))) = f(tau(r))`，

故副对角和是 `sum_r A[r, f(tau(r))]`。由于 `tau` 与 `R` 共轭，`n=19` 时它必有循环型 `2^9 1`。

反向也成立：给定零和 assignment `f` 和循环型 `2^9 1` 的 involution `tau`，把 9 对元素放到镜像位置，把唯一不动点放中心，即可构造满足 `tau=rho o R o rho^{-1}` 的 `rho`；再令 `kappa(i)=f(rho(i))`。因此当前两阶段搜索与原双行列置换可行性问题双向等价，不是只搜索一个更小的启发式子空间。

8 个正式 witness 均已按上述等式独立复算。

## PRNG、无偏采样与数值验证

### PCG32

`Pcg32(42,54)` 的前六个 32-bit 输出为：

`a15c02b7, 7b47f409, ba1d3330, 83d2f293, bfa4784b, cbed606e`

与 PCG XSH-RR reference vector 相同。`randbelow(b)` 使用 `threshold=2^32 mod b`，只接受区间 `[threshold,2^32)`；该区间长度能被 `b` 整除，之后取模，所以不是有偏的简单 modulo sampling。Fisher--Yates 的上下界也正确。

### Miller--Rabin 与安全范围

验证器的七底数集合适用于全部 `0 <= value < 2^64`；实现与独立 sieve 在 `[0,1_000_000]` 穷尽对照无差异。正式 seed 的每一个值还另经穷尽试除验证。

当前最大值 `10254767 < 2^32`，公共和 `190000361 < 2^53`，所以 PM19 binary 的 U32 元素、U64 线和以及 Web `number` 都安全。Compiler 在任何正式输出前拒绝超 U32 元素和超 U64 线和。

## 搜索与 exact solver 复验

- assignment 与 involution 的增量 residual 在 2,000 组小阶随机状态上与全量重算一致；任何返回解都具有正确 permutation / cycle type 和精确零残差。
- 固定 assignment 的 `_exact_involution_search` 在 `n=3,5,7` 共 600 组随机实例上与全枚举 oracle 一致；未触发 node budget 时没有发现完备性错误。
- 曾存在的“最后允许一步命中 0 却返回失败”已修复。最小 assignment 与 involution 反例都在 `steps=1` 时返回精确零解。
- `exact_solver_exhausted` 曾有黏滞语义风险；最终实现会按调用复位，并用 `exact_solver_exhausted_subproblems` 与 `exact_solver_budget_stops` 分别累计完整穷举和预算截断。复验第一次完整穷举后为 `(1,0,True)`，第二次被全局预算截断后为 `(1,1,False)`，风险已关闭。应在文档中继续说明布尔值只描述最近一次调用，两个 counter 才是聚合诊断。
- 当前实例 deviation scale 为 `38/19=2`；最终 stats 同时保存真实 `absoluteError` 和 `scaledResidual`，不再把最好误差低报一半。

## 已回放并确认关闭的历史 blocker

- composite 输入曾可经 compiler 发布；现在搜索前和发布后都跨 subprocess 调用独立 verifier，`[[4]]` 被拒且无正式输出。
- final seed 曾可缺 checksum、缺 magic sum，或忽略 `size/order`；现在均严格绑定，bool 和非字符串声明也结构化拒绝。
- assignment / involution 最后一步精确命中曾被丢弃；现已修复。
- `encode_binary` 曾接受空、ragged、bool、超 U32 输入并产生 decoder 不接受的文件；现均在编码前拒绝，size 0 binary 也显式拒绝。
- 超 U32 prime 曾先遗留 JSON 再在 `struct.pack` 失败；现在 preflight 后才构造两种 serialization，反例退出 1 且不遗留正式或临时 seed 文件。
- checkpoint 曾在 binary 删除或 JSON 篡改后静默跳过；现在校验连续 index、受限路径、长度、file SHA、canonical SHA、JSON/bin magic sum 和独立 verifier。
- checkpoint/manifest 顶层 `magicSum`、source、configuration 曾未充分绑定；把 `magicSum` 改成 `2` 的原反例现在同时被 resume 和 `verify_manifest.py` 以 exit 1 拒绝。
- checkpoint record 的 `compilerSeed`、`requestedBaseSeed`、worker 选择和 verification 状态曾可被单独篡改；现在与派生 job seed、worker 记录及 seed JSON compiler metadata 交叉绑定，原反例退出 1。
- 未知 `prime-magic-seed/v999` 和 malformed flat JSON 曾缺少严格、结构化拒绝；最终 verifier 明确枚举支持格式并返回结构化非零报告。
- Windows 顶层 `resource` import blocker 已用 platform guard 修复；macOS/Linux `ru_maxrss` 单位已区分。
- worker 0 曾随 workers 数变化而改变随机流；现在 workers=1/2 时 worker 0 使用相同 job seed。
- seed JSON 曾含 volatile stats；stats 已移至 manifest，JSON/bin 可逐字节复现。

## 唯一明确原规格差距：active-search checkpoint

当前 checkpoint 在一整张 seed 成功后才写入。它不保存正在执行 worker 的：

- outer attempt、restart、step；
- PCG `(state, increment)`；
- 当前 assignment、pairing、residual 与 best state；
- exact DFS frontier、当前 mask、分支位置或已探索分块。

因此进程若在 seed 内中断，该 seed 的已探索状态会重做。日志写入又早于 checkpoint，二者之间崩溃还可能在恢复后追加一条重复 job 日志。README 已诚实标为 seed-job 粒度；当前 `n=19` 单 job 很短，实际重做成本小，但这仍不满足原始强 checkpoint 语义。

若将来启用小时级 exact tail，应序列化 per-worker PCG、启发式状态和分块 DFS frontier，并把“结果记录、checkpoint、日志提交”设计成可幂等事务。当前短任务可以保留现实现，但验收应明确写成 job-level checkpoint。

## 非阻断风险与测试盲点

- `acceptance_rate = accepted_moves / candidate_moves` 不是传统逐提案接受率：分母统计所有被评分邻居，分子还包含未进入分母的 kick。现有值可作内部趋势指标，但建议改名或拆成 `selected/evaluated` 与 `kickMoves`。
- 正式 Python suite 已增至 12 项并覆盖 seed CLI、manifest 顶层 magic sum 和缺失 checkpoint artifact。此前其余反例均已人工回放，但 involution 尾步、PCG reference vector、workers=1/2、小阶 exact oracle、Windows RSS 分支尚未全部固化为 CI 自动测试；建议继续收录这些最小反例。

## 最终 PASS / FAIL

- **当前 8 张 seed：PASS。** 数学、质数性、互异性、40 条线、witness、JSON/bin/checksum 全部独立确认。
- **当前 `n=19` 实用 compiler：PASS WITH DOCUMENTED LIMITATION。** 没有发现仍会发布错误 seed 的路径；确定性与正式 Seed 00 字节复现通过。
- **严格满足用户全部离线 checkpoint 规格：FAIL 一项。** active seed 搜索状态不能恢复，会重做该 job。
- **`exact_solver_exhausted` 语义风险：RESOLVED。** 最终 counters 能区分穷举完成与预算截断。
- **不存在需要阻止现有 seed 进入 TypeScript runtime 的审计发现。**
