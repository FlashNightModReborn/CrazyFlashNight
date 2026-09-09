// ============================================================
// HeroUnarmedBehavior — 空手专用根状态机（继承 BaseUnitBehavior）
//
// 根机状态：
//   Sleeping — 基类默认状态（暂停/无思考标签时 Gate 兜底转入）
//   Selector — 决策中枢：索敌 + 无目标待命 + 待机喝药
//   Combat   — 战斗子状态机 HeroUnarmedCombatModule（Chasing/Engaging）
//   Evade    — 短时脱离（D4：低血触发，Z轴远离优先，限时强制回战斗，禁无限逛街）
//
// 设计约束（维护者拍板）：
//   - 不实现默认 HeroCombatBehavior 的 Retreating（逛街主因），只有短时 Evade
//   - 默认 AI/通用层零改动；本类全部为我们的新增实现
// ============================================================

import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.unit.UnitAI.core.BaseUnitBehavior;
import org.flashNight.arki.unit.UnitAI.core.UnitAIData;
import org.flashNight.arki.unit.UnitAI.core.AIEnvironment;
import org.flashNight.arki.unit.UnitAI.combat.MovementResolver;
import org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedSkillBrain;
import org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedCombatModule;
import org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedMoveHelper;

class org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedBehavior extends BaseUnitBehavior {

    private var brain:HeroUnarmedSkillBrain;
    private var combat:HeroUnarmedCombatModule;
    private var p:Object;

    // Evade 状态
    private var _evadeStartFrame:Number = -1;
    private var _evadeStartX:Number = 0;
    private var _evadeCooldownUntil:Number = 0;
    private var _evadeJumpTried:Boolean = false;

    public function HeroUnarmedBehavior(_data:UnitAIData, _brain:HeroUnarmedSkillBrain) {
        super(_data);
        this.brain = _brain;
        this.p = _data.self.配置AI参数;
        if (this.p == null) this.p = {};

        var behavior:HeroUnarmedBehavior = this;

        // ═══════ 状态列表 ═══════
        // 已存在：Sleeping（基类默认状态）

        // Selector：enter + action 都走同一决策（无目标时每 tick 重搜，防永久停留）
        this.AddStatus("Selector", new FSM_Status(function() {
            behavior.selector_enter();
        }, function() {
            behavior.selector_enter();
        }, null));

        this.combat = new HeroUnarmedCombatModule(_data, _brain);
        this.AddStatus("Combat", this.combat);

        this.AddStatus("Evade", new FSM_Status(
            function() { behavior.evade_action(); },
            function() { behavior.evade_enter(); },
            function() { behavior.evade_exit(); }
        ));

        // ═══════ Root Gate 转换 ═══════

        // Selector → Combat：索敌成功
        this.pushGateTransition("Selector", "Combat", function():Boolean {
            var t = data.target;
            return (t != null && t.hp > 0 && t._x != undefined);
        });

        // Combat → Selector：目标死亡/消失
        this.pushGateTransition("Combat", "Selector", function():Boolean {
            var t = data.target;
            return (t == null || !(t.hp > 0) || t._x == undefined);
        });

        // Combat → Evade：低血 + 近身威胁 + 冷却结束 + 概率触发（禁高频逃离）
        this.pushGateTransition("Combat", "Evade", function():Boolean {
            var frame:Number = AIEnvironment.getFrame();
            if (frame < behavior._evadeCooldownUntil) return false;
            var maxHP:Number = data.self.hp满血值;
            if (!(maxHP > 0)) return false;
            var lowTH:Number = behavior.p.低血阈值;
            if (lowTH == undefined || isNaN(lowTH)) lowTH = 0.5;
            if (data.self.hp / maxHP >= lowTH) return false;
            // 仅近身受威胁时脱离（远距离没必要跑）
            if (data.absdiff_x > 160) return false;
            return Math.random() < 0.15;
        });

        // Evade → Combat：贴身失效（敌人仍在攻击判定范围内 = 没跑掉，
        // 继续无攻击逃跑只会站着挨打 → 视为脱离失效直接回战斗）。
        // 前 15 帧宽限留给 enter 时的 闪现/小跳 位移爆发（50% 概率不跳，宽限照给）。
        this.pushGateTransition("Evade", "Combat", function():Boolean {
            if (AIEnvironment.getFrame() - behavior._evadeStartFrame <= 15) return false;
            var t = data.target;
            if (t == null || !(t.hp > 0) || t._x == undefined) return false;
            return data.absdiff_x <= behavior.p.攻击判定X
                && data.absdiff_z <= behavior.p.攻击判定Z;
        });

        // Evade → Selector：限时到 / 距离已拉开 / 目标失效（禁无限逛街）
        this.pushGateTransition("Evade", "Selector", function():Boolean {
            var frame:Number = AIEnvironment.getFrame();
            var maxSec:Number = behavior.p.迂回最长秒数;
            if (maxSec == undefined || isNaN(maxSec)) maxSec = 2.5;
            if (frame - behavior._evadeStartFrame >= maxSec * 30) return true; // 30FPS
            if (data.absdiff_x > 250) return true; // 已拉开足够距离
            var t = data.target;
            return (t == null || !(t.hp > 0) || t._x == undefined);
        });

        // 唤醒：Sleeping → Selector
        this.pushGateTransition("Sleeping", "Selector", this.wakeupCheck);
    }

