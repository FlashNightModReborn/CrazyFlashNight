class org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer
{
    private static var maxHor:Number = 33;
    private static var maxVer:Number = 15;
    
    // 构造函数（私有或空实现，避免被实例化）
    private function BulletInitializer()
    {
        // 不需要实例化
    }

    /**
     * 设置默认值
     * @param Obj {Object} 子弹对象
     * @param shooter {Object} 发射者对象
     */
    public static function setDefaults(Obj:Object, shooter:Object):Void
    {
        // 相当于 _root.设置默认值(Obj, shooter);
        Obj.固伤 = Obj.固伤 | 0;
        Obj.命中率 = (isNaN(Obj.命中率)) ? shooter.命中率 : Obj.命中率;
        Obj.最小霰弹值 = (isNaN(Obj.最小霰弹值)) ? 1 : Obj.最小霰弹值;

        // 远距离不消失的逻辑
        Obj.远距离不消失 = Obj.手雷检测 || Obj.爆炸检测;
        
        Obj.shooter = shooter;
        Obj.zAttackRangeSq = Obj.Z轴攻击范围 * Obj.Z轴攻击范围;
    }

    /**
     * 继承发射者属性
     * @param Obj {Object} 子弹对象
     * @param shooter {Object} 发射者对象
     */
    public static function inheritShooterAttributes(Obj:Object, shooter:Object):Void
    {
        // 局部化变量优化属性访问
        var objDmgType:Object = Obj.伤害类型;
        var shooterDmgType:Object = shooter.伤害类型;
        Obj.伤害类型 = (!objDmgType && shooterDmgType) ? shooterDmgType : objDmgType;

        var objMagicDmg:Object = Obj.魔法伤害属性;
        var shooterMagicDmg:Object = shooter.魔法伤害属性;
        Obj.魔法伤害属性 = (!objMagicDmg && shooterMagicDmg) ? shooterMagicDmg : objMagicDmg;

        // 最高吸血取较大值
        if (Obj.吸血 || shooter.吸血)
        {
            Obj.吸血 = Math.max(Obj.吸血 | 0, shooter.吸血 | 0);
        }

        // 击溃
        if (Obj.血量上限击溃 || shooter.击溃)
        {
            Obj.击溃 = Math.max(Obj.血量上限击溃 | 0, shooter.击溃 | 0);
        }
    }

    /**
     * 计算击退速度
     * @param Obj {Object} 子弹对象
     */
    public static function calculateKnockback(Obj:Object):Void
    {
        if (!(Obj.水平击退速度 >= 0)) {
            Obj.水平击退速度 = 10;
        } else {
            Obj.水平击退速度 = Math.min(Obj.水平击退速度, BulletInitializer.maxHor);
        }

        Obj.垂直击退速度 = Obj.垂直击退速度 | 0;
        Obj.垂直击退速度 = Math.min(Obj.垂直击退速度, BulletInitializer.maxVer);
    }

    /**
     * 初始化子弹属性
     * @param Obj {Object} 子弹对象
     */
    public static function initializeBulletProperties(Obj:Object):Void
    {
        // 相当于 _root.初始化子弹属性(Obj);
        Obj.发射者名 = Obj.发射者;
        Obj.子弹敌我属性值 = Obj.子弹敌我属性;
        Obj._x = Obj.shootX;
        Obj._y = Obj.shootY;
        Obj.Z轴坐标 = Obj.shootZ;
        Obj.子弹区域area = Obj.区域定位area;
    }

    /**
     * 初始化子弹毒属性
     * @param Obj {Object} 子弹对象
     */
    public static function initializeNanoToxicfunction(Obj:Object, bullet:Object, shooter:Object):Void
    {
        if(Obj.毒 || shooter.淬毒 || shooter.毒) {
            var shooterToxic:Number = shooter.淬毒 | 0;
            Obj.毒 = Math.max(Obj.毒 | 0, shooter.毒 | 0);
            if(shooterToxic && shooterToxic > Obj.毒) {
                bullet.nanoToxic = shooterToxic;
                bullet.nanoToxicDecay = 1;
                if(!bullet.近战检测 && shooter.淬毒 > 10) {
                    shooter.淬毒 -= 1;
                }
            } else {
                bullet.nanoToxic = Obj.毒;
            }
        }
    }
}
