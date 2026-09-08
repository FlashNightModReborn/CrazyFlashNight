// ============================================================
// HeroUnarmedMoveHelper — 空手专用移动辅助（全静态）
//
// 职责：
//   1. Z 轴精确对齐（D3）：由装备生命周期注册的每帧任务（"虎妙Z精确对齐"）驱动
//      alignTick。behavior 每 tick 视情况在 自机.虎妙Z对齐 放置
//      {目标:MovieClip, 每帧速度:Number} 激活接管；不激活时本任务零开销直返。
//      算法：实时读 目标.Z轴坐标（避免4帧陈旧）→ 末步截断（步长>剩余距离时取剩余）
//      → Mover.move2D 直接走，并清 上行/下行（避免行走状态机重复位移/双走）。
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
        if (d > -0.5 && d < 0.5) {
            // 已对齐：结束接管
            self.虎妙Z对齐 = null;
            return;
        }

        var ad:Number = (d < 0) ? -d : d;
        var step:Number = z.每帧速度;
        if (!(step > 0)) step = 5;
        if (ad < step) step = ad; // ★末步截断：精确对齐，永不越过目标 Z

        // ★末段边界钳制：目标 Z 在边界外时把步长钳到剩余边界距离——
        //   端点恰好压在 Ymin/Ymax 上（isDirectionWalkable 判可行走）→ 能正好走到边缘。
        //   本任务用步长级小步直走（Mover.move2D），完全绕开脱困逻辑的探测/逃离，
        //   这是"贴边最后一程"能走通的关键（chase 的收口在距边 20~60px 就把意图归零了）。
        var bMinY:Number = AIEnvironment.getYmin();
        var bMaxY:Number = AIEnvironment.getYmax();
        var room:Number = (d > 0) ? (bMaxY - self.Z轴坐标) : (self.Z轴坐标 - bMinY);
        if (step > room) step = room;
        if (!(step > 0)) { self.虎妙Z对齐 = null; return; } // 已贴边且目标在界外：走完即止

        // ★边界收口复检：目标 Z 在边界外/被挡时不再硬压——走不动就结束接管，
        //   交回 chase（其 clampZIntent 会把被挡的 Z 意图归零），否则每 33ms 撞边
        //   会被 resolveCollision 挤来挤去，观感即贴边上下抖。
        if (!Mover.isDirectionWalkable(self, 0, (d > 0 ? 1 : -1), step)) {
            self.虎妙Z对齐 = null;
            return;
        }

        // 交给我们走：清 Z 输入标志，避免行走状态机重复位移
        self.上行 = false;
        self.下行 = false;
        Mover.move2D(self, d > 0 ? "下" : "上", step);
    }

    // ── Z 意图边界收口（chase/engage/无目标跟随共用）──
    /**
     * 意图方向朝边界且**距边不足一个脱困探测距离** → 归零（最后一段由 Z 对齐接管走完）。
     * 根因：applyBoundaryAwareMovement 的脱困逻辑遇到"地图边界"这种绕不开的阻挡时，
     * 会选反向逃离（24帧窗口）→ 窗口结束又朝边界压 → 无Progress → 再逃 → 无限振荡。
     * ★探测距离必须与脱困逻辑同口径（MovementResolver：行走X速度*5，钳 20..60，斜向端点）。
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
        // 与 MovementResolver 脱困探测同距离（行走X速度*5，钳 20..60）
        var spd:Number = self.行走X速度;
        if (isNaN(spd) || spd <= 0) spd = 6;
        var probe:Number = spd * 5;
        if (probe < 20) probe = 20;
        else if (probe > 60) probe = 60;
        if (room < probe) return 0; // 距边不足一个脱困探测距离：收口（脱困逻辑必判挡）
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
}
