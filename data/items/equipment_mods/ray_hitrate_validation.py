import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
"""
射线插件命中率建模校验 -- Monte Carlo 仿真
Ray Plugin Hit Rate Assumption Validation

校验目标: 射线插件数值建模_2026-02.md 中的瞄准难度系数假设
  pierce(穿透) = 0.95
  fork(分裂)   = 0.85
  chain(连锁)  = 0.75

方法:
  1. 基于 EnemyBehavior.as / CombatModule.as 建立敌人空间分布模型
  2. 精确复现 BulletQueueProcessor.as 的命中检测算法
  3. Monte Carlo 统计各模式实际命中率, 与报告假设对比

数据来源:
  - BulletQueueProcessor.as: 射线碰撞检测逻辑
  - bullets_cases.xml: chainRadius / rayLength / pierceLimit / falloff
  - EnemyBehavior.as: 敌人状态机 (Following/Chasing/Wandering/Evading)
  - CombatModule.as: 战斗追击逻辑 (zrange=10, xrange=武器依赖)
  - scene_environment.xml: 场景边界 (Ymin~250, Ymax~540)
"""

import numpy as np
from collections import defaultdict

# ══════════════════════════════════════════════════════════
# 游戏参数 (来源于代码和数据文件)
# ══════════════════════════════════════════════════════════

# 场景 Z 轴范围 (scene_environment.xml, 取中等地图的典型值)
STAGE_ZMIN, STAGE_ZMAX = 250, 540   # Z轴 = 深度轴 (代码中 Ymin/Ymax)
Z_RANGE_TOTAL = STAGE_ZMAX - STAGE_ZMIN  # 290px

# 子弹 Z 轴容差 (BulletQueueProcessor.as line 615)
BULLET_Z_RANGE = 50  # |bulletZ - targetZ| < 50 才算命中

# 射线参数 (bullets_cases.xml)
RAY_CONFIGS = {
    '热能': dict(rayLength=1200, pierceLimit=6,  chainRadius=None, falloff=1.00, modes=['pierce']),
    '磁暴': dict(rayLength=900,  pierceLimit=10, chainRadius=200,  falloff=0.80, modes=['chain']),
    '光棱': dict(rayLength=900,  pierceLimit=8,  chainRadius=300,  falloff=0.65, modes=['fork']),
    '光谱': dict(rayLength=900,  pierceLimit=5,  chainRadius=250,  falloff=0.60, modes=['chain','fork']),
    '辉光': dict(rayLength=1100, pierceLimit=5,  chainRadius=350,  falloff=0.60, modes=['fork']),
    '涡旋': dict(rayLength=1000, pierceLimit=6,  chainRadius=250,  falloff=0.70, modes=['fork','pierce']),
    '谐振波': dict(rayLength=900,  pierceLimit=6,  chainRadius=200,  falloff=0.70, modes=['chain','pierce']),
    '等离子': dict(rayLength=1000, pierceLimit=4,  chainRadius=200,  falloff=0.85, modes=['chain','fork','pierce']),
    '波能': dict(rayLength=1000, pierceLimit=6,  chainRadius=None, falloff=0.95, modes=['pierce']),
}

# 报告假设的命中率
REPORT_AIM = {'pierce': 0.95, 'fork': 0.85, 'chain': 0.75}

# ══════════════════════════════════════════════════════════
# 敌人空间分布模型 (基于 AI 行为分析)
# ══════════════════════════════════════════════════════════
#
# EnemyBehavior.as:
#   - Chasing: 向目标移动, Z轴尝试对齐到 zrange=10 以内
#   - Idle: 原地停留 (IDLE_BASIC_TIME=5 ticks)
#   - Wandering: 随机位置 randomIntegerStrict(Xmin,Xmax), randomIntegerStrict(Ymin,Ymax)
#   - Following: X距离 100-300, Y距离 50
#   - Evading: 远离 250-400
#
# CombatModule.as:
#   - chase(): diff_z < zrange → 停止追击 Z 轴
#   - chase(): 偶数帧调整方向, 奇数帧判断是否跑步
#   - wander_enter(): 完全随机目标位置
#
# 结论: 大部分敌人 Z 轴集中在目标 ±30 以内, 少量散布

