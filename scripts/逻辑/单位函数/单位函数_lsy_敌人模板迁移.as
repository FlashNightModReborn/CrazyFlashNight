import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.arki.unit.*;
import org.flashNight.naki.RandomNumberEngine.*

//容纳敌人函数的对象
_root.敌人函数 = new Object();


//以下14个是原版敌人的必要函数

_root.敌人函数.根据等级初始数值 = function(等级值){
	//_root.服务器.发布服务器消息("unit: " + this._name + " at level: " + 等级值)
	
	hp满血值 = _root.根据等级计算值(hp_min, hp_max, 等级值) * _root.难度等级;
	空手攻击力 = _root.根据等级计算值(空手攻击力_min, 空手攻击力_max, 等级值) * _root.难度等级;
	行走X速度 = _root.根据等级计算值(速度_min, 速度_max, 等级值) / 10;
	行走Y速度 = 行走X速度 / 2;
	跑X速度 = 行走X速度 * 奔跑速度倍率;
	跑Y速度 = 行走Y速度 * 奔跑速度倍率;
	// 被击硬直度 = _root.根据等级计算值(被击硬直度_min, 被击硬直度_max, 等级值);
	起跳速度 = isNaN(起跳速度) ? -10 : 起跳速度;
	基本防御力 = _root.根据等级计算值(基本防御力_min, 基本防御力_max, 等级值);
	防御力 = 基本防御力 + 装备防御力;
	躲闪率 = _root.根据等级计算值(躲闪率_min, 躲闪率_max, 等级值, true, true); // 允许小数，且在60级后不再增长防止出现小于1的躲闪率
	hp = !isNaN(hp) ? hp : hp满血值;
};

_root.敌人函数.获取线性插值经验值 = function(target, list:Array){
	var level = target.等级;
	if(list.length > 2){
		for(var i = 0; i < list.length - 1; i++){
			if(level < list[i+1].level) break;
		}
	}
	target.最小经验值 = _root.常用工具函数.线性插值(1, list[i].level, list[i+1].level, list[i].value, list[i+1].value);
	target.最大经验值 = _root.常用工具函数.线性插值(_root.最大等级, list[i].level, list[i+1].level, list[i].value, list[i+1].value);
	// _root.发布消息(target.最小经验值 + " " + target.最大经验值);
}

_root.敌人函数.宠物属性初始化 = function(等级值){
	if(宠物属性){
		for(var key in 宠物属性){
			if(_root.战宠进阶函数[key] && _root.战宠进阶函数[key].单位进阶执行){
				this.单位进阶执行 = _root.战宠进阶函数[key].单位进阶执行;
				this.单位进阶执行();
			}
		}
	}
	hp = !isNaN(hp) ? hp : hp满血值;
};

_root.敌人函数.行走 = function() {
    if (this.右行 || this.左行 || this.上行 || this.下行) {
        // 定义策略对象，封装跑和走两种移动方式的参数
        var 移动策略 = {
            跑: {
                x速度: 跑X速度,
                y速度: 跑Y速度,
                状态后缀: "跑"
            },
            走: {
                x速度: 行走X速度,
                y速度: 行走Y速度,
                状态后缀: "行走"
            }
        };

        // 根据当前状态判断使用哪一种策略
        // 如果当前状态为攻击模式+"跑"，则使用跑的参数，否则使用走的参数
        var 初始目标状态 = 攻击模式 + "跑";
        var 最终策略 = (this.状态 === 初始目标状态) ? 移动策略.跑 : 移动策略.走;
        var 最终状态 = 攻击模式 + 最终策略.状态后缀;

        // 根据方向选择对应的移动操作
        if (this.右行) {
            方向改变("右");
            移动("右", 最终策略.x速度);
        } else if (this.左行) {
            方向改变("左");
            移动("左", 最终策略.x速度);
        }
        if (this.下行) {
            移动("下", 最终策略.y速度);
        } else if (this.上行) {
            移动("上", 最终策略.y速度);
        }

        // 改变状态为最终状态
        this.状态改变(最终状态);
    } else {
        // 没有移动操作时，设置为攻击模式+站立状态
        this.状态改变(攻击模式 + "站立");
    }
};


_root.敌人函数.移动 = function(移动方向, 速度) {
    Mover.move2D(this, 移动方向, 速度);
};



