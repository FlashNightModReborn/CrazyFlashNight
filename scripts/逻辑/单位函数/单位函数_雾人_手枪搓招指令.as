/**
 * 单位函数_雾人_手枪搓招指令.as
 *
 * 手枪搓招 · 三招指令（实装方式参照 单位函数_黑猫_技能搓招指令.as 的方向电平裁决，
 * 释放路由参照 单位函数_雾人_空手搓招指令.as 的搓招门槛口径）
 *
 * 指令表（8 向归一化，前 = 朝向）：
 *   后跳射击 Shift + ← + B   （Shift 修饰，向身后跳撤；判在 前冲 之前，见后键缓冲）
 *   前冲射击 Shift + → + B   （Shift 修饰，向前冲刺射击）
 *   瞬踢追射 → + B           （向前瞬踢突进后追射；判在 前冲 之后 —— shift前 必须先吃掉，
 *                              否则 Shift+→+B 会被「前」抢走）
 *   后射     ← + B            （朝后方向键 + B，向后回射；2026-11-19 由 →B 改为 ←B，
 *                              朝向在释放前回正到按下后键那一刻的朝向，全程不转身）
 *   后撩上射 ↑ + B            （2026-11-24 实装：枪口撩向头顶，向正上方连续射击；
 *                              发数参照前冲射击的比例（同一间隔梯与封顶），不可自动换弹）
 *   换弹打击 B               （2026-11-24 实装：裸按 K，打击中向前开一枪；
 *                              射击比例参照回射（后射）的间隔梯与封顶，可自动换弹）
 *
 * ⚠ 换弹打击触发语义（2026-11-24 用户裁定）：学习该技能后，裸按 K 一律出换弹打击，
 *   不再落回普通站姿射击；因此它必须排在搓招表尾（指令优先级最低），
 *   让全部方向搓招先吃输入，落下的裸 K 才轮到它。
 *
 * ⚠ 「后」的判定：行走公共体会在按住反方向键的下一帧把 方向 翻过去，
 *   所以 Shift+← 按久了 ← 就变成「前」。这里用 _手枪后键采样 在按键沿那帧
 *   记录后键意图（窗口 手枪搓招后键窗口 帧），再让 B 去消费；
 *   换按另一个水平键或松开后重按会按新沿重新判定，避免误吃后跳。
 *
 * ⚠ 串招修复（2026-11-21）：
 *   1. 换向竞态 —— 跑动中按下的反方向键在朝向翻转前（约 2 帧）会被电平判成后键，
 *      换向跑接 Shift+B 会串出后跳/后射。移动沿（__手枪后键移动沿）头 2 帧不参与命中。
 *   2. 修饰域泄漏 —— 双击跑玩家按住奔跑键=false，跑动 →+B 的 shift前 失败后
 *      顺位漏到「前」出瞬踢。shift前 修饰扩展双击跑；前/后 单方向招在 Shift
 *      按住时一律不判；后（后射）另排除移动沿（跑动 ←+B 是换向，不是回射）。
 *
 * ⚠ 回射重铸（2026-11-21）：
 *   后射：容器内伤害倍率 x2，保留自动换弹，无蓝耗无冷却
 *   （曾加 20 蓝 + 3 秒 CD，实测未生效，按用户决定移除）；
 *   其余三招无蓝耗无冷却，但容器已取消自动换弹（弹匣打空即停火，需玩家手动换弹）。
 *
 * ⚠ 2026-11-24 新增两招的换弹口径：
 *   后撩上射与后跳/前冲/瞬踢同口径：容器无自动换弹（弹匣打空即停火）；
 *   换弹打击与回射同口径：容器保留自动换弹。
 *
 * ⚠ 三招全部只走方向电平裁决，不吃 DFA 名字通道：
 *   手枪模式（攻击模式 == "手枪"/"手枪2"）下 推断动作模组 返回 undefined，
 *   帧计时器按 moduleId=1（lightWeapon）把输入喂给 Launcher DFA，其 →+B 命中的是
 *   冷兵器技能「瞬步斩」，名字对不上；且 Shift 组合事件在采样器里排在方向事件之后，
 *   TrieDFA 无「失败回根」，[SHIFT_FORWARD, B_PRESS] 这条边实际走不到
 *   （同 冷兵器主动技能搓招 ⓪ 段的分析）。⇒ 与拔刀术同款：电平裁决排在一切之前。
 *
 * 生效范围：
 *   - 入口挂在 持枪行走状态机 顶部（手枪站立/手枪行走/手枪跑 与 手枪2站立/手枪2行走/手枪2跑
 *     都绑定该状态机，即三招在这六个状态下的任意时刻都可释放）
 *   - 只对控制目标生效；未学习的招直接放行（B 落回原有的副武器射击/换弹等行为）
 *
 * 释放硬门槛（全部满足才出手，否则交回原状态机逻辑）：
 *   1. 已学习该搓招技能：被动技能[名].等级 >= 1 且「启用」为真（被动技能启用 裁判）
 *   2. 手枪模式：攻击模式 == "手枪" 或 "手枪2"（双枪/长枪/手雷/空手不参与；
 *      2026-11-27 起「手枪」/「手枪2」也涵盖双持切至单枪的情形）
 *   3. 装备了手枪1或手枪2：手枪属性.power 或 手枪2属性.power 至少一个有效
 *
 * 手枪2 容器选择（2026-11-27 键3切枪配套）：
 *   三个动画的手枪元件按手枪1装配（主角肢体素材/手枪 读 unit.手枪_装扮）。
 *   攻击模式 == "手枪2"（含只装备手枪2 与 双持切至手枪2 两种情形）时，改用
 *   「手枪搓招容器-<招式名>2」变体容器（其时间轴内的枪元件两两对调：
 *   手持位 = 手枪2 素材，腰挂位 = 手枪1 素材，手枪1 未装备时腰挂位自动隐藏）。
 *   射击数据两条枪路各自读 手枪属性 / 手枪2属性，但许可另受
 *   __手枪搓招启用枪1/2 旗标收口：单枪模式下未持握的那把枪不开火、不扣弹、不换弹。
 *
 * 释放路由（2026-11-18 消失卡住修复）：
 *   不在状态机 onEnterFrame 内同步 状态改变("技能") + attach——与空手攻击路由
 *   同构，改走 RoutingIntent.triggerStateTransitionJob：job 回调在
 *   StateTransition.apply 的 gotoAndStop("容器") 之后统一执行，attach 拿到的
 *   unit.container 才是容器帧占位；同帧旧 man 的卸载回调由 suppressOldManUnload
 *   压掉。attach 后不再 gotoAndPlay——容器首帧即招式段（与 技能容器-* 一致），
 *   末帧自带 _root.技能路由.动画完毕(this,_parent) 收尾。
 *
 * 返回码（沿用雾人约定）：
 *   0  = 未执行（条件不满足或没搓上，调用方继续原状态机逻辑）
 *   2  = 电平裁决执行
 */

