if(_root.基建系统 == null) _root.基建系统 = new Object();
_root.基建系统.infrastructure = new Object();

_root.基建系统.初始化基建元件 = function(target:MovieClip, key:String, args:Array):Void{
	target.stop();
	if(_root.基建系统.dict[key] == null) return;
	// 对目标基建等级进行排序
	// args = org.flashNight.naki.Sort.QuickSort.adaptiveSort(args, function(a, b) {
    //     return a[0] - b[0]; // Numeric comparison
    // });
	target.基建项目 = key;
	target.基建等级列表 = args.length > 0 ? args : null;
	if(this.infrastructure[target.基建项目] == null){ 
		this.infrastructure[target.基建项目] = 0;
		// 弹出提示
		_root.发布消息("发现新的基建项目：" + key);
	}
	_root.基建系统.更新基建元件(target);
}

_root.基建系统.更新基建元件 = function(target:MovieClip):Void{
	if(target.基建等级列表 == null) return;
	var currentLevel = isNaN(this.infrastructure[target.基建项目]) ? 0 : this.infrastructure[target.基建项目];
	// 逐个检索基建等级是否高于目标等级
	var frame = currentLevel < target.基建等级列表.length ? target.基建等级列表[currentLevel] : target.基建等级列表[target.基建等级列表.length - 1];
	if(frame == null){
		target._visible = false; // 若不满足则直接隐藏
	}else{
		target._visible = true;
		target.gotoAndStop(frame); // 否则，跳转到指定的帧
	}
}

_root.基建系统.检查基建等级 = function(key:String, level:Number):Boolean{
	return (_root.基建系统.infrastructure[key] > 0 && _root.基建系统.infrastructure[key] >= level);
}

_root.基建系统.获取已解锁基建列表 = function():Array{
	var list:Array = [];
	for(var i=0; i < this.nameList.length; i++){
		var 当前基建项目 = this.nameList[i];
		if(this.infrastructure[当前基建项目.Name] != null){
			list.push(当前基建项目);
		}
	}
	return list;
}

/*
初始化基建元件示例：
_root.基建系统.初始化基建元件(this, "厨房", [null, "锅", "大锅", "超大锅"]);
*/


_root.基建系统.第一防线调度板 = new Object();
_root.基建系统.第一防线调度板.启动任务面板 = function():Void{
	if (!_root.基建系统.检查基建等级("前线调度板", 1)) {
		_root.发布消息("前线调度板尚未建成");
		return;
	}
	if (_root.gameCommands != undefined && _root.gameCommands.openWebDispatchBoard != undefined) {
		_root.gameCommands.openWebDispatchBoard({boardId: "first_defense", skin: "first-defense"});
		return;
	}
	_root.发布消息("前线调度板通信尚未就绪");
}

// ── 平板 Web 面板：基建状态快照与升级命令（权威端）──
// 链路：Web tablet 面板 {domain:'tablet'} → Host TabletTask → 下列 gameCommand；
// 回执统一 socket task "tablet_response" + callId，由 Host 关联储备返回 panel_resp。
// 写权威与 基建内容整体.xml 同一套原语：捕获玩家物资快照 / itemSubmit /
// 记录玩家货币变化 / 基建系统.infrastructure++ / 玩家物资事务。

_root.平板基建等级快照 = function():Object{
	var map:Object = {};
	var infra:Object = (_root.基建系统 != undefined) ? _root.基建系统.infrastructure : undefined;
	if(infra != undefined){
		for(var key:String in infra){
			var safeKey:String = String(key);
			if(safeKey.length > 0 && safeKey.length <= 80){
				var lv:Number = Number(infra[key]);
				if(!isNaN(lv)) map[safeKey] = lv;
			}
		}
	}
	return map;
};

_root.平板回执 = function(params:Object, body:Object):Void{
	if(_root.server == undefined || _root.server.sendSocketMessage == undefined) return;
	if(_root.__tabletLiteJson == undefined) _root.__tabletLiteJson = new LiteJSON();
	var resp:Object = {task:"tablet_response"};
	resp.callId = (params == undefined) ? undefined : params.callId;
	for(var key:String in body) resp[key] = body[key];
	_root.server.sendSocketMessage(_root.__tabletLiteJson.stringifySafe(resp));
};

_root.gameCommands["tabletInfraSync"] = function(params:Object):Void{
	_root.平板回执(params, {task:"tablet_response", ok:true,
		infrastructure:_root.平板基建等级快照()});
};

