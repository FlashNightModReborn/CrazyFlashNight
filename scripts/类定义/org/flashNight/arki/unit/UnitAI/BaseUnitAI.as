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

        // 人格兜底：Hero/Mecenary 需要 personality 驱动 Utility AI，
        // 正常流程由 _root.配置人形怪AI 在单位创建时设置。
        // 防御性检查：personality 缺失时自动生成，避免后续 NaN 级联。
        if (this.data.personality == null
            && (_type == "Hero" || _type == "Mecenary")) {
            var s:MovieClip = this.self;
            if (s.aiSeed == null) {
                var _seed:Number = s.等级 || 0;
                var _n:String = s.名字 || s._name;
                for (var _i:Number = 0; _i < _n.length; _i++) {
                    _seed = _seed * 31 + _n.charCodeAt(_i);
                }
                s.aiSeed = _seed & 0x7FFFFFFF;
            }
            s.personality = _root.生成随机人格(s.aiSeed);
            _root.计算AI参数(s.personality);
            this.data.personality = s.personality;
            _root.服务器.发布服务器消息("[AI WARNING] " + s._name
                + " personality==null, auto-generated in BaseUnitAI");
        }

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
    // 反应对AI灵敏度的影响通过 ActionExecutor.commitBody 的 commitFrames × tickInterval 实现。
    public function update():Void{
        this.stateMachine.onAction();
    }

    /**
     * destroy — 释放 AI 子系统资源
     *
     * 由 StaticDeinitializer 在单位移除时调用（target.unitAI.destroy()）。
     * 清理顺序：arbiter（事件订阅 + BulletThreatScanProcessor）→ 状态机 → 引用置空。
     * dispatcher.destroy() 由 StaticDeinitializer 独立调用，此处不重复。
     */
    public function destroy():Void {
        if (this.data != null && this.data.arbiter != null) {
            this.data.arbiter.destroy();
        }
        if (this.stateMachine != null) {
            this.stateMachine.destroy();
        }
        this.stateMachine = null;
        this.data = null;
        this.self = null;
    }

}
