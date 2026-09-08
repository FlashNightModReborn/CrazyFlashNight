/** 角色构筑、建角与整形共用的完整人物预览；取景只由人物主体决定。 */
(function(root) {
    'use strict';
    var CAMERA_ENVELOPE_POSES = [
        ['空手站立', '空手'], ['长枪站立', '长枪'], ['手枪站立', '手枪'],
        ['手枪2站立', '手枪2'], ['双枪站立', '双枪'], ['兵器站立', '兵器'], ['手雷站立', '手雷']
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
    // 手臂、武器与光效照常绘制，但不能把人物主体挤小或挪出中心。
    var CAMERA_FIT_FIELDS = BODY_DRAW_FIELDS.slice(0, 5).concat(BODY_DRAW_FIELDS.slice(10));
    function cameraEnvelopePoses() {
        return CAMERA_ENVELOPE_POSES.map(function(value) {
            return {stateLabel:value[0], attackMode:value[1]};
        });
    }
    function buildStateFromEquipment(manifest, options) {
        options = options || {};
        var state = root.DressupDollRenderer.buildStateFromEquipment(manifest, options);
        var equipment = options.equipment || {};
        var head = manifest.items[equipment['头部装备'] || equipment.head];
        // 与 AS2 的 helmet 标记一致：仅隐藏预览中的发型，不能改写保留的原发型。
        state.hairHidden = !!(head && head.helmet === true);
        if (state.hairHidden) state.keyMap['发型'] = '';
        return state;
    }
    function create(canvas, options) {
        options = options || {};
        var missingItems = [];
        var hairHidden = false;
        var renderer = root.DressupDollRenderer.create(canvas, Object.assign({maxScale:12}, options, {
            onRender:function(meta) {
                meta.missingItems = missingItems.slice();
                meta.hairHidden = hairHidden;
                if (options.onRender) options.onRender(meta);
            }
        }));
        var render = renderer.render;
        renderer.render = function(state) {
            hairHidden = !!(state && state.hairHidden);
            function visible(field) { return !hairHidden || field !== '发型'; }
            // 每次按当前性别和装扮重新测量七种站姿；切姿势共用取景，换装不沿用旧包围盒。
            var framed = Object.assign({}, state, {
                rig:'battle', fitFields:CAMERA_FIT_FIELDS.filter(visible),
                drawFields:BODY_DRAW_FIELDS.concat(WEAPON_DRAW_FIELDS).filter(visible), strictFields:true
            });
            return render(root.DressupDollRenderer.withFitEnvelope(
                renderer, framed, cameraEnvelopePoses(), 0.06));
        };
        renderer.renderProfile = function(profile, equipment, appearance, view) {
            var manifest = renderer.getManifest();
            missingItems = Object.keys(equipment || {}).filter(function(key) {
                return equipment[key] && !manifest.items[equipment[key]];
            });
            var state = buildStateFromEquipment(manifest, Object.assign({
                gender:profile.gender === 'female' ? '女' : '男', equipment:equipment,
                appearance:appearance, rig:'battle', stateLabel:'空手站立', margin:18, zoom:0.96
            }, view || {}));
            return renderer.render(state);
        };
        return renderer;
    }
    root.CharacterAppearancePreview = {create:create, buildStateFromEquipment:buildStateFromEquipment,
        cameraEnvelopePoses:cameraEnvelopePoses};
})(typeof window !== 'undefined' ? window : globalThis);
