/**
 * 单位函数__技能搓招指令.as
 *
 * 冷兵器主动快捷技能 · 平A后摇搓招（参考 单位函数_雾人_兵器搓招指令.as 的写法）
 *
 * 指令表（8 向归一化，前 = 朝向）：
 *   迅斩     ↑ + B
 *   瞬步斩   → + B
 *   凶斩     ↓ + B
 *   火舞旋风 ↘ + B
 *   拔刀术   Shift + → + B   ← 数据里叫「拔刀术」（skills.xml id=19），没有「拔刀斩」
 *
 *   ⚠ 拔刀术是 Shift 修饰招，**不吃 DFA 名字通道**（原因见 冷兵器主动技能搓招 的 ⓪ 段），
 *     只走方向电平裁决：按住奔跑键（默认 Shift）+ 朝向前 + B。
 *
 * 生效范围：
 *   - 只挂在「冷兵器攻击」的后摇窗口上（兵器攻击容器的 冷兵器攻击搓招 被本文件包一层）
 *   - 只认 攻击模式 == "兵器" 的控制目标，空手 / 长枪 / 双枪 / 手雷 模式不参与
 *   - 技能名必须与 skills.xml 一致，否则 SkillReleaseGuard 查不到会静默失败
 *
 * 释放通道（QuickSkillInputService.releaseBySkillName，双通道）：
 *   - 已装备在 1..12 号槽：走槽通道，与数字键共享 quick:<槽> 冷却与 HUD 冷却条
 *   - 未装备：走 skill:<技能名> 名字通道，成本读 技能表对象[名].MP
 *   - MP 一律由 unit.释放技能 在「释放条件通过之后」扣，本文件不写 unit.mp
 *
 * 返回码沿用雾人约定，另加一个「吞键」码：
 *   0  = 未执行（交回原后摇逻辑，B 仍然是跳跃）
 *   1  = DFA 识别执行
 *   2  = 帧检查执行
 *   -1 = 搓招名字对上了、但这次按下的 B 被技能占用却没放出来
 *        （冷却中 / MP 不足 / 未学会）：调用方不要再跑原后摇逻辑，
 *        免得 后摇可跳跃 把同一帧的 B 变成跳跃，让玩家以为「搓招没识别」。
 *        末帧入口没有可吞的跳转，收到 -1 时按「未执行」处理，动画照常收尾。
 */

// ============================================================================
// 指令表
//   顺序即帧检查兜底优先级：复合方向必须排在单方向之前，
//   否则 ↘/↗ 会被 ↓/↑ 抢走。
// ============================================================================

_root.技能函数.黑猫技能表 = [
	{技能: "火舞旋风", 键: "下前"},
	{技能: "拔刀术",   键: "shift前"},
	{技能: "迅斩",     键: "上"},
	{技能: "瞬步斩",   键: "前"},
	{技能: "凶斩",     键: "下"}
];

// 预输入窗口（帧）。DFA 命中后名字默认只活 bufferTolerance+1 帧（约 6 帧），
// 而平A每段只有 4 帧的判定窗口、段间隔 11~15 帧，掐不准就错过。
// 这里用帧计时器不清空的 搓招缓冲名/搓招缓冲帧 做长缓冲：
// 只要命中发生在最近 预输入帧数 帧内，后摇窗口一到就消费。
// 30fps 下 30 帧 ≈ 1 秒：够覆盖「攻击前摇就开始搓、第一段窗口就放」，
// 又不至于站着随手按一下、一秒后才莫名其妙出招。觉得紧就调到 36~45。
_root.技能函数.黑猫预输入帧数 = 30;

// ============================================================================
// 小工具
// ============================================================================

/**
 * 是否按住朝向前方。方向归一化后与 DFA 的 FORWARD 同义。
 */
_root.技能函数._按前 = function(自机:MovieClip):Boolean {
	if (自机.方向 == "右") return 自机.右行 ? true : false;
	return 自机.左行 ? true : false;
};

/**
 * 帧检查兜底用的方向判定。键取值：下前 / shift前 / 上前 / 上 / 前 / 下。
 *
 * shift前 = 按住奔跑键（默认 Shift）+ 朝向前。
 * 注意用 按住奔跑键 而不是 强制奔跑：后者在按了 A/B/C 的同帧被压成 false，
 * 而拔刀术恰恰要在按住 B 的那一帧成立。
 */
_root.技能函数._方向命中 = function(自机:MovieClip, 键:String):Boolean {
	if (键 == "下前") return (自机.下行 && _root.技能函数._按前(自机)) ? true : false;
	if (键 == "shift前") return (自机.按住奔跑键 && _root.技能函数._按前(自机)) ? true : false;
	if (键 == "上前") return (自机.上行 && _root.技能函数._按前(自机)) ? true : false;
	if (键 == "上")   return 自机.上行 ? true : false;
	if (键 == "前")   return _root.技能函数._按前(自机);
	if (键 == "下")   return 自机.下行 ? true : false;
	return false;
};

/**
 * WebView2 刘海连击提示（与 搓招监控 同一协议；这里显式传单位，不依赖 _parent）。
 */
