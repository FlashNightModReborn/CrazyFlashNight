import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.*;

// 拾取相关函数
_root.pickupItemManager = new Object();
_root.pickupItemManager.count = 0;

_root.pickupItemManager.createPickupItemPool = function(){
	_root.pickupItemManager.pickupItemDict = {};
	_root.pickupItemManager.dispatcher = new LifecycleEventDispatcher(gameworld);
	org.flashNight.aven.Coordinator.EventCoordinator.addUnloadCallback(
		gameworld, 
		function(){
			_root.pickupItemManager.pickupItemDict = null;
			_root.pickupItemManager.dispatcher.destroy();
		}
	);
}

_root.pickupItemManager.pickup = function(target, 拾取者, 播放拾取动画){
	var str = "获得";
	var itemName = target.物品名;
	var value = target.数量;
	if (拾取者.名字){
		str = 拾取者.名字 + "为你收集了";
	}
	if (itemName == "金钱"){
		_root.金钱 += value;
		str += "金钱" + value;
	}else if (itemName == "K点"){
		_root.虚拟币 += value;
		str += "K点" + value;
	}else if (!拾取者 && Key.isDown(_root.组合键) &&_root.pickupItemManager.拾取并装备(itemName, value)){
		str =  "已拾取" + itemName;
	}else if (_root.singleAcquire(itemName, value)){
		str += itemName + value + "个。";
	}else{
		_root.发布消息("物品栏空间不足，无法拾取！");
		return;
	}
	// 销毁对象
	_root.发布消息(str);
	var 控制对象 = _root.gameworld[_root.控制目标];
	target.gotoAndPlay("消失");
	delete _root.pickupItemManager.pickupItemDict[target.index];
	_root.播放音效("拾取音效");
	if (!拾取者 && 播放拾取动画){
		控制对象.拾取();
	}
}
_root.pickupItemManager.拾取并装备 = function(itemName, value){
	var itemData = _root.getItemData(itemName);
	if(itemData.type == "武器" || itemData.type == "防具" || itemData.use == "手雷"){
		装备 = _root.物品栏.装备栏.getNameString(itemData.use);
		if(itemData.level && itemData.level > _root.等级) return false;
		if(!装备 && itemData.use){
			if(itemData.use == "手雷"){
				_root.物品栏.装备栏.add(itemData.use,{name:itemName, value:value});
			}else{
				_root.物品栏.装备栏.add(itemData.use,{name:itemName, value:{level:value}});
			}
			_root.刷新人物装扮(_root.控制目标);
			if(itemData.type == "武器" || itemData.use == "手雷"){
				_root.gameworld[_root.控制目标].攻击模式切换(itemData.use);
			}
		}
		else if(装备 && itemData.use){
			var 背包 = _root.物品栏.背包;
			var targetIndex = 背包.getFirstVacancy();
			if(targetIndex == -1) {
				return false;
			}
			//卸下装备
			var result = _root.物品栏.装备栏.move(背包,itemData.use,targetIndex);
        	if(!result) return false;
			if(itemData.use == "手雷"){
				_root.物品栏.装备栏.add(itemData.use,{name:itemName, value:value});
			}else{
				_root.物品栏.装备栏.add(itemData.use,{name:itemName, value:{level:value}});
			}
			_root.刷新人物装扮(_root.控制目标);
			if(itemData.type == "武器" || itemData.use == "手雷"){
				_root.gameworld[_root.控制目标].攻击模式切换(itemData.use);
			}
		}
		else{
			return false
		}
	}else{
		return false
	}
	return true
}