_root.敌人函数.被击移动 = function(移动方向, 速度, 摩擦力){
	if(免疫击退) return;
	this.移动钝感硬直(_root.钝感硬直时间);
	this.减速度 = 摩擦力;
	this.speed = 速度;
	this.onEnterFrame = function(){
		if (!硬直中){
			speed -= 减速度;
			if (speed <= 0){
				delete this.onEnterFrame;
				return;
			}
			this.移动(移动方向,speed);
		}
	};
};

_root.敌人函数.强制移动 = _root.主角函数.强制移动;


_root.敌人函数.方向改变 = function(新方向){
	if(锁定方向) return;
	if (新方向 === "右"){
		方向 = "右";
		this._xscale = myxscale;
		新版人物文字信息._xscale = 100;
	}else if (新方向 === "左"){
		方向 = "左";
		this._xscale = -myxscale;
		新版人物文字信息._xscale = -100;
	}
};

_root.敌人函数.状态改变 = function(新状态名) {
	if (this.状态 == 新状态名) return; // 已经处于该状态，跳过
	
	// this.旧状态 = this.状态; // 记录上一个状态名
	this.gotoAndStop(this.状态 = 新状态名);
};



_root.敌人函数.动画完毕 = function() {
	状态改变(hp <= 0 ? "血腥死" : 攻击模式 + "站立"); // 防止没有倒地动画的敌人在击倒动画被扣至0血导致不死
	// 考虑到该函数较为低频，一些状态更新顺带在此触发
	this.倒地 = false;
	this.aabbCollider.updateFromUnitArea(this); // 起身时更新碰撞箱
};

_root.敌人函数.硬直 = function(目标, 时间) {
	if(this.stiffID != null) return;
	var 自机:Object = this;  // 在外部保存对当前对象的引用
    目标.stop();

    this.stiffID = _root.帧计时器.添加或更新任务(目标, "硬直", function() {
		自机.stiffID = null;
        目标.play();
    }, 时间); 
};

_root.敌人函数.移动钝感硬直 = _root.主角函数.移动钝感硬直;


_root.敌人函数.随机掉钱 = function(){
	if (!this.不掉钱 && random(_root.打怪掉钱机率) === 0){
		var 金币时间倍率 = _root.天气系统.金币时间倍率;
		//_root.发布消息("金币时间倍率" + 金币时间倍率);
		var 昼夜爆金币 = this.hp满血值 * 金币时间倍率 / 5;
		
		_root.pickupItemManager.createCollectible("金钱",random(昼夜爆金币),this._x,this._y,true);
	}
};

_root.敌人函数.计算经验值 = function(){
	this.随机掉钱();
	this.掉落物判定();

	var 经验时间倍率 = _root.天气系统.经验时间倍率;
	
	//_root.发布消息("经验时间倍率" + 经验时间倍率);
	_root.经验值计算(最小经验值 * 经验时间倍率,最大经验值 * 经验时间倍率,等级,_root.最大等级);
	_root.主角是否升级(_root.等级,_root.经验值);
	this.已加经验值 = true;
};

_root.敌人函数.攻击呐喊 = function(){
	var arr:Array = 性别 === "女" ? 女_攻击呐喊_库 : 男_攻击呐喊_库;
	_root.soundEffectManager.playSound(LinearCongruentialEngine.instance.getRandomArrayElement(arr));
};

_root.敌人函数.中招呐喊 = function(){
	var arr:Array = 性别 === "女" ? 女_中招呐喊_库 : 男_中招呐喊_库;
	_root.soundEffectManager.playSound(LinearCongruentialEngine.instance.getRandomArrayElement(arr));
};

_root.敌人函数.击倒呐喊 = function(){
	var time = getTimer();
	if(time - this.上次击倒呐喊时间 < 300) return; // 击倒呐喊的最低间隔为300毫秒
	this.上次击倒呐喊时间 = time;

	var arr:Array = 性别 === "女" ? 女_击倒呐喊_库 : 男_击倒呐喊_库;
	_root.soundEffectManager.playSound(LinearCongruentialEngine.instance.getRandomArrayElement(arr));
};


//以下是新增或新整合的函数


