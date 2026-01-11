_root.主角函数.持枪行走状态机 = function(){
	//按攻击键后若需要转换状态则停止行走判定2帧
	// _root.发布消息("持枪行走状态机", 行走冷却帧)
	if(行走冷却帧 > 0){
		行走冷却帧--;
	}else{
		_parent.行走();
	}
	
    if (_parent.操控编号 != -1 && !_root.控制目标全自动 && !_root.全鼠标控制){
        _parent.按键控制攻击模式();
	}
	if (_parent.动作C){
		if(!_parent.移动射击 && _parent.状态 != _parent.攻击模式 + "站立"){
			_parent.状态改变(_parent.攻击模式 + "站立");
			行走冷却帧 = 2;
		}else if(_parent.移动射击 && _parent.状态 === _parent.攻击模式 + "跑"){
			_parent.状态改变(_parent.攻击模式 + "行走");
		}
		_parent.man.开始换弹();
	}else if (_parent.动作A){
		if(!_parent.移动射击 && _parent.状态 != _parent.攻击模式 + "站立"){
			_parent.状态改变(_parent.攻击模式 + "站立");
			行走冷却帧 = 2;
		}else if(_parent.移动射击 && _parent.状态 === _parent.攻击模式 + "跑"){
			_parent.状态改变(_parent.攻击模式 + "行走");
		}
		_parent.格斗架势 = true;
		// _root.发布消息("主角函数.持枪行走状态机", "开始射击");
		_parent.man.开始射击();
	}
	
}

_root.主角函数.双枪行走状态机 = function(){
	//按攻击键后若需要转换状态则停止行走判定2帧
	// _root.发布消息("双枪行走状态机", 行走冷却帧)
	if(行走冷却帧 > 0){
		行走冷却帧--;
	}else{
		_parent.行走();
	}
	
    if (_parent.操控编号 != -1 && !_root.控制目标全自动 && !_root.全鼠标控制){
        _parent.按键控制攻击模式();
	}
	if (_parent.动作C){
		if(!_parent.移动射击 && _parent.状态 != _parent.攻击模式 + "站立"){
			_parent.状态改变(_parent.攻击模式 + "站立");
			行走冷却帧 = 2;
		}else if(_parent.移动射击 && _parent.状态 === _parent.攻击模式 + "跑"){
			_parent.状态改变(_parent.攻击模式 + "行走");
		}
		_parent.man.开始换弹();
	}else if (_parent.动作A || _parent.动作B){
		if(!_parent.移动射击 && _parent.状态 != _parent.攻击模式 + "站立"){
			_parent.状态改变(_parent.攻击模式 + "站立");
			行走冷却帧 = 2;
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
