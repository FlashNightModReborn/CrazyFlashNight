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
        
        _isSameWeapon = (parentRef[mainWeaponType] == parentRef[subWeaponType]);
    }
    
    // 状态判断 getter 方法
    public function get mainIsEmpty():Boolean { return _mainIsEmpty; }
    public function get subIsEmpty():Boolean { return _subIsEmpty; }
    public function get mainIsFull():Boolean { return _mainIsFull; }
    public function get subIsFull():Boolean { return _subIsFull; }
    public function get isSameWeapon():Boolean { return _isSameWeapon; }
    
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
     * @return 是否可以结束换弹
     */
    public function canFinishMainHandReload(remainingMainMag:Number, remainingSubMag:Number):Boolean {
        return remainingSubMag == 0 || (_isSameWeapon ? _subIsFull : subNumber < parentRef[subMagCapacity]);
    }
    
    /**
     * 判断是否可以结束换弹 - 副手
     * @param remainingMainMag 主手剩余弹匣数
     * @param remainingSubMag 副手剩余弹匣数
     * @return 是否可以结束换弹
     */
    public function canFinishSubHandReload(remainingMainMag:Number, remainingSubMag:Number):Boolean {
        return remainingMainMag == 0 || (_isSameWeapon ? _mainIsFull : mainNumber < parentRef[mainMagCapacity]);
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
}