_root.技能函数._刘海通知 = function(触发码:Number, 招式名:String):Void {
	if (触发码 <= 0) return;
	var sm:Object = _root.server;
	if (sm != undefined && sm.isSocketConnected) {
		var color:String = (触发码 == 1) ? "ffd700" : "66ccff";
		var tag:String = (触发码 == 1) ? "DFA" : "Sync";
		sm.sendSocketMessage("Ncombo|" + color + "|" + tag + " " + 招式名);
	}
};

/**
 * 技能已经把单位推进「技能」状态，旧的后摇容器本帧还有一句 变招判定 要跑。
 * 它看到 动作B 会 状态改变("兵器跳")、看到方向会 动画完毕()，都会把刚放的技能顶掉。
 * 输入每帧由 Key.isDown 重建，所以只让位本帧即可。
 * （这 5 个技能容器首帧都不读方向/AB，让位不会影响它们自身的取景逻辑。）
 */
_root.技能函数._本帧输入让位 = function(自机:MovieClip):Void {
	自机.动作A = false;
	自机.动作B = false;
	自机.左行 = false;
	自机.右行 = false;
	自机.上行 = false;
	自机.下行 = false;
};

/**
 * 一次输入只判定一次：无论成功失败，都把这条 DFA 结果清干净，
 * 免得 4 帧后摇窗口里每帧重试（MP 不足会连刷提示、冷却中会连查 12 个槽）。
 */
_root.技能函数._清预输入 = function(自机:MovieClip):Void {
	自机.搓招缓冲ID = 0;
	自机.搓招缓冲名 = "";
	自机.搓招缓冲已消费 = true;
	自机.搓招缓冲修饰键 = false;
	自机.当前搓招ID = 0;
	自机.当前搓招名 = "";
};

// ============================================================================
// 释放
// ============================================================================

_root.技能函数._技能释放 = function(自机:MovieClip, 技能名:String, 触发码:Number):Number {
	// 同一次按下 B 只尝试一次：后摇窗口跨多帧，避免重复入栈/反复起冷却。
	// 锁存期间一律返回 -1：B 还按着就继续吞，松开（见 冷兵器主动技能搓招 的复位）才会重新判定。
	if (自机.__黑猫技能B已消费) return -1;
	自机.__黑猫技能B已消费 = true;

	// 双通道释放：已装备走槽（含 MP 事务 / 冷却 / HUD），未装备走名字通道。
	// 判定为「不可释放」（未学会、数据缺失、冷却中、MP 不足、条件不满足）时返回 -1，
	// 由调用方吞掉这次 B —— 不再回落成跳跃，冷却/MP 状态交给冷却条显示。
	var 结果:Object = QuickSkillInputService.releaseBySkillName(自机, 技能名, 自机.B键);
	if (结果 == null || 结果.released !== true) return -1;

	// 旧容器本帧的同帧跳转保护 + 输入让位
	RoutingIntent.markWeaponSameFrameJump(自机, _root.帧计时器.当前帧数);
	_root.技能函数._本帧输入让位(自机);
	_root.技能函数._刘海通知(触发码, 技能名);
	return 触发码;
};

// ============================================================================
// 派发（由 冷兵器攻击搓招 包装层调用，显式收单位，不读 _parent）
// ============================================================================

/**
 * @param 窗口帧数      DFA 缓冲名的接受窗口；不传则用 黑猫预输入帧数
 * @param 末帧窗口帧数  仅末帧通道使用，比 窗口帧数 更宽松（演出后半段搓好的也认）
 * @param 技能末帧      技能容器末帧来的调用：放宽「攻击模式 == 兵器」这道门，
 *                      让被动技能 / 主动技能演出末尾也能接下一招
 */
