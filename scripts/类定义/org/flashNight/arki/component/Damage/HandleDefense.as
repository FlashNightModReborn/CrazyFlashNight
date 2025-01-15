import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.HandleDefense extends BaseDamageHandle implements IDamageHandle {
    
    public function HandleDefense() {
        super();
    }

    public override function execute(context:DamageContext):Void {
        var bullet:Object = context.bullet;
        var target:Object = context.hitTarget;
        var shooter:Object = context.shooter;
        var result:DamageResult = context.damageResult;

        // 1) 基础防御处理
        target.防御力 = isNaN(target.防御力) ? 1 : Math.min(target.防御力, 99000);
        
        // 2) 计算破坏力
        bullet.破坏力 = Number(bullet.子弹威力) + (isNaN(shooter.伤害加成) ? 0 : shooter.伤害加成);

        var damageVariance:Number = bullet.破坏力 * ((!_root.调试模式 || bullet.霰弹值 > 1) ? (0.85 + _root.basic_random() * 0.3) : 1);
        var percentageDamage:Number = isNaN(bullet.百分比伤害) ? 0 : target.hp * bullet.百分比伤害 / 100;
        bullet.破坏力 = damageVariance + bullet.固伤 + percentageDamage;
        
        // 3) 暴击
        if (bullet.暴击) {
            bullet.破坏力 = bullet.破坏力 * bullet.暴击(bullet);
        }

        // 4) 设定默认颜色
        var defaultDamageColor:String = bullet.子弹敌我属性值 ? "#FFCC00" : "#FF0000";
        result.setDamageColor(defaultDamageColor);

        // 5) 按伤害类型处理
        if (bullet.伤害类型 === "真伤") {
            var trueDamageColor:String = bullet.子弹敌我属性值 ? "#4A0099" : "#660033";
            result.setDamageColor(trueDamageColor);
            result.addDamageEffect('<font color="' + trueDamageColor + '" size="20"> 真</font>');
            target.损伤值 = bullet.破坏力;
        } else if (bullet.伤害类型 === "魔法") {
            var magicDamageColor:String = bullet.子弹敌我属性值 ? "#0099FF" : "#AC99FF";
            result.setDamageColor(magicDamageColor);
            var magicDamageAttr:String = bullet.魔法伤害属性 ? bullet.魔法伤害属性 : "能";
            result.addDamageEffect('<font color="' + magicDamageColor + '" size="20"> ' + magicDamageAttr + '</font>');

            var enemyMagicResist:Number = bullet.魔法伤害属性 
                ? (target.魔法抗性 && (target.魔法抗性[bullet.魔法伤害属性] 
                        || target.魔法抗性[bullet.魔法伤害属性] === 0) 
                    ? target.魔法抗性[bullet.魔法伤害属性]
                    : (target.魔法抗性 && (target.魔法抗性["基础"] || target.魔法抗性["基础"] === 0) 
                        ? target.魔法抗性["基础"]
                        : 10 + target.等级 / 2))
                : (target.魔法抗性 && (target.魔法抗性["基础"] || target.魔法抗性["基础"] === 0) 
                    ? target.魔法抗性["基础"]
                    : 10 + target.等级 / 2);

            enemyMagicResist = isNaN(enemyMagicResist) ? 20 : Math.min(Math.max(enemyMagicResist, -1000), 100);
            target.损伤值 = Math.floor(bullet.破坏力 * (100 - enemyMagicResist) / 100);
        } else {
            // 物理伤害
            target.损伤值 = bullet.破坏力 * _root.防御减伤比(target.防御力);
        }
    }
}
