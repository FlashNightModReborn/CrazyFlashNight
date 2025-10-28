import org.flashNight.arki.item.*;
import org.flashNight.arki.unit.Action.Shoot.WeaponStateManager;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;
import org.flashNight.arki.unit.Action.Shoot.ShootCore;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.gesh.object.*;

/**
 * ShootInitCore.as
 * 
 * 武器初始化核心类，将武器系统的初始化逻辑统一封装
 * 完全重构后不再依赖_root.主角函数，直接使用各功能类
 * 
 * 主要职责：
 * 1. 单武器和双武器系统的初始化逻辑
 * 2. 武器属性的设置与子弹属性的生成
 * 3. 射击和换弹等功能函数的创建与绑定
 * 4. 使用武器状态管理器统一管理双枪状态逻辑
 * 
 * 设计原则：
 * - 模块化：每个方法专注于单一职责
 * - 低耦合：减少对全局对象的依赖
 * - 高内聚：相关功能集中在一起
 * - 可扩展：便于添加新武器类型和属性
 */
class org.flashNight.arki.unit.Action.Shoot.ShootInitCore {

    /**
     * 通用武器系统初始化函数
     * @param target    目标 MovieClip（原先依赖时间轴的 clip）
     * @param parentRef 父级引用（原 _parent 引用）
     * @param config    配置对象：
     *    - weaponType      : 武器类型 ("长枪"、"手枪"、"手枪2"、"双枪")
     *    - isDualGun       : 是否为双枪模式（true/false）
     *    - weaponData      : 单武器模式下的属性数组（双枪模式下忽略）
     *    - mainWeaponData  : 双枪模式下主手属性数组
     *    - subWeaponData   : 双枪模式下副手属性数组
     *    - extraParams     : 特殊属性参数（如毒、吸血、暴击、斩杀等）
     */
    public static function initWeaponSystem(target:MovieClip, parentRef:Object, config:Object):Void {
        // 使用闭包绑定 target 引用
        var self:MovieClip = target;
        
        // 检查攻击模式是否匹配
        if (parentRef.攻击模式 != config.weaponType) {
            return;
        }
        
        // 绑定核心函数到目标对象，传入必要的引用
        _bindCoreFunctions(self, parentRef, _root);
        
        // 处理双枪/单枪模式
        if (config.isDualGun) {
            _initDualGunSystem(self, parentRef, _root, config);
        } else {
            _initSingleGunSystem(self, parentRef, _root, config);
        }
    }

    /**
     * 绑定核心函数到目标对象
     * 直接使用各功能类的方法，不再依赖_root.主角函数
     * 
     * @param target     目标 MovieClip
     * @param parentRef  父级引用
     * @param rootRef    根引用（用于传递给功能类）
     */
    private static function _bindCoreFunctions(target:MovieClip, parentRef:Object, rootRef:Object):Void {
        // ShootCore 相关函数
        target.开始射击 = function() {
            ShootCore.startShooting(parentRef, target, ShootCore.primaryParams);
        };
        
        // 持续射击函数
        target.主手持续射击 = function(core, attackMode, shootSpeed) {
            return ShootCore.continuousShoot(core, attackMode, shootSpeed, ShootCore.primaryParams);
        };
        
        target.副手持续射击 = function(core, attackMode, shootSpeed) {
            return ShootCore.continuousShoot(core, attackMode, shootSpeed, ShootCore.secondaryParams);
        };
        
        // ReloadManager 相关函数
        target.开始换弹 = function() {
            ReloadManager.startReload(target, parentRef, rootRef);
        };
        
        target.换弹匣 = function() {
            ReloadManager.reloadMagazine(target, parentRef, rootRef);
        };
        
        target.结束换弹 = function() {
            ReloadManager.finishReload(target);
        };
        
        target.刷新弹匣数显示 = function() {
            ReloadManager.updateAmmoDisplay(target, parentRef, rootRef);
        };
    }

