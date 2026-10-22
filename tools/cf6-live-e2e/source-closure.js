'use strict';
const fs = require('fs'), path = require('path');
const E = require('../workbench-live-e2e/lib/evidence-artifact');
const Swf = require('../swf-metadata');
const ORIGINAL_SWF='flashswf/arts/new/Codex素材源稿/CF6地图/原作参考/crazyflasher6-cn.swf';
const FILES = [
    'flashswf/arts/new/Codex素材源稿/CF6地图/原作参考/source-manifest.json',
    'automation/start.ps1','launcher/src/Tasks/AgentControlTask.cs','launcher/src/Program.cs',
    'launcher/src/Tasks/BookshelfTask.cs','launcher/src/FixedWebViewRuntime.cs','launcher/webview2-runtime.lock.json',
    'scripts/类定义/org/flashNight/arki/ui/BookshelfPanelService.as',
    'scripts/类定义/org/flashNight/arki/scene/BookRunService.as',
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
    'tools/cf6-prototype/viewport-policy.json','tools/cf6-prototype/viewport-assembly.py',
    'tools/cf6-prototype/generated/original-camera-layout.json',
    'tools/cf6-prototype/generated/assembly.json','tools/cf6-roguelike-content/build-sting-fragments.py',
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
function chapterResources(chapter) {
    if(chapter?.id!=='cf6-sting'||chapter.routeId!=='historical'||!Array.isArray(chapter.maps)||!chapter.maps.length)
        throw Error('closure requires the installed historical chapter');
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
function capture(root) {
    root=E.assertExactDirectory(path.resolve(root),'cf6_closure');
    const pending=new Set(),folded=new Map(),rows=new Map(),edges=[];
    function add(ref,owner,kind){
        ref=relative(ref);inside(root,ref);
        const key=ref.toLowerCase();if(folded.has(key)&&folded.get(key)!==ref)throw Error('case-aliased closure resource: '+ref);
        folded.set(key,ref);pending.add(ref);
        if(pending.size>4096)throw Error('closure resource count exceeded');
        if(owner)edges.push({owner,target:ref,kind});return ref;
    }
    function read(ref){
        // CS6 creates this optional sidecar as an empty regular file for desktop XFLs.
        // Keep its exact bytes/hash in the closure; required source and asset files stay nonempty.
        const allowEmpty=ref==='flashswf/backgrounds/cf6/CF6_A01_Turret/MobileSettings.xml';
        const file=E.readExactRegularFile(inside(root,ref),{phase:'cf6_closure',maximumBytes:128*1024*1024,allowEmpty});
        const row={relativePath:ref,bytes:file.length,sha256:file.sha256};
        if(rows.has(ref)&&rows.get(ref).sha256!==row.sha256)throw Error('closure resource changed during discovery');
        rows.set(ref,row);return file.bytes;
    }
    const json=ref=>JSON.parse(read(ref).toString('utf8').replace(/^\uFEFF/,''));
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
    FILES.forEach(ref=>add(ref));
    const chapterPath='data/stages/books/cf6-sting.runtime.json';
    const chapter=JSON.parse(read(chapterPath).toString('utf8').replace(/^\uFEFF/,''));
    chapterResources(chapter).forEach(ref=>add(ref,chapterPath,'chapter_resource'));
    comicAssets();turretAssets();
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
    literalUrls.forEach(ref=>add(ref,mechanism,'runtime_literal'));
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
    const value={schema:'cf7-cf6-e2e.source-closure.v2',files,dependencies};
    value.closureSha256=E.sha256Text(E.canonicalJson(value));
    return value;
}
function verify(value){
    if(!value||value.schema!=='cf7-cf6-e2e.source-closure.v2'||!Array.isArray(value.files)||!value.files.length||!Array.isArray(value.dependencies))
        throw Error('invalid CF6 source closure');
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
module.exports={capture,assertUnchanged,verify,FILES,LISTS,relative,listReferences,chapterResources,resolveImport,ORIGINAL_SWF};
