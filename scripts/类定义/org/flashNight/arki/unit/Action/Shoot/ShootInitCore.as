/**
 * ShootInitCore.as
 * 
 * 新的武器初始化核心类，将原 _root.主角函数 中分散的初始化逻辑封装到此类中，
 * 提供统一入口 initWeaponSystem 以及针对长枪、手枪、手枪2、双枪的静态初始化方法。
 */
class org.flashNight.arki.unit.Action.Shoot.ShootInitCore {

    /**
     * 通用的武器系统初始化函数
     * @param target   目标 MovieClip（原先依赖时间轴代码的 clip）
     * @param _parent  父级对象（原来在时间轴中可直接访问的父对象）
     * @param config   配置对象：
     *   weaponType      : 武器类型（"长枪"、"手枪"、"手枪2"、"双枪"）
     *   isDualGun       : 是否为双枪模式（true/false）
     *   weaponData      : 单武器模式下的属性数组（双枪模式下忽略）
     *   mainWeaponData  : 双枪模式下主手属性数组
     *   subWeaponData   : 双枪模式下副手属性数组
     *   extraParams     : 单/双枪模式下的特殊属性参数（如毒、吸血、暴击等）
     */
    public static function initWeaponSystem(target:MovieClip, _parent:Object, config:Object):Void {
        // 若当前攻击模式不匹配则直接返回
        if(_parent.攻击模式 != config.weaponType) {
            return;
        }
        
        // 保留原有时间轴绑定方式，兼容外部调用
        target.开始射击       = _root.主角函数.开始射击;
        target.主手持续射击   = _root.主角函数.主手持续射击;
        target.副手持续射击   = _root.主角函数.副手持续射击;
        target.开始换弹       = _root.主角函数.开始换弹;
        target.换弹匣         = _root.主角函数.换弹匣;
        target.结束换弹       = _root.主角函数.结束换弹;
        target.刷新弹匣数显示 = _root.主角函数.刷新弹匣数显示;
        
        // -------------------- 双枪模式 --------------------
        if(config.isDualGun) {
            var mainData:Array = config.mainWeaponData;
            var subData:Array = config.subWeaponData;
            var mainExtra:Object = (config.extraParams && config.extraParams.main) ? config.extraParams.main : {};
            var subExtra:Object  = (config.extraParams && config.extraParams.sub)  ? config.extraParams.sub  : {};
            
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
            
            // 刷新界面显示
            target.刷新弹匣数显示();
            
            // 生成子弹属性对象（主手、辅手分别调用）
            target.子弹属性  = ShootInitCore.generateBulletProps(_parent, "手枪",  mainData, mainExtra);
            target.子弹属性2 = ShootInitCore.generateBulletProps(_parent, "手枪2", subData,  subExtra);
            
            // 定义主手开始射击逻辑
            target.主手开始射击 = function():Void {
                if (_parent.主手射击中 || this.换弹标签) return;
                if(_parent.手枪射击次数[_parent.手枪] >= _parent.手枪弹匣容量) {
                    if(org.flashNight.arki.item.ItemUtil.singleContain(this.主手使用弹匣名称, 1)){
                        this.gotoAndPlay("主手换弹匣");
                    } else {
                        if((_parent.手枪2射击次数[_parent.手枪2] >= _parent.手枪2弹匣容量 && this.主手剩余弹匣数 > 0)
                           || _root.控制目标 != _parent._name) {
                            this.开始换弹();
                        }
                    }
                    return;
                }
                if(!this.射击许可标签) return;
                var 继续射击许可:Boolean = this.主手持续射击(_parent, "手枪", this.主手射击速度, this);
                if(继续射击许可) {
                    _parent.keepshooting = _root.帧计时器.添加生命周期任务(
                        _parent,
                        "主手开始射击",
                        this.主手持续射击,
                        this.主手射击速度,
                        _parent, "手枪", this.主手射击速度
                    );
                }
            };
            
            // 定义副手开始射击逻辑
            target.副手开始射击 = function():Void {
                if (_parent.副手射击中 || this.换弹标签) return;
                if(_parent.手枪2射击次数[_parent.手枪2] >= _parent.手枪2弹匣容量) {
                    if(org.flashNight.arki.item.ItemUtil.singleContain(this.副手使用弹匣名称, 1)){
                        this.gotoAndPlay("副手换弹匣");
                    } else {
                        if((_parent.手枪射击次数[_parent.手枪] >= _parent.手枪弹匣容量 && this.副手剩余弹匣数 > 0)
                           || _root.控制目标 != _parent._name) {
                            this.开始换弹();
                        }
                    }
                    return;
                }
                if(!this.射击许可标签) return;
                var 继续射击许可:Boolean = this.副手持续射击(_parent, "手枪2", this.副手射击速度, this);
                if(继续射击许可) {
                    _parent.keepshooting2 = _root.帧计时器.添加生命周期任务(
                        _parent,
                        "副手开始射击",
                        this.副手持续射击,
                        this.副手射击速度,
                        _parent, "手枪2", this.副手射击速度
                    );
                }
            };
            
            // 主手换弹匣逻辑
            target.主手换弹匣 = function():Void {
                _parent.手枪射击次数[_parent.手枪] = 0;
                if (_root.控制目标 === _parent._name){
                    org.flashNight.arki.item.ItemUtil.singleSubmit(this.主手使用弹匣名称, 1);
                    this.主手剩余弹匣数 = _parent.检查弹匣数量(this.主手使用弹匣名称);
                    this.副手剩余弹匣数 = _parent.检查弹匣数量(this.副手使用弹匣名称);
                    if(this.主手剩余弹匣数 === 0) {
                        _root.发布消息("弹匣耗尽！");
                    }
                    _root.排列物品图标();
                    this.刷新弹匣数显示();
                    
                    if(this.副手剩余弹匣数 == 0 || _parent.手枪2射击次数[_parent.手枪2] == 0){
                        this.gotoAndPlay("换弹结束");
                    }
                }
            };
            
            // 副手换弹匣逻辑
            target.副手换弹匣 = function():Void {
                _parent.手枪2射击次数[_parent.手枪2] = 0;
                if (_root.控制目标 === _parent._name){
                    org.flashNight.arki.item.ItemUtil.singleSubmit(this.副手使用弹匣名称, 1);
                    this.主手剩余弹匣数 = _parent.检查弹匣数量(this.主手使用弹匣名称);
                    this.副手剩余弹匣数 = _parent.检查弹匣数量(this.副手使用弹匣名称);
                    
                    if(this.副手剩余弹匣数 === 0) {
                        _root.发布消息("弹匣耗尽！");
                    }
                    _root.排列物品图标();
                    this.刷新弹匣数显示();
                }
            };
            
            // 全局换弹逻辑
            target.开始换弹 = function():Void {
                if(this.换弹标签 || (_parent.手枪射击次数[_parent.手枪] == 0 && _parent.手枪2射击次数[_parent.手枪2] == 0)) {
                    return;
                }
                if (_root.控制目标 === _parent._name){
                    if(_parent.手枪射击次数[_parent.手枪] > 0){
                        if(org.flashNight.arki.item.ItemUtil.singleContain(this.主手使用弹匣名称, 1)){
                            this.gotoAndPlay("主手换弹匣");
                            return;
                        }
                    } else if(_parent.手枪2射击次数[_parent.手枪2] > 0) {
                        if(org.flashNight.arki.item.ItemUtil.singleContain(this.副手使用弹匣名称, 1)){
                            this.gotoAndPlay("副手换弹匣");
                            return;
                        }
                    }
                    this.gotoAndPlay("换弹结束");
                } else {
                    this.gotoAndPlay("主手换弹匣");
                }
            };
            
        }
        // -------------------- 单武器模式 --------------------
        else {
            var weaponData:Array = config.weaponData;
            var extraParams:Object = config.extraParams || {};
            
            target.射击速度      = weaponData[5];
            target.使用弹匣名称  = weaponData[11];
            target.是否单发      = weaponData[3];
            
            target.剩余弹匣数 = _parent.检查弹匣数量(target.使用弹匣名称);
            target.刷新弹匣数显示();
            
            target.子弹属性 = ShootInitCore.generateBulletProps(_parent, config.weaponType, weaponData, extraParams);
        }
    }
    