    /**
     * 初始化双枪系统
     * 完整配置双枪模式下的武器属性、状态管理和函数绑定
     * 
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     * @param rootRef   根引用
     * @param config    双枪配置对象
     */
    private static function _initDualGunSystem(target:MovieClip, parentRef:Object, rootRef:Object, config:Object):Void {
        // 创建武器状态管理器
        var stateManager:WeaponStateManager = new WeaponStateManager(
            parentRef, 
            "手枪",    // 主手武器类型
            "手枪2"    // 副手武器类型
        );
        
        // 将状态管理器保存到目标对象中，方便其他方法访问
        target.weaponStateManager = stateManager;
        
        // 主手配置
        var mainHandConfig:Object = {
            handPrefix: "主手",
            weaponType: "手枪",
            otherHandPrefix: "副手", 
            otherWeaponType: "手枪2",
            weaponData: config.mainWeaponData,
            extraParams: (config.extraParams && config.extraParams.main) ? config.extraParams.main : {},
            timerProperty: "keepshooting",
            bulletProperty: "子弹属性"
        };
        
        // 副手配置
        var subHandConfig:Object = {
            handPrefix: "副手",
            weaponType: "手枪2",
            otherHandPrefix: "主手",
            otherWeaponType: "手枪",
            weaponData: config.subWeaponData,
            extraParams: (config.extraParams && config.extraParams.sub) ? config.extraParams.sub : {},
            timerProperty: "keepshooting2",
            bulletProperty: "子弹属性2"
        };
        
        // 初始化两把手枪
        _initWeaponHand(target, parentRef, mainHandConfig);
        _initWeaponHand(target, parentRef, subHandConfig);
        
        // 绑定射击函数
        target.主手开始射击 = _createHandShootFunction(target, parentRef, mainHandConfig, stateManager);
        target.副手开始射击 = _createHandShootFunction(target, parentRef, subHandConfig, stateManager);
        
        // 使用ReloadManager创建换弹函数
        target.主手换弹匣 = ReloadManager.createHandReloadFunction(target, parentRef, rootRef, mainHandConfig, stateManager);
        target.副手换弹匣 = ReloadManager.createHandReloadFunction(target, parentRef, rootRef, subHandConfig, stateManager);
        
        // 使用ReloadManager创建开始换弹函数
        target.开始换弹 = ReloadManager.createDualGunReloadStartFunction(target, parentRef, rootRef, stateManager);
        
        // 刷新界面显示
        target.刷新弹匣数显示();
    }
    
    /**
     * 初始化武器手的属性
     * 设置特定手持武器的基本属性和子弹属性
     * 
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     * @param config    武器手配置对象
     */
    private static function _initWeaponHand(target:MovieClip, parentRef:Object, config:Object):Void {
        var prefix:String = config.handPrefix;
        var speedProp:String = prefix + "射击速度";
        var magNameProp:String = prefix + "使用弹匣名称";
        var singleShotProp:String = prefix + "是否单发";
        var remainingMagProp:String = prefix + "剩余弹匣数";
        
        // 设置属性
        target[speedProp] = config.weaponData.interval;
        target[magNameProp] = config.weaponData.clipname;
        target[singleShotProp] = config.weaponData.singleshoot;
        target[remainingMagProp] = ItemUtil.getTotal(target[magNameProp]);
        
        // 生成子弹属性
        target[config.bulletProperty] = generateBulletProps(
            parentRef, 
            config.weaponType, 
            config.weaponData, 
            config.extraParams
        );
    }
    
