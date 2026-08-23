
_root.战宠UI函数 = new Object();

// 宠物当前金币售价 = 基础价 + IncreasePrice×已购次数。
// 设计意图：IncreasePrice>0 的宠物每买一只就更贵，抑制玩家堆同质化战宠（购买价 + 刷怪可雇用价同步上涨）。
// 已购次数持久化于 _root._saveExt.宠物购买次数（存档预留命名空间，随 mydata.ext 往返）。
// 旧实现靠原地改写 _root.宠物库[id].Price 累积（会话内、不入存档）；现改为基于次数计算，配置保持只读。
// 权威单一来源：商城购买(PetPanelService)与刷怪雇佣价(计算可雇用敌人价格)都调本函数。
_root.获取宠物当前售价 = function(petId){
	var def = _root.宠物库[petId];
	if(def == undefined) return 0;
	var base = Number(def.Price) || 0;
	var inc = Number(def.IncreasePrice) || 0;
	if(inc <= 0) return base;
	var ext = _root._saveExt;
	var cnt = (ext != undefined && ext.宠物购买次数 != undefined) ? Number(ext.宠物购买次数[petId]) : 0;
	if(isNaN(cnt)) cnt = 0;
	return base + inc * cnt;
}

_root.开宠物格子 = function(){
	_root.宠物领养限制 += 1;
	_root.宠物信息.push([]);
	// Plan A audit: 开宠物格子 写 宠物领养限制 + 宠物信息，必须标脏
	_root.存档系统.dirtyMark = true;
}

_root.加载宠物 = function(地点X, 地点Y){
	if((!_root.限制系统.limitLevel || _root.难度等级 >= _root.限制系统.limitLevel) && _root.限制系统.DisableCompanion) return false;
	// 重载前先为仍被跟踪的动态单位提交删除请求；调用前结构失败时保留数组并
	// 停止重载，避免调用者忽略清场失败后直接清数组、再生成同 id 双实例。
	if(_root.宠物mc库 && _root.宠物mc库.length > 0
			&& _root.删除场景宠物() !== true){
		trace("[战宠加载] 旧场景宠物未能全部移除，本次重载已取消");
		return false;
	}
	_root.宠物mc库 = [];
	_root.出战宠物id库 = [];
	var 全部加载:Boolean = true;
	
	for (var i = 0; i < _root.宠物信息.length; i++){
		var 当前宠物信息 = _root.宠物信息[i];
		if(!当前宠物信息 || 当前宠物信息.length < 5) continue;
		if (当前宠物信息[4] == 1){
			if (当前宠物信息[2] > 0){
				if(_root.战宠UI函数.设置宠物出战(i, true, 地点X, 地点Y) !== true){
					// 存档宣称出战、运行态却未创建成功时，以可恢复的休息态闭环；
					// 否则后续退场按钮找不到 mc，又会把 flag 回滚为 1，形成永久假出战。
					_root.存档系统.dirtyMark = true;
					当前宠物信息[4] = 0;
					全部加载 = false;
				}
			}else{
				_root.存档系统.dirtyMark = true;
				当前宠物信息[4] = 0;
				全部加载 = false;
				try{
					_root.发布消息(_root.获得翻译("宠物体力不足，无法出战！"));
				}catch(体力提示错误){}
			}
		}
	}
	//加载宠物后立即应用减体力
	if(_root.当前为战斗地图) _root.宠物减体力();
	try{
		if(_root.宠物信息界面 && typeof _root.宠物信息界面.排列宠物图标 == "function"){
			_root.宠物信息界面.排列宠物图标();
		}
	}catch(图标刷新错误){}
	return 全部加载;
}

_root.战宠UI函数.计算战宠升级所需经验 = function(兵种,等级){
	var 敌人属性 = _root.敌人属性表[兵种];
	var obj = {兵种:兵种,等级:等级};
	if(敌人属性.线性插值经验值.length > 1){
		_root.敌人函数.获取线性插值经验值(obj, 敌人属性.线性插值经验值);
	}else{
		obj.最小经验值 = 敌人属性.最小经验值;
		obj.最大经验值 = 敌人属性.最大经验值;
	}
	var exp = Math.floor((obj.最小经验值 + ((obj.最大经验值 - obj.最小经验值) / (_root.最大等级 - 1)) * 等级) * 等级);
	return exp;
}

