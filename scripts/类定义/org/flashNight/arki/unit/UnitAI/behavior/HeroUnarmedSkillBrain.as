// ============================================================
// HeroUnarmedSkillBrain — 空手专用自研技能脑（D2：不复用 ActionArbiter）
//
// 职责：
//   1. 候选构建：已学技能表 + 战技条目，按 距离/CD/MP/特殊规则 过滤
//   2. 分层裁决：优先级 0~3（小号优先），同层随机；不评分竞赛
//   3. 平A窗口：射程内先掷骰子（参数 平A保底概率，默认 30%），命中即开一个 平A窗口帧（默认30）
//      的窗口，窗口内逐 tick 续写 动作A（空手连段靠持续按键推进，只写一次只能打出第一下）
//      且不进技能裁决；击倒/浮空/倒地/脱离射程/低血受威胁 一律中断窗口。
//      置 自机.单位平A中：平A 期间禁止 _tryInterrupt 换招（否则平A 会被 tier0 保命技顶掉）。
//      ★窗口维持必须排在 B 分支复位之后、C2 之前：B 在 状态!=技能/战技 时每 tick 都走到，
//        而平A的 状态 是 攻击模式+"攻击"，无条件复位会让平A只持续 1 tick（"几乎不平A"）。
//   4. 打断与 commit（D10）：
//        不可打断：表内 不可打断:true（铁布衫/觉醒霸体/聚气）+ 外部不可打断技能名单
//        （按 单位.技能名 判定，如 扭转乾坤 —— 由九命猫妖周期直接路由触发，本脑表里没有）；
//        高血（HP≥低血阈值）—— 打完一整套（以 状态 离开 技能/战技 为准），
//            期间仅 优先级0（保命/解围/躲避）可强制打断；
//        低血（HP<低血阈值）—— 低血commitFrames（默认30）后允许被更高优先级打断换招。
//   5. 特殊规则（5.7）：霸体不重复 / 能量盾退化为本图一次 / 单图永久技能 / 
//      踩人仅空中 / 空中技能组 {震地,地震,踩人} / MP 门槛
//   6. 释放：技能 → AIEnvironment.routeSkill；战技 → _root.战技路由.战技标签跳转_旧
//      （咒针 = 写 手部发射子弹属性（普通咒针）→ 路由 "手部发射"，已核实无独立条目）
//   7. 喝药：独立轨（D4），不走技能候选；必喝线 0.4 / 想喝线 0.7，最小间隔约1秒
//
// CD 口径与 SkillCandidateStrategy 一致：getTimer() ms，冷却*1000。
// 释放时写 sk.上次使用时间（替代 ActionArbiter 的职责）。
// ============================================================

import org.flashNight.arki.unit.UnitAI.core.UnitAIData;
import org.flashNight.arki.unit.UnitAI.core.AIEnvironment;
import org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedSkillTable;

class org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedSkillBrain {

    private var self:MovieClip;
    private var data:UnitAIData;
    private var p:Object;              // 配置AI参数（生命周期注入）
    private var battleSkills:Array;    // 战技条目副本（每单元独立CD）

    // commit / 打断状态
    private var _lastUnitState:String;     // 上一tick的 状态（检测 技能/战技 开始）
    private var _skillStartFrame:Number = -1;  // 当前技能开始帧
    private var _currentSkillTier:Number = -1; // 当前技能的裁决层号
    private var _currentSkillName:String = null;
    private var _currentSkill:Object = null;   // 当前技能条目引用（读 不可打断 / 单图一次 等标记）

    // 位移技能主动使用间隔锁（getTimer 时间戳）：小跳/闪现释放后 位移使用间隔 秒内，
    // 常态裁决(H)与打断换招(_tryInterrupt)不再选它们 —— 它们表内 CD 仅 1/2 秒且成本极低，
    // 受威胁/低血状态下会被同层随机反复抽中 → 观感"连续小跳闪现"。
    // 注：击倒脱困已完全交给原生机制（见 C2 分支注释），本锁只约束常态裁决与打断换招。
    private var _dodgeLockUntil:Number = 0;

    // 平A窗口起始帧（配合 自机.单位平A中，-1 = 无窗口）
    private var _normalAttackStartFrame:Number = -1;

    // 搓招最小持续保护（续32）：燃烧指节/能量喷泉等标了 持续帧 的搓招条目，
    // 释放后走"空手攻击"状态 —— A 分支（技能/战技 commit）管不到、B 分支每 tick
    // 复位 commit → 下一拍就被 G 平A保底 / H 技能裁决切掉（"刚触发就换招"）。
    // 保护窗口内（血量健康）本脑不再出招/平A，仅受威胁躲避可打断；详见 _chargeSustainTick。
    private var _chargeProtectUntilFrame:Number = -1; // 保护截止帧（-1 = 无保护）
    private var _chargeProtectName:String = null;     // 受保护招式名（调试/日志用）

    // 喝药节流
    private var _lastHealFrame:Number = -999;
    private var _healMinGapFrames:Number = 30; // 约1秒（30FPS）

    public function HeroUnarmedSkillBrain(_data:UnitAIData, params:Object) {
        this.data = _data;
        this.self = _data.self;
        this.p = params;
        // 战技组：优先用生命周期写入的 自机.单位战技组（技能组配置机制）；
        // 每次裁决时实时读 self（见 _decide），重初始化改配置可即时生效，这里只做兜底副本。
        this.battleSkills = (this.self.单位战技组 instanceof Array)
            ? this.self.单位战技组
            : HeroUnarmedSkillTable.getBattleSkillCopy();
    }

    /** 战技组实时读取：自机.单位战技组 优先（生命周期每次初始化重建），兜底构造时副本 */
    private function _battleSkillList():Array {
        return (self.单位战技组 instanceof Array) ? self.单位战技组 : battleSkills;
    }

    // ═══════ 主入口（Engaging / Air 每 tick 调用）═══════