    /**
     * 创建手枪射击函数
     * 封装了特定手枪的射击逻辑和状态判断
     * 
     * @param target        目标 MovieClip
     * @param parentRef     父级引用
     * @param config        武器手配置对象
     * @param stateManager  武器状态管理器
     * @return 返回特定手的开始射击函数
     */
    private static function _createHandShootFunction(target:MovieClip, parentRef:Object, config:Object, stateManager:WeaponStateManager):Function {
        var self:MovieClip = target;
        var handPrefix:String = config.handPrefix;
        var shootingFlagProp:String = handPrefix + "射击中";
        var speedProp:String = handPrefix + "射击速度";
        var remainingMagProp:String = handPrefix + "剩余弹匣数";
        var weaponType:String = config.weaponType;
        var timerProp:String = config.timerProperty;
        var continueMethodName:String = handPrefix + "持续射击";
        
        return function():Void {
            var that:MovieClip = self;
            
            // 检查是否可以射击
            if (parentRef[shootingFlagProp] || that.换弹标签) return;
            
            // 更新武器状态
            stateManager.updateState();

            var rMP:Number = that[remainingMagProp];

            // 获取当前手的弹夹状态（直接检查射击次数是否超过弹匣容量）
            var magazineCapName:String = weaponType + "弹匣容量";
            var currentShot:Number = parentRef[weaponType].value.shot;
            var currentHandIsEmpty:Boolean = currentShot >= parentRef[magazineCapName];

            // 双枪模式下的换弹逻辑：
            // 1. 如果当前手弹夹空了且有剩余弹匣 → 触发换弹
            // 2. 如果当前手弹夹空了但无剩余弹匣 → 静默返回，不射击
            // 3. 如果当前手弹夹未空 → 继续射击流程
            if (currentHandIsEmpty) {
                if (rMP > 0 || _root.控制目标 != parentRef._name) {
                    that.开始换弹();
                }
                // 弹夹已空，无论是否有弹匣都不能射击
                return;
            }
            
            // 检查射击许可
            if (!that.射击许可标签) {
                // _root.发布消息("主角函数.射击许可", "不允许射击");
                return;
            }
            
            // 开始持续射击
            var continueShooting:Boolean = that[continueMethodName](parentRef, weaponType, that[speedProp], that);
            if (continueShooting) {
                parentRef[timerProp] = EnhancedCooldownWheel.I().addTask(
                    that[continueMethodName],
                    that[speedProp],
                    0,
                    parentRef, weaponType, that[speedProp]
                );
            }
        };
    }
    
    /**
     * 初始化单武器系统
     * 设置单武器的基本属性和子弹生成
     * 
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     * @param rootRef   根引用
     * @param config    单武器配置对象
     */
    private static function _initSingleGunSystem(target:MovieClip, parentRef:Object, rootRef:Object, config:Object):Void {
        var weaponData:Array = config.weaponData;
        var extraParams:Object = config.extraParams || {};
        
        // 设置基础属性
        target.射击速度      = weaponData.interval;
        target.使用弹匣名称  = weaponData.clipname;
        target.是否单发      = weaponData.singleshoot;
        target.剩余弹匣数    = ItemUtil.getTotal(target.使用弹匣名称);
        
        // 更新弹药UI显示
        target.刷新弹匣数显示();
        
        // 生成子弹属性
        target.子弹属性 = generateBulletProps(parentRef, config.weaponType, weaponData, extraParams);
        
        // 单武器使用标准的开始射击和换弹匣函数，已在_bindCoreFunctions中绑定
    }

    /**
     * 计算武器的最终威力
     * 统一处理武器基础威力、被动技能倍率和额外加成倍率
     * 此方法可被UI显示和子弹生成逻辑共同使用，确保数据一致性
     *
     * @param parentRef   父级引用（单位对象）
     * @param weaponType  武器类型（"长枪"、"手枪"、"手枪2"、"刀"）
     * @param basePower   武器基础威力（weaponData.power）
     * @return 返回计算后的最终威力（不含伤害加成）
     */
    public static function calculateWeaponPower(parentRef:Object, weaponType:String, basePower:Number):Number {
        var finalPower:Number = basePower;
        var passiveSkills:Object = parentRef.被动技能;

        // 预生成武器类型判断结果
        var isLongGun:Boolean = (weaponType == "长枪");
        var isPistol:Boolean = (weaponType == "手枪" || weaponType == "手枪2");

        // 应用枪械攻击被动技能倍率
        if (passiveSkills && passiveSkills.枪械攻击 && passiveSkills.枪械攻击.启用) {
            var attackLevel:Number = passiveSkills.枪械攻击.等级 ? passiveSkills.枪械攻击.等级 : 0;
            if (isLongGun) {
                // 长枪公式: basePower * (1.5 + 等级 * 0.03) + 30
                finalPower = basePower * (1.5 + attackLevel * 0.03) + 30;
            } else if (isPistol) {
                // 手枪公式: basePower * (1 + 等级 * 0.015) + 20
                finalPower = basePower * (1 + attackLevel * 0.015) + 20;
            }
        }

        // 应用额外攻击加成倍率
        if (isLongGun && parentRef.长枪额外攻击加成倍率) {
            finalPower += basePower * parentRef.长枪额外攻击加成倍率;
        }
        if (isPistol && parentRef.短枪额外攻击加成倍率) {
            finalPower += basePower * parentRef.短枪额外攻击加成倍率;
        }

        return finalPower;
    }