_root.创建可拾取物 = function(物品名, 数量, X位置, Y位置, 是否飞出, parameterObject){
	if(数量 <= 0) 数量 = 1;
	if (物品名 === "金钱" && random(_root.打怪掉钱机率) == 0){
		物品名 = "K点";
	}
	
	if(!parameterObject){
		parameterObject = new Object();
	}

	parameterObject.index = _root.pickupItemManager.count;
	parameterObject._x = X位置;
	parameterObject._y = Y位置;
	parameterObject.物品名 = 物品名;
	parameterObject.数量 = Number(数量);
	parameterObject.在飞 = Boolean(是否飞出);

	var gameworld = _root.gameworld;
	var pickupItem = gameworld.attachMovie("可拾取物2", "可拾取物" + _root.pickupItemManager.count, gameworld.getNextHighestDepth(), parameterObject);

	pickupItem.焦点高亮框.gotoAndPlay(_root.随机整数(1,59));
	
	// 创建可拾取物池
	if (_root.pickupItemManager.dispatcher.isDestroyed() || _root.pickupItemManager.dispatcher == null) {
		_root.pickupItemManager.createPickupItemPool();
	}

	_root.pickupItemManager.pickupItemDict[_root.pickupItemManager.count] = pickupItem;
	pickupItem.焦点高亮框._visible = false;

	var pickUpFunc:Function = function():Void{
		// _root.发布消息("开始碰撞检测");
		var focusedObject:MovieClip = gameworld[_root.控制目标];
		var mc:MovieClip = this.焦点高亮框;
		mc.play();
		this.焦点高亮框._visible = true;
		if (Math.abs(this.Z轴坐标 - focusedObject.Z轴坐标) < 50 && focusedObject.area.hitTest(this.area)){
			_root.pickupItemManager.pickup(this,null,true);
		}
	};

	var resetFunc:Function = function():Void{
		var mc:MovieClip = this.焦点高亮框;
		mc.stop();
		mc._visible = false;
	}
    _root.pickupItemManager.dispatcher.subscribeGlobal("interactionKeyDown", pickUpFunc, pickupItem);
	_root.pickupItemManager.dispatcher.subscribeGlobal("interactionKeyUp", resetFunc, pickupItem);
	
	_root.pickupItemManager.count++;
}



// 出生点相关
_root.初始化出生点 = function(){
	//确定方向
	方向 = 方向 === "左" ? "左" : "右";
	if (方向 === "左"){
		this._xscale = -100;
	}
	//将碰撞箱附加到地图
	var gameworld = _root.gameworld;

	if(this.开门 == null){
		this.开门 = function(){
			gotoAndPlay("开门");
		}
	}
	if(this.area){
		var rect = this.area.getRect(gameworld);
		var 地图 = gameworld.地图;

        // 设置 `地图` 为不可枚举
        _global.ASSetPropFlags(gameworld, ["地图"], 1, false);
		
		地图.beginFill(0x000000);
		地图.moveTo(rect.xMin, rect.yMin);
		地图.lineTo(rect.xMax, rect.yMin);
		地图.lineTo(rect.xMax, rect.yMax);
		地图.lineTo(rect.xMin, rect.yMax);
		地图.lineTo(rect.xMin, rect.yMin);;
		地图.endFill();
	}
}

_root.地图元件 = new Object();

_root.地图元件.初始化地图元件 = function(target:MovieClip){
	if (!isNaN(target.最小主线进度) && target.最小主线进度 > _root.主线任务进度){
		target.removeMovieClip();
		return;
	}else if (!isNaN(target.最大主线进度) && target.最大主线进度 < _root.主线任务进度){
		target.removeMovieClip();
		return;
	}if (target.数量_min > 0 && target.数量_max > 0){
		target.数量 = target.数量_min + random(target.数量_max - target.数量_min + 1);
	}

	target.是否为敌人 = true;

	if(isNaN(target.hp)) {
		target.hp = target.hp满血值 = 10;
	} else {
		target.hp满血值 =  target.hp;
	}
	
	target.躲闪率 = 100;
	target.击中效果 = target.击中效果 || "火花";
	target.Z轴坐标 = target._y;
	target.unitAIType = "None";
	StaticInitializer.initializeUnit(target);

	target.gotoAndStop("正常");
	target.element.stop();




	if(target.stainedTarget) {
		// 初始化并校验色彩参数（默认值：乘数为1，偏移为0）
		target.redMultiplier = isNaN(target.redMultiplier) ? 1 : target.redMultiplier;
		target.greenMultiplier = isNaN(target.greenMultiplier) ? 1 : target.greenMultiplier;
		target.blueMultiplier = isNaN(target.blueMultiplier) ? 1 : target.blueMultiplier;
		target.alphaMultiplier = isNaN(target.alphaMultiplier) ? 1 : target.alphaMultiplier;

		target.redOffset = isNaN(target.redOffset) ? 0 : target.redOffset;
		target.greenOffset = isNaN(target.greenOffset) ? 0 : target.greenOffset;
		target.blueOffset = isNaN(target.blueOffset) ? 0 : target.blueOffset;
		target.alphaOffset = isNaN(target.alphaOffset) ? 0 : target.alphaOffset;

			// 应用色彩设置
		_root.设置色彩(target[target.stainedTarget],
					target.redMultiplier,
					target.greenMultiplier,
					target.blueMultiplier,
					target.redOffset,
					target.greenOffset,
					target.blueOffset,
					target.alphaMultiplier,
					target.alphaOffset);
	}


	// 将碰撞箱附加到地图
	var gameworld = _root.gameworld;

	if(target.obstacle && target.area){
		var rect = target.area.getRect(gameworld);
		var 地图 = gameworld.地图;

		// 设置 `地图` 为不可枚举
		_global.ASSetPropFlags(gameworld, ["地图"], 1, false);
		
		地图.beginFill(0x000000);
		地图.moveTo(rect.xMin, rect.yMin);
		地图.lineTo(rect.xMax, rect.yMin);
		地图.lineTo(rect.xMax, rect.yMax);
		地图.lineTo(rect.xMin, rect.yMax);
		地图.lineTo(rect.xMin, rect.yMin);
		地图.endFill();
	}

	target.area._visible = false;
	target.swapDepths(target._y);
}