    public function tick(frame:Number):Void {
        var st:String = self.状态;

        // ── A. 技能/战技播放中：commit 语义与打断判定 ──
        if (st == "技能" || st == "战技") {
            // 空中优先（升龙拳等跳跃技）：主动跳跃同样会置 浮空=true
            // （PlayerTemplateUnitFixture.as:309），但从起跳到落地 状态 一直保持"技能"，
            // 若只在 C 分支看"空手跳"/浮空，则整段空中都被本分支吃掉 →
            // 踩人/地震/震地 在空中永远不触发，落地后才补地面版。
            // 空中无韧性保护，必须在检测到离地的第一时间改出空中技能组。
            // 已出过空中技能（_currentSkillName 命中空中组）则静默等落地，不反复换招。
            if (self.浮空 == true || self.飞行浮空 == true) {
                // 不可打断技能（铁布衫/觉醒霸体）起手后必须打完，空中也不换招
                if (!_isNoInterruptSkill() && !_isCurrentAirSkill()) _airSkillTick(frame);
                _lastUnitState = st;
                return;
            }

            if (_lastUnitState != "技能" && _lastUnitState != "战技") {
                // 新技能开始
                _skillStartFrame = frame;
            }
            _lastUnitState = st;
            _tryInterrupt(frame);
            return;
        }

        // ── A2. 搓招最小持续保护（必须排在 B 复位之前：B 在 状态!="技能/战技" 时每 tick
        //        都会复位 commit，搓招的"空手攻击"状态正是从这里漏掉的）──
        // 保护成立的唯一前提：状态还在"空手攻击"且未到截止帧。
        // 招式动画先结束（状态回"空手站立"等）或被引擎打断（击倒/浮空/倒地换了状态）
        // → 条件不成立，保护立即失效，交回正常流程，不会出现"保护期挂着发呆"。
        if (_chargeProtectUntilFrame > 0) {
            if (st == "空手攻击" && frame < _chargeProtectUntilFrame
                && _chargeSustainTick(frame, st)) {
                return;
            }
            // 到期 / 状态离开"空手攻击" / 维持判定否决 → 撤保护，落入 B 正常复位
            _chargeProtectUntilFrame = -1;
            _chargeProtectName = null;
        }

        // ── B. 技能已结束：复位 commit 状态 ──
        // 不可打断技能（表内 不可打断:true，如 铁布衫/觉醒霸体）异常早退保护：
        // 起手后极短时间（<30帧）就脱离"技能"状态 = 多半被外部因素打断（受击/击倒/换状态），
        // 效果尚未结算。此时若 单图一次 标记已写，本图将永久失去该技能 →
        // 撤销标记，允许后续重新触发。（正常打完的技能不受影响，仍只放一次）
        // _currentSkillName != null：外部释放的不可打断技能（扭转乾坤）也会命中 _isNoInterruptSkill，
        // 但它不在本脑表里、无 单图一次 标记，写 单位已用永久技能[null] 会脏表 → 排除
        if (_skillStartFrame >= 0 && _currentSkillName != null && _isNoInterruptSkill()
            && frame - _skillStartFrame < 30 && self.单位已用永久技能 != null) {
            // 用 =false 而非 delete：AS2 的 delete 对动态属性行为不稳定，判定口径是 == true
            self.单位已用永久技能[_currentSkillName] = false;
        }
        _skillStartFrame = -1;
        _currentSkillTier = -1;
        _currentSkillName = null;
        _currentSkill = null;
        _lastUnitState = st;
        // 平A标记不在此无条件复位（见 B2）：本分支在 状态!=技能/战技 时每 tick 都走到，
        // 而平A的 状态 是 攻击模式+"攻击"（玩家模板迁移.as:967），不是"技能" →
        // 无条件复位会让平A只持续 1 tick（观感"几乎不平A"）。改由 B2 统一判定。

        // ── B3. 对空裁决：目标浮空（离地 >=100）时优先对空技能组 ──
        // 排在平A窗口之前：目标浮空时地面平A/常规技能根本打不中，对空是唯一有效输出。
        // 细则见 _antiAirTick 注释；全部对空手段不可用 → return false 走正常出招。
        if (_antiAirTick(frame)) {
            tickHeal(frame); // 对空占用本 tick 也不跳过喝药节流轨
            return;
        }

        // ── B2. 平A窗口维持（必须排在 C2/空中/喝药 之前，且必须在 B 之后）──
        // 触发平A后持续回写 动作A 并跳过技能裁决，直到 平A窗口帧（默认30，约1秒）结束。
        // 空手连段靠持续按键推进，只写一次 动作A 只能打出第一下 → 必须逐 tick 续写。
        if (self.单位平A中 == true) {
            if (_sustainNormalAttack(frame)) {
                tickHeal(frame); // 喝药优先级高于平A：窗口内仍照常喝
                return;
            }
            self.单位平A中 = false; // 窗口结束 / 被更高优先级逻辑中断
            _normalAttackStartFrame = -1;
        }

        // ── C2. 击倒：本脑不出招，脱困完全交给原生机制 ──
        // 原生实现（主角-男.xml:1030 被击飞击倒 帧脚本）：_parent.击倒时小跳 为真时，
        // !落地 期间每帧 random(15)：0=小跳、1/2=上下跳、3=前跳（九命猫妖初始化已置 true）。
        // 自研的 _knockdownEscapeTick 小跳/闪现脱困已于 2026-09-08 整体删除（与原生重复且有干扰）。
        // 击倒+浮空 也在此拦下（不再进 C 空中分支）：击倒期出招与原生小跳互相干扰。
        // 状态名可能带后缀（升空函数.as:176 用 indexOf 匹配），故用 indexOf 而非全等。
        if (st != null && st.indexOf("击倒") > -1) return;

        // ── C. 空中（含 空手跳 状态）：只出空中技能组 ──
        // 空手跳（升龙拳等跳起后）空中无韧性保护，必须立刻出招，不等浮空标记/技能动画收尾
        if (self.浮空 == true || self.飞行浮空 == true || st == "空手跳") {
            _airSkillTick(frame);
            return;
        }

        // ── D. 出场保护：N 帧内只移动不攻击 ──
        if (frame - data.createdFrame < p.出场保护帧) return;

        // ── E. 喝药（独立轨，优先级最高——保命先于输出）──
        tickHeal(frame);

        // ── F. 倒地/受硬直等异常状态不出招 ──
        if (self.倒地 == true) return;

        // ── G. 平A保底：射程内先掷骰子，命中即开一个平A窗口（不进技能裁决）──
        // 必须排在技能裁决之前，否则技能几乎每 tick 都能命中候选，平A永远轮不到。
        // 标记 单位平A中：平A 期间禁止 _tryInterrupt 换招（平A 不设 tier，
        // _currentSkillTier 仍是 -1 → 原本会被 tier0 保命技打断，导致平A几乎打不出来）。
        if (data.absdiff_x <= p.攻击判定X && data.absdiff_z <= p.攻击判定Z
            && Math.random() < p.平A保底概率) {
            _startNormalAttack(frame);
            return;
        }

        // ── H. 技能裁决 ──
        var pick:Object = _decide(frame);
        if (pick != null) {
            _release(pick, frame);
            return;
        }

        // ── I. 无候选 → 平A兜底（防输出饥饿）──
        if (data.absdiff_x <= p.攻击判定X && data.absdiff_z <= p.攻击判定Z) {
            _startNormalAttack(frame);
        }
    }

    // ═══════ 平A窗口 ═══════

    /**
     * 开启一个平A窗口：面向目标 + 写 动作A + 置 单位平A中。
     * 之后由 _sustainNormalAttack 逐 tick 续写，直到窗口结束或被更高优先级逻辑中断。
     */
    private function _startNormalAttack(frame:Number):Void {
        _faceTarget();
        self.动作A = true;
        self.单位平A中 = true;
        _normalAttackStartFrame = frame;
    }

