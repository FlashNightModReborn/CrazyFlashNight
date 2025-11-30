// LazyMiss懒闪避：低于5%总血量不闪避，高于100%时达到最大闪避
/*
_root.lazyMiss = function(Obj, damage, lazyMissValue) {
    // 检查对象的生命值是否有效
    if (!Obj.hp满血值 || !Obj.hp || Obj.hp <= 0) {
        return false;
    }

    var fullHp = Obj.hp满血值;
    var currentHp = Obj.hp;
    var successRate;

    // 如果伤害大于半血
    if (damage > fullHp / 2) {
        successRate = 100 * lazyMissValue;
    }
    // 如果当前血量小于半血
    else if (currentHp < fullHp / 2) {
        if (damage > fullHp / 5) {
            successRate = 100 * lazyMissValue;
        }
        else if (damage < fullHp * 0.025) {
            return false; // 伤害小于2.5%不闪避
        }
        else {
            // 计算动态闪避率
            successRate = 100 * lazyMissValue * damage * 5 / fullHp;
        }
    }
    // 当前血量大于或等于半血
    else {
        if (damage < fullHp * 0.05) {
            return false; // 伤害小于5%不闪避
        }
        // 计算动态闪避率
        successRate = 100 * lazyMissValue * damage * 2 / fullHp;
    }

    return _root.成功率(successRate);
}
*/