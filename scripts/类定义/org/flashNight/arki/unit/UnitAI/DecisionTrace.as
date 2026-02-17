import org.flashNight.arki.unit.UnitAI.AIContext;

/**
 * DecisionTrace — AI 决策可观测性系统
 *
 * 贯穿单次 tick 的诊断对象，策略在过滤/评分时调用 trace 方法记录，
 * tick 末尾由 flush() 按智能触发条件决定是否输出。
 *
 * 日志级别（从 _root.AI日志级别 读取，默认 0）：
 *   0 = OFF    — 不输出（零开销：reject/scored 方法直接 return）
 *   1 = BRIEF  — 选中动作 + 关键上下文（一行）
 *   2 = TOP3   — Top3 候选 + 概率 + 过滤聚合
 *   3 = FULL   — 维度分解 + 逐条过滤原因 + 人格溯源（首次输出 traits→params→__aiMeta）
 *
 * 智能触发（替代固定采样）：
 *   FULL     → 始终输出
 *   underFire → 始终输出（紧急情况需要可见性）
 *   决策切换  → 输出（selectedName != lastSelectedName）
 *   低置信度  → 输出（top1.score - top2.score < 0.1 * T）
 *   其他     → 跳过（节流）
 *
 * 过滤原因分类码：
 *   CD    = 冷却中
 *   RANGE = 距离不匹配
 *   BUFF  = buff 已激活
 *   RIGID = 刚体期间跳过霸体类
 *   AMMO  = 弹药充足
 *   STANCE = 非远程姿态
 *   INT   = 优先级不足以中断（+ lockSource）
 *   ALOCK = 动画锁期间（非紧急候选）
 */
class org.flashNight.arki.unit.UnitAI.DecisionTrace {

    // ── 日志级别常量 ──
    static var LEVEL_OFF:Number   = 0;
    static var LEVEL_BRIEF:Number = 1;
    static var LEVEL_TOP3:Number  = 2;
    static var LEVEL_FULL:Number  = 3;

    // ── 过滤原因码 ──
    static var REASON_CD:String        = "CD";
    static var REASON_RANGE:String     = "RANGE";
    static var REASON_BUFF:String      = "BUFF";
    static var REASON_RIGID:String     = "RIGID";
    static var REASON_AMMO:String      = "AMMO";
    static var REASON_STANCE:String    = "STANCE";
    static var REASON_INTERRUPT:String = "INT";
    static var REASON_ANIMLOCK:String  = "ALOCK";

    // ── 状态 ──
    private var _level:Number;
    private var _unitName:String;
    private var _ctx:AIContext;
    private var _p:Object;   // personality 引用（4a __aiMeta 溯源）

    // ── Reject 聚合（计数而非逐条）──
    private var _rejectCounts:Object;
    // FULL 级别逐条记录
    private var _rejectDetails:Array;

    // ── 评分记录（Top N）──
    private var _scored:Array;

    // ── 选中结果 ──
    private var _selectedName:String;
    private var _selectedProb:Number;
    private var _temperature:Number;

    // ── 跨 tick 状态（智能触发）──
    private var _lastSelectedName:String;
    private var _traitsPrinted:Boolean;  // FULL: 已输出 traits 概览（同一单位仅输出一次）

    // ═══════ 构造 ═══════

    public function DecisionTrace() {
        _level = 0;
        _lastSelectedName = null;
        _traitsPrinted = false;
        _rejectCounts = {};
        _rejectDetails = [];
        _scored = [];
    }

    // ═══════ 每 tick 生命周期 ═══════

    /**
     * begin — tick 开始时调用，重置本 tick 数据
     * @param p  personality 引用（FULL 级别溯源输出用）
     */
    public function begin(unitName:String, ctx:AIContext, p:Object):Void {
        // 动态读取日志级别
        var lv:Number = _root.AI日志级别;
        _level = (isNaN(lv) || lv < 0) ? 0 : lv;

        if (_level <= 0) return;

        _unitName = unitName;
        _ctx = ctx;
        _p = p;

        // 重置聚合器
        for (var k:String in _rejectCounts) {
            delete _rejectCounts[k];
        }
        _rejectDetails.length = 0;
        _scored.length = 0;
        _selectedName = null;
        _selectedProb = 0;
        _temperature = 0;
    }

