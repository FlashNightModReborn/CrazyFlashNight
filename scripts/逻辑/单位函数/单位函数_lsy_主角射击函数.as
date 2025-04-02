import org.flashNight.arki.unit.Action.Shoot.*;

_root.主角函数.开始射击 = function(){
	var 攻击模式 = _parent.攻击模式;
	if (_parent.主手射击中 || this.换弹标签) return;
	if (_parent[攻击模式 + "射击次数"][_parent[攻击模式]] >= _parent[攻击模式 + "弹匣容量"])
	{
		if(剩余弹匣数 > 0 || _root.控制目标 != _parent._name) 开始换弹();
		return;
	}
	if (!this.射击许可标签) return;
	var 继续射击许可 = this.主手持续射击(_parent, 攻击模式, this.射击速度);
	if(继续射击许可){
		_parent.keepshooting = _root.帧计时器.添加生命周期任务(_parent, "开始射击", this.主手持续射击, this.射击速度, _parent, 攻击模式, this.射击速度);
		if(this.射击速度 > 300){
			_root.帧计时器.添加或更新任务(_parent, "结束射击后摇", function(自机){自机.射击最大后摇中 = false;}, 300, _parent);
		}
	}
}

// 主手持续射击包装函数
_root.主角函数.主手持续射击 = function(core, attackMode, shootSpeed){
    return ShootCore.continuousShoot(core, attackMode, shootSpeed, 
           ShootCore.primaryParams);
};

// 副手持续射击包装函数
_root.主角函数.副手持续射击 = function(core, attackMode, shootSpeed){
    return ShootCore.continuousShoot(core, attackMode, shootSpeed, 
           ShootCore.secondaryParams);
};



_root.主角函数.开始换弹 = function()
{
	var 攻击模式 = _parent.攻击模式;
	if(this.换弹标签 || _parent[攻击模式 + "射击次数"][_parent[攻击模式]] == 0) return;
	if (_root.控制目标 === _parent._name)
	{
		if(org.flashNight.arki.item.ItemUtil.singleContain(使用弹匣名称,1) != null){
			gotoAndPlay("换弹匣");
		}
		// for(var i = 0; i < _root.物品栏总数; i++)
		// {
		// 	if (_root.物品栏[i][0] === 使用弹匣名称 && _root.物品栏[i][1] >= 1)
		// 	{
		// 		this.弹匣所在物品栏编号 = i;
		// 		gotoAndPlay("换弹匣");
		// 		return;
		// 	}
		// }
	}
	else
	{
		gotoAndPlay("换弹匣");
	}
}

_root.主角函数.换弹匣 = function(){
	var 攻击模式 = _parent.攻击模式;
	_parent[攻击模式 + "射击次数"][_parent[攻击模式]] = 0;
	if (_root.控制目标 === _parent._name)
	{
		org.flashNight.arki.item.ItemUtil.singleSubmit(使用弹匣名称,1);
		// if(--_root.物品栏[弹匣所在物品栏编号][1] <= 0){
		// 	_root.物品栏[弹匣所在物品栏编号] = ["空", 0, 0];
		// }
		剩余弹匣数 = _parent.检查弹匣数量(使用弹匣名称);
		if(剩余弹匣数 === 0) _root.发布消息("弹匣耗尽！");
		_root.排列物品图标();
		_parent.当前弹夹副武器已发射数 = 0;
		刷新弹匣数显示();
	}
}

_root.主角函数.结束换弹 = function(){
	gotoAndStop("空闲");
}

_root.主角函数.刷新弹匣数显示 = function(){
	if(_root.控制目标 != _parent._name) return;
	var 攻击模式 = _parent.攻击模式;
	if(攻击模式 === "双枪"){
		_root.玩家信息界面.玩家必要信息界面.子弹数 = _parent.手枪弹匣容量 - _parent.手枪射击次数[_parent.手枪];
		_root.玩家信息界面.玩家必要信息界面.弹夹数 = 主手剩余弹匣数;
		_root.玩家信息界面.玩家必要信息界面.子弹数_2 = _parent.手枪2弹匣容量 - _parent.手枪2射击次数[_parent.手枪2];
		_root.玩家信息界面.玩家必要信息界面.弹夹数_2 = 副手剩余弹匣数;
	}else{
		_root.玩家信息界面.玩家必要信息界面.子弹数 = _parent[攻击模式 + "弹匣容量"] - _parent[攻击模式 + "射击次数"][_parent[攻击模式]];
		_root.玩家信息界面.玩家必要信息界面.弹夹数 = 剩余弹匣数;
	}
}


