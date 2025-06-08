import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.spatial.animation.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.unit.Action.PickUp.*;

import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;


// 拾取相关函数
_root.pickupItemManager = new PickUpManager();

// 保持原有全局函数调用方式的兼容性
_root.创建可拾取物 = function(物品名, 数量, X位置, Y位置, 是否飞出, parameterObject) {
    return _root.pickupItemManager.createCollectible(物品名, 数量, X位置, Y位置, 是否飞出, parameterObject);
};



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

_root.地图元件.初始化地图元件 = function(target:MovieClip, presetName:String):Void {
	StaticInitializer.initializeMapElement(target, presetName);
}

_root.地图元件.掉落物转换为物品栏 = function(target:MovieClip){
    if(!target.掉落物) return;

    var cap = target.row * target.col;
    var inventory = new ArrayInventory(null, cap);
    var item;
	if(target.掉落物.length > 0){
        var arr = new Array(cap);
        var i;
        for(i=0; i<cap; i++){
            arr[i] = i;
        }
        arr = org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine.getInstance().reservoirSample(arr,target.掉落物.length);
		for(i = target.掉落物.length - 1; i > -1; i--){
			item = _root.地图元件.掉落物创建物品(target.掉落物[i]);
            if(item != null) inventory.add(arr[i], item);
		}
	}else if(target.掉落物.名字){
        item = _root.地图元件.掉落物创建物品(target.掉落物);
        if(item != null) inventory.add(random(cap), item);
	}
    target.掉落物 = null;

    _root.物品UI函数.创建资源箱图标(inventory, target.presetName, target.row, target.col);
}

_root.地图元件.掉落物创建物品 = function(item){
    if(isNaN(item.概率)) item.概率 = 100;
	if(item.名字 && _root.成功率(item.概率)){
		if(isNaN(item.最小数量) || isNaN(item.最大数量)){
			item.最小数量 = item.最大数量 = 1;
		}
		if(isNaN(item.总数)) item.总数 = item.最大数量;
		var 数量 = item.最小数量 + random(item.最大数量 - item.最小数量 + 1);
		if(item.总数 < 数量) 数量 = item.总数;
		item.总数 -= 数量;
		return ItemUtil.createItem(item.名字, 数量);
	}
    return null;
}



_root.地图元件.资源箱破碎脚本 = function(target:MovieClip) {
	target._visible = true;

	var source:MovieClip = _root.gameworld[target.产生源];

	if (target.是否为敌人 && source)
	{
		_root.敌人死亡计数 += 1;
		source.僵尸型敌人场上实际人数--;
		source.僵尸型敌人总个数--;
	}

    // _root.发布消息("资源箱破碎: " + target._name);

    // 在此处临时测试资源箱弹出物品栏
    if(target.row > 0 && target.col > 0){
        _root.地图元件.掉落物转换为物品栏(target);
    }else{
        target.掉落物判定 = _root.敌人函数.掉落物判定;
        target.掉落物品 = _root.敌人函数.掉落物品;
        target.掉落物判定();
    }
}


_root.地图元件.资源箱贴背景图 = function(target:MovieClip) {
	target.stop();
	_root.add2map(target,2);
	target.removeMovieClip();
}


/**
 * 地图元件破碎动画包装方法
 * 
 * 此函数作为新碎片动画系统的包装接口，保持与原有调用方式的兼容性。
 * 资源SWF文件可以直接调用此方法，无需导入任何类文件。
 * 
 * 设计目标：
 * - 向后兼容：保持原有的调用方式和参数结构
 * - 零依赖：资源SWF不需要导入类文件
 * - 功能增强：支持更多配置选项和预设效果
 * - 智能转换：自动将旧格式配置转换为新系统
 * 
 * 使用场景：
 * - 资源SWF中的破碎效果调用
 * - 旧项目的平滑迁移
 * - 快速原型制作和测试
 * - 简化的API接口
 * 
 * @author FlashNight
 * @version 1.0
 * @since AS2
 */

/**
 * 地图元件破碎动画包装函数
 * 
 * 这是原有动画系统的现代化替代方案，保持完全的向后兼容性。
 * 函数内部会自动检测配置类型并调用相应的处理逻辑。
 * 
 * 支持的调用方式：
 * 1. 传统方式：传入Object格式的配置
 * 2. 预设方式：传入字符串指定预设名称
 * 3. 混合方式：传入预设名称+自定义覆盖参数
 * 4. 空配置：使用默认设置
 * 
 * @param scope:MovieClip 当前作用域(this)，包含碎片MovieClip的容器
 * @param fragmentPrefix:String 碎片名称前缀(如"资源箱碎片")
 * @param cfg:Object|String 配置参数，支持多种格式：
 *   - Object: 传统的配置对象
 *   - String: 预设名称 ("wood", "metal", "glass"等)
 *   - null/undefined: 使用默认配置
 * @return Number 动画实例ID，可用于后续控制(-1表示失败)
 * 
 * @example
 * // 传统方式（完全兼容原有调用）
 * var cfg:Object = {
 *     gravity: 1.4,
 *     bounce: 0.35,
 *     fragmentCount: 10,
 *     enableDebug: true
 * };
 * _root.地图元件.地图元件破碎动画(this, "资源箱碎片", cfg);
 * 
 * @example
 * // 预设方式（新增功能）
 * _root.地图元件.地图元件破碎动画(this, "木箱碎片", "wood");
 * 
 * @example
 * // 混合方式（预设+自定义）
 * var cfg:Object = {
 *     preset: "metal",          // 基础预设
 *     gravity: 2.0,            // 覆盖重力
 *     fragmentCount: 15,       // 覆盖碎片数量
 *     enableDebug: true
 * };
 * _root.地图元件.地图元件破碎动画(this, "装甲碎片", cfg);
 * 
 * @example
 * // 最简调用
 * _root.地图元件.地图元件破碎动画(this, "碎片");
 */
