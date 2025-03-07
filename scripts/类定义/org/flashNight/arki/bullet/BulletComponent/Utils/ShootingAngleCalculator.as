class org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator {
    
    // 构造函数
    public function ShootingAngleCalculator() {
        // AS2类需要空构造函数
    }
    
    /**
     * 计算射击角度
     * @param Obj 子弹对象
     * @param shooter 射击者对象
     * @return 计算后的射击角度
     */
    public static function calculate(Obj:Object, shooter:Object):Number {
        // 初始化角度偏移
        Obj.角度偏移 = Obj.角度偏移 || 0;
        
        var 基础射击角度:Number = 0;
        var 发射方向:String = shooter.方向;
        
        // 处理子弹速度方向
        if (Obj.子弹速度 < 0) {
            Obj.子弹速度 *= -1;
            发射方向 = (发射方向 == "右") ? "左" : "右";
        }
        
        // 设置基础角度和偏移方向
        if (发射方向 == "左") {
            基础射击角度 = 180;
            Obj.角度偏移 = -Obj.角度偏移;
        }
        
        // 计算最终角度
        return 基础射击角度 + shooter._rotation + Obj.角度偏移;
    }
    
}