/*

**核心函数：初始化武器系统
说明：
  target：目标剪辑（MovieClip），原先依赖时间轴代码的 clip
  _parent：原来在时间轴中可直接访问的父级对象（保持不变或显式传入）
  config：配置对象，说明如下：

    weaponType：武器类型（"长枪"、"手枪"、"手枪2"、"双枪"）
    isDualGun：是否为双枪模式（true/false）

    // 以下针对“单武器”和“双枪”两种模式有所不同：
    weaponData：单武器模式下的属性数组（双枪模式下可忽略）
    mainWeaponData：双枪模式下主手属性数组
    subWeaponData： 双枪模式下副手属性数组

    extraParams：
       - 对于单武器：直接传入特殊属性（如毒、吸血等）
       - 对于双枪：应包含 { main: {...}, sub: {...} } 分别对应主手与副手的特殊属性
 */
_root.主角函数._初始化武器系统 = function(target, _parent, config)
{
    // 检查攻击模式是否匹配
    if(_parent.攻击模式 != config.weaponType) {
        return;
    }

    // 将原来依赖于时间轴的函数及属性显式绑定到 target 上
    target.开始射击       = _root.主角函数.开始射击;
    target.主手持续射击   = _root.主角函数.主手持续射击;
    target.副手持续射击   = _root.主角函数.副手持续射击; // 双枪时才会用到
    target.开始换弹       = _root.主角函数.开始换弹;
    target.换弹匣         = _root.主角函数.换弹匣;
    target.结束换弹       = _root.主角函数.结束换弹;
    target.刷新弹匣数显示 = _root.主角函数.刷新弹匣数显示;

    // -------------------- 双枪模式 --------------------
    if(config.isDualGun)
    {
        // 双枪模式下不使用 config.weaponData，而分别使用 mainWeaponData 与 subWeaponData
        var mainData = config.mainWeaponData;
        var subData  = config.subWeaponData;

        // 主手、副手的额外参数（例如毒、吸血、伤害类型、暴击、斩杀等）
        var mainExtra = (config.extraParams && config.extraParams.main) ? config.extraParams.main : {};
        var subExtra  = (config.extraParams && config.extraParams.sub)  ? config.extraParams.sub  : {};

        // 初始化主手属性
        target.主手射击速度     = mainData[5];
        target.主手使用弹匣名称 = mainData[11];
        target.主手是否单发     = mainData[3];
        target.主手剩余弹匣数   = _parent.检查弹匣数量(target.主手使用弹匣名称);

        // 初始化副手属性
        target.副手射击速度     = subData[5];
        target.副手使用弹匣名称 = subData[11];
        target.副手是否单发     = subData[3];
        target.副手剩余弹匣数   = _parent.检查弹匣数量(target.副手使用弹匣名称);

        // 刷新显示
        target.刷新弹匣数显示();

        // 分别生成主手与副手的子弹属性对象
        target.子弹属性  = _root.主角函数._生成子弹属性(_parent, "手枪",  mainData, mainExtra);
        target.子弹属性2 = _root.主角函数._生成子弹属性(_parent, "手枪2", subData,  subExtra);

        //------------------------------------------------
        // 修复后：与帧标签对应 —— 保持 “主手换弹匣”、“副手换弹匣” 命名
        //------------------------------------------------

        // 主手开始射击
        target.主手开始射击 = function()
        {
            if (_parent.主手射击中 || target.换弹标签) return;
            // 若主手子弹已打空，尝试换弹
            if(_parent.手枪射击次数[_parent.手枪] >= _parent.手枪弹匣容量)
            {
                // 判断物品栏有没有主手弹匣，若有则 gotoAndPlay("主手换弹匣")
                if(org.flashNight.arki.item.ItemUtil.singleContain(target.主手使用弹匣名称, 1)){
                    target.gotoAndPlay("主手换弹匣");
                }
                else {
                    // 若副手也打空则一起换弹
                    if((_parent.手枪2射击次数[_parent.手枪2] >= _parent.手枪2弹匣容量 && target.主手剩余弹匣数 > 0)
                       || _root.控制目标 != _parent._name)
                    {
                        target.开始换弹();
                    }
                }
                return;
            }
            if(!target.射击许可标签) return;
            var 继续射击许可 = target.主手持续射击(_parent, "手枪", target.主手射击速度, target);
            if(继续射击许可) {
                _parent.keepshooting = _root.帧计时器.添加生命周期任务(
                    _parent,
                    "主手开始射击",
                    target.主手持续射击,
                    target.主手射击速度,
                    _parent, "手枪", target.主手射击速度
                );
            }
        };

        // 副手开始射击
        target.副手开始射击 = function()
        {
            if (_parent.副手射击中 || target.换弹标签) return;
            // 若副手子弹已打空，尝试换弹
            if(_parent.手枪2射击次数[_parent.手枪2] >= _parent.手枪2弹匣容量)
            {
                // 判断物品栏有没有副手弹匣，若有则 gotoAndPlay("副手换弹匣")
                if(org.flashNight.arki.item.ItemUtil.singleContain(target.副手使用弹匣名称, 1)){
                    target.gotoAndPlay("副手换弹匣");
                }
                else {
                    // 若主手也打空则一起换弹
                    if((_parent.手枪射击次数[_parent.手枪] >= _parent.手枪弹匣容量 && target.副手剩余弹匣数 > 0)
                       || _root.控制目标 != _parent._name)
                    {
                        target.开始换弹();
                    }
                }
                return;
            }
            if(!target.射击许可标签) return;
            var 继续射击许可 = target.副手持续射击(_parent, "手枪2", target.副手射击速度, target);
            if(继续射击许可) {
                _parent.keepshooting2 = _root.帧计时器.添加生命周期任务(
                    _parent,
                    "副手开始射击",
                    target.副手持续射击,
                    target.副手射击速度,
                    _parent, "手枪2", target.副手射击速度
                );
            }
        };

        // 主手换弹匣（与动画帧标签一致）
        target.主手换弹匣 = function()
        {
            _parent.手枪射击次数[_parent.手枪] = 0;
            if (_root.控制目标 === _parent._name){
                // 扣掉一个主手弹匣
                org.flashNight.arki.item.ItemUtil.singleSubmit(target.主手使用弹匣名称, 1);
                // 更新剩余弹匣数
                target.主手剩余弹匣数 = _parent.检查弹匣数量(target.主手使用弹匣名称);
                target.副手剩余弹匣数 = _parent.检查弹匣数量(target.副手使用弹匣名称);

                if(target.主手剩余弹匣数 === 0) {
                    _root.发布消息("弹匣耗尽！");
                }
                _root.排列物品图标();
                target.刷新弹匣数显示();
                
                // 若副手也没弹匣或者副手本身已打空，则结束换弹动作
                if(target.副手剩余弹匣数 == 0 || _parent.手枪2射击次数[_parent.手枪2] == 0){
                    target.gotoAndPlay("换弹结束");
                }
            }
        };

        // 副手换弹匣（与动画帧标签一致）
        target.副手换弹匣 = function()
        {
            _parent.手枪2射击次数[_parent.手枪2] = 0;
            if (_root.控制目标 === _parent._name){
                // 扣掉一个副手弹匣
                org.flashNight.arki.item.ItemUtil.singleSubmit(target.副手使用弹匣名称, 1);
                // 更新剩余弹匣数
                target.主手剩余弹匣数 = _parent.检查弹匣数量(target.主手使用弹匣名称);
                target.副手剩余弹匣数 = _parent.检查弹匣数量(target.副手使用弹匣名称);

                if(target.副手剩余弹匣数 === 0) {
                    _root.发布消息("弹匣耗尽！");
                }
                _root.排列物品图标();
                target.刷新弹匣数显示();
            }
        };

        // 全局开始换弹函数：根据主手/副手是否还剩子弹，以及物品栏是否有对应弹匣来决定流程
        target.开始换弹 = function()
        {
            // 若正在换弹 或者 主副手皆无弹可换（已是空枪且无需要换弹），则直接返回
            if(target.换弹标签 || (_parent.手枪射击次数[_parent.手枪] == 0 && _parent.手枪2射击次数[_parent.手枪2] == 0)) {
                return;
            }
            // 如果当前角色是玩家可控，才检查物品栏
            if (_root.控制目标 === _parent._name)
            {
                // 如果主手还有子弹可换
                if(_parent.手枪射击次数[_parent.手枪] > 0){
                    if(org.flashNight.arki.item.ItemUtil.singleContain(target.主手使用弹匣名称, 1)){
                        target.gotoAndPlay("主手换弹匣");
                        return;
                    }
                }
                // 否则如果副手还有子弹可换
                else if(_parent.手枪2射击次数[_parent.手枪2] > 0) {
                    if(org.flashNight.arki.item.ItemUtil.singleContain(target.副手使用弹匣名称, 1)){
                        target.gotoAndPlay("副手换弹匣");
                        return;
                    }
                }
                // 如果两手都没子弹可换 或 没有对应弹匣，就直接结束
                target.gotoAndPlay("换弹结束");
            }
            else
            {
                // AI 或非玩家控制角色，直接默认用主手换弹
                target.gotoAndPlay("主手换弹匣");
            }
        };
    }
    // -------------------- 单武器模式 --------------------
    else
    {
        var weaponData  = config.weaponData;
        var extraParams = config.extraParams || {};

        target.射击速度      = weaponData[5];
        target.使用弹匣名称  = weaponData[11];
        target.是否单发      = weaponData[3];

        target.剩余弹匣数 = _parent.检查弹匣数量(target.使用弹匣名称);
        target.刷新弹匣数显示();

        target.子弹属性 = _root.主角函数._生成子弹属性(_parent, config.weaponType, weaponData, extraParams);
    }

};

