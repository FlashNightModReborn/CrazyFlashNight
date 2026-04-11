"""
MovementResolver — 精确复刻 AS2 MovementResolver.applyBoundaryAwareMovement。

逐行对照 combat/MovementResolver.as，保持相同的判断顺序和分支结构。
所有可调参数从 CombatAgent.config (MovementConfig) 读取，
供参数扫描框架外部覆盖。

返回值约定（与 AS2 一致）：
  0 = 正常移动
  1 = X轴沿墙滑行（Z已注入）
  2 = 角落突围（X反转）
"""
from __future__ import annotations

import math
from combat_agent import CombatAgent, MovementConfig
from shared import CollisionWorld


# ═══════ 辅助：方向可达性探测 ═══════

def is_direction_walkable(coll: CollisionWorld,
                          x: float, z: float,
                          want_x: int, want_z: int,
                          probe: float) -> bool:
    """
    对应 Mover.isDirectionWalkable(self, wantX, wantZ, probe)。
    探测 (x + wantX*probe, z + wantZ*probe) 是否可通行。
    """
    nx = x + want_x * probe
    nz = z + want_z * probe
    return coll.is_point_valid(nx, nz)


def push_out_from_collision(coll: CollisionWorld,
                            agent: CombatAgent,
                            radius: float = 120,
                            steps: int = 10,
                            n_angles: int = 45) -> None:
    """
    对应 Mover.pushOutFromCollision：同心圆搜索最近可通行点。
    """
    angle_step = 2 * math.pi / n_angles
    r_step = radius / steps

    for step_i in range(1, steps + 1):
        r = r_step * step_i
        for a_i in range(n_angles):
            angle = a_i * angle_step
            nx = agent.x + r * math.cos(angle)
            nz = agent.z + r * math.sin(angle)
            if coll.is_point_valid(nx, nz):
                agent.x = nx
                agent.z = nz
                return


# ═══════ pickZDirBySpaceEx ═══════

def pick_z_dir_by_space(agent: CombatAgent, margin: float = 80) -> int:
    """
    对应 MovementResolver.pickZDirBySpaceEx。

    返回值：
      0  = 上下都无空间
      1  = 偏好向下
     -1  = 偏好向上
      2  = 强制向下（贴边）
     -2  = 强制向上（贴边）
    """
    up = agent.bnd_up
    down = agent.bnd_down

    if up < margin and down < margin:
        return 0
    if up < margin:
        return 2
    if down < margin:
        return -2

    # 弹道威胁省略（离线仿真无弹道数据），直接按空间选择
    return -1 if up >= down else 1


# ═══════ 核心：applyBoundaryAwareMovement ═══════