    /**
     * 生成子弹属性对象（原 _生成子弹属性 函数）
     */
    public static function generateBulletProps(_parent:Object, weaponType:String, weaponData:Array, extraParams:Object):Object {
        var 子弹属性:Object = new Object();
        子弹属性.发射者 = _parent._name;
        子弹属性.声音   = weaponData[8];
        
        // 读取散射度及移动射击修正
        子弹属性.霰弹值         = weaponData[1];
        子弹属性.子弹散射度     = weaponData[2];
        子弹属性.站立子弹散射度 = weaponData[2];
        var 移动射击等级:Number = (_parent.被动技能.移动射击 && _parent.被动技能.移动射击.启用 && _parent.被动技能.移动射击.等级)
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
        var basePower:Number  = weaponData[13];
        var finalPower:Number = basePower;
        if(_parent.被动技能.枪械攻击 && _parent.被动技能.枪械攻击.启用) {
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
        
        // 特殊属性处理：优先使用 extraParams 指定，其次读取 _parent 内对应属性
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
        var critValue:Object = (extraParams.暴击 !== undefined) ? extraParams.暴击 : _parent[weaponType + "暴击"];
        if(critValue) {
            子弹属性.暴击 = ShootInitCore.createCritLogic(critValue);
        }
        // 处理斩杀逻辑
        var killValue:Object = (extraParams.斩杀 !== undefined) ? extraParams.斩杀 : _parent[weaponType + "斩杀"];
        if(killValue && !isNaN(Number(killValue))) {
            子弹属性.斩杀 = Number(killValue);
        }
        
        return 子弹属性;
    }
    
    /**
     * 根据暴击参数生成暴击判断函数
     * 参数 critValue 可能为数值（如20表示20%暴击率）或字符串（如 "满血暴击"）
     */
    public static function createCritLogic(critValue:Object):Function {
        if(!isNaN(Number(critValue))) {
            var critRate:Number = Number(critValue);
            return function(当前子弹:Object):Number {
                if(_root.成功率(critRate)) {
                    return 1.5;
                }
                return 1.0;
            };
        } else if(critValue == "满血暴击") {
            return function(当前子弹:Object):Number {
                if(当前子弹.hitTarget.hp >= 当前子弹.hitTarget.hp满血值) {
                    return 1.5;
                }
                return 1.0;
            };
        }
        // 默认不触发暴击
        return function(当前子弹:Object):Number {
            return 1.0;
        };
    }
    
    // ===================== 针对各武器类型的初始化封装 =====================
    
    /**
     * 初始化长枪射击
     */
    public static function initLongGun(target:MovieClip, _parent:Object):Void {
        var config:Object = {
            weaponType: "长枪",
            weaponData: _parent.长枪属性数组[14],
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, _parent, config);
    }
    
    /**
     * 初始化手枪射击
     */
    public static function initPistol(target:MovieClip, _parent:Object):Void {
        var config:Object = {
            weaponType: "手枪",
            weaponData: _parent.手枪属性数组[14],
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, _parent, config);
    }
    
    /**
     * 初始化手枪2射击
     */
    public static function initPistol2(target:MovieClip, _parent:Object):Void {
        var config:Object = {
            weaponType: "手枪2",
            weaponData: _parent.手枪2属性数组[14],
            isDualGun : false,
            extraParams: {}
        };
        ShootInitCore.initWeaponSystem(target, _parent, config);
    }
    
    /**
     * 初始化双枪射击
     */
    public static function initDualGun(target:MovieClip, _parent:Object):Void {
        var mainExtra:Object = {
            伤害类型        : _parent.手枪伤害类型,
            魔法伤害属性    : _parent.手枪魔法伤害属性,
            毒              : _parent.手枪毒,
            吸血            : _parent.手枪吸血,
            击溃            : _parent.手枪击溃,
            暴击            : _parent.手枪暴击,
            斩杀            : _parent.手枪斩杀
        };
        var subExtra:Object = {
            伤害类型        : _parent.手枪2伤害类型,
            魔法伤害属性    : _parent.手枪2魔法伤害属性,
            毒              : _parent.手枪2毒,
            吸血            : _parent.手枪2吸血,
            击溃            : _parent.手枪2击溃,
            暴击            : _parent.手枪2暴击,
            斩杀            : _parent.手枪2斩杀
        };
        var config:Object = {
            weaponType     : "双枪",
            isDualGun      : true,
            mainWeaponData : _parent.手枪属性数组[14],
            subWeaponData  : _parent.手枪2属性数组[14],
            extraParams    : { main: mainExtra, sub: subExtra }
        };
        ShootInitCore.initWeaponSystem(target, _parent, config);
    }
}