_root.地图元件.资源箱破碎脚本 = function(target:MovieClip) {
	target._visible = true;
	target.element.gotoAndPlay("结束");
	_root.帧计时器.注销目标缓存(target);
	if (target.是否为敌人 && _root.gameworld[target.产生源])
	{
		_root.敌人死亡计数 += 1;
		_root.gameworld[target.产生源].僵尸型敌人场上实际人数--;
		_root.gameworld[target.产生源].僵尸型敌人总个数--;
	}
	_root.创建可拾取物(target.内部物,target.数量,target._x,target._y,false);
}

/**
 * 地图元件破碎动画函数
 * @param scope:MovieClip - 当前作用域(this)
 * @param fragmentPrefix:String - 碎片名称前缀(如"资源箱碎片")
 * @param cfg:Object - 可选配置参数
 */
_root.地图元件.地图元件破碎动画 = function(scope:MovieClip, fragmentPrefix:String, cfg:Object):Void {
    // 默认配置参数
    var defaultConfig:Object = {
        // 物理参数
        gravity: 1.4,           // 重力 (px/帧²)
        bounce: 0.35,           // 反弹衰减
        friction: 0.85,         // 地面摩擦
        fragmentCount: 10,      // 碎片数量
        groundY: 30,            // 地面高度
        
        // 运动参数
        baseVelocityX: 8,       // 基础水平速度
        velocityXRange: 6,      // 水平速度随机范围
        velocityYMin: 4,        // 最小垂直速度
        velocityYMax: 12,       // 最大垂直速度
        rotationRange: 5,       // 旋转速度范围(-5~5)
        
        // 碰撞参数
        collisionProbability: 0.5,  // 碎片参与碰撞的概率
        energyLoss: 0.5,           // 碰撞能量损失系数
        
        // 质量计算参数
        massScale: 100,         // 面积转质量的缩放因子
        minMass: 0.5,          // 最小质量
        
        // 停止条件
        stopThresholdBase: 0.5, // 停止判定阈值基础值
        stopThresholdX: 0.3,    // X轴停止阈值
        stopThresholdRotation: 0.2, // 旋转停止阈值
        
        // 方向设置
        direction: -1,          // 主向量方向 (-1向左, 1向右)
        
        // 调试选项
        enableDebug: false       // 是否启用调试输出
    };
    
    // 合并配置参数
    if (!cfg) cfg = {};
    for (var key:String in defaultConfig) {
        if (cfg[key] == undefined) {
            cfg[key] = defaultConfig[key];
        }
    }
    
    // 验证必要参数
    if (!scope) {
        trace("错误：scope参数不能为空");
        return;
    }
    if (!fragmentPrefix) {
        trace("错误：fragmentPrefix参数不能为空");
        return;
    }
    
    // 创建动画数据容器（使用唯一键避免冲突）
    var animKey:String = fragmentPrefix + "_" + Math.random();
    if (!_root.fragmentAnimations) {
        _root.fragmentAnimations = {};
    }
    
    var animData:Object = {
        scope: scope,
        cfg: cfg,
        fragments: [],      // MovieClip 引用
        vx: [],            // x 速度
        vy: [],            // y 速度
        vr: [],            // 角速度
        collidable: [],    // 是否参与碰撞
        mass: [],          // 质量数组
        size: []           // 尺寸数组
    };
    
    _root.fragmentAnimations[animKey] = animData;
    
    // 初始化碎片引用并计算质量
    for (var i:Number = 1; i <= cfg.fragmentCount; i++) {
        var mc:MovieClip = scope[fragmentPrefix + i];
        if (mc) {
            animData.fragments.push(mc);
            
            // 获取碎片尺寸
            var bounds:Object = mc.getBounds(scope);
            var width:Number = bounds.xMax - bounds.xMin;
            var height:Number = bounds.yMax - bounds.yMin;
            
            // 计算面积作为质量基础
            var area:Number = width * height;
            var fragmentMass:Number = Math.max(area / cfg.massScale, cfg.minMass);
            
            animData.mass.push(fragmentMass);
            animData.size.push({width: width, height: height, area: area});
            
            if (cfg.enableDebug) {
                trace("碎片" + i + " - 尺寸:" + Math.round(width) + "x" + Math.round(height) + ", 质量:" + Math.round(fragmentMass * 10) / 10);
            }
        } else {
            if (cfg.enableDebug) {
                trace("警告：找不到碎片 " + fragmentPrefix + i);
            }
            // 为缺失的碎片填充默认值
            animData.fragments.push(null);
            animData.mass.push(1);
            animData.size.push({width: 20, height: 20, area: 400});
        }
    }
    
    // 初始化运动参数
    for (i = 0; i < cfg.fragmentCount; i++) {
        // 水平速度：基础方向 + 随机变化
        animData.vx[i] = cfg.direction * (cfg.baseVelocityX + Math.random() * cfg.velocityXRange);
        
        // 垂直速度：向上抛射 + 随机变化
        animData.vy[i] = -(Math.random() * (cfg.velocityYMax - cfg.velocityYMin) + cfg.velocityYMin);
        
        // 旋转速度：随机
        animData.vr[i] = (Math.random() * cfg.rotationRange * 2 - cfg.rotationRange);
        
        // 碰撞参与：根据概率决定
        animData.collidable[i] = (Math.random() < cfg.collisionProbability);
    }
    
    // 创建动画更新函数
    var updateFunction:Function = function() {
        var data:Object = _root.fragmentAnimations[animKey];
        if (!data) {
            delete scope.onEnterFrame;
            return;
        }
        
        var cfg:Object = data.cfg;
        
        // 1) 物理运动更新
        for (var i:Number = 0; i < cfg.fragmentCount; i++) {
            if (!data.fragments[i]) continue; // 安全检查
            
            // 应用重力（质量大的物体受空气阻力影响相对较小）
            var gravityEffect:Number = cfg.gravity * (0.8 + 0.4 / Math.sqrt(data.mass[i]));
            data.vy[i] += gravityEffect;
            
            // 更新位置
            data.fragments[i]._x += data.vx[i];
            data.fragments[i]._y += data.vy[i];
            data.fragments[i]._rotation += data.vr[i];
            
            // 地面碰撞处理
            if (data.fragments[i]._y >= cfg.groundY) {
                data.fragments[i]._y = cfg.groundY;
                
                // 质量影响反弹：质量大的反弹少
                var massBounceFactor:Number = cfg.bounce * (2 / (1 + data.mass[i] / 3));
                data.vy[i] *= -massBounceFactor;
                
                // 质量影响摩擦：质量大的摩擦力相对小
                var massFrictionFactor:Number = cfg.friction * (0.7 + 0.5 / Math.sqrt(data.mass[i]));
                data.vx[i] *= massFrictionFactor;
                data.vr[i] *= 0.6;               // 旋转也减速
                
                // 速度阈值判停（质量大的更容易停止）
                var stopThreshold:Number = cfg.stopThresholdBase / Math.sqrt(data.mass[i]);
                if (Math.abs(data.vy[i]) < stopThreshold) data.vy[i] = 0;
                if (Math.abs(data.vx[i]) < cfg.stopThresholdX) data.vx[i] = 0;
                if (Math.abs(data.vr[i]) < cfg.stopThresholdRotation) data.vr[i] = 0;
            }
        }
        
        // 2) 碎片间碰撞检测
        for (i = 0; i < cfg.fragmentCount - 1; i++) {
            if (!data.collidable[i] || !data.fragments[i]) continue;
            
            for (var j:Number = i + 1; j < cfg.fragmentCount; j++) {
                if (!data.collidable[j] || !data.fragments[j]) continue;
                
                // 动态碰撞半径：基于碎片大小
                var radiusI:Number = Math.sqrt(data.size[i].area) / 4;
                var radiusJ:Number = Math.sqrt(data.size[j].area) / 4;
                var minDist:Number = radiusI + radiusJ;
                
                // 简单圆形碰撞检测
                var dx:Number = data.fragments[j]._x - data.fragments[i]._x;
                var dy:Number = data.fragments[j]._y - data.fragments[i]._y;
                var dist2:Number = dx * dx + dy * dy;
                
                if (dist2 < minDist * minDist && dist2 > 0) {
                    // 计算碰撞响应
                    var dist:Number = Math.sqrt(dist2);
                    var overlap:Number = minDist - dist;
                    
                    // 分离重叠的碎片（质量影响分离比例）
                    var totalMass:Number = data.mass[i] + data.mass[j];
                    var separationRatioI:Number = data.mass[j] / totalMass;
                    var separationRatioJ:Number = data.mass[i] / totalMass;
                    
                    var separateX:Number = (dx / dist) * overlap;
                    var separateY:Number = (dy / dist) * overlap;
                    
                    data.fragments[i]._x -= separateX * separationRatioI;
                    data.fragments[i]._y -= separateY * separationRatioI;
                    data.fragments[j]._x += separateX * separationRatioJ;
                    data.fragments[j]._y += separateY * separationRatioJ;
                    
                    // 基于质量的弹性碰撞计算
                    var m1:Number = data.mass[i];
                    var m2:Number = data.mass[j];
                    
                    // 碰撞前速度
                    var v1x:Number = data.vx[i];
                    var v1y:Number = data.vy[i];
                    var v2x:Number = data.vx[j];
                    var v2y:Number = data.vy[j];
                    
                    // 弹性碰撞公式
                    data.vx[i] = ((m1 - m2) * v1x + 2 * m2 * v2x) / (m1 + m2) * cfg.energyLoss;
                    data.vy[i] = ((m1 - m2) * v1y + 2 * m2 * v2y) / (m1 + m2) * cfg.energyLoss;
                    data.vx[j] = ((m2 - m1) * v2x + 2 * m1 * v1x) / (m1 + m2) * cfg.energyLoss;
                    data.vy[j] = ((m2 - m1) * v2y + 2 * m1 * v1y) / (m1 + m2) * cfg.energyLoss;
                    
                    // 碰撞也影响旋转
                    data.vr[i] += (Math.random() - 0.5) * 2 / data.mass[i];
                    data.vr[j] += (Math.random() - 0.5) * 2 / data.mass[j];
                }
            }
        }
        
        // 3) 检查是否所有碎片都停止了
        var allStopped:Boolean = true;
        for (i = 0; i < cfg.fragmentCount; i++) {
            if (data.fragments[i] && (Math.abs(data.vx[i]) > 0.1 || Math.abs(data.vy[i]) > 0.1)) {
                allStopped = false;
                break;
            }
        }
        
        // 如果所有碎片都停止了，清理动画
        if (allStopped) {
            delete scope.onEnterFrame;
            delete _root.fragmentAnimations[animKey];
            if (cfg.enableDebug) {
                trace("破碎动画完成: " + fragmentPrefix);
            }
        }
    };
    
    // 设置动画循环
    scope.onEnterFrame = updateFunction;
    
    // 调试信息
    if (cfg.enableDebug) {
        trace("破碎动画已启动: " + fragmentPrefix + "，共" + cfg.fragmentCount + "个碎片");
        trace("参与碰撞的碎片：");
        for (var k:Number = 0; k < cfg.fragmentCount; k++) {
            if (animData.collidable[k]) {
                trace("- " + fragmentPrefix + (k + 1) + " (质量:" + Math.round(animData.mass[k] * 10) / 10 + ")");
            }
        }
        
        // 显示质量分布统计
        var totalMass:Number = 0;
        var maxMass:Number = 0;
        var minMass:Number = 999;
        for (k = 0; k < cfg.fragmentCount; k++) {
            totalMass += animData.mass[k];
            if (animData.mass[k] > maxMass) maxMass = animData.mass[k];
            if (animData.mass[k] < minMass) minMass = animData.mass[k];
        }
        trace("质量统计 - 总计:" + Math.round(totalMass * 10) / 10 + 
              ", 最大:" + Math.round(maxMass * 10) / 10 + 
              ", 最小:" + Math.round(minMass * 10) / 10);
    }
};

