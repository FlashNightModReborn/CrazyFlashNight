class org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator {
    
    /**
     * 计算射击角度
     * @param Obj 子弹对象
     * @param shooter 射击者对象
     * @return 计算后的射击角度
     */
    public static function calculate(Obj:Object, shooter:Object):Number {
        // 预取局部变量
        var angleOffset:Number = (Obj.角度偏移 !== undefined) ? Obj.角度偏移 : 0;
        var bulletSpeed:Number = Obj.子弹速度;
        
        // 如果子弹速度为负，则取绝对值并一次性写回
        if (bulletSpeed < 0) {
            Obj.子弹速度 = bulletSpeed = -bulletSpeed;
        }

        // 利用异或计算最终发射方向：
        // shooter.方向=="左" 表示原始方向为左，
        // (bulletSpeed < 0) 为 true 时需要翻转。
        // 两者异或后，true 表示最终为左侧，false 表示右侧。
        // 当最终方向为左侧时，角度偏移也需要取反（同时写回以保留副作用）
        // 依据最终方向确定基础射击角度：左侧为180°，右侧为0°
        // 返回综合旋转角度：基础角度 + 射手自身旋转 + 调整后的角度偏移
        if ((shooter.方向 == "左") ^ (bulletSpeed < 0)) {
            Obj.角度偏移 = -angleOffset;
            return 180 + shooter._rotation - angleOffset;
        }

        return shooter._rotation + angleOffset;
    }
}