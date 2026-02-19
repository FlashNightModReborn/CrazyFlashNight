import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.spatial.move.Mover;

/**
 * MovementResolver -- 静态移动工具类
 *
 * 从 UnitAIData 提取的三个 static 移动方法，
 * 职责：边界感知移动输出、Z方向选择、输入清除。
 *
 * UnitAIData 保留实例方法（卡死检测等）。
 */
class org.flashNight.arki.unit.UnitAI.MovementResolver {

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
        var btAge:Number = _root.帧计时器.当前帧数 - self._btFrame;
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
     * @return Number  0=正常, 1=X轴沿墙滑行, 2=角落突围
     */
    public static function applyBoundaryAwareMovement(
        data:UnitAIData, self:MovieClip,
        wantX:Number, wantZ:Number
    ):Number {
        var MARGIN:Number = 80;
        var xBlocked:Boolean = false;

        // ── Phase 0: 障碍物脱困（仅在确实卡死时触发）──
        // 说明：边界贴墙可用 bnd* 直接判断，但地图障碍需要碰撞探测。
        // 这里不引入 getWalkableDirections（8向全探测太重），只在卡死时用少量 probe。
        var frameNow:Number = _root.帧计时器.当前帧数;
        var trying:Boolean = (wantX != 0 || wantZ != 0);
        if (trying && !self.射击中 && self.状态 != "技能" && self.状态 != "战技") {
            // 脱困窗口内：直接复用上次方向（避免重复 hitTest）
            if (frameNow < data._unstuckUntilFrame) {
                wantX = data._unstuckX;
                wantZ = data._unstuckZ;
            } else if (data.stuckProbeByCurrentPosition(true, 6, 3, 4)) {
                var oldWX:Number = wantX;
                var oldWZ:Number = wantZ;
                // 探测距离：不要过大（会错过狭窄出口），也不要过小（容易被抖动误导）
                var spd:Number = self.行走X速度;
                if (isNaN(spd) || spd <= 0) spd = 6;
                var probe:Number = spd * 4;
                if (probe < 20) probe = 20;
                else if (probe > 60) probe = 60;

                // 优先 Z 方向：朝目标对齐（无目标则朝空间更大的一侧）
                var preferZ:Number = 0;
                if (data.tz != null && !isNaN(data.tz)) {
                    preferZ = (data.tz > data.z) ? 1 : -1;
                } else {
                    var zp:Number = MovementResolver.pickZDirBySpaceEx(data, self, MARGIN);
                    if (zp < 0) preferZ = -1;
                    else if (zp > 0) preferZ = 1;
                    else preferZ = (data.bndUpDist > data.bndDownDist) ? -1 : 1;
                }
                var altZ:Number = -preferZ;

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

                // 1) 尽量保持原意图（含对角）
                if (bestX == 0 && bestZ == 0
                    && (oldWX != 0 || oldWZ != 0) && Mover.isDirectionWalkable(self, oldWX, oldWZ, probe)) {
                    bestX = oldWX; bestZ = oldWZ;
                }
                // 2) X优先：对角绕障（X + preferZ / altZ）
                else if (bestX == 0 && bestZ == 0
                    && oldWX != 0 && Mover.isDirectionWalkable(self, oldWX, preferZ, probe)) {
                    bestX = oldWX; bestZ = preferZ;
                } else if (bestX == 0 && bestZ == 0
                    && oldWX != 0 && Mover.isDirectionWalkable(self, oldWX, altZ, probe)) {
                    bestX = oldWX; bestZ = altZ;
                }
                // 3) 纯Z挪位（沿墙滑行/绕柱）
                else if (bestX == 0 && bestZ == 0
                    && Mover.isDirectionWalkable(self, 0, preferZ, probe)) {
                    bestX = 0; bestZ = preferZ;
                } else if (bestX == 0 && bestZ == 0
                    && Mover.isDirectionWalkable(self, 0, altZ, probe)) {
                    bestX = 0; bestZ = altZ;
                }
                // 4) 退一步（反向X/反向Z）
                else if (bestX == 0 && bestZ == 0
                    && oldWX != 0 && Mover.isDirectionWalkable(self, -oldWX, 0, probe)) {
                    bestX = -oldWX; bestZ = 0;
                } else if (bestX == 0 && bestZ == 0
                    && oldWZ != 0 && Mover.isDirectionWalkable(self, 0, -oldWZ, probe)) {
                    bestX = 0; bestZ = -oldWZ;
                }

                if (bestX != 0 || bestZ != 0) {
                    wantX = bestX;
                    wantZ = bestZ;
                    data._unstuckX = bestX;
                    data._unstuckZ = bestZ;
                    data._unstuckUntilFrame = frameNow + 10;

                    // UNSTUCK 属于"关键异常事件"，即便不开 AI调试模式，也建议在较高日志级别输出
                    if (_root.AI调试模式 == true || _root.AI日志级别 >= 2) {
                        _root.服务器.发布服务器消息("[MOV] " + self.名字
                            + " UNSTUCK"
                            + " from=" + oldWX + "," + oldWZ
                            + " to=" + bestX + "," + bestZ
                            + " pos=" + Math.round(data.x) + "," + Math.round(data.y));
                    }
                }
            }
        } else if (!trying) {
            // 无移动意图：清空脱困窗口，避免下一次移动继承旧方向
            data._unstuckUntilFrame = 0;
        }

        // ── Phase 1: X轴可行性检查 ──
        if (wantX < 0 && data.bndLeftDist < MARGIN) {
            xBlocked = true;
        } else if (wantX > 0 && data.bndRightDist < MARGIN) {
            xBlocked = true;
        }

        // ── Phase 2: X轴被阻时注入Z逃脱分量 ──
        if (xBlocked && wantX != 0 && wantZ == 0) {
            var zPick:Number = MovementResolver.pickZDirBySpaceEx(data, self, MARGIN);
            if (zPick < 0) wantZ = -1;
            else if (zPick > 0) wantZ = 1;
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
        if (_root.AI调试模式 == true) {
            var _f:Number = _root.帧计时器.当前帧数;
            if ((_f & 31) == 0 || result > 0) {
                var tag:String = (result == 0) ? "OK" : ((result == 1) ? "SLIDE" : "CORNER");
                _root.服务器.发布服务器消息("[MOV] " + self.名字
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