/**工厂方法：生成子弹属性对象
说明：
  _parent：角色对象（用于读取被动技能、特殊属性等）
  weaponType：武器类型，如 "长枪"、"手枪"、"手枪2"、"双枪" 等
  weaponData：属性数组（各索引含义依据项目定义）
  extraParams：特殊属性（例如伤害类型、魔法伤害、毒、吸血、击溃、暴击、斩杀等）
 */
_root.主角函数._生成子弹属性 = function(_parent, weaponType, weaponData, extraParams)
{
    var 子弹属性 = new Object();
    子弹属性.发射者 = _parent._name;
    子弹属性.声音   = weaponData[8];

    // 读取散射度及移动射击修正
    子弹属性.霰弹值         = weaponData[1];
    子弹属性.子弹散射度     = weaponData[2];
    子弹属性.站立子弹散射度 = weaponData[2];
    var 移动射击等级 = (_parent.被动技能.移动射击 && _parent.被动技能.移动射击.启用 && _parent.被动技能.移动射击.等级)
                       ? _parent.被动技能.移动射击.等级 : 0;
    子弹属性.移动子弹散射度 = weaponData[2] + 10 - (移动射击等级 * 1);

    子弹属性.发射效果         = weaponData[9];
    子弹属性.子弹种类         = weaponData[7];
    子弹属性.子弹速度         = weaponData[6];
    子弹属性.击中地图效果     = weaponData[10];
    子弹属性.Z轴攻击范围      = weaponData[12];
    子弹属性.击倒率           = weaponData[14];
    子弹属性.击中后子弹的效果 = weaponData[15];
    子弹属性.子弹敌我属性     = !_parent.是否为敌人;

    // 计算子弹威力，含被动技能加成
    var basePower  = weaponData[13];
    var finalPower = basePower;
    if(_parent.被动技能.枪械攻击 && _parent.被动技能.枪械攻击.启用)
    {
        if(weaponType == "长枪") {
            finalPower = basePower * (1.5 + _parent.被动技能.枪械攻击.等级 * 0.03) + 30;
        } else {
            finalPower = basePower * (1 + _parent.被动技能.枪械攻击.等级 * 0.015) + 20;
        }
    }
    if(weaponType == "长枪" && _parent.长枪额外攻击加成倍率) {
        finalPower += basePower * _parent.长枪额外攻击加成倍率;
    }
    if((weaponType == "手枪" || weaponType == "手枪2") && _parent.短枪额外攻击加成倍率) {
        finalPower += basePower * _parent.短枪额外攻击加成倍率;
    }
    子弹属性.子弹威力 = finalPower;

    // 特殊属性：优先使用 extraParams 指定的设置，其次才尝试 _parent 里的同名属性
    // （如 extraParams.毒、_parent["手枪毒"] 等）
    if(extraParams.伤害类型){
        子弹属性.伤害类型 = extraParams.伤害类型;
    } else if(_parent[weaponType + "伤害类型"]) {
        子弹属性.伤害类型 = _parent[weaponType + "伤害类型"];
    }
    if(extraParams.魔法伤害属性){
        子弹属性.魔法伤害属性 = extraParams.魔法伤害属性;
    } else if(_parent[weaponType + "魔法伤害属性"]) {
        子弹属性.魔法伤害属性 = _parent[weaponType + "魔法伤害属性"];
    }
    if(extraParams.毒){
        子弹属性.毒 = extraParams.毒;
    } else if(_parent[weaponType + "毒"]) {
        子弹属性.毒 = _parent[weaponType + "毒"];
    }
    if(extraParams.吸血){
        子弹属性.吸血 = extraParams.吸血;
    } else if(_parent[weaponType + "吸血"]) {
        子弹属性.吸血 = _parent[weaponType + "吸血"];
    }
    if(extraParams.击溃){
        子弹属性.血量上限击溃 = extraParams.击溃;
    } else if(_parent[weaponType + "击溃"]) {
        子弹属性.血量上限击溃 = _parent[weaponType + "击溃"];
    }

    // 处理暴击逻辑
    var critValue = (extraParams.暴击 !== undefined) ? extraParams.暴击 : _parent[weaponType + "暴击"];
    if(critValue) {
        子弹属性.暴击 = _root.主角函数._创建暴击逻辑(critValue);
    }

    // 处理斩杀逻辑
    var killValue = (extraParams.斩杀 !== undefined) ? extraParams.斩杀 : _parent[weaponType + "斩杀"];
    if(killValue && !isNaN(Number(killValue))) {
        子弹属性.斩杀 = Number(killValue);
    }

    return 子弹属性;
};

