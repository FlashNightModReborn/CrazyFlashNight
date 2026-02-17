import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * UtilityEvaluator — 人格驱动 Utility AI 评分与评估服务
 *
 * 职责（Phase E 清理后）：
 *   1. 评分服务：scoreDimension() + 5 维度函数 + boltzmannSelect()
 *   2. 武器评估：evaluateWeaponMode() + scoreWeaponMode() + applyWeaponRanges()
 *   3. 治疗评估：evaluateHealNeed()
 *   4. Stance：STANCES, syncStance(), getRepositionDir(), getCurrentStance()
 *   5. Tactical Bias：triggerTacticalBias(), getTacticalBias(), clearTacticalBias()
 *   6. 工具：getAmmoRatio()
 *
 * 以下职责已迁移至 ActionArbiter + strategies：
 *   - 动作选择管线 → ActionArbiter.tick()
 *   - 候选收集 → OffenseStrategy / ReloadStrategy / PreBuffStrategy
 *   - 动作执行 → ActionExecutor.execute()
 *   - 决策日志 → DecisionTrace
 *
 * 所有参数从 personality 对象读取（mutate-only 引用）
 * 降级策略：personality == null 时评估器不创建，原 Phase 1 逻辑不变
 */
class org.flashNight.arki.unit.UnitAI.UtilityEvaluator {

    // ── 人格引用 ──
    private var p:Object;

    // ── 武器评估冷却 ──
    private var _lastWeaponSwitchFrame:Number;

    // ── 确定性随机源 ──
    private var _rng:LinearCongruentialEngine;

    // ── 武器姿态（Stance）──
    private var _currentStance:Object;

    // ── 战术偏置（Tactical Bias）──
    // 技能执行后的短期评分偏置，expiryFrame 后自动失效
    private var _tacticalBias:Object;

    // ── 评分维度键序（evalDepth 控制前 N 维激活）──
    // dim0=damage, dim1=safety, dim2=resource, dim3=positioning, dim4=combo
    public static var DIM_WEIGHTS:Array = ["w_damage", "w_safety", "w_resource", "w_positioning", "w_combo"];

    // ═══════ 武器威力系数（DPS 代理）═══════
    //
    // 控制武器选择的基础偏好：高系数 = 更高效的输出方式
    // 当前硬编码，后续替换为 actualDPS / referenceDPS
    // 中心化偏移公式：(power - 0.5) × POWER_WEIGHT
    //   0.5 = 中性点（兵器），不改变原有评分
    //   < 0.5 → 降权（空手），> 0.5 → 升权（远程）
    //   远程牵制 > 近战换血 的战术思路通过系数差异表达

    private static var WEAPON_POWER:Object = initWeaponPower();
    private static var POWER_WEIGHT:Number = 0.3;  // 降权：让距离/人格有更多发言权

    private static function initWeaponPower():Object {
        var wp:Object = {};
        wp["空手"] = 0.1;   // 极低：几乎不应主动选择
        wp["兵器"] = 0.75;  // 近战武器，效率较高但有风险
        wp["手枪"] = 0.6;   // 单手枪，略优于近战
        wp["双枪"] = 0.8;   // 双持高火力
        wp["长枪"] = 1.0;   // 最高效远程输出
        wp["手雷"] = 0.5;   // 情境武器，中性
        return wp;
    }

    // ═══════ 武器有效射程表（射程匹配度评分用）═══════
    //
    // min/max 定义每种武器的最优作战距离区间
    // 在区间内 → +0.1，偏离 → 按距离线性惩罚，封顶 -0.3
    // 与 WEAPON_POWER 共同决定武器选择：power 管基准偏好，range 管距离适应

    private static var WEAPON_RANGES:Object = initWeaponRanges();

    private static function initWeaponRanges():Object {
        var wr:Object = {};
        wr["空手"] = { min: 0,   max: 80  };
        wr["兵器"] = { min: 0,   max: 180 };
        wr["手枪"] = { min: 100, max: 350 };
        wr["双枪"] = { min: 80,  max: 350 };
        wr["长枪"] = { min: 150, max: 400 };
        wr["手雷"] = { min: 150, max: 350 };
        return wr;
    }

