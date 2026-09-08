// ============================================================
// HeroUnarmedMoveHelper — 空手专用移动辅助（全静态）
//
// 职责：
//   1. Z 轴精确对齐（D3）：由装备生命周期注册的每帧任务（"虎妙Z精确对齐"）驱动
//      alignTick。behavior 每 tick 视情况在 自机.虎妙Z对齐 放置
//      {目标:MovieClip, 停止距离:Number} 激活接管；不激活时本任务零开销直返。
//      算法：实时读 目标.Z轴坐标（避免4帧陈旧）→ 走不动/一步之内即收手（防越过目标 Z 抖动）
//      → 写 上行/下行 旗标，由 拳刀行走状态机 → 主角函数.行走 以 行走Y速度 位移并播
//        "空手行走" 动画（2026-09-09 起取代 Mover.move2D 直移：直移无走路动画、
//        且步长取 跑Y速度 ≈ 走路两倍速，实测观感"滑过去、比走路还快"）。
//   2. Z 对齐激活条件判定 shouldTakeOverZ（Chasing 调用）：
//        X轴距离 < 精确对齐触发X（默认250）
//     且 |Z差| < 精确对齐阈值倍率 × 每帧Z速度（默认4倍，≈1个决策窗位移）
//     且 方向为靠近（wantZ 与 diff_z 同号而非远离）
//
// 每帧任务注册/清理（生命周期侧）：
//   注册：_root.帧计时器.添加生命周期任务(自机, "虎妙Z精确对齐", fn, 33)
//   注销：_root.帧计时器.移除生命周期任务(自机, "虎妙Z精确对齐")（HeroUnarmedAI.destroy）
// ============================================================

import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.arki.unit.UnitAI.core.AIEnvironment;

class org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedMoveHelper {

    // ── 每帧任务入口（生命周期任务调用，obj = 自机）──
    public static function alignTick(self:MovieClip):Void {
        if (self == null || self._name == undefined) return;
        // 跳跃方向输入保持窗口优先：窗口内不做 Z 对齐位移，只回写方向输入
        // （小跳/闪现的位移帧读 上行/下行/左行/右行，不回写就会被清成默认后跳）
        if (syncLockedInput(self)) return;

        // ★空中/技能/倒地期禁走（根治 Z/Y 偏离与上下抖动）：
        //   跳跃/技能浮空的 _y 由 空中控制器 独占积分（高度=Z轴坐标-_y，落地回写 _y=Z轴坐标）；
        //   本任务若在此期间 move2D，会执行 _y = (Z轴坐标 += vy) —— 把空中单位拽回地面，
        //   下一帧重力积分又把 _y 拉起 → 每帧上下抖动，且 Z轴坐标 被拖走 → 落地后 Z/Y 偏离。
        //   技能/战技动画自带位移帧，同样不允许这里并行位移。清掉接管，交回 behavior 重新决策。
        //   高度判据补 0.5 容差（与 空中控制器/isInAir 同口径）：浮空标记存在"置位前/清除后"
        //   的一帧空窗，只看标记会在这几帧漏判，而一帧 move2D 就足以把 _y 拽回地面。
        var gz:Number = (!isNaN(self.Z轴坐标)) ? self.Z轴坐标 : self._y;
        var inAir:Boolean = (!isNaN(gz) && !isNaN(self._y)) && (self._y < gz - 0.5);
        if (self.浮空 == true || self.飞行浮空 == true || self.倒地 == true || inAir
            || self.状态 == "技能" || self.状态 == "战技") {
            self.虎妙Z对齐 = null;
            return;
        }

        var z:Object = self.虎妙Z对齐;
        if (z == null || z.目标 == null) return;

        var t:MovieClip = z.目标;
        // 目标失效（死亡/移除）→ 取消接管，交回原路径
        if (t._x == undefined || !(t.hp > 0)) {
            self.虎妙Z对齐 = null;
            return;
        }

        // 用实时坐标（self.Z轴坐标 / t.Z轴坐标），避免 AI 数据 4 帧陈旧
        var d:Number = t.Z轴坐标 - self.Z轴坐标;
        if (isNaN(d)) { self.虎妙Z对齐 = null; return; }
        // 容差：默认 0.5（精确对齐，chase/engage 口径）。
        //   无目标跟随传 z.停止距离 = 跟随停止Z（默认20）：只走到容差边就停，
        //   否则会一路贴到宿主身上、与宿主重叠站桩。
        var tol:Number = (z.停止距离 != undefined && !isNaN(z.停止距离)) ? z.停止距离 : 0.5;
        if (d > -tol && d < tol) {
            // 已进入容差：结束接管
            self.虎妙Z对齐 = null;
            return;
        }

        var ad:Number = (d < 0) ? -d : d;
        var need:Number = ad - tol; // 还需走的距离（走到容差边为止，永不越过）
        if (!(need > 0)) { self.虎妙Z对齐 = null; return; }

        // ★一步 = 行走Y速度（非主控单位上限 2.5）：与 主角函数.行走 的 Z 位移量同口径。
        //   旗标驱动不像 move2D 那样能任意截断步长，故改为"一步之内就收手"：
        //   误差 < 一步（≈2.5px），远小于 攻击判定Z(20)，且不会越过目标 Z 后反向纠偏抖动。
        var step:Number = self.行走Y速度;
        if (!(step > 0)) step = 5;
        if (need <= step) { self.虎妙Z对齐 = null; return; }

        // 末段边界：目标 Z 在边界外时，走到边界即可（room<=0 = 已贴边）
        var bMinY:Number = AIEnvironment.getYmin();
        var bMaxY:Number = AIEnvironment.getYmax();
        var room:Number = (d > 0) ? (bMaxY - self.Z轴坐标) : (self.Z轴坐标 - bMinY);
        if (!(room > 0)) { self.虎妙Z对齐 = null; return; }

        // ★边界收口复检：走不动（已贴边/被挡）就结束接管，交回 chase
        //   （其 clampZIntent 会把被挡的 Z 意图归零），否则持续硬压会挤来挤去。
        var dirZ:Number = (d > 0) ? 1 : -1;
        var probe:Number = (step < room) ? step : room;
        if (!Mover.isDirectionWalkable(self, 0, dirZ, probe)) {
            self.虎妙Z对齐 = null;
            return;
        }

        // ★旗标驱动（2026-09-09 改，取代 Mover.move2D 直移）：
        //   只写 上行/下行，位移交给 拳刀行走状态机 → 主角函数.行走 消费：
        //     移动("上"/"下", 行走Y速度) + 状态改变(攻击模式 + "行走")
        //   = 原生走路动画 + 原生走路速度，与正常 chase 走路完全一致。
        //   此前直移的两个代价（维护者实测"滑过去、比走路还快"）：
        //     ① 不经过行走状态机 → 没有"空手行走"动画，观感是平移滑行；
        //     ② 步长取 跑Y速度（= 行走Y速度 × 奔跑倍率，非主控 2.5→5）→ 约为走路两倍速。
        //   位移本身仍只查地图碰撞层、不经过 applyBoundaryAwareMovement 的 Phase 3，
        //   所以"贴边最后一程不会被自动反向"这个接管的核心意义不受影响。
        self.上行 = (dirZ < 0);
        self.下行 = (dirZ > 0);
    }