_root.技能函数.冷兵器主动技能搓招 = function(自机:MovieClip, 窗口帧数, 末帧窗口帧数, 技能末帧:Boolean):Number {
	if (自机 == undefined || 自机 == null) return 0;
	if (自机._name != _root.控制目标) return 0;

	// B 松开后复位锁存。放在模式门之前：切到空手/长枪/手枪时也能复位，
	// 否则锁存会一路带到切回冷兵器之后的第一次按键（那一下会被白吞）。
	if (!自机.动作B) {
		delete 自机.__黑猫技能B已消费;
	}

	// 模式门。武器类招式（平A / 冷兵器招式）要求「兵器」模式；
	// 技能容器末帧来的那次显式放行 —— 技能由 状态改变("技能") 进入，
	// 攻击模式仍是兵器，但个别技能会改写模式，且被动技能根本不需要持刀。
	if (自机.攻击模式 != "兵器" && 技能末帧 !== true) return 0;

	// 预输入窗口：默认沿用平A后摇的 黑猫预输入帧数；
	// 招式容器末帧可传更大的窗口（招式演出可能比平A一段长得多）。
	var 窗口:Number = _root.技能函数.黑猫预输入帧数;
	if (窗口帧数 != undefined && 窗口帧数 != null && !isNaN(Number(窗口帧数))) {
		窗口 = Number(窗口帧数);
	}

	var 表:Array = _root.技能函数.黑猫技能表;

	// Shift 修饰招的技能名（表里唯一一条 键=="shift前"），后面两处都要用
	var shift技能:String = "";
	for (var s:Number = 0; s < 表.length; s++) {
		if (表[s].键 == "shift前") { shift技能 = 表[s].技能; break; }
	}

	// ⓪ Shift 修饰变招必须抢在名字通道之前判（拔刀术 = Shift + 前 + B）
	//
	//    为什么不能只靠 DFA：采样器每帧先发方向事件、再发 Shift 组合事件
	//    （input-sampler.ts:84-110），所以按住 Shift+→ 时事件序列是
	//      [FORWARD, SHIFT_HOLD, SHIFT_FORWARD]
	//    TrieDFA 没有「失败回根」的语义（trie-dfa.ts:56），root 的 FORWARD 边
	//    会先把状态放到「瞬步斩」分支，SHIFT_FORWARD 边永远走不到；此时按 B，
	//    B_PRESS 正好落在 FORWARD 分支的接受态上 → 名字通道会误判成瞬步斩。
	//    所以 shift 变招一律用方向电平裁决，且排在名字通道前面。
	if (shift技能 != "" && 自机.动作B && _root.技能函数._方向命中(自机, "shift前")) {
		_root.技能函数._清预输入(自机);
		return _root.技能函数._技能释放(自机, shift技能, 2);
	}

	// ① DFA 名字优先：先判名字再判按键电平（快速点按 B 时，cmdName 到手时 B 可能已松）
	//    两级来源，逐级放宽：
	//      a) 当前搓招名 —— 只活 bufferTolerance+1 帧（约 6 帧），对应「窗口当帧按」的原始节奏
	//      b) 搓招缓冲名 + 搓招缓冲帧 —— 帧计时器不清这两个字段，用它做长预输入：
	//         攻击前摇/连段途中就把 ↑B 搓好，等后摇窗口出现再自动放
	var 候选名:String = 自机.当前搓招名;
	if (候选名 == undefined || 候选名 == null) 候选名 = "";
	if (候选名 == "") {
		var 缓冲名 = 自机.搓招缓冲名;
		var 缓冲帧 = 自机.搓招缓冲帧;
		// 注意：不能用 搓招缓冲ID 判断 —— 帧计时器在超过 bufferTolerance 后就把 ID 清零，
		// 只把 搓招缓冲名 / 搓招缓冲帧 留着。这里靠 帧差 + 已消费 标记判定。
		if (缓冲名 != undefined && 缓冲名 != null && 缓冲名 != "" &&
			自机.搓招缓冲已消费 !== true &&
			缓冲帧 != undefined && 缓冲帧 != null &&
			(_root.帧计时器.当前帧数 - 缓冲帧) >= 0 &&
			(_root.帧计时器.当前帧数 - 缓冲帧) <= 窗口) {
			候选名 = 缓冲名;
		}
	}

	if (候选名 != "") {
		// Shift 修饰的预输入纠正：攻击前摇里搓 Shift+→+B，DFA 记下来的是「瞬步斩」，
		// 靠 帧计时器 存的 搓招缓冲修饰键 把它换回 shift 变招。
		// 只对我们表里的技能替换，别的招（上+A 之类）一律不动。
		if (shift技能 != "" && 自机.搓招缓冲修饰键 === true && 候选名 != shift技能) {
			for (var t:Number = 0; t < 表.length; t++) {
				if (表[t].技能 == 候选名) { 候选名 = shift技能; break; }
			}
		}
		for (var i:Number = 0; i < 表.length; i++) {
			if (表[i].技能 == 候选名) {
				_root.技能函数._清预输入(自机);
				return _root.技能函数._技能释放(自机, 候选名, 1);
			}
		}
	}

	// ② 同帧帧检查兜底：方向事件是电平式，V8 DFA 每步只容忍 8 帧，按住稍久就回根
	//
	//    末帧通道要额外看 预输入帧数：招式/技能演完后仍在打的人，往往在演出后半段
	//    就把指令搓好了。DFA 那条「当前搓招名」只活约 6 帧，几乎必然错过，所以
	//    这里先用长缓冲消费一次；消费成功后还会再补看一次电平，让「间隔按两下」
	//    能在接出来的那一招落地后继续接下一招，不必等下一帧。
	if (!自机.动作B) return 0;
	for (var q:Number = 0; q < 2; q++) {
		var 本帧出手:Number = 0;
		for (var j:Number = 0; j < 表.length; j++) {
			if (_root.技能函数._方向命中(自机, 表[j].键)) {
				本帧出手 = _root.技能函数._技能释放(自机, 表[j].技能, 2);
				break;
			}
		}
		if (本帧出手 == 0) return 0;
		// -1 = 这次 B 已被占用（冷却/MP/未学会）：吞键，不能再拿同一帧去试下一招
		if (!(本帧出手 > 0)) return 本帧出手;
		if (q == 0) {
			// 刚把这一招接出来，B 仍按住 ⇒ 给同一次按下的第二招一次机会
			delete 自机.__黑猫技能B已消费;
			continue;
		}
		return 本帧出手;
	}

	return 0;
};