    // ═══════ Stance 配置表 ═══════
    //
    // 每种武器模式对应一组评分调制参数：
    //   dimMod[5]      : 叠加到 personality 维度权重上的偏移
    //   skillAffinity  : { 技能类型 → 额外加分 }
    //   repositionDir  : -1=贴近, 0=中性, +1=拉距
    //   attackBonus    : BasicAttack 额外加分
    //   optDistMin/Max : 距离窗口型姿态的最优区间（仅手雷）

    private static var STANCES:Object = initStances();

    private static function initStances():Object {
        var s:Object = {};

        // 近战：空手 — 高连击+伤害，贴近作战
        s["空手"] = {
            dimMod: [0.15, -0.1, 0, -0.05, 0.2],
            skillAffinity: {格斗: 0.25, 躲避: 0.1},
            repositionDir: -1,
            attackBonus: 0.1
        };

        // 近战：兵器 — 高伤害，刀技专精
        s["兵器"] = {
            dimMod: [0.2, -0.05, 0, 0, 0.15],
            skillAffinity: {刀技: 0.25, 格斗: 0.1},
            repositionDir: -1,
            attackBonus: 0.05
        };

        // 远程：手枪系 — 安全+定位，保持距离
        var ranged:Object = {
            dimMod: [-0.05, 0.1, 0.1, 0.1, -0.1],
            skillAffinity: {火器: 0.2},
            repositionDir: 1,
            attackBonus: 0
        };
        s["手枪"] = ranged;
        s["手枪2"] = ranged;
        s["双枪"] = ranged;

        // 远程：长枪 — 高安全+定位，技能优先于普攻
        s["长枪"] = {
            dimMod: [-0.05, 0.15, 0.05, 0.15, -0.15],
            skillAffinity: {火器: 0.25},
            repositionDir: 1,
            attackBonus: -0.1
        };

        // 特殊：手雷 — 距离窗口型，投掷后建议切换
        s["手雷"] = {
            dimMod: [0.15, 0, -0.15, 0.2, 0],
            skillAffinity: {},
            repositionDir: 1,
            attackBonus: -0.2,
            optDistMin: 150,
            optDistMax: 350
        };

        return s;
    }

    // ═══════ 构造 ═══════

    public function UtilityEvaluator(personality:Object) {
        this.p = personality;
        this._rng = LinearCongruentialEngine.getInstance();
        this._lastWeaponSwitchFrame = -999;
        this._currentStance = null;
        this._tacticalBias = null;
    }

    // ═══════ Stance 公开接口 ═══════

    /**
     * syncStance — 同步武器姿态（由 evaluateWeaponMode 调用）
     */
    public function syncStance(mode:String):Void {
        _currentStance = STANCES[mode];
    }

    /**
     * getRepositionDir — 当前姿态的位移倾向
     * @return -1=贴近, 0=中性/无姿态, +1=拉距
     * HeroCombatModule.engage 读取此值决定远程风筝行为
     */
    public function getRepositionDir():Number {
        return (_currentStance != null) ? _currentStance.repositionDir : 0;
    }

    // ═══════ Stance/Tactical 访问器（供 ActionArbiter 评分用）═══════

    public function getCurrentStance():Object {
        return _currentStance;
    }

    public function getTacticalBias():Object {
        return _tacticalBias;
    }

    public function clearTacticalBias():Void {
        _tacticalBias = null;
    }

    // ═══════ 评分服务（供 ActionArbiter._scoreCandidates 调用）═══════

    // ── 战术偏置触发 ──