/*
死亡检测统一函数
可传的参数：
noCount: 不计入关卡杀怪数
noCorpse: 不贴尸体
remainMovie: 不卸载元件

例：
_parent.死亡检测();
_parent.死亡检测({noCount:true});
_parent.死亡检测({noCorpse:true});
_parent.死亡检测({remainMovie:true});
_parent.死亡检测({noCount:true, noCorpse:true});
*/
_root.敌人函数.死亡检测 = function(para){
	if (hp <= 0 && !已加经验值){
		this.man.stop();
		if (是否为敌人 === true || 是否为敌人 === "null"){
			if(是否为敌人 === true && para.noCount !== true){
				_root.敌人死亡计数++;
				_root.gameworld[产生源].僵尸型敌人场上实际人数--;
				_root.gameworld[产生源].僵尸型敌人总个数--;
			}
			this.计算经验值();
		}
		this.人物文字信息._visible = false;
		this.新版人物文字信息._visible = false;
		if(para.remainMovie === true){
			StaticDeinitializer.deinitializeUnit(this); // 不卸载元件直接注销单位
		}else{
			if(para.noCorpse !== true) _root.add2map(this,2); // 检测是否需要贴尸体
			this.removeMovieClip(); // 移除单位
		}
	}	
};


_root.敌人函数.掉落物判定 = function(){
	if(!掉落物) return;
	if(掉落物.length > 0){
		for(var i = 掉落物.length - 1; i > -1; i--){
			掉落物品(掉落物[i]);
			if(掉落物[i].总数 <= 0){
				掉落物.splice(i,1);
			}
		}
	}else if(掉落物.名字){
		掉落物品(掉落物);
		if(掉落物.总数 <= 0){
			掉落物 = null;
		}
	}
}

_root.敌人函数.掉落物品 = function(item){
	if(isNaN(item.概率)) item.概率 = 100;
	if(item.名字 && _root.成功率(item.概率)){
		if(isNaN(item.最小数量) || isNaN(item.最大数量)){
			item.最小数量 = item.最大数量 = 1;
		}
		if(isNaN(item.总数)) item.总数 = item.最大数量;
		var 数量 = item.最小数量 + random(item.最大数量 - item.最小数量 + 1);
		if(item.总数 < 数量) 数量 = item.总数;
		item.总数 -= 数量;
		var yoffset = random(21) - 10;
		_root.pickupItemManager.createCollectible(item.名字,数量,this._x, this._y + yoffset, true);
	}
}

_root.敌人函数.fly = function(target:MovieClip){
	if(target.硬直中 == false){
		target._y += target.垂直速度;
		target.垂直速度 += _root.重力加速度;
		target.aabbCollider.updateFromUnitArea(target); // 更新碰撞箱
	}
	if(target._y >= target.Z轴坐标){
		target._y = target.Z轴坐标;
		target.浮空 = false;
		_root.帧计时器.移除任务(target.flyID);
		target.flyID = null;
		if(target.状态 == "击倒"){
			target.状态改变("倒地");
		}
	}
}

_root.敌人函数.击飞浮空 = function(){
	if(this.flyID != null) return;
	this.浮空 = true;
	this.倒地 = false;
	this.man.落地 = false;
	if(this._y >= this.Z轴坐标) this._y = this.Z轴坐标 - 1;
	if(this.垂直速度 >= this.起跳速度) this.垂直速度 = this.起跳速度;

	this.flyID = _root.帧计时器.添加生命周期任务(this, "击飞浮空", _root.敌人函数.fly, 1, this);
}

_root.敌人函数.击飞倒地 = function(){
	this._y = this.Z轴坐标;
	this.垂直速度 = 0;
	this.倒地 = true;
	this.aabbCollider.updateFromUnitArea(this); // 倒地时更新碰撞箱
}

_root.敌人函数.尝试拾取 = function(){
	var 拾取对象 = _root.gameworld[this.拾取目标];
	this.拾取目标 = "无";
	if (!拾取对象.area){
		return;
	}
	if (this.是否为敌人 === false){
		if (_root.物品栏.背包.getFirstVacancy() > -1){
			_root.pickupItemManager.pickup(拾取对象, this, false);
		}
	}else{
		拾取对象.gotoAndPlay("消失");
	}
}


_root.敌人函数.应用影子色彩 = function(target:MovieClip){
	if(target.影子单位){
		target.影子倍率 = target.影子倍率? target.影子倍率 : 0;
		target.透明倍率 =  target.透明倍率? target.透明倍率 : 0.7;
		_root.设置色彩(target,target.影子倍率,target.影子倍率,target.影子倍率,NaN,NaN,NaN,target.透明倍率,0);
		target.不掉钱 = true;
		target.掉落物 = [];
	}else if(target.色彩单位){
		_root.设置色彩(target,target.红色乘数,target.绿色乘数,target.蓝色乘数,target.红色偏移,target.绿色偏移,target.蓝色偏移,target.透明乘数,target.透明偏移);
		target.不掉钱 = true;
		target.掉落物 = [];
	}else{
		_root.重置色彩(target);
	}
}