// ============================================================================
// 挂载：包一层 冷兵器攻击搓招
//   容器在首帧把 _root.技能函数.冷兵器攻击搓招 拷到自己身上，再以 容器.冷兵器攻击搓招()
//   调用；所以包装层必须用 this 保留调用者（容器），_parent 才是单位。
//   本文件必须在 单位函数_雾人_兵器搓招指令.as 之后 include。
// ============================================================================

if (typeof _root.技能函数.冷兵器攻击搓招 == "function") {
	_root.技能函数.__原冷兵器攻击搓招 = _root.技能函数.冷兵器攻击搓招;

	_root.技能函数.冷兵器攻击搓招 = function():Number {
		var 容器:MovieClip = this;
		var 自机:MovieClip = 容器._parent;

		var r:Number = _root.技能函数.冷兵器主动技能搓招(自机);
		// r != 0 就抢占：1/2 = 技能已放，-1 = 这次 B 被技能占用（冷却/MP/未学会），
		// 两种都不能再跑原逻辑，否则 后摇可跳跃 会立刻把 B 变成跳跃。
		if (r) return r;

		var 原:Function = _root.技能函数.__原冷兵器攻击搓招;
		if (typeof 原 != "function") return 0;

		// AS2 的 Function.call 声明返回 Void，拿不到原函数的 Number 返回值，
		// 所以临时挂到容器上调用：既保留 this=容器 的调用约定，又能取回返回值。
		容器.__原搓招 = 原;
		var 原结果:Number = 容器.__原搓招();
		delete 容器.__原搓招;
		return 原结果;
	};
} else {
	trace("[黑猫技能搓招] 冷兵器攻击搓招 未定义，跳过挂载（检查 include 顺序）");
}

// ============================================================================
// 容器末帧变招：招式演完 → 直接接主动技能
//
//   覆盖面：cold_arms_weapon.xml 里全部招式 + 平A连招，它们的容器末帧
//   （兵器攻击容器-<招式名>.xml / 兵器攻击容器-1连招.xml 等）都只做一件事：
//       _root.兵器攻击路由.动画完毕(this, _parent);
//   这是唯一收口点，所以不必逐个改 40 多个 XFL 资产。
//
//   与「平A后摇窗口」的区别：
//   - 平A后摇：每段只有 4 帧窗口（帧 10-13 / 25-28 / 38-41 / 54-59）
//   - 末帧：招式演完的那一帧判定一次，窗口按 黑猫末帧预输入帧数 放宽，
//     适合「一整套招式打完 → 接迅斩/瞬步斩」这种节奏
// ============================================================================

// 招式容器末帧的预输入窗口（帧）。招式动画普遍比平A一段长，
// 45 帧 ≈ 1.5 秒，覆盖「招式后半段搓好，末帧一到就接上」。
_root.技能函数.黑猫末帧预输入帧数 = 45;

/**
 * 末帧会被丢弃的状态名白名单。
 *
 * 目前只有「兵器跑」—— 贯穿突刺 / 疾影突进 / 飞跃砸击 这三个位移类招式容器，
 * 末帧在 动画完毕 之后还有一句 `_parent.状态改变("兵器跑")`。
 * 只丢这一种，避免把同帧的受击/其它状态切换一起吞掉。
 * 将来若有容器末帧写别的状态，在这里补一行。
 */
_root.技能函数._末帧可屏蔽状态 = {兵器跑: true, 技能中: true};

// 技能容器（被动技能 / 主动技能共用）末帧的预输入窗口。
// 技能演出比平A长得多，45 帧常常不够在「演出后半段」搓好就接上，
// 这里放到 60 帧 ≈ 2 秒。只影响技能容器，不改变平A与冷兵器招式的节奏。
_root.技能函数.黑猫技能末帧预输入帧数 = 60;

/**
 * 只在「本帧」丢弃白名单里的状态改变。
 *
 * 技能已经 状态改变("技能") 进技能容器了，末帧后置的 `状态改变("兵器跑")`
 * 会把刚放出来的技能顶掉。AS2 没法中止帧脚本，所以在单位上包一层：
 * 只在接管帧、且只对白名单状态丢弃，其它时候原样转发。
 */
_root.技能函数._屏蔽本帧状态改变 = function(自机:MovieClip):Void {
	自机.__黑猫接管帧 = _root.帧计时器.当前帧数;
	if (自机.__黑猫状态改变已包装 === true) return;

	var 原:Function = 自机["状态改变"];
	if (typeof 原 != "function") return;

	自机.__黑猫原状态改变 = 原;
	自机["状态改变"] = function(新状态名:String):Void {
		if (this.__黑猫接管帧 == _root.帧计时器.当前帧数 &&
			_root.技能函数._末帧可屏蔽状态[新状态名] === true) return;
		var f:Function = this.__黑猫原状态改变;
		if (typeof f == "function") f.apply(this, [新状态名]);
	};
	自机.__黑猫状态改变已包装 = true;
};

/**
 * 招式容器末帧的技能变招判定。
 *
 * @param man   容器末帧的 `this`（部分容器传的是 Symbol，本函数不使用）
 * @param 自机   容器末帧的 `_parent`（玩家模板单位）
 * @return true = 技能已接管，调用方不要再执行 completeAnimation
 */