    /**
     * triggerTacticalBias — 技能执行后设定短期评分偏置
     *
     * 位移技能 → 后续 tick 提升近战/连招评分（"闪现突击"效果）
     * 增益技能 → 后续 tick 提升攻击性评分（"霸体冲锋"效果）
     * 躲避技能 → 后续 tick 提升反击评分（"规避反击"效果）
     *
     * 偏置自然过期（expiryFrame），无需独立状态机
     */
    public function triggerTacticalBias(skill:Object, currentFrame:Number):Void {
        var func:String = skill.功能;

        if (func == "位移" || func == "高频位移") {
            // 闪现突击：位移后追加近战连招
            _tacticalBias = {
                skillType: {格斗: 0.3, 刀技: 0.3, 火器: 0.1},
                attackBonus: 0.2,
                expiryFrame: currentFrame + 8
            };
        } else if (func == "增益") {
            // 霸体冲锋：buff 后提升攻击性
            _tacticalBias = {
                skillType: {格斗: 0.2, 刀技: 0.2, 火器: 0.2},
                attackBonus: 0.15,
                expiryFrame: currentFrame + 12
            };
        } else if (func == "躲避") {
            // 规避反击：闪避后窗口期反击
            _tacticalBias = {
                skillType: {格斗: 0.25, 刀技: 0.2},
                attackBonus: 0.1,
                expiryFrame: currentFrame + 6
            };
        }
        // 其他技能类型不触发战术偏置
    }

    // ── 单维度评分 ──

    public function scoreDimension(dim:Number, c:Object, data:UnitAIData, self:MovieClip):Number {
        switch (dim) {
            case 0: return scoreDamage(c, data, self);
            case 1: return scoreSafety(c, self);
            case 2: return scoreResource(c);
            case 3: return scorePositioning(c, data);
            case 4: return scoreCombo(c);
            default: return 0;
        }
    }

    private function scoreDamage(c:Object, data:UnitAIData, self:MovieClip):Number {
        if (c.type == "attack") return 0.5;
        if (c.type == "hold") return 0;
        // Skill
        var base:Number = 0.3 + (c.skill.技能等级 / 10) * 0.7;
        var 类型:String = c.skill.类型;
        var 功能:String = c.skill.功能;
        if (类型 == "刀技") base += 0.3;
        else if (类型 == "格斗") base += 0.2;
        else if (类型 == "火器") base += 0.3;
        if (功能 == "躲避") base -= 0.2;
        if (功能 == "远程输出" && data.absdiff_x > 200) base += 0.2;
        if (功能 == "位移持续输出") base += 0.2;
        if (base > 1) base = 1;
        if (base < 0) base = 0;
        return base;
    }

    private function scoreSafety(c:Object, self:MovieClip):Number {
        var hpRatio:Number = self.hp / self.hp满血值;
        if (c.type == "attack") return 0.5;
        if (c.type == "hold") return 0.5;
        // Skill
        if (c.skill.功能 == "躲避") {
            // 基础分大幅下调：躲避是反应性行为，非默认选项
            // 被击加分（+0.5）由 ActionArbiter._scoreCandidates 处理
            var hpDodge:Number = self.hp / self.hp满血值;
            if (hpDodge < 0.3) return 0.6;  // 低血恐慌躲避
            return 0.2;                      // 正常低基础分
        }
        var base:Number = 0.3 + hpRatio * 0.4;
        return base > 1 ? 1 : base;
    }

    private function scoreResource(c:Object):Number {
        // 当前游戏无 MP 系统，所有动作资源成本相同
        return 1.0;
    }

    private function scorePositioning(c:Object, data:UnitAIData):Number {
        if (c.type != "skill") return 0.3;
        var 功能:String = c.skill.功能;
        if (功能 == "高频位移") {
            return (data.absdiff_x > data.xrange * 0.8) ? 0.7 : 0.4;
        }
        if (功能 == "位移持续输出") return 0.6;
        return 0.3;
    }

    private function scoreCombo(c:Object):Number {
        var cp:Number = p.comboPreference;
        if (isNaN(cp)) cp = 0;
        if (c.type == "attack") return 0.4 + cp * 0.4;
        if (c.type == "hold") return 0.1;
        // Skill
        var 类型:String = c.skill.类型;
        if (类型 == "格斗" || 类型 == "刀技") return 0.6 + cp * 0.3;
        if (c.skill.功能 == "躲避" || c.skill.功能 == "增益") return 0.2;
        return 0.3;
    }

