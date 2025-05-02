import org.flashNight.arki.item.*;

/**
 * ShootInitCore.as
 * 
 * 武器初始化核心类，将原 _root.主角函数 中的初始化逻辑封装到此类中
 * 经过重构优化，降低了代码重复度，提高了可维护性
 * 主要负责：
 * 1. 单武器和双武器系统的初始化逻辑
 * 2. 武器属性的设置与子弹属性的生成
 * 3. 射击和换弹等功能函数的创建与绑定
 */
class org.flashNight.arki.unit.Action.Shoot.ShootInitCore {

    /**
     * 通用武器系统初始化函数
     * @param target    目标 MovieClip（原先依赖时间轴的 clip）
     * @param parentRef 父级引用（原 _parent 改为通过参数传入）
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
        
        // 绑定核心函数到目标对象
        _bindCoreFunctions(self);
        
        // 处理双枪/单枪模式
        if (config.isDualGun) {
            _initDualGunSystem(self, parentRef, config);
        } else {
            _initSingleGunSystem(self, parentRef, config);
        }
    }

    /**
     * 绑定核心函数到目标对象
     * @param target 目标 MovieClip
     */
    private static function _bindCoreFunctions(target:MovieClip):Void {
        target.开始射击       = _root.主角函数.开始射击;
        target.主手持续射击   = _root.主角函数.主手持续射击;
        target.副手持续射击   = _root.主角函数.副手持续射击;
        target.开始换弹       = _root.主角函数.开始换弹;
        target.换弹匣         = _root.主角函数.换弹匣;
        target.结束换弹       = _root.主角函数.结束换弹;
        target.刷新弹匣数显示 = _root.主角函数.刷新弹匣数显示;
    }

    /**
     * 初始化双枪系统
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     * @param config    双枪配置对象
     */
    private static function _initDualGunSystem(target:MovieClip, parentRef:Object, config:Object):Void {
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
        
        // 绑定射击和换弹函数
        target.主手开始射击 = _createHandShootFunction(target, parentRef, mainHandConfig);
        target.副手开始射击 = _createHandShootFunction(target, parentRef, subHandConfig);
        target.主手换弹匣 = _createHandReloadFunction(target, parentRef, mainHandConfig);
        target.副手换弹匣 = _createHandReloadFunction(target, parentRef, subHandConfig);
        
        // 绑定全局换弹函数
        target.开始换弹 = _createDualGunReloadStartFunction(target, parentRef);
        
        // 刷新界面显示
        target.刷新弹匣数显示();
    }
    