// ============================================================================
// 指令表
//   顺序即判定优先级：Shift 修饰招必须排在单方向之前，
//   否则 shift前/shift后 会被「前」抢走。
// ============================================================================

_root.技能函数.手枪搓招表 = [
	{技能: "后跳射击", 键: "shift后"},
	{技能: "前冲射击", 键: "shift前"},
	{技能: "后射",     键: "后"},
	{技能: "瞬踢追射", 键: "前"},
	{技能: "后撩上射", 键: "上"},
	// 裸按K（换弹打击）：无方向门槛，靠表尾顺序保证最低优先级 ——
	// 学习后裸按K一律出换弹打击，不再落回普通站姿射击（2026-11-24 用户裁定）。
	{技能: "换弹打击", 键: "无"}
];

// 后键意图窗口（帧）：30fps 下 12 帧 ≈ 400ms。
// 行走公共体会在按住反方向键的下一帧把 方向 翻过去（Shift+← 后 ← 变成「前」），
// 所以「后」必须在按键按下的那一帧（朝向尚未翻转时）记录下来，
// 再给 B 一个窗口去消费；否则后跳射击只能在「← 与 B 同帧」时搓出。
_root.技能函数.手枪搓招后键窗口 = 12;

// 回射（后射）2026-11-21 重铸备注：
//   曾加 20 蓝耗 + 3 秒冷却，实测未生效，已按用户决定移除 —— 回射当前无蓝耗无冷却。
//   其余三招（后跳/前冲/瞬踢追射）同样无蓝耗无冷却，但已取消自动换弹（弹匣打空即停火，需手动换弹）。

