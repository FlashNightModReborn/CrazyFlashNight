# 路线 A：双置换升级的独立审计、等价归约与求解结果

## 结论

现有 `19×19` 质数半幻方**存在**行、列双置换，使两条对角线同时等于公共和
`190000361`。这是构造性证明，不是启发式猜测。

本分支独立得到一张完整幻方；主线随后以更强的“两阶段 assignment + involution”
方法生成了 8 张 seed。本分支又在不导入主线验证代码的条件下交叉核验了主线
`seed00`，其矩阵、双置换、assignment、involution、JSON checksum 和紧凑二进制
全部一致且合法。

## 1. 输入审计

对上传的 JSON、TXT 和 Python 脚本做了以下独立检查：

- JSON 与 TXT 的 361 个矩阵元素逐项相同。
- 维度为 `19×19`，361 个元素均为严格整数且全局互异。
- 对每个约一千万的元素试除至 `isqrt(p)`；361 个元素全部被确定性证明为质数。
- 19 个行和与 19 个列和均重新计算为 `190000361`。
- 原始主对角线为 `189975263`，残差 `-25098`。
- 原始副对角线为 `190092881`，残差 `+92520`。
- 最小/最大质数为 `9666061 / 10254767`；元素和所有线和均远小于 `2^53`。
- 上传 JSON SHA-256：
  `dbc911a354b3d27a1217118a465f17b7633adff76720c4ffb0d6c314e4919dc6`。
- 本分支定义的 `U32LE` 规范矩阵摘要：
  `c8fb19d381b5b4aa1bcd994527ee7d2146555f7493a40b46666396a8145742e8`。

上传的 `prime_semimagic_search(2).py` 在补齐其声明依赖 SymPy 后，以默认
`n=19, seed=1, restarts=100` 实际运行成功，并逐项复现上传矩阵。运行输出保存在
`supplied_script_run.txt`，SHA-256 为
`9238042d1bdc85b2cfd19904b4017c8709237c62b4893975ded97c43df179802`。

源脚本返回结果时的正确性是 Las Vegas 型的：它会验证质数、互异、行列和；但搜索
只接受严格改善，平台时会直接放弃该 restart，因此“搜索失败”从来不构成无解证明。
其 `verify()` 也故意不检查对角线，符合它只生成半幻方的定位。当前数值范围内
SymPy `isprime` 是确定性的；本审计仍使用了完全独立的穷尽试除，避免同源验证。

## 2. 双置换问题的严格等价形式

令位置集合、原行集合、原列集合均为 `0..18`，`R(i)=18-i`。双置换矩阵为

`B[i,j] = A[rho(i), kappa(j)]`。

### 2.1 两个 assignment 加一个指定循环型 involution

从任意 `(rho,kappa)` 定义

- `f = kappa ∘ rho^{-1}`，它是“原行 -> 原列”的完美匹配；
- `tau = rho ∘ R ∘ rho^{-1}`，它是原行上的 involution。

因为 `R` 有一个固定点和 9 个二循环，所以 `tau` 的循环型严格为 `1^1 2^9`。于是

`D_main = sum_r A[r, f(r)]`

以及

`D_anti = sum_r A[r, f(tau(r))]`。

第二式来自
`kappa(R(i)) = f(rho(R(i))) = f(tau(rho(i)))`。

反过来，若给定列置换 `f` 和循环型为 `1^1 2^9` 的 `tau`，则 `tau` 与 `R`
共轭，必存在 `rho` 使 `tau=rho R rho^-1`。令 `kappa=f∘rho`，便恢复一组双置换。
因此以下条件与原问题**双向等价**：

1. `f` 是一个 assignment，且 `sum_r A[r,f(r)] = S`；
2. `tau` 是循环型 `1^1 2^9` 的 involution；
3. `sum_r A[r,f(tau(r))] = S`。

这不是只保证可行的充分条件；它覆盖全部双置换解。

### 2.2 9 个四环加一条公共边

若 `c` 是 `tau` 的唯一固定行，两个匹配在 `(c,f(c))` 共用一条边。每个二循环
`(r s)` 给出一个 `2×2` 交替四环：

- 主匹配边：`(r,f(r)), (s,f(s))`；
- 副匹配边：`(r,f(s)), (s,f(r))`。

所以两个对角匹配的并集恰为 9 个顶点不交的四环和 1 条重复中心边。这也是 weighted
exact-cover / exact-weight near-perfect-matching 表述的来源。

### 2.3 消除的巨大表示对称性