_root.地图元件.地图元件破碎动画 = function(scope:MovieClip, fragmentPrefix:String, cfg:Object):Number {
    
    // ======================== 参数验证 ========================
    
    if (!scope) {
        trace("[地图元件破碎动画] 错误：scope参数不能为空");
        return -1;
    }
    if (!fragmentPrefix) {
        trace("[地图元件破碎动画] 错误：fragmentPrefix参数不能为空");
        return -1;
    }
    
    // ======================== 配置处理 ========================
    
    var config:FragmentConfig;
    var debugEnabled:Boolean = false;
    
    try {
        // 检测配置类型并进行相应处理
        if (!cfg) {
            // 情况1：无配置，使用默认
            config = FragmentPresets.getDefault();
            
        } else if (typeof cfg == "string") {
            // 情况2：字符串预设名称
            config = FragmentPresets.getPreset(String(cfg));
            if (!config) {
                trace("[地图元件破碎动画] 警告：未知预设 '" + cfg + "'，使用默认配置");
                config = FragmentPresets.getDefault();
            }
            
        } else if (typeof cfg == "object") {
            // 情况3：对象配置（传统方式或混合方式）
            
            if (cfg.preset) {
                // 混合方式：从预设开始，然后覆盖参数
                config = FragmentPresets.getPreset(String(cfg.preset));
                if (!config) {
                    trace("[地图元件破碎动画] 警告：未知预设 '" + cfg.preset + "'，使用默认配置作为基础");
                    config = FragmentPresets.getDefault();
                }
                
                // 从配置对象加载覆盖参数
                var loadResult:Boolean = config.loadFromObject(cfg);
                if (cfg.enableDebug) {
                    trace("[地图元件破碎动画] 混合配置模式：基础预设 '" + cfg.preset + "' + 自定义覆盖");
                }
                
            } else {
                // 传统方式：纯对象配置
                config = FragmentPresets.getDefault();
                var loadResult:Boolean = config.loadFromObject(cfg);
                
                if (cfg.enableDebug) {
                    trace("[地图元件破碎动画] 传统配置模式：" + (loadResult ? "配置加载成功" : "配置加载失败"));
                }
            }
            
            debugEnabled = Boolean(cfg.enableDebug);
            
        } else {
            // 情况4：无效配置类型
            trace("[地图元件破碎动画] 警告：无效的配置类型，使用默认配置");
            config = FragmentPresets.getDefault();
        }
        
        // ======================== 配置验证和调试 ========================
        
        // 验证配置有效性
        if (!config.validate()) {
            trace("[地图元件破碎动画] 配置参数存在问题，已自动修正");
        }
        
        // 输出调试信息
        if (debugEnabled || config.enableDebug) {
            trace("[地图元件破碎动画] ===== 动画启动信息 =====");
            trace("  作用域: " + scope);
            trace("  碎片前缀: " + fragmentPrefix);
            trace("  配置类型: " + typeof cfg);
            trace("  预设使用: " + (cfg && cfg.preset ? cfg.preset : "默认"));
            config.printSummary();
            trace("=========================================");
        }
        
        // ======================== 启动动画 ========================
        
        // 调用新的动画系统
        var animationId:Number = FragmentAnimator.startAnimation(scope, fragmentPrefix, config);
        
        if (animationId >= 0) {
            if (debugEnabled || config.enableDebug) {
                trace("[地图元件破碎动画] 动画启动成功，ID: " + animationId);
                trace("  当前活动动画数: " + FragmentAnimator.getActiveAnimationCount());
            }
            return animationId;
        } else {
            trace("[地图元件破碎动画] 错误：动画启动失败");
            return -1;
        }
        
    } catch (error:Error) {
        // ======================== 错误处理 ========================
        
        trace("[地图元件破碎动画] 捕获到异常: " + error.message);
        
        // 尝试使用最基础的配置作为后备方案
        try {
            trace("[地图元件破碎动画] 尝试使用后备配置...");
            var fallbackConfig:FragmentConfig = new FragmentConfig();
            fallbackConfig.enableDebug = debugEnabled;
            
            var fallbackId:Number = FragmentAnimator.startAnimation(scope, fragmentPrefix, fallbackConfig);
            
            if (fallbackId >= 0) {
                trace("[地图元件破碎动画] 后备方案成功，动画ID: " + fallbackId);
                return fallbackId;
            }
            
        } catch (fallbackError:Error) {
            trace("[地图元件破碎动画] 后备方案也失败: " + fallbackError.message);
        }
        
        return -1;
    }
};

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