// ============================================================================
// 射击节奏：2026-11-26 起「完全照搬 技能容器-死亡绽放」的比率与实现方式。
// 间隔帧不再由本入口按 weapontype 查表注入，而是由各容器帧 1 脚本用绽放公式逐枪计算：
//   枪1：间隔帧 = floor((interval + 20) * 0.7 * 30 / 1000)，枪2：floor((interval + 10) * 0.8 * 30 / 1000)，下限 1。
//   间隔帧 ≤ 3 且弹种不含「横向」的枪转纵向联弹：霰弹值 ×ceil(5/帧)、弹种加「纵向联弹-」前缀、
//   间隔帧固定 5（与绽放容器一致）。
//   弹数记账（2026-11-27 三次裁定）：只有霰弹枪 1 扳机 = 1 发（联弹弹丸免费，原版口径）；
//   其余枪类（冲锋枪/手枪/特殊/发射器等）联弹多少发就扣多少发 —— 容器帧1算好「单发消耗」
//   （霰弹枪=1，其余=联弹后的霰弹值），本入口注入 __手枪搓招弹丸免费1/2 供容器读取。
//   弹夹容量保持真实弹数；不折算、卸载不乘回。任何跨释放的单位折算都会让 shot 单位翻转，
//   冲锋枪扣弹指数级膨胀且几乎不吐子弹，一律废弃。
// 发数只由「间隔帧 + 动画射击窗口 + 弹夹容量」收束，weapontype 封顶全部移除
// （特殊武器只射 1 发、压制机枪减半两条旧削弱一并撤销，按用户 2026-11-26 裁定）。
// 唯一保留的封顶：后射 / 换弹打击（回射比例两招）走「最低档」——冲锋枪类 3 发、其余武器 1 发。
//
// 参数兼容两种来源：枪名 String（手枪配置写的就是名字）或 {name:...} 物品对象。
// ============================================================================
_root.技能函数.手枪搓招枪类型 = function(枪:Object):String {
	var 枪名:String = "";
	if (枪 != undefined && 枪 != null) {
		if (typeof 枪 == "string") 枪名 = String(枪);
		else if (枪.name != undefined) 枪名 = String(枪.name);
	}
	if (枪名 == "" || 枪名 == "undefined") return "";
	var 条目:Object = _root.getItemData(枪名);
	if (条目 != undefined && 条目.weapontype != undefined) return String(条目.weapontype);
	return "";
};

// 弹丸免费判定（2026-11-27 裁定）：只有霰弹枪 1 发子弹打出一串纵向联弹，
// 其余枪类每颗弹丸都要扣弹。容器帧1据此算「单发消耗」。
_root.技能函数.手枪搓招弹丸免费 = function(枪:Object):Boolean {
	return _root.技能函数.手枪搓招枪类型(枪) == "霰弹枪";
};

_root.技能函数.手枪搓招枪类型 = function(枪:Object):String {
	var 枪名:String = "";
	if (枪 != undefined && 枪 != null) {
		if (typeof 枪 == "string") 枪名 = String(枪);
		else if (枪.name != undefined) 枪名 = String(枪.name);
	}
	if (枪名 == "" || 枪名 == "undefined") return "";
	var 条目:Object = _root.getItemData(枪名);
	if (条目 != undefined && 条目.weapontype != undefined) return String(条目.weapontype);
	return "";
};

_root.技能函数.手枪搓招发数上限 = function(枪:Object, 是否后射:Boolean, 技能名:String):Number {
	// 2026-11-26：射速/联弹/发数已完全交给容器的绽放公式与动画窗口，本函数只负责
	// 「后射 / 换弹打击 两招放最低档」这一条：冲锋枪类 3 发，其余武器 1 发。
	// 其余四招一律返回 0（不封顶），发数由「间隔帧 + 窗口 + 弹夹」自然收束。
	if (是否后射 != true) return 0;
	var 类型:String = _root.技能函数.手枪搓招枪类型(枪);
	var 冲锋枪:Boolean = (类型 == "冲锋枪" || 类型 == "突击步枪"
		|| 类型 == "压制冲锋枪" || 类型 == "压制机枪");
	return 冲锋枪 ? 3 : 1;
};

// ============================================================================
// 方向判定
// ============================================================================

/**
 * 是否按住朝向后方（黑猫表的 _方向命中 没有 shift后，这里补齐自己的一套）。
 */
_root.技能函数._手枪按后 = function(自机:MovieClip):Boolean {
	if (自机.方向 == "右") return 自机.左行 ? true : false;
	return 自机.右行 ? true : false;
};