与 `R` 交换的置换群大小为

`|C(R)| = 2^9 * 9! = 185794560`。

固定 `(f,tau)` 后，恰有这么多种位置编号 `(rho,kappa)` 表示同一对对角匹配。
循环型 `1^1 2^9` 的 involution 数为

`19! / (2^9 9!) = 654729075`。

原始位置状态数 `19!^2` 在按该对称性取商后为
`79644584068956697190400000`。两阶段模型直接在 `(f,tau)` 上搜索，避免了
`185794560` 倍的目标等价状态，这是它显著优于直接双排列搜索的核心原因。

## 3. 求解模型比较

### 固定行排列后的 side-constrained assignment

固定 `rho`，令二元变量 `x[i,c]` 表示 `kappa(i)=c`：

- 每个位置恰选一列；
- 每个原列恰用一次；
- `sum A[rho(i),c] x[i,c] = S`；
- `sum A[rho(R(i)),c] x[i,c] = S`。

这是只有 361 个二元变量的、带两个精确权重等式的 assignment。普通 Hungarian
algorithm 只能优化单个线性代价，不能保证两个精确等式；必须使用 CP-SAT、MILP、
伪布尔求解或专用 exact-weight matching。任意固定 `rho` 的无解也不代表双置换无解。

### 直接 MILP / QAP

用 `x[i,r]`、`y[i,c]` 表示行列排列时，对角项是 `x*y`，因此是 0-1 quadratic
assignment-like feasibility problem，而非普通 assignment。引入主/副位置边变量
`M[i,r,c]`、`N[i,r,c]` 可精确线性化；本分支模型有 13,718 个二元变量、798 个
原始约束，并加入了镜像行对的 `9!*2^9` 对称破缺。模型正确，但比两阶段归约重得多。

### exact cover、SAT/SMT、MITM 与 branch-and-bound

- 9 个四环加中心边可写成 weighted exact cover；纯 Algorithm X 只处理覆盖，仍需
  精确和约束或残差 DP。
- SAT 需要对大整数和做伪布尔编码；SMT/QF-LIA 可表达 `AllDifferent` 与精确和，
  但在该小而稠密的排列问题上通常不如 CP-SAT/专用邻域搜索。
- 对固定 `f`，第二阶段是：枚举中心 `c`，在剩余 18 个行顶点上找 9 条完美匹配边，
  使 `A[c,f(c)] + sum_(r,s)(A[r,f(s)]+A[s,f(r)]) = S`。每个中心有 `17!!`
  个完美匹配，完整空间共 `654729075` 个 involution；带剩余上下界、模筛和 memo 的
  DFS/meet-in-the-middle 可做精确尾部求解或给固定 `f` 出具穷尽证书。
- 直接 simulated annealing / tabu / memetic / VNS 很适合发现 witness，但除非把剩余
  子问题交给精确搜索，否则失败不能证明不可达。

### 实际推荐

对本实例，最佳工程路线是主线已实现的混合算法：

1. 在 `f in S_19` 上用 O(1) 交换 delta 找第一条精确和 assignment；
2. 把第二条对角约束降为 exact-weight involution matching；
3. 用配对 rewire、中心交换、多启动搜索；必要时由有界 DFS 精确收尾；
4. 将 witness 交给不共享搜索逻辑的验证器。

CP-SAT/MILP 最适合作为独立模型、受限邻域精确收尾和不可行证书工具，而不是当前
实例的首选发现器。

## 4. 本分支独立求解实验

本分支还实现了不使用上述两阶段分解的直接 VNS，状态为 `(rho,kappa)`：

- 行换位、列换位的两个对角 delta 都是 O(1)；
- 一阶邻域共 `2*C(19,2)=342` 个换位；
- 平台时扫描 `C(19,2)^2=29241` 个行列组合换位；
- 两次同行或同列换位作为精确 3-cycle / `2+2` cycle finisher；
- 四次随机换位 kick，多启动；
- 目标为 `x^2+y^2`，其中 `x=(D1-S)/2`、`y=(D2-S)/2`。除以 2 来自所有质数和
  `S/19=10000019` 均为奇数的严格格点不变量。

确定性 `seed=3` 在 36 次迭代、约 `0.0286 s` 找到：

- `rho = [3,6,16,18,10,15,8,5,9,2,4,1,12,7,0,11,14,13,17]`
- `kappa = [7,16,6,17,11,9,10,4,12,15,2,3,5,0,13,18,1,8,14]`

