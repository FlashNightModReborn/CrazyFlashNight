// import org.flashNight.neur.StateMachine.FSM_Status;
// import org.flashNight.neur.StateMachine.FSM_StateMachine;

import org.flashNight.arki.unit.UnitAI.FSMEnemy;
import org.flashNight.arki.unit.UnitAI.UnitAIData;

class org.flashNight.arki.unit.UnitAI.BaseUnitAI{

    // 自身引用
    public var self:MovieClip;

    // 状态机实例
    public var stateMachine;
    // 数据黑板，UnitAIData
    public var data:UnitAIData;

    public function BaseUnitAI(_self:MovieClip){
        this.self = _self;
        this.data = new UnitAIData(this.self);
        this.stateMachine = new FSMEnemy(this.data);
        this.stateMachine.setActiveState(this.stateMachine.getDefaultState());
    }

    //更新函数
    public function update():Void{
        this.stateMachine.onAction();
    }
}
