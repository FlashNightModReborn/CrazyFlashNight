/**
 * 单位函数_雾人_手枪搓招指令.as
 *
 * 手枪搓招 · 三招指令（实装方式参照 单位函数_黑猫_技能搓招指令.as 的方向电平裁决，
 * 释放路由参照 单位函数_雾人_空手搓招指令.as 的搓招门槛口径）
 *
 * 指令表（8 向归一化，前 = 朝向）：
 *   后射     → + B            （向前按键后按 B，向身后射击）
 *   前冲射击 Shift + → + B    （Shift 修饰，向前冲刺射击）
 *   后跳射击 Shift + ← + B   （Shift 修饰，向后跳射击）
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
 *   2. 手枪模式：攻击模式 == "手枪" 或 "手枪2"（双枪/长枪/手雷/空手不参与）
 *   3. 装备了手枪1或手枪2：手枪属性.power 或 手枪2属性.power 至少一个有效
 *
 * 手枪2 容器选择（用户要求的行为）：
 *   三个动画的手枪元件按手枪1装配（主角肢体素材/手枪 读 unit.手枪_装扮）。
 *   玩家未装备手枪1、只装备手枪2 时，改用「手枪搓招容器-<招式名>2」变体容器
 *   （其时间轴内的枪元件两两对调：手持位 = 手枪2 素材，腰挂位 = 手枪1 素材，
 *   手枪1 未装备时腰挂位自动隐藏）。射击数据本身两条枪路各自读
 *   手枪属性 / 手枪2属性，未装备的那条枪路射击许可恒为 false，无需额外处理。
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
	{技能: "前冲射击", 键: "shift前"},
	{技能: "后跳射击", 键: "shift后"},
	{技能: "后射",     键: "前"}
];

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
 * 帧检查用的方向判定。键取值：shift前 / shift后 / 前。
 * shift 判定用 按住奔跑键 而不是 强制奔跑：后者在按了 A/B/C 的同帧被压成 false，
 * 而手枪搓招恰恰要在按住 B 的那一帧成立。
 */
_root.技能函数._手枪方向命中 = function(自机:MovieClip, 键:String):Boolean {
	if (键 == "shift前") return (自机.按住奔跑键 && _root.技能函数._按前(自机)) ? true : false;
	if (键 == "shift后") return (自机.按住奔跑键 && _root.技能函数._手枪按后(自机)) ? true : false;
	if (键 == "前")      return _root.技能函数._按前(自机);
	return false;
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

	// 手枪2 变体选择：未装备手枪1、只装备手枪2 时改挂「手枪搓招容器-<名>2」
	var 有手枪1:Boolean = (自机.手枪属性 != undefined && 自机.手枪属性.power > 0);
	var 有手枪2:Boolean = (自机.手枪2属性 != undefined && 自机.手枪2属性.power > 0);
	var variantSuffix:String = (!有手枪1 && 有手枪2) ? "2" : "";
	自机.__手枪搓招容器名 = 技能名 + variantSuffix;

	// 屏蔽旧 man 卸载回调（时间轴 man 随 gotoAndStop 销毁时不再写状态）
	org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntent.suppressOldManUnload(自机);
	// 对齐 技能路由.技能标签跳转_旧：先归一 temp_y，保证 handleFloat 的浮空判定拿到数字
	org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle.ensureTempY(自机);

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

	// B 松开即复位锁存：一次按下只出一招，按住不放不连发
	if (!自机.动作B) {
		delete 自机.__手枪搓招B已消费;
	}

	// 模式 + 装备门槛（未过 → B 交回原状态机行为）
	if (!_root.技能函数.手枪搓招模式允许(自机)) return 0;
	// 必须按着 B
	if (!自机.动作B) return 0;
	// 同一次按下只尝试一次
	if (自机.__手枪搓招B已消费) return 0;

	var 表:Array = _root.技能函数.手枪搓招表;
	for (var i:Number = 0; i < 表.length; i++) {
		// 先判学习门槛再判方向：未学的招不吞键（B 落回副武器射击等原行为）
		if (!_root.技能函数.手枪搓招已学习(自机, 表[i].技能)) continue;
		if (!_root.技能函数._手枪方向命中(自机, 表[i].键)) continue;

		// 命中：锁存本次按下，清掉旧 DFA 预输入（手枪模式下缓冲名是别的模组的产物）
		自机.__手枪搓招B已消费 = true;
		if (typeof _root.技能函数._清预输入 == "function") {
			_root.技能函数._清预输入(自机);
		}

		var 挂载成功:Boolean = _root.技能函数.手枪搓招标签跳转(自机, 表[i].技能);
		if (!挂载成功) {
			// 容器缺失等异常：不吞键，让原状态机逻辑继续跑
			delete 自机.__手枪搓招B已消费;
			return 0;
		}

		// WebView2 刘海连击提示（对齐搓招监控协议；触发码 2 = 电平裁决）
		if (typeof _root.技能函数._刘海通知 == "function") {
			_root.技能函数._刘海通知(2, 表[i].技能);
		}
		return 2;
	}
	return 0;
};