def gen_combat_tight(rng, n, player_z):
    """紧密战斗群: 大部分敌人在追击状态, Z轴对齐良好"""
    xs = rng.uniform(80, 500, n)  # 相对于 player_x
    zs = player_z + rng.normal(0, 20, n)
    return np.column_stack([xs, np.clip(zs, STAGE_ZMIN, STAGE_ZMAX)])

def gen_combat_medium(rng, n, player_z):
    """中等战斗群: 混合追击/空闲, Z轴有一定散布"""
    xs = rng.uniform(60, 600, n)
    zs = player_z + rng.normal(0, 45, n)
    return np.column_stack([xs, np.clip(zs, STAGE_ZMIN, STAGE_ZMAX)])

def gen_combat_wide(rng, n, player_z):
    """宽松战斗群: 部分游荡, Z轴散布较大"""
    n_chase = max(1, int(n * 0.6))
    n_wander = n - n_chase
    xs_c = rng.uniform(80, 500, n_chase)
    zs_c = player_z + rng.normal(0, 35, n_chase)
    xs_w = rng.uniform(50, 800, n_wander) if n_wander > 0 else np.array([])
    zs_w = rng.uniform(STAGE_ZMIN, STAGE_ZMAX, n_wander) if n_wander > 0 else np.array([])
    xs = np.concatenate([xs_c, xs_w])
    zs = np.concatenate([zs_c, zs_w])
    return np.column_stack([xs, np.clip(zs, STAGE_ZMIN, STAGE_ZMAX)])

def gen_spread(rng, n, player_z):
    """分散分布: 大部分敌人在游荡/接近状态"""
    xs = rng.uniform(50, 900, n)
    zs = rng.uniform(STAGE_ZMIN, STAGE_ZMAX, n)
    return np.column_stack([xs, zs])

# 各分布的实战权重 (基于 AI 状态占比估算)
DISTRIBUTIONS = [
    ('紧密集群', gen_combat_tight,  0.30),
    ('中等散布', gen_combat_medium, 0.40),
    ('宽松混合', gen_combat_wide,   0.20),
    ('全散分布', gen_spread,        0.10),
]

# ══════════════════════════════════════════════════════════
# 命中检测算法 (精确复现 BulletQueueProcessor.as)
# ══════════════════════════════════════════════════════════

def find_nearest_in_ray(enemies, player_z, ray_length):
    """找到射线路径上最近的敌人 (single/chain/fork 的首次命中)"""
    best_x, best_idx = float('inf'), None
    for i in range(len(enemies)):
        ex, ez = enemies[i]
        if 0 < ex <= ray_length and abs(player_z - ez) < BULLET_Z_RANGE:
            if ex < best_x:
                best_x, best_idx = ex, i
    return best_idx

def detect_pierce(enemies, player_z, ray_length, pierce_limit):
    """
    穿透模式 (BulletQueueProcessor.as lines 1173-1293)
    扫描射线路径上所有目标, 按距离排序取前 pierceLimit 个
    """
    candidates = []
    for i in range(len(enemies)):
        ex, ez = enemies[i]
        if 0 < ex <= ray_length and abs(player_z - ez) < BULLET_Z_RANGE:
            candidates.append((ex, i))
    candidates.sort()
    return [idx for _, idx in candidates[:pierce_limit]]

