import org.flashNight.arki.unit.UnitAI.core.UnitAIData;
import org.flashNight.arki.unit.UnitAI.core.AIEnvironment;
import org.flashNight.arki.spatial.move.Mover;

/**
 * MovementResolver -- 静态移动工具类
 *
 * 从 UnitAIData 提取的三个 static 移动方法，
 * 职责：边界感知移动输出、Z方向选择、输入清除。
 *
 * UnitAIData 保留实例方法（卡死检测等）。
 */
class org.flashNight.arki.unit.UnitAI.combat.MovementResolver {

    /**
     * pickZDirBySpaceEx -- 根据上下边界空间选择 Z 方向（轻量版）
     *
     * 统一多处"上下空间选择"逻辑（走位/沿墙滑行/脱困），避免各处规则漂移。
     *
     * 返回值约定：
     *   0  : 上下都无空间（不建议输出 Z）
     *   1  : 偏好向下（可交替）
     *  -1  : 偏好向上（可交替）
     *   2  : 强制向下（贴边/强弹道威胁）
     *  -2  : 强制向上（贴边/强弹道威胁）
     *
     * @param data   UnitAIData（需已 updateSelf）
     * @param self   MovieClip（用于读取 _bt* 弹道威胁）
     * @param margin 边界余量（像素），默认 80
     */
    public static function pickZDirBySpaceEx(data:UnitAIData, self:MovieClip, margin:Number):Number {
        if (margin == undefined) margin = 80;

        var upSpace:Number = data.bndUpDist;
        var downSpace:Number = data.bndDownDist;

        // 边界硬约束：一侧空间不足时强制反向
        if (upSpace < margin && downSpace < margin) return 0;
        if (upSpace < margin) return 2;
        if (downSpace < margin) return -2;

        // 弹道威胁：强偏向空间更大的一侧（保持与 EngageMovementStrategy 一致）
        var btAge:Number = AIEnvironment.getFrame() - self._btFrame;
        if (btAge >= 0 && btAge <= 1 && self._btCount > 0) {
            if (upSpace > downSpace * 1.3) return -2;
            if (downSpace > upSpace * 1.3) return 2;
        }

        // 默认偏好：空间更大的一侧
        return (upSpace >= downSpace) ? -1 : 1;
    }

    // ═══════ 统一边界感知移动 ═══════