_root.技能函数._末帧技能搓招 = function(man:MovieClip, 自机:MovieClip):Boolean {
	if (自机 == undefined || 自机 == null) return false;
	if (自机._name != _root.控制目标) return false;
	if (自机.攻击模式 != "兵器") return false;
	if (自机.倒地) return false;

	// 技能释放会 状态改变("技能") 卸载旧容器；先压掉旧容器的 onUnload，
	// 否则 bindContainerEndState 装的 "UpdateBigSmallState(普攻结束, 兵器攻击结束)"
	// 会把刚进入的技能状态写坏。没放出来再还原。
	var 原卸载:Function = undefined;
	if (自机.man != undefined) 原卸载 = 自机.man.onUnload;
	RoutingIntent.suppressOldManUnload(自机);

	var r:Number = _root.技能函数.冷兵器主动技能搓招(
		自机, _root.技能函数.黑猫末帧预输入帧数, _root.技能函数.黑猫末帧预输入帧数
	);
	// 末帧没有「可吞的跳转」：-1（按了但没放出来）跟 0 一样按未执行处理，
	// 让 completeAnimation 正常收尾，否则容器会停在最后一帧。
	if (!(r > 0)) {
		if (自机.man != undefined && 原卸载 != undefined) {
			自机.man.onUnload = 原卸载;
		}
		return false;
	}

	_root.技能函数._屏蔽本帧状态改变(自机);
	return true;
};

// ============================================================================
// 挂载：包一层 兵器攻击路由.动画完毕
//   本文件在 frame36 执行，此时 引擎_fs_兵器攻击路由.as（frame2）已定义，
//   且所有容器在运行期才调用，包装时机安全。
// ============================================================================

if (_root.兵器攻击路由 != undefined && typeof _root.兵器攻击路由.动画完毕 == "function") {
	_root.技能函数.__原兵器动画完毕 = _root.兵器攻击路由.动画完毕;

	_root.兵器攻击路由.动画完毕 = function(man:MovieClip, 单位:MovieClip):Void {
		// 先判技能变招：命中就由技能接管，不执行 completeAnimation（动画完毕 + 卸载 man）
		if (_root.技能函数._末帧技能搓招(man, 单位)) return;

		var 原:Function = _root.技能函数.__原兵器动画完毕;
		if (typeof 原 != "function") return;
		原.apply(_root.兵器攻击路由, [man, 单位]);
	};
} else {
	trace("[黑猫技能搓招] 兵器攻击路由.动画完毕 未定义，跳过末帧变招挂载");
}

// ── 技能类容器的末帧通道 ──────────────────────────────────────────────────
//
// 「技能类容器」= 主动技能自己的容器（技能容器-凶斩 / -迅斩 …）+ 被动技能容器
// （技能容器-一瞬千击 / -扭转乾坤 …）。它们末帧调的是 _root.技能路由.动画完毕，
// 和平A/冷兵器招式走的 兵器攻击路由 是两条独立入口，所以这里另配一套挂载。
//
// 与兵器招式那一套的差别：
//   · 模式门放宽：显式传 技能末帧=true 给派发器，绕过「攻击模式 == 兵器」。
//     技能容器由 状态改变("技能") 进入，此时 攻击模式 一般仍是兵器，但被动技能
//     可能整个过程中都不是兵器模式，所以不能靠模式判。
//   · 释放条件仍是 _冷兵器技能释放条件（持有冷兵器 + 未倒地）：这是技能的
//     自身门槛，与「从哪儿搓出来」无关，所以被动技能后摇也只能在持刀时接。
//   · 不在这里查操作模式：是不是「来自技能容器」由本函数自己保证（它只挂在
//     技能路由.动画完毕 上），不需要再拿 攻击模式/状态 二次猜。

_root.技能函数._末帧技能容器搓招 = function(man:MovieClip, 自机:MovieClip):Boolean {
	if (自机 == undefined || 自机 == null) return false;
	if (自机._name != _root.控制目标) return false;
	if (自机.倒地) return false;

	var 原卸载:Function = undefined;
	if (自机.man != undefined) 原卸载 = 自机.man.onUnload;
	RoutingIntent.suppressOldManUnload(自机);

	// 第 4 参 技能末帧=true：放行模式门。技能的持刀门槛由释放条件兜。
	var r:Number = _root.技能函数.冷兵器主动技能搓招(
		自机,
		_root.技能函数.黑猫末帧预输入帧数,
		_root.技能函数.黑猫技能末帧预输入帧数,
		true
	);

	// 同兵器版：-1 与 0 一样按未执行处理，让容器正常收尾，否则会卡在末帧。
	if (!(r > 0)) {
		if (自机.man != undefined && 原卸载 != undefined) {
			自机.man.onUnload = 原卸载;
		}
		return false;
	}

	_root.技能函数._屏蔽本帧状态改变(自机);
	return true;
};

if (_root.技能路由 != undefined && typeof _root.技能路由.动画完毕 == "function") {
	_root.技能函数.__原技能动画完毕 = _root.技能路由.动画完毕;

	_root.技能路由.动画完毕 = function(man:MovieClip, 单位:MovieClip, enableDoubleJump:Boolean):Void {
		if (_root.技能函数._末帧技能容器搓招(man, 单位)) return;

		var 原:Function = _root.技能函数.__原技能动画完毕;
		if (typeof 原 != "function") return;
		原.apply(_root.技能路由, [man, 单位, enableDoubleJump]);
	};
} else {
	trace("[黑猫技能搓招] 技能路由.动画完毕 未定义，跳过技能末帧搓招挂载");
}

