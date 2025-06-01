import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/**
 * 交互处理组件 - 负责处理地图元件的交互功能，如拾取等
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.InteractionHandler {
    
    // 交互距离常量
    private static var INTERACTION_Z_DISTANCE:Number = 50;
    private static var DEFAULT_PICKUP_AUDIO:String = "拾取音效";
    
    /**
     * 初始化目标的交互功能
     * @param target 要初始化的目标MovieClip
     */
    public static function initialize(target:MovieClip):Void {
        // 设置拾取检测功能
        InteractionHandler.setupPickupDetection(target);
        
        // 设置拾取处理功能
        InteractionHandler.setupPickupHandler(target);
    }
    
    /**
     * 设置拾取检测功能
     * @param target 要设置的目标MovieClip
     */
    private static function setupPickupDetection(target:MovieClip):Void {
        var pickUpFunc:Function = function():Void {
            if (this._killed) return; // 避免多次触发
            
            var focusedObject:MovieClip = TargetCacheManager.findHero();
            if (InteractionHandler.canInteract(this, focusedObject)) {
                this.dispatcher.publish("pickUp", this);
            }
        };
        
        target.dispatcher.subscribeGlobal("interactionKeyDown", pickUpFunc, target);
    }
    
    /**
     * 设置拾取处理功能
     * @param target 要设置的目标MovieClip
     */
    private static function setupPickupHandler(target:MovieClip):Void {
        var pickFunc:Function = function(target:MovieClip):Void {
            InteractionHandler.executePickup(target);
        };
        
        target.dispatcher.subscribe("pickUp", pickFunc, target);
    }
    
    /**
     * 检查两个对象是否可以交互
     * @param target 目标对象
     * @param hero 英雄对象
     * @return Boolean 如果可以交互返回true
     */
    public static function canInteract(target:MovieClip, hero:MovieClip):Boolean {
        if (!target || !hero || !target.area || !hero.area) {
            return false;
        }
        
        // 检查Z轴距离
        var zDistance:Number = Math.abs(target.Z轴坐标 - hero.Z轴坐标);
        if (zDistance >= INTERACTION_Z_DISTANCE) {
            return false;
        }
        
        // 检查区域碰撞
        return hero.area.hitTest(target.area);
    }
    
    /**
     * 执行拾取操作
     * @param target 要拾取的目标MovieClip
     */
    public static function executePickup(target:MovieClip):Void {
        // 发布死亡事件
        target.dispatcher.publish("kill", target);
        
        // 获取拾取者
        var scavenger:MovieClip = TargetCacheManager.findHero();
        if (!scavenger) return;
        
        // 播放音效
        InteractionHandler.playPickupAudio(target);
        
        // 执行拾取逻辑
        if (scavenger.拾取) {
            scavenger.拾取();
        }
    }
    
    /**
     * 播放拾取音效
     * @param target 拾取的目标MovieClip
     */
    private static function playPickupAudio(target:MovieClip):Void {
        var audio:String = target.audio || DEFAULT_PICKUP_AUDIO;
        if (_root.播放音效) {
            _root.播放音效(audio);
        }
    }
    
    /**
     * 移除目标的所有交互监听器
     * @param target 要清理的目标MovieClip
     */
    public static function cleanup(target:MovieClip):Void {
        if (target.dispatcher) {
            target.dispatcher.unsubscribeAll();
        }
    }
    
    /**
     * 设置交互距离
     * @param distance 新的交互距离
     */
    public static function setInteractionDistance(distance:Number):Void {
        INTERACTION_Z_DISTANCE = distance;
    }
}