_root.初始化敌人模板 = function(){
	//以下14个是原版敌人的必要函数
	this.根据等级初始数值 = this.根据等级初始数值 ? this.根据等级初始数值 : _root.敌人函数.根据等级初始数值;
	this.行走 = this.行走 ? this.行走 : _root.敌人函数.行走;
	this.移动 = this.移动 ? this.移动 : _root.敌人函数.移动;
	this.被击移动 = this.被击移动 ? this.被击移动 : _root.敌人函数.被击移动;
	this.方向改变 = this.方向改变 ? this.方向改变 : _root.敌人函数.方向改变;
	this.状态改变 = this.状态改变 ? this.状态改变 : _root.敌人函数.状态改变;
	this.动画完毕 = this.动画完毕 ? this.动画完毕 : _root.敌人函数.动画完毕;
	this.硬直 = this.硬直 ? this.硬直 : _root.敌人函数.硬直;
	this.移动钝感硬直 = this.移动钝感硬直 ? this.移动钝感硬直 : _root.敌人函数.移动钝感硬直;
	this.随机掉钱 = this.随机掉钱 ? this.随机掉钱 : _root.敌人函数.随机掉钱;
	this.计算经验值 = this.计算经验值 ? this.计算经验值 : _root.敌人函数.计算经验值;
	this.攻击呐喊 = this.攻击呐喊 ? this.攻击呐喊 : _root.敌人函数.攻击呐喊;
	this.中招呐喊 = this.中招呐喊 ? this.中招呐喊 : _root.敌人函数.中招呐喊;
	this.击倒呐喊 = this.击倒呐喊 ? this.击倒呐喊 : _root.敌人函数.击倒呐喊;
	
	//以下是新增或新整合的函数
	this.死亡检测 = _root.敌人函数.死亡检测;
	this.强制移动 = _root.敌人函数.强制移动;
	this.击飞浮空 = _root.敌人函数.击飞浮空;
	this.击飞倒地 = _root.敌人函数.击飞倒地;
	this.宠物属性初始化 = this.宠物属性初始化 ? this.宠物属性初始化 : _root.敌人函数.宠物属性初始化;
	this.掉落物判定 = _root.敌人函数.掉落物判定;
	this.掉落物品 = _root.敌人函数.掉落物品;
	
	if(this.允许拾取 === true) this.尝试拾取 = _root.敌人函数.尝试拾取;
	
	//敌人属性表涉及的参数，共18项
	if(!this.兵种) _root.发布消息("警告：敌人未加载兵种信息！")
	var 敌人属性 = _root.敌人属性表[this.兵种];
	if(!敌人属性) 敌人属性 = _root.敌人属性表["默认"];
	//13项基础数值
	if(敌人属性.线性插值经验值.length > 1){
		_root.敌人函数.获取线性插值经验值(this,敌人属性.线性插值经验值);
	}else{
		if (isNaN(最小经验值)) 最小经验值 = 敌人属性.最小经验值;
		if (isNaN(最大经验值)) 最大经验值 = 敌人属性.最大经验值;
	}
	if (isNaN(hp_min)) hp_min = 敌人属性.hp_min;
	if (isNaN(hp_max)) hp_max = 敌人属性.hp_max;
	if (isNaN(速度_min)) 速度_min = 敌人属性.速度_min;
	if (isNaN(速度_max)) 速度_max = 敌人属性.速度_max;
	if (isNaN(空手攻击力_min)) 空手攻击力_min = 敌人属性.空手攻击力_min;
	if (isNaN(空手攻击力_max)) 空手攻击力_max = 敌人属性.空手攻击力_max;
	if (isNaN(躲闪率_min)) 躲闪率_min = 敌人属性.躲闪率_min;
	if (isNaN(躲闪率_max)) 躲闪率_max = 敌人属性.躲闪率_max;
	if (isNaN(基本防御力_min)) 基本防御力_min = 敌人属性.基本防御力_min;
	if (isNaN(基本防御力_max)) 基本防御力_max = 敌人属性.基本防御力_max;
	if (isNaN(装备防御力)) 装备防御力 = 敌人属性.装备防御力;
	//性别 重量 韧性
	if (性别 == null) 性别 = 敌人属性.性别;
	if (isNaN(重量)) 重量 = 敌人属性.重量;
	if (isNaN(韧性系数)) 韧性系数 = 敌人属性.韧性系数;
	//label
	if (!label) label = new Object();
	for(var key in 敌人属性.label){
		if(!label[key]) label[key] = 敌人属性.label[key];
	}
	//魔法抗性
	if (!魔法抗性) 魔法抗性 = new Object();
	for(var key in 敌人属性.魔法抗性){
		if(isNaN(魔法抗性[key])) 魔法抗性[key] = 敌人属性.魔法抗性[key];
	}
	//掉落物
	if(!掉落物 && 敌人属性.掉落物 && 敌人属性.掉落物 != "null") 掉落物 = _root.duplicateOf(敌人属性.掉落物);
	
	//被击硬直度是一个原版从未使用过的属性，这里顺理成章地将其弃用
	// 被击硬直度_min = !isNaN(被击硬直度_min) ? 被击硬直度_min : 1000;
	// 被击硬直度_max = !isNaN(被击硬直度_max) ? 被击硬直度_max : 1000;
	
	//以下是可以自定义的原版参数
	称号 = 称号 ? 称号 : "";
	if(isNaN(身高)) 身高 = 175;
	方向 = 方向 ? 方向 : "右";
	攻击模式 = 攻击模式 ? 攻击模式 : "空手";
	状态 = 登场动画 ? "登场" : 攻击模式 + "站立";
	击中效果 = 击中效果 ? 击中效果 : "飙血";
	刚体 = 刚体 ? true : false;
	无敌 = 无敌 === true ? true : false;
	
	//以下是可自定义的原版ai相关参数，在ai改革后可能被废弃
	x轴攻击范围 = x轴攻击范围 ? x轴攻击范围 : 100;
	y轴攻击范围 = y轴攻击范围 ? y轴攻击范围 : 10;
	x轴保持距离 = !isNaN(x轴保持距离) ? x轴保持距离 : 50;
	停止机率 = !isNaN(停止机率) ? 停止机率 : 50;
	随机移动机率 = !isNaN(随机移动机率) ? 随机移动机率 : 50;
	攻击欲望 = !isNaN(攻击欲望) ? 攻击欲望 : 5;
	
	//以下是可以自定义的新增参数
	命中率 = !isNaN(命中率) ? 命中率 : 10;
	免疫击退 = 免疫击退 ? true : false;
	锁定方向 = 锁定方向 ? true : false;
	奔跑速度倍率 = !isNaN(奔跑速度倍率) ? 奔跑速度倍率 : 2;
	允许拾取 = 允许拾取 ? true : false;
	
	//以下是自动初始化的必要参数
	攻击目标 = "无";
	攻击模式 = "空手";
	格斗架势 = false;
	浮空 = false;
	倒地 = false;
	硬直中 = false;
	垂直速度 = 0;
	已加经验值 = false;
	remainingImpactForce = 0;
	
	//转换身高，调整层级
	身高转换值 = UnitUtil.getHeightPercentage(this.身高);
	this._xscale = 身高转换值;
	this._yscale = 身高转换值;
	myxscale = this._xscale;
	Z轴坐标 = this._y;
	this.swapDepths(this._y + random(10));
	
	// 应用新版人物文字信息
	if(this.人物文字信息){
		this.attachMovie("新版人物文字信息","新版人物文字信息",this.getNextHighestDepth());
		this.新版人物文字信息._x = 人物文字信息._x;
		this.新版人物文字信息._y = 人物文字信息._y;

		this.人物文字信息.unloadMovie();
	}
	
	// 应用初始器
	根据等级初始数值(等级);
	宠物属性初始化();
	StaticInitializer.initializeUnit(this);

	// 应用影子色彩
	_root.敌人函数.应用影子色彩(this);
	
	// 初始化完毕
	方向改变(方向);
	gotoAndStop(状态);
}