    /**
     * 平A窗口维持。返回 true = 本 tick 仍是平A（调用方应 return，跳过技能裁决）。
     *
     * 中断条件（"其他特殊逻辑优先级高于平A"）：
     *   被技能/战技接管、击倒、浮空/飞行浮空、倒地、目标脱离射程、窗口到期；
     *   低血且正受弹道威胁 → 让位给躲避/保命（高血受威胁不中断，否则弹幕图里平A永远打不出来）。
     * 其余情况（常态无异常）一律续写 动作A，保证至少打完一个窗口的连段。
     */
    private function _sustainNormalAttack(frame:Number):Boolean {
        var st:String = self.状态;
        if (st == "技能" || st == "战技") return false;                       // 已被技能接管
        if (st != null && st.indexOf("击倒") > -1) return false;
        if (self.浮空 == true || self.飞行浮空 == true || self.倒地 == true) return false;
        if (frame - data.createdFrame < p.出场保护帧) return false;
        if (_isLowHP() && _isUnderFire(frame)) return false;
        // 目标脱离射程 → 收招，交回技能裁决
        if (!(data.absdiff_x <= p.攻击判定X && data.absdiff_z <= p.攻击判定Z)) return false;

        var win:Number = p.平A窗口帧;
        if (win == undefined || isNaN(win)) win = 30;
        if (_normalAttackStartFrame >= 0 && frame - _normalAttackStartFrame >= win) return false;

        _faceTarget();
        self.动作A = true;
        return true;
    }

    // ═══════ 搓招最小持续保护（燃烧指节/能量喷泉等 _type=="搓招" 且标了 持续帧 的条目）═══════

    /**
     * 搓招保护是否生效中（供 CombatModule/移动层查询）。
     *
     * 为什么移动层必须查：chase()/engage() 只对 状态=="技能"/"战技" 早退停止移动，
     * 搓招的"空手攻击"状态不走那道门 → 模块继续输出移动意图，
     * 跑步切换 状态改变("空手跑") 与 applyBoundaryAwareMovement（行走状态机改写 空手行走）
     * 都会直接掐断"空手攻击"里正在播的搓招元件 —— 这是"配了25帧只撑不到半秒"的主因
     * （燃烧指节射程 50~300，释放时多半在 Chasing 态，第一拍移动就中招）。
     */
    public function isChargeProtected(frame:Number):Boolean {
        return (_chargeProtectUntilFrame > 0
            && frame < _chargeProtectUntilFrame
            && self.状态 == "空手攻击");
    }

    /**
     * 搓招保护期维持。返回 true = 本 tick 仍受保护（调用方收口 return，跳过 B3/B2/G/H）。
     *
     * 背景：搓招经 空手攻击路由 触发，状态是"空手攻击"而非"技能/战技"——
     *   A 分支的高血 commit（打完整套，仅 tier0 可打断）覆盖不到；B 分支每 tick 复位
     *   _currentSkillName → 下一拍 G 平A保底 / H 技能裁决就把它切掉（观感"刚触发就换招"）。
     *
     * 语义对齐技能 commit（高血=打完一整套）：
     *   - 低血 → 不保护（return false 交回正常流程，低血时尽快允许换招/保命）；
     *   - 引擎侧异常（击倒/浮空/倒地）→ 保护立即失效，招式已被打断，续着没意义；
     *   - 受威胁（弹道预警 _bt*）→ 允许 tier0 躲避技（小跳/闪现）打断换招。
     *     注意不放开整个 tier0：震地/地震 也是 tier0（爆发解围输出），若放行它们
     *     会在 CD 好时反复抢拍，保护形同虚设 —— 只放行 类型=="躲避" 的真保命位移。
     *   - 其余情况（血量健康、无异常）→ 静默维持，什么都不写：
     *     搓招由 空手攻击标签跳转 直接播招式元件，不像平A需要逐 tick 续写 动作A。
     *
     * @return true = 继续保护（或已换招、本 tick 收口）；false = 撤保护走正常流程
     */
    private function _chargeSustainTick(frame:Number, st:String):Boolean {
        if (self.倒地 == true) return false;
        if (self.浮空 == true || self.飞行浮空 == true) return false;
        if (st != null && st.indexOf("击倒") > -1) return false;
        if (_isLowHP()) return false;

        // 喝药独立轨照常走（保护不截断保命喝水）
        tickHeal(frame);

        // 受威胁 → 允许 tier0 躲避技打断（保命优先于招式完整度）
        if (_isUnderFire(frame)) {
            var pick:Object = _decide(frame, 0);
            if (pick != null && pick.类型 == "躲避") {
                _chargeProtectUntilFrame = -1;
                _chargeProtectName = null;
                _release(pick, frame);
                return true; // 已换招，本 tick 收口（_release 已预置 _lastUnitState="技能"）
            }
        }
        _lastUnitState = st; // 纯维持：状态跟踪照常，不留在过期的"技能"预置上
        return true;
    }

    // ═══════ 追击期兜底平A（Chasing 调用：射程内近战立即输出）═══════

    public function chaseMeleeTick(frame:Number):Void {
        var st:String = self.状态;
        if (st == "技能" || st == "战技") return;
        // 搓招最小持续保护（续32）：Chasing 侧同样不得在搓招动画期注入平A输入
        // （写 动作A 会打断"空手攻击"状态里正在播的搓招元件）。保护期直接静默。
        if (st == "空手攻击" && _chargeProtectUntilFrame > 0
            && frame < _chargeProtectUntilFrame && !_isLowHP()) return;
        if (self.射击中 == true) return;
        if (self.浮空 == true || self.飞行浮空 == true) return;
        if (self.倒地 == true || st == "击倒") return;
        if (frame - data.createdFrame < p.出场保护帧) return;

        // 平A窗口维持（本函数是 Chasing 侧的平A入口，窗口内必须续写 动作A）
        if (self.单位平A中 == true) {
            if (_sustainNormalAttack(frame)) return;
            self.单位平A中 = false;
            _normalAttackStartFrame = -1;
            return;
        }

        if (data.absdiff_x <= p.攻击判定X && data.absdiff_z <= p.攻击判定Z
            && Math.random() < p.平A保底概率) {
            _startNormalAttack(frame);
        }
    }

    // ═══════ 喝药（独立轨，Combat/Evade 均 tick）═══════
    public function tickHeal(frame:Number):Void {
        var maxHP:Number = self.hp满血值;
        if (!(maxHP > 0)) return;
        var ratio:Number = self.hp / maxHP;

        var wantHeal:Boolean = false;
        if (ratio < p.喝药必喝线) {
            wantHeal = true;                              // <40% 必喝
        } else if (ratio < p.喝药想喝线) {
            var prob:Number = (p.喝药想喝线 - ratio) / (p.喝药想喝线 - p.喝药必喝线);
            wantHeal = (Math.random() < prob);            // 越低越容易喝
        }
        if (!wantHeal) return;
        if (frame - _lastHealFrame < _healMinGapFrames) return; // 防连喝

        // 血包数量上限（与佣兵轨同规则：初始化 血包数量=3，喝一扣一，扣完不喝）
        if (!(self.血包数量 > 0)) return;

        // 技能播放中不喝（血包轨独立于 body 轨，但观感上避开技能动画）
        var st:String = self.状态;
        if (st == "技能" || st == "战技") return;

        // 佣兵使用血包读 血包恢复比例（undefined 时兜底 30%，避免 NaN 恢复量）
        if (self.血包恢复比例 == undefined) self.血包恢复比例 = 30;
        _lastHealFrame = frame;
        self.血包数量--; // 与 佣兵ai.as:90 同步：先扣再喝
        AIEnvironment.useHealPack(self._name);
    }