// 使用示例：
/*
// 基本调用（使用默认参数）
_root.地图元件破碎动画(this, "资源箱碎片");

// 自定义配置调用
var customConfig = {
    gravity: 2.0,           // 更强的重力
    fragmentCount: 8,       // 8个碎片
    direction: 1,           // 向右飞散
    baseVelocityX: 12,      // 更快的初始速度
    enableDebug: false      // 关闭调试输出
};
_root.地图元件破碎动画(this, "木箱碎片", customConfig);

// 爆炸效果配置
var explosionConfig = {
    direction: 0,           // 不设主方向
    baseVelocityX: 0,       // 基础速度为0
    velocityXRange: 20,     // 大范围随机速度
    velocityYMin: 8,        // 更强的向上速度
    velocityYMax: 16,
    gravity: 0.8,           // 较轻的重力
    bounce: 0.6             // 更强的反弹
};
_root.地图元件破碎动画(this, "爆炸碎片", explosionConfig);
*/

// 资源箱
_root.初始化资源箱 = function(){
	if (!isNaN(最小主线进度) && 最小主线进度 > _root.主线任务进度){
		this.removeMovieClip();
		return;
	}else if (!isNaN(最大主线进度) && 最大主线进度 < _root.主线任务进度){
		this.removeMovieClip();
		return;
	}if (数量_min > 0 and 数量_max > 0){
		数量 = 数量_min + random(数量_max - 数量_min + 1);
	}

	是否为敌人 = true;
	hp = hp满血值 = 10;
	躲闪率 = 100;
	击中效果 = "火花";
	Z轴坐标 = this._y;
	this.unitAIType = "None";
	StaticInitializer.initializeUnit(this);
	gotoAndStop("正常");
	
}

