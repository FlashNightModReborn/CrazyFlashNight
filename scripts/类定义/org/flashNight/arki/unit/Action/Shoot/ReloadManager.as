import org.flashNight.arki.item.*;

/**
 * ReloadManager.as
 * 
 * 武器换弹管理器类，将原 _root.主角函数 中的换弹和弹药显示逻辑封装到此类中
 * 经过重构优化，集中管理换弹相关的所有功能
 * 主要负责：
 * 1. 开始换弹、换弹匣和结束换弹的流程控制
 * 2. 单武器和双武器系统的换弹逻辑
 * 3. UI界面中弹药数量的显示更新
 * 4. 弹匣消耗和库存管理的交互
 */
class org.flashNight.arki.unit.Action.Shoot.ReloadManager {
    
    /**
     * 开始武器换弹
     * @param target 目标MovieClip (原this引用)
     * @param parentRef 父级引用 (原_parent引用)
     * @param rootRef 根引用 (原_root引用)
     */
    public static function startReload(target:MovieClip, parentRef:Object, rootRef:Object):Void {
        var attackMode:String = parentRef.攻击模式;
        
        // 如果已在换弹或弹匣已满，则直接返回
        if (target.换弹标签 || parentRef[attackMode + "射击次数"][parentRef[attackMode]] == 0) {
            return;
        }
        
        // 检查是否为玩家控制的角色
        if (rootRef.控制目标 === parentRef._name) {
            // 检查是否有可用弹匣
            if (ItemUtil.singleContain(target.使用弹匣名称, 1) != null) {
                target.gotoAndPlay("换弹匣");
            }
        } else {
            // AI角色直接进入换弹状态
            target.gotoAndPlay("换弹匣");
        }
    }
    
    /**
     * 执行换弹匣操作
     * @param target 目标MovieClip (原this引用)
     * @param parentRef 父级引用 (原_parent引用)
     * @param rootRef 根引用 (原_root引用)
     */
    public static function reloadMagazine(target:MovieClip, parentRef:Object, rootRef:Object):Void {
        var attackMode:String = parentRef.攻击模式;
        
        // 重置射击次数
        parentRef[attackMode + "射击次数"][parentRef[attackMode]] = 0;
        
        // 检查是否为玩家控制的角色
        if (rootRef.控制目标 === parentRef._name) {
            // 消耗一个弹匣
            ItemUtil.singleSubmit(target.使用弹匣名称, 1);
            
            // 更新剩余弹匣数
            target.剩余弹匣数 = ItemUtil.getTotal(target.使用弹匣名称);
            
            // 检查弹匣是否耗尽
            if (target.剩余弹匣数 === 0) {
                rootRef.发布消息("弹匣耗尽！");
            }
            
            // 更新物品栏
            rootRef.排列物品图标();
            
            // 重置副武器发射数据
            parentRef.当前弹夹副武器已发射数 = 0;
            
            // 刷新UI显示
            ReloadManager.updateAmmoDisplay(target, parentRef, rootRef);
        }
    }
    
    /**
     * 结束换弹过程
     * @param target 目标MovieClip (原this引用)
     */
    public static function finishReload(target:MovieClip):Void {
        target.gotoAndStop("空闲");
    }
    
    /**
     * 更新弹药显示界面
     * @param target 目标MovieClip (原this引用)
     * @param parentRef 父级引用 (原_parent引用)
     * @param rootRef 根引用 (原_root引用)
     */
    public static function updateAmmoDisplay(target:MovieClip, parentRef:Object, rootRef:Object):Void {
        // 如果控制目标不匹配，则直接返回
        if (rootRef.控制目标 != parentRef._name) {
            return;
        }
        
        // 缓存UI引用
        var ui:Object = rootRef.玩家信息界面.玩家必要信息界面;
        var mode:String = parentRef.攻击模式;
        var weapons:Array = [];
        
        // 构造武器配置
        if (mode === "双枪") {
            // 主手武器配置
            weapons.push({
                weapon: parentRef.手枪,
                capacity: parentRef.手枪弹匣容量,
                shot: parentRef.手枪射击次数[parentRef.手枪],
                uiBullet: "子弹数",
                uiMag: "弹夹数",
                magCount: target.主手剩余弹匣数
            });
            
            // 副手武器配置
            weapons.push({
                weapon: parentRef.手枪2,
                capacity: parentRef.手枪2弹匣容量,
                shot: parentRef.手枪2射击次数[parentRef.手枪2],
                uiBullet: "子弹数_2",
                uiMag: "弹夹数_2",
                magCount: target.副手剩余弹匣数
            });
        } else {
            // 单武器配置
            var singleShot:Number = parentRef[mode + "射击次数"][parentRef[mode]];
            weapons.push({
                weapon: parentRef.长枪, // 注：这里使用长枪引用但实际以mode判断类型
                capacity: parentRef[mode + "弹匣容量"],
                shot: singleShot,
                uiBullet: "子弹数",
                uiMag: "弹夹数",
                magCount: target.剩余弹匣数
            });
        }
        
        // 遍历更新每个武器的UI显示
        for (var i:Number = 0; i < weapons.length; i++) {
            var w:Object = weapons[i];
            var data:Object = ItemUtil.getRawItemData(w.weapon);
            
            // 计算子弹消耗系数
            var cost:Number = (data.data.bullet.indexOf("纵向") >= 0) ? data.data.split : 1;
            
            // 计算剩余子弹数
            var remaining:Number = w.capacity - w.shot;
            // 更新UI显示
            ui[w.uiBullet] = cost * remaining;
            ui[w.uiMag] = w.magCount;
        }
    }
    