    // ═══════ 打断判定（技能播放中）═══════

    private function _tryInterrupt(frame:Number):Void {
        if (_skillStartFrame < 0) return;

        // 平A 期间禁止换招：平A 不经过 _release，_currentSkillTier 仍是 -1，
        // 下方 `_currentSkillTier < 0` 分支会让任意 tier0 保命技（小跳/闪现/震地）立刻顶掉
        // 刚起步的平A —— 这正是"平A 频率远低于技能"的根因。平A 收招由 tick B 分支解除。
        if (self.单位平A中 == true) return;

        // 不可打断技能（表内 不可打断:true，如 铁布衫/觉醒霸体）：起手后必须完整打完，
        // 任何情况下都不换招。这类技能的效果在动画尾部结算，中途被打断则前功尽弃，
        // 而 单图一次 标记在释放瞬间已写 → 被打断就等于本图永久失去该技能。
        if (_isNoInterruptSkill()) return;

        var maxHP:Number = self.hp满血值;
        var hpRatio:Number = (maxHP > 0) ? self.hp / maxHP : 1;
        var lowHP:Boolean = hpRatio < p.低血阈值;

        var canInterrupt:Boolean = false;
        var minTier:Number = 0; // 只允许 优先级0（保命/解围/躲避）打断

        if (lowHP) {
            // 低血：低血commitFrames 后允许被"更高优先级"打断（层号更小）
            if (frame - _skillStartFrame >= p.低血commitFrames) {
                canInterrupt = true;
                minTier = _currentSkillTier >= 0 ? _currentSkillTier : 1;
            }
        } else {
            // 高血：打完一整套，仅优先级0保命可打断
            canInterrupt = true;
            minTier = 0;
        }
        if (!canInterrupt) return;

        // 只在存在"可打断层"候选时才换招（避免白浪费当前技能）
        var pick:Object = _decide(frame, minTier);
        if (pick != null && (_currentSkillTier < 0 || pick.优先级 < _currentSkillTier
            || (lowHP && pick.优先级 <= _currentSkillTier))) {
            _release(pick, frame);
        }
    }

    // ═══════ 候选构建 + 分层裁决 ═══════

    /**
     * @param frame      当前帧
     * @param maxTier    只收集层号 <= maxTier 的候选（undefined = 全部）
     * @return 候选条目 或 null
     */
    private function _decide(frame:Number, maxTier:Number):Object {
        var lowHP:Boolean = _isLowHP();
        var underFire:Boolean = _isUnderFire(frame);
        var zLimit:Number = p.攻击判定Z;
        // 位移/远程/躲避类技能用放宽的 Z 窗口（参数 位移技能Z放宽）：
        //   贴身但 Z 差 25~60 时，平A与贴身技能都够不着、纯移动又追不上走位 → 干追不出招（"只移动不攻击"）。
        //   放宽后这类技能能在 Z 未对齐时突进/远程出手。平A与贴身技能仍严格用 攻击判定Z。
        var zLoose:Number = p.位移技能Z放宽;
        if (!(zLoose > zLimit)) zLoose = zLimit;

        // 收集：地面技能 + 战技
        var bestTier:Number = 99;
        var pool:Array = [];
        var lists:Array = [self.已学技能表, _battleSkillList()];
        for (var li:Number = 0; li < lists.length; li++) {
            var skills:Array = lists[li];
            if (skills == null) continue;
            for (var i:Number = 0; i < skills.length; i++) {
                var sk:Object = skills[i];
                if (sk == null) continue;

                // 距离命中
                if (data.absdiff_x < sk.距离min || data.absdiff_x > sk.距离max) continue;
                // 忽略Z轴（增益类 / 兽王崩拳）：Z 轴距离任意，只看 X 轴距离
                if (sk.忽略Z轴 != true
                    && data.absdiff_z > (_isMobileSkill(sk) ? zLoose : zLimit)) continue;

                // 贴地限定（升龙拳等跳起技）：未落地不进候选，见 _isGrounded 说明
                if (sk.贴地限定 == true && !_isGrounded()) continue;

                // 位移使用间隔锁：小跳/闪现刚放过，常态裁决与打断换招都不再选（击倒脱困不走本函数，不受限）
                if (getTimer() < _dodgeLockUntil
                    && (sk.技能名 == "小跳" || sk.技能名 == "闪现")) continue;

                // CD
                if (!isNaN(sk.上次使用时间)
                    && (getTimer() - sk.上次使用时间 <= sk.冷却 * 1000)) continue;

                // 空中限定（踩人）不进地面候选
                if (sk.空中限定 == true) continue;

                // 特殊规则过滤
                if (!_passSpecialRules(sk)) continue;

                // MP 门槛
                if (sk.消耗 > 0 && self.mp < sk.消耗) continue;

                // 搓招前置：被动技能未解锁/未启用/等级不足/MP 比例不够 → 不进候选
                if (!_passiveReady(sk)) continue;

                // 层号修正：躲避类受威胁时提到 0 层，否则降为 2 层（前跳拉近）
                var tier:Number = sk.优先级;
                if (sk.类型 == "躲避" || sk.功能 == "躲避") {
                    tier = underFire ? 0 : 2;
                }
                // 保命/解围在残血时更积极（原层号已是 0）
                if (maxTier != undefined && tier > maxTier) continue;

                if (tier < bestTier) { bestTier = tier; pool = [sk]; }
                else if (tier == bestTier) { pool.push(sk); }
            }
        }

        if (pool.length == 0) return null;
        return pool[Math.floor(Math.random() * pool.length)]; // 同层随机
    }

    // ═══════ 特殊规则（5.7）═══════

    private function _passSpecialRules(sk:Object):Boolean {
        // 霸体不重复：已有刚体/刚体标签 → 不再触发霸体类
        if (sk.功能 == "解围霸体" || sk.功能 == "霸体") {
            if (self.刚体 == true) return false;
            if (self.man != null && self.man.刚体标签 != null && self.man.刚体标签 !== false) return false;
        }
        // 单图永久：觉醒霸体/兴奋剂/铁布衫/聚气/能量盾 —— 本图释放过一次即不再触发
        // （能量盾读不到护盾状态，按维护者拍板退化为本图一次）
        if (sk.单图一次 == true) {
            if (self.单位已用永久技能 != null && self.单位已用永久技能[sk.技能名] == true) return false;
        }
        return true;
    }

    /**
     * 搓招前置校验（复刻 单位函数_雾人_空手搓招指令.as 里玩家侧的解锁条件）。
     * 玩家靠按键序列触发并由这些函数校验，AI 不走输入层，直接调 空手攻击标签跳转，
     * 因此必须在此自行把关，否则会放出没解锁的招式。
     * 无 被动 字段的普通技能一律放行。
     */
    private function _passiveReady(sk:Object):Boolean {
        if (sk.被动 == undefined || sk.被动 == null) return true;

        var ps:Object = (self.被动技能 != null) ? self.被动技能[sk.被动] : null;
        if (ps == null) return false;          // 没这个被动技能 = 未解锁
        if (ps.启用 != true) return false;      // 未启用（与玩家侧 技能.启用 同口径）
        if (sk.被动等级 > 0 && !(ps.等级 >= sk.被动等级)) return false;

        // MP 比例门槛（能量喷泉：mp ≥ mp满血值 × 10%）
        if (sk.MP比例 > 0) {
            var full:Number = self.mp满血值;
            if (full > 0 && self.mp < full * sk.MP比例) return false;
        }
        return true;
    }

