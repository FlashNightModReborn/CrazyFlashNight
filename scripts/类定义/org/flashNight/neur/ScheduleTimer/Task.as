import org.flashNight.naki.DataStructures.*;

/**
 * 定时任务数据结构 (对应原始代码中的"任务"对象)
 * 
 * ░░░░░░░░░░░░░ 原始代码属性对应关系 ░░░░░░░░░░░░░
 * 原属性名       => 本类属性名       | 变更说明
 * -----------------------------------------------------------------
 * taskID        => id             | 保持相同，任务唯一标识符
 * 间隔帧数      => intervalFrames  | 语义不变，执行间隔帧数（初始值）
 * 重复次数      => repeatCount     | 支持数值型/布尔型（true为无限循环）
 * 待执行帧数    => pendingFrames  | 新增明确命名，表示剩余等待帧数
 * 参数数组      => parameters     | 保持参数存储功能
 * 动作          => action         | 保持函数引用功能
 * node          => node           | 类型明确为TaskIDNode，关联优先级队列节点
 */
class org.flashNight.neur.ScheduleTimer.Task {
    //----------------------------------------
    //  核心属性 (与原始代码直接对应)
    //----------------------------------------
    
    /**
     * 任务唯一标识符 (对应原始代码中的taskID)
     * @type {String}
     */
    public var id:String;
    
    /**
     * 任务执行间隔帧数 (对应原始"间隔帧数")
     * - 根据原始代码逻辑，通过 间隔时间*毫秒每帧 计算得到
     * @type {Number}
     */
    public var intervalFrames:Number;
    
    /**
     * 任务重复模式 (对应原始"重复次数")
     * - Number类型: 剩余执行次数（1表示单次）
     * - Boolean类型: true代表无限循环（对应原始代码中循环任务）
     * @type {Number|Boolean}
     */
    public var repeatCount;
    
    //----------------------------------------
    //  运行时属性 (与原始代码逻辑对应)
    //----------------------------------------
    
    /**
     * 调度延迟帧数 (对应原始"待执行帧数")
     * - 作为 evaluateAndInsertTask / rescheduleTaskByNode 的延迟参数
     * - 重新调度时重置为 intervalFrames
     * - delayTask 累加延迟帧数到此字段
     * - 值为 Infinity 时表示任务被暂停（delayTask(true) 语义）
     * 注意：此字段并非每帧递减，实际倒计时由时间轮/堆节点的 priority 管理
     * @type {Number}
     */
    public var pendingFrames:Number;
    
    /**
     * 任务参数存储 (对应原始代码中的arguments.slice操作)
     * - 上层通过Delegate.createWithParams绑定参数
     * @type {Array}
     */
    public var parameters:Array;
    
    /**
     * 任务执行函数 (对应原始"动作")
     * - 通过Delegate.createWithParams绑定上下文和参数
     * @type {Function}
     */
    public var action:Function;
    
    /**
     * 在调度器队列中的节点引用 (对应原始"节点")
     * - 用于快速定位任务在优先级队列中的位置
     * - 当任务进入zeroFrameTasks时应置空
     * @type {TaskIDNode}
     */
    public var node:TaskIDNode;

    //----------------------------------------
    //  构造函数
    //----------------------------------------
    
    /**
     * 构造函数
     * @param {String} id 任务ID，通过任务ID计数器生成
     * @param {Number} intervalFrames 初始间隔帧数
     * @param {Number|Boolean} [repeatCount=1] 重复次数 
     *        - Number: 具体次数 
     *        - Boolean: true为无限循环
     */
    public function Task(id:String, intervalFrames:Number, repeatCount) {
        this.id = id;
        this.intervalFrames = intervalFrames;
        // 使用双等号同时处理 undefined 和 null
        this.repeatCount = (repeatCount == null) ? 1 : repeatCount;
    }

    /**
     * 返回任务的调试信息字符串
     * - 显示关键属性：ID、间隔帧数、重复模式、剩余帧数
     * - 包含运行状态：参数数量、动作绑定状态、队列节点关联状态
     * @return {String} 任务详细信息的格式化字符串
     */
    public function toString():String {
        var repeatInfo:String = (typeof this.repeatCount == "boolean" && this.repeatCount === true) 
            ? "无限循环" 
            : "剩余" + this.repeatCount + "次";
        
        var paramInfo:String = this.parameters ? "参数[" + this.parameters.length + "]" : "无参数";
        var actionInfo:String = this.action ? "已绑定" : "未绑定";
        var nodeInfo:String = this.node ? "队列中" : "非队列";
        
        return "[Task id=" + this.id + 
            " interval=" + this.intervalFrames + 
            " repeat=" + repeatInfo + 
            " pending=" + this.pendingFrames + 
            " | " + paramInfo + 
            ", action:" + actionInfo + 
            ", node:" + nodeInfo + "]";
    }
}