    // ── Boltzmann 选择 ──

    public function boltzmannSelect(candidates:Array, T:Number):Object {
        var len:Number = candidates.length;
        if (len == 0) return null;
        if (len == 1) {
            candidates[0]._ew = 1;
            return candidates[0];
        }

        // 数值稳定：减去最大分
        var maxS:Number = candidates[0].score;
        for (var i:Number = 1; i < len; i++) {
            if (candidates[i].score > maxS) maxS = candidates[i].score;
        }

        // 计算 exp 权重
        var sumExp:Number = 0;
        for (var j:Number = 0; j < len; j++) {
            var ew:Number = Math.exp((candidates[j].score - maxS) / T);
            candidates[j]._ew = ew;
            sumExp += ew;
        }

        // 轮盘选择
        var r:Number = _rng.nextFloat() * sumExp;
        var cum:Number = 0;
        for (var k:Number = 0; k < len; k++) {
            cum += candidates[k]._ew;
            if (r <= cum) return candidates[k];
        }
        return candidates[len - 1];
    }

    // ═══════ 2. 武器模式选择 ═══════

    /**
     * getAmmoRatio — 指定武器模式的余弹比
     *
     * @return 1.0=满弹, 0.0=空弹; 近战模式返回 1.0
     *         双枪取两把中较低值（短板决定切换紧迫度）
     */
    public function getAmmoRatio(self:MovieClip, mode:String):Number {
        switch (mode) {
            case "长枪":
                if (self.长枪弹匣容量 > 0) return 1 - self.长枪.value.shot / self.长枪弹匣容量;
                break;
            case "手枪":
                if (self.手枪弹匣容量 > 0) return 1 - self.手枪.value.shot / self.手枪弹匣容量;
                break;
            case "双枪":
                var r1:Number = (self.手枪弹匣容量 > 0) ? (1 - self.手枪.value.shot / self.手枪弹匣容量) : 1;
                var r2:Number = (self.手枪2弹匣容量 > 0) ? (1 - self.手枪2.value.shot / self.手枪2弹匣容量) : 1;
                return (r1 < r2) ? r1 : r2; // 短板值
        }
        return 1.0; // 近战/空手/无限弹药
    }

