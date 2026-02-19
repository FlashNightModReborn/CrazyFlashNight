import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

import org.flashNight.arki.spatial.move.Mover;

class org.flashNight.arki.unit.UnitAI.UnitAIData{

    // 自身引用
    public var self:MovieClip;
    public var self_name:String;
    public var state:String;
    public var createdFrame:Number;

    // 自身坐标
    public var x:Number;
    public var y:Number;
    public var z:Number;
    public var right:Boolean;
    public var left:Boolean;

    // 攻击目标引用
    public var target:MovieClip;
    // public var target_name:String; // 暂未启用

    // 攻击目标坐标
    public var tx:Number;
    public var ty:Number;
    public var tz:Number;

    // 目标速度追踪（T2-A 预测拦截）
    public var targetVX:Number;
    private var _prevTx:Number;
    private var _prevUpdateFrame:Number;
    private var _prevTargetRef:MovieClip;  // 检测目标切换，归零速度历史
    // 攻击目标与自身的坐标差值
    public var diff_x:Number;
    public var diff_y:Number;
    public var diff_z:Number;
    public var absdiff_x:Number;
    public var absdiff_z:Number;

    // 玩家引用
    public var player:MovieClip;

    // 根据自身的奔跑xy速度计算起跑距离
    public var run_threshold_x:Number;
    public var run_threshold_z:Number;

    
    // AI相关参数
    public var xrange:Number; // x轴攻击范围
    public var zrange:Number; // z轴攻击范围
	public var xdistance:Number; // x轴保持距离

    public var idle_threshold:Number; // 由追击转入停止状态的临界动作次数
    public var wander_threshold:Number; // 由追击转入随机移动状态的临界动作次数
    public var think_threshold:Number // 返回思考的临界时长
    
    public var evade_distance:Number; // 个性化的远离安全距离

    public var standby:Boolean; // 是否处于待机状态

    public var aiNextMode:String; // 模块主观完成信号（方案A预留）

    public var _chaseStartFrame:Number; // 追击开始帧（chase frustration 武器切换用）

    // 人格向量 + 派生AI参数（Phase 2）
    // 引用 self.personality 同一对象，mutate-only 策略保证不陈旧
    public var personality:Object;

    // Utility 评估器实例（仅 Hero 类型创建）
    public var evaluator:Object;

    // 统一动作决策管线（ActionArbiter）
    public var arbiter:Object;

    // 已施放的全局buff技能（单次施放保护，fight-scoped）
    public var _usedGlobalBuffs:Object;

    // ═══════ 边界感知（updateSelf 计算）═══════
    public var bndLeftDist:Number;   // 距左边界距离（像素）
    public var bndRightDist:Number;  // 距右边界距离
    public var bndUpDist:Number;     // 距上边界距离
    public var bndDownDist:Number;   // 距下边界距离
    public var bndCorner:Number;     // 角落压迫度 [0,1]（0=开阔, 1=贴角）


    public function UnitAIData(_self:MovieClip){
        this.self = _self;
        init();
    }

    public function init():Void{
        this.self_name = self._name;
        this.state = self.状态;
        // this.attackmode = self.攻击模式;
        this.target = null;
        // this.target_name = null;
        this.player = TargetCacheManager.findHero();
        //初始化ai参数
        this.xrange = self.x轴攻击范围;
        this.xdistance = self.x轴保持距离;
        this.zrange = 10; // 这里暂时不使用设置的z轴范围参数，并强制将原来填的数值刷新为10
        this.self.y轴攻击范围 = 10;
        // 根据自身的奔跑xy速度计算起跑距离
        // 如果跑速度尚未初始化（getter未装/属性未设置），从行走X速度和奔跑速度倍率推算
        var runX:Number = self.跑X速度;
        var runY:Number = self.跑Y速度;
        if (isNaN(runX) || runX <= 0) {
            var walkX:Number = self.行走X速度;
            var runMult:Number = self.奔跑速度倍率;
            if (isNaN(runMult) || runMult <= 0) runMult = 2;
            runX = walkX * runMult;
            runY = (walkX / 2) * runMult;
        }
        this.run_threshold_x = runX * 8;
        this.run_threshold_z = runY * 8;

        this.aiNextMode = null;
        this.personality = self.personality; // 六维 + 派生参数（同一对象引用）
        this.createdFrame = _root.帧计时器.当前帧数;
        this._usedGlobalBuffs = {};
    }