def apply_boundary_aware_movement(
    agent: CombatAgent,
    coll: CollisionWorld,
    want_x: int,
    want_z: int,
    frame: int,
) -> int:
    """
    精确复刻 MovementResolver.applyBoundaryAwareMovement。

    参数：
        agent:  CombatAgent（需已 update_boundaries）
        coll:   CollisionWorld
        want_x: X轴意图 -1/0/1
        want_z: Z轴意图 -1/0/1
        frame:  当前帧号

    返回：
        0=正常, 1=沿墙滑行, 2=角落突围
    """
    cfg = agent.config
    MARGIN = cfg.margin
    x_blocked = False

    # ── Phase 0: 障碍物/边界脱困 ──
    trying = (want_x != 0 or want_z != 0)

    if trying:
        # 脱困窗口内：复用上次方向
        if frame < agent.unstuck_until_frame:
            want_x = agent.unstuck_x
            want_z = agent.unstuck_z
        else:
            # 探测距离
            spd = agent.speed
            if spd <= 0:
                spd = 6
            probe = spd * cfg.probe_speed_mult
            if probe < cfg.probe_min:
                probe = cfg.probe_min
            elif probe > cfg.probe_max:
                probe = cfg.probe_max

            # blockedAhead：先用 bnd 快速排除
            blocked_ahead = False
            bnd_maybe = False
            if want_x < 0 and agent.bnd_left < probe + MARGIN:
                bnd_maybe = True
            elif want_x > 0 and agent.bnd_right < probe + MARGIN:
                bnd_maybe = True
            if want_z < 0 and agent.bnd_up < probe + MARGIN:
                bnd_maybe = True
            elif want_z > 0 and agent.bnd_down < probe + MARGIN:
                bnd_maybe = True
            if bnd_maybe:
                blocked_ahead = not is_direction_walkable(
                    coll, agent.x, agent.z, want_x, want_z, probe)

            # noProgress：分轴检测
            # 合成投影（原逻辑）：dpX*wantX + dpZ*wantZ < 1.0
            # 分轴检测（新增）：want_x≠0 时单独检查 X 方向进展
            # 解决的问题：Z 有自由度时合成投影不触发，但 X 永远被 Phase 1 拦截
            no_progress = False
            if agent.last_progress_x is not None:
                dp_x = agent.x - agent.last_progress_x
                dp_z = agent.z - agent.last_progress_z
                prog = dp_x * want_x + dp_z * want_z
                if prog < 1.0:
                    agent.no_progress_count += 1
                else:
                    agent.no_progress_count = 0
                no_progress = (agent.no_progress_count >= cfg.no_progress_threshold)

                # [分轴检测] X 方向单独计数
                if want_x != 0:
                    x_prog = dp_x * want_x
                    if x_prog < 0.5:
                        agent._x_no_progress = getattr(agent, '_x_no_progress', 0) + 1
                    else:
                        agent._x_no_progress = 0
                    # X 轴持续无进展也触发脱困
                    if agent._x_no_progress >= cfg.no_progress_threshold + 1:
                        no_progress = True
                else:
                    agent._x_no_progress = 0
            agent.last_progress_x = agent.x
            agent.last_progress_z = agent.z

            # stuck：位置历史
            stuck = agent.stuck_probe(True, 6, 3, 4)

            if blocked_ahead or no_progress or stuck:
                old_wx = want_x
                old_wz = want_z

                # preferZ：朝目标对齐 or 空间更大侧
                prefer_z = 0
                if agent.target_z is not None:
                    prefer_z = 1 if agent.target_z > agent.z else -1
                else:
                    zp = pick_z_dir_by_space(agent, MARGIN)
                    if zp < 0:
                        prefer_z = -1
                    elif zp > 0:
                        prefer_z = 1
                    else:
                        prefer_z = -1 if agent.bnd_up > agent.bnd_down else 1
                alt_z = -prefer_z

                best_x = 0
                best_z = 0

                # 方向搜索函数（避免重复代码）
                def _search_escape(p):
                    bx, bz = 0, 0
                    # edgeEscape
                    eex = 0
                    if agent.bnd_left < MARGIN:
                        eex = 1
                    elif agent.bnd_right < MARGIN:
                        eex = -1
                    if eex != 0:
                        if old_wz != 0 and is_direction_walkable(coll, agent.x, agent.z, eex, old_wz, p):
                            return eex, old_wz
                        if is_direction_walkable(coll, agent.x, agent.z, eex, prefer_z, p):
                            return eex, prefer_z
                        if is_direction_walkable(coll, agent.x, agent.z, eex, alt_z, p):
                            return eex, alt_z
                        if is_direction_walkable(coll, agent.x, agent.z, eex, 0, p):
                            return eex, 0
                    # 1) 原意图
                    if (old_wx != 0 or old_wz != 0) and is_direction_walkable(coll, agent.x, agent.z, old_wx, old_wz, p):
                        return old_wx, old_wz
                    # 2) X + preferZ/altZ 对角
                    if old_wx != 0:
                        if is_direction_walkable(coll, agent.x, agent.z, old_wx, prefer_z, p):
                            return old_wx, prefer_z
                        if is_direction_walkable(coll, agent.x, agent.z, old_wx, alt_z, p):
                            return old_wx, alt_z
                    # 3) 纯Z
                    if is_direction_walkable(coll, agent.x, agent.z, 0, prefer_z, p):
                        return 0, prefer_z
                    if is_direction_walkable(coll, agent.x, agent.z, 0, alt_z, p):
                        return 0, alt_z
                    # 4) 退一步
                    if old_wx != 0 and is_direction_walkable(coll, agent.x, agent.z, -old_wx, 0, p):
                        return -old_wx, 0
                    if old_wz != 0 and is_direction_walkable(coll, agent.x, agent.z, 0, -old_wz, p):
                        return 0, -old_wz
                    return 0, 0

                # 常规 probe 搜索
                best_x, best_z = _search_escape(probe)

                # [新增] 如果常规搜索只找到纯Z/退后（X方向无进展），
                # 用更大 probe 重试——看到更远处的绕行空间
                if old_wx != 0 and best_x == 0:
                    far_probe = max(probe * 2, cfg.probe_max)
                    bx2, bz2 = _search_escape(far_probe)
                    if bx2 != 0:
                        best_x, best_z = bx2, bz2

                if best_x != 0 or best_z != 0:
                    want_x = best_x
                    want_z = best_z
                    agent.unstuck_x = best_x
                    agent.unstuck_z = best_z
                    # 脱困窗口递增
                    scc = agent.get_stuck_check_count()
                    base_win = cfg.unstuck_base_window
                    if scc > cfg.unstuck_high_thresh:
                        base_win = cfg.unstuck_high_window
                    elif scc > cfg.unstuck_mid_thresh:
                        base_win = cfg.unstuck_mid_window
                    agent.unstuck_until_frame = frame + base_win
                    agent.no_progress_count = 0
                    agent.probe_fail_count = 0
                else:
                    # 全败 → pushOut 兜底
                    agent.probe_fail_count += 1
                    if agent.probe_fail_count >= cfg.probe_fail_trigger:
                        push_out_from_collision(
                            coll, agent,
                            cfg.pushout_radius, cfg.pushout_steps, cfg.pushout_angles)
                        agent.probe_fail_count = 0
                        agent.stuck_frames += 4
    else:
        # 无移动意图：清空脱困状态
        agent.unstuck_until_frame = 0
        agent.no_progress_count = 0
        agent.last_progress_x = None
        agent.last_progress_z = None

    # ── Phase 1: X轴可行性检查 ──
    if want_x < 0 and agent.bnd_left < MARGIN:
        x_blocked = True
    elif want_x > 0 and agent.bnd_right < MARGIN:
        x_blocked = True

    # ── Phase 2: X轴被阻时注入Z ──
    if x_blocked and want_x != 0 and want_z == 0:
        z_pick = pick_z_dir_by_space(agent, MARGIN)
        if z_pick < 0:
            want_z = -1
        elif z_pick > 0:
            want_z = 1

    # ── Phase 3: Z轴输出 ──
    z_blocked = False
    if want_z < 0:
        if agent.bnd_up >= MARGIN:
            agent.move_up = True
        elif agent.bnd_down >= MARGIN:
            agent.move_down = True
        else:
            z_blocked = True
    elif want_z > 0:
        if agent.bnd_down >= MARGIN:
            agent.move_down = True
        elif agent.bnd_up >= MARGIN:
            agent.move_up = True
        else:
            z_blocked = True

    # ── Phase 4: X轴输出 + 结果码 ──
    result = 0
    if not x_blocked and want_x != 0:
        if want_x < 0:
            agent.move_left = True
        else:
            agent.move_right = True
        result = 0
    elif x_blocked and not z_blocked:
        result = 1  # 沿墙滑行
        agent.slide_events += 1
    elif x_blocked and z_blocked and want_x != 0:
        # 角落突围：反转X
        if want_x < 0:
            agent.move_right = True
        else:
            agent.move_left = True
        result = 2
        agent.corner_events += 1

    return result