    /**
     * evaluateWeaponMode — 替换 HeroCombatBehavior.evaluateWeapon
     *
     * 在 Selector 中每次决策时调用。
     * 评估各可用武器模式 → 切换最优 → 设定攻击范围参数 → 同步 Stance。
     *
     * 紧急前置：远程空弹 + 近距 → 直接切近战（不走评分）
     * 余弹比参与武器评分（弹药快耗尽的武器降权）
     */
    public function evaluateWeaponMode(data:UnitAIData):Void {
        var self:MovieClip = data.self;
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 武器切换冷却（8帧 ≈ 0.3s，配合 unitUpdateWheel 4帧间隔 = 每2个AI tick评估一次）
        if (currentFrame - _lastWeaponSwitchFrame < 8) {
            applyWeaponRanges(self, data);
            syncStance(self.攻击模式);
            return;
        }

        // 检查装备
        var has刀:Boolean = self.刀 ? true : false;
        var has长枪:Boolean = self.长枪 ? true : false;
        var has手枪:Boolean = self.手枪 ? true : false;
        var has手枪2:Boolean = self.手枪2 ? true : false;
        var hasWeapon:Boolean = has刀 || has长枪 || has手枪 || has手枪2;

        if (!hasWeapon) {
            applyWeaponRanges(self, data);
            syncStance(self.攻击模式);
            return;
        }

        // 估算到目标的距离
        var dist:Number = 200;
        if (data.target != null) {
            data.updateSelf();
            data.updateTarget();
            dist = data.absdiff_x;
        }

        // ── 紧急前置：远程空弹 + 近距 → 直接切近战 ──
        // 不走评分，生死攸关不交给概率
        if (_currentStance != null && _currentStance.repositionDir > 0) {
            var curAmmo:Number = getAmmoRatio(self, self.攻击模式);
            if (curAmmo <= 0 && dist < 150 && has刀) {
                self.攻击模式切换("兵器");
                _lastWeaponSwitchFrame = currentFrame;
                applyWeaponRanges(self, data);
                syncStance("兵器");
                if (_root.AI调试模式 == true) {
                    _root.服务器.发布服务器消息("[WPN] " + self.名字 + " EMERGENCY melee! ammo=0 dist=" + Math.round(dist));
                }
                return;
            }
        }

        // 技能动画保护已由 ActionArbiter._evaluateStance 处理
        // （p.skillAnimProtect 帧，基于人格派生）

        // 生命值比例（供武器评分中生存压力计算）
        var hpRatio:Number = self.hp / self.hp满血值;
        if (isNaN(hpRatio) || hpRatio > 1) hpRatio = 1;
        if (hpRatio < 0) hpRatio = 0;

        // 生存压力（切换成本 + debug 共用）
        var courage:Number = p.勇气 || 0;
        var healthPressure:Number = (1 - hpRatio) * (1 - courage);

        // 评估各可用模式
        var bestMode:String = self.攻击模式;
        var bestScore:Number = -999;
        var modes:Array = ["空手"];
        if (has刀) modes.push("兵器");
        if (has手枪 && has手枪2) {
            modes.push("双枪");
        } else if (has手枪 || has手枪2) {
            modes.push("手枪");
        }
        if (has长枪) modes.push("长枪");

        // 切换成本/迟滞（从 personality 读取，fallback 硬编码）
        var baseSwitchCost:Number = p.weaponSwitchCost;
        if (isNaN(baseSwitchCost) || baseSwitchCost < 0.05) baseSwitchCost = 0.2;
        var hysteresis:Number = p.weaponHysteresis;
        if (isNaN(hysteresis) || hysteresis < 0) hysteresis = 0.1;

        for (var i:Number = 0; i < modes.length; i++) {
            var mode:String = modes[i];
            var score:Number = scoreWeaponMode(mode, dist, hpRatio);

            // ── 射程匹配度 ──
            // 在最优区间内 → +0.1；偏离 → 按距离线性惩罚，封顶 -0.3
            var wRange:Object = WEAPON_RANGES[mode];
            if (wRange != null) {
                if (dist < wRange.min) {
                    var underPenalty:Number = -(wRange.min - dist) / 200;
                    score += (underPenalty < -0.3) ? -0.3 : underPenalty;
                } else if (dist > wRange.max) {
                    var overPenalty:Number = -(dist - wRange.max) / 200;
                    score += (overPenalty < -0.3) ? -0.3 : overPenalty;
                } else {
                    score += 0.1; // 在最优区间内
                }
            }

            // ── 余弹比评分调制 ──
            // 满弹=+0.1, 半弹=0, 空弹=-0.5（大惩罚直接淘汰）
            var ammoR:Number = getAmmoRatio(self, mode);
            if (ammoR <= 0) {
                score -= 0.5;
            } else {
                score += (ammoR - 0.5) * 0.2;
            }

            // ── 切换成本 + 迟滞（hysteresis）──
            // 切入新武器：需要越过 switchCost 关卡
            // 维持当前武器：获得 hysteresis 加分（形成死区，抑制抖动）
            if (mode == self.攻击模式) {
                score += hysteresis; // 维持当前 → 加分
            } else {
                var switchCost:Number = baseSwitchCost * (1 - healthPressure * 0.7);
                if (switchCost < 0.05) switchCost = 0.05;
                score -= switchCost; // 切换 → 惩罚
            }

            if (score > bestScore) {
                bestScore = score;
                bestMode = mode;
            }
        }

        // 执行切换
        var didSwitch:Boolean = false;
        if (bestMode != self.攻击模式 && bestMode != "空手") {
            var prevMode:String = self.攻击模式;
            self.攻击模式切换(bestMode);
            didSwitch = true;
        }

        // 更新评估帧（无论是否切换，防止每帧重复评估）
        _lastWeaponSwitchFrame = currentFrame;

        applyWeaponRanges(self, data);
        syncStance(self.攻击模式);

        // ── Debug 武器评估输出 ──
        if (_root.AI调试模式 == true) {
            var curMode:String = didSwitch ? prevMode : self.攻击模式;
            var dbgSwitchCost:Number = baseSwitchCost * (1 - healthPressure * 0.7);
            if (dbgSwitchCost < 0.05) dbgSwitchCost = 0.05;
            var wmsg:String = "[WPN] " + self.名字 + " cur=" + curMode + " sc=" + (Math.round(dbgSwitchCost * 100) / 100) + " hy=" + (Math.round(hysteresis * 100) / 100) + " | ";
            for (var di:Number = 0; di < modes.length; di++) {
                var dm:String = modes[di];
                var ds:Number = scoreWeaponMode(dm, dist, hpRatio);
                var ar:Number = getAmmoRatio(self, dm);
                var ammoAdj:Number = (ar <= 0) ? -0.5 : ((ar - 0.5) * 0.2);
                var dsc:Number = (dm != curMode) ? -dbgSwitchCost : 0;
                wmsg += dm + "=" + (Math.round((ds + ammoAdj + dsc) * 100) / 100);
                // 远程武器显示余弹比
                if (dm != "空手" && dm != "兵器") wmsg += "[" + Math.round(ar * 100) + "%]";
                wmsg += " ";
            }
            wmsg += "-> " + bestMode + (didSwitch ? " SWITCH!" : " hold");
            wmsg += " [dist=" + Math.round(dist) + " hp=" + Math.round(hpRatio * 100) + "% pr=" + (Math.round(healthPressure * 100) / 100) + "]";
            _root.服务器.发布服务器消息(wmsg);
        }
    }