//对初始化单位的函数进行包装
_root.敌人函数.初始化单位 = function(target){
	StaticInitializer.initializeUnit(target);
}
_root.敌人函数.注销单位 = function(target){
	StaticDeinitializer.deinitializeUnit(target);
}

_root.敌人函数.跳转到招式 = _root.主角函数.跳转到招式;

/*
_root.初始化可操控敌人模板 = function()
{
	this.循环切换攻击模式 = _root.主角函数.循环切换攻击模式;
	this.随机切换攻击模式 = _root.主角函数.随机切换攻击模式;
	this.单发枪计时 = _root.主角函数.单发枪计时;
	//this.单发枪可以射击 = _root.主角函数.单发枪可以射击;
	this.单发枪计时_2 = _root.主角函数.单发枪计时_2;
	//this.单发枪可以射击_2 = _root.主角函数.单发枪可以射击_2;
	this.攻击呐喊 = _root.主角函数.攻击呐喊;
	this.中招呐喊 = _root.主角函数.中招呐喊;
	this.击倒呐喊 = _root.主角函数.击倒呐喊;

	//

	this.计算经验值 = _root.主角函数.计算经验值;
	this.播放二级动画 = _root.主角函数.播放二级动画;

	//

	this.动画完毕 = _root.主角函数.动画完毕;

	//

	this.硬直 = _root.主角函数.硬直;

	this.移动钝感硬直 = _root.主角函数.移动钝感硬直;


	//
	this.攻击模式切换 = this.攻击模式切换 ? this.攻击模式切换 : _root.主角函数.攻击模式切换;
	this.按键控制攻击模式 = _root.主角函数.按键控制攻击模式;
	this.根据模式重新读取武器加成 = _root.主角函数.根据模式重新读取武器加成;
	// this.跳 = _root.主角函数.跳;


	//
	this.冲击 = _root.主角函数.冲击;
	this.攻击 = this.攻击 ? this.攻击 : _root.主角函数.攻击;
	this.方向改变 = _root.主角函数.方向改变;
	this.移动 = _root.主角函数.移动;
	// this.跳跃上下移动 = _root.主角函数.跳跃上下移动;
	this.被击移动 = _root.主角函数.被击移动;
	this.拾取 = _root.主角函数.拾取;
	this.非主角外观刷新 = _root.主角函数.非主角外观刷新;
	this.状态改变 = this.状态改变 ? this.状态改变 : _root.主角函数.状态改变;
	// this.UpdateBigState = _root.主角函数.UpdateBigState;
	// this.UpdateState = _root.主角函数.UpdateState;
	// this.UpdateSmallState = _root.主角函数.UpdateSmallState;
	// this.UpdateBigSmallState = _root.主角函数.UpdateBigSmallState;
	// this.getBigState = _root.主角函数.getBigState;
	// this.getState = _root.主角函数.getState;
	// this.getSmallState = _root.主角函数.getSmallState;
	// this.getAllState = _root.主角函数.getAllState;
	// this.getPastBigStates = _root.主角函数.getPastBigStates;
	// this.getPastStates = _root.主角函数.getPastStates;
	// this.getPastSmallStates = _root.主角函数.getPastSmallStates;
	this.人物暂停 = _root.主角函数.人物暂停;
	this.获取键值 = _root.主角函数.获取键值;
	this.根据等级初始数值 = _root.主角函数.根据等级初始数值;
	this.行走 = this.行走 ? this.行走 : _root.主角函数.行走;
	this.初始化可用技能 = _root.主角函数.初始化可用技能;
	// this.存储当前飞行状态 = _root.主角函数.存储当前飞行状态;
	// this.读取当前飞行状态 = _root.主角函数.读取当前飞行状态;
	this.按键检测 = _root.主角函数.按键检测;

	this.死亡检测 = _root.主角函数.死亡检测;

	// this.刀口位置生成子弹 = _root.主角函数.刀口位置生成子弹;
	// this.长枪射击 = _root.主角函数.长枪射击;
	// this.手枪射击 = _root.主角函数.手枪射击;
	// this.手枪2射击 = _root.主角函数.手枪2射击;
	
	最小经验值 = !isNaN(最小经验值) ? 最小经验值 : 16;
	最大经验值 = !isNaN(最大经验值) ? 最大经验值 : 134;
	hp_min = !isNaN(hp_min) ? hp_min : 200;
	hp_max = !isNaN(hp_max) ? hp_max : 1000;
	mp_min = !isNaN(mp_min) ? mp_min : 100;
	mp_max = !isNaN(mp_max) ? mp_max : 600;
	速度_min = !isNaN(速度_min) ? 速度_min : 40;
	速度_max = !isNaN(速度_max) ? 速度_max : 60;
	空手攻击力_min = !isNaN(空手攻击力_min) ? 空手攻击力_min : 10;
	空手攻击力_max = !isNaN(空手攻击力_max) ? 空手攻击力_max : 150;
	被击硬直度_min = !isNaN(被击硬直度_min) ? 被击硬直度_min : 1000;
	被击硬直度_max = !isNaN(被击硬直度_max) ? 被击硬直度_max : 200;
	躲闪率_min = !isNaN(躲闪率_min) ? 躲闪率_min : 10;
	躲闪率_max = !isNaN(躲闪率_max) ? 躲闪率_max : 2;
	基本防御力_min = !isNaN(基本防御力_min) ? 基本防御力_min : 10;
	基本防御力_max = !isNaN(基本防御力_max) ? 基本防御力_max : 400;

	//新加属性
	重量 = !isNaN(重量) ? 重量 : 60;
	韧性系数 = !isNaN(韧性系数) ? 韧性系数 : 1;
	命中率 = !isNaN(命中率) ? 命中率 : 10;
	// 血包数量 = 3;
	// 血包使用间隔 = 8 * _root.帧计时器.帧率;
	// 血包恢复比例 = 33;
	// 上次使用血包时间 = _root.帧计时器.当前帧数;

	不掉钱 = 不掉钱 ? true : false;
	// 不掉装备 = 不掉装备 ? true : false;


	操控编号 = _root.获取操控编号(this._name);
	if (操控编号 != -1) 获取键值();
	
	if (!this.装备防御力) this.装备防御力 = 0;
	if (this.hp满血值装备加层 == undefined)
	{
		this.hp满血值装备加层 = 0;
	}
	if (mp满血值装备加层 == undefined)
	{
		mp满血值装备加层 = 0;
	}
	
	攻击目标 = "无";
	x轴攻击范围 = 100;
	y轴攻击范围 = 20;
	x轴保持距离 = 50;
	
	攻击模式 = 攻击模式 ? 攻击模式 : "空手";
	状态 = 登场动画 ? "登场" : 攻击模式 + "站立";
	方向 = 方向 ? 方向 : "右";
	击中效果 = 击中效果 ? 击中效果 : "飙血";
	格斗架势 = false;
	Z轴坐标 = this._y;
	浮空 = false;
	倒地 = false;
	硬直中 = false;
	强制换弹夹 = false;
	if (!长枪射击次数) 长枪射击次数 = new Object();
	if (!手枪射击次数) 手枪射击次数 = new Object();
	if (!手枪2射击次数) 手枪2射击次数 = new Object();
	手雷射击次数 = 0;
	循环切换攻击模式计数 = 1;
	// 单发枪射击速度 = 1000;
	// 单发枪射击速度_2 = 1000;
	// 单发枪计时_时间结束 = true;
	// 单发枪计时_时间结束_2 = true;
	射击许可 = true;
	射击许可2 = true;
	// bigState = [];
	// state = [];
	// smallState = [];
	// allStage = [bigState, state, smallState];//暂时取消
	// useBigState = ["技能中", "技能结束", "普攻中", "普攻结束"];
	// useSmallStateSkill = ["闪现中", "闪现结束", "六连中", "六连结束", "踩人中", "踩人结束", "技能结束"];
	// useSmallStateWeapon = ["兵器一段前", "兵器一段中", "兵器二段中", "兵器三段中", "兵器四段中", "兵器五段中", "兵器五段结束", "兵器普攻结束", "长枪攻击前", "长枪攻击中", "长枪攻击结束"];
	// useStateWeapon = ["空手", "兵器", "手枪", "手枪2", "双枪", "长枪", "手雷"];
	// useStateWeaponAction = ["站立", "行走", "攻击", "跑", "冲击", "跳", "拾取", "躲闪"];
	// useStateOtherType = ["技能", "挂机", "被击", "击倒", "被投", "血腥死"];


	_root.刷新人物装扮(this._name);

	身高转换值 = UnitUtil.getHeightPercentage(this.身高);
	this._xscale = 身高转换值;
	this._yscale = 身高转换值;
	myxscale = this._xscale;
	this.swapDepths(this._y + random(10) - 5);

	if (_root.控制目标 != this._name)
	{
		初始化可用技能();
	}else{
		被动技能 = _root.主角被动技能;
	}
	buff = new 主角模板数值buff(this);
	
	//应用新版人物文字信息
	this.attachMovie("新版人物文字信息","新版人物文字信息",this.getNextHighestDepth());
	this.新版人物文字信息._x = 人物文字信息._x;
	this.新版人物文字信息._y = 人物文字信息._y;
	this.人物文字信息.unloadMovie();
	
	//初始化完毕
	根据等级初始数值(等级);
	方向改变(方向);
	gotoAndStop(状态);
};
*/