// NPC
//_root.初始化NPC(this);
_root.初始化NPC = function(目标){
	if(目标.NPC初始化完毕 === true) return;
	if(目标.任务需求 > 1 && _root.主线任务进度 < 目标.任务需求){
		目标.stop();
		目标._visible = false;
		return;
	}
	目标._name = 目标.名字;
	if(目标.默认对话 == null) 目标.默认对话 = _root.读取并组装NPC对话(目标.名字);
	if(目标.物品栏 == null) 目标.物品栏 = _root.getNPCShop(目标.名字);
	if(目标.可学的技能 == null) 目标.可学的技能 = _root.getNPCSkills(目标.名字);
	if (_root.NPCTaskCheck(目标.名字).result == "接受任务"){
		_root.发布消息(目标.名字 + "也许需要你的帮助");
	}
	// 目标.是否为敌人 = false;
	//目标.击中效果 = "飙血"; //意义不明
	if(目标.方向 == null) 目标.方向 = "右";
	if(isNaN(目标.身高)) 目标.身高 = 175;
	var 缩放系数 = UnitUtil.getHeightPercentage(目标.身高) / 100;
	目标._yscale *= 缩放系数;
	if(目标.方向 == "左"){
		目标._xscale *= - 缩放系数;
		目标.文字信息._xscale = -100;
		目标.商店名._xscale = -100;
	}else{
		目标._xscale *= 缩放系数;
	}
	目标.NPC初始化完毕 = true;
}