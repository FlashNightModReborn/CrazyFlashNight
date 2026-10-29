'use strict';
const {resolveRoute}=require('./route-config');
const fs = require('fs'), path = require('path'), crypto = require('crypto'), cp = require('child_process');
const E = require('../workbench-live-e2e/lib/evidence-artifact');
const Swf = require('../swf-metadata');
const {parseStrictJson}=require('../cf7-agent/lib/strict-json');
const VEHICLE_ASSETS=Object.freeze([
    {swf:'flashswf/arts/new/CF6Vehicle.swf',xfl:'flashswf/arts/new/CF6Vehicle/CF6Vehicle.xfl'},
    {swf:'flashswf/backgrounds/cf6/CF6_A07_BG.swf',xfl:'flashswf/backgrounds/cf6/CF6_A07_BG/CF6_A07_BG.xfl'},
    {swf:'flashswf/backgrounds/cf6/CF6_A07_sky.swf',xfl:'flashswf/backgrounds/cf6/CF6_A07_sky/CF6_A07_sky.xfl'}
]);
const VEHICLE_CONSUMERS=Object.freeze(['Service','ActorAdapter','Combat','Timeline','Data','Rules']
    .map(name=>'scripts/类定义/org/flashNight/arki/scene/Cf6Vehicle'+name+'.as'));