/** 根据暴击参数生成暴击判断函数
  参数 critValue 可能为数值(如20表示20%暴击率)或字符串("满血暴击")
*/
_root.主角函数._创建暴击逻辑 = function(critValue)
{
    if(!isNaN(Number(critValue)))
    {
        var critRate = Number(critValue);
        return function(当前子弹) {
            if(_root.成功率(critRate)) {
                return 1.5;
            }
            return 1.0;
        };
    }
    else if(critValue == "满血暴击")
    {
        return function(当前子弹) {
            if(当前子弹.hitTarget.hp >= 当前子弹.hitTarget.hp满血值) {
                return 1.5;
            }
            return 1.0;
        };
    }
    // 默认不触发暴击
    return function(当前子弹) { return 1.0; };
};

/** 以下为“各武器初始化包装函数”：仅负责构造配置参数并调用核心函数 _初始化武器系统
 *  注意：所有包装函数均要求显式传入目标剪辑 this，以便内部使用 gotoAndPlay() 时，能正确作用于当前clip
 */
// 长枪初始化
_root.主角函数.初始化长枪射击函数 = function()
{
    _root.主角函数._初始化武器系统(
        this,
        _parent,
        {
            weaponType: "长枪",
            weaponData: _parent.长枪属性数组[14],
            isDualGun : false,
            extraParams: {}
        }
    );
};

