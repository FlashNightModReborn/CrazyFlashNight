
import org.flashNight.arki.component.Damage.*;


class org.flashNight.arki.component.Damage.MultiShotDamageHandle extends BaseDamageHandle implements IDamageHandle {
    public static var instance:MultiShotDamageHandle = new MultiShotDamageHandle();

    public function MultiShotDamageHandle() {
        super();
    }

    // 判断是否有联弹检测并且不穿刺
    public function canHandle(bullet:Object):Boolean {
        return (bullet.联弹检测 && !bullet.穿刺检测);
    }

    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var overlapRatio:Number = manager.overlapRatio;
        
        // 计算 A = bullet.最小霰弹值 + overlapRatio * (bullet.霰弹值 - bullet.最小霰弹值 + 1) * 1.2
        var A:Number = bullet.最小霰弹值 + overlapRatio * (bullet.霰弹值 - bullet.最小霰弹值 + 1) * 1.2;
        
        // 计算 B = target.hp / (target.损伤值 > 0 ? target.损伤值 : 1)
        var thp:Number = target.hp;
        var B:Number = target.损伤值 > 0 ? thp / target.损伤值 : thp;
        
        // 计算 min(A, B)
        var C:Number = A < B ? A : B;

        // 计算 ceil(C)
        // 使用位运算实现向下取整
        var floorC:Number = C >> 0;
        var ceilC:Number;
        if (C > floorC) {
            ceilC = floorC + 1;
        } else {
            ceilC = floorC;
        }
        
        // 计算 min(bullet.霰弹值, ceilC)
        var actualScatterUsed:Number;
        if (bullet.霰弹值 < ceilC) {
            actualScatterUsed = bullet.霰弹值;
        } else {
            actualScatterUsed = ceilC;
        }
        
        // 设置 DamageResult
        result.actualScatterUsed = actualScatterUsed;
        
        // 更新 bullet 和 target
        bullet.霰弹值 -= actualScatterUsed;
        result.finalScatterValue = bullet.霰弹值;
        
        // 乘以实际消耗霰弹值
        target.损伤值 *= actualScatterUsed;
    }


    public function toString():String
    {
        return "MultiShotDamageHandle";
    }
}