def detect_chain(enemies, first_idx, chain_radius, max_bounces, player_z=None, visited=None):
    """
    连锁模式 (BulletQueueProcessor.as lines 1385-1468)
    从首命中点开始, 逐次弹跳到最近的未访问目标
    """
    if first_idx is None:
        return []
    hits = [first_idx]
    vis = visited if visited is not None else set()
    vis.add(first_idx)
    cx, cz = enemies[first_idx]
    cr_sq = chain_radius * chain_radius

    for _ in range(max_bounces):
        best_sq, best_i = cr_sq, None
        for i in range(len(enemies)):
            if i in vis: continue
            ex, ez = enemies[i]
            if abs(cz - ez) >= BULLET_Z_RANGE: continue
            dx, dz = ex - cx, ez - cz
            dsq = dx*dx + dz*dz
            if dsq < best_sq:
                best_sq, best_i = dsq, i
        if best_i is None: break
        vis.add(best_i)
        hits.append(best_i)
        cx, cz = enemies[best_i]
    return hits

def detect_fork(enemies, first_idx, chain_radius, max_forks, player_z=None, visited=None):
    """
    分裂模式 (BulletQueueProcessor.as lines 1479-1568)
    从首命中点搜索最近的 max_forks 个未访问目标
    """
    if first_idx is None:
        return []
    hits = [first_idx]
    vis = visited if visited is not None else set()
    vis.add(first_idx)
    hx, hz = enemies[first_idx]
    cr_sq = chain_radius * chain_radius

    cands = []
    for i in range(len(enemies)):
        if i in vis: continue
        ex, ez = enemies[i]
        if abs(hz - ez) >= BULLET_Z_RANGE: continue
        dx, dz = ex - hx, ez - hz
        dsq = dx*dx + dz*dz
        if dsq < cr_sq:
            cands.append((dsq, i))
    cands.sort()
    for _, idx in cands[:max_forks]:
        vis.add(idx)
        hits.append(idx)
    return hits

def detect_combo_per_node(enemies, player_z, cfg):
    """
    Per-node 管道: pierce + chain/fork (BulletQueueProcessor.as lines 669-896)
    沿穿透路径逐节点触发 chain/fork
    """
    modes = cfg['modes']
    want_chain = 'chain' in modes
    want_fork = 'fork' in modes
    budget = cfg['pierceLimit']
    cr = cfg['chainRadius']
    cr_sq = cr * cr
    vis = set()
    all_hits = []

    # Phase 0: 收集所有穿透候选 (按距离排序)
    pierce_cands = []
    for i in range(len(enemies)):
        ex, ez = enemies[i]
        if 0 < ex <= cfg['rayLength'] and abs(player_z - ez) < BULLET_Z_RANGE:
            pierce_cands.append((ex, i))
    pierce_cands.sort()

    # 逐节点处理
    for _, node_idx in pierce_cands:
        if node_idx in vis or budget <= 0: continue
        vis.add(node_idx)
        budget -= 1
        all_hits.append(node_idx)
        nx, nz = enemies[node_idx]

        # chain 子阶段
        if want_chain and budget > 0:
            cx, cz_cur = nx, nz
            while budget > 0:
                best_sq, best_i = cr_sq, None
                for i in range(len(enemies)):
                    if i in vis: continue
                    ex, ez = enemies[i]
                    if abs(cz_cur - ez) >= BULLET_Z_RANGE: continue
                    dx, dz = ex - cx, ez - cz_cur
                    dsq = dx*dx + dz*dz
                    if dsq < best_sq:
                        best_sq, best_i = dsq, i
                if best_i is None: break
                vis.add(best_i)
                budget -= 1
                all_hits.append(best_i)
                cx, cz_cur = enemies[best_i]

        # fork 子阶段
        if want_fork and budget > 0:
            fcands = []
            for i in range(len(enemies)):
                if i in vis: continue
                ex, ez = enemies[i]
                if abs(nz - ez) >= BULLET_Z_RANGE: continue
                dx, dz = ex - nx, ez - nz
                dsq = dx*dx + dz*dz
                if dsq < cr_sq:
                    fcands.append((dsq, i))
            fcands.sort()
            for _, idx in fcands:
                if budget <= 0: break
                if idx in vis: continue
                vis.add(idx)
                budget -= 1
                all_hits.append(idx)
    return all_hits

