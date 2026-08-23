

_root.最大等级 = 60;
_root.等级限制 = 100;

_root.根据等级得升级所需经验 = function(等级):Number{
	var 经验 = Math.floor(13 * 等级 * 等级 * 等级 * 等级 + 500);
	if (!isNaN(经验) && 经验 > 0) return 经验;
	return 1000000000000;
}

_root.根据等级计算获得技能点 = function(等级):Number{
	if (_root.isChallengeMode()) return 15;
	if (等级 > 70) return 100;
	if (等级 > 60) return 90;
	if (等级 > 50) return 80;
	if (等级 > 40) return 70;
	if (等级 > 30) return 60;
	if (等级 > 20) return 50;
	if (等级 > 10) return 30;
	return 20;
}

_root.健身房主角是否升级 = function()
{
	if (isNaN(_root.经验值) || isNaN(_root.等级) || _root.等级 >= _root.等级限制) return;

	var 是否升级 = false;
	var 是否完成全部升级 = false;
	while (!是否完成全部升级)
	{
		_root.升级需要经验值 = _root.根据等级得升级所需经验(_root.等级);
		_root.上次升级需要经验值 = _root.等级 > 1 ? _root.根据等级得升级所需经验(_root.等级 - 1) : 0;
		_root.玩家信息界面.刷新经验值显示();
		if (_root.升级需要经验值 <= _root.经验值)
		{
			_root.玩家信息界面.主角经验值显示界面.frame = 100;
			_root.等级++;
			_root.技能点数 += _root.根据等级计算获得技能点(_root.等级);
			// _root.聊天窗.传言("勤奋的" + _root.玩家称号 + _root.角色名 + "升到了" + _root.等级 + "级！");
			是否升级 = true;
		}
		else
		{
			是否完成全部升级 = true;
		}
	}

	if (是否升级) {
		_root.身价 = _root.基础身价值 * _root.等级;
		var 控制对象 = TargetCacheManager.findHero();
		控制对象.等级 = _root.等级;
		控制对象.根据等级初始数值(_root.等级);
		if(!控制对象.hp || 控制对象.hp < 控制对象.hp满血值) 控制对象.hp = 控制对象.hp满血值;
		if(!控制对象.mp || 控制对象.mp < 控制对象.mp满血值) 控制对象.mp = 控制对象.mp满血值;
		_root.玩家信息界面.刷新hp显示();
		_root.玩家信息界面.刷新mp显示();
		EffectSystem.Effect("升级动画",控制对象._x,控制对象._y,100);
		// 资产事务内的升级延迟到领域提交后强存盘，避免奖励已落盘而任务完成态尚未落盘。
		org.flashNight.arki.item.PlayerAssetTransaction.requestStrongSave();
	}
}

_root.主角是否升级 = function(当前等级, 当前经验值)
{
	if (isNaN(当前经验值) || isNaN(当前等级) || 当前等级 >= _root.等级限制) return;

	var 是否升级 = false;
	var 是否完成全部升级 = false;

	// 使用while循环支持连续升级（修复一次只能升1级的问题）
	while (!是否完成全部升级)
	{
		_root.升级需要经验值 = _root.根据等级得升级所需经验(_root.等级);
		_root.上次升级需要经验值 = _root.等级 > 1 ? _root.根据等级得升级所需经验(_root.等级 - 1) : 0;
		_root.玩家信息界面.刷新经验值显示();

		if (_root.升级需要经验值 <= 当前经验值 && _root.等级 < _root.等级限制)
		{
			_root.玩家信息界面.主角经验值显示界面.frame = 100;
			_root.等级++;
			_root.技能点数 += _root.根据等级计算获得技能点(_root.等级);
			// _root.聊天窗.传言("勤奋的" + _root.玩家称号 + _root.角色名 + "升到了" + _root.等级 + "级！");
			是否升级 = true;
		}
		else
		{
			是否完成全部升级 = true;
		}
	}

	if (是否升级) {
		_root.身价 = _root.基础身价值 * _root.等级;
		var 控制对象 = TargetCacheManager.findHero();
		控制对象.等级 = _root.等级;
		控制对象.根据等级初始数值(_root.等级);
		控制对象.hp = 控制对象.hp满血值;
		控制对象.mp = 控制对象.mp满血值;
		_root.玩家信息界面.刷新hp显示();
		_root.玩家信息界面.刷新mp显示();
		EffectSystem.Effect("升级动画",控制对象._x,控制对象._y,100);
		// 资产事务内的升级延迟到领域提交后强存盘；普通战斗/健身路径仍立即执行。
		org.flashNight.arki.item.PlayerAssetTransaction.requestStrongSave();
	}
}