_root.战宠UI函数.计算战宠最大出战数 = function(){
	if(_root.isChallengeMode()) return Math.ceil(_root.等级 / 35);
	return Math.min(Math.ceil(_root.等级 / 5), 5);
}

_root.战宠UI函数.统计当前出战数 = function(){
	var count = 0;
	for (var i = 0; i < _root.宠物信息.length; i++){
		if (_root.宠物信息[i] && _root.宠物信息[i][4] == 1){
			count++;
		}
	}
	return count;
}

// 装备型战宠统一销毁入口：先执行 Dressup 生命周期显式 teardown，再交给
// removeMovieClip/onUnload 完成 StaticDeinitializer、dispatcher 与 task 清理。
_root.战宠UI函数.安全移除装备单位 = function(单位对象):Boolean{
	if(!单位对象) return true;
	var 原实例名:String = String(单位对象._name);
	try{
		org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer.teardownLifeCycles(单位对象);
	}catch(生命周期卸载错误){
		// 装备卸载动作来自可扩展脚本；单个动作异常不能阻断 MovieClip 和其余
		// StaticDeinitializer/onUnload 清理，也不能让两阶段替换留下双实例。
		trace("[战宠清理] Dressup 生命周期函数卸载失败: " + 生命周期卸载错误);
	}
	// 所有生产战宠都由 gameworld.attachMovie 动态创建。直接使用不可被时间轴
	// 覆写的 bare 原生 action，并把“删除请求已发出”作为提交边界；XMLSocket/onData
	// 相位内 onUnload 可能要到 phase flush 才清 _parent/parent[name]，任何同步
	// 显示树读回都会把已不可逆的删除误报失败并错误回滚出战标志。
	try{
		removeMovieClip(单位对象);
	}catch(原生移除错误){
		// 原生 action 抛错时删除也可能已经受理；休息是 at-most-once 命令，
		// 继续提交 flag/数组，避免同一单位在下一张图按回滚 flag 重生。
		trace("[战宠清理] 原生 removeMovieClip 异常，按已提交处理: "
			+ 原实例名 + ": " + 原生移除错误);
	}
	return true;
}

// 同图运行态只按权威 slot 做定点移除。缺席视为已经收敛；删除请求未受理时
// 保留数组对供调用方标记 refresh-deferred，不清场、不触碰其他战宠。
_root.战宠UI函数.移除场景宠物槽 = function(id:Number):Boolean{
	var found:Number = -1;
	var i:Number;
	for(i = 0; i < _root.宠物mc库.length; i++){
		var unit = _root.宠物mc库[i];
		if(unit && unit.宠物属性
				&& Number(unit.宠物属性.宠物信息数组号) == id){
			found = i;
			break;
		}
	}
	if(found < 0){
		for(i = 0; i < _root.出战宠物id库.length; i++){
			if(Number(_root.出战宠物id库[i]) == id){
				found = i;
				break;
			}
		}
	}
	if(found < 0) return true;
	var target = _root.宠物mc库[found];
	if(target && !_root.战宠UI函数.安全移除装备单位(target)) return false;
	_root.宠物mc库.splice(found, 1);
	_root.出战宠物id库.splice(found, 1);
	return true;
}

// 场景投影失败不回滚已经提交的宠物所有权/等级事实；现役 Web 服务与自动升级
// 共用这个运行态标记保留 refresh-deferred 可观测性，下一次成功重建或换场景加载会自然清除。
_root.战宠UI函数._宠物刷新待处理 = {};
_root.战宠UI函数.记录宠物刷新结果 = function(id:Number, success:Boolean,
											reason:String):Boolean{
	if(success === true){
		delete _root.战宠UI函数._宠物刷新待处理[id];
		return true;
	}
	_root.战宠UI函数._宠物刷新待处理[id] = {
		reason:reason,
		level:_root.宠物信息[id] ? Number(_root.宠物信息[id][1]) : 0
	};
	trace("[战宠刷新] refresh deferred slot=" + id + " reason=" + reason);
	return false;
}

