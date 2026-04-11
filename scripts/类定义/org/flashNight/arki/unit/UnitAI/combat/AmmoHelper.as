/**
 * AmmoHelper — 弹药比共享计算
 *
 * 从 WeaponEvaluator.getAmmoRatio 提取的核心逻辑。
 * UnitAIData.updateSelf() 和 WeaponEvaluator 共同调用，
 * 消除双实现漂移风险。
 */
class org.flashNight.arki.unit.UnitAI.combat.AmmoHelper {

    /**
     * computeRatio — 计算指定武器模式的弹药比
     *
     * @param self  单位 MovieClip
     * @param mode  武器模式字符串
     * @return      弹药比 [0,1]，1=满弹，0=空弹
     */
    public static function computeRatio(self:MovieClip, mode:String):Number {
        switch (mode) {
            case "长枪":
                if (self.长枪弹匣容量 > 0) return 1 - self.长枪.value.shot / self.长枪弹匣容量;
                break;
            case "手枪":
                if (self.手枪弹匣容量 > 0) return 1 - self.手枪.value.shot / self.手枪弹匣容量;
                break;
            case "手枪2":
                if (self.手枪2弹匣容量 > 0) return 1 - self.手枪2.value.shot / self.手枪2弹匣容量;
                break;
            case "双枪":
                var r1:Number = (self.手枪弹匣容量 > 0) ? (1 - self.手枪.value.shot / self.手枪弹匣容量) : 1;
                var r2:Number = (self.手枪2弹匣容量 > 0) ? (1 - self.手枪2.value.shot / self.手枪2弹匣容量) : 1;
                return (r1 < r2) ? r1 : r2;
        }
        return 1.0;
    }
}
