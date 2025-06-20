import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

import org.flashNight.arki.scene.StageEvent;

/**
StageEventHandler 关卡事件处理器
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.StageEventHandler {
    public static var instance:StageEventHandler; // 单例引用

    public var gameworld:MovieClip; // 当前gameworld
    private var dispatcher:LifecycleEventDispatcher; // 当前gameworld的事件分发器

    private var eventDict:Object;
    
    /**
     * 单例获取：返回全局唯一实例
     */
    public static function getInstance():StageEventHandler {
        return instance || (instance = new StageEventHandler());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function StageEventHandler() {
        gameworld = null;
    }

    
    public function init(_gw:MovieClip):Void{
        gameworld = _gw;
        dispatcher = gameworld.dispatcher;
        eventDict = {};
    }

    public function clear():Void{
        gameworld = null;
        dispatcher = null;
        eventDict = null;
    }

    public function subscribeStageEvent(stageEvent:StageEvent):Void{
        var eventName:String = stageEvent.eventName;
        if(eventDict[eventName] == null){
            eventDict[eventName] = [];
            dispatcher.subscribe(eventName, function(){
                this.handleEvent(eventName, arguments);
            }, this);
        }
        eventDict[eventName].push(stageEvent);
    }

    private function handleEvent(eventName:String, args:FunctionArguments):Void{
        var eventList = eventDict[eventName];
        var event:StageEvent;
        for(var i = eventList.length - 1; i > -1; i--){
            event = eventList[i];
            // 检查所有参数是否对应
            if(event.parameters.length > 0){
                for(var j = 0; j < event.parameters.length; j++){
                    if(event.parameters[j] != args[j]) continue;
                }
            }
            // 检测通过，执行并销毁事件
            event.execute();
            eventList.splice(i,1);
        }
    }

}