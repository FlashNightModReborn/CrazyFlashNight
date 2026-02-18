/**
 * StanceManager — 武器姿态 + 战术偏置管理
 *
 * 从 UtilityEvaluator 提取的姿态/战术子服务。
 * 职责：
 *   1. STANCES 配置表（评分维度调制、技能亲和、位移倾向）
 *   2. 当前姿态同步 syncStance() / getCurrentStance() / getRepositionDir()
 *   3. 战术偏置生命周期 triggerTacticalBias() / getTacticalBias() / clearTacticalBias()
 *
 * 无状态依赖：仅依赖静态配置表和内部字段，不引用其他 AI 子服务。
 */
class org.flashNight.arki.unit.UnitAI.StanceManager {

    // ── 姿态状态 ──
    private var _currentStance:Object;

    // ── 战术偏置（技能执行后短期评分偏置，expiryFrame 后自动失效）──
    private var _tacticalBias:Object;

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

    public function StanceManager() {
        this._currentStance = null;
        this._tacticalBias = null;
    }

    // ═══════ Stance 公开接口 ═══════

    /**
     * syncStance — 同步武器姿态（由 WeaponEvaluator.evaluateWeaponMode 调用）
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

    public function getCurrentStance():Object {
        return _currentStance;
    }

    // ═══════ 战术偏置 ═══════

    public function getTacticalBias():Object {
        return _tacticalBias;
    }

    public function clearTacticalBias():Void {
        _tacticalBias = null;
    }

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
}