    /**
     * 生成子弹属性对象
     * 根据武器类型、数据和额外参数生成完整的子弹属性配置
     *
     * @param parentRef   父级引用
     * @param weaponType  武器类型
     * @param weaponData  武器数据数组
     * @param extraParams 额外参数对象
     * @return 返回子弹属性对象
     */
    public static function generateBulletProps(parentRef:Object, weaponType:String, weaponData:Array, extraParams:Object):Object {
        var bulletProps:Object = {};

        // 缓存常用的对象属性，减少重复查找
        var passiveSkills:Object = parentRef.被动技能;
        var isEnemy:Boolean = Boolean(parentRef.是否为敌人);

        // 缓存 weaponData 数组中各个关键数据，使用具名属性提高可读性
        var wd:Object = {
            霰弹值:         weaponData.split,
            子弹散射度:     weaponData.diffusion,
            声音:           weaponData.sound,
            发射效果:       weaponData.muzzle,
            子弹种类:       weaponData.bullet,
            子弹速度:       weaponData.velocity,
            击中地图效果:   weaponData.bullethit,
            子弹威力Base:   weaponData.power,
            Z轴攻击范围:    weaponData.bulletsize,
            击倒率:        weaponData.impact,
            击中后子弹效果: weaponData.targethit
        };

        // 设置基础属性
        bulletProps.发射者 = parentRef._name;
        bulletProps.声音   = wd.声音;
        bulletProps.霰弹值 = wd.霰弹值;
        bulletProps.子弹散射度 = wd.子弹散射度;
        bulletProps.站立子弹散射度 = wd.子弹散射度;

        // 计算移动射击等级（如果启用则取等级，否则为0）
        var 移动射击等级:Number = (passiveSkills.移动射击 && passiveSkills.移动射击.启用 && passiveSkills.移动射击.等级)
                                ? passiveSkills.移动射击.等级 : 0;
        bulletProps.移动子弹散射度 = wd.子弹散射度 + 10 - 移动射击等级;

        bulletProps.发射效果       = wd.发射效果;
        bulletProps.子弹种类       = wd.子弹种类;
        bulletProps.ammoCost      = (wd.子弹种类.indexOf("纵向") >= 0) ? wd.霰弹值 : 1;
        bulletProps.子弹速度       = wd.子弹速度;
        bulletProps.击中地图效果   = wd.击中地图效果;
        bulletProps.Z轴攻击范围    = wd.Z轴攻击范围;
        bulletProps.击倒率         = wd.击倒率;
        bulletProps.击中后子弹的效果 = wd.击中后子弹效果;

        // 计算子弹威力（使用统一的武器威力计算函数）
        var basePower:Number = wd.子弹威力Base;
        bulletProps.子弹威力 = calculateWeaponPower(parentRef, weaponType, basePower);

        // 处理动态参数：伤害类型、魔法伤害属性、毒、吸血、击溃（击溃对应 bulletProps.血量上限击溃）
        var optionalKeys:Array = ["伤害类型", "魔法伤害属性", "毒", "吸血", "击溃"];
        for (var i:Number = 0; i < optionalKeys.length; i++) {
            var key:String = optionalKeys[i];
            var targetKey:String = (key == "击溃") ? "血量上限击溃" : key;
            if (extraParams[key]) {
                bulletProps[targetKey] = extraParams[key];
            } else if (parentRef[weaponType + key]) {
                bulletProps[targetKey] = parentRef[weaponType + key];
            }
        }

        // 处理暴击逻辑，使用严格检查以确保不漏掉 false 以外的有效值
        var critValue:Object = (extraParams.暴击 !== undefined) ? extraParams.暴击 : parentRef[weaponType + "暴击"];
        if (critValue) {
            bulletProps.暴击 = ShootInitCore.createCritLogic(critValue);
        }

        // 处理斩杀属性，确保数值有效后转换为 Number
        var killValue:Object = (extraParams.斩杀 !== undefined) ? extraParams.斩杀 : parentRef[weaponType + "斩杀"];
        if (killValue && !isNaN(Number(killValue))) {
            bulletProps.斩杀 = Number(killValue);
        }

        //_root.服务器.发布服务器消息(weaponType + " 子弹数据: " + ObjectUtil.toString(wd) + " 返回子弹数据: " + ObjectUtil.toString(bulletProps));

        return bulletProps;
    }