    /**
     * 初始化武器手的属性
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
        target[speedProp] = config.weaponData[5];
        target[magNameProp] = config.weaponData[11];
        target[singleShotProp] = config.weaponData[3];
        target[remainingMagProp] = parentRef.检查弹匣数量(target[magNameProp]);
        
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
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     * @param config    武器手配置对象
     * @return 返回特定手的开始射击函数
     */
    private static function _createHandShootFunction(target:MovieClip, parentRef:Object, config:Object):Function {
        var self:MovieClip = target;
        var handPrefix:String = config.handPrefix;
        var shootingFlagProp:String = handPrefix + "射击中";
        var speedProp:String = handPrefix + "射击速度";
        var remainingMagProp:String = handPrefix + "剩余弹匣数";
        var weaponType:String = config.weaponType;
        var otherWeaponType:String = config.otherWeaponType;
        var timerProp:String = config.timerProperty;
        var continueMethodName:String = handPrefix + "持续射击";
        
        return function():Void {
            var that:MovieClip = self;
            
            // 检查是否可以射击
            if (parentRef[shootingFlagProp] || that.换弹标签) return;
            
            // 检查弹匣状态
            var weaponShotCountArray:String = weaponType + "射击次数";
            var weaponShotCountIndex:String = weaponType;
            var weaponMagCapacity:String = weaponType + "弹匣容量";

            // 其他手枪属性
            var otherWeaponShotCountArray:String = otherWeaponType + "射击次数";
            var otherWeaponShotCountIndex:String = otherWeaponType;
            var otherWeaponMagCapacity:String = otherWeaponType + "弹匣容量";

            var mainNumber:Number = parentRef[weaponShotCountArray][parentRef[weaponShotCountIndex]];
            var otherNumber:Number = parentRef[otherWeaponShotCountArray][parentRef[otherWeaponShotCountIndex]];

            var mainIsEmpty:Boolean = mainNumber >= parentRef[weaponMagCapacity];
            var otherIsEmpty:Boolean = otherNumber >= parentRef[otherWeaponMagCapacity];

            var mainIsFull:Boolean = mainNumber == 0;
            var otherIsFull:Boolean = otherNumber == 0;

            var isSameWeapon:Boolean = (parentRef[weaponType] == parentRef[otherWeaponType])

            var needReload:Boolean = (mainIsEmpty && otherIsEmpty);
            needReload = needReload || (mainIsEmpty && otherIsFull);
            needReload = needReload || (mainIsFull && otherIsEmpty);
            needReload = needReload || ((mainIsEmpty || otherIsEmpty) && !isSameWeapon);

            if (needReload) {
  
                // 检查是否需要开始换弹
                if ((that[remainingMagProp] > 0) 
                    || _root.控制目标 != parentRef._name) {
                    that.开始换弹();
                }
                return;
            }
            
            // 检查射击许可
            if (!that.射击许可标签) return;
            
            // 开始持续射击
            var continueShooting:Boolean = that[continueMethodName](parentRef, weaponType, that[speedProp], that);
            if (continueShooting) {
                parentRef[timerProp] = _root.帧计时器.添加生命周期任务(
                    parentRef,
                    handPrefix + "开始射击",
                    that[continueMethodName],
                    that[speedProp],
                    parentRef, weaponType, that[speedProp]
                );
            }
        };
    }
    
    /**
     * 创建手枪换弹函数
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     * @param config    武器手配置对象
     * @return 返回特定手的换弹匣函数
     */
    private static function _createHandReloadFunction(target:MovieClip, parentRef:Object, config:Object):Function {
        var self:MovieClip = target;
        var handPrefix:String = config.handPrefix;
        var otherHandPrefix:String = config.otherHandPrefix;
        var weaponType:String = config.weaponType;
        var otherWeaponType:String = config.otherWeaponType;
        var magNameProp:String = handPrefix + "使用弹匣名称";
        
        // 弹匣相关属性
        var shotCountArray:String = weaponType + "射击次数";
        var shotCountIndex:String = weaponType;
        var otherShotCountArray:String = otherWeaponType + "射击次数";
        var otherShotCountIndex:String = otherWeaponType;

        var weaponMagCapacity:String = weaponType + "弹匣容量";
        var otherWeaponMagCapacity:String = otherWeaponType + "弹匣容量";
        var isSameWeapon:Boolean = (parentRef[weaponType] == parentRef[otherWeaponType])
        
        return function():Void {
            var that:MovieClip = self;
            // 重置射击次数
            parentRef[shotCountArray][parentRef[shotCountIndex]] = 0;
            
            if (_root.控制目标 === parentRef._name) {
                // 使用弹匣
                ItemUtil.singleSubmit(that[magNameProp], 1);
                
                // 更新弹匣数量（两把枪都需要更新）
                that.主手剩余弹匣数 = parentRef.检查弹匣数量(that.主手使用弹匣名称);
                that.副手剩余弹匣数 = parentRef.检查弹匣数量(that.副手使用弹匣名称);
                
                // 检查弹匣耗尽
                if (that[handPrefix + "剩余弹匣数"] === 0) {
                    _root.发布消息("弹匣耗尽！");
                }
                
                // 更新物品与显示
                _root.排列物品图标();
                that.刷新弹匣数显示();

                
                // 主手特殊处理 - 检查是否可以结束换弹
                if (handPrefix == "主手") {
                    var otherNumber:Number = parentRef[otherShotCountArray][parentRef[otherShotCountIndex]];
                    // _root.发布消息("主手", that.副手剩余弹匣数, isSameWeapon, otherNumber, parentRef[otherWeaponMagCapacity])
                    if(that.副手剩余弹匣数 == 0 || (isSameWeapon ? (otherNumber == 0) :
                                                                   otherNumber < parentRef[otherWeaponMagCapacity])) {
                        that.gotoAndPlay("换弹结束");
                    }
                } else {
                    var mainNumber:Number = parentRef[shotCountArray][parentRef[shotCountIndex]];
                    // _root.发布消息("副手", that.主手剩余弹匣数, isSameWeapon, mainNumber, parentRef[weaponMagCapacity])
                    if(that.主手剩余弹匣数 == 0 || (isSameWeapon ? (mainNumber == 0) :
                                                                   mainNumber < parentRef[weaponMagCapacity])) {
                        that.gotoAndPlay("换弹结束");
                    }
                }
            }
        };
    }
    