    /**
     * reject — 记录候选被过滤
     *
     * @param name       候选名称
     * @param reasonCode 原因码（REASON_* 常量）
     */
    public function reject(name:String, reasonCode:String):Void {
        if (_level <= 0) return;

        // 聚合计数
        if (_rejectCounts[reasonCode] == undefined) {
            _rejectCounts[reasonCode] = 1;
        } else {
            _rejectCounts[reasonCode]++;
        }

        // FULL 级别逐条记录
        if (_level >= LEVEL_FULL) {
            _rejectDetails.push(name + "[" + reasonCode + "]");
        }
    }

    /**
     * isFullTrace — 供外部管线判断是否需要收集诊断信息
     */
    public function isFullTrace():Boolean {
        return _level >= LEVEL_FULL;
    }

    /**
     * scored — 记录候选评分结果
     *
     * @param candidate      候选对象（含 name, type, score）
     * @param dimScores      维度分解数组（可选，FULL 级别使用）
     * @param modBreakdown   修正器分解字符串（可选，FULL 级别使用）
     * @param postBreakdown  后处理器分解字符串（可选，FULL 级别使用）
     */
    public function scored(candidate:Object, dimScores:Array,
                           modBreakdown:String, postBreakdown:String):Void {
        if (_level < LEVEL_TOP3) return;

        _scored.push({
            name: candidate.name,
            type: candidate.type,
            score: candidate.score,
            dims: dimScores,
            mods: modBreakdown,
            posts: postBreakdown
        });
    }

    /**
     * selected — 记录最终选中结果
     */
    public function selected(candidate:Object, prob:Number, T:Number):Void {
        if (_level <= 0) return;
        _selectedName = candidate.name;
        _selectedProb = prob;
        _temperature = T;
    }

    // ═══════ 输出 ═══════

