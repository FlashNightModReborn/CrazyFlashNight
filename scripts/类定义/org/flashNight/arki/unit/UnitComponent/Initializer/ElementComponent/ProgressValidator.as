import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
/**
 * 进度验证组件 - 负责验证地图元件的主线任务进度限制
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.ProgressValidator {
    
/**
 * 安全删除 MovieClip（时间轴实例需先挪到动态深度再删）
 */
private static function safeRemove(target:MovieClip):Void {
    if (target == undefined) return;

    // 根层/关卡级别不允许直接删，给个兜底
    if (target == _root) { 
        target.unloadMovie(); 
        target._visible = false; 
        return; 
    }

    var p:MovieClip = target._parent;
    if (p == undefined) { // 理论上用不到，但防御一下
        target.removeMovieClip();
        return;
    }

    // 如果是时间轴实例（深度<0），先挪到同一父容器的动态深度
    // 注意：swapDepths 应该用父容器的 getNextHighestDepth()
    var d:Number = target.getDepth();
    if (d < 0) {
        var safeDepth:Number = p.getNextHighestDepth(); // >=0 的空闲深度
        target.swapDepths(safeDepth);
    }

    // 挪到动态深度后即可真正删除
    target.removeMovieClip();

    // 兜底：极端情况下（组件/系统锁定），至少清空与隐藏
    if (typeof target == "movieclip") { // 如果还保留着引用
        target.unloadMovie();
        target._visible = false;
    }
}


    /**
     * 验证目标是否满足进度要求
     * @param target 要验证的目标MovieClip
     * @return Boolean 如果满足要求返回true，否则返回false并移除目标
     */
    public static function validate(target:MovieClip):Boolean {
        // 显式转换为数值类型，防止 XML 解析产生的字符串隐患
        var minProgress:Number = Number(target.最小主线进度);
        var maxProgress:Number = Number(target.最大主线进度);
        var currentProgress:Number = Number(_root.主线任务进度);

        // _root.发布消息(_root.主线任务进度, currentProgress, " vs ", target.最小主线进度,minProgress, " - ", target.最大主线进度, maxProgress, currentProgress < minProgress, " | ", currentProgress > maxProgress);

        // 检查最小主线进度要求
        if (!isNaN(minProgress) && currentProgress < minProgress) {
            safeRemove(target);
            return false;
        }

        // 检查最大主线进度限制
        if (!isNaN(maxProgress) && currentProgress > maxProgress) {
            safeRemove(target);
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
        return !isNaN(Number(target.最小主线进度)) || !isNaN(Number(target.最大主线进度));
    }
}