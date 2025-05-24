import org.flashNight.naki.DataStructures.*;

// 时间轮接口，定义时间轮必须实现的功能
interface org.flashNight.neur.TimeWheel.ITimeWheel {
    
    // 返回时间轮的当前状态，包含指针位置、槽位任务数、节点池大小等信息
    function getTimeWheelStatus():Object;

    // 根据任务ID添加定时任务
    function addTimerByID(taskID:String, delay:Number):TaskIDNode;

    // 根据任务节点添加定时任务
    function addTimerByNode(node:TaskIDNode, delay:Number):TaskIDNode;

    // 根据任务ID移除定时任务
    function removeTimerByID(taskID:String):Void;

    // 根据任务节点移除定时任务
    function removeTimerByNode(node:TaskIDNode):Void;

    // 根据任务ID重新安排定时任务
    function rescheduleTimerByID(taskID:String, newDelay:Number):Void;

    // 根据任务节点重新安排定时任务
    function rescheduleTimerByNode(node:TaskIDNode, newDelay:Number):Void;

    // 推进时间轮，并返回当前槽的任务链表
    function tick():TaskIDLinkedList;

    // 节点池管理：获取节点池大小
    function getNodePoolSize():Number;

    // 节点池管理：填充节点池
    function fillNodePool(size:Number):Void;

    // 节点池管理：缩减节点池
    function trimNodePool(size:Number):Void;
}
