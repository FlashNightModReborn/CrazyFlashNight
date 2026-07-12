_root.主角函数.持枪行走状态机 = function(){
	//按攻击键后若需要转换状态则停止行走判定2帧
	// _root.发布消息("持枪行走状态机", _parent.行走冷却帧)
	if(_parent.行走冷却帧 > 0){
		_parent.行走冷却帧--;
	}else{
		_parent.行走();
	}
	
	if (_parent.操控编号 != -1 && !_root.控制目标全自动 && !_root.全鼠标控制){
		_parent.按键控制攻击模式();
	}
	// R/F 在同一个持枪动作仲裁点消费：R > F > A/B。
	// 跑姿切换后的 man 要到下一帧才绑定换弹函数：意图只在 man ready 后消费，
	// 不使用 unit 锁、轮询任务或无界延迟重试。
	var 当前输入帧:Number = _root.帧计时器.当前帧数;
	var 待处理战斗意图:Object = org.flashNight.arki.unit.Action.Input.UnitActionIntentService.peek(
		_parent,
		org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
		当前输入帧
	);
	var 有副武器换弹意图:Boolean = 待处理战斗意图 != null
		&& 待处理战斗意图.kind == org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_SUBWEAPON_RELOAD;
	var 有主武器换弹意图:Boolean = 待处理战斗意图 != null
		&& 待处理战斗意图.kind == org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_PRIMARY_RELOAD;

	// 同采样帧 R 永远压过 F，并立即清除输掉的 F 意图。
	if (_parent.动作C && 有副武器换弹意图) {
		org.flashNight.arki.unit.Action.Input.UnitActionIntentService.take(
			_parent,
			org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
			org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_SUBWEAPON_RELOAD,
			当前输入帧,
			true
		);
		待处理战斗意图 = null;
		有副武器换弹意图 = false;
	}

	var 主武器换弹请求:Boolean = _parent.动作C || 有主武器换弹意图;
	var 副武器换弹请求:Boolean = 有副武器换弹意图
		&& org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore.canReloadManual(_parent);
	if (有副武器换弹意图 && !副武器换弹请求) {
		org.flashNight.arki.unit.Action.Input.UnitActionIntentService.take(
			_parent,
			org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
			org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_SUBWEAPON_RELOAD,
			当前输入帧,
			false
		);
	}

	if (主武器换弹请求 || 副武器换弹请求){
		if(!_parent.移动射击 && _parent.状态 != _parent.攻击模式 + "站立"){
			_parent.状态改变(_parent.攻击模式 + "站立");
			_parent.行走冷却帧 = 2;
		}else if(_parent.移动射击 && _parent.状态 === _parent.攻击模式 + "跑"){
			_parent.状态改变(_parent.攻击模式 + "行走");
			// 换弹请求需要等新姿态 man 的第 0 帧完成函数绑定。
			// 暂停两帧行走判定，避免持续方向输入在下一帧把行走重新切回跑，
			// 否则 man 会永远停在第 1 帧，直到有界意图过期。
			_parent.行走冷却帧 = 2;
		}
		if (主武器换弹请求) {
			var 主武器换弹就绪:Boolean = typeof _parent.man.开始换弹 == "function";
			if (!主武器换弹就绪) {
				// 将跑姿 R 的一次性点按延续到 ready man；holding R 仍保持原有连续候补语义。
				if (!有主武器换弹意图) {
					org.flashNight.arki.unit.Action.Input.UnitActionIntentService.submit(
						_parent,
						org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
						org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_PRIMARY_RELOAD,
						当前输入帧,
						2,
						null,
						30
					);
				}
				return;
			}
			if (有主武器换弹意图) {
				org.flashNight.arki.unit.Action.Input.UnitActionIntentService.take(
					_parent,
					org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
					org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_PRIMARY_RELOAD,
					当前输入帧,
					false
				);
			}
			_parent.man.开始换弹();
		} else {
			var 副武器换弹就绪:Boolean = typeof _parent.man.开始副武器换弹 == "function";
			if (!副武器换弹就绪) {
				return;
			}
			var 已消费副武器意图:Object = org.flashNight.arki.unit.Action.Input.UnitActionIntentService.take(
				_parent,
				org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
				org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_SUBWEAPON_RELOAD,
				当前输入帧,
				false
			);
			if (已消费副武器意图 != null) _parent.man.开始副武器换弹();
		}
	}else if (_parent.动作A || _parent.动作B){
		var 需要切换状态 = false;
		var 目标状态 = _parent.状态;
		if(!_parent.移动射击 && _parent.状态 != _parent.攻击模式 + "站立"){
			需要切换状态 = true;
			目标状态 = _parent.攻击模式 + "站立";
		}else if(_parent.移动射击 && _parent.状态 === _parent.攻击模式 + "跑"){
			需要切换状态 = true;
			目标状态 = _parent.攻击模式 + "行走";
		}
		if (_parent.动作B && !_parent.动作A && 需要切换状态) {
			org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore.requestShoot(_parent);
			return;
		}
		if (需要切换状态) {
			_parent.状态改变(目标状态);
			if(!_parent.移动射击) _parent.行走冷却帧 = 2;
		}
		if (_parent.动作A) {
			_parent.格斗架势 = true;
			// _root.发布消息("主角函数.持枪行走状态机", "开始射击");
			_parent.man.开始射击();
		}
		if (_parent.动作B) {
			org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore.requestShoot(_parent);
		}
	}
	
}