    // ═══════ 释放 ═══════

    /**
     * 面向目标（左右朝向校正）——释放技能 / 平A 前调用。
     * 单位朝向权威字段是 方向（"左"/"右"）+ _xscale，攻击判定与技能位移都按它生成；
     * 朝向背对目标时出招会打空（观感即"乱放技能/打不到人"）。
     *
     * 走权威函数 自机.方向改变(新方向)（主角函数，含 _xscale 与文字信息翻转）；
     * 该函数在 锁定方向 == true 或 飞行浮空 == true 时内部直接 return，
     * 这两种情况我们同样跳过（强行改会破坏锁定语义/浮空表现）。
     *
     * @return true = 本帧发生了转向（调用方据此决定是否推迟释放）
     */
    private function _faceTarget():Boolean {
        var t:MovieClip = data.target;
        if (t == null || t._x == undefined || isNaN(t._x)) return false;
        if (self._x == undefined || isNaN(self._x)) return false;

        var want:String = (t._x >= self._x) ? "右" : "左";
        if (self.方向 == want) return false;              // 已经面向目标
        if (self.锁定方向 == true) return false;           // 锁定方向：方向改变 内部会拒绝
        if (self.飞行浮空 == true) return false;           // 浮空：方向改变 内部会拒绝

        if (typeof self.方向改变 == "function") {
            self.方向改变(want);
        } else {
            // 兜底：直接改 方向 + _xscale（保持与 方向改变 一致的表现）
            self.方向 = want;
            var sx:Number = (self.myxscale != undefined && !isNaN(self.myxscale)) ? self.myxscale : Math.abs(self._xscale);
            if (!(sx > 0)) sx = 100;
            self._xscale = (want == "右") ? sx : -sx;
            if (self.新版人物文字信息 != null) self.新版人物文字信息._xscale = (want == "右") ? 100 : -100;
        }

        if (AIEnvironment.isAIDebug()) {
            AIEnvironment.log("[HU-BRAIN] " + self.名字 + " 转向 " + want);
        }
        return true;
    }

    private function _release(sk:Object, frame:Number):Void {
        // 释放前先面向目标（背对时出招会打空）
        _faceTarget();

        // 空中出招时补齐 技能浮空 旗标（修复"屏幕边缘卡死+反复震地"）：
        //   震地/地震/觉醒震地 容器第一帧以 `技能浮空 == true` 决定是否 启用快速下落(重力20)；
        //   而上一技能结束时容器 onUnload 会清掉该旗标（人仍在天上）→ 不启用 fastFall。
        //   人确实在浮空物理下，置 true 与物理语义一致；fastFall 落地时会自动清回 false。
        //   注意：不动 垂直速度 —— 上升/下降速度一律交还给空中控制器物理积分。
        if (self.浮空 == true && self.技能浮空 != true) {
            self.技能浮空 = true;
        }

        // 小跳/闪现方向控制（技能动画不设输入时默认后跳，必须显式给方向输入）。
        //   优先级：① 贴边覆盖（距上缘<80px→向下，距下缘<80px→向上，仅贴边时生效）
        //           ② 受威胁（弹道预警=高危）→ 一律上下跳/闪（前跳=朝射手撞子弹）
        //           ③ 贴身 → 上下跳（随机上/下）
        //           ④ 未贴身（接近中）→ 前跳拉近。
        //   （击倒脱困不走本函数：击倒期 C2 守卫直接 return，脱困由原生 击倒时小跳 处理。）
        if (sk.技能名 == "小跳" || sk.技能名 == "闪现") {
            var up:Boolean = false;
            var down:Boolean = false;
            var lf:Boolean = false;
            var rt:Boolean = false;
            // ① 贴边覆盖：80 与 MovementResolver Phase3 MARGIN 同口径，bnd* 由 data.updateSelf 维护
            var nearTop:Boolean = (!isNaN(data.bndUpDist) && data.bndUpDist < 80);
            var nearBot:Boolean = (!isNaN(data.bndDownDist) && data.bndDownDist < 80);
            if (nearTop) {
                down = true;
            } else if (nearBot) {
                up = true;
            } else if (_isUnderFire(frame)) {
                // ② 受威胁：上下随机
                if (Math.random() < 0.5) up = true;
                else down = true;
            } else if (data.absdiff_x <= p.攻击判定X) {
                // ③ 贴身：只能上下跳
                if (Math.random() < 0.5) up = true;
                else down = true;
            } else {
                // ④ 接近中：前跳拉近（diff_x<0 = 目标在左 → 左行）
                if (data.diff_x < 0) lf = true;
                else rt = true;
            }
            // 方向锁：MovementResolver.clearInput / MoveHelper.alignTick 每帧都会清这些旗标，
            // 只设一次会被清掉退回默认后跳 → 写锁，由 syncLockedInput 在窗口内持续回写
            var lockFrames:Number = p.跳跃方向锁帧;
            if (lockFrames == undefined || isNaN(lockFrames)) lockFrames = 15;
            self.单位方向锁 = {上行: up, 下行: down, 左行: lf, 右行: rt,
                截止帧: AIEnvironment.getFrame() + lockFrames};
            self.上行 = up;
            self.下行 = down;
            self.左行 = lf;
            self.右行 = rt;
        }

        // 写 CD（替代 ActionArbiter）
        sk.上次使用时间 = getTimer();

        // 位移使用间隔锁：小跳/闪现 释放后 位移使用间隔 秒内常态裁决/打断换招不再选它们
        // （击倒脱困不走 _decide，不受此锁影响，保命优先）
        if (sk.技能名 == "小跳" || sk.技能名 == "闪现") {
            var 间隔:Number = p.位移使用间隔;
            if (!(间隔 > 0)) 间隔 = 3;
            _dodgeLockUntil = getTimer() + 间隔 * 1000;
        }

        _applySkillLevel(sk);

        if (sk._type == "battleSkill") {
            if (sk.技能名 == "咒针") {
                // 咒针：按 贯空天盖战技 既有模式 —— 普通咒针子弹属性 → 路由 "手部发射"
                self.手部发射子弹属性 = {
                    子弹种类: "普通咒针",
                    声音: "speed07.wav",
                    子弹威力: 25 * self.内力,
                    子弹速度: 35,
                    Z轴攻击范围: 30,
                    击倒率: 5,
                    伤害类型: "破击",
                    魔法伤害属性: "人类",
                    毒: 1000,
                    霰弹值: 3,
                    子弹散射度: 5
                };
                _root.战技路由.战技标签跳转_旧(self, "手部发射");
            } else {
                // 飞身踢：已有 空手 实现（单位函数_雾人_aka_fs_主动战技.as:43）
                _root.战技路由.战技标签跳转_旧(self, sk.技能名);
            }
        } else if (sk._type == "搓招") {
            // 搓招组：AI 无输入序列，直接走搓招的执行终点 —— 空手攻击标签跳转
            // （与 单位函数_雾人_空手搓招指令.as 里各 使用XXX() 的落点完全一致，
            //   跳的是同一批招式元件；解锁条件已由 _passiveReady 复刻校验）
            _root.空手攻击路由.空手攻击标签跳转(self, sk.技能名);
        } else {
            AIEnvironment.routeSkill(self, sk.技能名);
        }

        // 单图一次标记
        if (sk.单图一次 == true) {
            if (self.单位已用永久技能 == null) self.单位已用永久技能 = {};
            self.单位已用永久技能[sk.技能名] = true;
        }

        // commit 状态（本 tick 内 状态 改变尚未生效，直接预置）
        _skillStartFrame = frame;
        _currentSkillTier = (sk.类型 == "躲避" && !_isUnderFire(frame)) ? 2 : sk.优先级;
        _currentSkillName = sk.技能名;
        _currentSkill = sk;
        _lastUnitState = "技能";

        // 搓招最小持续保护（续32）：仅表内标了 持续帧 的搓招条目（燃烧指节/能量喷泉）。
        // 搓招走"空手攻击"状态，_skillStartFrame/_currentSkill* 这套 commit 会被 B 分支
        // 每 tick 复位（A 分支只认 技能/战技），所以另立 _chargeProtectUntilFrame 窗口，
        // 由 tick A2 + _chargeSustainTick 维持；动画先结束（状态离开"空手攻击"）自动失效。
        // 未标 持续帧 的搓招（连环踢/波动拳/诛杀步）行为不变，要跟进只需在表里补字段。
        if (sk._type == "搓招" && sk.持续帧 > 0) {
            _chargeProtectUntilFrame = frame + Number(sk.持续帧);
            _chargeProtectName = sk.技能名;
        }

        if (AIEnvironment.isAIDebug()) {
            AIEnvironment.log("[HU-BRAIN] " + self.名字 + " 释放 " + sk.技能名
                + " tier=" + _currentSkillTier
                + " dist=" + Math.round(data.absdiff_x));
        }
    }

