interface org.flashNight.neur.StateMachine.IStatus {
    function onAction():Void; // 每帧刷新的事件
    function onEnter():Void; // 进入该状态的事件
    function onExit():Void; // 退出该状态的事件
}