/**
 * 后键意图是否仍在窗口内。
 * 电平为真（朝向未翻转 / 移动射击锁定朝向）直接算命中；
 * 电平为假但最近 后键窗口 帧内按下过反方向键，也算命中（覆盖「先按方向、后按 B」）。
 *
 * 换向竞态冷却（2026-11-21 串招修复）：行走公共体在按下反方向键的下一帧才翻转朝向，
 * 朝左跑按 → 的瞬间（朝向还是左）→ 会被电平判成「后键」。移动中记下的沿
 * （__手枪后键移动沿）在头 2 帧内不参与命中 —— 翻转完成后 电平/shift前 语义自动归位。
 */
_root.技能函数._手枪后键有效 = function(自机:MovieClip):Boolean {
	var 按下帧:Number = 自机.__手枪后键帧;
	var 当前帧:Number = _root.帧计时器.当前帧数;
	var 电平命中:Boolean = _root.技能函数._手枪按后(自机);
	var 窗口命中:Boolean = false;
	if (按下帧 != undefined) {
		var 间隔:Number = 当前帧 - 按下帧;
		窗口命中 = (间隔 >= 0 && 间隔 <= _root.技能函数.手枪搓招后键窗口);
	}
	if (!电平命中 && !窗口命中) return false;
	// 移动沿冷却：跑动/行走中记下的后键沿，头 2 帧不算（等行走翻转完成）
	if (自机.__手枪后键移动沿 == true && 按下帧 != undefined
		&& (当前帧 - 按下帧) < 2) return false;
	return true;
};

/**
 * 每帧采样水平方向键，在「新按下」的那一帧记录后键意图。
 *
 * 行走公共体在按住反方向键的下一帧就把 方向 翻过去（Shift+← 之后 ← 变成「前」），
 * 所以后键电平只在按下那一帧可信。这里按「物理按键沿」记：
 *   · 按下或换到另一个水平键 → 用当前朝向判一次后键，记录帧号（不是后键则清空）
 *   · 松开全部水平键 → 复位键码，允许再次按同一键重新判定
 * 这样「先点←、再按→+Shift+B」按新沿清空，不会误吃后跳。
 */
_root.技能函数._取消手枪后键输入 = function(自机:MovieClip):Void {
    delete 自机.__手枪方向键码;
    delete 自机.__手枪方向按下序;
    delete 自机.__手枪后键帧;
    delete 自机.__手枪后键方向;
    delete 自机.__手枪后键移动沿;
};

_root.技能函数._手枪后键采样 = function(自机:MovieClip):Void {
	var 键码:String = 自机.左行 ? "左" : (自机.右行 ? "右" : null);
	if (键码 == null) {
		自机.__手枪方向键码 = null;
		return;
	}
	var input:Object = _root.GameInput;
	var press:Number = 0;
	if (input.passiveActive === true) {
		press = input.getActorPress(自机, 键码 == "左" ? 自机.左键 : 自机.右键);
		if (press == 0) return;
	}
	if (键码 != 自机.__手枪方向键码 || press !== 自机.__手枪方向按下序) {
		自机.__手枪方向键码 = 键码;
		自机.__手枪方向按下序 = press;
		var 是后键:Boolean = _root.技能函数._手枪按后(自机);
		自机.__手枪后键帧 = 是后键 ? _root.帧计时器.当前帧数 : undefined;
		// 后键按下这一帧 方向 还没被 行走 翻转，把此时的朝向存下来：
		// 后跳射击要用它把人物转回原朝向（按住 ← 之后行走已经把人物转过去了）。
		自机.__手枪后键方向 = 是后键 ? 自机.方向 : undefined;
		// 移动沿标记：跑动/行走中按下的后键沿多半是换向意图（朝向下一帧才翻转），
		// 头 2 帧内不参与后键命中（见 _手枪后键有效 的换向竞态冷却）。
		自机.__手枪后键移动沿 = 是后键 ? _root.技能函数._手枪是否移动中(自机) : undefined;
	}
};

/**
 * 是否处于移动状态（手枪搓招六状态中的行走/跑四种）。站立返回 false。
 */
_root.技能函数._手枪是否移动中 = function(自机:MovieClip):Boolean {
	var 状态:String = 自机.状态;
	return (状态 == "手枪行走" || 状态 == "手枪跑"
		|| 状态 == "手枪2行走" || 状态 == "手枪2跑");
};

