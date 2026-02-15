import org.flashNight.arki.unit.UnitAI.*;

class org.flashNight.arki.unit.UnitAI.BaseUnitAI{

    // 自身引用
    public var self:MovieClip;
    public var type:String;

    // 状态机实例
    public var stateMachine;
    // 数据黑板，UnitAIData
    public var data:UnitAIData;

    public function BaseUnitAI(_self:MovieClip, _type:String){
        this.self = _self;
        this.type = _type;
        this.data = new UnitAIData(this.self);
        switch(this.type){
            case "Enemy":
                this.stateMachine = new EnemyBehavior(this.data);
                break;
            case "PickupEnemy":
                var eb:EnemyBehavior = new EnemyBehavior(this.data);
                eb.setPickupEnabled();
                this.stateMachine = eb;
                break;
            case "Hero":
                this.stateMachine = new HeroCombatBehavior(this.data);
                break;
            case "Mecenary":
                this.stateMachine = new MecenaryBehavior(this.data);
                break;
            default:
                this.type = "Enemy";
                this.stateMachine = new EnemyBehavior(this.data);
                break;
        }

        this.stateMachine.activate();
    }

    //更新函数
    // 反应(反应)驱动的throttle不在此层实现 — unitUpdateWheel已是4帧间隔，
    // 复合tickInterval会导致Z轴阈值(10-20px)内振荡永远无法进入Engaging。
    // 反应对AI灵敏度的影响通过 UtilityEvaluator 的 commitUntilFrame 实现。
    public function update():Void{
        this.stateMachine.onAction();
    }

}