    /**
     * flush — tick 末尾输出决策日志
     *
     * 智能触发：安静时不刷屏，关键时刻自动详细。
     */
    public function flush():Void {
        if (_level <= 0 || _selectedName == null) return;

        // 智能触发条件
        var shouldOutput:Boolean = false;

        if (_level >= LEVEL_FULL) {
            shouldOutput = true;
        } else if (_ctx.underFire) {
            shouldOutput = true;
        } else if (_selectedName != _lastSelectedName) {
            shouldOutput = true;
        } else if (_scored.length >= 2) {
            // 低置信度检查
            _scored.sortOn("score", Array.DESCENDING | Array.NUMERIC);
            var gap:Number = _scored[0].score - _scored[1].score;
            if (gap < 0.1 * _temperature) {
                shouldOutput = true;
            }
        }

        if (!shouldOutput) {
            _lastSelectedName = _selectedName;
            return;
        }

        // 构建输出
        var msg:String = "[AI] " + _unitName + " F:" + _ctx.frame;

        if (_level >= LEVEL_BRIEF) {
            msg += " → " + _selectedName;
            if (_selectedProb > 0) {
                msg += " (p=" + _formatNum(_selectedProb) + ")";
            }
            msg += " ctx:" + _ctx.context;
            if (_ctx.underFire) msg += " THREAT";
            if (_ctx.isRigid) msg += " RIGID";
            if (_ctx.lockSource != null) msg += " lock:" + _ctx.lockSource;
        }

        if (_level >= LEVEL_TOP3) {
            // 过滤聚合
            var filterParts:Array = [];
            for (var rk:String in _rejectCounts) {
                filterParts.push(rk + "×" + _rejectCounts[rk]);
            }
            if (filterParts.length > 0) {
                msg += " | FILTERED(" + _getTotalRejects() + "): " + filterParts.join(" ");
            }

            // Top3 候选
            _scored.sortOn("score", Array.DESCENDING | Array.NUMERIC);
            var topN:Number = Math.min(3, _scored.length);
            if (topN > 0) {
                msg += " | Top" + topN + ":";
                for (var i:Number = 0; i < topN; i++) {
                    var s:Object = _scored[i];
                    msg += " " + s.name + "=" + _formatNum(s.score);
                }
            }
            msg += " T=" + _formatNum(_temperature);
        }

        if (_level >= LEVEL_FULL && _rejectDetails.length > 0) {
            msg += "\n  rejects: " + _rejectDetails.join(", ");
        }

        // 维度分解 + 修正器分解（FULL 级别，Top1 候选）
        if (_level >= LEVEL_FULL && _scored.length > 0) {
            var top:Object = _scored[0];
            if (top.dims != null && top.dims.length > 0) {
                msg += "\n  dims[" + top.name + "]:";
                for (var di:Number = 0; di < top.dims.length; di++) {
                    msg += " d" + di + "=" + _formatNum(top.dims[di]);
                }
            }
            if (top.mods != null && top.mods.length > 0) {
                msg += "\n  mods[" + top.name + "]: " + top.mods;
            }
            if (top.posts != null && top.posts.length > 0) {
                msg += "\n  posts[" + top.name + "]: " + top.posts;
            }
        }

        // FULL: 人格概览（同一单位首次 FULL 输出时打印一次）
        if (_level >= LEVEL_FULL && !_traitsPrinted && _p != null) {
            _traitsPrinted = true;
            msg += "\n  ── personality ──"
                + " 勇气=" + _formatNum(_p.勇气)
                + " 技术=" + _formatNum(_p.技术)
                + " 经验=" + _formatNum(_p.经验)
                + " 反应=" + _formatNum(_p.反应)
                + " 智力=" + _formatNum(_p.智力)
                + " 谋略=" + _formatNum(_p.谋略);
            msg += "\n  T=" + _formatNum(_p.temperature)
                + " depth=" + _p.evalDepth
                + " tick=" + _p.tickInterval
                + " noise=" + _formatNum(_p.decisionNoise)
                + " kite=" + _formatNum(_p.kiteThreshold);
            // __aiMeta 溯源：输出选中动作相关的关键参数派生公式
            if (_p.__aiMeta != null && _selectedName != null) {
                var metaKeys:Array = _getRelevantMeta(_selectedName);
                if (metaKeys.length > 0) {
                    msg += "\n  meta:";
                    for (var mi:Number = 0; mi < metaKeys.length; mi++) {
                        var mk:String = metaKeys[mi];
                        if (_p.__aiMeta[mk] != undefined) {
                            msg += "\n    " + mk + ": " + _p.__aiMeta[mk];
                        }
                    }
                }
            }
        }

        _root.服务器.发布服务器消息(msg);

        _lastSelectedName = _selectedName;
    }

    // ═══════ 内部工具 ═══════

    private function _getTotalRejects():Number {
        var total:Number = 0;
        for (var k:String in _rejectCounts) {
            total += _rejectCounts[k];
        }
        return total;
    }

    private function _formatNum(v:Number):String {
        return String(Math.round(v * 100) / 100);
    }

    /**
     * _getRelevantMeta — 根据选中动作类型返回最相关的 __aiMeta key 列表
     *
     * 避免倒出全部 35+ 个参数，只展示与当前决策最直接相关的 3~5 个。
     */
    private function _getRelevantMeta(selectedName:String):Array {
        // 通用：temperature 和 evalDepth 始终相关
        var keys:Array = ["temperature", "evalDepth"];

        // Reload → 换弹参数
        if (selectedName == "Reload") {
            keys.push("reloadCommitFrames", "weaponSwitchCost");
            return keys;
        }

        // 技能类（含 preBuff）
        if (_selectedName != null) {
            // 检查是否是已知的非技能 name
            var isAttack:Boolean = (selectedName == "Attack" || selectedName == "Continue");
            if (!isAttack && selectedName != "Reload") {
                keys.push("skillCommitFrames", "skillAnimProtect", "decisionNoise");
                // preBuff 专属
                if (_p.__aiMeta["preBuffDistMult"] != undefined) {
                    keys.push("preBuffDistMult", "preBuffCooldown");
                }
                return keys;
            }
        }

        // Attack / Continue → 攻击倾向
        keys.push("engageDistanceMult", "comboPreference", "w_damage");
        return keys;
    }
}
