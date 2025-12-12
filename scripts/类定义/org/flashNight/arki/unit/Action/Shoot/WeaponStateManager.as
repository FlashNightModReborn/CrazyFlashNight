import org.flashNight.arki.item.*;

/**
 * WeaponStateManager.as
 * 
 * 武器状态管理器
 * 用于封装双枪系统中的武器状态判断逻辑
 * 将原本分散在多个函数中的状态判断统一集中管理
 * 
 * 主要功能：
 * 1. 跟踪主副手武器的弹药状态（满弹、空弹）
 * 2. 提供统一的状态判断方法
 * 3. 优化状态逻辑的复用与维护
 */
class org.flashNight.arki.unit.Action.Shoot.WeaponStateManager {
    // 武器引用
    private var parentRef:Object;
    private var mainWeaponType:String;
    private var subWeaponType:String;
    
    // 缓存的属性名称
    private var mainShotCountIndex:String;
    private var mainMagCapacity:String;
    private var subShotCountIndex:String;
    private var subMagCapacity:String;
    
    // 计算的状态变量
    private var mainNumber:Number;
    private var subNumber:Number;
    private var _mainIsEmpty:Boolean;
    private var _subIsEmpty:Boolean;
    private var _mainIsFull:Boolean;
    private var _subIsFull:Boolean;
    private var _isSameWeapon:Boolean;
    private var _bothEmpty:Boolean;
    
    /**
     * 构造函数
     * @param parentRef 父级引用
     * @param mainType 主武器类型
     * @param subType 副武器类型
     */
    public function WeaponStateManager(parentRef:Object, mainType:String, subType:String) {
        this.parentRef = parentRef;
        this.mainWeaponType = mainType;
        this.subWeaponType = subType;
        
        // 初始化属性名
        mainShotCountIndex = mainWeaponType;
        mainMagCapacity = mainWeaponType + "弹匣容量";
        
        subShotCountIndex = subWeaponType;
        subMagCapacity = subWeaponType + "弹匣容量";
        
        // 初始状态更新
        updateState();
    }
    
    /**
     * 更新武器状态
     * 每次进行状态判断前调用此方法
     */
    public function updateState():Void {
        // 获取当前射击次数
        mainNumber = parentRef[mainShotCountIndex].value.shot;
        subNumber = parentRef[subShotCountIndex].value.shot;
        
        // 计算状态标志
        _mainIsEmpty = mainNumber >= parentRef[mainMagCapacity];
        _subIsEmpty = subNumber >= parentRef[subMagCapacity];
        
        _mainIsFull = mainNumber == 0;
        _subIsFull = subNumber == 0;

        // _root.发布消息(parentRef[mainWeaponType].name, parentRef[subWeaponType].name, parentRef[mainWeaponType].name == parentRef[subWeaponType].name)

        _isSameWeapon = (parentRef[mainWeaponType].name == parentRef[subWeaponType].name);
        _bothEmpty = _mainIsEmpty && _subIsEmpty;
    }
    
    // 状态判断 getter 方法
    public function get mainIsEmpty():Boolean { return _mainIsEmpty; }
    public function get subIsEmpty():Boolean { return _subIsEmpty; }
    public function get mainIsFull():Boolean { return _mainIsFull; }
    public function get subIsFull():Boolean { return _subIsFull; }
    public function get isSameWeapon():Boolean { return _isSameWeapon; }

    /**
     * 判断两把枪是否都彻底空了
     * @return 当主手和副手都空弹时返回 true
     */
    public function get bothEmpty():Boolean { return _bothEmpty; }
    
    /**
     * 判断是否需要换弹
     * 整合了三个方法中的换弹判断逻辑
     * 当满足以下任一条件时需要换弹:
     * 1. 两把枪都空了
     * 2. 主手空了且副手满了
     * 3. 主手满了且副手空了
     * 4. 一把枪空了且两把枪不同类型
     */
    public function needsReload(handPrefix:String, magazineNumber:Number):Boolean {
        // 早期返回：如果两手都不空且是同一武器，不需要重新装弹
        if (_isSameWeapon && !_mainIsEmpty && !_subIsEmpty) {
            return false;
        }
        
        var isMainHand:Boolean = (handPrefix === "主手");
        
        // 有弹匣：检查当前手；无弹匣：检查另一手
        return (magazineNumber > 0) ? 
            (isMainHand ? _mainIsEmpty : _subIsEmpty) :
            (isMainHand ? _subIsEmpty : _mainIsEmpty);
    }
    