    /**
     * 创建双枪模式的开始换弹函数
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     * @return 返回开始换弹函数
     */
    private static function _createDualGunReloadStartFunction(target:MovieClip, parentRef:Object):Function {
        var self:MovieClip = target;
        
        return function():Void {
            var that:MovieClip = self;
            
            // 检查换弹标签
            if (that.换弹标签) {
                return;
            }
            
            // 检查弹匣状态
            var mainWeaponType:String = "手枪";
            var subWeaponType:String = "手枪2";
            
            var mainShotCountArray:String = mainWeaponType + "射击次数";
            var mainShotCountIndex:String = mainWeaponType;
            var mainMagCapacity:String = mainWeaponType + "弹匣容量";
            
            var subShotCountArray:String = subWeaponType + "射击次数";
            var subShotCountIndex:String = subWeaponType;
            var subMagCapacity:String = subWeaponType + "弹匣容量";
            
            var mainNumber:Number = parentRef[mainShotCountArray][parentRef[mainShotCountIndex]];
            var subNumber:Number = parentRef[subShotCountArray][parentRef[subShotCountIndex]];
            
            var mainIsEmpty:Boolean = mainNumber >= parentRef[mainMagCapacity];
            var subIsEmpty:Boolean = subNumber >= parentRef[subMagCapacity];
            
            var mainIsFull:Boolean = mainNumber == 0;
            var subIsFull:Boolean = subNumber == 0;

            // 如果两把枪都是满的，则不需要换弹
            if (mainIsFull && subIsFull) {
                return;
            }
            
            if (_root.控制目标 === parentRef._name) {
                // 检查主手是否需要换弹
                if (mainIsEmpty || (!mainIsFull && !subIsEmpty)) {
                    if (ItemUtil.singleContain(that.主手使用弹匣名称, 1)) {
                        that.gotoAndPlay("主手换弹匣");
                        return;
                    }
                } 
                // 检查副手是否需要换弹
                else if (subIsEmpty || (!subIsFull && !mainIsEmpty)) {
                    if (ItemUtil.singleContain(that.副手使用弹匣名称, 1)) {
                        that.gotoAndPlay("副手换弹匣");
                        return;
                    }
                }
                that.gotoAndPlay("换弹结束");
            } else {
                that.gotoAndPlay("主手换弹匣");
            }
        };
    }
    
    /**
     * 初始化单武器系统
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     * @param config    单武器配置对象
     */
    private static function _initSingleGunSystem(target:MovieClip, parentRef:Object, config:Object):Void {
        var weaponData:Array = config.weaponData;
        var extraParams:Object = config.extraParams || {};
        
        // 设置基础属性
        target.射击速度      = weaponData[5];
        target.使用弹匣名称  = weaponData[11];
        target.是否单发      = weaponData[3];
        target.剩余弹匣数    = parentRef.检查弹匣数量(target.使用弹匣名称);
        target.刷新弹匣数显示();
        
        // 生成子弹属性
        target.子弹属性 = generateBulletProps(parentRef, config.weaponType, weaponData, extraParams);
        
        // 注意：此处不需要创建特殊函数，因为单武器使用标准的开始射击和换弹匣函数
    }

