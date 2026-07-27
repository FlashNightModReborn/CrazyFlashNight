/**
 * Pure paper-doll pose selection for the character-build preview.
 *
 * A selected weapon slot owns preview visibility. Without one, the pose is a
 * stable representative of the current build and never imitates combat state.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildPose = api;
        root.CharacterBuildPose = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function pose(stateLabel, attackMode) {
        return {stateLabel:stateLabel, attackMode:attackMode};
    }
    function occupied(equipment, slotKey) {
        return !!String(equipment && equipment[slotKey] || '');
    }
    function forSelectedWeapon(equipment, target) {
        if (!target || target.kind !== 'equipment') return null;
        switch (String(target.slotKey || '')) {
        case '长枪':
            return pose('长枪站立', '长枪');
        case '手枪':
        case '手枪2':
            if (occupied(equipment, '手枪') && occupied(equipment, '手枪2')) {
                return pose('双枪站立', '双枪');
            }
            return target.slotKey === '手枪2'
                ? pose('手枪2站立', '手枪2') : pose('手枪站立', '手枪');
        case '刀':
            return pose('兵器站立', '兵器');
        case '手雷':
            return pose('空手站立', '手雷');
        default:
            return null;
        }
    }
    function select(equipment, target) {
        equipment = equipment || {};
        var selected = forSelectedWeapon(equipment, target);
        if (selected) return selected;
        if (occupied(equipment, '长枪')) return pose('长枪站立', '长枪');
        if (occupied(equipment, '手枪') && occupied(equipment, '手枪2')) {
            return pose('双枪站立', '双枪');
        }
        if (occupied(equipment, '手枪2')) return pose('手枪2站立', '手枪2');
        if (occupied(equipment, '手枪')) return pose('手枪站立', '手枪');
        if (occupied(equipment, '刀')) return pose('兵器站立', '兵器');
        return pose('空手站立', '空手');
    }

    return {
        select:select
    };
});
