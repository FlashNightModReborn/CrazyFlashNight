_root.主角函数.持枪行走状态机 = function(){
	var self:MovieClip = this._parent;
	if (_root.gameworld.__combatAdmitted === false) return;
	if(self.__cf6TraversalOwner!==undefined || self.__cf6ElevatorPoseOwner!==undefined || self.__cf6VehicleOwner!==undefined) return;
	//按攻击键后若需要转换状态则停止行走判定2帧
	// _root.发布消息("持枪行走状态机", self.行走冷却帧)
	if(self.行走冷却帧 > 0){
		self.行走冷却帧--;
	}else{
		self.行走();
	}

	if (self.操控编号 != -1 && !_root.控制目标全自动 && !_root.全鼠标控制){
		self.按键控制攻击模式();
	}
	// R/F 在同一个持枪动作仲裁点消费：R > F > A/B。
	// 跑姿切换后的 man 要到下一帧才绑定换弹函数：意图只在 man ready 后消费，
	// 不使用 unit 锁、轮询任务或无界延迟重试。
	var 当前输入帧:Number = _root.帧计时器.当前帧数;
	var 待处理战斗意图:Object = org.flashNight.arki.unit.Action.Input.UnitActionIntentService.peek(
		self,
		org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
		当前输入帧
	);
	var 有副武器换弹意图:Boolean = 待处理战斗意图 != null
		&& 待处理战斗意图.kind == org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_SUBWEAPON_RELOAD;
	var 有主武器换弹意图:Boolean = 待处理战斗意图 != null
		&& 待处理战斗意图.kind == org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_PRIMARY_RELOAD;

	// 同采样帧 R 永远压过 F，并立即清除输掉的 F 意图。
	if (self.动作C && 有副武器换弹意图) {
		org.flashNight.arki.unit.Action.Input.UnitActionIntentService.take(
			self,
			org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
			org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_SUBWEAPON_RELOAD,
			当前输入帧,
			true
		);
		待处理战斗意图 = null;
		有副武器换弹意图 = false;
	}

	var 主武器换弹请求:Boolean = self.动作C || 有主武器换弹意图;
	var 副武器换弹请求:Boolean = 有副武器换弹意图
		&& org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore.canReloadManual(self);
	if (有副武器换弹意图 && !副武器换弹请求) {
		org.flashNight.arki.unit.Action.Input.UnitActionIntentService.take(
			self,
			org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
			org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_SUBWEAPON_RELOAD,
			当前输入帧,
			false
		);
	}

	if (主武器换弹请求 || 副武器换弹请求){
        var 换弹目标状态:String = null;
        if (!self.移动射击 && self.状态 != self.攻击模式 + "站立") {
            换弹目标状态 = self.攻击模式 + "站立";
        } else if (self.移动射击 && self.状态 === self.攻击模式 + "跑") {
            换弹目标状态 = self.攻击模式 + "行走";
        }
        if (换弹目标状态 != null) {
            // 跳父时间轴前保存冷却与有界点按意图；旧 man 卸载后不依赖后续代码。
            self.行走冷却帧 = 2;
            if (主武器换弹请求 && !有主武器换弹意图) {
                org.flashNight.arki.unit.Action.Input.UnitActionIntentService.submit(
                    self, org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
                    org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_PRIMARY_RELOAD,
                    当前输入帧, 2, null, 30);
            }
            self.状态改变(换弹目标状态);
            return;
        }
		if (主武器换弹请求) {
			var 主武器换弹就绪:Boolean = typeof self.man.开始换弹 == "function";
			if (!主武器换弹就绪) {
				// 将跑姿 R 的一次性点按延续到 ready man；holding R 仍保持原有连续候补语义。
				if (!有主武器换弹意图) {
					org.flashNight.arki.unit.Action.Input.UnitActionIntentService.submit(
						self,
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
					self,
					org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
					org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_PRIMARY_RELOAD,
					当前输入帧,
					false
				);
			}
			self.man.开始换弹();
		} else {
			var 副武器换弹就绪:Boolean = typeof self.man.开始副武器换弹 == "function";
			if (!副武器换弹就绪) {
				return;
			}
			var 已消费副武器意图:Object = org.flashNight.arki.unit.Action.Input.UnitActionIntentService.take(
				self,
				org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
				org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_SUBWEAPON_RELOAD,
				当前输入帧,
				false
			);
			if (已消费副武器意图 != null) self.man.开始副武器换弹();
		}
	}else if (self.动作A || self.动作B){
		var 需要切换状态 = false;
		var 目标状态 = self.状态;
		if(!self.移动射击 && self.状态 != self.攻击模式 + "站立"){
			需要切换状态 = true;
			目标状态 = self.攻击模式 + "站立";
		}else if(self.移动射击 && self.状态 === self.攻击模式 + "跑"){
			需要切换状态 = true;
			目标状态 = self.攻击模式 + "行走";
		}
		if (self.动作B && !self.动作A && 需要切换状态) {
			org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore.requestShoot(self);
			return;
		}
		if (需要切换状态) {
			self.状态改变(目标状态);
			if(!self.移动射击) self.行走冷却帧 = 2;
		}
		if (self.动作A) {
			self.格斗架势 = true;
			// _root.发布消息("主角函数.持枪行走状态机", "开始射击");
			self.man.开始射击();
		}
		if (self.动作B) {
			org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore.requestShoot(self);
		}
	}

}

_root.主角函数.双枪行走状态机 = function(){
	var self:MovieClip = this._parent;
	if (_root.gameworld.__combatAdmitted === false) return;
	if(self.__cf6TraversalOwner!==undefined || self.__cf6ElevatorPoseOwner!==undefined || self.__cf6VehicleOwner!==undefined) return;
	//按攻击键后若需要转换状态则停止行走判定2帧
	// _root.发布消息("双枪行走状态机", self.行走冷却帧)
	if(self.行走冷却帧 > 0){
		self.行走冷却帧--;
	}else{
		self.行走();
	}

    if (self.操控编号 != -1 && !_root.控制目标全自动 && !_root.全鼠标控制){
        self.按键控制攻击模式();
	}
    var 当前输入帧:Number = _root.帧计时器.当前帧数;
    var 待处理战斗意图:Object = org.flashNight.arki.unit.Action.Input.UnitActionIntentService.peek(
        self, org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT, 当前输入帧);
    var 有主武器换弹意图:Boolean = 待处理战斗意图 != null
        && 待处理战斗意图.kind == org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_PRIMARY_RELOAD;
    if (self.动作C || 有主武器换弹意图) {
        var 换弹目标状态:String = null;
        if (!self.移动射击 && self.状态 != self.攻击模式 + "站立") {
            换弹目标状态 = self.攻击模式 + "站立";
        } else if (self.移动射击 && self.状态 === self.攻击模式 + "跑") {
            换弹目标状态 = self.攻击模式 + "行走";
        }
        if (换弹目标状态 != null) {
            self.行走冷却帧 = 2;
            if (!有主武器换弹意图) {
                org.flashNight.arki.unit.Action.Input.UnitActionIntentService.submit(
                    self, org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
                    org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_PRIMARY_RELOAD,
                    当前输入帧, 2, null, 30);
            }
            self.状态改变(换弹目标状态);
            return;
        }
        if (typeof self.man.开始换弹 != "function") {
            if (!有主武器换弹意图) {
                org.flashNight.arki.unit.Action.Input.UnitActionIntentService.submit(
                    self, org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
                    org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_PRIMARY_RELOAD,
                    当前输入帧, 2, null, 30);
            }
            return;
        }
        if (有主武器换弹意图) {
            org.flashNight.arki.unit.Action.Input.UnitActionIntentService.take(
                self, org.flashNight.arki.unit.Action.Input.UnitActionIntentService.CHANNEL_COMBAT,
                org.flashNight.arki.unit.Action.Input.UnitActionIntentService.KIND_PRIMARY_RELOAD, 当前输入帧, false);
        }
        self.man.开始换弹();
	}else if (self.动作A || self.动作B){
		if(!self.移动射击 && self.状态 != self.攻击模式 + "站立"){
			self.状态改变(self.攻击模式 + "站立");
			self.行走冷却帧 = 2;
		}else if(self.移动射击 && self.状态 === self.攻击模式 + "跑"){
			self.状态改变(self.攻击模式 + "行走");
		}
		if (self.动作A) self.man.主手开始射击();
		if (self.动作B) self.man.副手开始射击();
	}
}

_root.主角函数.拳刀行走状态机 = function(){
	var self:MovieClip = this._parent;
	if (_root.gameworld.__combatAdmitted === false) return;
	if(self.__cf6TraversalOwner!==undefined || self.__cf6ElevatorPoseOwner!==undefined || self.__cf6VehicleOwner!==undefined) return;
	self.行走();
	/*
	_root.服务器.发布服务器消息("拳刀行走状态机 " + "行走冷却帧:" + 行走冷却帧 +
        " 上行:" + self.上行 +
        " 下行:" + self.下行 +
        " 上下移动射击:" + 上下移动射击 +
        " isShooting:" + (self.主手射击中 || self.副手射击中) +
        " isActionA:" + self.动作A +
        " isActionB:" + self.动作B +
        " 射击最大后摇中:" + 射击最大后摇中 +
        " isReloading:" + self.man.换弹标签 +
        " shouldRestrictMovement:" + (((self.主手射击中 || self.副手射击中) &&
                                (射击最大后摇中 || self.动作A || self.动作B)) ||
                                self.man.换弹标签)
    );
	*/
    if (self.操控编号 != -1 && !_root.控制目标全自动 && !_root.全鼠标控制){
        self.按键控制攻击模式();
	}
	if (self.动作A){
        if (org.flashNight.arki.unit.Action.Huofeng.HuofengRules.profileActive(self)) {
            self.__huofeng.startAttack(self.状态 === self.攻击模式 + "跑");
            return;
        }
		self.格斗架势 = true;
		if (self.状态 === self.攻击模式 + "跑"){
			self.状态改变(self.攻击模式 + "冲击");
		}else{
			// 主角-男普攻连招容器化：单容器内跳帧（不覆盖冲击/跑攻）
			if (self.攻击模式 === "空手" && self.兵种 === "主角-男") {
				_root.空手攻击路由.主角普攻连招开始(self);
			} else if (self.攻击模式 === "兵器" && self.兵种 === "主角-男") {
				_root.兵器攻击路由.主角普攻连招开始(self);
			} else {
				self.状态改变(self.攻击模式 + "攻击");
			}
		}
	}else if (self.动作B){
		self.跳();
	}
}

_root.主角函数.手雷行走状态机 = function(){
	var self:MovieClip = this._parent;
	if (_root.gameworld.__combatAdmitted === false) return;
	if(self.__cf6TraversalOwner!==undefined || self.__cf6ElevatorPoseOwner!==undefined || self.__cf6VehicleOwner!==undefined) return;
	// _root.发布消息("手雷行走状态机", 行走冷却帧)
	self.行走();
    if (self.操控编号 != -1 && !_root.控制目标全自动 && !_root.全鼠标控制){
        self.按键控制攻击模式();
	}
	if (self.动作A){
		self.格斗架势 = true;
		self.状态改变("手雷攻击");
	}
}
