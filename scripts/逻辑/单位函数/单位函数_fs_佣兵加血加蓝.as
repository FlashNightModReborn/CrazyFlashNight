// ==================== 配置常量 ====================
_root.HealingConfig = {
    // 治疗效果配置
    EFFECTS: {
        POTION: "药剂动画-2",
        CRIMSON_BOOST: "猩红增幅"
    },
    
    // 治疗比例配置
    HEAL_RATIOS: {
        VOCALIST_BASE: 0.03,        // 主唱基础治疗比例
        VOCALIST_BASE_2: 0.03,      // 主唱集体加血2的治疗比例
        KEYBOARD_BASE: 0.05,        // 键盘基础治疗比例
        BLOODPACK_ALLY_BONUS: 2     // 血包对友军的加成倍数
    }
};

// ==================== 核心治疗模块 ====================
_root.HealingCore = {
    
    /**
     * 验证目标是否可以被治疗
     * @param target 目标对象
     * @param isAllyOnly 是否只能治疗友军
     * @return Boolean 是否可以治疗
     */
    canHeal: function(target, isAllyOnly) {
        if (!target || target.hp == undefined) return false;
        if (isNaN(target.hp) || target.hp <= 0) return false;
        if (target.hp >= target.hp满血值) return false;
        if (isAllyOnly && target.是否为敌人 !== false) return false;
        return true;
    },
    
    /**
     * 验证目标是否可以回蓝
     * @param target 目标对象
     * @param isAllyOnly 是否只能对友军回蓝
     * @return Boolean 是否可以回蓝
     */
    canRestoreMana: function(target, isAllyOnly) {
        if (!target || target.mp == undefined) return false;
        if (isNaN(target.mp) || target.mp <= 0) return false;
        if (target.mp >= target.mp满血值) return false;
        if (isAllyOnly && target.是否为敌人 !== false) return false;
        return true;
    },
    
    /**
     * 应用治疗效果
     * @param target 目标对象
     * @param healAmount 治疗量
     * @param effectName 效果名称
     */
    applyHeal: function(target, healAmount, effectName) {
        if (isNaN(healAmount) || healAmount <= 0) return false;
        
        var newHp = target.hp + healAmount;
        target.hp = Math.min(newHp, target.hp满血值);
        
        if (effectName) {
            _root.效果(effectName, target._x, target._y, 100, true);
        }
        return true;
    },
    
    /**
     * 应用回蓝效果
     * @param target 目标对象
     * @param manaAmount 回蓝量
     * @param effectName 效果名称
     */
    applyManaRestore: function(target, manaAmount, effectName) {
        if (isNaN(manaAmount) || manaAmount <= 0) return false;
        
        var newMp = target.mp + manaAmount;
        target.mp = Math.min(newMp, target.mp满血值);
        
        if (effectName) {
            _root.效果(effectName, target._x, target._y, 100, true);
        }
        return true;
    },
    
    /**
     * 检查目标是否在范围内
     * @param caster 施法者
     * @param target 目标
     * @param rangeX X轴范围
     * @param rangeY Y轴范围
     * @return Boolean 是否在范围内
     */
    isInRange: function(caster, target, rangeX, rangeY) {
        if (!caster || !target) return false;
        var deltaX = Math.abs(target._x - caster._x);
        var deltaY = Math.abs(target._y - caster._y);
        return deltaX < rangeX && deltaY < rangeY;
    },
    
    /**
     * 获取所有符合条件的目标
     * @param caster 施法者（可选，用于范围判断）
     * @param sameFaction 是否同阵营
     * @param rangeX X轴范围（可选）
     * @param rangeY Y轴范围（可选）
     * @return Array 目标数组
     */
    getTargets: function(caster, sameFaction, rangeX, rangeY) {
        var targets = [];
        
        for (var key in _root.gameworld) {
            var target = _root.gameworld[key];
            if (!target) continue;
            
            // 检查阵营
            if (sameFaction && caster && target.是否为敌人 !== caster.是否为敌人) continue;
            
            // 检查范围
            if (rangeX !== undefined && rangeY !== undefined && caster) {
                if (!this.isInRange(caster, target, rangeX, rangeY)) continue;
            }
            
            targets.push(target);
        }
        
        return targets;
    }
};

// ==================== 全局治疗功能 ====================
_root.GlobalHealing = {
    
    /**
     * 佣兵集体加血
     * @param healAmount 治疗量
     */
    mercenaryGroupHeal: function(healAmount) {
        if (isNaN(healAmount) || healAmount <= 0) return;
        
        var targets = _root.HealingCore.getTargets(null, false);
        var healedCount = 0;
        
        for (var i = 0; i < targets.length; i++) {
            var target = targets[i];
            if (_root.HealingCore.canHeal(target, true)) {
                _root.HealingCore.applyHeal(target, healAmount, _root.HealingConfig.EFFECTS.POTION);
                healedCount++;
            }
        }
        
        return healedCount;
    },
    
    /**
     * 佣兵集体回蓝
     * @param manaAmount 回蓝量
     */
    mercenaryGroupManaRestore: function(manaAmount) {
        if (isNaN(manaAmount) || manaAmount <= 0) return;
        
        var targets = _root.HealingCore.getTargets(null, false);
        var restoredCount = 0;
        
        for (var i = 0; i < targets.length; i++) {
            var target = targets[i];
            if (_root.HealingCore.canRestoreMana(target, true)) {
                _root.HealingCore.applyManaRestore(target, manaAmount, _root.HealingConfig.EFFECTS.POTION);
                restoredCount++;
            }
        }
        
        return restoredCount;
    },
    
    /**
     * 佣兵使用血包
     * @param targetKey 目标key
     */
    mercenaryUseBloodPack: function(targetKey) {
        var target = _root.gameworld[targetKey];
        if (!target || !_root.HealingCore.canHeal(target, false)) return false;
        
        var baseHealAmount = target.hp满血值 * target.血包恢复比例 / 100;
        
        // 对友军双倍效果
        if (target.是否为敌人 === false) {
            baseHealAmount *= _root.HealingConfig.HEAL_RATIOS.BLOODPACK_ALLY_BONUS;
        }
        
        return _root.HealingCore.applyHeal(target, baseHealAmount, _root.HealingConfig.EFFECTS.POTION);
    }
};