    // ═══════ 空中技能组（5.7：只从 震地/地震/踩人 随机取，全CD则平A）═══════

    /** 当前技能是否已是空中组成员（用于避免空中反复换招） */
    private function _isCurrentAirSkill():Boolean {
        if (_currentSkillName == null) return false;
        var airNames:Array = (self.单位空中技能组 instanceof Array)
            ? self.单位空中技能组
            : HeroUnarmedSkillTable.getAirSkillCopy();
        for (var i:Number = 0; i < airNames.length; i++) {
            if (airNames[i] == _currentSkillName) return true;
        }
        return false;
    }

    private function _airSkillTick(frame:Number):Void {
        // 空中技能沿用地面表条目做 CD/MP 判定（踩人为空中限定，此处允许）
        var airNames:Array = (self.单位空中技能组 instanceof Array)
            ? self.单位空中技能组
            : HeroUnarmedSkillTable.getAirSkillCopy();
        var pool:Array = [];
        for (var i:Number = 0; i < airNames.length; i++) {
            var sk:Object = _findGroundSkill(airNames[i]);
            if (sk == null) continue;
            if (!isNaN(sk.上次使用时间)
                && (getTimer() - sk.上次使用时间 <= sk.冷却 * 1000)) continue;
            if (sk.消耗 > 0 && self.mp < sk.消耗) continue;
            pool.push(sk);
        }
        var pick:Object = null;
        if (pool.length > 0) {
            pick = pool[Math.floor(Math.random() * pool.length)];
        } else {
            // 保底：三个空中技能全 CD 也强制触发震地（忽略 CD，防止空中无韧性干等被击倒）；
            // 仅 MP 不足才退化平A，避免空放失败
            pick = _findGroundSkill("震地");
            if (pick != null && pick.消耗 > 0 && self.mp < pick.消耗) pick = null;
            if (pick == null) {
                if (data.absdiff_x <= p.攻击判定X) self.动作A = true;
                return;
            }
        }
        // 空中释放：允许踩人（跳过 地面 的 空中限定 过滤）
        // 浮空出招必须补 技能浮空 旗标（强制震地不走 _release，此前漏了这步）：
        //   缺旗标 → 震地容器第一帧判定不成立 → 不启用 fastFall；而 状态=="技能" 又会让
        //   空中控制器删掉 naturalFall 源（空中控制器._tick 状态切换让出）→ **所有物理源清空、
        //   单位悬停冻结**，且强制兜底每 tick 重放震地、状态恒为"技能" → naturalFall 永远
        //   回不来 → "卡在屏幕边缘无限震地"，直到 MP 耗尽退化平A（状态离开技能）才恢复下落。
        //   补旗标 → 容器启用 fastFall(重力20) 快速下落，落地自动清旗标并 play() 砸地。
        if (self.浮空 == true && self.技能浮空 != true) {
            self.技能浮空 = true;
        }
        pick.上次使用时间 = getTimer();
        _applySkillLevel(pick);
        AIEnvironment.routeSkill(self, pick.技能名);
        _skillStartFrame = frame;
        _currentSkillTier = 1;
        _currentSkillName = pick.技能名;
        _currentSkill = pick;
        _lastUnitState = "技能";
    }

    /**
     * 当前技能是否"不可打断"（技能表条目 不可打断:true，如 铁布衫/觉醒霸体）。
     * 起手后必须完整打完：效果在动画尾部结算，中途换招 = 前功尽弃且单图一次标记已写。
     */
    /**
     * 外部释放的"不可打断"技能名（本脑技能表里没有，不参与裁决，
     * 由装备/其他系统直接走 技能路由 触发，例如 九命猫妖周期 在 hp<=1 时
     * _root.技能路由.技能标签跳转_旧(自机,"扭转乾坤") 触发复活）。
     * 这类技能进 状态=="技能" 时 _currentSkill 为 null（不是本脑释放的），
     * 只能按 单位.技能名 判定（技能路由.as:29 `unit.技能名 = skillName`）。
     * 必须让它自然收招：中途被打断会丢掉复活/护盾的尾部结算。
     */
    private static var 外部不可打断技能:Array = ["扭转乾坤"];

    // 对空裁决（_antiAirTick）的 Z 轴窗口：弹幕类（气动波/咒针/手部发射）走这个，
    // 贴身对空（升龙拳）走 攻击判定Z。取值 = 子弹自带 Z轴攻击范围（三者均为 30）：
    // 子弹 Z 在发射时固定为射手 Z（BulletInitializer: Obj.Z轴坐标 = Obj.shootZ），
    // 且 ZY比例 未设 → 飞行不更新 Z → 向上偏角只改屏幕 _y，不产生 Z 覆盖。
    // ★不进装备参数：这是引擎子弹的固有属性，不是可调的 AI 行为参数；
    //   想改就改这里（改完对所有空手 AI 生效）。
    private static var 对空Z容差:Number = 30;