    /**
     * 判断主手是否应该首先换弹
     * 综合考虑弹匣状态和可换弹性来决定优先级
     * @param isMainHandReloadable 主手是否有弹匣可换
     * @param isSubHandReloadable 副手是否有弹匣可换
     */
    public function shouldReloadMainFirst(isMainHandReloadable:Boolean, isSubHandReloadable:Boolean):Boolean {
        // 如果主手无法换弹，则不应该优先主手
        if (!isMainHandReloadable) {
            return false;
        }
        
        // 如果主手已空，且主手可以换弹，则优先主手
        if (_mainIsEmpty) {
            return true;
        }
        
        // 如果主手未满且副手满弹，且主手可以换弹，则优先主手
        if (!_mainIsFull && _subIsFull) {
            return true;
        }
        
        // 如果副手无法换弹，但主手未满且可以换弹，则选择主手
        if (!isSubHandReloadable && !_mainIsFull) {
            return true;
        }
        
        return false;
    }


    /**
     * 判断主手是否应该换弹
     * 在以下情况下副手应该换弹:
     * 1. 主手未满
     */
    public function shouldReloadMain():Boolean {
        return !_mainIsFull;
    }

        
    /**
     * 判断副手是否应该换弹
     * 在以下情况下副手应该换弹:
     * 1. 副手未满
     */
    public function shouldReloadSub():Boolean {
        return !_subIsFull;
    }
    
    /**
     * 判断是否可以结束换弹 - 主手
     * @param remainingMainMag 主手剩余弹匣数
     * @param remainingSubMag 副手剩余弹匣数
     * @param hasImpactChain  是否启用冲击连携被动（启用时避免给未空的另一手补满）
     * @return 是否可以结束换弹
     */
    public function canFinishMainHandReload(remainingMainMag:Number, remainingSubMag:Number, hasImpactChain:Boolean):Boolean {
        // 无可用弹匣：直接结束
        if (remainingSubMag == 0) {
            return true;
        }

        // 半换弹仅在“冲击连携启用 + 双枪异枪”时生效
        // 启用时：只要另一手未空即可结束（避免补满未空的那把枪）
        if (hasImpactChain && !_isSameWeapon) {
            return subNumber < parentRef[subMagCapacity];
        }

        // 默认策略：同枪时倾向补满另一手；异枪时仅保证另一手未空
        return _isSameWeapon ? _subIsFull : subNumber < parentRef[subMagCapacity];
    }
    
    /**
     * 判断是否可以结束换弹 - 副手
     * @param remainingMainMag 主手剩余弹匣数
     * @param remainingSubMag 副手剩余弹匣数
     * @param hasImpactChain  是否启用冲击连携被动（启用时避免给未空的另一手补满）
     * @return 是否可以结束换弹
     */
    public function canFinishSubHandReload(remainingMainMag:Number, remainingSubMag:Number, hasImpactChain:Boolean):Boolean {
        // 无可用弹匣：直接结束
        if (remainingMainMag == 0) {
            return true;
        }

        // 半换弹仅在“冲击连携启用 + 双枪异枪”时生效
        // 启用时：只要另一手未空即可结束（避免补满未空的那把枪）
        if (hasImpactChain && !_isSameWeapon) {
            return mainNumber < parentRef[mainMagCapacity];
        }

        // 默认策略：同枪时倾向补满另一手；异枪时仅保证另一手未空
        return _isSameWeapon ? _mainIsFull : mainNumber < parentRef[mainMagCapacity];
    }
    
    /**
     * 判断是否需要进行任何换弹操作
     * 仅当两把枪都满弹时返回 false
     */
    public function needsAnyReload():Boolean {
        return !(_mainIsFull && _subIsFull);
    }
    
    // 提供原始属性访问
    public function getMainNumber():Number { return mainNumber; }
    public function getSubNumber():Number { return subNumber; }

    // ======================================================
    // 决策 API - 封装复杂的业务逻辑判断
    // ======================================================