独立验证确认两条对角、所有行列均为 `190000361`，且元素集合与原矩阵完全相同。
该矩阵的 row-major U32LE SHA-256 为
`499a8394035fc72c97b94b4ed31041740f2c2ac893210952a3d7b016c4122dc5`。

但 100 个种子、每个 1 秒、4 进程 benchmark 仅 1/100 命中；其余运行往往已把
半残差降到个位数却不能精确命中。这说明直接二维梯度搜索存在严重格点平台，不能因
一次幸运的 28 ms 成功而高估稳健性。相比之下，主线两阶段编译器的 100 次确定性
benchmark 是 100/100，median 70.94 ms、P99 292.96 ms；两阶段法应作为正式实现。

受控精确模型对照（仅作为求解器行为，不是无解证据）：

- 固定 `rho=identity` 的 361-binary HiGHS MILP：10.22 s、2521 nodes、59008 LP
  iterations，未找到 incumbent；状态为 time limit，不代表该固定行序无解。
- 同一固定行序的 CP-SAT：10.01 s、111188 branches、42490 conflicts，状态
  `UNKNOWN`，同样没有不可行证书。
- 全位置 13,718-binary MILP（中心行固定为 0）：10.06 s 尚停留根节点切割，未有
  incumbent；这验证了直接线性化的工程劣势，而非结构障碍。

## 5. 主线 seed00 的独立交叉核验

`cross_validate_main_seed.py` 没有导入主线 compiler/verifier，使用穷尽试除和直接
`struct` 解码验证了以下事实：

- `f` 与 `(rho,kappa)` 均为双射；`kappa(i)=f(rho(i))`；
- `tau` 是 involution，唯一固定行为 `1`；
- 9 个二循环为 `(0,16),(2,12),(3,4),(5,11),(6,10),(7,15),(8,13),
  (9,17),(14,18)`；
- `rho(R(i))=tau(rho(i))` 对全部 19 个位置成立；
- `sum A[r,f(r)] = sum A[r,f(tau(r))] = 190000361`；
- JSON 矩阵等于原矩阵按声明的 `rho,kappa` 双置换所得；
- 361 个数仍为同一互异质数集合，19 行、19 列、两对角全部精确；
- canonical checksum：
  `a5e002e9047e02dba2608428ef7416493a0b1ce9148e6e77f3d57be04084413d`；
- JSON SHA-256：
  `3288ab7a2a18f000dfd86971ca3d0602fda7877edc1526a662785625f3a2f12a`；
- binary SHA-256：
  `5867419cf02b32838f4fd5f369a031a4d552b99153e2f78ee897019fcf6fce61`；
- 二进制长度 1460 bytes，头部与 361 个 U32LE 元素均和 JSON 一致。

因此，路线 A 已完成：现有半幻方可仅通过行列置换升级为真实完整质数幻方。

## 6. 明确区分证明与实验

### 已证明

- 输入矩阵是合法的互异质数半幻方，公共和为 `190000361`。
- `(rho,kappa)` 与 `(f,tau)` 表述双向等价。
- `tau` 必须且只需具有 `1^1 2^9` 循环型；两个匹配并集为 9 个四环加中心公共边。
- 至少存在多组双置换精确解；本分支解与主线 `seed00` 均有完整 witness 和独立复验。

### 仅有实验支持

- 主线默认预算在当前机器/当前实例上的 100/100 成功率和延迟分布；这不是对任意
  半幻方或任意随机种子的终止性证明。
- 直接 VNS 的命中率、MILP/CP-SAT 的限时表现。

### 未证明 / 不应声称

- 固定 `rho=identity` 是否存在列排列解；两个精确求解器只返回限时/UNKNOWN。
- 任意 19 阶质数半幻方都能通过双置换升级。
- 启发式编译器在任意输入或任意随机种子上必然终止。

## 7. 本分支产物

- `input_audit.json` / `audit_input.py`：上传输入的独立审计。
- `double_permutation_search.cpp`：直接双排列 VNS 研究原型。
- `prime_magic_19_route_a.json` / `.bin`：本分支独立完整 seed。
- `solution_verification.json` / `verify_and_package.py`：本分支 seed 的独立复验。
- `cross_validate_main_seed.py` / `main_seed00_cross_validation.json`：主线 seed00 与
  两阶段 witness 的独立交叉验证。
- `milp_fixed_rows.py`、`milp_position.py`、`cp_sat_fixed_rows.py`：精确模型原型。
- `heuristic_benchmark.json`、`milp_*_10s.json`、`cp_fixed_identity_10s.json`：实验记录。
