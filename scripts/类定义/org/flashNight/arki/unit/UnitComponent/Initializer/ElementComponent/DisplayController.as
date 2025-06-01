import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
/**
 * 显示控制组件 - 负责控制地图元件的显示相关属性
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.DisplayController {
    
    /**
     * 初始化目标的显示控制
     * @param target 要初始化的目标MovieClip
     */
    public static function initialize(target:MovieClip):Void {
        // 设置区域不可见
        DisplayController.setAreaVisibility(target, false);
        
        // 根据Y坐标调整深度
        DisplayController.adjustDepthByPosition(target);
    }
    
    /**
     * 设置目标区域的可见性
     * @param target 目标MovieClip
     * @param visible 是否可见
     */
    public static function setAreaVisibility(target:MovieClip, visible:Boolean):Void {
        if (target && target.area) {
            target.area._visible = visible;
        }
    }
    
    /**
     * 根据Y坐标调整目标的显示深度
     * @param target 目标MovieClip
     */
    public static function adjustDepthByPosition(target:MovieClip):Void {
        if (target && target._y !== undefined) {
            target.swapDepths(target._y);
        }
    }
    
    /**
     * 设置目标的透明度
     * @param target 目标MovieClip
     * @param alpha 透明度值 (0-100)
     */
    public static function setAlpha(target:MovieClip, alpha:Number):Void {
        if (target) {
            target._alpha = Math.max(0, Math.min(100, alpha));
        }
    }
    
    /**
     * 设置目标的可见性
     * @param target 目标MovieClip
     * @param visible 是否可见
     */
    public static function setVisibility(target:MovieClip, visible:Boolean):Void {
        if (target) {
            target._visible = visible;
        }
    }
    
    /**
     * 设置目标的缩放
     * @param target 目标MovieClip
     * @param scaleX X轴缩放比例
     * @param scaleY Y轴缩放比例，如果不提供则使用scaleX的值
     */
    public static function setScale(target:MovieClip, scaleX:Number, scaleY:Number):Void {
        if (!target) return;
        
        if (scaleY === undefined) {
            scaleY = scaleX;
        }
        
        target._xscale = scaleX;
        target._yscale = scaleY;
    }
    
    /**
     * 设置目标的位置
     * @param target 目标MovieClip
     * @param x X坐标
     * @param y Y坐标
     * @param adjustDepth 是否根据新Y坐标调整深度
     */
    public static function setPosition(target:MovieClip, x:Number, y:Number, adjustDepth:Boolean):Void {
        if (!target) return;
        
        target._x = x;
        target._y = y;
        
        // 更新Z轴坐标
        if (target.Z轴坐标 !== undefined) {
            target.Z轴坐标 = y;
        }
        
        // 是否需要调整深度
        if (adjustDepth) {
            DisplayController.adjustDepthByPosition(target);
        }
    }
    
    /**
     * 设置目标的深度
     * @param target 目标MovieClip
     * @param depth 新的深度值
     */
    public static function setDepth(target:MovieClip, depth:Number):Void {
        if (target) {
            target.swapDepths(depth);
        }
    }
    
    /**
     * 获取目标当前的深度
     * @param target 目标MovieClip
     * @return Number 当前深度值，如果目标无效则返回-1
     */
    public static function getDepth(target:MovieClip):Number {
        if (!target) return -1;
        return target.getDepth();
    }
    
    /**
     * 隐藏目标的所有子元件的区域
     * @param target 目标MovieClip
     */
    public static function hideAllAreas(target:MovieClip):Void {
        if (!target) return;
        
        // 递归隐藏所有子元件的area
        for (var prop in target) {
            var child:MovieClip = target[prop];
            if (child instanceof MovieClip) {
                if (child.area) {
                    child.area._visible = false;
                }
                DisplayController.hideAllAreas(child);
            }
        }
    }
    
    /**
     * 批量设置多个目标的可见性
     * @param targets 目标数组
     * @param visible 是否可见
     */
    public static function setBatchVisibility(targets:Array, visible:Boolean):Void {
        if (!targets) return;
        
        for (var i:Number = 0; i < targets.length; i++) {
            DisplayController.setVisibility(targets[i], visible);
        }
    }
    
    /**
     * 批量调整多个目标的深度
     * @param targets 目标数组
     */
    public static function batchAdjustDepth(targets:Array):Void {
        if (!targets) return;
        
        for (var i:Number = 0; i < targets.length; i++) {
            DisplayController.adjustDepthByPosition(targets[i]);
        }
    }
    
    /**
     * 重置目标的显示属性为默认值
     * @param target 目标MovieClip
     */
    public static function resetDisplayProperties(target:MovieClip):Void {
        if (!target) return;
        
        target._visible = true;
        target._alpha = 100;
        target._xscale = 100;
        target._yscale = 100;
        
        if (target.area) {
            target.area._visible = false;
        }
    }
}