import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.DamageContext {
    public var bullet:Object;        // 原本的 子弹 对象
    public var shooter:Object;       // 发射者
    public var hitTarget:Object;     // 被击中的目标
    public var overlapRatio:Number;  // 重叠比例
    public var scatterCost:Number;   // 消耗霰弹值
    public var dodgeState:String;    // 躲闪状态
    public var damageResult:DamageResult; // 伤害结果 (输出)

    public function DamageContext(
        bullet:Object, 
        shooter:Object, 
        hitTarget:Object, 
        overlapRatio:Number, 
        scatterCost:Number, 
        dodgeState:String
    ) {
        this.bullet = bullet;
        this.shooter = shooter;
        this.hitTarget = hitTarget;
        this.overlapRatio = overlapRatio;
        this.scatterCost = scatterCost;
        this.dodgeState = dodgeState;
        
        // 与之前相同，使用 DamageResult.IMPACT 或直接 new 一个
        this.damageResult = DamageResult.IMPACT;
        this.damageResult.reset();
    }
}