/**
 * 前冲的奔跑修饰：Shift 电平 或 双击方向奔跑生效中。
 * 双击跑玩家按住奔跑键是 false，只认 Shift 会让跑动中 →+B 漏到瞬踢追射。
 */
_root.技能函数._手枪前冲奔跑修饰 = function(自机:MovieClip):Boolean {
	if (自机.按住奔跑键) return true;
	var dir:Number = 自机.doubleTapRunDirection;
	if (dir == undefined || dir == 0) return false;
	return (dir < 0) ? 自机.左行 : 自机.右行;
};

/**
 * 帧检查用的方向判定。键取值：shift前 / shift后 / 前 / 后 / 上 / 无。
 *
 * 修饰域隔离（2026-11-21 串招修复）：
 *   shift前 的修饰 = Shift 电平 或 双击奔跑生效（双击跑玩家也能出前冲）；
 *   shift后 的修饰 = Shift 电平（双击跑不扩展，避免跑动 ←+B 被后跳抢判）；
 *   前（瞬踢）/ 后（后射）只在非 Shift 域判定 —— 按住奔跑键时这两种单方向招
 *   一律放行给 shift 招，杜绝 shift 招判定失败时顺位漏到单方向招。
 *   后（后射）额外排除移动沿：跑动中按下的后键是换向意图，不是回射指令。
 *
 * shift 判定用 按住奔跑键 而不是 强制奔跑：后者在按了 A/B/C 的同帧被压成 false，
 * 而手枪搓招恰恰要在按住 B 的那一帧成立。
 */
_root.技能函数._手枪方向命中 = function(自机:MovieClip, 键:String):Boolean {
	if (键 == "shift前") return (_root.技能函数._手枪前冲奔跑修饰(自机) && _root.技能函数._按前(自机)) ? true : false;
	if (键 == "shift后") return (自机.按住奔跑键 && _root.技能函数._手枪后键有效(自机)) ? true : false;
	if (键 == "后")      return (!自机.按住奔跑键 && 自机.__手枪后键移动沿 != true
		&& _root.技能函数._手枪后键有效(自机)) ? true : false;
	if (键 == "前")      return (!自机.按住奔跑键 && _root.技能函数._按前(自机));
	// 上（后撩上射）：竖直方向电平，与 持枪行走 的上行键一致（空手搓招同款判据）
	if (键 == "上")      return 自机.上行 ? true : false;
	// 无（换弹打击）：裸按K，无方向门槛；最低优先级由搓招表尾顺序保证
	if (键 == "无")      return true;
	return false;
};

/**
 * 后向招式（后跳射击 / 后射）：把朝向转回「按下后键之前」的朝向。
 *
 * 行走公共体在按住反方向键的下一帧就 方向改变(反方向)（移动射击未锁朝向时），
 * 所以 ←（或 →）搓出来的后向招式往往是在人物已经转身之后才释放的 ——
 * 表现就是「释放中转身」。后键按下那一帧的朝向存在 __手枪后键方向，
 * 这里在释放前转回去，再交给 锁定方向 保持到技能结束：
 *   后跳射击 = 保持原朝向、朝身后位移、枪口朝前开火；
 *   后射     = 保持原朝向、原地不动、枪口朝后开火（回射不转身）。
 */
_root.技能函数._手枪后向朝向回正 = function(自机:MovieClip):Void {
	var 目标方向:String = 自机.__手枪后键方向;
	if (目标方向 == undefined || 目标方向 == 自机.方向) return;
	// 方向改变 自带 锁定方向 门，这里临时让开再原样收回（只收回自己的锁）
	var 原锁:Object = 自机.锁定方向;
	自机.锁定方向 = false;
	自机.方向改变(目标方向);
	自机.锁定方向 = 原锁;
};

// ============================================================================
// 门槛与释放
// ============================================================================

/**
 * 手枪搓招总门槛：模式 + 装备。通过返回 true。
 */
_root.技能函数.手枪搓招模式允许 = function(自机:MovieClip):Boolean {
	// 手枪模式：只装备手枪1（攻击模式=手枪）或手枪2（攻击模式=手枪2）；双枪不参与
	if (自机.攻击模式 != "手枪" && 自机.攻击模式 != "手枪2") return false;
	// 装备门：手枪1 或 手枪2 至少一把有效（power > 0）
	var 有手枪1:Boolean = (自机.手枪属性 != undefined && 自机.手枪属性.power > 0);
	var 有手枪2:Boolean = (自机.手枪2属性 != undefined && 自机.手枪2属性.power > 0);
	return 有手枪1 || 有手枪2;
};