    // ── Z 意图边界收口（chase/engage/无目标跟随共用）──
    /**
     * 意图方向朝边界且**距边不足 80px** → 归零（最后一段由 Z 对齐接管走完）。
     * 根因一：applyBoundaryAwareMovement 的脱困逻辑遇到"地图边界"这种绕不开的阻挡时，
     * 会选反向逃离（24帧窗口）→ 窗口结束又朝边界压 → 无Progress → 再逃 → 无限振荡。
     * 根因二（2026-09-08 实测残留）：其 Phase 3 对朝边意图在 bnd*Dist < 80(MARGIN) 时
     * 会自动反向输出——收口带若只覆盖脱困探测距离(20~60px)，60~80px 带内意图被放行
     * → 被 Phase 3 反向 → 上下振荡。故收口阈值取 MARGIN(80)。
     * ★walkable 探测距离仍与脱困逻辑同口径（MovementResolver：行走X速度*5，钳 20..60）。
     *   此前用每帧Z速度(~5px)小步探测，离边 5~60px 的距离带里收口放行、脱困判挡
     *   → 照样触发逃离振荡（维护者实测"接近边缘来回抖、到不了边"即此残留）。
     * @param wantX X 意图（脱困探测是斜向端点，需一并传入对齐口径；无则传 0）
     * @param wantZ 本tick Z 意图（-1上/0无/1下）
     * @return 收口后的 wantZ（0=本次不输出 Z 位移，调用方应改走 Z 对齐接管）
     */
    public static function clampZIntent(self:MovieClip, wantX:Number, wantZ:Number):Number {
        if (wantZ == 0) return 0;
        var bMinY:Number = AIEnvironment.getYmin();
        var bMaxY:Number = AIEnvironment.getYmax();
        var z:Number = (!isNaN(self.Z轴坐标)) ? self.Z轴坐标 : self._y;
        var room:Number = (wantZ < 0) ? (z - bMinY) : (bMaxY - z);
        if (!(room > 0)) return 0; // 已贴到边界
        // ★收口阈值必须 ≥ applyBoundaryAwareMovement 的 MARGIN(80)：
        //   其 Phase 3 对"朝边意图"在 bnd*Dist < 80 时会自动反向输出
        //   （wantZ>0 且 bndDownDist<80 → 改输出 上行）。若只收口脱困探测带(20~60px)，
        //   60~80px 带内的朝边意图被放行 → 被 Phase 3 反向 → 单位向上走离 80 线
        //   → 下一拍意图又放行 → 向下折返；叠加 noProgress（意图向下、实际向上，
        //   投影为负）触发 24 帧脱困窗口锁死原意图 → 整段窗口持续被反向放大，
        //   实测表现即"目标站边缘，AI 在离边一段距离处反复上下抖动"。
        //   收口到 80px 后，这段距离带改由 Z 对齐接管（alignTick 写 上行/下行 旗标，
        //   由行走状态机以 行走Y速度 走完；位移只查地图碰撞层、不经过 Phase 3）
        //   → 正常走路动画与速度，且不会在距边 80px 内被自动反向。
        if (room < 80) return 0;
        // 与 MovementResolver 脱困探测同距离（行走X速度*5，钳 20..60）
        var spd:Number = self.行走X速度;
        if (isNaN(spd) || spd <= 0) spd = 6;
        var probe:Number = spd * 5;
        if (probe < 20) probe = 20;
        else if (probe > 60) probe = 60;
        return Mover.isDirectionWalkable(self, wantX, wantZ, probe) ? wantZ : 0;
    }

