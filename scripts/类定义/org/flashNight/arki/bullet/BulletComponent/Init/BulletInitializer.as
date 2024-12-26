class org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer
{
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
    publish static function setDefaults(Obj:Object, shooter:Object):Void
    {
        // 相当于 _root.设置默认值(Obj, shooter);
        Obj.固伤 = (isNaN(Obj.固伤)) ? 0 : Obj.固伤;
        Obj.命中率 = (isNaN(Obj.命中率)) ? shooter.命中率 : Obj.命中率;
        Obj.最小霰弹值 = (isNaN(Obj.最小霰弹值)) ? 1 : Obj.最小霰弹值;

        // 远距离不消失的逻辑
        Obj.远距离不消失 = Obj.手雷检测 || Obj.爆炸检测;
    }

    /**
     * 继承发射者属性
     * @param Obj {Object} 子弹对象
     * @param shooter {Object} 发射者对象
     */
    publish static function inheritShooterAttributes(Obj:Object, shooter:Object):Void
    {
        // 相当于 _root.继承发射者属性(Obj, shooter);
        Obj.伤害类型 = (!Obj.伤害类型 && shooter.伤害类型) ? shooter.伤害类型 : Obj.伤害类型;
        Obj.魔法伤害属性 = (!Obj.魔法伤害属性 && shooter.魔法伤害属性) ? shooter.魔法伤害属性 : Obj.魔法伤害属性;

        // 最高吸血取较大值
        if (Obj.吸血 || shooter.吸血)
        {
            var obj吸血 = isNaN(Obj.吸血) ? 0 : Obj.吸血;
            var shooter吸血 = isNaN(shooter.吸血) ? 0 : shooter.吸血;
            Obj.吸血 = Math.max(obj吸血, shooter吸血);
        }

        // 击溃
        if (Obj.血量上限击溃 || shooter.击溃)
        {
            var obj击溃 = isNaN(Obj.血量上限击溃) ? 0 : Obj.血量上限击溃;
            var shooter击溃 = isNaN(shooter.击溃) ? 0 : shooter.击溃;
            Obj.击溃 = Math.max(obj击溃, shooter击溃);
        }
    }

    /**
     * 计算击退速度
     * @param Obj {Object} 子弹对象
     */
    publish static function calculateKnockback(Obj:Object):Void
    {
        // 相当于 _root.计算击退速度(Obj);
        // 假设 _root.最大水平击退速度、_root.最大垂直击退速度 是在全局可访问的地方
        var maxHor:Number = _root.最大水平击退速度; // 需在外部定义
        var maxVer:Number = _root.最大垂直击退速度; // 需在外部定义

        if (isNaN(Obj.水平击退速度) || Obj.水平击退速度 < 0) {
            Obj.水平击退速度 = 10;
        } else {
            Obj.水平击退速度 = Math.min(Obj.水平击退速度, maxHor);
        }

        Obj.垂直击退速度 = isNaN(Obj.垂直击退速度) ? 0 : Obj.垂直击退速度;
        Obj.垂直击退速度 = Math.min(Obj.垂直击退速度, maxVer);
    }

    /**
     * 初始化子弹属性
     * @param Obj {Object} 子弹对象
     */
    publish static function initializeBulletProperties(Obj:Object):Void
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
     * 初始化子弹属性
     * @param Obj {Object} 子弹对象
     */
    publish static function initializeBulletProperties(Obj:Object):Void
    {
        // 相当于 _root.初始化子弹属性(Obj);
        Obj.发射者名 = Obj.发射者;
        Obj.子弹敌我属性值 = Obj.子弹敌我属性;
        Obj._x = Obj.shootX;
        Obj._y = Obj.shootY;
        Obj.Z轴坐标 = Obj.shootZ;
        Obj.子弹区域area = Obj.区域定位area;
    }
}