    // ═══════ 决策中枢 ═══════

    private function selector_enter():Void {
        var self:MovieClip = data.self;
        MovementResolver.clearInput(self);

        if (self.hp <= 0) {
            self.状态改变(AIEnvironment.isBloodyMode() ? "血腥死" : "击倒");
            return;
        }
        if (AIEnvironment.isPaused()) return;

        data.updateSelf();

        // 待机也照常喝药（脱离战斗回血窗口）
        brain.tickHeal(AIEnvironment.getFrame());

        // 索敌（复刻 寻找攻击目标：威胁阈值随机化）
        var threshold = self.threatThreshold;
        if (threshold == undefined || isNaN(threshold)) threshold = 1;
        if (threshold > 1) threshold = 1 + Math.floor(Math.random() * threshold);

        var target:MovieClip = MovieClip(TargetCacheManager.findValidEnemyForAI(self, 1, threshold));
        if (target != null && target.hp > 0) {
            data.target = target;
            self.攻击目标 = target._name;
            if (self.dispatcher != null) self.dispatcher.publish("aggroSet", self, target);
        } else {
            data.target = null;
            if (self.dispatcher != null) self.dispatcher.publish("aggroClear", self);
            // 无目标待命：清 Z 对齐，避免残留接管
            self.虎妙Z对齐 = null;
            // 无目标跟随：不站桩（见 _followWhenNoTarget 说明）
            _followWhenNoTarget();
        }
    }