    // ── 激活条件判定（Chasing 每 tick 调用）──
    /**
     * @param data   UnitAIData（需已 updateSelf/updateTarget）
     * @param self   MovieClip
     * @param wantZ  本tick的 Z 移动意图（-1上/0无/1下）
     * @return Boolean 是否激活 Z 轴精确对齐接管
     */
    public static function shouldTakeOverZ(data:Object, self:MovieClip, wantZ:Number):Boolean {
        var p:Object = self.配置AI参数;
        if (p == null) return false;

        // 条件1：X 轴足够近
        if (!(data.absdiff_x < p.精确对齐触发X)) return false;

        // 条件2：|Z差| 小于 阈值倍率 × 每帧Z速度
        var zSpeed:Number = _getZSpeed(self);
        var threshold:Number = p.精确对齐阈值倍率 * zSpeed;
        if (!(data.absdiff_z < threshold)) return false;

        // 条件3：方向为靠近（wantZ 与 diff_z 同号；wantZ==0 无意图不接管）
        if (wantZ == 0) return false;
        // diff_z < 0 = 目标在上方 → 意图应为上行(-1)；diff_z > 0 → 下行(1)
        var approachZ:Number = (data.diff_z < 0) ? -1 : 1;
        if (wantZ != approachZ) return false;

        return true;
    }

    // ── 跳跃方向输入保持窗口（小跳/闪现专用）──
    /**
     * 技能动画的位移帧读 上行/下行/左行/右行，但 MovementResolver.clearInput（每 AI tick）
     * 与本文件 alignTick（每帧）都会清掉它们 → 不持续回写就会退回默认后跳。
     * 释放侧（HeroUnarmedSkillBrain._release）写 自机.单位方向锁 = {上行,下行,左行,右行,截止帧}，
     * 本函数在窗口内每次被调用都回写一次；过期自动清除。
     * @return Boolean 窗口是否仍然有效（有效时调用方可跳过后续移动/对齐输出）
     */
    public static function syncLockedInput(self:MovieClip):Boolean {
        var lock:Object = self.单位方向锁;
        if (lock == null) return false;
        var frame:Number = AIEnvironment.getFrame();
        if (!(frame <= lock.截止帧)) {
            self.单位方向锁 = null;
            return false;
        }
        self.上行 = (lock.上行 == true);
        self.下行 = (lock.下行 == true);
        self.左行 = (lock.左行 == true);
        self.右行 = (lock.右行 == true);
        return true;
    }

    /** 每帧 Z 速度：跑Y速度优先，回退 行走X速度/2，再回退 5 */
    public static function _getZSpeed(self:MovieClip):Number {
        var v:Number = self.跑Y速度;
        if (isNaN(v) || v <= 0) {
            var wx:Number = self.行走X速度;
            v = (isNaN(wx) || wx <= 0) ? 5 : wx / 2;
        }
        return v;
    }

    // ── 接管期间的 Z 旗标补写（AI tick 内调用）──
    /**
     * 必须在 MovementResolver.applyBoundaryAwareMovement **之后** 调用。
     * 原因：该函数开头会 clearInput 清掉 上行/下行；而接管生效时 Z 意图已被收口为 0，
     *   它不会重写 Z 旗标 → AI tick 那一帧行走状态机判"未移动" → 切回 空手站立 动画，
     *   观感是走三步顿一下。这里按接管目标方向补写一次即可对齐。
     * 其余帧由 alignTick（每帧任务）自行续写，无需调用方操心。
     */
    public static function syncZAlignInput(self:MovieClip):Void {
        if (self == null) return;
        var z:Object = self.虎妙Z对齐;
        if (z == null || z.目标 == null) return;
        var t:MovieClip = z.目标;
        if (t._x == undefined) return;
        var d:Number = t.Z轴坐标 - self.Z轴坐标;
        if (isNaN(d)) return;
        var tol:Number = (z.停止距离 != undefined && !isNaN(z.停止距离)) ? z.停止距离 : 0.5;
        self.上行 = (d < -tol);
        self.下行 = (d > tol);
    }
}