_root.主角函数.双枪行走状态机 = function(){
	//按攻击键后若需要转换状态则停止行走判定2帧
	// _root.发布消息("双枪行走状态机", _parent.行走冷却帧)
	if(_parent.行走冷却帧 > 0){
		_parent.行走冷却帧--;
	}else{
		_parent.行走();
	}
	
    if (_parent.操控编号 != -1 && !_root.控制目标全自动 && !_root.全鼠标控制){
        _parent.按键控制攻击模式();
	}
	if (_parent.动作C){
		if(!_parent.移动射击 && _parent.状态 != _parent.攻击模式 + "站立"){
			_parent.状态改变(_parent.攻击模式 + "站立");
			_parent.行走冷却帧 = 2;
		}else if(_parent.移动射击 && _parent.状态 === _parent.攻击模式 + "跑"){
			_parent.状态改变(_parent.攻击模式 + "行走");
		}
		_parent.man.开始换弹();
	}else if (_parent.动作A || _parent.动作B){
		if(!_parent.移动射击 && _parent.状态 != _parent.攻击模式 + "站立"){
			_parent.状态改变(_parent.攻击模式 + "站立");
			_parent.行走冷却帧 = 2;
		}else if(_parent.移动射击 && _parent.状态 === _parent.攻击模式 + "跑"){
			_parent.状态改变(_parent.攻击模式 + "行走");
		}
		if (_parent.动作A) _parent.man.主手开始射击();
		if (_parent.动作B) _parent.man.副手开始射击();
	}
}

_root.主角函数.拳刀行走状态机 = function(){
	_parent.行走();
	/*
	_root.服务器.发布服务器消息("拳刀行走状态机 " + "行走冷却帧:" + 行走冷却帧 + 
        " 上行:" + _parent.上行 + 
        " 下行:" + _parent.下行 + 
        " 上下移动射击:" + 上下移动射击 + 
        " isShooting:" + (_parent.主手射击中 || _parent.副手射击中) + 
        " isActionA:" + _parent.动作A + 
        " isActionB:" + _parent.动作B + 
        " 射击最大后摇中:" + 射击最大后摇中 + 
        " isReloading:" + _parent.man.换弹标签 + 
        " shouldRestrictMovement:" + (((_parent.主手射击中 || _parent.副手射击中) && 
                                (射击最大后摇中 || _parent.动作A || _parent.动作B)) || 
                                _parent.man.换弹标签)
    );
	*/
    if (_parent.操控编号 != -1 && !_root.控制目标全自动 && !_root.全鼠标控制){
        _parent.按键控制攻击模式();
	}
	if (_parent.动作A){
		_parent.格斗架势 = true;
		if (_parent.状态 === _parent.攻击模式 + "跑"){
			_parent.状态改变(_parent.攻击模式 + "冲击");
		}else{
			// 主角-男普攻连招容器化：单容器内跳帧（不覆盖冲击/跑攻）
			if (_parent.攻击模式 === "空手" && _parent.兵种 === "主角-男") {
				_root.空手攻击路由.主角普攻连招开始(_parent);
			} else if (_parent.攻击模式 === "兵器" && _parent.兵种 === "主角-男") {
				_root.兵器攻击路由.主角普攻连招开始(_parent);
			} else {
				_parent.状态改变(_parent.攻击模式 + "攻击");
			}
		}
	}else if (_parent.动作B){
		_parent.跳();
	}
}

_root.主角函数.手雷行走状态机 = function(){
	// _root.发布消息("手雷行走状态机", 行走冷却帧)
	_parent.行走();
    if (_parent.操控编号 != -1 && !_root.控制目标全自动 && !_root.全鼠标控制){
        _parent.按键控制攻击模式();
	}
	if (_parent.动作A){
		_parent.格斗架势 = true;
		_parent.状态改变("手雷攻击");
	}
}