// ============================================================================
// 释放条件：这 5 个技能只在「冷兵器模式」成立
//   XML 的 <Requirements> 在生产链路没有消费方，门槛只能落在这里。
//   注册后对数字键同样生效，保证「数字键能放 / 搓招不能放」不会出现分歧。
// ============================================================================

_root.技能函数._冷兵器技能释放条件 = function():Boolean {
	if (this.倒地) return false;
	if (this.攻击模式 != "兵器") return false;
	return true;
};

if (_root.技能函数.释放条件 == undefined) _root.技能函数.释放条件 = new Object();
for (var 黑猫表索引:Number = 0; 黑猫表索引 < _root.技能函数.黑猫技能表.length; 黑猫表索引++) {
	_root.技能函数.释放条件[_root.技能函数.黑猫技能表[黑猫表索引].技能] = _root.技能函数._冷兵器技能释放条件;
}

// ============================================================================
// 冷兵器技能冷却面板（AS2 自绘）
//
//   数据：本段的 冷技能HUD快照 是唯一权威（未学会的技能不入表、暂停返回空表）。
//   渲染：见文件末尾「自绘面板」段 —— 每格纯色白底 + 黑色外框，贴在
//         「快捷技能栏」正上方，格内只写技能名，不再画搓招指令提示。
//   原生 C# 的 coldSkills 组已下线（PlayerHudService.readColdSkills 返回空），
//   避免两套 UI 同时出现。
//
//   本段只做纯读投影：不写冷却、不扣 MP、不改状态。
// ============================================================================

/**
 * 技能当前该读哪个冷却通道。与 QuickSkillInputService.releaseBySkillName 的
 * 双通道裁决同口径：装在 1..12 号槽走 quick:<槽>（与数字键共用冷却），
 * 未装备走 skill:<名>。
 */
_root.技能函数.冷技能冷却键 = function(技能名:String):String {
	for (var i:Number = 1; i <= 12; i++) {
		if (String(_root["快捷技能栏" + i]) == 技能名) return "quick:" + i;
	}
	return "skill:" + 技能名;
};

// 指令键 → 提示文本（C# 侧原样画在格子顶部）
_root.技能函数.冷技能键位 = {
	上: "↑B", 下: "↓B", 前: "→B", 下前: "↓↘B", 上前: "↑↗B", shift前: "⇧→B"
};

// 复用缓冲：每帧不新建这几个数组
_root.技能函数.冷技能_HUD键 = [];
_root.技能函数.冷技能_HUD值 = [];
_root.技能函数.冷技能_HUD名 = [];
_root.技能函数.冷技能_HUD键位 = [];

/**
 * 冷兵器主动技能的 HUD 投影。返回可直接 JSON 化的行数组：
 *   [{name:"迅斩", key:"↑B", ready:true, current:0, total:0, blocked:false}, ...]
 *
 * - **未学会的技能不入表** ⇒ C# 侧天然不显示（「未学会不显示」的唯一权威）。
 * - current / total 是 ManualCooldownService 的步（≈33.33ms/步），与既有
 *   cooldowns 组同一口径，C# 复用 PlayerHudCooldownText 格式化。
 * - blocked = 已就绪但 MP 不够（C# 画红字/红边）。
 * - 暂停（面板、对话）时返回空表，原生面板随之隐藏。
 *
 * 注意：行对象每帧新建而不是就地改。addGroup 用 sameProjection 做变更检测，
 * 若复用同一批对象，上一次快照会被就地改掉，永远比不出差异（永不下发）。
 */
_root.技能函数.冷技能HUD快照 = function(单位:Object):Array {
	var 表:Array = _root.技能函数.黑猫技能表;
	if (表 == null) return [];
	if (_root.暂停 === true) return [];

	var 查等级:Function = _root.根据技能名查找主角技能等级;
	if (typeof 查等级 != "function") return [];

	var 键:Array = _root.技能函数.冷技能_HUD键;
	var 名表:Array = _root.技能函数.冷技能_HUD名;
	var 键位:Array = _root.技能函数.冷技能_HUD键位;
	键.length = 0; 名表.length = 0; 键位.length = 0;
	for (var i:Number = 0; i < 表.length; i++) {
		var 名:String = 表[i].技能;
		if (!(Number(查等级(名)) > 0)) continue;
		名表.push(名);
		键位.push(String(_root.技能函数.冷技能键位[表[i].键]));
		键.push(_root.技能函数.冷技能冷却键(名));
	}
	if (名表.length == 0) return [];

	var 值:Array = _root.技能函数.冷技能_HUD值;
	ManualCooldownService.writeHudSnapshot(键, 值);

	var mp:Number = (单位 == null) ? 0 : Number(单位.mp);
	var 结果:Array = [];
	for (var k:Number = 0; k < 名表.length; k++) {
		var 技能名:String = 名表[k];
		var 就绪:Boolean = Number(值[k * 3]) == 1;
		var 数据:Object = (_root.技能表对象 == undefined) ? null : _root.技能表对象[技能名];
		var 缺蓝:Boolean = 就绪 && 数据 != null && mp < Number(数据.MP);
		结果.push({
			name: 技能名,
			key: 键位[k],
			ready: 就绪,
			current: Number(值[k * 3 + 1]),
			total: Number(值[k * 3 + 2]),
			blocked: 缺蓝
		});
	}
	return 结果;
};