    /**
     * scoreWeaponMode — 武器模式评分
     *
     * 设计原则：
     *   武器选择主要由人格（勇气/智力）和生存压力驱动，
     *   当前距离只做轻度调制（±0.1 级别），因为切换武器后
     *   AI 会通过 repositionDir + xdistance 自动调整站位。
     *
     * 评分结构：
     *   base（0.5 统一基准）+ 人格加成 + 生存压力 + 距离微调
     *
     * 生存压力：healthPressure = (1 - hpRatio) × (1 - 勇气)
     *   满血: ≈0, 无影响
     *   低血+低勇气: 高压 → 强烈偏向远程
     *   低血+高勇气: 低压 → 维持近战
     */
    private function scoreWeaponMode(mode:String, dist:Number, hpRatio:Number):Number {
        var score:Number = 0;
        var courage:Number = p.勇气 || 0;
        var intel:Number = p.智力 || 0;
        var mastery:Number = p.stanceMastery || 0;
        var stability:Number = p.stabilityFactor || 0;

        // 生存压力：(1 - 血量比) × (1 - 勇气)
        var healthPressure:Number = (1 - hpRatio) * (1 - courage);

        switch (mode) {
            case "空手":
                // 基准 + 勇气驱动近战倾向 + 熟练度
                score = 0.5 + courage * 0.35 + mastery * 0.15;
                // 近战：生存压力惩罚
                score -= healthPressure * 0.5;
                // 距离微调：近距小加分，远距轻惩罚
                if (dist < 80) score += 0.05;
                else if (dist > 200) score -= 0.1;
                break;
            case "兵器":
                // 基准偏高（有武器 > 没武器）+ 勇气 + 熟练度
                score = 0.55 + courage * 0.3 + mastery * 0.15;
                // 近战：生存压力惩罚（略低于空手，有距离优势）
                score -= healthPressure * 0.4;
                // 距离微调
                if (dist < 180) score += 0.05;
                else if (dist > 300) score -= 0.1;
                break;
            case "手枪":
                // 基准 + 智力驱动远程倾向 + 稳定性
                score = 0.5 + intel * 0.3 + stability * 0.15;
                // 远程：生存压力加分
                score += healthPressure * 0.35;
                // 距离微调：远距小加分，极近轻惩罚
                if (dist > 150) score += 0.05;
                else if (dist < 60) score -= 0.1;
                break;
            case "双枪":
                // 双持：火力密度高于单手枪，适用距离更灵活
                score = 0.5 + intel * 0.25 + courage * 0.1 + stability * 0.1;
                // 远程：生存压力加分
                score += healthPressure * 0.35;
                // 距离微调：比手枪更适应中近距
                if (dist > 120) score += 0.05;
                else if (dist < 50) score -= 0.1;
                break;
            case "长枪":
                // 基准 + 智力 + 稳定性
                score = 0.5 + intel * 0.3 + stability * 0.15;
                // 远程：生存压力加分（最安全选择）
                score += healthPressure * 0.4;
                // 距离微调
                if (dist > 200) score += 0.05;
                else if (dist < 80) score -= 0.1;
                break;
        }

        // ── 武器威力系数偏移（DPS 代理层）──
        // 中心化：兵器(0.5) = 中性不变，< 0.5 降权，> 0.5 升权
        // 后续替换：WEAPON_POWER[mode] → self[mode].dps / referenceDPS
        var power:Number = WEAPON_POWER[mode];
        if (power == undefined) power = 0.5; // 未知模式 → 中性
        score += (power - 0.5) * POWER_WEIGHT;

        return score;
    }