def detect_combo_per_phase(enemies, player_z, cfg):
    """
    Per-phase 管道: chain + fork 无 pierce (BulletQueueProcessor.as lines 947-1150)
    从 hit₁ 触发 chain → fork
    """
    budget = cfg['pierceLimit']
    cr = cfg['chainRadius']
    vis = set()
    all_hits = []

    first = find_nearest_in_ray(enemies, player_z, cfg['rayLength'])
    if first is None:
        return []
    vis.add(first)
    budget -= 1
    all_hits.append(first)
    hx, hz = enemies[first]

    # chain 阶段
    if 'chain' in cfg['modes'] and budget > 0:
        cr_sq = cr * cr
        cx, cz_cur = hx, hz
        while budget > 0:
            best_sq, best_i = cr_sq, None
            for i in range(len(enemies)):
                if i in vis: continue
                ex, ez = enemies[i]
                if abs(cz_cur - ez) >= BULLET_Z_RANGE: continue
                dx, dz = ex - cx, ez - cz_cur
                dsq = dx*dx + dz*dz
                if dsq < best_sq:
                    best_sq, best_i = dsq, i
            if best_i is None: break
            vis.add(best_i)
            budget -= 1
            all_hits.append(best_i)
            cx, cz_cur = enemies[best_i]

    # fork 阶段 (从原始命中点)
    if 'fork' in cfg['modes'] and budget > 0:
        cr_sq = cr * cr
        fcands = []
        for i in range(len(enemies)):
            if i in vis: continue
            ex, ez = enemies[i]
            if abs(hz - ez) >= BULLET_Z_RANGE: continue
            dx, dz = ex - hx, ez - hz
            dsq = dx*dx + dz*dz
            if dsq < cr_sq:
                fcands.append((dsq, i))
        fcands.sort()
        for _, idx in fcands:
            if budget <= 0: break
            if idx in vis: continue
            vis.add(idx)
            budget -= 1
            all_hits.append(idx)
    return all_hits

def simulate_ray(enemies, player_z, cfg):
    """统一调度: 根据模式选择检测算法"""
    modes = cfg['modes']
    has_pierce = 'pierce' in modes
    if len(modes) == 1:
        mode = modes[0]
        if mode == 'pierce':
            return detect_pierce(enemies, player_z, cfg['rayLength'], cfg['pierceLimit'])
        first = find_nearest_in_ray(enemies, player_z, cfg['rayLength'])
        if first is None: return []
        if mode == 'chain':
            return detect_chain(enemies, first, cfg['chainRadius'], cfg['pierceLimit']-1)
        if mode == 'fork':
            return detect_fork(enemies, first, cfg['chainRadius'], cfg['pierceLimit']-1)
    elif has_pierce:
        return detect_combo_per_node(enemies, player_z, cfg)
    else:
        return detect_combo_per_phase(enemies, player_z, cfg)
    return []

# ══════════════════════════════════════════════════════════
# Monte Carlo 仿真
# ══════════════════════════════════════════════════════════

N_TRIALS = 50000
N_ENEMY_RANGE = range(2, 11)  # 2~10 个敌人
PLAYER_Z = 400  # 玩家 Z 轴位置 (场景中部偏上)

def run_pure_mode_analysis():
    """
    纯模式命中率分析: 对 pierce/chain/fork 分别计算
    逐目标条件命中概率 P(H≥k+1 | H≥k)
    """
    rng = np.random.default_rng(42)

    # 纯模式代表射线
    pure_modes = {
        'pierce': ['热能', '波能'],
        'chain':  ['磁暴'],
        'fork':   ['光棱', '辉光'],
    }

    results = {}
    for mode_type, ray_names in pure_modes.items():
        results[mode_type] = {}
        for ray_name in ray_names:
            cfg = RAY_CONFIGS[ray_name]
            max_hits = cfg['pierceLimit']

            # hit_count_matrix[dist_name][n_enemies] = list of hit counts
            raw_hits = defaultdict(lambda: defaultdict(list))

            for dist_name, dist_func, dist_weight in DISTRIBUTIONS:
                for n_enemies in N_ENEMY_RANGE:
                    for _ in range(N_TRIALS):
                        enemies = dist_func(rng, n_enemies, PLAYER_Z)
                        hits = simulate_ray(enemies, PLAYER_Z, cfg)
                        raw_hits[dist_name][n_enemies].append(len(hits))

            results[mode_type][ray_name] = raw_hits
    return results

