import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.StanceManager;

/**
 * WeaponEvaluator — 武器模式评估与切换
 *
 * 从 UtilityEvaluator 提取的武器评估子服务。
 * 职责：
 *   1. 武器威力系数 WEAPON_POWER + 射程匹配 WEAPON_RANGES（静态配置）
 *   2. evaluateWeaponMode(): 综合评分 → 切换 → 范围设定 → 姿态同步
 *   3. scoreWeaponMode(): 人格×距离×生存压力驱动武器评分
 *   4. applyWeaponRanges(): 根据攻击模式设定范围参数
 *   5. getAmmoRatio(): 武器余弹比查询
 *
 * 依赖：StanceManager（syncStance / getCurrentStance）
 */
class org.flashNight.arki.unit.UnitAI.WeaponEvaluator {

    // ── 人格引用 ──
    private var p:Object;

    // ── 姿态管理器引用 ──
    private var _stanceMgr:StanceManager;

    // ── 武器评估冷却 ──
    private var _lastWeaponSwitchFrame:Number;

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

    // ═══════ 构造 ═══════

    public function WeaponEvaluator(personality:Object, stanceMgr:StanceManager) {
        this.p = personality;
        this._stanceMgr = stanceMgr;
        this._lastWeaponSwitchFrame = -999;
    }

    // ═══════ 余弹比查询 ═══════

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
            case "手枪2":
                if (self.手枪2弹匣容量 > 0) return 1 - self.手枪2.value.shot / self.手枪2弹匣容量;
                break;
            case "双枪":
                var r1:Number = (self.手枪弹匣容量 > 0) ? (1 - self.手枪.value.shot / self.手枪弹匣容量) : 1;
                var r2:Number = (self.手枪2弹匣容量 > 0) ? (1 - self.手枪2.value.shot / self.手枪2弹匣容量) : 1;
                return (r1 < r2) ? r1 : r2; // 短板值
        }
        return 1.0; // 近战/空手/无限弹药
    }

    // ═══════ 武器模式评估 ═══════

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
            _stanceMgr.syncStance(self.攻击模式);
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
            _stanceMgr.syncStance(self.攻击模式);
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
        var curStance:Object = _stanceMgr.getCurrentStance();
        if (curStance != null && curStance.repositionDir > 0) {
            var curAmmo:Number = getAmmoRatio(self, self.攻击模式);
            if (curAmmo <= 0 && dist < 150 && has刀) {
                self.攻击模式切换("兵器");
                _lastWeaponSwitchFrame = currentFrame;
                applyWeaponRanges(self, data);
                _stanceMgr.syncStance("兵器");
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
            var ammoR:Number = getAmmoRatio(self, mode);
            if (ammoR <= 0) {
                score -= 0.5;
            } else {
                score += (ammoR - 0.5) * 0.2;
            }

            // ── 切换成本 + 迟滞（hysteresis）──
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
            var switchArg:String = (bestMode == "双枪") ? "手枪" : bestMode;
            self.攻击模式切换(switchArg);
            didSwitch = true;
        }

        // 更新评估帧（无论是否切换，防止每帧重复评估）
        _lastWeaponSwitchFrame = currentFrame;

        applyWeaponRanges(self, data);
        _stanceMgr.syncStance(self.攻击模式);

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
                if (dm != "空手" && dm != "兵器") wmsg += "[" + Math.round(ar * 100) + "%]";
                wmsg += " ";
            }
            wmsg += "-> " + bestMode + (didSwitch ? " SWITCH!" : " hold");
            wmsg += " [dist=" + Math.round(dist) + " hp=" + Math.round(hpRatio * 100) + "% pr=" + (Math.round(healthPressure * 100) / 100) + "]";
            _root.服务器.发布服务器消息(wmsg);
        }
    }

    // ═══════ 武器模式评分 ═══════

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
                score = 0.5 + courage * 0.35 + mastery * 0.15;
                score -= healthPressure * 0.5;
                if (dist < 80) score += 0.05;
                else if (dist > 200) score -= 0.1;
                break;
            case "兵器":
                score = 0.55 + courage * 0.3 + mastery * 0.15;
                score -= healthPressure * 0.4;
                if (dist < 180) score += 0.05;
                else if (dist > 300) score -= 0.1;
                break;
            case "手枪":
                score = 0.5 + intel * 0.3 + stability * 0.15;
                score += healthPressure * 0.35;
                if (dist > 150) score += 0.05;
                else if (dist < 60) score -= 0.1;
                break;
            case "双枪":
                score = 0.5 + intel * 0.25 + courage * 0.1 + stability * 0.1;
                score += healthPressure * 0.35;
                if (dist > 120) score += 0.05;
                else if (dist < 50) score -= 0.1;
                break;
            case "长枪":
                score = 0.5 + intel * 0.3 + stability * 0.15;
                score += healthPressure * 0.4;
                if (dist > 200) score += 0.05;
                else if (dist < 80) score -= 0.1;
                break;
        }

        // ── 武器威力系数偏移（DPS 代理层）──
        var power:Number = WEAPON_POWER[mode];
        if (power == undefined) power = 0.5;
        score += (power - 0.5) * POWER_WEIGHT;

        return score;
    }

    // ═══════ 攻击范围设定 ═══════

    /**
     * 根据当前攻击模式设定范围参数
     *
     * 基础值（武器模式决定）+ 智力×强弱动态延伸
     * 远程基础 xrange=600 → 600px 有效射程
     * 智力延伸：面对更强敌人时自动拉开保持距离
     */
    public function applyWeaponRanges(self:MovieClip, data:UnitAIData):Void {
        switch (self.攻击模式) {
            case "空手":
                self.x轴攻击范围 = 90;
                self.y轴攻击范围 = 25;
                self.x轴保持距离 = 50;
                break;
            case "兵器":
                self.x轴攻击范围 = 150;
                self.y轴攻击范围 = 25;
                self.x轴保持距离 = 120;
                break;
            case "长枪":
            case "手枪":
            case "手枪2":
            case "双枪":
                self.x轴攻击范围 = 600;
                self.y轴攻击范围 = 25;
                self.x轴保持距离 = 350;
                break;
            case "手雷":
                self.x轴攻击范围 = 400;
                self.y轴攻击范围 = 10;
                self.x轴保持距离 = 250;
                break;
        }
        data.xrange = self.x轴攻击范围;
        data.zrange = self.y轴攻击范围;
        data.xdistance = self.x轴保持距离;

        // ── 智力×敌我强弱 → 动态保持距离延伸 ──
        if (p != null && data.target != null && data.target.hp > 0) {
            var intel:Number = p.智力;
            if (!isNaN(intel) && intel > 0) {
                var selfHP:Number = self.hp满血值;
                var enemyHP:Number = data.target.hp满血值;
                if (selfHP > 0 && enemyHP > 0) {
                    var strengthRatio:Number = enemyHP / selfHP;
                    if (strengthRatio > 1) {
                        var excess:Number = strengthRatio - 1;
                        if (excess > 2) excess = 2;
                        data.xdistance += Math.round(intel * excess * 150);
                    }
                }
            }
        }
    }
}