// ============================================================================
// 自绘面板：纯色白底 + 黑色外框 + 技能名，贴在快捷技能栏正上方
//
//   字形：沿用游戏里其它 AS2 动态文本的口径（CutsceneService 的「跳过动画」
//   提示）——设备字体 _sans、不开 embedFonts。之前那版 8~9px 中文看不见，
//   主因是字号太小 + 底色透明；这里字号提到 10、底改成纯白不透明。
//
//   坐标：面板挂在 _root 上（不挂进 玩家信息界面，避免被原生 HUD 的垫片
//   对象遮挡），位置由「快捷技能栏1」的全局左上角反推：底边 = 槽位顶边 - 6。
// ============================================================================
_root.技能函数.冷技能面板_格宽 = 44;
_root.技能函数.冷技能面板_格高 = 34;
_root.技能函数.冷技能面板_间距 = 4;
_root.技能函数.冷技能面板_离栏 = 6;
_root.技能函数.冷技能面板_字号 = 10;

// 找技能栏：优先直挂，其次 玩家信息界面 子级，最后扫一遍 _root 子剪辑。
// 原生 HUD 会把 _root.玩家信息界面 换成垫片对象，原剪辑仍留在显示列表里，
// 所以最后那步兜底是有意义的；只在没命中时才扫，开销可忽略。
_root.技能函数._冷技能面板找栏 = function():MovieClip {
	var 直挂:MovieClip = _root.快捷技能界面;
	if (直挂 != null && 直挂.快捷技能栏1 != null) return 直挂;
	var 面板:Object = _root.玩家信息界面;
	if (面板 != null && 面板.快捷技能界面 != null) return 面板.快捷技能界面;
	for (var 名:String in _root) {
		var 子:Object = _root[名];
		if (typeof 子 != "movieclip") continue;
		if (子._name == "冷技能冷却面板") continue;
		if (子.快捷技能界面 != null) return 子.快捷技能界面;
	}
	return null;
};

_root.技能函数._冷技能面板定位 = function(容器:MovieClip):Void {
	var 格宽:Number = _root.技能函数.冷技能面板_格宽;
	var 格高:Number = _root.技能函数.冷技能面板_格高;
	var x:Number;
	var y:Number;
	var 栏:MovieClip = _root.技能函数._冷技能面板找栏();
	if (栏 != null && 栏.快捷技能栏1 != null) {
		var 槽:MovieClip = 栏.快捷技能栏1;
		// AS2 的 localToGlobal 是「就地改写传入的点对象、返回 Void」，
		// 不能写成 var 角 = 栏.localToGlobal(...)（会报 Void→Object 类型不匹配）。
		var 角:Object = {x: 槽._x, y: 槽._y};
		栏.localToGlobal(角);
		x = Math.round(角.x);
		y = Math.round(角.y - 格高 - _root.技能函数.冷技能面板_离栏);
	} else {
		// 兜底：贴着屏幕底部一栏的高度往上放，横向偏右（技能栏原位置）。
		var 屏宽:Number = (Stage.width > 0) ? Stage.width : 1024;
		var 屏高:Number = (Stage.height > 0) ? Stage.height : 576;
		x = Math.round(屏宽 * 0.58);
		y = Math.round(屏高 - 64 - 格高 - 12);
	}
	if (容器._x != x || 容器._y != y) {
		容器._x = x;
		容器._y = y;
		// 面板是 _root 的直接子级，只要在兄弟里排最上面就不会被单位/场景盖住
		// （单位在 游戏世界 容器内部，和这里不是同一层深度空间）。
		容器.swapDepths(_root.getNextHighestDepth());
	}
};

// 画格子底 + 名字。只在「技能列表变了」时调用一次，不逐帧重画。
_root.技能函数._冷技能面板画格 = function(格:MovieClip, 名:String):Void {
	var 格宽:Number = _root.技能函数.冷技能面板_格宽;
	var 格高:Number = _root.技能函数.冷技能面板_格高;
	格.clear();
	格.lineStyle(1, 0x000000, 100);
	格.beginFill(0xFFFFFF, 100);
	格.moveTo(0.5, 0.5);
	格.lineTo(格宽 - 0.5, 0.5);
	格.lineTo(格宽 - 0.5, 格高 - 0.5);
	格.lineTo(0.5, 格高 - 0.5);
	格.lineTo(0.5, 0.5);
	格.endFill();

	var 行高:Number = _root.技能函数.冷技能面板_字号 + 4;
	var 格式:TextFormat = new TextFormat("_sans", _root.技能函数.冷技能面板_字号, 0x000000, true);
	格式.align = "center";
	var 文本:TextField = 格.名;
	文本.embedFonts = false;
	文本.selectable = false;
	文本.wordWrap = false;
	文本.text = 名;
	文本.setTextFormat(格式);
	文本._x = 1;
	文本._y = Math.round((格高 - 行高) / 2);
	文本._width = 格宽 - 2;
	文本._height = 行高;
};