    private function _isNoInterruptSkill():Boolean {
        if (_currentSkill != null && _currentSkill.不可打断 == true) return true;
        // 外部释放的技能：按 单位.技能名 判定（本脑未参与，无表条目可读）。
        // 只在 状态=="技能"/"战技" 时生效：技能名 是"最近一次路由的技能"，技能本身结束后
        // 不会清空；限定状态可避免 B 分支（状态已离开技能时也会走到这里）误判。
        // （搓招/平A 走 空手攻击路由，状态是"空手攻击"且只写 空手攻击名，不会污染 技能名）
        var st:String = self.状态;
        if (st != "技能" && st != "战技") return false;
        var nm:String = self.技能名;
        if (nm == null || nm == undefined || nm == "") return false;
        for (var i:Number = 0; i < 外部不可打断技能.length; i++) {
            if (nm == 外部不可打断技能[i]) return true;
        }
        return false;
    }

    // ═══════ 对空裁决（tick B3 调用）═══════

    /**
     * 对空裁决：目标浮空（离地 >= 100）时优先使用对空技能组。
     *
     * 对空组三技能：
     *   气动波 / 咒针（弹幕）—— 释放前预写 上行 方向锁，引擎发射函数
     *     （气动波攻击 / 手部发射攻击，单位函数_lsy_主角技能.as）读 _parent.上行
     *     置 子弹.角度偏移=-30°，FLA 侧零改动；咒针属性对象无 角度偏移 键，
     *     不会覆盖引擎先设好的偏移。
     *   升龙拳 —— 贴身跳击，本就向上。
     *
     * ★Z 轴前提：目标必须在 Z 轴范围内才走对空（Z 差过大打不中，空放纯浪费 CD/MP）。
     *   Z 轴 = 地面纵轴（Z轴坐标），与索敌/交战用的是同一根轴；子弹的"向上偏角"只改
     *   屏幕 _y（视觉高度），子弹 Z 固定为射手 Z（ZY比例 未设 → 飞行不更新 Z），
     *   因此弹幕对空**不会**因为向上打就覆盖更大 Z 差 —— 与近战同一判定性质。
     *   口径：弹幕/位移补位用 对空Z容差（static 常量 30 = 气动波/咒针/手部发射子弹的
     *   Z轴攻击范围）；升龙拳（贴身技）用 攻击判定Z（默认20）。超出 对空Z容差 不走对空。
     *
     * 主逻辑（按序短路，前提：目标离地 >=100 且 Z 差在窗口内）：
     *   1. 弹幕可用（CD/MP 过关）且 dist 在条目射程内 → 向上放弹幕（两者都可用随机选一）；
     *   2. 升龙拳可用且 dist 在其射程内（贴身）→ 升龙拳；
     *   3. 补位 a：贴身 + 升龙拳不可用 + 弹幕可用（暂不在射程）→ 后闪拉开，
     *      下一拍裁决距离进入弹幕射程自然接上（涌现式连招，无需显式序列状态）；
     *   4. 补位 b：弹幕全不可用 + 升龙拳可用 + dist 80~400 → 300~400 前闪 /
     *      200~300 诛杀步，下一拍贴身接升龙拳。
     * 全部对空手段不可用（含 Z 差超出窗口）→ return false，走正常出招。
     *
     * 防反复：闪现释放走 _release 写 位移使用间隔锁，本裁决位移前统一检查该锁；
     * 诛杀步/弹幕/升龙拳各有自身 CD。
     *
     * @return true = 本 tick 已释放对空/补位技能（调用方收口 return）
     */
    private function _antiAirTick(frame:Number):Boolean {
        var t:MovieClip = data.target;
        if (t == null || isNaN(t._x) || !(t.hp > 0)) return false;
        if (_targetAirHeight(t) < 100) return false;

        // ★Z 轴门槛：对空手段（弹幕/升龙拳/位移补位）都要求目标在 Z 轴范围内才走对空，
        //   Z 差过大时打不中，空放纯浪费 CD/MP —— 直接 return false 走常规出招（继续走位对齐）。
        //   口径（2026-09-08 核对引擎侧，向上偏角不带 Z）：
        //     · 子弹 Z：BulletInitializer 写 Obj.Z轴坐标 = Obj.shootZ（射手 Z），
        //       且 ZY比例 默认 undefined → LinearBulletMovement 走 updateWithoutZCoordinate，
        //       飞行中只更新 _x/_y → 子弹 Z 全程固定；角度偏移(-30°)只改屏幕 _y（视觉高度），
        //       不产生任何 Z 位移 → 弹幕对空**不会**因为向上打就覆盖更大的 Z 差。
        //     · 弹幕 Z 容差 = 子弹自带 Z轴攻击范围（气动波/咒针/手部发射均为 30）
        //       → 直接用常量 对空Z容差（类级 static，不额外占装备参数位）。
        //       绝不使用 位移技能Z放宽(60)：那是给"Z 未对齐时先突进/远程起手"用的，
        //       对空弹幕按 Z 差判定，与近战同一性质。
        //     · 升龙拳（贴身技）用 攻击判定Z（默认20）。
        var zL:Number = Number(p.攻击判定Z);
        if (!(zL > 0)) zL = 20;
        var zShot:Number = 对空Z容差;
        if (zShot < zL) zShot = zL;
        var adz:Number = data.absdiff_z;
        if (isNaN(adz) || adz > zShot) return false;

        var dist:Number = data.absdiff_x;
        var dragon:Object = _findSkillAny("升龙拳");
        var wave:Object = _findSkillAny("气动波");
        var needle:Object = _findSkillAny("咒针");
        var dragonReady:Boolean = _skillReady(dragon);
        var waveReady:Boolean = _skillReady(wave);
        var needleReady:Boolean = _skillReady(needle);
        // 弹幕：Z 用子弹自身的 Z 射程（向上偏角不带 Z 位移，容差与近战同性质）
        var waveOK:Boolean = waveReady && _inXRange(wave, dist) && adz <= zShot;
        var needleOK:Boolean = needleReady && _inXRange(needle, dist) && adz <= zShot;

        // 1. 弹幕对空（优先）：距离合适就向上打
        if (waveOK || needleOK) {
            var sk:Object;
            if (waveOK && needleOK) sk = (Math.random() < 0.5) ? wave : needle;
            else sk = waveOK ? wave : needle;
            _lockAimUp(frame);
            _release(sk, frame);
            return true;
        }

        // 2. 贴身：升龙拳可用 → 升龙拳（贴身技：Z 用严格窗口）
        if (dragonReady && _inXRange(dragon, dist) && adz <= zL) {
            _release(dragon, frame);
            return true;
        }

        // 位移补位公共前提：不在位移使用间隔锁内（防"刚闪完又闪"循环）
        var dodgeLocked:Boolean = (_dodgeLockUntil > getTimer());

        // 3. 补位 a：贴身 + 升龙拳不可用 + 弹幕可用 → 后闪拉开接弹幕
        var closeX:Number = Number(p.攻击判定X);
        if (!(closeX > 0)) closeX = 80;
        if (dist <= closeX && !dragonReady && (waveReady || needleReady) && !dodgeLocked) {
            var blink:Object = _findSkillAny("闪现");
            if (_skillReady(blink)) {
                _release(blink, frame);
                _lockAimBackward(frame); // 覆盖 _release 的闪现默认方向（贴身=上下跳）为后闪
                return true;
            }
        }

        // 4. 补位 b：弹幕全不可用 + 升龙拳可用 + 中距（升龙拳射程外~400）→ 突进接升龙拳
        var dragonMax:Number = (dragon != null) ? Number(dragon.距离max) : 80;
        if (isNaN(dragonMax)) dragonMax = 80;
        if (!waveReady && !needleReady && dragonReady && dist > dragonMax && dist <= 400 && !dodgeLocked) {
            if (dist >= 300) {
                var blink2:Object = _findSkillAny("闪现");
                if (_skillReady(blink2)) {
                    _release(blink2, frame);
                    _lockAimForward(frame); // 前闪（300~400，闪现位移最远）
                    return true;
                }
            } else if (dist >= 200) {
                var step:Object = _findSkillAny("诛杀步");
                if (_skillReady(step) && _inXRange(step, dist)) {
                    _release(step, frame);
                    return true;
                }
            }
        }

        return false;
    }