const SCENIC_WINGS_SWF='flashswf/backgrounds/cf6/preparation/CF6_ScenicWings.swf';
const ORIGINAL_SWF='flashswf/arts/new/Codex素材源稿/CF6地图/原作参考/crazyflasher6-cn.swf';
const FILES = [
    'scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as',
    'scripts/类定义/org/flashNight/arki/scene/StageReturnFlow.as',
    'scripts/类定义/org/flashNight/arki/camera/HorizontalScroller.as',
    'launcher/src/Data/MapTaskCatalog.cs',
    'scripts/类定义/org/flashNight/arki/scene/StageRunSession.as',
    'scripts/类定义/org/flashNight/arki/scene/SceneTransitionGuard.as',
    'scripts/类定义/org/flashNight/arki/scene/PlayerResourceTransfer.as',
    'scripts/类定义/org/flashNight/arki/scene/PlayerSceneLifecycle.as',
    'scripts/类定义/org/flashNight/arki/unit/PlayerStatRefreshCoordinator.as',
    'scripts/类定义/org/flashNight/arki/item/CharacterBuildService.as',
    'scripts/类定义/org/flashNight/arki/hud/FocusTargetHudService.as',
    'scripts/类定义/org/flashNight/arki/hud/PlayerHudService.as',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerHudController.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerHudRuntime.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerHudState.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerHudFocusTargetWidget.cs',
    'scripts/类定义/org/flashNight/arki/unit/Action/Regeneration/LevelUpRecovery.as',
    'scripts/类定义/org/flashNight/arki/unit/Action/Regeneration/ResourceNumber.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/DressupInitializer.as',
    'scripts/类定义/org/flashNight/arki/ui/SceneTransitionService.as',
    'CRAZYFLASHER7MercenaryEmpire/LIBRARY/sprite/淡出动画.xml',

    'scripts/类定义/org/flashNight/arki/scene/Cf6TraversalRules.as',
    'scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as',
    'scripts/类定义/org/flashNight/arki/scene/Cf6TransportService.as',
    'scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthService.as',
    'scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskPresentation.as',
    'scripts/类定义/org/flashNight/arki/scene/Cf6ExitGuideService.as',
    'scripts/类定义/org/flashNight/arki/unit/Cf6BodyScaleRules.as',
    'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as',
    'scripts/类定义/org/flashNight/arki/pause/PauseManager.as',
    'scripts/类定义/org/flashNight/gesh/depth/DepthManager.as',
    'tools/cf7-agent/lib/strict-json.js',
    'tools/cf6-prototype/scene-assembly.py',
    'tools/cf6-prototype/interactive-assembly.py',
    'tools/cf6-prototype/transport-assembly.py',
    'tools/cf6-prototype/spawn-assembly.py',
    'flashswf/arts/new/Codex素材源稿/CF6地图/A11-R2/cf6-stage11-redraw-r2/reference/environment-original-nodes.json',
    'tools/cf6-scene-completion/source-evidence/actions/da8403d2135566583ef7baf6a1351c820f5bcb78a31c633a95066e239aa04e01.as.txt',
    'flashswf/arts/things3/LIBRARY/地瓜手雷.xml',
    'flashswf/arts/原版素材库-子弹/LIBRARY/手雷/地瓜手雷/地瓜手雷.xml',
    'tools/cf6-scene-completion/completion-plan.json',
    'tools/cf6-prop-layout/calibrate.py',
    'tools/cf6-prop-layout/scale-policy.json',
    'tools/cf6-prop-layout/build_unit_scale.py',
    'tools/cf6-prop-layout/derive_laboratory.py',
    'tools/cf6-prop-layout/derive_tutorial.py',
    'tools/cf6-scene-completion/pod_scale.py',
    'tools/cf6-map-runtime/native-vector/batch/pattern_adapter.py',
    'tools/cf6-prop-layout/build_depth_props.py',
    'tools/cf6-prop-layout/recipe.json',
    'tools/cf6-prop-layout/depth-recipe.json',
    'tools/cf6-prop-layout/generated/instance-layout.json',
    'tools/cf6-prop-layout/generated/depth-props.fragment.json',
    'tools/cf6-scene-completion/build_traversal_art.py',
    'tools/cf6-scene-completion/build_auxiliary_doors.py',
    'tools/cf6-scene-completion/build_interactive_art.py',
    'tools/cf6-scene-completion/build_transport_art.py',
    'scripts/类定义/org/flashNight/arki/component/Damage/DamageCalculator.as',
    'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/AABBCollider.as',
    'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/AABBColliderFactory.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/ComponentInitializer.as',
    'scripts/类定义/org/flashNight/neur/Event/EventDispatcher.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/StaticInitializer.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Deinitializer/StaticDeinitializer.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventInitializer.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/ElementComponent/BasicAttributeInitializer.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/HitEventComponent.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/KillEventComponent.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/DeathEventComponent.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/UpdateEventComponent.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Targetcache/TargetCacheManager.as',
    'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Targetcache/FactionManager.as',
    'tools/cf6-scene-completion/install_rules.py',

    'flashswf/arts/new/Codex素材源稿/CF6地图/原作参考/source-manifest.json',
    'automation/start.ps1','launcher/src/Tasks/AgentControlTask.cs','launcher/src/Program.cs',
    'launcher/src/Tasks/BookshelfTask.cs','launcher/src/FixedWebViewRuntime.cs','launcher/webview2-runtime.lock.json',
    'scripts/类定义/org/flashNight/arki/ui/BookshelfPanelService.as',
    'scripts/类定义/org/flashNight/arki/scene/BookRunService.as',
    'scripts/类定义/org/flashNight/arki/dialogue/NativeDialogueService.as',
    'scripts/类定义/org/flashNight/arki/dialogue/NativeDialogueAppearance.as',
    'launcher/src/Tasks/NativeDialogueTask.cs',
    'launcher/src/Guardian/Dialogue/DialoguePortraitService.cs',
    'launcher/src/Guardian/Dialogue/NativeDialogueSourceAssembler.cs',
    'tools/cf6-elder-assets/ElderTransform.as',
    'tools/cf6-elder-assets/ElderAI.as',
    'flashswf/arts/new/Codex老头素材/LIBRARY/Codex/老头/敌人-CF6老头人形.xml',
    'flashswf/arts/new/Codex老头素材/LIBRARY/Codex/老头/敌人-CF6老头机器人.xml',
    'scripts/类定义/org/flashNight/arki/scene/BookRunRules.as',
    'scripts/类定义/org/flashNight/arki/scene/BookDefinition.as',
    'scripts/类定义/org/flashNight/arki/scene/Cf6BossEncounter.as',
    'scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as',
    'scripts/类定义/org/flashNight/arki/scene/Cf6MapPresentation.as',
    'scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretService.as',
    'scripts/类定义/org/flashNight/arki/scene/Cf6StoryService.as',
    'scripts/类定义/org/flashNight/arki/scene/BookComicService.as',
    'scripts/类定义/org/flashNight/arki/audio/AudioBridge.as',
    'scripts/类定义/org/flashNight/arki/audio/SoundEffectManager.as',
    'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as',
    'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Init/BulletInitializer.as',
    'scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as',
    'scripts/类定义/org/flashNight/arki/component/StatHandler/DodgeHandler.as',
    'scripts/逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as',
    'launcher/src/Tasks/BookComicTask.cs','launcher/src/Audio/AudioCoordinator.cs',
    'launcher/src/Guardian/LauncherCommandRouter.cs','launcher/src/Guardian/WebOverlayForm.cs',
    'scripts/类定义/org/flashNight/arki/scene/Cf6EconomyRules.as',
    'scripts/类定义/org/flashNight/arki/scene/BookRunClock.as',
    'scripts/类定义/org/flashNight/arki/scene/SceneManager.as',
    'scripts/类定义/org/flashNight/arki/scene/StageInfo.as',
    'scripts/类定义/org/flashNight/arki/scene/StageManager.as',
    'scripts/类定义/org/flashNight/arki/scene/StageEvent.as',
    'scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as',
    'scripts/类定义/org/flashNight/arki/scene/WaveSpawnWheel.as',
    'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/LinearBulletMovement.as',
    'scripts/类定义/org/flashNight/arki/item/ChoiceRewardDefinition.as',
    'scripts/类定义/org/flashNight/arki/item/ChoiceRewardService.as',
    'scripts/类定义/org/flashNight/arki/item/ChoiceRewardStore.as',
    'scripts/类定义/org/flashNight/arki/item/RewardStashService.as',
    'scripts/类定义/org/flashNight/arki/item/RewardStashStore.as',
    'scripts/类定义/org/flashNight/arki/item/EquipmentTuningService.as',
    'scripts/类定义/org/flashNight/arki/unit/Action/PickUp/PickUpManager.as',
    'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ReloadManager.as',
    'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponAmmoRuntime.as',
    'scripts/逻辑/关卡系统/关卡系统_lsy_add2map_加载背景.as',
    'scripts/逻辑/关卡系统/关卡系统_lsy_地图元件.as',
    'scripts/逻辑系统分区/商店系统_兼容.as',
    'scripts/引擎/引擎_lsy_等级与经验值.as',
    'scripts/类定义/org/flashNight/neur/Server/SaveManager.as','scripts/asLoader.swf',
    'CRAZYFLASHER7MercenaryEmpire.swf',
    'data/stages/books/cf6-sting.runtime.json','data/stages/books/cf6-sting.json','data/books/catalog.json',
    'data/environment/stage_environment.xml','data/environment/scene_environment.xml',
    'data/environment/scene_lights.v1.json','data/environment/presentation_presets.v1.json',
    'data/environment/color_engine_preset.xml','config/WeatherSystemConfig.xml',
    'data/units/units.json','data/equipment/equipment_config.xml',
    'data/shops/remote-access.json',
    'data/skills/skills.xml','data/skills/skills_tree_config.json','data/skills/skills_metadata.json','data/skills/npc_skills.json',
    'data/rewards/choice-rewards.json','data/rewards/choice-rewards.generated.json',
    'data/stages/books/cf6-sting-source/choice-rewards.fragment.json',
    'data/stages/books/cf6-sting-source/economy.fragment.json','data/stages/books/cf6-sting-source/maps.fragment.json',
    'tools/cf6-prototype/balance-input.json','tools/cf6-prototype/build-chapter.py',
    'tools/cf6-prototype/dialogue-portraits.json',
    'tools/cf6-prototype/viewport-policy.json','tools/cf6-prototype/viewport-assembly.py',
    'tools/cf6-prototype/generated/original-camera-layout.json',
    'tools/cf6-prototype/generated/assembly.json','tools/cf6-roguelike-content/build-sting-fragments.py',
    'tools/cf6-roguelike-content/weapon_pools.py','tools/cf6-roguelike-content/weapon-pools.source.json',
    'tools/cf6-roguelike-content/difficulty.source.json','tools/cf6-roguelike-content/difficulty_plan.py',
    'data/stages/books/cf6-sting-source/encounter-facts.v1.json',
    'tools/cf6-map-runtime/build-tutorial.py','tools/cf6-tutorial/assemble.py',
    'tools/cf6-tutorial/layout.json','tools/cf6-tutorial/original-tutorial-geometry.json',
    'tools/cf6-tutorial/environment.fragment.xml','tools/cf6-tutorial/tutorial-map.fragment.json',
    'tools/cf6-tutorial/provenance.json',
    'tools/cf6-tutorial-turrets/tutorial-turrets.fragment.json',
    'tools/cf6-tutorial-turrets/generated/geometry-r14.json',
    'tools/cf6-tutorial-turrets/generated/import-assets.jsfl',
    'tools/cf6-tutorial-turrets/build-turret-xfl.py',
    'tools/cf6-tutorial-turrets/build-manifest.py','tools/cf6-tutorial-turrets/build-fragment.py',
    'flashswf/arts/new/Codex素材源稿/CF6教学炮塔/manifest.json',
    'tools/cf6-map-runtime/sky-parallax.fragment.json','tools/import-bookshelf-library.py',
    'tools/choice_reward_catalog.py','tools/cf6_economy.py','tools/build-choice-rewards.py',
    'tools/build-book-definition.py','tools/book-definition-runtime.as.inc','tools/swf-metadata.js',
    'launcher/web/modules/bridge.js','launcher/web/modules/panels.js',
    'launcher/web/modules/book-comic-panel.js','launcher/web/modules/book-comic-content.js',
    'launcher/web/modules/book-comic-cf6-content.js','launcher/web/css/book-comic.css',
    'launcher/web/assets/book-comic/cf6/manifest.json',
    'launcher/web/assets/book-comic/cf6/integrity-audit.json',
    'tools/cf6-story-migration/generated/cf6-web-content.json',
    'launcher/web/modules/panels-lazy-registry.js','launcher/web/modules/bookshelf-runtime.js',
    'launcher/web/modules/bookshelf-panel.js','tools/workbench-live-e2e/lib/launcher-observation.js',
    'launcher/web/assets/bookshelf/catalog.json','launcher/web/assets/bookshelf/library-manifest.json',
    'launcher/web/css/bookshelf.css','launcher/web/modules/bookshelf-shelf-scene.js',
    'launcher/web/modules/bookshelf/shelf/interaction-core.mjs',
    'launcher/web/modules/bookshelf/shelf/layout-core.mjs','launcher/web/modules/bookshelf/shelf/layout-three.js',
    'launcher/web/assets/bookshelf/shelf/config.json','launcher/web/assets/bookshelf/shelf/manifest.json',
    'launcher/web/assets/bookshelf/shelf/v4-manifest.json','launcher/web/assets/bookshelf/shelf/v3.glb',
    'launcher/web/assets/bookshelf/shelf/scene.glb',
    'tools/workbench-live-e2e/lib/clone-save-guard.js','tools/workbench-live-e2e/kshop/generic-opener.js',
    'tools/workbench-live-e2e/lib/runtime-guard.js','tools/workbench-live-e2e/kshop/cdp-client.js',
    ...['preflight','source-closure','passive-observer','manual-observation','cdp-input-channel','affiliated-slot','run-candidate','verified-return-observation']
        .map(name=>'tools/cf6-live-e2e/'+name+'.js')
];
const LISTS = Object.freeze([
    ['data/shops/list.xml','data/shops',['shops']],
    ['data/items/list.xml','data/items',['items','itemSets']],
    ['data/items/equipment_mods/list.xml','data/items/equipment_mods',['items','uiPresentation']],
    ['data/enemy_properties/list.xml','data/enemy_properties',['items']]
]);
function relative(value) {
    if(typeof value!=='string'||!value||value!==value.trim()||/[\x00-\x1f\x7f:%?#]/.test(value)
            ||path.win32.isAbsolute(value)||path.posix.isAbsolute(value))throw Error('invalid closure relative path');
    const normalized=value.replace(/\\/g,'/'),parts=normalized.split('/');
    if(parts.some(p=>!p||p==='.'||p==='..'||/[. ]$/.test(p)))throw Error('invalid closure path segment');
    return normalized;
}
function inside(root, ref) {
    const full=path.resolve(root,relative(ref));
    if(!E.pathInside(root,full))throw Error('closure resource escapes root');
    return full;
}
function xmlText(value) {
    const decoded=value.replace(/&(?:amp|lt|gt|quot|apos);/g,x=>({'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&apos;':"'"}[x]))
        .replace(/&#(x[0-9a-f]+|[0-9]+);/gi,(_m,n)=>String.fromCodePoint(n[0].toLowerCase()==='x'?parseInt(n.slice(1),16):Number(n)));
    if(/&[A-Za-z#][^;\s]*;/.test(decoded))throw Error('unsupported XML entity in closure path');
    return decoded.trim();
}
function listReferences(xml, tags) {
    if(/<!DOCTYPE|<!ENTITY/i.test(xml))throw Error('external/entity XML is not a closed resource list');
    const source=xml.replace(/<!--[\s\S]*?-->/g,'');
    const result=[];
    for(const tag of tags){
        const open=(source.match(new RegExp('<'+tag+'(?:\\s|>)','g'))||[]).length;
        const matches=[...source.matchAll(new RegExp('<'+tag+'\\s*>([^<>]+)</'+tag+'\\s*>','g'))];
        if(open!==matches.length)throw Error('malformed closure list entries: '+tag);
        for(const match of matches)result.push(relative(xmlText(match[1])));
    }
    if(!result.length)throw Error('empty closure resource list');
    return result;
}
const TYPE61_FILES=Object.freeze([
    "tools/cf6-type61/build-route.py",
    "tools/cf6-type61/route.source.json",
    "tools/cf6-type61/encounters.py",
    "tools/cf6-type61/encounters.source.json",
    "tools/cf6-soldier-assets/instructor-tuning.json",
    "tools/cf6-soldier-assets/instructor-register.py",
    "tools/cf6-soldier-assets/balance.py",
    "tools/cf6-soldier-assets/elite-register.py",
    "tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts",
    "tools/cf6-type61/choice-rewards.fragment.json",
    "tools/cf6-type61/recipes.generated.json",
    "tools/cf6-type61/manifest.generated.json",
    "data/stages/books/cf6-type61.json",
    "data/stages/books/cf6-type61.runtime.json",
    "data/crafting/书中配给.json",
    "data/crafting/进阶防具.json",
    "data/crafting/铁枪会.json",
    "scripts/类定义/org/flashNight/arki/scene/Cf6Type61Service.as",
    "scripts/类定义/org/flashNight/arki/item/Cf6ConstellationPolicy.as",
    "scripts/类定义/org/flashNight/arki/item/ItemUseService.as",
    "scripts/类定义/org/flashNight/arki/interaction/NativeMenuBridge.as",
    "tools/cf6_acquisition.py",
    "tools/cf6-type61/acquisition.generated.json",
    "data/crafting/list.xml",
    "data/kshop/list.xml",
    "data/crafting/属性武器.json",
    "data/crafting/烹饪.json",
    "data/crafting/化学生产.json",
    "data/crafting/武器合成.json",
    "data/crafting/饰品合成.json",
    "data/crafting/基础防具.json",
    "data/crafting/公社防具.json",
    "data/crafting/黑白契约.json",
    "data/crafting/插件合成.json",
    "data/crafting/大学装备.json",
    "data/crafting/调酒.json",
    "data/kshop/乱七八糟.json",
    "data/kshop/A兵团官方周边直营店.json",
    "data/kshop/联合大学D.L.S.研究中心.json",
    "data/kshop/联合大学校服批发.json",
    "data/kshop/蓉都公社弹药加工厂.json",
    "data/kshop/统合尘都临时政府卫生部.json",
    "data/kshop/莱昂利亚自由革命军军火出口.json",
    "data/kshop/【数据错误-未知来源军火】.json",
    "data/kshop/天地玄黄慈悲万怀兵器库.json",
    "data/kshop/末日COS☆PLAY.json",
    "data/kshop/堕落城浮世安保专卖店.json",
    "data/kshop/武术联盟.json",
    "data/kshop/情趣店.json",
    "scripts/类定义/org/flashNight/arki/scene/Cf6ActorLoadout.as",
    "scripts/类定义/org/flashNight/arki/scene/StageManager.as",
    "scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as",
    "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as",
    "scripts/类定义/org/flashNight/arki/item/MaterialArchiveProjector.as",
    "scripts/类定义/org/flashNight/arki/item/ProcurementPlanService.as",
    "scripts/类定义/org/flashNight/arki/item/NpcShopAccessService.as",
    "scripts/类定义/org/flashNight/arki/skill/SkillLoadoutService.as",
    "scripts/类定义/org/flashNight/arki/skill/SkillPanelService.as",
    "scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as",
    "scripts/展现/UI交互/UI交互_lsy_物品栏UI.as",
    "scripts/逻辑系统分区/商城系统_WebView.as"
]);
function chapterResources(chapter,routeId) {
    const route=resolveRoute(routeId);
    if(chapter?.id!=='cf6-sting'||chapter.routeId!==route.id||!Array.isArray(chapter.maps)||!chapter.maps.length)
        throw Error('closure requires the selected installed chapter');
    const result=[];
    function walk(value,depth){
        if(depth>32)throw Error('chapter resource nesting exceeded');
        if(Array.isArray(value)){value.forEach(x=>walk(x,depth+1));return;}
        if(!value||typeof value!=='object')return;
        for(const [key,child] of Object.entries(value)){
            if(key==='url'||key==='Background'||key==='assetUrl'){
                if(typeof child!=='string')throw Error('chapter runtime resource URL must be a string');
                if(!/\.swf$/i.test(child))throw Error('chapter runtime resource must be a local SWF');
                const ref=relative(child);if(!ref.startsWith('flashswf/'))throw Error('chapter resource outside flashswf');result.push(ref);
            }else walk(child,depth+1);
        }
    }
    for(const map of chapter.maps){
        if(typeof map.background!=='string'||!/\.swf$/i.test(map.background))throw Error('chapter background must be a local SWF');
        result.push(relative('flashswf/backgrounds/'+relative(map.background)));walk(map.stage,0);walk(map.mechanism,0);
    }
    return [...new Set(result)].sort();
}
function resolveImport(root,owner,raw) {
    let url;try{url=decodeURIComponent(raw).replace(/\\/g,'/');}catch(_){throw Error('invalid SWF import encoding');}
    if(!url||/[\x00-\x1f\x7f:%?#]/.test(url)||path.win32.isAbsolute(url)||path.posix.isAbsolute(url)||!/\.swf$/i.test(url))
        throw Error('SWF import is not a local relative resource');
    const candidates=[];
    for(const candidate of [url,path.posix.normalize(path.posix.join(path.posix.dirname(owner),url))]){
        let ref;try{ref=relative(candidate);inside(root,ref);}catch(_){continue;}
        if(ref==='flashswf/gk-1-s.swf')throw Error('legacy credential-shaped pseudo-SWF is not an asset closure input');
        if(fs.existsSync(inside(root,ref))&&!candidates.includes(ref))candidates.push(ref);
    }
    if(candidates.length!==1)throw Error('missing or ambiguous SWF import from '+owner+': '+raw);
    return candidates[0];
}
// Manifests retain authoring-machine provenance. A linked worktree may use the
// same repository's primary checkout as that origin; texture bytes are always
// read and hash-checked inside the selected current root, never at item.path.
function textureOriginRoots(root) {
    const roots=[path.resolve(root)];
    try {
        const git=(args)=>cp.execFileSync('git',['-C',root,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:5000}).trim();
        if(path.resolve(git(['rev-parse','--show-toplevel']))!==roots[0])return roots;
        const common=E.assertExactDirectory(path.resolve(git(['rev-parse','--path-format=absolute','--git-common-dir'])),'cf6_texture_origin');
        if(path.basename(common)!=='.git')return roots;
        const primary=E.assertExactDirectory(path.dirname(common),'cf6_texture_origin');
        if(primary!==roots[0])roots.push(primary);
    }catch(_){/* Non-Git installed roots retain the original exact-local rule. */}
    return roots;
}
function capture(root,routeId) {
    const route=resolveRoute(routeId);
    root=E.assertExactDirectory(path.resolve(root),'cf6_closure');
    const origins=textureOriginRoots(root);
    const pending=new Set(),folded=new Map(),rows=new Map(),edges=[];
    function add(ref,owner,kind){
        ref=relative(ref);inside(root,ref);
        const key=ref.toLowerCase();if(folded.has(key)&&folded.get(key)!==ref)throw Error('case-aliased closure resource: '+ref);
        folded.set(key,ref);pending.add(ref);
        // Four full interactive timelines require a larger but finite whole-journey inventory.
        if(pending.size>8192)throw Error('closure resource count exceeded');
        if(owner)edges.push({owner,target:ref,kind});return ref;
    }
    function read(ref){
        // CS6 creates this optional sidecar as an empty regular file for desktop XFLs.
        // The one hash-named original 1805/frame2 ActionEnd export is also genuinely empty.
        // Keep exact bytes/hash; other required source and asset files stay nonempty.
        const allowEmpty=ref==='flashswf/backgrounds/cf6/CF6_A01_Turret/MobileSettings.xml'
            ||ref==='tools/cf6-vehicle/source/actions/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.as.txt';
        const file=E.readExactRegularFile(inside(root,ref),{phase:'cf6_closure',maximumBytes:128*1024*1024,allowEmpty});
        const row={relativePath:ref,bytes:file.length,sha256:file.sha256};
        if(rows.has(ref)&&rows.get(ref).sha256!==row.sha256)throw Error('closure resource changed during discovery');
        rows.set(ref,row);return file.bytes;
    }
    const json=ref=>parseStrictJson(read(ref).toString('utf8').replace(/^\uFEFF/,''),{maximumDepth:64});
    const digest=value=>typeof value==='string'&&/^[0-9a-f]{64}$/.test(value);
    function bound(row,base,owner,kind){
        if(!row||!digest(row.sha256))throw Error('invalid declared asset digest: '+owner);
        const ref=relative(base+relative(row.path));add(ref,owner,kind);read(ref);
        if(rows.get(ref).sha256!==row.sha256)throw Error('declared asset digest mismatch: '+ref);
        if(row.bytes!==undefined&&(!Number.isSafeInteger(row.bytes)||row.bytes<1||rows.get(ref).bytes!==row.bytes))
            throw Error('declared asset size mismatch: '+ref);
        return ref;
    }
    function assetRows(list,base,owner,kind){
        if(!Array.isArray(list)||!list.length||list.length>256)throw Error('invalid asset list: '+owner);
        const names=new Set();let bytes=0;
        for(const row of list){
            const ref=bound(row,base,owner,kind),key=ref.toLowerCase();
            if(names.has(key))throw Error('duplicate declared asset: '+ref);
            names.add(key);bytes+=rows.get(ref).bytes;
        }
        return {names,bytes};
    }
    function sourceTree(base){
        let count=0;
        function walk(ref,depth){
            if(depth>16)throw Error('XFL source nesting exceeded');
            E.assertExactDirectory(inside(root,ref),'cf6_xfl_closure');
            for(const entry of fs.readdirSync(inside(root,ref),{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))){
                const child=relative(ref+'/'+entry.name);
                if(entry.isSymbolicLink())throw Error('linked XFL source entry: '+child);
                if(entry.isDirectory())walk(child,depth+1);
                else if(entry.isFile()){
                    if(++count>256)throw Error('XFL source file count exceeded');
                    add(child,base,'xfl_source');read(child);
                }else throw Error('non-regular XFL source entry: '+child);
            }
        }
        walk(base,0);
        for(const name of ['CF6_A01_Turret.xfl','DOMDocument.xml','PublishSettings.xml'])
            if(!rows.has(base+'/'+name))throw Error('missing turret XFL source: '+name);
    }
    function comicAssets(){
        const base='launcher/web/assets/book-comic/cf6/',source='flashswf/arts/new/Codex素材源稿/CF6漫画过场/';
        const manifestPath=base+'manifest.json',auditPath=base+'integrity-audit.json';
        const manifest=json(manifestPath),audit=json(auditPath),binding=manifest.sourceBinding;
        if(manifest.schema!=='cf6-book-comic-runtime-manifest.v1'||audit.schema!=='cf6-book-comic-integrity-audit.v1'
                ||!binding||!digest(manifest.sourceBindingSha256)
                ||E.sha256Text(E.canonicalJson(binding))!==manifest.sourceBindingSha256
                ||audit.sourceBindingSha256!==manifest.sourceBindingSha256)
            throw Error('invalid comic source binding');
        const payload=assetRows(manifest.files,base,manifestPath,'comic_runtime');
        if(manifest.fileCount!==manifest.files.length||manifest.totalBytes!==payload.bytes
                ||audit.fileCount!==manifest.fileCount||audit.totalBytes!==manifest.totalBytes
                ||E.canonicalJson(audit.runtimePayload)!==E.canonicalJson(manifest.files))
            throw Error('comic inventory totals or mirror binding mismatch');
        const exact={fragment:'tools/cf6-story-migration/generated/comic-story.fragment.json',
            index:'tools/cf6-story-migration/generated/cf6-story-index.extracted.json',assetManifest:source+'MANIFEST.json'};
        for(const key of Object.keys(exact)){
            if(binding[key]?.path!==exact[key])throw Error('unexpected comic source path: '+key);
            bound(binding[key],'',manifestPath,'comic_source');
        }
        if(!Array.isArray(binding.scripts)||!binding.scripts.length
                ||binding.scripts.some(row=>!/^tools\/cf6-story-migration\/[^/]+\.py$/.test(row.path)))
            throw Error('invalid comic producer paths');
        assetRows(binding.scripts,'',manifestPath,'comic_producer');
        assetRows(binding.assets,source,manifestPath,'comic_source');
        const contentPath='tools/cf6-story-migration/generated/cf6-web-content.json';
        const content=json(contentPath);
        if(content.schema!=='cf6-book-comic-web-content.v1'||content.sourceBindingSha256!==manifest.sourceBindingSha256
                ||!Array.isArray(content.pages)||!content.pages.length)throw Error('invalid comic runtime content');
        for(const page of content.pages)for(const ref of [page.image,page.audio?.music,page.audio?.narration].filter(x=>x!==undefined&&x!==null)){
            if(typeof ref!=='string'||!ref.startsWith('assets/book-comic/cf6/')
                    ||!payload.names.has(relative('launcher/web/'+ref).toLowerCase()))
                throw Error('comic runtime references an undeclared asset');
        }
        if(!Array.isArray(audit.generatedOutputs)||audit.generatedOutputs.some(row=>typeof row.path!=='string'
                ||!(row.path.startsWith(base)||row.path===contentPath||row.path==='launcher/web/modules/book-comic-cf6-content.js')))
            throw Error('invalid comic generated output paths');
        const outputs=assetRows(audit.generatedOutputs,'',auditPath,'comic_generated');
        for(const ref of [manifestPath,contentPath,'launcher/web/modules/book-comic-cf6-content.js',...payload.names])
            if(!outputs.names.has(ref.toLowerCase()))throw Error('missing comic generated output binding: '+ref);
        if(!digest(binding.originalSwfSha256)||binding.originalSwfSha256!==json(exact.fragment).source?.sha256)
            throw Error('comic original source identity mismatch');
    }
    function turretAssets(){
        const base='flashswf/arts/new/Codex素材源稿/CF6教学炮塔/';
        const manifestPath=base+'manifest.json',geometryPath='tools/cf6-tutorial-turrets/generated/geometry-r14.json';
        const fragmentPath='tools/cf6-tutorial-turrets/tutorial-turrets.fragment.json';
        const manifest=json(manifestPath),geometry=json(geometryPath),fragment=json(fragmentPath);
        if(manifest.schema!=='cf6-turret-native-tags.v2'||geometry.schema!=='cf6-turret-geometry.v1'
                ||fragment.schema!=='cf6-tutorial-turrets.v1'||!digest(manifest.sourceSwfSha256)
                ||geometry.sourceSwfSha256!==manifest.sourceSwfSha256||fragment.sourceSwf?.sha256!==manifest.sourceSwfSha256)
            throw Error('invalid turret source binding');
        if(fragment.sourceSwf.path!==ORIGINAL_SWF)
            throw Error('unexpected turret original source path');
        bound(fragment.sourceSwf,'',fragmentPath,'original_source');
        const tags=Object.values(manifest.tags||{}).map(row=>({path:row.file,bytes:row.length,sha256:row.sha256}));
        if(tags.some(row=>typeof row.path!=='string'||!row.path.startsWith('raw-tags/')))throw Error('invalid turret raw tag path');
        assetRows(tags,base,manifestPath,'turret_source');
        const media=Object.entries(geometry.media||{}).map(([name,row])=>({path:name,bytes:row.bytes,sha256:row.sha256}));
        if(media.some(row=>row.path.includes('/')||row.path.includes('\\')))throw Error('invalid turret media name');
        assetRows(media,base+'bitmaps/',geometryPath,'turret_media');
        sourceTree('flashswf/backgrounds/cf6/CF6_A01_Turret');
    }
    function attributes(xml,tag){
        if(/<!DOCTYPE|<!ENTITY/i.test(xml))throw Error('non-closed native XML');
        const clean=xml.replace(/<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>/g,'');
        return [...clean.matchAll(new RegExp('<(?:[A-Za-z_][\\w.-]*:)?'+tag+'\\b([^>]*)>','g'))].map(match=>{
            const out={};for(const a of match[1].matchAll(/([\w:.-]+)\s*=\s*(["'])([\s\S]*?)\2/g)){
                if(Object.hasOwn(out,a[1]))throw Error('duplicate native XML attribute');out[a[1]]=xmlText(a[3]);
            }return out;
        });
    }
    function nativeClosure(xfl,declared,owner,options={}){
        const base=path.posix.dirname(relative(xfl)),required=new Set();
        const need=ref=>{ref=relative(ref);required.add(ref);if(!declared.has(ref))throw Error('omitted native source dependency: '+ref);return read(ref).toString('utf8');};
        need(xfl);need(base+'/PublishSettings.xml');const doc=need(base+'/DOMDocument.xml');
        const includes=new Set(),media=new Set();
        for(const item of attributes(doc,'Include')){
            const ref=relative(base+'/LIBRARY/'+relative(item.href));if(includes.has(ref))throw Error('duplicate native Include');includes.add(ref);need(ref);
        }
        for(const item of attributes(doc,'DOMBitmapItem')){
            if(typeof item.name!=='string'||media.has(item.name))throw Error('duplicate or invalid bitmap name');media.add(item.name);
            need(base+'/LIBRARY/'+relative(item.href));need(base+'/bin/'+relative(item.bitmapDataHRef));
        }
        for(const ref of [base+'/DOMDocument.xml',...includes]){
            const xml=need(ref);
            if(options.visualOnly&&(/<(?:[A-Za-z_][\w.-]*:)?Actionscript\b/i.test(xml)
                    ||attributes(xml,'DOMSymbolItem').some(item=>Object.keys(item).some(key=>key.startsWith('linkage')))
                    ||attributes(xml,'DOMBitmapItem').length))throw Error('scenic actor gained executable, linked or bitmap content');
            for(const instance of attributes(xml,'DOMSymbolInstance')){
                const target=relative(base+'/LIBRARY/'+relative(instance.libraryItemName)+'.xml');
                if(!includes.has(target))throw Error('native symbol reference missing Include: '+target);
            }
            for(const instance of attributes(xml,'DOMBitmapInstance'))if(!media.has(instance.libraryItemName))throw Error('native bitmap reference missing media');
            for(const fill of attributes(xml,'BitmapFill'))if(!media.has(fill.bitmapPath))throw Error('native fill reference missing media');
        }
        if(options.exact){
            if(required.size!==declared.size||[...declared].some(ref=>!required.has(ref)))throw Error('extra native source declaration: '+owner);
            let count=0;
            function exactTree(folder,depth){
                if(depth>16)throw Error('native source tree depth exceeded');
                E.assertExactDirectory(inside(root,folder),'cf6_native_exact_closure');
                for(const item of fs.readdirSync(inside(root,folder),{withFileTypes:true})){
                    const ref=relative(folder+'/'+item.name);
                    if(item.isSymbolicLink())throw Error('linked native source entry');
                    if(item.isDirectory())exactTree(ref,depth+1);
                    else if(!item.isFile()||++count>4096||!required.has(ref))throw Error('extra or non-regular native source file: '+ref);
                }
            }
            exactTree(base,0);
        }
    }
    function tableEntries(table,owner,maximum=4096){
        if(!table||Array.isArray(table)||typeof table!=='object'||!Object.keys(table).length||Object.keys(table).length>maximum)
            throw Error('invalid scene asset table: '+owner);
        const seen=new Set();return Object.entries(table).map(([raw,value])=>{
            const ref=relative(raw),key=ref.toLowerCase();if(seen.has(key))throw Error('duplicate scene asset path: '+ref);seen.add(key);
            if(ref===owner)throw Error('self-bound scene manifest');
            const row=typeof value==='string'?{path:ref,sha256:value}:{...value,path:ref};
            if(!digest(row.sha256))throw Error('invalid scene asset digest: '+ref);
            return row;
        });
    }
    function sceneManifest(ref,schema,used,kind){
        const auxiliary=kind===true,interactive=kind==='interactive',transport=kind==='transport',textured=auxiliary||interactive||transport;
        add(ref);const manifest=json(ref);
        if((interactive||transport)&&manifest.originalSha256!==rows.get(ORIGINAL_SWF).sha256)throw Error(kind+' original source digest mismatch');
        if(manifest.schema!==schema||!Array.isArray(manifest.assets)||!manifest.assets.length||manifest.assets.length>32)
            throw Error('invalid native scene manifest');
        const known=new Map(),names=new Set(),selected=[];
        for(const asset of manifest.assets){
            const name=asset.name;
            if(typeof name!=='string'||!(transport?/^CF6_Transport1868$/:interactive?/^CF6_Interactive(?:Barrel(?:1736|1838|1976)|Pod1939)$/:auxiliary?/^CF6_Aux[A-Za-z0-9_]+$/:/^CF6_Traversal(?:1720|1729|1750)_(?:Back|Front|Mask)$/).test(name)
                    ||auxiliary&&![1430,1862,1832].includes(asset.sourceSprite)||names.has(name.toLowerCase()))throw Error('invalid or duplicate native scene asset');
            if(interactive&&(name!=='CF6_Interactive'+(asset.sourceSprite===1939?'Pod':'Barrel')+asset.sourceSprite
                    ||![1736,1838,1976,1939].includes(asset.sourceSprite)||asset.frames!==(asset.sourceSprite===1939?25:16)))throw Error('invalid interactive sprite/frame binding');
            if(transport&&(asset.sourceSprite!==1868||asset.frames!==29||asset.dispatchFrame!==29))throw Error('invalid transport sprite/frame binding');
            names.add(name.toLowerCase());const base='flashswf/backgrounds/cf6/preparation/'+name;
            if(asset.xfl!==base+'/'+name+'.xfl')throw Error('native scene XFL path mismatch');
            const swf='flashswf/backgrounds/cf6/preparation/'+name+'.swf';
            if(asset.swf!==undefined&&asset.swf!==swf)throw Error('native scene SWF path mismatch');
            known.set(swf,asset);if(used.has(swf))selected.push(asset);
        }
        const prefix=transport?'CF6_Transport':interactive?'CF6_Interactive':auxiliary?'CF6_Aux':'CF6_Traversal';
        for(const url of used)if(url.startsWith('flashswf/backgrounds/cf6/preparation/'+prefix)&&!known.has(url))throw Error('runtime native asset absent from manifest: '+url);
        const inputs=tableEntries(manifest.inputs,ref),outputs=tableEntries(manifest.outputs,ref);
        const seedName=transport?'CF6_TransportTextureSeed':interactive?'CF6_InteractiveTextureSeed':'CF6_AuxiliaryTextureSeed';
        const seedBase='flashswf/backgrounds/cf6/preparation/'+seedName;
        const seedRows=inputs.filter(row=>row.path.startsWith(seedBase+'/'));
        if(transport&&(!seedRows.length||!inputs.some(row=>row.path===ORIGINAL_SWF&&row.sha256===manifest.originalSha256)))throw Error('omitted transport original or texture seed binding');
        if(seedRows.length){
            if(!textured||manifest.textureSeed!==seedBase+'/'+seedName+'.xfl')throw Error('invalid native texture seed binding');
            const declared=new Set(seedRows.map(row=>row.path)),doc=seedBase+'/DOMDocument.xml';
            if(!declared.has(doc))throw Error('omitted native texture seed descriptor');
            const allowed=new Set([doc,seedBase+'/bin/SymDepend.cache']);
            for(const item of attributes(read(doc).toString('utf8'),'DOMBitmapItem')){
                const cache=seedBase+'/bin/'+relative(item.bitmapDataHRef);
                if(!declared.has(cache))throw Error('omitted native texture seed cache: '+cache);
                allowed.add(cache);
            }
            for(const row of seedRows)if(!allowed.has(row.path))throw Error('unreviewed native texture seed input: '+row.path);
        }
        for(const row of inputs){
            if(!seedRows.includes(row)&&row.path!=='tools/cf6-prop-layout/scale-policy.json'&&!/^(tools\/(?:cf6-scene-completion|cf6-map-runtime|cf6-map-source|tesla-map-assets)\/|flashswf\/arts\/new\/Codex素材源稿\/CF6地图\/|flashswf\/backgrounds\/cf6\/CF6_A01_BG\/)/.test(row.path)||/\/(?:A07[^/]*|vehicle-art)(?:\/|$)/.test(row.path)||/\/(?:traversal-art-manifest|auxiliary-art-manifest|interactive-art-manifest|transport-art-manifest)\.json$/.test(row.path))throw Error('unreviewed native scene input path');
        }
        const fragments='tools/cf6-scene-completion/'+(transport?'transport-art':interactive?'interactive-art':'auxiliary-art')+'/';
        const selectedNames=new Set(selected.map(a=>a.name));
        const admitted=new Set();
        for(const row of outputs){
            if(!Number.isSafeInteger(row.bytes)||row.bytes<1||/\.swf$/i.test(row.path))throw Error('native output requires exact source size');
            const native=manifest.assets.map(a=>a.name).find(name=>row.path.startsWith('flashswf/backgrounds/cf6/preparation/'+name+'/'));
            const fragment=textured&&manifest.assets.map(a=>a.name).find(name=>row.path.startsWith(fragments+name+'/'));
            const shared=textured&&(row.path.startsWith(fragments+'textures/')||row.path===fragments+'import-textures.jsfl');
            if(!native&&!fragment&&!shared)throw Error('unreviewed native output path: '+row.path);
            if(selectedNames.has(native)||selectedNames.has(fragment)||shared&&selected.length){bound(row,'',ref,'native_scene_output');admitted.add(row.path);}
        }
        if(selected.length)for(const row of inputs)bound(row,'',ref,'native_scene_input');
        for(const asset of selected)nativeClosure(asset.xfl,admitted,ref);
        return selected.length;
    }
    function scenicWings(used){
        for(const url of used)if(url.toLowerCase().startsWith('flashswf/backgrounds/cf6/preparation/cf6_scenic')&&url!==SCENIC_WINGS_SWF)
            throw Error('unreviewed scenic actor runtime resource');
        if(!used.has(SCENIC_WINGS_SWF))return;
        const ref='tools/cf6-scene-completion/scenic-wings-manifest.json',base=SCENIC_WINGS_SWF.slice(0,-4);
        add(ref,SCENIC_WINGS_SWF,'scenic_manifest');const manifest=json(ref);
        if(manifest.schema!=='cf6-scenic-wings.v1'||manifest.originalSha256!==rows.get(ORIGINAL_SWF).sha256
                ||manifest.sourceSprite!==1777||manifest.frames!==15||manifest.swf!==SCENIC_WINGS_SWF
                ||manifest.xfl!==base+'/CF6_ScenicWings.xfl'||!Number.isFinite(manifest.bodyScale)
                ||manifest.bodyScale<=0||manifest.bodyScale>=4||manifest.palette!=='scenic-wings-palette.json'
                ||!Number.isSafeInteger(manifest.bodyColorsReplaced)||manifest.bodyColorsReplaced<1)throw Error('invalid scenic Wings source binding');
        const source='flashswf/arts/new/CodexWings素材/',stand='Codex/Wings/动作/站立';
        const palettePath='tools/cf6-scene-completion/scenic-wings-palette.json';
        const expected=new Set(['tools/cf6-scene-completion/build_scenic_wings.py',palettePath,'tools/cf6-prop-layout/scale-policy.json',
            'tools/cf6-map-runtime/generated/A06-original-geometry.json','tools/cf6-map-runtime/generated/A08-original-geometry.json',
            source+'LIBRARY/Codex/Wings/敌人-CF6Wings.xml',source+'PublishSettings.xml',source+'CodexWings素材.xfl']);
        const inputs=tableEntries(manifest.inputs,ref,128),inputPaths=new Set(inputs.map(row=>row.path));
        const visited=new Set();
        function visit(name){
            name=relative(name);if(!name.startsWith('Codex/Wings/'))throw Error('unreviewed scenic source symbol');
            if(visited.has(name))return;if(visited.size>=128)throw Error('scenic source symbol bound exceeded');visited.add(name);
            const target=source+'LIBRARY/'+name+'.xml';expected.add(target);
            if(!inputPaths.has(target))throw Error('omitted scenic source input: '+target);
            const xml=read(target).toString('utf8');
            for(const item of attributes(xml,'DOMSymbolInstance'))visit(item.libraryItemName);
        }
        visit(stand);
        if(expected.size!==inputPaths.size||[...inputPaths].some(target=>!expected.has(target)))throw Error('extra scenic source input');
        for(const target of expected)if(!inputPaths.has(target))throw Error('omitted scenic source input: '+target);
        for(const row of inputs)bound(row,'',ref,'scenic_source');
        const palette=json(palettePath);
        if(palette.schema!=='cf6-scenic-wings-palette.v1'||palette.originalSwfSha256!==manifest.originalSha256
                ||palette.originalSprite!==1777||!palette.colors||Object.keys(palette.colors).length!==manifest.bodyColorsReplaced)
            throw Error('invalid scenic Wings palette');
        for(const [oldColor,newColor] of Object.entries(palette.colors))
            if(!/^#[0-9A-F]{6}$/.test(oldColor)||!/^#[0-9A-F]{6}$/.test(newColor)||oldColor===newColor)throw Error('invalid scenic Wings palette color');
        for(const row of tableEntries(palette.sources,palettePath,128)){
            if(!row.path.startsWith(source+'LIBRARY/Codex/Wings/分件/')||!inputPaths.has(row.path))throw Error('unreviewed scenic palette source');
            bound(row,'',palettePath,'scenic_palette_source');
        }
        const outputs=tableEntries(manifest.outputs,ref,512),declared=new Set();
        for(const row of outputs){
            if(!row.path.startsWith(base+'/')||/\.swf$/i.test(row.path)||!Number.isSafeInteger(row.bytes)||row.bytes<1)
                throw Error('unreviewed scenic native output');
            bound(row,'',ref,'scenic_native_output');declared.add(row.path);
        }
        nativeClosure(manifest.xfl,declared,ref,{exact:true,visualOnly:true});
    }
    function vehicleAssets(used){
        for(const url of used)if(url.toLowerCase()==='flashswf/arts/cf6vehicle.swf')throw Error('obsolete wrong-location vehicle runtime resource');
        for(const url of used)if((url.toLowerCase().startsWith('flashswf/arts/new/cf6vehicle')
                ||url.toLowerCase().startsWith('flashswf/backgrounds/cf6/cf6_a07'))&&!VEHICLE_ASSETS.some(asset=>asset.swf===url))
            throw Error('unreviewed vehicle runtime resource');
        const selected=VEHICLE_ASSETS.filter(asset=>used.has(asset.swf));if(!selected.length)return;
        const base='tools/cf6-vehicle/',ref=base+'art-manifest.json',texturePath=base+'texture-manifest.json';
        const originalPath=base+'source/original-nodes.json',actionsPath=base+'source/actions.json',redrawPath=base+'redraw-manifest.json',seed=base+'texture-seed/';
        const archive='flashswf/arts/new/Codex素材源稿/CF6地图/',r2=archive+'A07-R2/cf6-stage7-redraw-r2/',r5=archive+'A08-R5/';
        const fixed=[base+'prepare_art.py',base+'extract_source.py',base+'prepare_redraw.py',redrawPath,ORIGINAL_SWF,originalPath,actionsPath,
            ...['build-a01.py','build-a08.py','build-layer.py','procedural_filter.py'].map(name=>'tools/cf6-map-runtime/native-vector/'+name),
            'tools/cf6-map-runtime/build.py','tools/cf6-map-runtime/extract-geometry.py','tools/swf-audit/swfscan.py',
            'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',r5+'reference/vehicles-props-DejaVuSans-Bold.ttf',
            ...['DOMDocument.xml','PublishSettings.xml','CF6_A01_BG.xfl'].map(name=>'flashswf/backgrounds/cf6/CF6_A01_BG/'+name),
            seed+'DOMDocument.xml',seed+'texture-seed.xfl'];
        const requiredExports={'361':'CF6VehicleGrenade','612':'CF6VehicleRaider','627':'CF6VehicleRoadblock','629':'CF6VehicleShield',
            '1791':'CF6VehicleRoad','1803':'CF6VehiclePlayer','1813':'CF6VehicleArmoredBoss',
            '356':'CF6VehicleBullet','115':'CF6VehicleSpark','391':'CF6VehicleExplosion'};
        add(ref,selected[0].swf,'vehicle_manifest');const manifest=json(ref);
        if(manifest.schema!=='cf6-vehicle-art.v1'||E.canonicalJson(manifest.exports)!==E.canonicalJson(requiredExports)
                ||![manifest.nativeSymbols,manifest.sourceNodes,manifest.textures].every(v=>Number.isSafeInteger(v)&&v>0&&v<=4096))
            throw Error('invalid vehicle art manifest');
        const inputRows=tableEntries(manifest.inputs,ref),inputs=new Map(inputRows.map(row=>[row.path,row]));
        for(const target of fixed)if(!inputs.has(target))throw Error('omitted vehicle fixed input: '+target);
        if(inputs.get(ORIGINAL_SWF).sha256!==rows.get(ORIGINAL_SWF).sha256)throw Error('vehicle original source digest mismatch');
        const original=json(originalPath),roots={world:1816,sky:1754,road:1791,player:1803,boss:1813,grenade:361,raider:612,obstacle:627,shield:629,bullet:356,spark:115,explosion:391};
        if(original.schema!=='cf6-vehicle-source.v1'||original.originalSha256!==rows.get(ORIGINAL_SWF).sha256
                ||E.canonicalJson(original.roots)!==E.canonicalJson(roots)||!original.nodes||Array.isArray(original.nodes)
                ||Object.keys(original.nodes).length>4096||Object.values(roots).some(id=>!Object.hasOwn(original.nodes,String(id))))
            throw Error('invalid vehicle original display closure');
        const actions=json(actionsPath),actionPaths=new Set();
        if(!Array.isArray(actions)||!actions.length||actions.length>4096)throw Error('invalid vehicle action source list');
        for(const action of actions){
            if(!action||!digest(action.sha256)||action.capture!=='source/actions/'+action.sha256+'.as.txt'
                    ||typeof action.originalPath!=='string')throw Error('invalid vehicle action source binding');
            if(action.sha256==='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'&&action.originalPath!=='scripts/DefineSprite_1805/frame_2/DoAction.as')
                throw Error('unreviewed empty vehicle action');
            if(!action.originalPath.endsWith('/DoAction.as'))continue;
            const match=/^(?:scripts\/)?DefineSprite_([0-9]+)(?:_[^/]+)?\/frame_([0-9]+)\/DoAction\.as$/.exec(action.originalPath);
            if(!match||!Object.hasOwn(original.nodes,match[1]))throw Error('vehicle action is outside original display closure');
            const target=base+action.capture;
            if(!inputs.has(target)||inputs.get(target).sha256!==action.sha256)throw Error('omitted vehicle action source');
            actionPaths.add(target);
        }
        if(!actionPaths.size)throw Error('missing vehicle timeline action inputs');
        const redraw=json(redrawPath);
        if(redraw.schema!=='cf6-vehicle-redraw.v1')throw Error('invalid vehicle redraw manifest');
        const redrawInputPaths=new Set([base+'prepare_redraw.py',r2+'source/sky_material.py',r2+'source/river_arcade.py',r2+'source/svg_native.py',
            r2+'reference/environment-original-nodes.json',r2+'reference/environment-shape-details.json',r5+'parts/bitmap-1823.svg',r5+'parts/bitmap-1786.svg',
            'tools/cf6-scene-completion/vehicle-art/bitmap-1806.svg','tools/cf6-scene-completion/vehicle-art/bitmap-1808.svg']);
        const redrawNames=['player-body.svg','player-wheel-0.svg','player-wheel-1.svg','armored-body.svg','armored-wheel.svg','asphalt.svg',
            'reference/1784.png','reference/1789.png','parts/bitmap-1784.svg','parts/bitmap-1789.svg','sky.svg','sky-extension.svg'];
        const redrawOutputPaths=new Set(redrawNames.map(name=>base+'source/redraw/'+name));
        const redrawInputs=tableEntries(redraw.inputs,redrawPath),redrawOutputs=tableEntries(redraw.outputs,redrawPath);
        if(redrawInputs.length!==redrawInputPaths.size||redrawInputs.some(row=>!redrawInputPaths.has(row.path))
                ||redrawOutputs.length!==redrawOutputPaths.size||redrawOutputs.some(row=>!redrawOutputPaths.has(row.path)))
            throw Error('unreviewed vehicle redraw inventory');
        for(const row of [...redrawInputs,...redrawOutputs])bound(row,'',redrawPath,'vehicle_redraw');
        const outputs=tableEntries(manifest.outputs,ref),outputMap=new Map(outputs.map(row=>[row.path,row]));
        for(const target of [texturePath,base+'import-textures.jsfl',base+'source/art-timelines.json'])
            if(!outputMap.has(target))throw Error('omitted vehicle shared output: '+target);
        const texture=json(texturePath);
        if(texture.schema!=='cf6-vehicle-texture.v1'||!texture.textures||Array.isArray(texture.textures))throw Error('invalid vehicle texture manifest');
        const textureInputs=tableEntries(texture.inputs,texturePath);
        const shapeInputs=new Set([originalPath,...redrawNames.filter(name=>!name.startsWith('reference/')).map(name=>base+'source/redraw/'+name)]);
        const excluded=new Set([277,281,359,360,501,1433,1434,1497,1498,1585,1793,1795,1804,1805,1816]);
        for(const [id,node] of Object.entries(original.nodes)){
            if(!/^[1-9][0-9]*$/.test(id))throw Error('invalid vehicle source node id');
            if([2,22,32,83].includes(node.code)&&!excluded.has(Number(id)))shapeInputs.add(base+'source/ffdec/'+id+'.svg');
        }
        if(textureInputs.length!==shapeInputs.size||textureInputs.some(row=>!shapeInputs.has(row.path)))throw Error('vehicle texture source inventory mismatch');
        for(const row of textureInputs){
            if(!inputs.has(row.path)||inputs.get(row.path).sha256!==row.sha256)throw Error('omitted or conflicting vehicle texture input');
            bound(row,'',texturePath,'vehicle_texture_source');
        }
        const textures=Object.entries(texture.textures),textureNames=new Set(),textureFiles=new Set();
        if(textures.length!==manifest.textures||!textures.length||textures.length>256)throw Error('vehicle texture count mismatch');
        for(const [identity,item] of textures){
            if(!digest(identity)||item.sha256!==identity||typeof item.name!=='string'
                    ||!new RegExp('^CF6VehicleTexture_'+identity.slice(0,20)+'\\.(?:png|jpg)$').test(item.name)
                    ||textureNames.has(item.name)||!Array.isArray(item.pixels)||item.pixels.length!==2
                    ||!item.pixels.every(v=>Number.isSafeInteger(v)&&v>0&&v<=8192))throw Error('invalid vehicle texture record');
            const target=base+'source/textures/'+item.name,absolute=inside(root,target);
            if(typeof item.path!=='string'||!path.isAbsolute(item.path)
                    ||!origins.some(origin=>path.resolve(item.path)===path.resolve(origin,target)))
                throw Error('vehicle texture absolute path is outside exact repository binding');
            if(!outputMap.has(target)||outputMap.get(target).sha256!==identity)throw Error('omitted vehicle texture output');
            textureNames.add(item.name);textureFiles.add(target);
        }
        const seedPaths=new Set([seed+'DOMDocument.xml',seed+'texture-seed.xfl']),seedNames=new Set();
        for(const item of attributes(read(seed+'DOMDocument.xml').toString('utf8'),'DOMBitmapItem')){
            if(!textureNames.has(item.name)||seedNames.has(item.name))throw Error('vehicle seed texture inventory mismatch');seedNames.add(item.name);
            seedPaths.add(seed+'LIBRARY/'+relative(item.href));seedPaths.add(seed+'bin/'+relative(item.bitmapDataHRef));
        }
        if(seedNames.size!==textureNames.size)throw Error('vehicle seed texture inventory mismatch');
        for(const target of seedPaths)if(!inputs.has(target))throw Error('omitted vehicle seed input: '+target);
        const allowedInputs=new Set([...fixed,...shapeInputs,...seedPaths,...redrawInputPaths,...actionPaths,seed+'bin/SymDepend.cache']);
        for(const row of inputRows){
            if(!allowedInputs.has(row.path))throw Error('unreviewed vehicle input: '+row.path);
            bound(row,'',ref,'vehicle_source');
        }
        const nativeSources=new Map(selected.map(asset=>[asset.xfl,new Set()]));
        for(const row of outputs){
            const asset=VEHICLE_ASSETS.find(a=>row.path.startsWith(path.posix.dirname(a.xfl)+'/'));
            const shared=[texturePath,base+'import-textures.jsfl',base+'source/art-timelines.json'].includes(row.path)||textureFiles.has(row.path);
            if((!asset&&!shared)||/\.swf$/i.test(row.path)||!Number.isSafeInteger(row.bytes)||row.bytes<1)throw Error('unreviewed vehicle output: '+row.path);
            if(shared||nativeSources.has(asset.xfl)){
                bound(row,'',ref,'vehicle_native_output');if(asset)nativeSources.get(asset.xfl).add(row.path);
            }
        }
        for(const asset of selected)nativeClosure(asset.xfl,nativeSources.get(asset.xfl),ref,{exact:true});
        if(used.has(VEHICLE_ASSETS[0].swf)){
            const dir=path.posix.dirname(VEHICLE_ASSETS[0].xfl),includes=attributes(read(dir+'/DOMDocument.xml').toString('utf8'),'Include');
            const exports=[];
            for(const item of includes)for(const symbol of attributes(read(dir+'/LIBRARY/'+relative(item.href)).toString('utf8'),'DOMSymbolItem'))
                if(symbol.linkageExportForAS==='true')exports.push(symbol.linkageIdentifier);
            if(includes.length!==manifest.nativeSymbols||E.canonicalJson(exports.sort())!==E.canonicalJson(['CF6Vehicle',...Object.values(requiredExports)].sort()))
                throw Error('vehicle native export or symbol inventory mismatch');
        }
        add(base+'chapter_fragment.py',ref,'vehicle_chapter_producer');
        const runtimePath=base+'runtime-manifest.json';add(runtimePath,ref,'vehicle_runtime_manifest');
        const runtime=json(runtimePath),runtimeInputs=tableEntries(runtime.inputs,runtimePath),runtimeOutputs=tableEntries(runtime.outputs,runtimePath);
        const expectedInputs=[base+'prepare_runtime.py',originalPath,base+'audio-manifest.json','tools/cf6-scene-completion/Cf6VehicleRules.as.txt',
            ...['ActorAdapter','Combat','Service','Timeline'].map(name=>base+'Cf6Vehicle'+name+'.as.txt')];
        if(runtime.schema!=='cf6-vehicle-runtime.v1'
                ||E.canonicalJson(runtimeInputs.map(r=>r.path).sort())!==E.canonicalJson(expectedInputs.sort())
                ||E.canonicalJson(runtimeOutputs.map(r=>r.path).sort())!==E.canonicalJson([...VEHICLE_CONSUMERS].sort()))
            throw Error('invalid vehicle runtime input/output inventory');
        for(const row of runtimeInputs)bound(row,'',runtimePath,'vehicle_runtime_input');
        for(const row of runtimeOutputs){if(!Number.isSafeInteger(row.bytes)||row.bytes<1)throw Error('invalid vehicle runtime output size');bound(row,'',runtimePath,'vehicle_runtime_output');}
        vehicleAudio(base+'audio-manifest.json');
        for(const target of VEHICLE_CONSUMERS)add(target,ref,'vehicle_consumer');
        sceneConsumers(VEHICLE_CONSUMERS);
    }
    function vehicleAudio(ref){
        const manifest=json(ref),base='tools/cf6-vehicle/';
        const expectedInputs=[base+'prepare_audio.py','tools/cf6-audio/source.py','tools/swf-audit/swfscan.py',ORIGINAL_SWF,'tools/cf6-audio/assets.json'];
        const inputs=tableEntries(manifest.inputs,ref),outputs=tableEntries(manifest.outputs,ref);
        const added=[626,1160,1161,1162,1163,1169],reused=[915,1009,1121,1135,1144,1123,1137,1146,1151,1154,1157];
        const filename=(id,fresh)=> (fresh?'CF6Vehicle_':'CF6_')+String(id).padStart(4,'0')+(fresh&&id>=1160&&id<=1163?'.wav':'.mp3');
        const outputPath=(id,fresh)=>'sounds/export/人物/'+filename(id,fresh);
        if(manifest.schema!=='cf6-vehicle-audio.v1'||manifest.sourceSha256!==rows.get(ORIGINAL_SWF).sha256
                ||E.canonicalJson(inputs.map(r=>r.path).sort())!==E.canonicalJson(expectedInputs.sort())
                ||E.canonicalJson(outputs.map(r=>r.path).sort())!==E.canonicalJson(added.map(id=>outputPath(id,true)).sort()))
            throw Error('invalid vehicle audio input/output inventory');
        for(const row of inputs)bound(row,'',ref,'vehicle_audio_input');
        for(const row of outputs)bound(row,'',ref,'vehicle_audio_output');
        for(const [key,ids,fresh] of [['new',added,true],['reused',reused,false]]){
            if(!Array.isArray(manifest[key])||manifest[key].length!==ids.length)throw Error('invalid vehicle audio source inventory');
            const seen=new Set();
            for(const row of manifest[key]){
                if(!Number.isSafeInteger(row.bytes)||row.bytes<1||!ids.includes(row.soundId)||seen.has(row.soundId)||row.path!==outputPath(row.soundId,fresh)
                        ||row.name!==filename(row.soundId,fresh))throw Error('invalid vehicle audio identity');
                seen.add(row.soundId);bound(row,'',ref,fresh?'vehicle_new_sound':'vehicle_reused_sound');
                if(!fresh)continue;
                const source=row.source,bytes=read(row.path),pcm=row.path.endsWith('.wav');
                if(!source||source.soundId!==row.soundId||!digest(source.bodySha256)||source.codec!==(pcm?3:2)
                        ||!Number.isSafeInteger(source.sampleCount)||source.sampleCount<1)throw Error('invalid vehicle sound source record');
                if(!pcm){if(source.mp3Sha256!==row.sha256||source.mp3Bytes!==bytes.length)throw Error('vehicle MP3 source payload mismatch');continue;}
                if(bytes.length<44||bytes.toString('ascii',0,4)!=='RIFF'||bytes.toString('ascii',8,12)!=='WAVE'
                        ||bytes.readUInt32LE(4)!==bytes.length-8||bytes.toString('ascii',12,16)!=='fmt '||bytes.readUInt32LE(16)!==16
                        ||bytes.readUInt16LE(20)!==1||bytes.readUInt16LE(22)!==source.channels||bytes.readUInt32LE(24)!==source.rate
                        ||bytes.readUInt16LE(34)!==source.bits||bytes.toString('ascii',36,40)!=='data'||bytes.readUInt32LE(40)!==bytes.length-44
                        ||!digest(source.pcmSha256)||crypto.createHash('sha256').update(bytes.subarray(44)).digest('hex')!==source.pcmSha256
                        ||(bytes.length-44)!==source.actualPcmFrames*source.channels*source.bits/8
                        ||source.declaredMinusActualFrames!==source.sampleCount-source.actualPcmFrames)
                    throw Error('vehicle PCM wrapper or source payload mismatch');
            }
        }
        const cueIds={gun:[1169],metal:[1160,1161,1162,1163],raiderDown:[1121,1135,1144],
            raiderDeath:[1123,1137,1146,1151,1154,1157],obstacle:[626],vehicleDeath:[915],explosion:[1009]};
        const cues=Object.fromEntries(Object.entries(cueIds).map(([key,ids])=>[key,ids.map(id=>filename(id,added.includes(id)))]));
        if(E.canonicalJson(manifest.cues)!==E.canonicalJson(cues)||!Array.isArray(manifest.events)||!manifest.events.length||manifest.events.length>32
                ||manifest.events.some(event=>!event||!Object.hasOwn(cues,event.cue)||typeof event.source!=='string'||!event.source
                    ||typeof event.delivery!=='string'||!event.delivery))throw Error('invalid vehicle audio consumer cues');
    }
    function tutorialR7(used){
        if(!used.has('flashswf/backgrounds/cf6/CF6_Tutorial_BG.swf'))return;
        const layout=json('tools/cf6-tutorial/layout.json');
        if(layout.artRevision!=='r7-bold')return;
        const base='tools/cf6-tutorial/',work=base+'r7/',target='flashswf/backgrounds/cf6/CF6_Tutorial_BG/';
        const art='flashswf/arts/new/Codex素材源稿/CF6地图/教程-R7/';
        const source=art+'教程房-R7-bold-全图.svg',archive=art+'CF6-教程摆件-R7-Flash边线对照与源包.zip';
        const ref=base+'provenance.json',manifest=json(ref),conversionRef=work+'conversion.json';
        const recipe='tools/cf6-map-runtime/native-vector/layers/CF6_A01_TutorialR7Textures01/import-textures.jsfl';
        if(manifest.schema!=='cf6-tutorial-assembly.v3'||manifest.artRevision!=='r7-bold'||manifest.mapId!=='TUTORIAL'
                ||manifest.selectedSource!==source||manifest.conversion!==conversionRef||!digest(manifest.sourceArchiveSha256))
            throw Error('invalid R7 tutorial source identity');
        const expected=new Set([source,archive,base+'layout.json',base+'assemble.py',work+'native-media/closure.json']);
        if(!Array.isArray(manifest.sourceInputs)||manifest.sourceInputs.length!==expected.size)throw Error('invalid R7 tutorial source inventory');
        for(const row of manifest.sourceInputs){if(!expected.delete(row.path))throw Error('unexpected R7 tutorial input');bound(row,'',ref,'tutorial_r7_source');}
        if(rows.get(archive).sha256!==manifest.sourceArchiveSha256)throw Error('R7 original archive changed');
        if(!Array.isArray(manifest.outputs)||!manifest.outputs.length||manifest.outputs.length>220)throw Error('invalid R7 output inventory');
        const declared=new Set();let total=0;
        for(const row of manifest.outputs){
            const path=relative(row.path);
            const allowed=path===recipe||[base+'environment.fragment.xml',base+'tutorial-map.fragment.json'].includes(path)
                ||path.startsWith(work)&&/^(?:LIBRARY\/.+\.xml|textures\/intrinsic-[0-9a-f]{24}\.(?:png|jpg)|timeline\.xml|conversion\.json)$/.test(path.slice(work.length))
                ||path.startsWith(target)&&/^(?:LIBRARY\/.+\.(?:xml|png|jpg)|bin\/M [0-9]+ [0-9]+\.dat|DOMDocument\.xml|PublishSettings\.xml|CF6_Tutorial_BG\.xfl)$/.test(path.slice(target.length));
            if(!allowed||declared.has(path))throw Error('unexpected or duplicate R7 output');
            bound(row,'',ref,'tutorial_r7_generated');declared.add(path);total+=row.bytes;
        }
        if(total>16*1024*1024||!declared.has(conversionRef))throw Error('R7 content size or conversion binding invalid');
        const conversion=json(conversionRef);
        if(conversion.schema!=='cf6-tutorial-r7-native.v1'||conversion.source!==source||conversion.selectedOutline!=='bold'
                ||conversion.sourceSha256!==rows.get(source).sha256)throw Error('R7 conversion source mismatch');
        const producers=new Set([base+'r7.py','tools/cf6-map-runtime/native-vector/build-a01.py',
            'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py','tools/cf6-map-runtime/build.py']);
        if(!Array.isArray(conversion.generatorInputs)||conversion.generatorInputs.length!==producers.size)throw Error('R7 producer inventory invalid');
        for(const row of conversion.generatorInputs){if(!producers.delete(row.path))throw Error('unexpected R7 producer');bound(row,'',conversionRef,'tutorial_r7_producer');}
        const cacheRef=work+'native-media/closure.json',cache=json(cacheRef);
        if(cache.schema!=='cf6-tutorial-r7-native-media.v1'||!Array.isArray(cache.files)||cache.files.length<3||cache.files.length>16)throw Error('R7 native cache inventory invalid');
        const caches=new Set();
        for(const row of cache.files){
            if(typeof row.path!=='string'||!/^(?:DOMDocument\.xml|LIBRARY\/intrinsic-[0-9a-f]{24}\.(?:png|jpg)|bin\/M [0-9]+ [0-9]+\.dat)$/.test(row.path)||caches.has(row.path))throw Error('unexpected R7 native cache path');
            caches.add(row.path);bound(row,work+'native-media/',cacheRef,'tutorial_r7_native_cache');
        }
        if(!caches.has('DOMDocument.xml'))throw Error('R7 native cache descriptor omitted');
        nativeClosure(target+'CF6_Tutorial_BG.xfl',new Set([...declared].filter(path=>path.startsWith(target))),ref);
    }
    function propSources(used){
        const base='tools/cf6-prop-layout/',recipePath=base+'recipe.json',depthPath=base+'depth-recipe.json';
        const recipe=json(recipePath),depth=json(depthPath);
        if(recipe.schema!=='cf6-prop-calibration-recipe.v1'||!Array.isArray(recipe.instances)||!recipe.instances.length||recipe.instances.length>1024
                ||depth.schema!=='cf6-depth-prop-exclusions.v1'||typeof depth.enabled!=='boolean'||!Array.isArray(depth.groups))throw Error('invalid prop recipes');
        const ids=new Map(),selectors=new Set(),pins=new Map(),parents=new Map();
        for(const item of recipe.instances){
            if(typeof item.id!=='string'||ids.has(item.id)||!/^flashswf\/backgrounds\/cf6\/CF6_(?:Tutorial|A\d{2})_BG$/.test(item.xflDirectory)
                    ||typeof item.parentFile!=='string'||!/^LIBRARY\/.+\.xml$/.test(item.parentFile)||!Number.isSafeInteger(item.instanceIndex)||item.instanceIndex<0
                    ||typeof item.symbol!=='string'||!item.symbol||!Number.isFinite(item.localVisualScale)||item.localVisualScale<=0
                    ||!Array.isArray(item.pivotNative)||item.pivotNative.length!==2||!item.pivotNative.every(Number.isFinite))throw Error('invalid or duplicate calibrated instance');
            const selector=item.xflDirectory+'/'+relative(item.parentFile)+'#'+item.instanceIndex;
            if(selectors.has(selector))throw Error('duplicate calibrated instance selector');selectors.add(selector);ids.set(item.id,item);
            if(typeof item.baseline!=='string'||!/^baselines\/[^/]+\.xml$/.test(item.baseline))throw Error('unreviewed prop baseline path');
            const ref=relative(base+item.baseline);
            if(pins.has(ref)&&pins.get(ref)!==item.baselineSha256)throw Error('conflicting prop baseline digest');pins.set(ref,item.baselineSha256);
            bound({path:ref,sha256:item.baselineSha256},'',recipePath,'prop_baseline');
            const instance=attributes(read(ref).toString('utf8'),'DOMSymbolInstance')[item.instanceIndex];
            if(!instance||instance.libraryItemName!==item.symbol)throw Error('prop baseline selector mismatch');
            const current=relative(item.xflDirectory+'/'+item.parentFile);add(current,recipePath,'calibrated_background');read(current);
            const originalNames=attributes(read(ref).toString('utf8'),'DOMSymbolInstance').map(n=>n.libraryItemName);
            if(parents.has(current)&&E.canonicalJson(parents.get(current))!==E.canonicalJson(originalNames))throw Error('conflicting background parent baselines');parents.set(current,originalNames);
        }
        const manifestPath=base+'generated/depth-props-manifest.json';add(manifestPath);const manifest=json(manifestPath);
        if(manifest.schema!=='cf6-native-depth-props.v1'||!Array.isArray(manifest.groups)||manifest.groups.length>32)throw Error('invalid depth prop manifest');
        const groups=new Map(),groupNames=new Set(),memberSet=new Set();
        for(const group of manifest.groups){
            const name=group.name,dir='flashswf/backgrounds/cf6/props/'+name;
            if(typeof name!=='string'||!/^CF6_Prop_[A-Za-z0-9_]+$/.test(name)||groupNames.has(name.toLowerCase())||group.xfl!==dir+'/'+name+'.xfl'||group.swf!==dir+'.swf'
                    ||!Array.isArray(group.files)||!group.files.length||group.files.length>2048||!Array.isArray(group.memberIds)||!group.memberIds.length)throw Error('invalid or duplicate depth prop group');
            groups.set(name,group);groupNames.add(name.toLowerCase());
            for(const id of group.memberIds){if(!ids.has(id)||memberSet.has(id))throw Error('unknown or duplicate depth prop member');memberSet.add(id);}
            const seen=new Set();
            for(const row of group.files){
                const ref=relative(row.path);if(!ref.startsWith(dir+'/')||/\.swf$/i.test(ref)||seen.has(ref.toLowerCase())||!Number.isSafeInteger(row.bytes)||row.bytes<1)throw Error('invalid or duplicate depth source file');seen.add(ref.toLowerCase());
            }
            if(used.has(group.swf)){
                const declared=new Set();for(const row of group.files){bound(row,'',manifestPath,'depth_prop_source');declared.add(relative(row.path));}
                nativeClosure(group.xfl,declared,manifestPath);
            }
        }
        for(const url of used)if(url.startsWith('flashswf/backgrounds/cf6/props/')&&![...groups.values()].some(g=>g.swf===url))throw Error('unbound depth prop runtime resource');
        const active=new Set();
        for(const group of depth.groups){
            const declared=groups.get(group.name);
            if(active.has(group.name)||!declared||group.swf!==declared.swf||!Array.isArray(group.memberIds)
                    ||E.canonicalJson(group.memberIds)!==E.canonicalJson(declared.memberIds))throw Error('depth exclusions do not match extracted source');
            active.add(group.name);if(depth.enabled&&!used.has(group.swf))throw Error('background prop excluded without runtime consumer');
        }
        for(const group of groups.values())if(used.has(group.swf)&&(!depth.enabled||!active.has(group.name)))throw Error('depth runtime prop still duplicated in background recipe');
        const removed=new Map();
        if(depth.enabled)for(const group of depth.groups)for(const id of group.memberIds){
            const item=ids.get(id),parent=item.xflDirectory+'/'+item.parentFile;
            if(!removed.has(parent))removed.set(parent,new Set());removed.get(parent).add(item.instanceIndex);
        }
        for(const [parent,names] of parents){
            const expected=names.filter((_name,index)=>!removed.get(parent)?.has(index));
            const actual=attributes(read(parent).toString('utf8'),'DOMSymbolInstance').map(n=>n.libraryItemName);
            if(E.canonicalJson(expected)!==E.canonicalJson(actual))throw Error('calibrated background instance inventory mismatch: '+parent);
        }

    }
    function sceneConsumers(extra=[]){
        const base='scripts/类定义/org/flashNight/arki/scene/',queue=[...FILES.filter(p=>p.startsWith(base)&&/\/Cf6[^/]+\.as$/.test(p)),...extra],seen=new Set();
        while(queue.length){const ref=queue.shift();if(seen.has(ref))continue;seen.add(ref);if(seen.size>64)throw Error('CF6 consumer dependency bound exceeded');
            const source=read(ref).toString('utf8').replace(/\/\*[\s\S]*?\*\/|\/\/[^\r\n]*/g,'');
            for(const match of source.matchAll(/\borg\.flashNight\.arki\.scene\.(Cf6[A-Za-z0-9_]+)\b/g)){
                const child=base+match[1]+'.as';if(child!==ref)add(child,ref,'cf6_scene_consumer');queue.push(child);
            }
        }
    }
    function scaleSources(){
        const ref='tools/cf6-prop-layout/scale-policy.json',policy=json(ref);
        const types=['敌人-CF6普通男僵尸','敌人-CF6女僵尸','敌人-CF6Wings','敌人-CF6特种兵',
            '敌人-CF6持盾特种兵','敌人-CF6光头保安','敌人-CF6变身光头保安'];
        if(policy.schema!=='cf6-local-scale-policy.v1'||!Array.isArray(policy.humanoids)
            ||E.canonicalJson(policy.humanoids.map(row=>row.linkage))!==E.canonicalJson(types))throw Error('invalid bounded CF6 body scale source set');
        for(const body of policy.humanoids){
            const entries=Object.entries(body.nativeSources||{});
            if(!entries.length||entries.length>128)throw Error('invalid native body source count');
            for(const [raw,sha256] of entries){const target=relative(raw);
                if(!/^flashswf\/arts\/new\/(?:Antigravity专用素材|CodexWings素材|Codex特种兵素材|Codex光头保安素材)\/LIBRARY\/.+\.xml$/.test(target))
                    throw Error('unreviewed native body measurement input');
                bound({path:target,sha256},'',ref,'native_body_measurement');
            }
        }
    }
    function portraitSources(chapter){
        const chars=new Set(chapter.maps.flatMap(m=>(m.dialogue||[]).map(line=>line.char).filter(Boolean)));
        if(!chars.size)return;
        const base='launcher/web/assets/dialogue-portraits/',ref=base+'manifest.json';
        add(ref,route.chapterPath,'dialogue_catalog');const catalog=json(ref);
        for(const char of chars){
            if(typeof char!=='string'||!/^Andy Law#[^#]{1,12}$/.test(char))throw Error('unreviewed CF6 dialogue portrait');
            const expression=char.slice(9),asset=catalog.entries?.['Andy Law']?.expressions?.[expression];
            if(!asset||!/^external\/p_[a-f0-9]+\/e_[a-f0-9]+\.webp$/.test(asset.uri))throw Error('missing exact CF6 dialogue expression');
            bound({path:asset.uri,sha256:asset.sha256,bytes:asset.bytes},base,ref,'dialogue_expression');
        }
    }
    FILES.forEach(ref=>add(ref));
    for(const name of ['route-config.js','preflight.js','affiliated-slot.js','run-candidate.js','cdp-input-channel.js','passive-observer.js','source-closure.js','verified-return-observation.js'])
        add('tools/cf6-live-e2e/'+name);
    if(route.id==='type61')TYPE61_FILES.forEach(ref=>add(ref));
    const chapterPath=route.chapterPath;
    const chapter=JSON.parse(read(chapterPath).toString('utf8').replace(/^\uFEFF/,''));
    chapterResources(chapter,route.id).forEach(ref=>add(ref,chapterPath,'chapter_resource'));
    comicAssets();turretAssets();
    scaleSources();portraitSources(chapter);
    const used=new Set(chapterResources(chapter,route.id));
    tutorialR7(used);
    sceneConsumers();
    sceneManifest('tools/cf6-scene-completion/traversal-art-manifest.json','cf6-traversal-native-source.v1',used,false);
    sceneManifest('tools/cf6-scene-completion/auxiliary-art-manifest.json','cf6-auxiliary-native-source.v1',used,true);
    sceneManifest('tools/cf6-scene-completion/interactive-art-manifest.json','cf6-interactive-native-source.v1',used,'interactive');
    sceneManifest('tools/cf6-scene-completion/transport-art-manifest.json','cf6-transport-native-source.v1',used,'transport');
    scenicWings(used);
    vehicleAssets(used);
    propSources(used);
    const cameraPath='tools/cf6-prototype/generated/original-camera-layout.json';
    const camera=JSON.parse(read(cameraPath).toString('utf8').replace(/^\uFEFF/,''));
    if(camera.schema!=='cf6-original-camera-layout.v1'||!Array.isArray(camera.maps)||!camera.maps.length||camera.maps.length>32)
        throw Error('invalid original CF6 camera source manifest');
    for(const row of camera.maps)for(const [field,hashField] of [['geometryPath','geometrySha256'],['decodedLoad','decodedLoadSha256']]){
        const ref=relative(row[field]);
        if(!/^[0-9a-f]{64}$/.test(row[hashField]))throw Error('invalid original camera source digest');
        add(ref,cameraPath,'camera_source');read(ref);
        if(rows.get(ref).sha256!==row[hashField])throw Error('original camera source changed: '+ref);
    }
    const mechanism='scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as';
    const literalUrls=[...read(mechanism).toString('utf8').matchAll(/["'](flashswf[\\/][^"'\r\n]+\.swf)["']/g)].map(m=>relative(m[1]));
    if(chapter.maps.some(m=>m.id==='A20')&&!literalUrls.some(p=>/CF6_A21_Transform\.swf$/.test(p)))
        throw Error('A20 cinematic resource no longer has its explicit closed source binding');
    literalUrls.filter(ref=>ref!==SCENIC_WINGS_SWF&&!VEHICLE_ASSETS.some(asset=>asset.swf===ref)||used.has(ref)).forEach(ref=>add(ref,mechanism,'runtime_literal'));
    for(const [list,base,tags] of LISTS){
        add(list);for(const child of listReferences(read(list).toString('utf8'),tags))add(base+'/'+child,list,'list_reference');
    }
    const processed=new Set();
    while(processed.size<pending.size){
        const ref=[...pending].filter(p=>!processed.has(p)).sort()[0];processed.add(ref);
        const bytes=read(ref);
        if(ref.endsWith('BookshelfPanelService.as')&&!bytes.toString('utf8').includes('openBookshelfForAgent'))
            throw Error('AS2 fixed opener patch has not been applied');
        if(/\.swf$/i.test(ref))for(const imp of Swf.parseSwf(bytes).imports)add(resolveImport(root,ref,imp.url),ref,'swf_import');
    }
    const files=[...rows.values()].sort((a,b)=>a.relativePath<b.relativePath?-1:a.relativePath>b.relativePath?1:0);
    const dependencies=[...new Map(edges.map(e=>[E.canonicalJson(e),e])).values()].sort((a,b)=>{
        const x=E.canonicalJson(a),y=E.canonicalJson(b);return x<y?-1:x>y?1:0;
    });
    const value={schema:'cf7-cf6-e2e.source-closure.v2',routeId:route.id,textureOriginRoots:origins,files,dependencies};
    value.closureSha256=E.sha256Text(E.canonicalJson(value));
    return value;
}
function verify(value){
    if(!value||value.schema!=='cf7-cf6-e2e.source-closure.v2'||!Array.isArray(value.files)||!value.files.length||!Array.isArray(value.dependencies))
        throw Error('invalid CF6 source closure');
    resolveRoute(value.routeId);
    const {closureSha256,...body}=value;
    if(closureSha256!==E.sha256Text(E.canonicalJson(body)))throw Error('CF6 source closure digest mismatch');
    return value;
}
function assertUnchanged(before,after) {
    verify(before);verify(after);
    if (before.closureSha256!==after.closureSha256)
        throw Error('CF6 sources or runtime resources changed during the journey');
    return true;
}
module.exports={TYPE61_FILES,capture,assertUnchanged,verify,FILES,LISTS,relative,listReferences,chapterResources,resolveImport,ORIGINAL_SWF,SCENIC_WINGS_SWF,VEHICLE_ASSETS,VEHICLE_CONSUMERS};
