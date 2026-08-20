#!/usr/bin/env node
"use strict";

var assert = require("assert");
var fs = require("fs");
var path = require("path");
var vm = require("vm");
var Core = require("../launcher/web/modules/minigames/blackmarket/core/index.js");
var Preview = require("../launcher/web/modules/minigames/blackmarket/visual/equipment-preview.js");
var InspectionFocus = require("../launcher/web/modules/minigames/blackmarket/visual/inspection-focus.js");
var catalog = require("../launcher/web/data/black-market-shadow-catalog.v1.json");
var manifest = require("../launcher/web/assets/dressup/manifest.json");

function loadEquipmentInspector() {
    var source = fs.readFileSync(path.resolve(__dirname,
        "../launcher/web/modules/equipment-inspector.js"), "utf8");
    var context = {
        DressupDollRenderer: {
            buildStateFromEquipment: function(unusedManifest, options) {
                return Object.assign({}, options);
            }
        }
    };
    context.globalThis = context;
    vm.runInNewContext(source, context, { filename: "equipment-inspector.js" });
    return context.EquipmentInspector;
}

async function main() {
    var target = catalog.entries.filter(function(entry) {
        return entry.displayName === "黄金骑士牙狼胸甲";
    })[0];
    assert(target, "牙狼胸甲 catalog entry missing");

    var session = Core.createShadowSession(catalog, { seed: "equipment-preview-test" });
    var focused = session.lab.focusItem(target.id);
    var source = session.visual.resolveOfferSource(focused.focus.offerId);
    assert.strictEqual(source.kind, "dressup-paperdoll");
    assert.strictEqual(source.slot, "body");
    assert.strictEqual(Core.publicSnapshotContainsIdentity(focused.snapshot, catalog), false);

    var calls = [];
    var portraitApi = {
        loadManifest: function() { return Promise.resolve(manifest); },
        renderStateDataUrl: function(state, options) {
            calls.push({ state: state, options: options });
            return Promise.resolve("data:image/png;base64,AAAA");
        }
    };
    var equipmentInspectorApi = loadEquipmentInspector();
    var renderer = Preview.create({
        portraitApi: portraitApi,
        equipmentInspectorApi: equipmentInspectorApi,
        size: 320,
        cacheLimit: 4
    });
    var pair = await Promise.all([
        renderer.resolve(source, { gender: "女" }),
        renderer.resolve(source, { gender: "女" })
    ]);
    assert.strictEqual(calls.length, 1, "same paper-doll source did not deduplicate");
    assert.strictEqual(pair[0].sourceKind, "dressup-paperdoll");
    assert.strictEqual(pair[0].sourceComposition, "equipment-inspector-focus");
    assert.strictEqual(pair[0].autoRotate, false);
    assert.strictEqual(pair[0].previewGender, "女");
    assert.strictEqual(calls[0].state.equipment.preview, target.name);
    var chestFields = Object.keys(manifest.items[target.name].fieldsByGender["女"]);
    assert.deepStrictEqual(Array.from(calls[0].state.fitFields), chestFields);
    assert.deepStrictEqual(Array.from(calls[0].state.drawFields), chestFields);
    ["脸型", "屁股", "左大腿", "右大腿", "小腿", "脚"].forEach(function(field) {
        assert(!calls[0].state.drawFields.includes(field),
            "chest focus leaked unrelated full-body field " + field);
    });
    assert.strictEqual(calls[0].state.rig, "battle");
    assert.strictEqual(calls[0].state.stateLabel, "空手站立");

    var handTarget = catalog.entries.filter(function(entry) {
        return entry.displayName === "毒液蜘蛛侠战衣手套";
    })[0];
    assert(handTarget, "representative hand armor missing");
    var handFocused = session.lab.focusItem(handTarget.id);
    var handSource = session.visual.resolveOfferSource(handFocused.focus.offerId);
    await renderer.resolve(handSource, { gender: "男" });
    assert.strictEqual(calls.length, 2, "hand focus did not render exactly once");
    assert(calls[1].state.drawFields.length > 0, "hand focus has no draw fields");
    ["身体", "上臂", "屁股", "左大腿", "右大腿", "小腿", "脚", "脸型"].forEach(function(field) {
        assert(!calls[1].state.drawFields.includes(field),
            "hand focus leaked unrelated full-body field " + field);
    });

    var femaleOnly = catalog.entries.filter(function(entry) {
        return entry.name === "战术JK上衣";
    })[0];
    var maleOnly = catalog.entries.filter(function(entry) {
        return entry.name === "电脑佣兵上装";
    })[0];
    assert(femaleOnly && maleOnly, "gender-specific armor fixtures missing");
    var femaleFocused = session.lab.focusItem(femaleOnly.id);
    var femaleSource = session.visual.resolveOfferSource(femaleFocused.focus.offerId);
    var sharedGender = await renderer.resolvePairGender([source, femaleSource], { gender: "男" });
    assert.strictEqual(sharedGender, "女",
        "pair did not select the common authored equipment-focus gender");
    var maleFocused = session.lab.focusItem(maleOnly.id);
    var maleSource = session.visual.resolveOfferSource(maleFocused.focus.offerId);
    await assert.rejects(function() {
        return renderer.resolvePairGender([maleSource, femaleSource], { gender: "男" });
    }, /no common equipment-focus gender/);

    var icon = await renderer.resolve({ kind: "icon", assetUri: "icons/test.webp" });
    assert.strictEqual(icon.assetUrl, "icons/test.webp");
    assert.strictEqual(icon.autoRotate, true);
    assert.strictEqual(calls.length, 2, "icon source invoked paper-doll renderer");

    var weaponTarget = catalog.entries.filter(function(entry) {
        return entry.displayName === "剧毒蛇矛";
    })[0];
    assert(weaponTarget, "representative weapon missing");
    var weaponFocused = session.lab.focusItem(weaponTarget.id);
    var weaponSource = session.visual.resolveOfferSource(weaponFocused.focus.offerId);
    assert.strictEqual(weaponSource.kind, "dressup-weapon");
    assert.strictEqual(Core.publicSnapshotContainsIdentity(weaponFocused.snapshot, catalog), false);
    var weaponVisual = await renderer.resolve(weaponSource, { gender: "男" });
    assert.strictEqual(weaponVisual.sourceKind, "dressup-weapon");
    assert(/^equipment-inspector-/.test(weaponVisual.sourceComposition),
        "weapon did not use equipment-inspector composition");
    assert.strictEqual(weaponVisual.autoRotate, true);
    assert.strictEqual(weaponVisual.sharpenSource, false);
    assert.strictEqual(calls.length, 3, "full weapon did not render exactly once");

    var fallbackSource = {
        kind: "dressup-weapon",
        itemId: "missing-weapon-fixture",
        itemName: "缺失武器素材夹具",
        iconName: "missing-weapon-fixture",
        itemType: "武器",
        use: "长枪",
        actionType: "",
        assetUri: "icons/test.webp",
        assetKind: "icon-proxy",
        sharpenFallback: true
    };
    var fallbackVisual = await renderer.resolve(fallbackSource, { gender: "男" });
    assert.strictEqual(fallbackVisual.kind, "icon");
    assert.strictEqual(fallbackVisual.sourceComposition, "sharpened-icon-fallback");
    assert.strictEqual(fallbackVisual.sharpenSource, true);
    assert.strictEqual(calls.length, 3, "weapon fallback invoked dressup renderer");

    var coverage = Preview.validateArmorCoverage(catalog, manifest);
    assert.strictEqual(coverage.candidates, 492);
    assert.strictEqual(coverage.covered, 492);
    assert.deepStrictEqual(coverage.missing, []);
    assert.strictEqual(coverage.partialGender.length, 16);
    assert.strictEqual(coverage.maleOnly, 2);
    assert.strictEqual(coverage.femaleOnly, 14);

    var focusedBranchCount = 0;
    var armorUses = {
        "头部装备": true,
        "上装装备": true,
        "手部装备": true,
        "下装装备": true,
        "脚部装备": true
    };
    catalog.entries.filter(function(entry) {
        return entry.mechanicallyRenderable && entry.type === "防具" && armorUses[entry.use];
    }).forEach(function(entry) {
        ["男", "女"].forEach(function(gender) {
            var focus = equipmentInspectorApi.resolveProductSource({
                name: entry.name,
                icon: entry.iconKey,
                majorType: "防具",
                type: "防具",
                use: entry.use
            }, gender, manifest);
            if (focus.kind !== "armor") return;
            focusedBranchCount++;
            var state = equipmentInspectorApi.buildStateForSource(focus, manifest);
            var authoredFields = Object.keys(manifest.items[entry.name].fieldsByGender[gender]);
            assert.deepStrictEqual(Array.from(state.fitFields), authoredFields,
                entry.name + "/" + gender + " fit fields drifted");
            var allowedDraw = authoredFields.concat(entry.use === "头部装备" ? ["脸型"] : []);
            state.drawFields.forEach(function(field) {
                assert(allowedDraw.includes(field),
                    entry.name + "/" + gender + " leaked unrelated draw field " + field);
            });
        });
    });
    assert.strictEqual(focusedBranchCount, 968,
        "equipment-focus branch count drifted");

    var offCenterFocus = InspectionFocus.plan({
        sourceWidth:512,
        sourceHeight:768,
        objectBounds:{x:116, y:548, width:280, height:142, count:24000},
        envelopeRadiusPx:6,
        viewportWidth:1088,
        viewportHeight:600,
        rotation:0
    });
    assert.strictEqual(offCenterFocus.version, "blackmarket-inspection-focus.v1");
    assert(offCenterFocus.zoom > 1.5 && offCenterFocus.panY < -100,
        "off-centre item was not enlarged and moved into the focus area");
    var rotatedFocus = InspectionFocus.plan({
        sourceWidth:512,
        sourceHeight:768,
        objectBounds:{x:116, y:548, width:280, height:142, count:24000},
        envelopeRadiusPx:6,
        viewportWidth:1088,
        viewportHeight:600,
        rotation:90
    });
    assert.strictEqual(rotatedFocus.rotation, 90);
    assert.strictEqual(rotatedFocus.canvasWidth, 768);
    assert.strictEqual(rotatedFocus.canvasHeight, 512);
    assert.notStrictEqual(rotatedFocus.panX, offCenterFocus.panX,
        "rotated item reused the stale focus transform");
    var fullSurfaceFocus = InspectionFocus.plan({
        sourceWidth:512,
        sourceHeight:768,
        objectBounds:{x:0, y:0, width:512, height:768, count:512 * 768},
        viewportWidth:1088,
        viewportHeight:600
    });
    assert.strictEqual(fullSurfaceFocus.zoom, 1);
    assert.strictEqual(fullSurfaceFocus.panX, 0);
    assert.strictEqual(fullSurfaceFocus.panY, 0);

    renderer.destroy();
    await assert.rejects(function() {
        return renderer.resolve(source, { gender: "男" });
    }, /destroyed/);

    var broken = Preview.create({
        portraitApi: {
            loadManifest: function() { return Promise.resolve(manifest); },
            renderStateDataUrl: function() { return Promise.resolve(""); }
        },
        equipmentInspectorApi: equipmentInspectorApi
    });
    await assert.rejects(function() {
        return broken.resolve(source, { gender: "男" });
    }, /no PNG/);
    broken.destroy();

    var root = path.resolve(__dirname, "..");
    var panelSource = fs.readFileSync(path.join(root,
        "launcher/web/modules/minigames/blackmarket/blackmarket-panel.js"), "utf8");
    var cssSource = fs.readFileSync(path.join(root,
        "launcher/web/modules/minigames/blackmarket/blackmarket.css"), "utf8");
    var surfaceSource = fs.readFileSync(path.join(root,
        "launcher/web/modules/minigames/blackmarket/visual/item-surface.js"), "utf8");
    var focusSource = fs.readFileSync(path.join(root,
        "launcher/web/modules/minigames/blackmarket/visual/inspection-focus.js"), "utf8");
    var registrySource = fs.readFileSync(path.join(root,
        "launcher/web/modules/panels-lazy-registry.js"), "utf8");
    var mercPortraitSource = fs.readFileSync(path.join(root,
        "launcher/web/modules/merc-portrait-renderer.js"), "utf8");
    assert(panelSource.includes("blackmarket-surface-guard")
        && panelSource.includes('data-surface-state="loading"'), "fail-closed guard markup missing");
    assert(/\.blackmarket-item-fallback\s*\{[\s\S]*?opacity:\s*0\s*!important;[\s\S]*?visibility:\s*hidden\s*!important;/.test(cssSource),
        "raw icon fallback is not hard-hidden");
    assert(surfaceSource.includes('rendered.metrics.mudOrientationDeg = plan.degrees')
        && surfaceSource.includes('surfaceSpace = "post-orientation-object-alpha"'),
        "mud/item post-orientation evidence missing");
    assert(surfaceSource.includes("function sharpenSourceImageData")
        && surfaceSource.includes('sourceSharpening = sharpeningStrength > 0 ? "alpha-safe-unsharp" : "none"'),
        "alpha-safe proxy sharpening evidence missing");
    assert(panelSource.includes("SURFACE_MASTER_WIDTH = 512")
        && panelSource.includes("SURFACE_MASTER_HEIGHT = 768")
        && panelSource.includes("rememberSurfaceMaster(offer.offerId, completedCanvas, metrics)"),
        "fixed shared surface-master contract missing");
    assert(panelSource.includes("WorkbenchInspectionViewport.create")
        && panelSource.includes('data-bm-action="inspection-rotate"')
        && panelSource.includes("只放大同一份覆泥证据"),
        "identity-safe inspection shell missing");
    assert(panelSource.includes("PanelScale.attach(_scaleShell, DESIGN_WIDTH, DESIGN_HEIGHT)")
        && panelSource.includes("DESIGN_WIDTH = 1024")
        && panelSource.includes("DESIGN_HEIGHT = 576"),
        "blackmarket fixed 1024x576 Flash design-surface contract missing");
    assert(panelSource.includes("BlackMarketInspectionFocus.plan")
        && panelSource.includes("resetOffset") && panelSource.includes("panBounds"),
        "automatic inspection focus contract missing");
    assert(focusSource.includes('version:"blackmarket-inspection-focus.v1"'),
        "inspection focus planner version missing");
    assert(!/@media\s*\([^)]*(?:max-width|max-height)/.test(cssSource)
        && !/\d(?:\.\d+)?vw\b/.test(cssSource),
        "blackmarket still contains physical-viewport reflow rules");
    assert(!panelSource.includes("EquipmentInspector.open("),
        "blackmarket inspection called the identity-bearing equipment inspector opener");
    assert(cssSource.includes(".blackmarket-inspection-dialog")
        && cssSource.includes(".blackmarket-inspection-viewport")
        && cssSource.includes(".blackmarket-asset.icon-proxy.source-dressup-weapon::after"),
        "inspection/weapon-source presentation styles missing");
    assert(mercPortraitSource.includes("renderStateDataUrl: renderStateDataUrl"),
        "shared resolved-state snapshot API missing");
    var inspectorIndex = registrySource.indexOf("modules/equipment-inspector.js");
    var portraitIndex = registrySource.indexOf("modules/merc-portrait-renderer.js");
    var previewIndex = registrySource.indexOf("modules/minigames/blackmarket/visual/equipment-preview.js");
    var focusIndex = registrySource.indexOf("modules/minigames/blackmarket/visual/inspection-focus.js");
    var panelIndex = registrySource.indexOf("modules/minigames/blackmarket/blackmarket-panel.js");
    assert(inspectorIndex >= 0 && inspectorIndex < previewIndex
        && portraitIndex >= 0 && portraitIndex < previewIndex
        && previewIndex < focusIndex && focusIndex < panelIndex,
        "blackmarket paper-doll lazy dependency order drifted");

    console.log("[blackmarket-equipment-preview] 30/30 passed; focused paper-doll armor="
        + coverage.covered + "/" + coverage.candidates + ", gender-specific="
        + coverage.partialGender.length + ", focusedBranches=" + focusedBranchCount
        + ", weapon=" + weaponTarget.displayName + ", sharpenedFallback=synthetic-missing-weapon");
}

main().catch(function(error) {
    console.error(error && error.stack ? error.stack : String(error));
    process.exitCode = 1;
});