def run_combo_mode_analysis():
    """组合模式命中分析"""
    rng = np.random.default_rng(42)
    combo_rays = ['光谱', '涡旋', '谐振波', '等离子']
    results = {}

    for ray_name in combo_rays:
        cfg = RAY_CONFIGS[ray_name]
        raw_hits = defaultdict(lambda: defaultdict(list))

        for dist_name, dist_func, dist_weight in DISTRIBUTIONS:
            for n_enemies in N_ENEMY_RANGE:
                for _ in range(N_TRIALS):
                    enemies = dist_func(rng, n_enemies, PLAYER_Z)
                    hits = simulate_ray(enemies, PLAYER_Z, cfg)
                    raw_hits[dist_name][n_enemies].append(len(hits))

        results[ray_name] = raw_hits
    return results

# ══════════════════════════════════════════════════════════
# 分析与输出
# ══════════════════════════════════════════════════════════

def compute_weighted_stats(raw_hits, n_enemies):
    """计算加权平均命中数和逐级条件命中率"""
    weighted_counts = []
    for dist_name, _, dist_weight in DISTRIBUTIONS:
        counts = raw_hits[dist_name][n_enemies]
        weighted_counts.extend([(c, dist_weight / len(counts)) for c in counts])

    # E[hits]
    total_weight = sum(w for _, w in weighted_counts)
    e_hits = sum(c * w for c, w in weighted_counts) / total_weight

    # P(H ≥ k) for k = 1, 2, ...
    max_k = max(c for c, _ in weighted_counts)
    p_ge = {}
    for k in range(1, max_k + 1):
        p_ge[k] = sum(w for c, w in weighted_counts if c >= k) / total_weight

    # 条件命中率 P(H≥k+1 | H≥k) = P(H≥k+1) / P(H≥k)
    cond_rates = {}
    for k in range(1, max_k):
        if p_ge.get(k, 0) > 0.001:
            cond_rates[k] = p_ge.get(k+1, 0) / p_ge[k]
        else:
            cond_rates[k] = 0.0

    return e_hits, p_ge, cond_rates

def compute_per_dist_stats(raw_hits, n_enemies):
    """计算每个分布下的平均命中数"""
    stats = {}
    for dist_name, _, _ in DISTRIBUTIONS:
        counts = raw_hits[dist_name][n_enemies]
        stats[dist_name] = np.mean(counts)
    return stats

def theoretical_segments(n_targets, aim, falloff, max_hits):
    """报告理论模型: segments = 1 + sum(aim * falloff^i for i=1..min(n,max)-1)"""
    actual_n = min(n_targets, max_hits)
    s = 1.0
    for i in range(1, actual_n):
        s += aim * (falloff ** i)
    return s

def empirical_segments(raw_hits, n_enemies, falloff, mode_type):
    """
    经验 segments: E[总伤害倍率之和]

    注意：此处按 BulletQueueProcessor.as 的实际伤害衰减规则计算：
    - pierce/chain: sum(falloff^i) (i=0..H-1)
    - fork: 1 + (H-1)*falloff （fork 不做累积衰减）
    """
    total_seg = 0.0
    total_w = 0.0
    for dist_name, _, dist_weight in DISTRIBUTIONS:
        counts = raw_hits[dist_name][n_enemies]
        for c in counts:
            if c <= 0:
                seg = 0.0
            elif mode_type == 'fork':
                seg = 1.0 + (c - 1) * falloff
            else:
                seg = sum(falloff**i for i in range(c))
            total_seg += seg * dist_weight
            total_w += dist_weight
    return total_seg / total_w if total_w > 0 else 0

