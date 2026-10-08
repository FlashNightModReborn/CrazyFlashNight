/* Visual routing only. Gameplay names, difficulty and unlock state stay in StageSelectData/Host. */
var StageSelectDesertData = (function() {
    'use strict';
    var frame = StageSelectData.getCatalog(StageSelectData.DEFAULT_CATALOG_ID).frames.filter(function(item) {
        return item.frameLabel === '基地房顶';
    })[0];
    var fallbackPins = {};
    (frame.stageButtons || []).forEach(function(button) {
        fallbackPins[button.id] = {
            x: button.x, y: button.y + 120, labelX: 0, labelY: -42,
            shortLabel: button.stageName === '外交-军阀' ? '军阀外交' : button.stageName,
            labelWidth: Math.max(92, Math.min(144, button.stageName.length * 15 + 20)), labelHeight: 30
        };
    });
    // These remain independent screen controls, not fabricated 3D buildings.
    var screenPins = {
        stage_34_8: { x: 704, y: 500, labelX: 0, labelY: 36, shortLabel: '虫洞外围', labelWidth: 96, labelHeight: 30 },
        stage_34_9: { x: 842, y: 500, labelX: 0, labelY: 36, shortLabel: '虫洞洞口', labelWidth: 96, labelHeight: 30 }
    };
    return {
        frameLabel: '基地房顶', name: '荒漠', scene: 'desert', releaseOnHide: true,
        presetKey: 'cf7.stage-camera.desert-region.eleven-submap-v1',
        fallback: frame.background.assetUrl,
        fallbackPins: fallbackPins,
        pins: fallbackPins,
        worldStageIds: ['stage_34_0', 'stage_34_1', 'stage_34_2', 'stage_34_3', 'stage_34_4',
            'stage_34_5', 'stage_34_6', 'stage_34_7', 'stage_34_10'],
        twoDimensionalStageIds: ['stage_34_8', 'stage_34_9'],
        screenPins: screenPins,
        navPins: {
            nav_34_0: { x: 64, y: 540 },
            nav_34_1: { x: 960, y: 500 },
            nav_34_2: { x: 960, y: 104 }
        }
    };
})();