// FP20 的 attachMovie 同步返回只保证 placement/initObject；资产第 0 帧与
// onClipEvent(load) 要等当前脚本返回后的 load flush。创建调用栈内只能验证这组
// 落位/身份字段，不能读取 dispatcher、HP/MP 或 StaticInitializer 完成闩锁。
_root.战宠UI函数.验证宠物候选落位 = function(候选:MovieClip, id:Number,
											实例名:String):Boolean{
	return 候选 && 候选._parent === _root.gameworld && 候选._name == 实例名
		&& _root.gameworld[实例名] === 候选 && 候选.宠物属性
		&& Number(候选.宠物属性.宠物信息数组号) == id;
}

// 仅供“loader 已同步完成初始化”的兼容实现与 focused 诊断使用。真实 Flash
// attachMovie 返回栈不会进入此门；版本闩锁一旦存在，就必须与 version 精确相等。
_root.战宠UI函数.验证宠物初始化完成 = function(候选:MovieClip):Boolean{
	if(!候选) return false;
	var 最大HP:Number = Number(候选.hp满血值);
	var 当前HP:Number = Number(候选.hp);
	var 最大MP:Number = Number(候选.mp满血值);
	var 当前MP:Number = Number(候选.mp);
	// 非人形敌人模板通常没有通用 MP，两个字段会同时缺省；hasDressup 人形范围
	// 可能把“无可用 MP”投影为合法 0/0。若只出现其中一个字段，或任一已有值
	// 非有限，仍按半初始化资源拒绝，不能为了兼容无 MP 单位放宽损坏候选。
	var 没有MP资源:Boolean = 候选.mp满血值 == undefined && 候选.mp == undefined;
	var MP就绪:Boolean = 没有MP资源 || (候选.mp满血值 != undefined
		&& 候选.mp != undefined && isFinite(最大MP) && 最大MP >= 0
		&& isFinite(当前MP) && 当前MP >= 0);
	var 装扮就绪:Boolean = 候选.hasDressup !== true
		|| (typeof 候选.装载生命周期函数 == "function"
			&& typeof 候选.完成生命周期函数装载 == "function"
			&& 候选.生命周期函数列表 instanceof Array);
	return 候选.dispatcher && typeof 候选.dispatcher.publish == "function"
		&& 候选.aabbCollider && 候选.unitAI && 候选.shield
		&& isFinite(Number(候选.version))
		&& 候选.__unitInitializedVersion === 候选.version
		&& isFinite(最大HP) && 最大HP > 0
		&& isFinite(当前HP) && 当前HP >= 0
		&& MP就绪
		&& 装扮就绪;
}

_root.战宠UI函数.验证宠物候选 = function(候选:MovieClip, id:Number,
										实例名:String):Boolean{
	if(!_root.战宠UI函数.验证宠物候选落位(候选, id, 实例名)) return false;
	// undefined 表示真实 attachMovie 尚未进入第 0 帧，这是合法的 deferred 形状；
	// null/旧 version 表示初始化已经开始但没有完整结束，仍应失败关闭。
	if(typeof 候选.__unitInitializedVersion == "undefined") return true;
	return _root.战宠UI函数.验证宠物初始化完成(候选);
}