// ==================== 范围治疗动作 ====================
_root.RangeHealing = {
    
    /**
     * 范围治疗基础函数
     * @param caster 施法者
     * @param rangeX X轴范围
     * @param rangeY Y轴范围
     * @param healAmount 治疗量
     * @param healType 治疗类型 ("fixed", "percentage", "max_percentage")
     * @param effectName 效果名称
     */
    rangeHeal: function(caster, rangeX, rangeY, healAmount, healType, effectName) {
        if (!caster) return 0;
        
        var targets = _root.HealingCore.getTargets(caster, true, rangeX, rangeY);
        var healedCount = 0;
        
        for (var i = 0; i < targets.length; i++) {
            var target = targets[i];
            if (!_root.HealingCore.canHeal(target, false)) continue;
            
            var actualHealAmount = 0;
            
            switch (healType) {
                case "fixed":
                    actualHealAmount = healAmount;
                    break;
                case "percentage":
                    actualHealAmount = target.hp * healAmount;
                    break;
                case "max_percentage":
                    actualHealAmount = target.hp满血值 * healAmount;
                    break;
                default:
                    actualHealAmount = healAmount;
            }
            
            if (_root.HealingCore.applyHeal(target, actualHealAmount, effectName)) {
                healedCount++;
            }
        }
        
        return healedCount;
    },
    
    /**
     * 将军集体加血
     */
    generalGroupHeal: function(rangeX, rangeY, healAmount) {
        return this.rangeHeal(
            _parent, 
            rangeX, 
            rangeY, 
            healAmount, 
            "fixed", 
            _root.HealingConfig.EFFECTS.POTION
        );
    },
    
    /**
     * 主唱百分比集体加血
     */
    vocalistPercentageHeal: function(rangeX, rangeY, percentage) {
        return this.rangeHeal(
            _parent, 
            rangeX, 
            rangeY, 
            percentage, 
            "percentage", 
            _root.HealingConfig.EFFECTS.CRIMSON_BOOST
        );
    },
    
    /**
     * 主唱集体加血（固定3%最大血量）
     */
    vocalistFixedHeal: function(rangeX, rangeY) {
        return this.rangeHeal(
            _parent, 
            rangeX, 
            rangeY, 
            _root.HealingConfig.HEAL_RATIOS.VOCALIST_BASE, 
            "max_percentage", 
            _root.HealingConfig.EFFECTS.CRIMSON_BOOST
        );
    },
    
    /**
     * 主唱集体加血2（可配置独立倍率）
     */
    vocalistFixedHeal2: function(rangeX, rangeY) {
        return this.rangeHeal(
            _parent, 
            rangeX, 
            rangeY, 
            _root.HealingConfig.HEAL_RATIOS.VOCALIST_BASE_2, 
            "max_percentage", 
            _root.HealingConfig.EFFECTS.CRIMSON_BOOST
        );
    },
    
    /**
     * 键盘集体加血（固定5%最大血量）
     */
    keyboardGroupHeal: function(rangeX, rangeY) {
        return this.rangeHeal(
            _parent, 
            rangeX, 
            rangeY, 
            _root.HealingConfig.HEAL_RATIOS.KEYBOARD_BASE, 
            "max_percentage", 
            _root.HealingConfig.EFFECTS.CRIMSON_BOOST
        );
    }
};

// ==================== 向后兼容的接口 ====================
// 保持原有的函数接口，但内部调用新的模块化代码

_root.佣兵集体加血 = function(加血值) {
    return _root.GlobalHealing.mercenaryGroupHeal(加血值);
};

_root.佣兵集体回蓝 = function(回蓝值) {
    return _root.GlobalHealing.mercenaryGroupManaRestore(回蓝值);
};

_root.佣兵使用血包 = function(目标) {
    return _root.GlobalHealing.mercenaryUseBloodPack(目标);
};

// 重新定义加血动作对象
_root.加血动作 = {
    将军集体加血: function(加血距离X, 加血距离Y, 加血值) {
        return _root.RangeHealing.generalGroupHeal(加血距离X, 加血距离Y, 加血值);
    },
    
    主唱百分比集体加血: function(加血距离X, 加血距离Y, 加血值) {
        return _root.RangeHealing.vocalistPercentageHeal(加血距离X, 加血距离Y, 加血值);
    },
    
    主唱集体加血: function(加血距离X, 加血距离Y, 加血值) {
        // 使用配置的固定倍率，忽略传入的加血值参数（保持原有逻辑）
        return _root.RangeHealing.vocalistFixedHeal(加血距离X, 加血距离Y);
    },
    
    主唱集体加血2: function(加血距离X, 加血距离Y, 加血值) {
        // 使用独立的配置倍率，忽略传入的加血值参数（保持原有逻辑）
        return _root.RangeHealing.vocalistFixedHeal2(加血距离X, 加血距离Y);
    },
    
    键盘集体加血: function(加血距离X, 加血距离Y, 加血值) {
        // 使用配置的固定倍率，忽略传入的加血值参数（保持原有逻辑）
        return _root.RangeHealing.keyboardGroupHeal(加血距离X, 加血距离Y);
    }
};