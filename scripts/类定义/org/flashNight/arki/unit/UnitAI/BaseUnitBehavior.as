import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.unit.UnitAI.UnitAIData;

// 单位状态机基类

class org.flashNight.arki.unit.UnitAI.BaseUnitBehavior extends FSM_StateMachine{

    public var data:UnitAIData;

    public function BaseUnitBehavior(_data:UnitAIData){
        super(null,null,null);
        this.data = _data;
        this.active = false;

        // 状态列表
        // 睡眠状态（默认状态）
        this.AddStatus("Sleeping",new FSM_Status(null, this.sleep_enter, null));
    }

    private function pushGateTransition(current:String, target:String, func:Function):Void{
        if(!this.statusDict[current] || !this.statusDict[target] || !func) return;
        this.transitions.push(current, target, func, true);
    }

    public function activate():Void{
        for(var key:String in this.statusDict){
            // 所有状态在游戏暂停时及思考标签不存在时均会过渡到睡眠状态
            if(key != "Sleeping"){
                this.pushGateTransition(key, "Sleeping", this.sleepCheck);
            }
        }
        this.active = true;
        // start() 幂等：首次调用触发 Sleeping.onEnter，后续调用为 no-op
        this.start();
    }


    // 具体执行函数
    // 检查是否进入睡眠/启用ai
    public function sleepCheck():Boolean{
        return data.self.思考标签 == null || _root.暂停 === true;
    }
    public function wakeupCheck():Boolean{
        return data.self.思考标签 != null && _root.暂停 !== true;
    }
    //睡眠及各个停止函数通用
    public function sleep_enter():Void{
        data.self.左行 = false;
        data.self.右行 = false;
        data.self.上行 = false;
        data.self.下行 = false;
    }
}