// 创建入口已经在同步 loader 调用前证明 exact-name 不存在；因此调用返回前出现的
// 新同名对象只能属于本次创建。清理不再依赖可能尚未写入的宠物属性/id，避免初始化
// 在 initObject 可观察前抛错时留下孤儿；创建前快照仍保证不会删除既有单位。
_root.战宠UI函数.清理失败宠物候选 = function(候选:MovieClip, id:Number,
										实例名:String, 创建前对象:MovieClip):Void{
	var 已注册:MovieClip = _root.gameworld ? _root.gameworld[实例名] : null;
	var 已清理注册:Boolean = false;
	if(已注册 && 已注册 !== 创建前对象 && 已注册._name == 实例名){
		已清理注册 = true;
		try{ _root.战宠UI函数.安全移除装备单位(已注册); }catch(清理注册错误){}
	}
	if(候选 && 候选 !== 创建前对象 && (!已清理注册 || 候选 !== 已注册)
			&& 候选._name == 实例名){
		try{ _root.战宠UI函数.安全移除装备单位(候选); }catch(清理返回引用错误){}
	}
}

// 存档自定义名是唯一显示名覆盖权威；Web 快照、场景创建与旧 Flash 图标共用本函数。
_root.战宠UI函数.获取宠物显示名 = function(id:Number):String{
	var info = _root.宠物信息[id];
	if(!info || info.length < 1) return "";
	var def = _root.宠物库[info[0]];
	if(!def) return "";
	var baseName:String = String(def.Name);
	var attrs:Object = info.length >= 6 && typeof info[5] == "object" ? info[5] : null;
	if(!attrs || attrs.customName == undefined) return baseName;
	var customName:String = String(attrs.customName);
	return customName.length > 0 && customName.length <= 10 ? customName : baseName;
}

// 常驻淬毒的每图扣费只能在候选正式采用后发生。重建若继承同图已结算的旧单位，
// 直接复制 marker/剩余淬毒，不能因为生成了新 MovieClip 再收费。
_root.战宠UI函数.结算宠物部署效果 = function(单位对象:MovieClip,
												旧部署效果:Object):Boolean{
	if(!单位对象) return false;
	delete 单位对象.延迟常驻淬毒结算;
	if(旧部署效果 && 旧部署效果.已常驻淬毒 === true){
		// 同图关闭开关只影响以后入图；已经付费的本图毒效保留到换图，避免
		// 重建把玩家已购买的剩余效果清零。
		单位对象.已常驻淬毒 = true;
		单位对象.淬毒 = 旧部署效果.淬毒;
		return true;
	}
	try{
		var poisonHook:Function = _root.战宠进阶函数.常驻淬毒.单位进阶执行;
		if(typeof poisonHook == "function") poisonHook.call(单位对象);
		return true;
	}catch(部署效果错误){
		// 单位已经正式采用；副作用失败只让本图不生效，不能把成功部署抛成可重放失败。
		trace("[战宠部署] 常驻效果结算失败: " + 部署效果错误);
		return false;
	}
}