//#change:主角-牛仔



//容纳敌人二级函数的对象，包括了原版的二级函数，以及新写或基于原版修改的二级函数
_root.敌人二级函数 = new Object();

//最广泛的二级函数
_root.敌人二级函数.攻击时移动 = function(速度)
{
	var 移动方向 = _parent.方向;
	if (速度 < 0)
	{
		速度 = -速度;
		移动方向 = 移动方向 === "右" ? "左" : "右";
	}
	_parent.移动(移动方向,速度);
};

//首次实装于武装JK
_root.敌人二级函数.攻击时四向移动 = function(上, 下, 左, 右)
{
	if (上 != 0)
	{
		_parent.移动("上",上);
	}
	else if (下 != 0)
	{
		_parent.移动("下",下);
	}
	if (左 != 0)
	{
		_parent.方向改变("左");
		_parent.移动("左",左);
	}
	else if (右 != 0)
	{
		_parent.方向改变("右");
		_parent.移动("右",右);
	}
}

//由李小龙的瞬移改写，增加了最小与最大移动距离参数
_root.敌人二级函数.X轴追踪移动 = function(保持距离, 最小移动距离, 最大移动距离)
{
	if (!_parent.攻击目标 || _parent.攻击目标 === "无"){
		return;
	}
	var 方向 = _parent.方向;
	var distance = _root.gameworld[_parent.攻击目标]._x - _parent._x;
	if (方向 === "左"){
		distance = -distance;
	}
	distance -= 保持距离;
	if (!isNaN(最小移动距离) && distance < 最小移动距离){
		distance = 最小移动距离;
	}
	if (最大移动距离 > 0 && distance > 最大移动距离){
		distance = 最大移动距离;
	}
	_parent.移动(_parent.方向, distance);
};