    /**
     * 根据暴击参数生成暴击判断函数
     * 支持数值暴击率和特殊条件暴击（如满血暴击）
     * 
     * @param critValue 数值（例如 20 表示 20% 暴击率）或字符串（例如 "满血暴击"）
     * @return 返回暴击判断函数
     */
    public static function createCritLogic(critValue:Object):Function {
        if (!isNaN(Number(critValue))) {
            var critRate:Number = Number(critValue);
            return function(当前子弹:Object):Number {
                if (_root.成功率(critRate)) {
                    return 1.5;
                }
                return 1.0;
            };
        } else if (critValue == "满血暴击") {
            return function(当前子弹:Object):Number {
                if (当前子弹.hitTarget.hp >= 当前子弹.hitTarget.hp满血值) {
                    return 1.5;
                }
                return 1.0;
            };
        }
        return function(当前子弹:Object):Number {
            return 1.0;
        };
    }
    
    // ======================================================
    // 各武器初始化包装方法，兼容原调用方式
    // ======================================================
    
    /**
     * 初始化长枪
     * 为长枪武器创建标准配置并调用通用初始化方法
     * 
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     */
    public static function initLongGun(target:MovieClip, parentRef:Object):Void {
        var config:Object = {
            weaponType: "长枪",
            weaponData: parentRef.长枪属性,
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
    
    /**
     * 初始化手枪
     * 为手枪武器创建标准配置并调用通用初始化方法
     * 
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     */
    public static function initPistol(target:MovieClip, parentRef:Object):Void {
        var config:Object = {
            weaponType: "手枪",
            weaponData: parentRef.手枪属性,
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
    
    /**
     * 初始化手枪2
     * 为副手手枪创建标准配置并调用通用初始化方法
     * 
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     */
    public static function initPistol2(target:MovieClip, parentRef:Object):Void {
        var config:Object = {
            weaponType: "手枪2",
            weaponData: parentRef.手枪2属性,
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
    
    /**
     * 初始化双枪
     * 创建双枪系统的完整配置并调用通用初始化方法
     * 包括主副手的所有特殊属性配置
     * 
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     */
    public static function initDualGun(target:MovieClip, parentRef:Object):Void {
        // 创建主手额外参数对象
        var mainExtra:Object = {
            伤害类型        : parentRef.手枪伤害类型,
            魔法伤害属性    : parentRef.手枪魔法伤害属性,
            毒              : parentRef.手枪毒,
            吸血            : parentRef.手枪吸血,
            击溃            : parentRef.手枪击溃,
            暴击            : parentRef.手枪暴击,
            斩杀            : parentRef.手枪斩杀
        };
        
        // 创建副手额外参数对象
        var subExtra:Object = {
            伤害类型        : parentRef.手枪2伤害类型,
            魔法伤害属性    : parentRef.手枪2魔法伤害属性,
            毒              : parentRef.手枪2毒,
            吸血            : parentRef.手枪2吸血,
            击溃            : parentRef.手枪2击溃,
            暴击            : parentRef.手枪2暴击,
            斩杀            : parentRef.手枪2斩杀
        };
        
        // 创建双枪配置
        var config:Object = {
            weaponType     : "双枪",
            isDualGun      : true,
            mainWeaponData : parentRef.手枪属性,
            subWeaponData  : parentRef.手枪2属性,
            extraParams    : { main: mainExtra, sub: subExtra }
        };

        /*
        _root.服务器.发布服务器消息(target._name + " 初始化双枪系统 " + parentRef + " " + 
        ObjectUtil.toString(config));
        */

        // 调用通用初始化函数
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
}