    /**
     * 判断当前手空弹时是否应该触发自动换弹
     * 封装了冲击连携被动技能对换弹策略的影响
     *
     * 规则：
     * - AI控制：有弹匣就换弹
     * - 玩家控制 + 冲击连携 + 异枪：单手空即可换弹
     * - 玩家控制 + 同枪：仍需两把都空才换弹（避免同枪半换弹手感割裂）
     * - 玩家控制 + 无冲击连携：必须两把都空才换弹
     *
     * @param isHeroControlled 是否为玩家控制
     * @param hasImpactChain   是否启用冲击连携被动
     * @param currentHandMag   当前手剩余弹匣数
     * @return true = 应该触发换弹, false = 跳过换弹
     */
    public function shouldAutoReloadOnEmpty(isHeroControlled:Boolean, hasImpactChain:Boolean, currentHandMag:Number):Boolean {
        // AI 控制：有弹匣就换弹
        if (!isHeroControlled) {
            return currentHandMag > 0;
        }

        // 玩家控制：检查弹匣和换弹条件
        if (currentHandMag <= 0) {
            return false;
        }

        // 半换弹仅在“冲击连携启用 + 双枪异枪”时生效
        // 否则仍按“两把都空”触发自动换弹
        var halfReloadEnabled:Boolean = (hasImpactChain && !_isSameWeapon);
        return halfReloadEnabled || _bothEmpty;
    }

    /**
     * 决定双枪换弹时应该换哪只手
     * 封装了优先级判断和弹匣库存校验，确保不会出现"无弹匣也能换弹"的问题
     *
     * 规则：
     * - 半换弹（冲击连携启用 + 异枪）：使用优先级判断（主手优先策略）
     * - 非半换弹（无冲击连携或同枪）：优先换空弹的那只手，其次允许补弹
     * - 任何情况下都必须有弹匣才能换弹
     *
     * @param hasImpactChain 是否启用冲击连携被动
     * @param target         目标 MovieClip（用于获取弹匣名称和库存）
     * @return 0 = 不需要换弹, 1 = 主手换弹, 2 = 副手换弹
     */
    public function decideReloadHand(hasImpactChain:Boolean, target:Object):Number {
        var halfReloadEnabled:Boolean = (hasImpactChain && !_isSameWeapon);

        // 延迟查询库存：只在需要时才调用 ItemUtil
        var isMainReloadable:Boolean = false;
        var isSubReloadable:Boolean = false;

        // 半换弹：使用完整的优先级判断
        if (halfReloadEnabled) {
            // 先检查主手是否需要且可以换弹
            if (!_mainIsFull) {
                isMainReloadable = !!(ItemUtil.singleContain(target.主手使用弹匣名称, 1));
                if (isMainReloadable) {
                    // 检查是否应该优先主手
                    isSubReloadable = !!(ItemUtil.singleContain(target.副手使用弹匣名称, 1));
                    if (shouldReloadMainFirst(isMainReloadable, isSubReloadable)) {
                        return 1; // 主手换弹
                    }
                }
            }

            // 检查副手是否需要且可以换弹
            if (!_subIsFull) {
                if (!isSubReloadable) {
                    isSubReloadable = !!(ItemUtil.singleContain(target.副手使用弹匣名称, 1));
                }
                if (isSubReloadable) {
                    return 2; // 副手换弹
                }
            }

            // 如果副手不能换，但主手可以且未满
            if (!_mainIsFull && isMainReloadable) {
                return 1; // 主手换弹
            }
        } else {
            // 非半换弹：优先换空弹的那只手，其次允许补弹
            // 优先换空弹的那只手
            if (_mainIsEmpty && !_mainIsFull) {
                isMainReloadable = !!(ItemUtil.singleContain(target.主手使用弹匣名称, 1));
                if (isMainReloadable) {
                    return 1; // 主手换弹
                }
            }

            if (_subIsEmpty && !_subIsFull) {
                isSubReloadable = !!(ItemUtil.singleContain(target.副手使用弹匣名称, 1));
                if (isSubReloadable) {
                    return 2; // 副手换弹
                }
            }

            // 如果都没空但未满，检查是否可以补弹
            if (!_mainIsFull) {
                isMainReloadable = !!(ItemUtil.singleContain(target.主手使用弹匣名称, 1));
                if (isMainReloadable) {
                    return 1;
                }
            }

            if (!_subIsFull) {
                isSubReloadable = !!(ItemUtil.singleContain(target.副手使用弹匣名称, 1));
                if (isSubReloadable) {
                    return 2;
                }
            }
        }

        return 0; // 不需要换弹
    }
}
