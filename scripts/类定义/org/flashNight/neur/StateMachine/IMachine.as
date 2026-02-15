import org.flashNight.neur.StateMachine.FSM_Status;

/**
 * 状态机公共接口
 *
 * 仅暴露行为方法与只读查询。
 * setter（setActiveState/setLastState）已从接口和实现类中完全移除 —
 * 绕过生命周期管理，请使用 ChangeState() 进行安全的状态切换。
 */
interface org.flashNight.neur.StateMachine.IMachine {
    function start():Void;                  // 显式启动状态机，触发首次 onEnter（幂等）
    function ChangeState(name:String):Void;  // 请求切换状态（未 start 时仅移指针）
    function getActionCount():Number;       // 当前活跃状态已执行的 action 次数（只读）
    function getActiveState():FSM_Status;    // 当前活跃状态
    function getLastState():FSM_Status;      // 上一个状态
    function getActiveStateName():String;    // 当前活跃状态名

    /**
     * 查询状态机是否已注册指定状态名。
     * 目的：避免外部直接读取 statusDict（也避免 AS2 为绕过类型检查而使用的动态访问“黑魔法”）。
     */
    function hasStatus(name:String):Boolean;
}