    /**
     * 生成子弹属性对象
     * 保证功能不变的前提下对性能及代码结构进行了优化
     * 
     * @param parentRef  父级引用
     * @param weaponType 武器类型
     * @param weaponData 武器数据数组
     * @param extraParams 额外参数对象
     * @return 返回子弹属性对象
     */
    public static function generateBulletProps(parentRef:Object, weaponType:String, weaponData:Array, extraParams:Object):Object {
        var bulletProps:Object = {};

        // 缓存常用的对象属性，减少重复查找
        var passiveSkills:Object = parentRef.被动技能;
        var isEnemy:Boolean = Boolean(parentRef.是否为敌人);
        
        // 预生成武器类型判断结果
        var isLongGun:Boolean = (weaponType == "长枪");
        var isPistol:Boolean = (weaponType == "手枪" || weaponType == "手枪2");

        // 缓存 weaponData 数组中各个关键数据，使用具名属性提高可读性
        var wd:Object = {
            霰弹值:         weaponData[1],
            子弹散射度:     weaponData[2],
            声音:           weaponData[8],
            发射效果:       weaponData[9],
            子弹种类:       weaponData[7],
            子弹速度:       weaponData[6],
            击中地图效果:   weaponData[10],
            子弹威力Base:   weaponData[13],
            Z轴攻击范围:    weaponData[12],
            击倒率:        weaponData[14],
            击中后子弹效果: weaponData[15]
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
        bulletProps.子弹敌我属性   = !isEnemy;

        // 计算子弹威力（基于枪械攻击被动技能及额外攻击加成）
        var basePower:Number  = wd.子弹威力Base;
        var finalPower:Number = basePower;
        if (passiveSkills.枪械攻击 && passiveSkills.枪械攻击.启用) {
            var attackLevel:Number = passiveSkills.枪械攻击.等级;
            if (isLongGun) {
                finalPower = basePower * (1.5 + attackLevel * 0.03) + 30;
            } else {
                finalPower = basePower * (1 + attackLevel * 0.015) + 20;
            }
        }
        if (isLongGun && parentRef.长枪额外攻击加成倍率) {
            finalPower += basePower * parentRef.长枪额外攻击加成倍率;
        }
        if (isPistol && parentRef.短枪额外攻击加成倍率) {
            finalPower += basePower * parentRef.短枪额外攻击加成倍率;
        }
        bulletProps.子弹威力 = finalPower;

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

        return bulletProps;
    }

    /**
     * 根据暴击参数生成暴击判断函数
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
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     */
    public static function initLongGun(target:MovieClip, parentRef:Object):Void {
        var config:Object = {
            weaponType: "长枪",
            weaponData: parentRef.长枪属性数组[14],
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
    
    /**
     * 初始化手枪
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     */
    public static function initPistol(target:MovieClip, parentRef:Object):Void {
        var config:Object = {
            weaponType: "手枪",
            weaponData: parentRef.手枪属性数组[14],
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
    
    /**
     * 初始化手枪2
     * @param target    目标 MovieClip
     * @param parentRef 父级引用
     */
    public static function initPistol2(target:MovieClip, parentRef:Object):Void {
        var config:Object = {
            weaponType: "手枪2",
            weaponData: parentRef.手枪2属性数组[14],
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
    
    /**
     * 初始化双枪
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
            mainWeaponData : parentRef.手枪属性数组[14],
            subWeaponData  : parentRef.手枪2属性数组[14],
            extraParams    : { main: mainExtra, sub: subExtra }
        };
        
        // 调用通用初始化函数
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
}