_root.gameCommands["tabletInfraUpgrade"] = function(params:Object):Void{
	var name:String = (params == undefined) ? "" : String(params.name || "");
	var sys:Object = _root.基建系统;
	var project:Object = (sys != undefined && sys.dict != undefined) ? sys.dict[name] : undefined;
	if(name == "" || project == undefined || project.Level == undefined || project.Level.length < 2){
		_root.平板回执(params, {task:"tablet_response", success:false, name:name, error:"unknown_infra"});
		return;
	}
	if(sys.infrastructure == undefined || sys.infrastructure[name] == undefined){
		_root.平板回执(params, {task:"tablet_response", success:false, name:name, error:"not_unlocked"});
		return;
	}
	var level:Number = isNaN(Number(sys.infrastructure[name])) ? 0 : Number(sys.infrastructure[name]);
	var maxLevel:Number = project.Level.length - 1;
	if(level >= maxLevel){
		_root.平板回执(params, {task:"tablet_response", success:false, name:name, level:level, error:"max_level"});
		return;
	}
	var levelData:Object = project.Level[level];
	if(levelData.Skill != undefined && levelData.Skill.length > 0){
		for(var i:Number = 0; i < levelData.Skill.length; i++){
			var skill = levelData.Skill[i];
			if(_root.根据技能名查找主角技能等级(skill.Name) < Number(skill.Level)){
				_root.发布消息("技能[" + skill.Name + "]等级不足！");
				_root.平板回执(params, {task:"tablet_response", success:false, name:name, level:level, error:"skill_required"});
				return;
			}
		}
	}
	if(Number(levelData.Price) > 0 && _root.金钱 < Number(levelData.Price)){
		_root.发布消息("金币不足！");
		_root.平板回执(params, {task:"tablet_response", success:false, name:name, level:level, error:"money_shortage"});
		return;
	}
	var assetContext = {source:"base_upgrade", reason:"infrastructure_upgrade", mergeScope:"operation"};
	var assetSnapshot = _root.捕获玩家物资快照();
	var infraMap:Object = sys.infrastructure;
	var hadLevel:Boolean = infraMap.hasOwnProperty(name);
	var levelBefore:Number = infraMap[name];
	var restoreSnapshot = function():Boolean{
		// 与 基建内容整体.xml 恢复语义一致：先复原领域等级，
		// 再 exact 返还玩家资产；资产无法复原时领域回到失败事实。
		var failureHadLevel:Boolean = infraMap.hasOwnProperty(name);
		var failureLevel:Number = infraMap[name];
		var infraRestored:Boolean = false;
		try {
			if(hadLevel) infraMap[name] = levelBefore;
			else delete infraMap[name];
			infraRestored = hadLevel
				? infraMap[name] === levelBefore
				: !infraMap.hasOwnProperty(name);
		} catch(infraRestoreError) {
			trace("[tabletInfraUpgrade] level restore failed: " + infraRestoreError);
		}
		if(!infraRestored) return false;
		var assetsRestored:Boolean = false;
		try {
			assetsRestored = _root.恢复玩家物资快照(assetSnapshot) === true;
		} catch(assetRestoreError) {
			trace("[tabletInfraUpgrade] asset restore failed: " + assetRestoreError);
		}
		if(assetsRestored) return true;
		try {
			if(failureHadLevel) infraMap[name] = failureLevel;
			else delete infraMap[name];
		} catch(infraFailureStateError) {
			trace("[tabletInfraUpgrade] failure-state restore failed: " + infraFailureStateError);
		}
		return false;
	};
	var assetTransaction = _root.开始玩家物资事务(assetContext);
	try {
		_root.标记玩家物资存档脏();
		if(levelData.Material != undefined && levelData.Material.length > 0){
			var reqList:Array = [];
			for(var mi:Number = 0; mi < levelData.Material.length; mi++){
				var material = levelData.Material[mi];
				reqList.push(String(material.Name) + "#" + material.Value);
			}
			var itemArr:Array = _root.getRequirementFromTask(reqList);
			if(!_root.itemSubmit(itemArr, assetContext)){
				var submitRestored:Boolean = restoreSnapshot();
				_root.结算玩家物资事务异常(assetTransaction, !submitRestored);
				_root.发布消息("材料不足！");
				_root.平板回执(params, {task:"tablet_response", success:false, name:name, level:level, error:"material_shortage"});
				return;
			}
		}
		if(Number(levelData.Price) > 0){
			var moneyBefore:Number = Number(_root.金钱);
			try {
				_root.金钱 -= Number(levelData.Price);
			} finally {
				var committedMoney:Number = moneyBefore - Number(_root.金钱);
				if(committedMoney > Number(levelData.Price)) committedMoney = Number(levelData.Price);
				if(committedMoney > 0 && !isNaN(committedMoney)){
					_root.记录玩家货币变化(-committedMoney, 0, assetContext);
				}
			}
		}
		infraMap[name]++;
		_root.提交玩家物资事务(assetTransaction);
	} catch(assetError) {
		var upgradeRestored:Boolean = restoreSnapshot();
		_root.结算玩家物资事务异常(assetTransaction, !upgradeRestored);
		_root.平板回执(params, {task:"tablet_response", success:false, name:name, level:level, error:"transaction_error"});
		throw assetError;
	}
	_root.发布消息(name + " 升级至 " + infraMap[name] + " 级");
	_root.平板回执(params, {task:"tablet_response", success:true, name:name, level:infraMap[name],
		infrastructure:_root.平板基建等级快照()});
};