    /**
     * applyBoundaryAwareMovement -- 统一边界感知移动输出
     *
     * 接收语义化移动意图（wantX: -1=左, 0=无, 1=右; wantZ: -1=上, 0=无, 1=下），
     * 处理边界碰撞并输出到 self 的移动标志。
     *
     * 三级逃脱策略：
     *   0=正常：方向可行，直接输出
     *   1=沿墙滑行：X轴贴墙 -> 不输出X，自动注入Z分量斜向逃脱
     *   2=角落突围：X+Z都被堵 -> 反转X方向冲出（打出去）
     *
     * 所有移动代码（retreat_action, EngageMovementStrategy 等）统一调用此方法，
     * 消除分散的 ad-hoc 边界处理。调用前需已执行 updateSelf()。
     *
     * @param data   UnitAIData（bnd* 字段需有效）
     * @param self   MovieClip
     * @param wantX  X轴意图: -1=左, 0=无, 1=右
     * @param wantZ  Z轴意图: -1=上, 0=无, 1=下
     * @param goalX  可选的长期目标X（如撤退锚点）；仅用于脱困绕行偏置
     * @param goalZ  可选的长期目标Z（如撤退锚点）；仅用于脱困绕行偏置
     * @return Number  0=正常, 1=X轴沿墙滑行, 2=角落突围
     */
    public static function applyBoundaryAwareMovement(
        data:UnitAIData, self:MovieClip,
        wantX:Number, wantZ:Number,
        goalX:Number, goalZ:Number
    ):Number {
        var MARGIN:Number = 80;
        var xBlocked:Boolean = false;

        // ── Phase 0: 障碍物/边界脱困（在被阻/卡死时触发）──
        // 说明：边界贴墙可用 bnd* 直接判断，但地图障碍需要碰撞探测。
        // 这里不引入 getWalkableDirections（8向全探测太重），仅在"方向不可走/确实卡死"时用少量 probe。
        var frameNow:Number = AIEnvironment.getFrame();
        var trying:Boolean = (wantX != 0 || wantZ != 0);
        if (trying && self.状态 != "技能" && self.状态 != "战技") {
            // 脱困窗口内：直接复用上次方向（避免重复 hitTest）
            if (frameNow < data._unstuckUntilFrame) {
                wantX = data._unstuckX;
                wantZ = data._unstuckZ;
            } else {
                // 探测距离：不要过大（会错过狭窄出口），也不要过小（容易被抖动误导）
                var spd:Number = self.行走X速度;
                if (isNaN(spd) || spd <= 0) spd = 6;
                var probe:Number = spd * 5;
                if (probe < 20) probe = 20;
                else if (probe > 60) probe = 60;

                // 三类触发：
                //  1) blockedAhead：前方探测点不可行走（边界/障碍）
                //  2) noProgress：位移在意图方向上的投影连续不足（贴障碍滑动/被推挤）
                //  3) stuck：绝对位置长期无进展（兜底）

                // blockedAhead: 先用 bnd 快速排除，只在接近边界/障碍时才做 hitTest
                var blockedAhead:Boolean = false;
                var bndMaybe:Boolean = false;
                if (wantX < 0 && data.bndLeftDist < probe + MARGIN) bndMaybe = true;
                else if (wantX > 0 && data.bndRightDist < probe + MARGIN) bndMaybe = true;
                if (wantZ < 0 && data.bndUpDist < probe + MARGIN) bndMaybe = true;
                else if (wantZ > 0 && data.bndDownDist < probe + MARGIN) bndMaybe = true;
                if (bndMaybe) {
                    blockedAhead = !Mover.isDirectionWalkable(self, wantX, wantZ, probe);
                }

                // noProgress: 合成投影 + 分轴X检测
                // 合成投影：捕获"贴障碍物侧向滑动"和"被推挤"
                // 分轴X：捕获"Z有自由度但X被边界/障碍永久阻挡"（解决边界无限弹跳）
                var noProgress:Boolean = false;
                var curPlaneZ:Number = !isNaN(data.z) ? data.z : data.y;
                if (data._lastProgressX != undefined) {
                    var dpX:Number = data.x - data._lastProgressX;
                    var dpZ:Number = curPlaneZ - data._lastProgressZ;
                    var prog:Number = dpX * wantX + dpZ * wantZ;
                    if (prog < 1.0) {
                        data._noProgressCount++;
                    } else {
                        data._noProgressCount = 0;
                    }
                    noProgress = (data._noProgressCount >= 2);
                    // 分轴X检测：wantX≠0 时单独追踪X方向进展
                    if (wantX != 0) {
                        if (dpX * wantX < 0.5) {
                            data._xNoProgressCount++;
                        } else {
                            data._xNoProgressCount = 0;
                        }
                        if (data._xNoProgressCount >= 3) noProgress = true;
                    } else {
                        data._xNoProgressCount = 0;
                    }
                }
                data._lastProgressX = data.x;
                data._lastProgressZ = curPlaneZ;

                var stuck:Boolean = data.stuckProbeByCurrentPosition(true, 6, 3, 4);

                if (blockedAhead || noProgress || stuck) {
                    var oldWX:Number = wantX;
                    var oldWZ:Number = wantZ;

                    // 优先 Z 方向：朝显式撤退目标对齐；无显式目标时沿用旧目标/空间规则
                    var preferZ:Number = 0;
                    if (goalZ != null && !isNaN(goalZ) && Math.abs(goalZ - data.z) > 8) {
                        preferZ = (goalZ > data.z) ? 1 : -1;
                    } else if (data.tz != null && !isNaN(data.tz)) {
                        preferZ = (data.tz > data.z) ? 1 : -1;
                    } else {
                        var zp:Number = MovementResolver.pickZDirBySpaceEx(data, self, MARGIN);
                        if (zp < 0) preferZ = -1;
                        else if (zp > 0) preferZ = 1;
                        else preferZ = (data.bndUpDist > data.bndDownDist) ? -1 : 1;
                    }
                    var altZ:Number = -preferZ;
                    var goalDirX:Number = 0;
                    if (goalX != null && !isNaN(goalX) && Math.abs(goalX - data.x) > 8) {
                        goalDirX = (goalX > data.x) ? 1 : -1;
                    }

                    var bestX:Number = 0;
                    var bestZ:Number = 0;

                    // 边界脱困：贴左右边时优先往屏幕中间挪（解决卡在左右边不反向的问题）
                    var edgeEscapeX:Number = 0;
                    if (data.bndLeftDist < MARGIN) edgeEscapeX = 1;
                    else if (data.bndRightDist < MARGIN) edgeEscapeX = -1;
                    if (edgeEscapeX != 0) {
                        if (oldWZ != 0 && Mover.isDirectionWalkable(self, edgeEscapeX, oldWZ, probe)) {
                            bestX = edgeEscapeX; bestZ = oldWZ;
                        } else if (Mover.isDirectionWalkable(self, edgeEscapeX, preferZ, probe)) {
                            bestX = edgeEscapeX; bestZ = preferZ;
                        } else if (Mover.isDirectionWalkable(self, edgeEscapeX, altZ, probe)) {
                            bestX = edgeEscapeX; bestZ = altZ;
                        } else if (Mover.isDirectionWalkable(self, edgeEscapeX, 0, probe)) {
                            bestX = edgeEscapeX; bestZ = 0;
                        }
                    }

                    // 1) 朝长期目标X绕行/推进（撤退锚点）
                    if (bestX == 0 && bestZ == 0
                        && goalDirX != 0 && Mover.isDirectionWalkable(self, goalDirX, preferZ, probe)) {
                        bestX = goalDirX; bestZ = preferZ;
                    } else if (bestX == 0 && bestZ == 0
                        && goalDirX != 0 && Mover.isDirectionWalkable(self, goalDirX, altZ, probe)) {
                        bestX = goalDirX; bestZ = altZ;
                    } else if (bestX == 0 && bestZ == 0
                        && goalDirX != 0 && Mover.isDirectionWalkable(self, goalDirX, 0, probe)) {
                        bestX = goalDirX; bestZ = 0;
                    }
                    // 2) 尽量保持原意图（含对角）
                    if (bestX == 0 && bestZ == 0
                        && (oldWX != 0 || oldWZ != 0) && Mover.isDirectionWalkable(self, oldWX, oldWZ, probe)) {
                        bestX = oldWX; bestZ = oldWZ;
                    }
                    // 3) X优先：对角绕障（X + preferZ / altZ）
                    else if (bestX == 0 && bestZ == 0
                        && oldWX != 0 && Mover.isDirectionWalkable(self, oldWX, preferZ, probe)) {
                        bestX = oldWX; bestZ = preferZ;
                    } else if (bestX == 0 && bestZ == 0
                        && oldWX != 0 && Mover.isDirectionWalkable(self, oldWX, altZ, probe)) {
                        bestX = oldWX; bestZ = altZ;
                    }
                    // 4) 纯Z挪位（沿墙滑行/绕柱）
                    else if (bestX == 0 && bestZ == 0
                        && Mover.isDirectionWalkable(self, 0, preferZ, probe)) {
                        bestX = 0; bestZ = preferZ;
                    } else if (bestX == 0 && bestZ == 0
                        && Mover.isDirectionWalkable(self, 0, altZ, probe)) {
                        bestX = 0; bestZ = altZ;
                    }
                    // 5) 退一步（反向X/反向Z）
                    else if (bestX == 0 && bestZ == 0
                        && oldWX != 0 && Mover.isDirectionWalkable(self, -oldWX, 0, probe)) {
                        bestX = -oldWX; bestZ = 0;
                    } else if (bestX == 0 && bestZ == 0
                        && oldWZ != 0 && Mover.isDirectionWalkable(self, 0, -oldWZ, probe)) {
                        bestX = 0; bestZ = -oldWZ;
                    }

                    // 6) 远距probe重试：常规probe只找到纯Z/退后时，
                    // 用2x probe看更远处的绕行对角方向（解决贴障碍物时短probe看不到绕行空间）
                    if ((oldWX != 0 || goalDirX != 0) && bestX == 0) {
                        var farProbe:Number = probe * 2;
                        if (farProbe < 60) farProbe = 60;
                        if (goalDirX != 0 && Mover.isDirectionWalkable(self, goalDirX, preferZ, farProbe)) {
                            bestX = goalDirX; bestZ = preferZ;
                        } else if (goalDirX != 0 && Mover.isDirectionWalkable(self, goalDirX, altZ, farProbe)) {
                            bestX = goalDirX; bestZ = altZ;
                        } else if (goalDirX != 0 && Mover.isDirectionWalkable(self, goalDirX, 0, farProbe)) {
                            bestX = goalDirX; bestZ = 0;
                        } else if (Mover.isDirectionWalkable(self, oldWX, preferZ, farProbe)) {
                            bestX = oldWX; bestZ = preferZ;
                        } else if (Mover.isDirectionWalkable(self, oldWX, altZ, farProbe)) {
                            bestX = oldWX; bestZ = altZ;
                        }
                    }

                    if (bestX != 0 || bestZ != 0) {
                        wantX = bestX;
                        wantZ = bestZ;
                        data._unstuckX = bestX;
                        data._unstuckZ = bestZ;
                        // 脱困窗口递增：持续卡死时逐步加长，足够绕过大障碍
                        var scc:Number = data.getStuckCheckCount();
                        var baseWindow:Number = 24;
                        if (scc > 12) baseWindow = 48;
                        else if (scc > 6) baseWindow = 36;
                        data._unstuckUntilFrame = frameNow + baseWindow;
                        data._noProgressCount = 0; // 成功找到脱困方向，重置进展计数
                        data._xNoProgressCount = 0;
                        data._probeFailCount = 0;

                        if (AIEnvironment.isAIDebug() || AIEnvironment.getAILogLevel() >= 2) {
                            var reason:String = blockedAhead ? "BLOCKED"
                                : (noProgress ? "NO_PROGRESS" : "STUCK");
                            AIEnvironment.log("[MOV] " + self.名字
                                + " UNSTUCK(" + reason + ")"
                                + " from=" + oldWX + "," + oldWZ
                                + " to=" + bestX + "," + bestZ
                                + " win=" + baseWindow
                                + " pos=" + Math.round(data.x) + "," + Math.round(data.y));
                        }
                    } else {
                        // 5) 所有方向探测全败（嵌入复杂碰撞体内）→ 同心圆搜索兜底
                        data._probeFailCount = (data._probeFailCount || 0) + 1;
                        if (data._probeFailCount >= 3) {
                            Mover.pushOutFromCollision(self, 120, 10, 45);
                            data._probeFailCount = 0;
                            if (AIEnvironment.isAIDebug() || AIEnvironment.getAILogLevel() >= 2) {
                                AIEnvironment.log("[MOV] " + self.名字
                                    + " PUSHOUT pos=" + Math.round(data.x) + "," + Math.round(data.y));
                            }
                        }
                    }
                }
            }
        } else if (!trying) {
            // 无移动意图：清空脱困窗口 + 进展计数，避免下一次移动继承旧状态
            data._unstuckUntilFrame = 0;
            data._noProgressCount = 0;
            data._xNoProgressCount = 0;
            data._lastProgressX = undefined;
            data._lastProgressZ = undefined;
        }

        // ── Phase 1: X轴可行性检查 ──
        if (wantX < 0 && data.bndLeftDist < MARGIN) {
            xBlocked = true;
        } else if (wantX > 0 && data.bndRightDist < MARGIN) {
            xBlocked = true;
        }

        // ── Phase 2: X轴被阻时注入Z逃脱分量 ──
        if (xBlocked && wantX != 0 && wantZ == 0) {
            if (goalZ != null && !isNaN(goalZ) && Math.abs(goalZ - data.z) > 8) {
                wantZ = (goalZ > data.z) ? 1 : -1;
            } else {
                var zPick:Number = MovementResolver.pickZDirBySpaceEx(data, self, MARGIN);
                if (zPick < 0) wantZ = -1;
                else if (zPick > 0) wantZ = 1;
            }
        }

        // ── Phase 3: Z轴输出（含自动重定向）──
        var zBlocked:Boolean = false;
        if (wantZ < 0) {
            if (data.bndUpDist >= MARGIN) {
                self.上行 = true;
            } else if (data.bndDownDist >= MARGIN) {
                self.下行 = true;
            } else {
                zBlocked = true;
            }
        } else if (wantZ > 0) {
            if (data.bndDownDist >= MARGIN) {
                self.下行 = true;
            } else if (data.bndUpDist >= MARGIN) {
                self.上行 = true;
            } else {
                zBlocked = true;
            }
        }

        // ── Phase 4: X轴输出 + 结果码 ──
        var result:Number = 0;
        if (!xBlocked && wantX != 0) {
            if (wantX < 0) self.左行 = true;
            else self.右行 = true;
            result = 0;
        } else if (xBlocked && !zBlocked) {
            result = 1; // 沿墙滑行（Z已在 Phase 3 输出）
        } else if (xBlocked && zBlocked && wantX != 0) {
            // 角落突围：反转X
            if (wantX < 0) self.右行 = true;
            else self.左行 = true;
            result = 2;
        }

        // ── 调试日志（每 32 帧输出一次，覆盖所有调用）──
        if (AIEnvironment.isAIDebug()) {
            var _f:Number = AIEnvironment.getFrame();
            if ((_f & 31) == 0 || result > 0) {
                var tag:String = (result == 0) ? "OK" : ((result == 1) ? "SLIDE" : "CORNER");
                AIEnvironment.log("[MOV] " + self.名字
                    + " " + tag
                    + " wX=" + wantX + " wZ=" + wantZ
                    + " pos=" + Math.round(data.x) + "," + Math.round(data.y)
                    + " L=" + Math.round(data.bndLeftDist)
                    + " R=" + Math.round(data.bndRightDist)
                    + " U=" + Math.round(data.bndUpDist)
                    + " D=" + Math.round(data.bndDownDist)
                    + " xB=" + xBlocked + " zB=" + zBlocked);
            }
        }

        return result;
    }

    // ═══════ 输入清除工具 ═══════

    /**
     * clearInput -- 重置所有移动/动作输入标志
     * 消除 6 行重复模式（selector_enter/follow_enter/manual_enter/chase/engage/engage_enter）
     */
    public static function clearInput(self:MovieClip):Void {
        self.左行 = false;
        self.右行 = false;
        self.上行 = false;
        self.下行 = false;
        self.动作A = false;
        self.动作B = false;
    }

}