def main():
    print("=" * 80)
    print("射线插件命中率建模校验 — Monte Carlo 仿真")
    print(f"试验次数: {N_TRIALS} | 敌人数: {list(N_ENEMY_RANGE)} | 分布模型: {len(DISTRIBUTIONS)} 种")
    print("=" * 80)

    # ── 1. 纯模式分析 ──
    print("\n正在运行纯模式仿真 (pierce/chain/fork)...")
    pure_results = run_pure_mode_analysis()

    for mode_type in ['pierce', 'chain', 'fork']:
        assumed_aim = REPORT_AIM[mode_type]
        print(f"\n{'─'*70}")
        print(f"模式: {mode_type} | 报告假设命中率: {assumed_aim}")
        print(f"{'─'*70}")

        for ray_name, raw_hits in pure_results[mode_type].items():
            cfg = RAY_CONFIGS[ray_name]
            print(f"\n  > {ray_name} (chainRadius={cfg['chainRadius']}, "
                  f"pierceLimit={cfg['pierceLimit']}, rayLength={cfg['rayLength']})")

            # 表头
            print(f"  {'N敌人':>6} | {'E[命中]':>8} | {'E[seg]经验':>10} | {'E[seg]理论':>10} | "
                  f"{'误差%':>6} | {'逐级条件命中率 P(H≥k+1|H≥k) k=1,2,3,4,5...'}")
            print(f"  {'':->6}-+-{'':->8}-+-{'':->10}-+-{'':->10}-+-{'':->6}-+-{'':->45}")

            for n in N_ENEMY_RANGE:
                e_hits, p_ge, cond = compute_weighted_stats(raw_hits, n)
                e_seg = empirical_segments(raw_hits, n, cfg['falloff'], mode_type)
                t_seg = theoretical_segments(n, assumed_aim, cfg['falloff'], cfg['pierceLimit'])
                err = (e_seg - t_seg) / t_seg * 100 if t_seg > 0 else 0

                # 条件命中率字符串
                cond_str = ", ".join(f"{cond.get(k, 0):.3f}" for k in range(1, min(7, n)))

                print(f"  {n:>6} | {e_hits:>8.3f} | {e_seg:>10.4f} | {t_seg:>10.4f} | "
                      f"{err:>+5.1f}% | {cond_str}")

            # 汇总: 各分布下的命中率差异
            print(f"\n  各分布下 E[命中] (N=6):")
            dist_stats = compute_per_dist_stats(raw_hits, 6)
            for dn, avg in dist_stats.items():
                print(f"    {dn}: {avg:.3f}")

    # ── 2. 加权平均命中率提取 ──
    print(f"\n{'='*80}")
    print("综合命中率提取 (加权平均, 所有敌人数综合)")
    print(f"{'='*80}")

    for mode_type in ['pierce', 'chain', 'fork']:
        all_cond_rates = defaultdict(list)
        for ray_name, raw_hits in pure_results[mode_type].items():
            for n in range(3, 9):  # 3~8 敌人 (有足够的统计意义)
                _, _, cond = compute_weighted_stats(raw_hits, n)
                for k in range(1, min(6, n)):
                    all_cond_rates[k].append(cond.get(k, 0))

        avg_rates = {k: np.mean(v) for k, v in all_cond_rates.items()}
        overall = np.mean(list(avg_rates.values())) if avg_rates else 0

        print(f"\n  {mode_type}:")
        print(f"    逐级平均: " + ", ".join(f"k={k}: {v:.4f}" for k, v in sorted(avg_rates.items())))
        print(f"    总体平均: {overall:.4f}")
        print(f"    报告假设: {REPORT_AIM[mode_type]}")
        print(f"    差异: {(overall - REPORT_AIM[mode_type]):.4f} "
              f"({(overall - REPORT_AIM[mode_type]) / REPORT_AIM[mode_type] * 100:+.1f}%)")

    # ── 3. 组合模式验证 ──
    print(f"\n{'='*80}")
    print("组合模式验证")
    print(f"{'='*80}")
    print("\n正在运行组合模式仿真...")
    combo_results = run_combo_mode_analysis()

    for ray_name, raw_hits in combo_results.items():
        cfg = RAY_CONFIGS[ray_name]
        modes_str = "+".join(cfg['modes'])
        print(f"\n  > {ray_name} ({modes_str}, chainRadius={cfg['chainRadius']}, "
              f"pierceLimit={cfg['pierceLimit']})")
        print(f"  {'N敌人':>6} | {'E[命中]':>8} | {'各分布命中数'}")
        print(f"  {'':->6}-+-{'':->8}-+-{'':->50}")

        for n in N_ENEMY_RANGE:
            e_hits, _, _ = compute_weighted_stats(raw_hits, n)
            dist_stats = compute_per_dist_stats(raw_hits, n)
            ds = " | ".join(f"{dn}:{avg:.2f}" for dn, avg in dist_stats.items())
            print(f"  {n:>6} | {e_hits:>8.3f} | {ds}")

    # ── 4. 敏感度分析: Z轴散布 vs 命中率 ──
    print(f"\n{'='*80}")
    print("敏感度分析: Z轴散布 σ_z 对命中率的影响 (N=6 敌人)")
    print(f"{'='*80}")

    rng = np.random.default_rng(123)
    sigma_z_values = [10, 20, 30, 40, 50, 60, 80, 100]

    # 用波能(pierce)、磁暴(chain)、光棱(fork) 作为代表
    test_rays = {'波能(pierce)': '波能', '磁暴(chain)': '磁暴', '光棱(fork)': '光棱'}
    n_test = 6
    n_sensitivity_trials = 30000

    print(f"\n  {'σ_z':>5}", end="")
    for label in test_rays:
        print(f" | {label:>15}", end="")
    print()
    print(f"  {'':->5}", end="")
    for _ in test_rays:
        print(f"-+-{'':->15}", end="")
    print()

    for sigma_z in sigma_z_values:
        print(f"  {sigma_z:>5}", end="")
        for label, ray_name in test_rays.items():
            cfg = RAY_CONFIGS[ray_name]
            hit_counts = []
            for _ in range(n_sensitivity_trials):
                xs = rng.uniform(80, 500, n_test)
                zs = PLAYER_Z + rng.normal(0, sigma_z, n_test)
                zs = np.clip(zs, STAGE_ZMIN, STAGE_ZMAX)
                enemies = np.column_stack([xs, zs])
                hits = simulate_ray(enemies, PLAYER_Z, cfg)
                hit_counts.append(len(hits))
            avg = np.mean(hit_counts)
            # 推导等效 aim rate
            if avg > 1:
                # E[H] = 1 + aim*(N-1) → aim = (E[H]-1)/(N-1)
                implied_aim = (avg - 1) / (n_test - 1)
                print(f" | E[H]={avg:.2f} aim≈{implied_aim:.3f}", end="")
            else:
                print(f" | E[H]={avg:.2f} aim≈  N/A", end="")
        print()

    # ── 5. 最终结论 ──
    print(f"\n{'='*80}")
    print("最终结论")
    print(f"{'='*80}")
    print("""
    本仿真基于以下实际游戏数据:
    - BulletQueueProcessor.as 的精确碰撞检测算法
    - EnemyBehavior.as / CombatModule.as 的敌人空间分布行为
    - bullets_cases.xml 的实际射线参数 (chainRadius, rayLength, pierceLimit)
    - 场景 Z 轴范围 [250, 540], 子弹 Z 容差 ±50

    通过 Monte Carlo 仿真验证报告假设的命中率:
    - pierce = 0.95: 穿透最易, 只需敌人在射线路径的 Z 带内
    - fork   = 0.85: 分裂中等, 需敌人在搜索半径内且 Z 对齐
    - chain  = 0.75: 连锁最难, 逐跳搜索可能远离敌人集群

    上方数据展示了各假设的仿真校验结果。
    """)

if __name__ == "__main__":
    main()