// 战宠单位唯一创建入口。attachMovie 返回栈只验 placement；资源结算计划随 initObject
// 进入 MovieClip，由 StaticInitializer 在 Dressup/属性投影完成后一次性消费。这样既不
// 建立跨帧轮询状态机，也不会在最大值尚未就绪时误删候选或错误恢复 HP/MP。
_root.战宠UI函数.创建宠物单位 = function(id:Number, 地点X:Number, 地点Y:Number,
											实例名覆盖:String, 资源结算:Object):MovieClip{
	var 当前宠物信息 = _root.宠物信息[id];
	if(!当前宠物信息 || 当前宠物信息.length < 5) return null;

	var 宠物数据 = _root.宠物库[当前宠物信息[0]];
	if(!宠物数据) return null;
	var 宠物兵种 = 宠物数据.Identifier;
	var 宠物等级 = 当前宠物信息[1];
	var 宠物名字 = _root.战宠UI函数.获取宠物显示名(id);
	var 宠物身高 = 宠物数据.Height;
	var 宠物实例名:String = 实例名覆盖 ? 实例名覆盖 : "宠物" + id + 宠物兵种;
	if(!_root.gameworld) return null;

	var 宠物属性:Object;
	if (当前宠物信息.length >= 6 && 当前宠物信息[5] != null
			&& typeof 当前宠物信息[5] == "object"){
		宠物属性 = 当前宠物信息[5];
	}else{
		// 旧档曾把 [5] 留成 number；先进入存档队列再正规化，避免向 primitive
		// 静默写属性后由 readiness 拒绝，导致“存档出战但场景无单位”。
		_root.存档系统.dirtyMark = true;
		当前宠物信息[5] = {};
		宠物属性 = 当前宠物信息[5];
	}
	宠物属性.宠物库数组号 = 当前宠物信息[0];
	宠物属性.宠物信息数组号 = id;
	if(!资源结算) 资源结算 = {mode:"spawn"};

	var 创建前对象:MovieClip = _root.gameworld[宠物实例名];
	if(创建前对象) return null;
	var 宠物对象:MovieClip = null;
	try{
		宠物对象 = _root.加载游戏世界人物(
			宠物兵种, 宠物实例名, _root.gameworld.getNextHighestDepth(), {
				等级:宠物等级,
				名字:宠物名字,
				宠物属性:宠物属性,
				是否为敌人:false,
				延迟常驻淬毒结算:true,
				__petResourceSettlement:资源结算,
				身高:宠物身高,
				_x:地点X,
				_y:地点Y
			});
	}catch(创建错误){
		_root.战宠UI函数.清理失败宠物候选(宠物对象, id, 宠物实例名, 创建前对象);
		return null;
	}
	if(!_root.战宠UI函数.验证宠物候选(宠物对象, id, 宠物实例名)){
		_root.战宠UI函数.清理失败宠物候选(宠物对象, id, 宠物实例名, 创建前对象);
		return null;
	}
	// focused mock 或未来同步工厂若已经完成 StaticInitializer，可在返回前消费计划；
	// 真实 Flash 的 deferred 候选会由 StaticInitializer 末端执行同一入口。
	if(typeof 宠物对象.__unitInitializedVersion != "undefined"
			&& _root.战宠UI函数.验证宠物初始化完成(宠物对象)
			&& 宠物对象.__petResourceSettlement != undefined){
		org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer
			.settleSpawnResources(宠物对象, 宠物对象.__petResourceSettlement);
		delete 宠物对象.__petResourceSettlement;
	}
	return 宠物对象;
}