    /**
     * 根据当前攻击模式设定范围参数
     * 保留原始 Phase 1 的硬编码值（这些是游戏平衡参数）
     */
    public function applyWeaponRanges(self:MovieClip, data:UnitAIData):Void {
        switch (self.攻击模式) {
            case "空手":
                self.x轴攻击范围 = 90;
                self.y轴攻击范围 = 20;
                self.x轴保持距离 = 50;
                break;
            case "兵器":
                self.x轴攻击范围 = 150;
                self.y轴攻击范围 = 20;
                self.x轴保持距离 = 150;
                break;
            case "长枪":
            case "手枪":
            case "手枪2":
            case "双枪":
                self.x轴攻击范围 = 400;
                self.y轴攻击范围 = 20;
                self.x轴保持距离 = 200;
                break;
            case "手雷":
                self.x轴攻击范围 = 300;
                self.y轴攻击范围 = 10;
                self.x轴保持距离 = 200;
                break;
        }
        data.xrange = self.x轴攻击范围;
        data.zrange = self.y轴攻击范围;
        data.xdistance = self.x轴保持距离;
    }

    // ═══════ 3. 血包评估 ═══════

    /**
     * evaluateHealNeed — 替换 HeroCombatBehavior.evaluateHeal
     *
     * healScore = (1 - hp/maxHP) × healEagerness × 2.0 + 紧急加成
     * healScore > 0.5 → 使用血包
     */
    public function evaluateHealNeed(data:UnitAIData):Void {
        var self:MovieClip = data.self;
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 技能/战技播放期：血包动作会打断技能，按“仅技能可取消技能”规则延后
        if (self.状态 == "技能" || self.状态 == "战技") return;

        // 前置条件
        if (self.血包数量 <= 0) return;
        if (currentFrame - self.上次使用血包时间 <= self.血包使用间隔) return;

        var hpRatio:Number = self.hp / self.hp满血值;
        var eagerness:Number = p.healEagerness;
        if (isNaN(eagerness)) eagerness = 0.5;

        var healScore:Number = (1 - hpRatio) * eagerness * 2.0;

        // 紧急加成：血量 < 20%
        if (hpRatio < 0.2) healScore += 1.0;

        // 安全区自动回血
        if (_root.gameworld.允许通行 && self.hp满血值 > self.hp) {
            healScore += 0.6;
        }

        if (healScore > 0.5) {
            var hpBefore:Number = self.hp;
            self.血包数量--;
            _root.佣兵使用血包(self._name);
            self.上次使用血包时间 = currentFrame;
            _root.发布消息(self.名字 + "[" + hpBefore + "/" + self.hp满血值 + "] 紧急治疗后还剩[" + self.血包数量 + "]个治疗包");
        }
    }

}
