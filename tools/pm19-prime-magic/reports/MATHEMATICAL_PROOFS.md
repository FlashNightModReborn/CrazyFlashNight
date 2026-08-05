# 数学证明汇总

本文件给出正式实现所依赖的最短完整证明。更细的 trade 枚举、反例和实验数据见 `ORBIT_AND_TRADES.md`；求解模型与 witness 见 `ROUTE_A.md`。

## 1. 双置换问题的等价归约

令 `R(i)=n-1-i`，`B[i,j]=A[rho(i),kappa(j)]`。定义原行到原列的置换

\[
f=\kappa\circ\rho^{-1}
\]

以及原行集合上的 involution

\[
\tau=\rho\circ R\circ\rho^{-1}.
\]

由于 `n=19` 时 `R` 的循环型为 `1^1 2^9`，`tau` 具有相同循环型。令 `r=rho(i)`，则

\[
\begin{aligned}
D_1(B)
 &=\sum_i A_{\rho(i),\kappa(i)}
  =\sum_r A_{r,f(r)},\\
D_2(B)
 &=\sum_i A_{\rho(i),\kappa(R(i))}
  =\sum_r A_{r,f(\tau(r))}.
\end{aligned}
\]

反向，给定任意列置换 `f` 和循环型 `1^1 2^9` 的 `tau`，`tau` 与 `R` 共轭，所以可选 `rho` 使 `tau=rho R rho^-1`；令 `kappa=f rho` 即恢复原双置换。故原问题与以下条件双向等价：

\[
\sum_r A_{r,f(r)}=S,
\qquad
\sum_r A_{r,f(\tau(r))}=S.
\]

这解释了正式编译器的两阶段结构：先找 exact-sum assignment `f`，再找 exact-weight involution `tau`。每个二循环 `(r,s)` 在两个匹配的并中形成一个 `2×2` 交替四环，唯一固定点形成两个对角线共享的中心边。

## 2. 固定 `f` 后的线性精确模型

对固定 `f`，令 `z[r,s]`（`r<s`）表示 involution 选中二循环 `(r,s)`，`z[r,r]` 表示唯一固定点。约束为：

\[
z_{rr}+\sum_{s\ne r} z_{\min(r,s),\max(r,s)}=1\quad\forall r,
\]

\[
\sum_r z_{rr}=1,
\]

\[
\sum_r A_{r,f(r)}z_{rr}
+\sum_{r<s}\bigl(A_{r,f(s)}+A_{s,f(r)}\bigr)z_{rs}=S.
\]

因此第二阶段是带一个精确权重等式的完美匹配/CP-SAT，而不是 QAP。第一阶段本身是带精确权重等式的 assignment：

\[
\sum_c x_{rc}=1,
\quad\sum_r x_{rc}=1,
\quad\sum_{r,c} A_{rc}x_{rc}=S.
\]

Hungarian algorithm 只能优化一个线性代价，不能单独保证最后的精确等式；CP-SAT、MILP、伪布尔或专用搜索才是正确模型。把 `rho,kappa` 同时作为变量时出现乘积项，才是 quadratic-assignment-like 表述。

## 3. 同步中心化置换保持完整幻方

令 `A` 已是完整幻方，公共和为 `S`；`pi` 是索引置换且 `pi R=R pi`。定义

\[
B_{ij}=A_{\pi(i),\pi(j)}.
\]

对任一固定 `i`，由于 `pi` 双射：

\[
\sum_j B_{ij}=\sum_j A_{\pi(i),\pi(j)}=S.
\]

列同理。主对角线：

\[
\sum_i B_{ii}=\sum_i A_{\pi(i),\pi(i)}=S.
\]

副对角线使用交换条件：

\[
\sum_i B_{i,R(i)}
=\sum_i A_{\pi(i),\pi(R(i))}
=\sum_i A_{\pi(i),R(\pi(i))}=S.
\]

所有值只重排位置，所以质数性、全局互异和元素集合也保持。命题得证。

## 4. 合法置换数量

对 `n=2m+1`，`R` 有 `m` 个镜像二元轨道和一个中心不动点。与 `R` 交换的 `pi` 必须固定中心、任意置换这 `m` 个二元轨道，并可在每个轨道内独立翻向；反向构造显然仍与 `R` 交换。故

