/** 升级刷新属性只能治疗活着的单位；死亡恢复只走显式 respawn。 */
class org.flashNight.arki.unit.Action.Regeneration.LevelUpRecovery {
    public static function refresh(target:Object, level:Number):Void {
        if (target == undefined) return;
        var hp:Number = Number(target.hp);
        var mp = target.mp;
        var alive:Boolean = isFinite(hp) && hp > 0;
        target.等级 = level;
        target.根据等级初始数值(level);
        target.hp = alive ? target.hp满血值 : isFinite(hp) && hp <= 0 ? hp : 0;
        target.mp = alive ? target.mp满血值 : mp;
    }
}
