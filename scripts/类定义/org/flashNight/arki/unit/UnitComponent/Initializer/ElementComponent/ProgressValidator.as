import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
/**
 * 进度验证组件 - 负责验证地图元件的主线任务进度限制
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.ProgressValidator {
    
    /**
     * 验证目标是否满足进度要求
     * @param target 要验证的目标MovieClip
     * @return Boolean 如果满足要求返回true，否则返回false并移除目标
     */
    public static function validate(target:MovieClip):Boolean {
        // 检查最小主线进度要求
        if (!isNaN(target.最小主线进度) && _root.主线任务进度 < target.最小主线进度) {
            target.removeMovieClip();
            return false;
        }
        
        // 检查最大主线进度限制
        if (!isNaN(target.最大主线进度) && _root.主线任务进度 > target.最大主线进度) {
            target.removeMovieClip();
            return false;
        }
        
        return true;
    }
    
    /**
     * 检查目标是否有进度限制设置
     * @param target 要检查的目标MovieClip
     * @return Boolean 如果有进度限制返回true
     */
    public static function hasProgressLimits(target:MovieClip):Boolean {
        return !isNaN(target.最小主线进度) || !isNaN(target.最大主线进度);
    }
}