_root.经验值计算 = function(最小经验值, 最大经验值, 怪物等级, 怪物最大等级){
	var tmp_exp = Math.floor((最小经验值 + (最大经验值 - 最小经验值) / (怪物最大等级 - 1) * 怪物等级) * _root.难度等级);
	if (isNaN(tmp_exp) || tmp_exp <= 1) tmp_exp = 1;
	
	//战宠加经验
	for (var i = 0; i < _root.出战宠物id库.length; i++){
		var petid = 出战宠物id库[i];
		var 宠物对象 = _root.宠物mc库[i];
		var 当前宠物信息 = _root.宠物信息[petid];
		if (宠物对象.hp > 0 && 当前宠物信息[4] == 1){
			// 宠物进度独立于玩家等级上限；在首次宠物经验/结构写入前标脏，
			// 避免满级玩家跳过下方主角经验分支后丢失本场宠物成长。
			if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
			//
			if (当前宠物信息.length < 6) 当前宠物信息.push({});
			if (!当前宠物信息[5] || typeof 当前宠物信息[5] == "number") 当前宠物信息[5] = {};
			if (!当前宠物信息[5].宠物升级经验) 当前宠物信息[5].宠物升级经验 = 0;
			
			var 旧升级阈值:Number = Number(当前宠物信息[5].宠物升级所需经验);
			if (!isFinite(旧升级阈值) || !(旧升级阈值 > 0)) {
				当前宠物信息[5].宠物升级所需经验 = _root.战宠UI函数.计算战宠升级所需经验(
					宠物对象.兵种, 宠物对象.等级);
			}

			当前宠物信息[5].宠物升级经验 += tmp_exp;

			if (当前宠物信息[5].宠物升级经验 > 当前宠物信息[5].宠物升级所需经验 && 当前宠物信息[1] < 等级限制){
				当前宠物信息[1]++;
				当前宠物信息[5].宠物升级经验 = 0;
				// 先提交完整等级事实，再把场景重建当成可恢复投影。Dressup 战宠升级会
				// 替换 MovieClip，下一档阈值必须只读存档与宠物库权威。
				当前宠物信息[5].宠物升级所需经验 = _root.战宠UI函数.计算战宠升级所需经验(
					_root.宠物库[当前宠物信息[0]].Identifier, 当前宠物信息[1]);
				var 升级重建完成:Boolean = false;
				try{
					升级重建完成 = _root.宠物升级加载(i) === true;
				}catch(升级重建错误){
					// 等级事实已经提交；场景重建只是升级冷路投影，异常不能中断
					// 后续宠物/玩家经验结算，也不能把本次升级伪装成可重试失败。
					trace("[战宠升级] 场景重建失败: " + 升级重建错误);
				}
				try{
					_root.战宠UI函数.记录宠物刷新结果(
						petid, 升级重建完成, "auto_level_up");
				}catch(刷新标记错误){
					trace("[战宠升级] refresh-deferred 标记失败: " + 刷新标记错误);
				}
				try{
					_root.发布消息("宠物" + _root.战宠UI函数.获取宠物显示名(petid) + "已升级！");
				}catch(升级提示错误){
					trace("[战宠升级] 提示失败: " + 升级提示错误);
				}
			}
		}
	}

	_root.等级 = Number(_root.等级);
	if (_root.等级 < _root.等级限制){
		if (isNaN(_root.经验值)) _root.经验值 = _root.等级 > 1 ? 根据等级得升级所需经验(_root.等级 - 1) : 0;

		if (_root.等级 > 怪物等级)
		{
			tmp_exp = Math.floor(tmp_exp / (_root.等级 - 怪物等级) * _root.难度等级);
		}
		_root.经验值 = Number(_root.经验值) + tmp_exp;
		// Plan A audit: 经验值变更必须标脏；升级路径已 flushNow，不升级时本标脏保证 debounce 落盘
		_root.存档系统.dirtyMark = true;
		_root.主角是否升级(_root.等级,_root.经验值);
	}
}

_root.宠物升级加载 = function(mc库索引):Boolean{
	// 兼容旧调用者的 mc 库索引，但所有单位类型都交给同一个同步两阶段入口；
	// 不再保留 Dressup 重建、普通宠原地改值两套容易漂移的升级实现。
	var 宠物信息数组号 = Number(_root.出战宠物id库[mc库索引]);
	if(!isFinite(宠物信息数组号) || 宠物信息数组号 < 0) return false;
	var 当前宠物信息 = _root.宠物信息[宠物信息数组号];
	if(!当前宠物信息 || 当前宠物信息[4] != 1 || !(Number(当前宠物信息[2]) >= 0)) return false;
	return _root.战宠UI函数.重建宠物单位(
		宠物信息数组号, true, "升级动画2") === true;
}