    /**
     * 无目标时朝主角移动（对应默认 AI 的 FollowingHero，HeroCombatBehavior:238/245）。
     *
     * 为什么必须有：默认 AI 索敌失败会转 FollowingHero 朝主角走；我们原实现无目标时什么都不做 → 原地站桩。
     * 站桩还会形成恶性循环：不动 → 与敌人距离拉大 → findValidEnemyForAI 的邻域扩张有距离安全阀
     * （searchLimit 30 步 + distanceThreshold = 自适应阈值×5）→ 越站越搜不到。
     * 朝主角移动既符合佣兵/敌人行为，也天然把单位带回战场重获目标。
     *
     * 开关：参数 无目标跟随（0=禁用）；停止距离 跟随停止距离 / 跟随停止Z。
     */
    private function _followWhenNoTarget():Void {
        var self:MovieClip = data.self;
        if (Number(p.无目标跟随) == 0) return;

        // 技能/战技/倒地中不移动（状态机层面不接管这些表现）
        var st:String = self.状态;
        if (st == "技能" || st == "战技" || st == "击倒" || self.倒地 == true) return;

        var hero:MovieClip = MovieClip(TargetCacheManager.findHero());
        if (hero == null || hero._x == undefined || !(hero.hp > 0)) return;
        if (hero._name == self._name) return; // 自己就是主角

        var dx:Number = hero._x - data.x;
        var hz:Number = isNaN(hero.Z轴坐标) ? hero._y : hero.Z轴坐标;
        var dz:Number = hz - data.z;
        var absDx:Number = Math.abs(dx);
        var absDz:Number = Math.abs(dz);

        var stopX:Number = Number(p.跟随停止距离);
        if (!(stopX > 0)) stopX = 120;
        var stopZ:Number = Number(p.跟随停止Z);
        if (!(stopZ > 0)) stopZ = 20;

        if (absDx <= stopX && absDz <= stopZ) {
            self.虎妙Z对齐 = null; // 已到位：清接管，保持静止
            return;
        }

        var wantX:Number = (absDx > stopX) ? ((dx < 0) ? -1 : 1) : 0;
        var wantZ:Number = (absDz > stopZ) ? ((dz < 0) ? -1 : 1) : 0;
        // ★边界收口：距边不足 80px（Phase3 MARGIN，防其自动反向造成上下抖）时归零
        var rawZ:Number = wantZ;
        wantZ = HeroUnarmedMoveHelper.clampZIntent(self, wantX, wantZ);

        // ★收口后的最后一程（宿主站边缘时也要贴边）：意图仍在但被收口 → 交给 Z 对齐接管，
        //   alignTick 写 上行/下行 旗标由行走状态机走完（正常走路动画与速度），
        //   不经过 applyBoundaryAwareMovement 的 Phase 3（那会在距边 80px 内自动
        //   反向 → 上下抖）。
        //   停止距离 = stopZ：走到跟随容差边即停，避免贴到宿主身上重叠站桩。
        if (rawZ != 0 && wantZ == 0) {
            self.虎妙Z对齐 = {
                目标: hero,
                每帧速度: HeroUnarmedMoveHelper._getZSpeed(self),
                停止距离: stopZ
            };
        } else if (rawZ == 0) {
            self.虎妙Z对齐 = null;
        }

        MovementResolver.applyBoundaryAwareMovement(UnitAIData(data), self, wantX, wantZ);
        // 接管靠 上行/下行 旗标驱动走路 → 移动输出的 clearInput 会清掉它，这里补写回来
        HeroUnarmedMoveHelper.syncZAlignInput(self);
    }

    // ═══════ 短时脱离（D4）═══════

    private function evade_enter():Void {
        var self:MovieClip = data.self;
        var frame:Number = AIEnvironment.getFrame();
        MovementResolver.clearInput(self);
        self.虎妙Z对齐 = null; // 脱离期不用精确对齐

        _evadeStartFrame = frame;
        _evadeStartX = self._x;
        _evadeJumpTried = false;

        // 进入脱离时尝试用 小跳/闪现 做位移爆发（CD 由已学技能表条目约束）
        _tryEscapeSkill(frame);
    }

    private function evade_action():Void {
        var self:MovieClip = data.self;
        var frame:Number = AIEnvironment.getFrame();
        MovementResolver.clearInput(self);

        if (self.hp <= 0) return;
        if (AIEnvironment.isPaused()) return;

        data.updateSelf();
        if (data.target != null && data.target.hp > 0) data.updateTarget();

        // 脱离途中自然喝药
        brain.tickHeal(frame);

        // ★脱离不停止攻击（迂回只是移动倾向）：技能脑照常 tick，
        //   技能/搓招/对空该出就出——攻击与 Combat 状态完全同权
        brain.tick(frame);
        HeroUnarmedMoveHelper.syncLockedInput(self);

        // 技能播放中不移动
        if (self.状态 == "技能" || self.状态 == "战技") return;
        // 搓招最小持续保护期间同样静默移动（同 CombatModule：行走状态机会把
        // "空手攻击"掐成"空手行走"，招式中途夭折）
        if (brain.isChargeProtected(frame)) return;

        // 方向：Z 轴远离为主（上下），X 轴远离设上限（迂回横向最大位移）
        var awayZ:Number = 0;
        if (data.target != null && data.absdiff_z > 5) {
            // 远离目标：目标在上方(diff_z<0) → 向下远离(+1)，反之向上(-1)
            awayZ = (data.diff_z < 0) ? 1 : -1;
            // 边界硬约束：倾向侧没空间则反向
            var space:Number = MovementResolver.pickZDirBySpaceEx(data, self, 80);
            if (space == 0) awayZ = 0;
            else if (space == 2 && awayZ < 0) awayZ = 1;
            else if (space == -2 && awayZ > 0) awayZ = -1;
        }

        // X 轴远离 + 横向位移封顶（迂回横向最大位移）：
        // awayX = 与目标相反方向；沿 awayX 方向累计漂移达到上限后停止横向移动
        var wantX:Number = 0;
        var maxDrift:Number = p.迂回横向最大位移;
        if (maxDrift == undefined || isNaN(maxDrift)) maxDrift = 120;
        if (data.target != null && data.absdiff_x < 250) {
            var awayX:Number = (data.diff_x < 0) ? 1 : -1; // 目标在左→向右远离，反之向左
            var drift:Number = (awayX > 0) ? (self._x - _evadeStartX) : (_evadeStartX - self._x);
            if (drift < maxDrift) wantX = awayX;
        }

        // ★脱离用跑步（逃命不容慢走）：跑状态 X/Y 双轴提速（跑X速度/跑Y速度），
        //   且行走处理器会自我维持跑状态、无输入自动回站立（玩家模板迁移.as:510/533）。
        //   守卫同 chase 的跑步切换（防每 tick 重复 状态改变）；
        //   不带 chase 的 absdiff_z<=20 限制——那是防追击斜向冲过目标，脱离无此顾虑。
        if ((wantX != 0 || awayZ != 0) && self.状态 != self.攻击模式 + "跑") {
            self.状态改变(self.攻击模式 + "跑");
        }

        MovementResolver.applyBoundaryAwareMovement(UnitAIData(data), self, wantX, awayZ);
    }