    /**
     * 为双枪系统创建开始换弹函数
     * 封装了双枪模式下的换弹逻辑，使用武器状态管理器进行状态判断
     * 
     * @param target        目标 MovieClip
     * @param parentRef     父级引用
     * @param rootRef       根引用
     * @param stateManager  武器状态管理器
     * @return 返回开始换弹函数
     */
    public static function createDualGunReloadStartFunction(target:MovieClip, parentRef:Object, rootRef:Object, stateManager:Object):Function {
        var self:MovieClip = target;
        
        return function():Void {
            var that:MovieClip = self;
            
            // 检查换弹标签
            if (that.换弹标签) {
                return;
            }
            
            // 更新武器状态
            stateManager.updateState();
            
            // 使用状态管理器检查是否需要任何换弹
            if (!stateManager.needsAnyReload()) {
                return;
            }
            
            if (rootRef.控制目标 === parentRef._name) {
                // 使用状态管理器检查应该优先换哪把枪
                var isMainHandReloadable:Boolean = !!(ItemUtil.singleContain(that.主手使用弹匣名称, 1));
                var isSubHandReloadable:Boolean = !!(ItemUtil.singleContain(that.副手使用弹匣名称, 1));
                
                if (stateManager.shouldReloadMainFirst(isMainHandReloadable, isSubHandReloadable)) {
                    // _root.发布消息("主手换弹匣" );
                    that.gotoAndPlay("主手换弹匣");
                    return;
                } else {
                    if (stateManager.shouldReloadSub() && isSubHandReloadable) {
                        // _root.发布消息("副手换弹匣");
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
     * 为双枪系统创建手枪换弹函数
     * 封装了特定手枪的换弹逻辑，使用武器状态管理器进行状态判断
     * 
     * @param target        目标 MovieClip
     * @param parentRef     父级引用
     * @param rootRef       根引用
     * @param config        武器手配置对象
     * @param stateManager  武器状态管理器
     * @return 返回特定手的换弹匣函数
     */
    public static function createHandReloadFunction(target:MovieClip, parentRef:Object, rootRef:Object, config:Object, stateManager:Object):Function {
        var self:MovieClip = target;
        var handPrefix:String = config.handPrefix;
        var weaponType:String = config.weaponType;
        var magNameProp:String = handPrefix + "使用弹匣名称";
        
        // 弹匣相关属性
        var shotCountArray:String = weaponType + "射击次数";
        var shotCountIndex:String = weaponType;
        
        return function():Void {
            var that:MovieClip = self;
            
            // 重置射击次数
            parentRef[shotCountArray][parentRef[shotCountIndex]] = 0;
            
            if (rootRef.控制目标 === parentRef._name) {
                // 使用弹匣
                ItemUtil.singleSubmit(that[magNameProp], 1);
                
                // 更新弹匣数量（两把枪都需要更新）
                that.主手剩余弹匣数 = ItemUtil.getTotal(that.主手使用弹匣名称);
                that.副手剩余弹匣数 = ItemUtil.getTotal(that.副手使用弹匣名称);
                
                // 检查弹匣耗尽
                if (that[handPrefix + "剩余弹匣数"] === 0) {
                    rootRef.发布消息("弹匣耗尽！");
                }
                
                // 更新物品与显示
                rootRef.排列物品图标();
                ReloadManager.updateAmmoDisplay(that, parentRef, rootRef);
                
                // 更新武器状态
                stateManager.updateState();
                
                // 使用状态管理器检查是否可以结束换弹
                if (handPrefix == "主手") {
                    if (stateManager.canFinishMainHandReload(that.主手剩余弹匣数, that.副手剩余弹匣数)) {
                        that.gotoAndPlay("换弹结束");
                    }
                } else {
                    if (stateManager.canFinishSubHandReload(that.主手剩余弹匣数, that.副手剩余弹匣数)) {
                        that.gotoAndPlay("换弹结束");
                    }
                }
            }
        };
    }
}