    public function updateSelf():Void{
        this.state = self.状态;
        this.x = self._x;
        this.y = self._y;
        this.z = self.Z轴坐标;
        this.right = self.方向 === "右";
        this.left = self.方向 === "左";
        this.standby = self.待机 ? true : false;

        // 边界距离（供 applyBoundaryAwareMovement 和评分修正器使用）
        var bMinX:Number = (_root.Xmin != undefined) ? _root.Xmin : 0;
        var bMaxX:Number = (_root.Xmax != undefined) ? _root.Xmax : Stage.width;
        var bMinY:Number = (_root.Ymin != undefined) ? _root.Ymin : 0;
        var bMaxY:Number = (_root.Ymax != undefined) ? _root.Ymax : Stage.height;
        this.bndLeftDist  = this.x - bMinX;
        this.bndRightDist = bMaxX - this.x;
        this.bndUpDist    = this.y - bMinY;
        this.bndDownDist  = bMaxY - this.y;
        // 角落压迫度：X轴和Z轴的边界压力乘积
        var _m:Number = 80;
        var xP:Number = 1 - Math.min(this.bndLeftDist, this.bndRightDist) / _m;
        var zP:Number = 1 - Math.min(this.bndUpDist, this.bndDownDist) / _m;
        this.bndCorner = ((xP > 0) ? xP : 0) * ((zP > 0) ? zP : 0);
    }
    
    public function updateTarget():Void{
        var target:MovieClip = this.target;
        if(target != null){
            // T2-A：目标速度追踪（预测拦截用）
            var curFrame:Number = _root.帧计时器.当前帧数;
            // 目标切换检测：不同对象引用 → 归零速度历史，防止预测过冲
            if (target != _prevTargetRef) {
                _prevTargetRef = target;
                _prevTx = target._x;
                _prevUpdateFrame = curFrame;
                targetVX = 0;
            } else {
                var dt:Number = curFrame - _prevUpdateFrame;
                if (dt > 0 && !isNaN(_prevTx)) {
                    targetVX = (target._x - _prevTx) / dt;
                } else {
                    targetVX = 0;
                }
                _prevTx = target._x;
                _prevUpdateFrame = curFrame;
            }

            this.tx = target._x;
            this.ty = target._y;
            this.tz = isNaN(target.Z轴坐标) ? target._y : target.Z轴坐标;
            //
            this.diff_x = this.tx - this.x;
            this.diff_y = this.ty - this.y;
            this.diff_z = this.tz - this.z;
            this.absdiff_x = Math.abs(this.diff_x);
            this.absdiff_z = Math.abs(this.diff_z);
        }else{
            this.tx = null;
            this.ty = null;
            this.tz = null;
            //
            this.diff_x = null;
            this.diff_y = null;
            this.diff_z = null;
            this.absdiff_x = null;
            this.absdiff_z = null;
        }
    }

    // 卡死检测的历史位置缓存
    private var _lastStuckCheckFrame:Number = -1;
    private var _lastSelfX:Number;
    private var _lastSelfY:Number;
    private var _lastSelfZ:Number;
    private var _stuckCheckCount:Number = 0;

    // 障碍脱困（仅在确实卡死时触发，避免每帧碰撞探测）
    private var _unstuckUntilFrame:Number = 0;
    private var _unstuckX:Number = 0;
    private var _unstuckZ:Number = 0;

    /**
     * 改进版卡死检测 - 基于自身绝对位置变化而非相对距离变化
     * 
     * 解决原版本的误报问题：
     * 1. 检测自身绝对位置变化而非与目标的相对距离
     * 2. 适配间隔检测（非每帧调用）
     * 3. 需要连续多次检测到无移动才判定为卡死
     *
     * @param isTryingToMove  是否有移动意图
     * @param eps            位置变化阈值（像素）
     * @param minStuckCount  连续无移动的最小次数才判定卡死（默认3）
     * @return Boolean       true=确实卡死；false=正常
     */
    public function stuckProbeByDiffChange(isTryingToMove:Boolean, eps:Number, minStuckCount:Number):Boolean {
        // 参数默认值处理
        if (isTryingToMove == undefined) {
            var s:String = this.state;
            isTryingToMove = (s == "Walk" || s == "Run" || s == "Chase" || s == "移动" || s == "追击" || s == "奔跑");
        }
        if (eps == undefined) eps = 8; // 提高阈值，适配四向移动
        if (minStuckCount == undefined) minStuckCount = 3;

        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 非移动意图 / 待机状态：重置检测计数
        if (!isTryingToMove || this.standby) {
            this._stuckCheckCount = 0;
            this._lastStuckCheckFrame = currentFrame;
            return false;
        }

        // 更新自身坐标
        this.updateSelf();

        // 初次检测：记录位置，不判定卡死
        if (this._lastStuckCheckFrame < 0 || 
            this._lastSelfX == undefined || 
            this._lastSelfY == undefined || 
            this._lastSelfZ == undefined) {
            
            this._lastSelfX = this.x;
            this._lastSelfY = this.y;
            this._lastSelfZ = this.z;
            this._lastStuckCheckFrame = currentFrame;
            this._stuckCheckCount = 0;
            return false;
        }

        // 检测时间间隔过短，跳过本次检测
        var frameGap:Number = currentFrame - this._lastStuckCheckFrame;
        if (frameGap < 4) { // 至少4帧间隔再检测
            return this._stuckCheckCount >= minStuckCount;
        }

        // 计算位置变化量
        var deltaX:Number = Math.abs(this.x - this._lastSelfX);
        var deltaY:Number = Math.abs(this.y - this._lastSelfY);
        var deltaZ:Number = Math.abs(this.z - this._lastSelfZ);
        var delta2:Number = deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ;
        var eps2:Number = eps * eps;

        // 判断是否有显著移动（避免 sqrt，性能更好）
        var hasMoved:Boolean = delta2 > eps2;

        if (hasMoved) {
            // 有移动：重置卡死计数
            this._stuckCheckCount = 0;
        } else {
            // 无移动：增加卡死计数
            this._stuckCheckCount++;
        }

        // 更新检测记录
        this._lastSelfX = this.x;
        this._lastSelfY = this.y;
        this._lastSelfZ = this.z;
        this._lastStuckCheckFrame = currentFrame;

        // 调试输出
        if (_root.调试模式 && this._stuckCheckCount > 0) {
            var totalDelta:Number = Math.sqrt(delta2);
            _root.发布消息(this.self, "卡死检测: " + this._stuckCheckCount + "/" + minStuckCount + " 移动距离: " + totalDelta);
        }

        // 只有连续多次无移动才判定为真正卡死
        return this._stuckCheckCount >= minStuckCount;
    }

