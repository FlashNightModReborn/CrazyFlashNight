import org.flashNight.neur.StateMachine.FSM_Status;

interface org.flashNight.neur.StateMachine.IMachine {
    function start():Void;                 // 显式启动状态机，触发首次 onEnter（幂等）
    function ChangeState(name:String):Void; // 请求切换状态（未 start 时仅移指针）
    function getActiveState():FSM_Status;
    function setActiveState(state:FSM_Status):Void;
    // 当前处于的状态
    function getLastState():FSM_Status;
    function setLastState(state:FSM_Status):Void;
    // 上次处于的状态
    function getActiveStateName():String;
}
