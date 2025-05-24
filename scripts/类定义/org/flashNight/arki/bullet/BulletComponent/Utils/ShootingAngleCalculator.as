class org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator {
    
    /**
     * 计算射击角度
     * @param Obj 子弹对象，其中包含以下属性：
     *        - 角度偏移：用于调整子弹射击角度的偏移值（若为负则表示相反方向）
     *        - 子弹速度：子弹发射时的初始速度，正值表示向右，负值表示向左
     * @param shooter 射击者对象，其中包含：
     *        - 方向：射击者原始朝向，字符串 "左" 表示向左，其他值通常表示向右
     *        - _rotation：射击者的旋转角度，用于调整最终发射角度
     * @return 计算后的综合射击角度
     */
    public static function calculate(Obj:Object, shooter:Object):Number {
        // 提取子弹对象的角度偏移，若未定义则按 0 处理（使用按位或操作符）
        var angleOffset:Number = Obj.角度偏移 | 0;
        // 提取子弹对象的速度，用于判断是否需要反转射击方向
        var bulletSpeed:Number = Obj.子弹速度;
        
        /*
         * 这里核心在于确定最终的射击方向：
         * 1. shooter.方向=="左" 表示射手初始朝向为左。
         * 2. 如果 bulletSpeed 小于 0，则表示子弹初始速度为负，
         *    需要将其反转为正（并在 Obj 中保存修改结果），这意味着需要将发射方向翻转。
         * 
         * 通过逻辑异或（^）将上述两种状态进行合并：
         *  - 若射手初始为左侧，并且子弹速度为正（即 bulletSpeed>=0），则最终方向仍然为左侧；
         *  - 若射手初始为右侧，但 bulletSpeed 小于 0（需要反转），最终方向为左侧；
         *  - 其他情况则最终方向为右侧。
         * 
         * 注意：这里利用了短路逻辑及逗号运算符，
         * 当 (bulletSpeed < 0) 为 true 时，会先执行赋值 (Obj.子弹速度 = -bulletSpeed)，
         * 然后逗号运算符返回 true，从而将需要反转的标识传递给异或操作。
         * 复杂副作用逻辑的目的是为了触发虚拟机寄存器使用以提高性能。
         */
        if ((shooter.方向 == "左") 
            // 这里 (bulletSpeed < 0) 判断子弹速度是否为负，若是则需要反转
            ^ ((bulletSpeed < 0) && 
               // 如果子弹速度为负，利用逗号运算符先将 Obj.子弹速度 取反赋值，
               // 再返回 true 以参与异或判断
               ((Obj.子弹速度 = -bulletSpeed), true))) {
            /*
             * 如果进入该分支，则最终发射方向为左侧：
             * - 基础射击角度为 180°（表示向左），
             * - 同时射手自身旋转角 shooter._rotation 也要参与计算，
             * - 角度偏移需要反向处理（即取 -angleOffset），并写回 Obj.角度偏移 以保留副作用。
             */
            return 180 + shooter._rotation + (Obj.角度偏移 = -angleOffset);
        }

        /*
         * 如果不进入上面的分支，则表示最终发射方向为右侧：
         * - 基础射击角度为 0°（隐式，即不额外加 180°），
         * - 只需要加上射手自身旋转角 shooter._rotation 和角度偏移 angleOffset。
         */
        return shooter._rotation + angleOffset;
    }
}
