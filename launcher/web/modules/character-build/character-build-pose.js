/**
 * Pure paper-doll pose selection for the character-build preview.
 *
 * A selected weapon slot owns preview visibility; otherwise the pose is a stable
 * representative of the current build and never imitates combat state.
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
    var CAMERA_ENVELOPE_POSES = [
        ['空手站立', '空手'],
        ['长枪站立', '长枪'],
        ['手枪站立', '手枪'],
        ['手枪2站立', '手枪2'],
        ['双枪站立', '双枪'],
        ['兵器站立', '兵器'],
        ['手雷站立', '手雷']
    ];
    var BODY_DRAW_FIELDS = [
        '身体', '脸型', '发型', '面具', '屁股',
        '上臂', '左下臂', '右下臂', '左手', '右手',
        '左大腿', '右大腿', '小腿', '脚'
    ];
    var WEAPON_DRAW_FIELDS = [
        '长枪_装扮', '手枪_装扮', '手枪2_装扮',
        '刀_装扮', '刀2_装扮', '刀3_装扮', '手雷_装扮'
    ];
    function pose(stateLabel, attackMode) {
        return {stateLabel:stateLabel, attackMode:attackMode};
    }
    function cameraEnvelopePoses() {
        return CAMERA_ENVELOPE_POSES.map(function(value) {
            return pose(value[0], value[1]);
        });
    }
    function cameraFitFields() { return BODY_DRAW_FIELDS.slice(0, 5).concat(BODY_DRAW_FIELDS.slice(10)); }
    function drawFields() { return BODY_DRAW_FIELDS.concat(WEAPON_DRAW_FIELDS); }
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
            return pose('手雷站立', '手雷');
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
        select:select,
        cameraEnvelopePoses:cameraEnvelopePoses,
        cameraFitFields:cameraFitFields,
        drawFields:drawFields
    };
});