    /** 目标离地高度：高度 = Z轴坐标 - _y，浮空高度 存在则叠加（用户口径） */
    private function _targetAirHeight(t:MovieClip):Number {
        var base:Number = (t.Z轴坐标 == undefined || isNaN(t.Z轴坐标)) ? t._y : t.Z轴坐标;
        var h:Number = base - t._y;
        if (t.浮空高度 != undefined && !isNaN(t.浮空高度) && t.浮空高度 > 0) h += t.浮空高度;
        return h;
    }

    /** 对空用可用性检查：CD + MP（不查距离） */
    private function _skillReady(sk:Object):Boolean {
        if (sk == null) return false;
        if (!isNaN(sk.上次使用时间)
            && (getTimer() - sk.上次使用时间 <= sk.冷却 * 1000)) return false;
        if (sk.消耗 > 0 && self.mp < sk.消耗) return false;
        return true;
    }

    /** 对空用射程检查：dist 是否在条目 距离min/max 内 */
    private function _inXRange(sk:Object, dist:Number):Boolean {
        if (sk == null) return false;
        var mn:Number = Number(sk.距离min);
        var mx:Number = Number(sk.距离max);
        if (isNaN(mn)) mn = 0;
        if (isNaN(mx)) return false;
        return dist >= mn && dist <= mx;
    }

    /** 已学技能表 + 战技组 双表查找（咒针在战技组，不在已学技能表） */
    private function _findSkillAny(名:String):Object {
        var sk:Object = _findGroundSkill(名);
        if (sk != null) return sk;
        var list:Array = _battleSkillList();
        if (list == null) return null;
        for (var i:Number = 0; i < list.length; i++) {
            if (list[i] != null && list[i].技能名 == 名) return list[i];
        }
        return null;
    }

    /** 方向锁：向上瞄准（弹幕 角度偏移=-30°）。窗口 30 帧覆盖弹幕动画的发射帧 */
    private function _lockAimUp(frame:Number):Void {
        self.单位方向锁 = {上行: true, 下行: false, 左行: false, 右行: false, 截止帧: frame + 30};
        self.上行 = true;
        self.下行 = false;
        self.左行 = false;
        self.右行 = false;
        self.动作A = false;
    }

    /** 方向锁：后闪（远离目标） */
    private function _lockAimBackward(frame:Number):Void {
        var lf:Boolean = (data.diff_x < 0) ? false : true; // 目标在左 → 向右闪
        self.单位方向锁 = {上行: false, 下行: false, 左行: lf, 右行: !lf, 截止帧: frame + 15};
        self.上行 = false;
        self.下行 = false;
        self.左行 = lf;
        self.右行 = !lf;
    }

    /** 方向锁：前闪（朝目标） */
    private function _lockAimForward(frame:Number):Void {
        var lf:Boolean = (data.diff_x < 0) ? true : false; // 目标在左 → 向左闪
        self.单位方向锁 = {上行: false, 下行: false, 左行: lf, 右行: !lf, 截止帧: frame + 15};
        self.上行 = false;
        self.下行 = false;
        self.左行 = lf;
        self.右行 = !lf;
    }

    private function _findGroundSkill(名:String):Object {
        var skills:Array = self.已学技能表;
        if (skills == null) return null;
        for (var i:Number = 0; i < skills.length; i++) {
            if (skills[i] != null && skills[i].技能名 == 名) return skills[i];
        }
        return null;
    }

    // ═══════ 辅助 ═══════

    /** 释放时技能等级：条目配置了 释放等级(1~10) 则锁定，否则按单位等级推导（与九命猫妖周期同口径） */
    private function _applySkillLevel(sk:Object):Void {
        if (sk.释放等级 > 0) {
            self.技能等级 = Math.min(Number(sk.释放等级), 10);
        } else {
            self.技能等级 = Math.min(Math.ceil(self.等级 / 10), 10);
        }
        if (!(self.技能等级 > 0)) self.技能等级 = 1;
    }

    /** 位移/远程/躲避类技能判定（放宽 Z 出招窗口的对象）：类型==躲避，或 功能 含"位移"/"远程" */
    private function _isMobileSkill(sk:Object):Boolean {
        if (sk.类型 == "躲避") return true;
        var f:String = String(sk.功能);
        if (f == "undefined" || f == "null" || f == "") return false;
        return (f.indexOf("位移") >= 0 || f.indexOf("远程") >= 0);
    }

    // ═══════ 贴地判定（跳起技释放门槛）════════

    /**
     * 是否贴地——判据与 升龙拳浮空初始化（单位函数_lsy_主角技能.as:1742）完全同口径：
     *     高度 = Z轴坐标 - _y；_y >= Z轴坐标 - 0.5 视作贴地。
     * 为什么要 0.5 容差：Flash 的 _y 是浮点，贴地瞬间常停在 z-0.5 到 z 的半开带内（时序调整后
     * 原本依赖"恰好相等"的隐性行为会失效），没有容差会把刚落地判成空中、把起跳第一帧判成地面。
     * 只看高度不读 浮空/技能浮空 标记：地面触发时这些标记可能残留 true（升龙拳初始化里
     * 也是据此强制复位的），信标记会误判。
     * @return Boolean 贴地（可安全起跳）
     */
    private function _isGrounded():Boolean {
        var z:Number = (!isNaN(self.Z轴坐标)) ? self.Z轴坐标 : self._y;
        if (isNaN(z) || isNaN(self._y)) return true; // 数据缺失：保守放行，交回原行为
        return (self._y >= z - 0.5);
    }

    private function _isLowHP():Boolean {
        var maxHP:Number = self.hp满血值;
        return (maxHP > 0) ? (self.hp / maxHP < p.低血阈值) : false;
    }

    private function _isUnderFire(frame:Number):Boolean {
        // 弹道威胁信号（BulletThreatScanProcessor 写入 self._bt*）
        var btAge:Number = frame - self._btFrame;
        return (btAge >= 0 && btAge <= 2 && self._btCount > 0);
    }
}