/**
 * 单招学习门槛：学过（等级>=1）且面板「启用」。未学过返回 false（放行 B，不吞键）。
 */
_root.技能函数.手枪搓招已学习 = function(自机:MovieClip, 技能名:String):Boolean {
	var 技能 = 自机.被动技能[技能名];
	// 与空手搓招同一口径：Number(等级) + 被动技能启用 归一裁判（兼容旧档 1/"1"/"true"）
	if (!技能 || Number(技能.等级) < 1) return false;
	if (!_root.技能函数.被动技能启用(技能)) return false;
	return true;
};

/**
 * 状态切换作业回调（module-level named function）：进入"容器"帧后挂载手枪搓招容器。
 * 结构对齐 空手攻击路由.__job_载入后跳转 / 技能路由.载入后跳转技能容器。
 * 变体名经 unit.__手枪搓招容器名 传递（create 后写入，execute 后由 StateTransition 清回调）。
 */
_root.技能函数.__job_挂载手枪搓招容器 = function(u:MovieClip):Void {
	var scope:Object = u.__手枪搓招输入;
	delete u.__手枪搓招输入;
	var input:Object = _root.GameInput;
	if (input.passiveActive === true && (scope == null || !input.isCurrentActor(u)
			|| scope.actor !== u.__cf7InputIdentity || !input.isInputCurrent(scope.epoch, scope.cancelSerial, scope.configInc)
			|| scope.gun1 !== u.手枪 || scope.gun2 !== u.手枪2)) {
		org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle.recoverMissingSkillContainer(u);
		return;
	}
	var 容器名:String = u.__手枪搓招容器名;
	var initObj:Object = org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle.buildPublicContainerInit(u.container);
	var attachResult:Object = org.flashNight.arki.unit.UnitComponent.Routing.ContainerAttachAction.attach(
		u,
		org.flashNight.arki.unit.UnitComponent.Routing.ContainerSpec.KIND_PISTOL_SKILL,
		容器名,
		initObj
	);
	if (attachResult.status !== org.flashNight.arki.unit.UnitComponent.Routing.ContainerAttachAction.STATUS_OK) {
		// 容器缺失：按技能容器的兜底语义立即退出空容器状态
		org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle.recoverMissingSkillContainer(u);
		return;
	}
	var man:MovieClip = attachResult.man;
	org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle.handleFloat(man, u, "技能浮空");
	org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle.bindEndCleanup(man, u, "战技", "技能结束", "技能浮空");

	// ── 朝向守卫（用户反馈：后射打完朝向像被翻过去）─────────────────────────
	// 技能演出全程禁止改朝向，结束（man 卸载）时按快照还原 —— 保证「任何时刻朝向都不变」。
	// 与 Cf6TraversalService / Cf6VehicleActorAdapter 的 锁定方向 快照-还原同一约定：
	// 只收回自己上的锁，别人的锁值原样写回；方向/缩放也一并回写快照。
	// （必须放在 bindEndCleanup 之后：让它的 onUnload 先跑完状态收尾，再做朝向还原。）
	var 原锁存在:Boolean = (u.锁定方向 !== undefined);
	var 原锁值:Object = u.锁定方向;
	var 原方向:String = u.方向;
	var 原Xscale:Number = u._xscale;
	// 人物文字信息跟着 方向改变 一起翻转（-100/100），还原时一并回写
	var 原文字X:Number = (u.新版人物文字信息 != undefined) ? u.新版人物文字信息._xscale : undefined;
	u.锁定方向 = true;
	var 原卸载:Function = man.onUnload;
	man.onUnload = function():Void {
		if (原卸载 != undefined) 原卸载.apply(this);
		if (原锁存在) u.锁定方向 = 原锁值;
		else delete u.锁定方向;
		if (原方向 != undefined && u.方向 != 原方向) {
			u.方向 = 原方向;
			if (原Xscale != undefined && !isNaN(原Xscale)) u._xscale = 原Xscale;
			if (原文字X != undefined && u.新版人物文字信息 != undefined) {
				u.新版人物文字信息._xscale = 原文字X;
			}
		}
	};

	// 容器首帧即招式段（label 在帧 1），与 技能容器-* 相同从帧 1 自动播放，无需 gotoAndPlay。
	// AI 事件：技能释放开始（对齐 技能路由.技能标签跳转_旧）
	if (u.dispatcher != undefined && u.dispatcher != null) {
		u.dispatcher.publish("skillStart", u, u.技能名);
	}
};