// 手枪初始化
_root.主角函数.初始化手枪射击函数 = function()
{
    _root.主角函数._初始化武器系统(
        this,
        _parent,
        {
            weaponType: "手枪",
            weaponData: _parent.手枪属性数组[14],
            isDualGun : false,
            extraParams: {}
        }
    );
};

// 手枪2初始化
_root.主角函数.初始化手枪2射击函数 = function()
{
    _root.主角函数._初始化武器系统(
        this,
        _parent,
        {
            weaponType: "手枪2",
            weaponData: _parent.手枪2属性数组[14],
            isDualGun : false,
            extraParams: {}
        }
    );
};

// 双枪初始化
_root.主角函数.初始化双枪射击函数 = function()
{
    // 构造主手与副手各自的特殊属性参数
    var mainExtra = {
        伤害类型        : _parent.手枪伤害类型,
        魔法伤害属性    : _parent.手枪魔法伤害属性,
        毒              : _parent.手枪毒,
        吸血            : _parent.手枪吸血,
        击溃            : _parent.手枪击溃,
        暴击            : _parent.手枪暴击,
        斩杀            : _parent.手枪斩杀
    };
    var subExtra = {
        伤害类型        : _parent.手枪2伤害类型,
        魔法伤害属性    : _parent.手枪2魔法伤害属性,
        毒              : _parent.手枪2毒,
        吸血            : _parent.手枪2吸血,
        击溃            : _parent.手枪2击溃,
        暴击            : _parent.手枪2暴击,
        斩杀            : _parent.手枪2斩杀
    };

    _root.主角函数._初始化武器系统(
        this,
        _parent,
        {
            weaponType     : "双枪",
            isDualGun      : true,
            mainWeaponData : _parent.手枪属性数组[14],
            subWeaponData  : _parent.手枪2属性数组[14],
            extraParams    : { main: mainExtra, sub: subExtra }
        }
    );
};