// 托管装备变化必须整只重建，不能只走旧的原地“宠物升级加载”。
// 先以唯一临时实例名创建并验证同步 placement，再替换数组并销毁旧单位；真实资产
// 初始化在调用栈返回后的 load flush 完成。单机同步引擎不为极低频的资产第 0 帧异常
// 再建轮询/超时状态机：该边界保留为换场景可恢复故障。资源迁移必须延迟到最终 max
// 已就绪后执行：普通换枪保留绝对 HP/MP，升级重建恢复 HP 满值但延续已有 MP。
_root.战宠UI函数.重建宠物单位 = function(id:Number, 升级重建:Boolean,
													效果名:String):Boolean{
	var 当前宠物信息 = _root.宠物信息[id];
	if(!当前宠物信息 || 当前宠物信息.length < 5 || 当前宠物信息[4] != 1) return false;
	var 地点X:Number = 500;
	var 地点Y:Number = 300;
	var found:Number = -1;
	for(var i:Number = 0; i < _root.宠物mc库.length; i++){
		var unit = _root.宠物mc库[i];
		if(unit && unit.宠物属性 && unit.宠物属性.宠物信息数组号 == id){
			found = i;
			地点X = unit._x;
			地点Y = unit._y;
			break;
		}
	}
	if(found >= 0){
		var oldUnit:MovieClip = _root.宠物mc库[found];
		var oldHp:Number = Number(oldUnit.hp);
		var oldMaxHp:Number = Number(oldUnit.hp满血值);
		var oldMp:Number = Number(oldUnit.mp);
		var replaceSeq:Number = Number(_root.战宠UI函数._宠物替换序号) + 1;
		if(!isFinite(replaceSeq) || replaceSeq < 1) replaceSeq = 1;
		_root.战宠UI函数._宠物替换序号 = replaceSeq;
		var candidateName:String = "宠物" + id + String(_root.宠物库[当前宠物信息[0]].Identifier)
			+ "__替换" + replaceSeq;
		var resourceSettlement:Object = 升级重建 === true
			? {mode:"upgrade", currentMp:oldMp}
			: {mode:"preserve", currentHp:oldHp,
				previousMaxHp:oldMaxHp, currentMp:oldMp};
		var candidate:MovieClip = _root.战宠UI函数.创建宠物单位(
			id, 地点X, 地点Y, candidateName, resourceSettlement);
		var candidateValid:Boolean = candidate && candidate !== oldUnit;
		if(!candidateValid){
			if(candidate){
				_root.战宠UI函数.清理失败宠物候选(candidate, id, candidateName, null);
			}
			return false;
		}
		// removeMovieClip 后旧引用的时间轴字段不再可靠；正式移除前只快照本函数
		// 需要的同图部署效果，避免 focused 普通对象保留字段造成假绿。
		var inheritedDeploymentEffects:Object = oldUnit.已常驻淬毒 === true
			? {已常驻淬毒:true, 淬毒:oldUnit.淬毒} : null;

		// 旧单位的删除请求必须先由统一清理入口受理；调用前失败时清掉候选并
		// 保持两个活动数组仍指向旧单位，避免“双实例”或数组与场景失配。
		if(!_root.战宠UI函数.安全移除装备单位(oldUnit)){
			_root.战宠UI函数.清理失败宠物候选(candidate, id, candidateName, null);
			return false;
		}
		_root.宠物mc库[found] = candidate;
		_root.出战宠物id库[found] = id;
		_root.战宠UI函数.结算宠物部署效果(candidate, inheritedDeploymentEffects);
		if(效果名){
			try{
				EffectSystem.Effect(效果名, candidate._x, candidate._y, 100);
			}catch(重建效果错误){
				// 动画是提交后的可选消费者，不能把已经完成的替换抛成未知结果。
				trace("[战宠重建] 升级效果播放失败: " + 重建效果错误);
			}
		}
		_root.战宠UI函数.记录宠物刷新结果(id, true, "rebuild");
		return true;
	}else{
		var hero:MovieClip = TargetCacheManager.findHero();
		if(hero){
			地点X = hero._x;
			地点Y = hero._y;
		}
	}
	return _root.战宠UI函数.设置宠物出战(id, true, 地点X, 地点Y);
}

// UI 状态写与首次创建组成一个可回滚边界。加载存档时仍可直接调用 设置宠物出战，
// 但玩家按钮必须经此函数，确保 loader 返回空、抛错或半初始化时出战 flag 恢复原值。
_root.战宠UI函数.尝试切换宠物出战状态 = function(id:Number, 是否出战:Boolean,
											地点X:Number, 地点Y:Number):Boolean{
	var 当前宠物信息 = _root.宠物信息[id];
	if(!当前宠物信息 || 当前宠物信息.length < 5) return false;
	var 原状态 = 当前宠物信息[4];
	// 这是旧 Flash UI 的持久化写入口；先确认存档队列可用，再做同步 provisional
	// 写与场景操作。失败即使回滚也允许多一次 save，不能留下未标脏的成功切换。
	_root.存档系统.dirtyMark = true;
	当前宠物信息[4] = 是否出战 ? 1 : 0;
	var success:Boolean = _root.战宠UI函数.设置宠物出战(id, 是否出战, 地点X, 地点Y);
	if(!success) 当前宠物信息[4] = 原状态;
	return success;
}