/**
 * 释放路由：进入技能容器状态并挂载 手枪搓招容器。
 *
 * 与 空手攻击路由.空手攻击标签跳转 同构：
 *   suppressOldManUnload → triggerStateTransitionJob(状态"技能", "容器", __job_挂载手枪搓招容器)
 *   job 回调由 StateTransition.apply 的 executeStateTransitionJob 在 gotoAndStop("容器") 后执行。
 *
 * @param 自机     执行单位
 * @param 技能名   招式名（skills.xml Name，同时是容器帧标签）
 * @return:Boolean 是否成功提交释放
 */
_root.技能函数.手枪搓招标签跳转 = function(自机:MovieClip, 技能名:String):Boolean {
	// 技能等级写入单位（容器射击逻辑按 1.2 + 技能等级 * 0.1 缩放子弹威力）
	var 技能 = 自机.被动技能[技能名];
	自机.技能名 = 技能名;
	自机.技能等级 = Math.max(Number(技能.等级), 1);

	// 手枪2 变体选择（2026-11-27 键3切枪配套）：手持手枪2 时挂「手枪搓招容器-<名>2」变体容器，
	// 覆盖两种情形：只装备手枪2（旧行为，此时攻击模式必为「手枪2」）与 双持切换至手枪2 模式
	var 有手枪1:Boolean = (自机.手枪属性 != undefined && 自机.手枪属性.power > 0);
	var 有手枪2:Boolean = (自机.手枪2属性 != undefined && 自机.手枪2属性.power > 0);
	var variantSuffix:String = (自机.攻击模式 == "手枪2" && 有手枪2) ? "2" : "";
	自机.__手枪搓招容器名 = 技能名 + variantSuffix;
	// 单枪路收敛：双持切至 手枪/手枪2 模式后，容器只允许所选手枪那一路开火——
	// 另一把枪不吐弹、不扣弹、不换弹（绝不允许未持握的枪开火）。许可旗标由容器帧 1 消费。
	自机.__手枪搓招启用枪1 = (自机.攻击模式 == "手枪") && 有手枪1;
	自机.__手枪搓招启用枪2 = (自机.攻击模式 == "手枪2") && 有手枪2;

	// 射击节奏（2026-11-26「完全照搬死亡绽放」）：间隔帧与联弹由各容器帧 1 脚本自行按枪的
	// interval / split / bullet 计算，入口不再注入间隔帧；发数由「间隔帧 + 动画窗口 + 弹夹」收束。
	// 入口只注入「后射 / 换弹打击 最低档」封顶（冲锋枪类 3 发、其余 1 发），其余四招注入 0（不封顶）。
	//   后射（窗口 3..11）/ 换弹打击（窗口 5..7）：最低档；
	//   后跳·前冲（3..14）、瞬踢追射（8..15）、后撩上射（10..16）：按绽放节奏铺满窗口。
	// 双枪各自按自己的枪算，容器帧 1 直接读枪属性、帧 2 读发数上限。
	var 是否后射:Boolean = (技能名 == "后射" || 技能名 == "换弹打击");
	自机.__手枪搓招发数1 = _root.技能函数.手枪搓招发数上限(自机.手枪, 是否后射, 技能名);
	自机.__手枪搓招发数2 = _root.技能函数.手枪搓招发数上限(自机.手枪2, 是否后射, 技能名);
	// 弹丸免费标记：只有霰弹枪 1 扳机 1 发，其余枪类联弹发数全扣（2026-11-27 裁定）
	自机.__手枪搓招弹丸免费1 = _root.技能函数.手枪搓招弹丸免费(自机.手枪);
	自机.__手枪搓招弹丸免费2 = _root.技能函数.手枪搓招弹丸免费(自机.手枪2);

	// 屏蔽旧 man 卸载回调（时间轴 man 随 gotoAndStop 销毁时不再写状态）
	org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntent.suppressOldManUnload(自机);
	// 对齐 技能路由.技能标签跳转_旧：先归一 temp_y，保证 handleFloat 的浮空判定拿到数字
	org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle.ensureTempY(自机);

	var input:Object = _root.GameInput;
	if (input.passiveActive === true) {
		自机.__手枪搓招输入 = {actor:自机.__cf7InputIdentity, epoch:input.getKeyboardEpoch(),
			cancelSerial:input.cancelSerial, configInc:input.configInc, gun1:自机.手枪, gun2:自机.手枪2};
	}
	// 与空手路由同构：job 里带 forceGotoLabel="容器"，回调在 gotoAndStop 后执行
	org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntent.triggerStateTransitionJob(
		自机,
		"技能",
		org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntent.LABEL_CONTAINER,
		_root.技能函数.__job_挂载手枪搓招容器,
		org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntent.LABEL_CONTAINER
	);
	return true;
};

