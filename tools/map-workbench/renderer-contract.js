'use strict';
// Test-only comparison with the production Web renderer, never a disk publisher.
const fs=require('fs'),path=require('path'),vm=require('vm');
function loadMapData(definition,root=path.resolve(__dirname,'../..')) {
    const sandbox={console,MapDefinitionData:definition};vm.createContext(sandbox);
    vm.runInContext(fs.readFileSync(path.join(root,'launcher/web/modules/map-avatar-source-data.js'),'utf8'),sandbox);
    vm.runInContext(fs.readFileSync(path.join(root,'launcher/web/modules/map-panel-data.js'),'utf8'),sandbox);
    return sandbox.MapPanelData;
}
function buildHotspotEntry(D, hotspotId) {
    const meta = D.resolveHotspotMeta(hotspotId);
    if (!meta) return null;
    const outline = D.getHudOutline(meta.pageId, meta.hotspotId);
    if (!outline) return null;

    const group = D.getHotspotUnlockGroup(meta.pageId, meta.hotspotId) || '';

    return {
        meta: {
            pageId: meta.pageId,
            pageLabel: meta.pageLabel || '',
            hotspotId: meta.hotspotId,
            label: meta.label || '',
            sceneName: meta.sceneName || '',
            group: group
        },
        outline: {
            focusFilterId: outline.focusFilterId || '',
            focusFilterLabel: outline.focusFilterLabel || '',
            viewportRect: outline.viewportRect || null,
            currentRect: outline.currentRect || null,
            blocks: (outline.blocks || []).map(function (b) {
                return {
                    hotspotId: b.hotspotId,
                    label: b.label || '',
                    sourceRect: b.sourceRect || null
                };
            }),
            visuals: (outline.visuals || []).map(function (v) {
                return {
                    id: v.id,
                    label: v.label || '',
                    assetUrl: v.assetUrl || '',
                    hotspotIds: v.hotspotIds || [],
                    sourceRect: v.sourceRect || null,
                    isCurrent: !!v.isCurrent
                };
            })
        }
    };
}
module.exports={loadMapData,buildHotspotEntry};