\[
C_{S_n}(R)\cong C_2\wr S_m,
\qquad |H|=2^m m!.
\]

`n=19,m=9` 时：

\[
|H|=2^9\cdot9!=185,794,560.
\]

## 5. 转置与 D4 闭包

在保持 rook geometry 的坐标变换中，无转置的映射为 `(i,j)->(rho(i),kappa(j))`。若要求把无序对 `{主对角线,副对角线}` 映回自身，则必有：

\[
\kappa=\rho\quad\text{或}\quad\kappa=R\rho,
\qquad \rho R=R\rho.
\]

再允许转置，得到四个互不相交的正规形式；`pi in H`：

\[
\begin{array}{ll}
(\pi(i),\pi(j)), & (\pi(i),R\pi(j)),\\
(\pi(j),\pi(i)), & (\pi(j),R\pi(i)).
\end{array}
\]

因此完整自然坐标群大小为

\[
|G|=4|H|=743,178,240.
\]

不能再乘 8：`D4` 的 identity 与 180° 旋转已分别对应 `pi=id` 与 `pi=R`，即 `H∩D4={e,r180}`；所以 `|HD4|=|H||D4|/2`。

## 6. 轨道与稳定子

一般有 orbit-stabilizer：

\[
|G\cdot A|=|G|/|Stab_G(A)|.
\]

本任务的 361 个值全局互异。若纯坐标置换 `g` 满足 `gA=A`，每个唯一值都必须回到自身位置，故 `g` 固定全部格点，只能是 identity。因此

\[
Stab_G(A)=\{e\},\qquad |G\cdot A|=743,178,240.
\]

8 个正式 seed 又经精确关系判定两两不在同一 `G` 轨道，所以 seed bank 的不重叠状态总数为 `5,945,425,920`。后一句是对这 28 对 seed 的有限计算结论，不是从群阶单独推出。

## 7. 均匀采样

对 9 个镜像对做无偏 Fisher–Yates 得到均匀 `sigma in S9`，再取 9 个独立 bit 决定每对内部翻向。表示唯一，所以得到 `H` 上严格均匀样本；再独立均匀取一个单轴反转 bit 和一个 transpose bit，得到 `G` 上严格均匀样本。bounded RNG 必须用 rejection 消除 modulo bias。

运行时每次独立直采整个群，而非在上一状态做局部随机游走；因此不需要混合时间，也不会因 involution 生成元相消产生显眼二周期。任何抽到的群元素先验合法，rejection 只服务随机数均匀性，不是“生成后验证失败重试”。

## 8. 保边际且保元素集合的 trade

固定两行 `r,s` 和列子集 `C`，在每个 `c in C` 交换 `A[r,c]` 与 `A[s,c]`。每个列内只交换两个值，列和与元素集合自动保持；两行改变量互反，且合法的充要条件为

\[
\sum_{c\in C}(A_{s,c}-A_{r,c})=0.
\]

对角增量只取决于 `C` 是否包含 `r,s,R(r),R(s)`，故 membership mask 下为 `O(1)`。双列版本转置即可。

标准整数零空间中的 `2×2` 加减 move 一般产生新数，因此不能与上述 fixed-multiset trade 混同。传统 contingency-table Markov basis 的连通性也不能直接移植到 361 个全异标签的 0/1 fiber；bounded-support move 图可能不连通。

## 9. 已证明、已构造与仍未知的边界

- **已证明并构造：** 所附具体 19 阶半幻方存在双置换完整解；8 个正式 seed 有完整 witness。
- **理论可终止但未作为主实现：** 在给定有限候选质数集合和数值上界后，完整 CP-SAT/MILP/穷举必终止。
- **实际可运行：** 本实例的两阶段离线编译器；运行时群变换为固定 `O(n^2)`。
- **未证明：** 任意 19 阶质数半幻方都能双置换升级；任意整数阶均存在全异质数幻方；当前 trade move family 连接整个 fixed-multiset fiber。
- **需纠正的问题表述：** 方阵阶数 `n` 必须是正整数，不存在“任意正实数阶”。`n=2` 时全异半幻方已不可能，故更不可能有统一覆盖所有正整数的无条件构造。
