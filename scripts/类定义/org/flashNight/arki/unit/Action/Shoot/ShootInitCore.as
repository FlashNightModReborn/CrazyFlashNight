import org.flashNight.arki.item.*;
/**
 * ShootInitCore.as
 * 
 * 新的武器初始化核心类，将原 _root.主角函数 中的初始化逻辑封装到此类中，
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
        
        // 保留原有时间轴函数绑定方式
        self.开始射击       = _root.主角函数.开始射击;
        self.主手持续射击   = _root.主角函数.主手持续射击;
        self.副手持续射击   = _root.主角函数.副手持续射击;
        self.开始换弹       = _root.主角函数.开始换弹;
        self.换弹匣         = _root.主角函数.换弹匣;
        self.结束换弹       = _root.主角函数.结束换弹;
        self.刷新弹匣数显示 = _root.主角函数.刷新弹匣数显示;
        
        // -------------------- 双枪模式 --------------------
        if (config.isDualGun) {
            var mainData:Array = config.mainWeaponData;
            var subData:Array  = config.subWeaponData;
            var mainExtra:Object = (config.extraParams && config.extraParams.main) ? config.extraParams.main : {};
            var subExtra:Object  = (config.extraParams && config.extraParams.sub)  ? config.extraParams.sub  : {};
            
            // 初始化主手属性
            self.主手射击速度     = mainData[5];
            self.主手使用弹匣名称 = mainData[11];
            self.主手是否单发     = mainData[3];
            self.主手剩余弹匣数   = parentRef.检查弹匣数量(self.主手使用弹匣名称);
            
            // 初始化副手属性
            self.副手射击速度     = subData[5];
            self.副手使用弹匣名称 = subData[11];
            self.副手是否单发     = subData[3];
            self.副手剩余弹匣数   = parentRef.检查弹匣数量(self.副手使用弹匣名称);
            
            // 刷新界面显示
            self.刷新弹匣数显示();
            
            // 分别生成主手与副手的子弹属性对象
            self.子弹属性  = ShootInitCore.generateBulletProps(parentRef, "手枪",  mainData, mainExtra);
            self.子弹属性2 = ShootInitCore.generateBulletProps(parentRef, "手枪2", subData,  subExtra);
            
            // 定义主手开始射击方法，使用闭包绑定 self
            self.主手开始射击 = function():Void {
                var that:MovieClip = self;
                if (parentRef.主手射击中 || that.换弹标签) return;
                if (parentRef.手枪射击次数[parentRef.手枪] >= parentRef.手枪弹匣容量) {
                    if (ItemUtil.singleContain(that.主手使用弹匣名称, 1)) {
                        that.gotoAndPlay("主手换弹匣");
                    } else {
                        if ((parentRef.手枪2射击次数[parentRef.手枪2] >= parentRef.手枪2弹匣容量 && that.主手剩余弹匣数 > 0)
                            || _root.控制目标 != parentRef._name) {
                            that.开始换弹();
                        }
                    }
                    return;
                }
                if (!that.射击许可标签) return;
                var continueShooting:Boolean = that.主手持续射击(parentRef, "手枪", that.主手射击速度, that);
                if (continueShooting) {
                    parentRef.keepshooting = _root.帧计时器.添加生命周期任务(
                        parentRef,
                        "主手开始射击",
                        that.主手持续射击,
                        that.主手射击速度,
                        parentRef, "手枪", that.主手射击速度
                    );
                }
            };
            
            // 定义副手开始射击方法
            self.副手开始射击 = function():Void {
                var that:MovieClip = self;
                if (parentRef.副手射击中 || that.换弹标签) return;
                if (parentRef.手枪2射击次数[parentRef.手枪2] >= parentRef.手枪2弹匣容量) {
                    if (ItemUtil.singleContain(that.副手使用弹匣名称, 1)) {
                        that.gotoAndPlay("副手换弹匣");
                    } else {
                        if ((parentRef.手枪射击次数[parentRef.手枪] >= parentRef.手枪弹匣容量 && that.副手剩余弹匣数 > 0)
                            || _root.控制目标 != parentRef._name) {
                            that.开始换弹();
                        }
                    }
                    return;
                }
                if (!that.射击许可标签) return;
                var continueShooting:Boolean = that.副手持续射击(parentRef, "手枪2", that.副手射击速度, that);
                if (continueShooting) {
                    parentRef.keepshooting2 = _root.帧计时器.添加生命周期任务(
                        parentRef,
                        "副手开始射击",
                        that.副手持续射击,
                        that.副手射击速度,
                        parentRef, "手枪2", that.副手射击速度
                    );
                }
            };
            
            // 定义主手换弹匣方法
            self.主手换弹匣 = function():Void {
                var that:MovieClip = self;
                parentRef.手枪射击次数[parentRef.手枪] = 0;
                if (_root.控制目标 === parentRef._name) {
                    ItemUtil.singleSubmit(that.主手使用弹匣名称, 1);
                    that.主手剩余弹匣数 = parentRef.检查弹匣数量(that.主手使用弹匣名称);
                    that.副手剩余弹匣数 = parentRef.检查弹匣数量(that.副手使用弹匣名称);
                    if (that.主手剩余弹匣数 === 0) {
                        _root.发布消息("弹匣耗尽！");
                    }
                    _root.排列物品图标();
                    that.刷新弹匣数显示();
                    
                    if (that.副手剩余弹匣数 == 0 || parentRef.手枪2射击次数[parentRef.手枪2] == 0) {
                        that.gotoAndPlay("换弹结束");
                    }
                }
            };
            
            // 定义副手换弹匣方法
            self.副手换弹匣 = function():Void {
                var that:MovieClip = self;
                parentRef.手枪2射击次数[parentRef.手枪2] = 0;
                if (_root.控制目标 === parentRef._name) {
                    ItemUtil.singleSubmit(that.副手使用弹匣名称, 1);
                    that.主手剩余弹匣数 = parentRef.检查弹匣数量(that.主手使用弹匣名称);
                    that.副手剩余弹匣数 = parentRef.检查弹匣数量(that.副手使用弹匣名称);
                    if (that.副手剩余弹匣数 === 0) {
                        _root.发布消息("弹匣耗尽！");
                    }
                    _root.排列物品图标();
                    that.刷新弹匣数显示();
                }
            };
            
            // 定义全局换弹方法
            self.开始换弹 = function():Void {
                var that:MovieClip = self;
                if (that.换弹标签 || (parentRef.手枪射击次数[parentRef.手枪] == 0 && parentRef.手枪2射击次数[parentRef.手枪2] == 0)) {
                    return;
                }
                if (_root.控制目标 === parentRef._name) {
                    if (parentRef.手枪射击次数[parentRef.手枪] > 0) {
                        if (ItemUtil.singleContain(that.主手使用弹匣名称, 1)) {
                            that.gotoAndPlay("主手换弹匣");
                            return;
                        }
                    } else if (parentRef.手枪2射击次数[parentRef.手枪2] > 0) {
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
        // -------------------- 单武器模式 --------------------
        else {
            var weaponData:Array = config.weaponData;
            var extraParams:Object = config.extraParams || {};
            
            self.射击速度      = weaponData[5];
            self.使用弹匣名称  = weaponData[11];
            self.是否单发      = weaponData[3];
            self.剩余弹匣数    = parentRef.检查弹匣数量(self.使用弹匣名称);
            self.刷新弹匣数显示();
            
            self.子弹属性 = ShootInitCore.generateBulletProps(parentRef, config.weaponType, weaponData, extraParams);
        }
    }

    /**
     * 生成子弹属性对象（原 _生成子弹属性 函数）
     * 保证功能不变的前提下对性能及代码结构进行了优化
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
    // 以下为各武器初始化包装方法，兼容原调用方式
    // ======================================================
    
    public static function initLongGun(target:MovieClip, parentRef:Object):Void {
        var config:Object = {
            weaponType: "长枪",
            weaponData: parentRef.长枪属性数组[14],
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
    
    public static function initPistol(target:MovieClip, parentRef:Object):Void {
        var config:Object = {
            weaponType: "手枪",
            weaponData: parentRef.手枪属性数组[14],
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
    
    public static function initPistol2(target:MovieClip, parentRef:Object):Void {
        var config:Object = {
            weaponType: "手枪2",
            weaponData: parentRef.手枪2属性数组[14],
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
    
    public static function initDualGun(target:MovieClip, parentRef:Object):Void {
        var mainExtra:Object = {
            伤害类型        : parentRef.手枪伤害类型,
            魔法伤害属性    : parentRef.手枪魔法伤害属性,
            毒              : parentRef.手枪毒,
            吸血            : parentRef.手枪吸血,
            击溃            : parentRef.手枪击溃,
            暴击            : parentRef.手枪暴击,
            斩杀            : parentRef.手枪斩杀
        };
        var subExtra:Object = {
            伤害类型        : parentRef.手枪2伤害类型,
            魔法伤害属性    : parentRef.手枪2魔法伤害属性,
            毒              : parentRef.手枪2毒,
            吸血            : parentRef.手枪2吸血,
            击溃            : parentRef.手枪2击溃,
            暴击            : parentRef.手枪2暴击,
            斩杀            : parentRef.手枪2斩杀
        };
        var config:Object = {
            weaponType     : "双枪",
            isDualGun      : true,
            mainWeaponData : parentRef.手枪属性数组[14],
            subWeaponData  : parentRef.手枪2属性数组[14],
            extraParams    : { main: mainExtra, sub: subExtra }
        };
        ShootInitCore.initWeaponSystem(target, parentRef, config);
    }
}