    /**
     * 轻量卡死检测（假设本帧已调用 updateSelf）
     *
     * 与 stuckProbeByDiffChange 的区别：
     *  - 不会在内部调用 updateSelf()（避免重复计算）
     *  - 适合 applyBoundaryAwareMovement 等热路径统一调用
     *
     * @param isTryingToMove 是否有移动意图（wantX/wantZ 非0）
     * @param eps            位置变化阈值（像素）
     * @param minStuckCount  连续无移动次数阈值
     * @param minFrameGap    两次检测的最小帧间隔
     * @return Boolean       true=确实卡死；false=正常
     */
    public function stuckProbeByCurrentPosition(isTryingToMove:Boolean,
                                                eps:Number,
                                                minStuckCount:Number,
                                                minFrameGap:Number):Boolean {
        if (eps == undefined) eps = 8;
        if (minStuckCount == undefined) minStuckCount = 3;
        if (minFrameGap == undefined) minFrameGap = 4;

        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 非移动意图 / 待机状态：重置检测计数
        if (!isTryingToMove || this.standby) {
            this._stuckCheckCount = 0;
            this._lastStuckCheckFrame = currentFrame;
            this._lastSelfX = this.x;
            this._lastSelfY = this.y;
            this._lastSelfZ = this.z;
            return false;
        }

        // 初次检测：记录位置，不判定卡死
        if (this._lastStuckCheckFrame < 0
            || this._lastSelfX == undefined
            || this._lastSelfY == undefined
            || this._lastSelfZ == undefined) {
            this._lastSelfX = this.x;
            this._lastSelfY = this.y;
            this._lastSelfZ = this.z;
            this._lastStuckCheckFrame = currentFrame;
            this._stuckCheckCount = 0;
            return false;
        }

        // 检测时间间隔过短，跳过本次检测
        var frameGap:Number = currentFrame - this._lastStuckCheckFrame;
        if (frameGap < minFrameGap) {
            return this._stuckCheckCount >= minStuckCount;
        }

        // 计算位置变化量（使用本帧已更新的 x/y/z）
        var deltaX:Number = Math.abs(this.x - this._lastSelfX);
        var deltaY:Number = Math.abs(this.y - this._lastSelfY);
        var deltaZ:Number = Math.abs(this.z - this._lastSelfZ);
        var delta2:Number = deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ;
        var eps2:Number = eps * eps;

        if (delta2 > eps2) {
            this._stuckCheckCount = 0;
        } else {
            this._stuckCheckCount++;
        }

        this._lastSelfX = this.x;
        this._lastSelfY = this.y;
        this._lastSelfZ = this.z;
        this._lastStuckCheckFrame = currentFrame;

        return this._stuckCheckCount >= minStuckCount;
    }

    /**
     * pickZDirBySpaceEx — 根据上下边界空间选择 Z 方向（轻量版）
     *
     * 统一多处“上下空间选择”逻辑（走位/沿墙滑行/脱困），避免各处规则漂移。
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
     * applyBoundaryAwareMovement — 统一边界感知移动输出
     *
     * 接收语义化移动意图（wantX: -1=左, 0=无, 1=右; wantZ: -1=上, 0=无, 1=下），
     * 处理边界碰撞并输出到 self 的移动标志。
     *
     * 三级逃脱策略：
     *   0=正常：方向可行，直接输出
     *   1=沿墙滑行：X轴贴墙 → 不输出X，自动注入Z分量斜向逃脱
     *   2=角落突围：X+Z都被堵 → 反转X方向冲出（打出去）
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
                    var zp:Number = UnitAIData.pickZDirBySpaceEx(data, self, MARGIN);
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

                    // UNSTUCK 属于“关键异常事件”，即便不开 AI调试模式，也建议在较高日志级别输出
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
            var zPick:Number = UnitAIData.pickZDirBySpaceEx(data, self, MARGIN);
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
     * clearInput — 重置所有移动/动作输入标志
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