    private function evade_exit():Void {
        // 再入冷却（振荡抑制）
        _evadeCooldownUntil = AIEnvironment.getFrame() + 90;
        MovementResolver.clearInput(data.self);
    }

    /**
     * 脱离位移技能：小跳/闪现（残血专属用法）。
     * 先把 上行/下行 置为远离方向，再走技能路由（技能动画按 Z 输入方向跳）。
     * CD 由已学技能表条目的 上次使用时间 约束。
     */
    private function _tryEscapeSkill(frame:Number):Void {
        if (_evadeJumpTried) return;
        if (Math.random() > 0.5) { _evadeJumpTried = true; return; }

        var self:MovieClip = data.self;
        var candidates:Array = ["闪现", "小跳"];
        for (var i:Number = 0; i < candidates.length; i++) {
            var sk:Object = _findSkill(candidates[i]);
            if (sk == null) continue;
            if (!isNaN(sk.上次使用时间)
                && (getTimer() - sk.上次使用时间 <= sk.冷却 * 1000)) continue;
            if (sk.消耗 > 0 && self.mp < sk.消耗) continue;

            // 设置远离方向的 Z 输入（技能动画读取）。
            // ★贴边覆盖（仅贴边时，80=Phase3 MARGIN 同口径）：距上缘<80→向下，距下缘<80→向上
            var awayZ:Number = (data.diff_z < 0) ? 1 : -1;
            if (!isNaN(data.bndUpDist) && data.bndUpDist < 80) awayZ = 1;
            else if (!isNaN(data.bndDownDist) && data.bndDownDist < 80) awayZ = -1;
            var upD:Boolean = (awayZ < 0);
            var downD:Boolean = (awayZ > 0);
            self.上行 = upD;
            self.下行 = downD;
            self.动作A = false;

            // ★必须写方向锁：这里只设一次旗标，下一拍 evade_action 的 clearInput 就会清掉
            //   （syncLockedInput 只回写 单位方向锁，锁为 null 时无从恢复）→ 动画读到无方向
            //   → 默认后跳/后闪现。这就是"偶尔默认后跳"的主因。锁窗口与 _release 同参。
            var lockFrames:Number = Number(p.跳跃方向锁帧);
            if (!(lockFrames > 0)) lockFrames = 15;
            self.单位方向锁 = {上行: upD, 下行: downD, 左行: false, 右行: false,
                截止帧: frame + lockFrames};

            sk.上次使用时间 = getTimer();
            self.技能等级 = Math.min(Math.ceil(self.等级 / 10), 10);
            if (!(self.技能等级 > 0)) self.技能等级 = 1;
            AIEnvironment.routeSkill(self, sk.技能名);
            break;
        }
        _evadeJumpTried = true;
    }

    private function _findSkill(名:String):Object {
        var skills:Array = data.self.已学技能表;
        if (skills == null) return null;
        for (var i:Number = 0; i < skills.length; i++) {
            if (skills[i] != null && skills[i].技能名 == 名) return skills[i];
        }
        return null;
    }
}