_root.战宠UI函数.出战按钮函数 = function(是否出战:Boolean){
	if(_root.当前为战斗地图) return;
	var success = false;
	var 当前宠物信息 = _root.宠物信息[_parent.宠物信息数组号];
	_root.最大宠物出战数 = _root.战宠UI函数.计算战宠最大出战数();
	if (当前宠物信息[4] == 0){
		// 使用标记计数而非MC库长度判断出战数
		var 当前出战数 = _root.战宠UI函数.统计当前出战数();
		if (当前出战数 >= _root.最大宠物出战数){
			显示文字 = _root.获得翻译("出战数达到上限");
			return;
		}else if(当前宠物信息[2] <= 0){
			_root.发布消息(_root.获得翻译("宠物体力不足，无法出战！"));
			return;
		}else{
			// 设置出战状态并尝试创建宠物，失败则回滚
			var hero:MovieClip = TargetCacheManager.findHero();
			success = _root.战宠UI函数.尝试切换宠物出战状态(
				_parent.宠物信息数组号, true, hero._x, hero._y);
		}
	}else if (当前宠物信息[4] == 1){
		// 取消出战状态并移除宠物，失败则回滚
		success = _root.战宠UI函数.尝试切换宠物出战状态(
			_parent.宠物信息数组号, false);
	}
	//现在改为加载宠物完成后刷新图标
	if(success) _parent._parent.排列宠物图标();
}

_root.战宠UI函数.设置宠物出战 = function(id:Number, 是否出战:Boolean, 地点X:Number, 地点Y:Number):Boolean{
	var i = -1;
	var 当前宠物信息 = _root.宠物信息[id];
	if(!当前宠物信息 || 当前宠物信息.length < 5) return false;
	if(是否出战){
		if (当前宠物信息[4] != 1) return false;
		if (当前宠物信息[2] <= 0) return false;
		for(i=0; i<_root.宠物mc库.length; i++){
			if(_root.宠物mc库[i].宠物属性.宠物信息数组号 == id) return false;
		}
		var 宠物数据 = _root.宠物库[当前宠物信息[0]];
		if(!宠物数据 || !_root.gameworld) return false;
		var 宠物对象:MovieClip = _root.战宠UI函数.创建宠物单位(
			id, 地点X, 地点Y, null);
		if(!宠物对象) return false;
		_root.宠物mc库.push(宠物对象);
		_root.出战宠物id库.push(id);
		_root.战宠UI函数.结算宠物部署效果(宠物对象, null);
		_root.战宠UI函数.记录宠物刷新结果(id, true, "deploy");
		return true;
	}else{
		if(当前宠物信息[4] != 0) return false;
		return _root.战宠UI函数.移除场景宠物槽(id);
	}
}

_root.宠物减体力 = function(){
	var 已标记体力存档:Boolean = false;
	for (var i = 0; i < _root.宠物mc库.length; i++){
		var id = _root.宠物mc库[i].宠物属性.宠物信息数组号;
		var 当前宠物信息 = _root.宠物信息[id];
		if(当前宠物信息 == null){
			_root.发布消息("战宠体力数据异常！");
			continue;
		}
		if(Number(当前宠物信息[2]) <= 0) continue;
		if(!已标记体力存档){
			// 场景载入是低频路径；在第一笔真实体力写前一次性进入存档队列。
			_root.存档系统.dirtyMark = true;
			已标记体力存档 = true;
		}
		当前宠物信息[2] -= 2;
		if (当前宠物信息[2] <= 0){
			当前宠物信息[2] = 0;
		}
	}
}

_root.删除场景宠物 = function():Boolean{
	// 倒序提交已受理删除请求的配对条目；调用前失败单位继续留在两个数组中
	// 被跟踪。不得在本栈用 _parent/parent[name] 猜测 phase-flush 后的解绑结果。
	var 全部移除:Boolean = true;
	for (var i:Number = _root.宠物mc库.length - 1; i >= 0; i--){
		var unit = _root.宠物mc库[i];
		if(!unit || _root.战宠UI函数.安全移除装备单位(unit)){
			_root.宠物mc库.splice(i, 1);
			_root.出战宠物id库.splice(i, 1);
		}else{
			全部移除 = false;
		}
	}
	return 全部移除;
}

// 读取/存盘战宠已折入 SaveManager.loadAll() / saveAll()
// 保留空壳防止外部调用报错
_root.读取本地存盘战宠 = function(){};
_root.本地存盘战宠 = function(){};

_root.最大宠物格子数 = 80;
_root.最大宠物出战数 = 5;
_root.宠物信息 = [];
_root.读取本地存盘战宠();