//首次实装于独狼
_root.敌人二级函数.Z轴追踪移动 = function(最大移动距离){
	if (!_parent.攻击目标 || _parent.攻击目标 === "无"){
		return;
	}
	var distance = _root.gameworld[_parent.攻击目标].Z轴坐标 - _parent.Z轴坐标;
	var 方向 = "下";
	if (distance < 0){
		distance = -distance;
		方向 = "上";
	}
	if (最大移动距离 > 0 && distance > 最大移动距离){
		distance = 最大移动距离;
	}
	_parent.移动(方向,distance);
};

//根据攻击目标的位置计算移动角度，可限制角度的最大值。首次实装于方舟爪豪
//大于最大角度则返回最大角度，攻击目标在身后则返回角度限制下的随机值
_root.敌人二级函数.计算攻击角度 = function(最大角度){
	if (!最大角度 || 最大角度 <= 0){
		return 0;
	}
	var 水平距离 = _root.gameworld[_parent.攻击目标]._x - _parent._x;
	水平距离 = _parent.方向 === "左" ? -水平距离 : 水平距离;
	if (水平距离 <= 0){
		return 2 * Math.random() * 最大角度 - 最大角度;
	}
	var 垂直距离 = _root.gameworld[_parent.攻击目标].Z轴坐标 - _parent.Z轴坐标;
	var 角度 = Math.atan(垂直距离 / 水平距离) / Math.PI * 180;
	角度 = Math.min(角度, 最大角度);
	角度 = Math.max(角度, -最大角度);
	return 角度;
}

//以固定角度移动，可能需要同时限制转向。首次实装于方舟爪豪
_root.敌人二级函数.固定角度移动 = function(速度, 角度){
	if (!攻击时移动) 攻击时移动 = _root.敌人二级函数.攻击时移动;
	攻击时移动(速度 * Math.cos(角度 * Math.PI / 180));
	var 垂直速度 = 速度 * Math.sin(角度 * Math.PI / 180);
	var 垂直方向 = "上";
	if (垂直速度 < 0){
		垂直速度 = -垂直速度;
		垂直方向 = "下";
	}
	_parent.移动(垂直方向,垂直速度);
}