// 显示闸门：只有真正处在冷兵器战斗状态时才画面板。
//   ① 攻击模式 != "兵器"：空手 / 手枪 / 双枪 / 长枪 / 手雷 都没有冷兵器搓招，
//      留着面板只会误导（这些模式下按方向+B 是别的动作）。
//   ② 刀 槽为空：攻击模式切换("兵器") 本身就要求 刀 存在，但「切到兵器模式后
//      再把刀卸了」会让 攻击模式 残留在 "兵器" ⇒ 光看模式会留一块空面板。
//   ③ 倒地：趴着不能搓招。
// 三个条件都查一遍，任何一个不成立就藏板（不销毁格子，只关 _visible，
// 重新满足条件时按原样显示，不用重建）。
_root.技能函数._冷技能面板可显示 = function(单位:Object):Boolean {
	if (单位 == null) return false;
	if (单位.攻击模式 != "兵器") return false;
	if (单位.刀 == null) return false;
	if (单位.倒地 == true) return false;
	return true;
};

_root.技能函数._冷技能面板帧 = function():Void {
	var 容器:MovieClip = _root.冷技能冷却面板;
	if (容器 == null) return;

	var 单位:MovieClip = TargetCacheManager.findHero();
	if (!_root.技能函数._冷技能面板可显示(单位)) {
		容器._visible = false;
		return;
	}

	var 行:Array = _root.技能函数.冷技能HUD快照(单位);
	if (行 == null) 行 = [];
	if (行.length == 0) {
		容器._visible = false;
		容器.名字签名 = "";
		return;
	}

	_root.技能函数._冷技能面板定位(容器);

	var 格宽:Number = _root.技能函数.冷技能面板_格宽;
	var 格高:Number = _root.技能函数.冷技能面板_格高;
	var 字号:Number = _root.技能函数.冷技能面板_字号;

	var 签名:String = "";
	var i:Number;
	for (i = 0; i < 行.length; i++) 签名 += 行[i].name + "|";
	if (容器.名字签名 != 签名) {
		容器.名字签名 = 签名;
		for (var d:Number = 行.length; d < 12; d++) {
			var 旧:MovieClip = 容器["格" + d];
			if (旧 != null) 旧.removeMovieClip();
		}
		for (i = 0; i < 行.length; i++) {
			var 格:MovieClip = 容器["格" + i];
			if (格 == null) {
				格 = 容器.createEmptyMovieClip("格" + i, i + 1);
				格.createEmptyMovieClip("遮罩", 1);
				格.createTextField("名", 2, 1, 0, 格宽 - 2, 字号 + 4);
			}
			格._x = i * (格宽 + _root.技能函数.冷技能面板_间距);
			格._y = 0;
			格.文字色 = -1;
			_root.技能函数._冷技能面板画格(格, 行[i].name);
		}
	}

	for (i = 0; i < 行.length; i++) {
		var 当前格:MovieClip = 容器["格" + i];
		if (当前格 == null) continue;
		var 数据:Object = 行[i];

		// 冷却遮罩：格内顶部往下压，高度占比 = 剩余冷却比例。
		var 比例:Number = 0;
		if (数据.ready !== true && Number(数据.total) > 0) {
			比例 = Number(数据.current) / Number(数据.total);
			if (!(比例 > 0)) 比例 = 0;
			if (比例 > 1) 比例 = 1;
		}
		var 遮:MovieClip = 当前格.遮罩;
		遮.clear();
		if (比例 > 0.002) {
			var 底:Number = 1 + (格高 - 2) * 比例;
			遮.beginFill(0x000000, 30);
			遮.moveTo(1, 1);
			遮.lineTo(格宽 - 1, 1);
			遮.lineTo(格宽 - 1, 底);
			遮.lineTo(1, 底);
			遮.lineTo(1, 1);
			遮.endFill();
		}

		var 色:Number = 0x000000;
		if (数据.blocked === true) 色 = 0xB03A2E;
		else if (数据.ready !== true) 色 = 0x3A3A3A;
		if (当前格.文字色 != 色) {
			当前格.文字色 = 色;
			var 格式:TextFormat = new TextFormat("_sans", 字号, 色, true);
			格式.align = "center";
			当前格.名.setTextFormat(格式);
		}
	}

	容器._visible = true;
};

if (_root.冷技能面板驱动 == undefined) {
	var 驱动:MovieClip = _root.createEmptyMovieClip("冷技能面板驱动", _root.getNextHighestDepth());
	驱动.onEnterFrame = function():Void {
		if (_root.冷技能冷却面板 == undefined) {
			if (typeof TargetCacheManager != "function" && typeof TargetCacheManager != "object") return;
			var 容器:MovieClip = _root.createEmptyMovieClip("冷技能冷却面板", _root.getNextHighestDepth());
			容器._visible = false;
			容器.名字签名 = "";
			容器.tabEnabled = false;
		}
		_root.技能函数._冷技能面板帧();
	};
}