// ============================================================================
// 派发入口（由 持枪行走状态机 顶部调用，显式收单位）
// ============================================================================

/**
 * @param 自机 手枪站立/行走/跑状态下的单位
 * @return Number 0=未执行；2=已释放（调用方立即 return，本帧不再跑原状态机逻辑）
 */
_root.技能函数.手枪搓招检查 = function(自机:MovieClip):Number {
	if (自机 == undefined || 自机 == null) return 0;
	// 只对控制目标生效（AI 没有输入序列）
	if (自机._name != _root.控制目标) return 0;

	var input:Object = _root.GameInput;
	var passive:Boolean = input.passiveActive === true;
	var press:Number = passive ? input.getActorPress(自机, 自机.B键) : 0;
	if (passive && (!input.isInputAdmitted() || !input.isCurrentActor(自机))) return 0;
	if (!passive && !自机.动作B) delete 自机.__手枪搓招B已消费;

	// 后键意图采样（必须每帧跑，且在 行走() 翻转朝向前记录）
	_root.技能函数._手枪后键采样(自机);

	// 模式 + 装备门槛（未过 → B 交回原状态机行为）
	if (!_root.技能函数.手枪搓招模式允许(自机)) return 0;
	// 必须按着 B
	if (!自机.动作B) return 0;
	// 同一次按下只尝试一次
	if (passive ? (press == 0 || press <= 自机.__comboBPressConsumed) : 自机.__手枪搓招B已消费) return 0;

	var 表:Array = _root.技能函数.手枪搓招表;
	for (var i:Number = 0; i < 表.length; i++) {
		// 先判学习门槛再判方向：未学的招不吞键（B 落回副武器射击等原行为）
		if (!_root.技能函数.手枪搓招已学习(自机, 表[i].技能)) continue;
		if (!_root.技能函数._手枪方向命中(自机, 表[i].键)) continue;

		// 命中：锁存本次按下，清掉旧 DFA 预输入与后键意图（避免同一次输入连出两招）
		if (passive) 自机.__comboBPressConsumed = press;
		else 自机.__手枪搓招B已消费 = true;
		自机.__手枪后键帧 = undefined;
		自机.__手枪后键移动沿 = undefined;
		// 后向招式（后跳射击/后射）：先转回按下后键前的朝向，再释放
		//（否则人物已被行走翻转，表现就是「转身」）
		if (表[i].技能 == "后跳射击" || 表[i].技能 == "后射") {
			_root.技能函数._手枪后向朝向回正(自机);
		}
		自机.__手枪后键方向 = undefined;
		if (typeof _root.技能函数._清预输入 == "function") {
			_root.技能函数._清预输入(自机);
		}

		var 挂载成功:Boolean = _root.技能函数.手枪搓招标签跳转(自机, 表[i].技能);
		delete 自机.__手枪搓招输入;
		if (!挂载成功) {
			// 容器缺失等异常：不吞键，让原状态机逻辑继续跑
			if (passive && 自机.__comboBPressConsumed === press) delete 自机.__comboBPressConsumed;
			else if (!passive) delete 自机.__手枪搓招B已消费;
			return 0;
		}

		// 回射曾试加 20 蓝耗 + 3 秒冷却（2026-11-21），实测门禁不生效，按用户决定移除；
		// 当前回射无蓝耗无冷却。伤害倍率与换弹行为在容器侧，不在此处。

		// WebView2 刘海连击提示（对齐搓招监控协议；触发码 2 = 电平裁决）
		if (typeof _root.技能函数._刘海通知 == "function") {
			_root.技能函数._刘海通知(2, 表[i].技能);
		}
		return 2;
	}
	return 0;
};
