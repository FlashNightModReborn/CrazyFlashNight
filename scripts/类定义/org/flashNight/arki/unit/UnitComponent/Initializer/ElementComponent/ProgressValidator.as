import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
/**
 * 进度验证组件 - 负责验证地图元件和关卡拾取物的任务进度限制
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
     * 只判断配置是否满足进度要求，不产生显示对象副作用。
     * 地图元件和直接拾取物共用此入口，避免两套任务门控语义漂移。
     * @param config 带进度字段的配置对象
     * @return Boolean 如果满足要求返回true
     */
    public static function meetsRequirements(config:Object):Boolean {
        if (config == undefined) return true;

        // 显式转换为数值类型，防止 XML 解析产生的字符串隐患
        var minProgress:Number = Number(config.最小主线进度);
        var maxProgress:Number = Number(config.最大主线进度);
        var currentProgress:Number = Number(_root.主线任务进度);

        // 检查最小主线进度要求
        if (!isNaN(minProgress) && currentProgress < minProgress) {
            return false;
        }

        // 检查最大主线进度限制
        if (!isNaN(maxProgress) && currentProgress > maxProgress) {
            return false;
        }

        var minChainProgress:Number = Number(config.最小任务链进度);
        var maxChainProgress:Number = Number(config.最大任务链进度);
        if (!isNaN(minChainProgress) || !isNaN(maxChainProgress)) {
            var chainName = config.任务链名称;
            if (chainName == undefined || String(chainName).length == 0) return false;

            var currentChainProgress:Number = 0;
            if (_root.task_chains_progress != undefined) {
                currentChainProgress = Number(_root.task_chains_progress[String(chainName)]);
                if (isNaN(currentChainProgress)) currentChainProgress = 0;
            }

            if (!isNaN(minChainProgress) && currentChainProgress < minChainProgress) return false;
            if (!isNaN(maxChainProgress) && currentChainProgress > maxChainProgress) return false;
        }

        var activeTaskId = config.要求进行中任务ID;
        if (activeTaskId != undefined && activeTaskId != null && String(activeTaskId).length > 0) {
            var tasks:Array = _root.tasks_to_do;
            var isActive:Boolean = false;
            if (tasks != undefined) {
                for (var i:Number = 0; i < tasks.length; i++) {
                    if (tasks[i] != undefined && String(tasks[i].id) == String(activeTaskId)) {
                        isActive = true;
                        break;
                    }
                }
            }
            if (!isActive) return false;
        }

        return true;
    }

    /**
     * 验证地图元件是否满足进度要求；不满足时安全移除目标。
     * @param target 要验证的目标MovieClip
     * @return Boolean 如果满足要求返回true，否则返回false并移除目标
     */
    public static function validate(target:MovieClip):Boolean {
        if (!ProgressValidator.meetsRequirements(target)) {
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
        return !isNaN(Number(target.最小主线进度))
            || !isNaN(Number(target.最大主线进度))
            || !isNaN(Number(target.最小任务链进度))
            || !isNaN(Number(target.最大任务链进度))
            || (target.要求进行中任务ID != undefined && target.要求进行中任务ID != null);
    }
}
