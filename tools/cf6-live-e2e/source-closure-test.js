#!/usr/bin/env node
'use strict';
const assert=require('assert'),fs=require('fs'),os=require('os'),path=require('path');
const C=require('./source-closure');
const E=require('../workbench-live-e2e/lib/evidence-artifact');
const crypto=require('crypto');
let passed=0;
function test(name,fn){fn();passed++;console.log('PASS '+name);}
function swf(url){
    const tags=[];
    if(url){const body=Buffer.concat([Buffer.from(url+'\0'),Buffer.from([1,0,0,0])]);
        const header=Buffer.alloc(6);header.writeUInt16LE((71<<6)|63);header.writeUInt32LE(body.length,2);tags.push(header,body);}
    const body=Buffer.concat([Buffer.from([8,0,0,30,1,0]),...tags,Buffer.from([0,0])]);
    const header=Buffer.alloc(8);header.write('FWS');header[3]=8;header.writeUInt32LE(body.length+8,4);return Buffer.concat([header,body]);
}
const parent=fs.realpathSync.native(os.tmpdir()),root=fs.mkdtempSync(path.join(parent,'cf7-cf6-closure-fixture-'));
const write=(ref,value)=>{const file=path.join(root,ref);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,value);};
const chapter={id:'cf6-sting',routeId:'historical',maps:[{id:'A20',background:'cf6/base.swf',
    stage:{Instances:[{url:'flashswf/object.swf'}]},mechanism:{layers:[{url:'flashswf/overlay.swf'},{url:'flashswf/backgrounds/cf6/preparation/CF6_Traversal1720_Back.swf'},{url:'flashswf/backgrounds/cf6/preparation/CF6_AuxDoor1430.swf'},{url:'flashswf/backgrounds/cf6/props/CF6_Prop_Fixture.swf'}]}},
    {id:'A01',background:'cf6/base.swf',mechanism:{turrets:{assetUrl:'flashswf/backgrounds/cf6/CF6_A01_Turret.swf'}}}]};
const chapterPath='data/stages/books/cf6-sting.runtime.json',mechanism='scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as';
const comicBase='launcher/web/assets/book-comic/cf6/',comicSource='flashswf/arts/new/Codex素材源稿/CF6漫画过场/';
const turretBase='flashswf/arts/new/Codex素材源稿/CF6教学炮塔/',xflBase='flashswf/backgrounds/cf6/CF6_A01_Turret';
const comicManifest=comicBase+'manifest.json',comicAudit=comicBase+'integrity-audit.json';
const contentPath='tools/cf6-story-migration/generated/cf6-web-content.json';
const contentJs='launcher/web/modules/book-comic-cf6-content.js';
const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
const parse=ref=>JSON.parse(fs.readFileSync(path.join(root,ref),'utf8'));
const put=(ref,value)=>write(ref,JSON.stringify(value));
function declared(ref,name=ref){const bytes=fs.readFileSync(path.join(root,ref));return {path:name,bytes:bytes.length,sha256:hash(bytes)};}
const sceneBase='tools/cf6-scene-completion/',propBase='tools/cf6-prop-layout/';
const traversalManifest=sceneBase+'traversal-art-manifest.json',auxManifest=sceneBase+'auxiliary-art-manifest.json',interactiveManifest=sceneBase+'interactive-art-manifest.json',transportManifest=sceneBase+'transport-art-manifest.json';
const depthManifest=propBase+'generated/depth-props-manifest.json',propRecipe=propBase+'recipe.json';
const parentXml='flashswf/backgrounds/cf6/CF6_A05_BG/LIBRARY/parent.xml';
function nativeFixture(name,folder){
    const base='flashswf/backgrounds/cf6/'+folder+'/'+name;
    const doc='<DOMDocument><symbols><Include href="one.xml"/></symbols><timelines><DOMSymbolInstance libraryItemName="one"/></timelines></DOMDocument>';
    write(base+'/DOMDocument.xml',doc);write(base+'/PublishSettings.xml','<settings/>');write(base+'/'+name+'.xfl','PROXY-CS5');
    write(base+'/LIBRARY/one.xml','<DOMSymbolItem name="one"><timeline/></DOMSymbolItem>');write(base+'.swf',swf());
    const files=['DOMDocument.xml','PublishSettings.xml',name+'.xfl','LIBRARY/one.xml'].map(p=>declared(base+'/'+p));
    return {name,xfl:base+'/'+name+'.xfl',swf:base+'.swf',files};
}
function restoreSceneAssets(){
    const measured='flashswf/arts/new/Antigravity专用素材/LIBRARY/body-measurement.xml';write(measured,'native body');
    put(propBase+'scale-policy.json',{schema:'cf6-local-scale-policy.v1',humanoids:
        ['敌人-CF6普通男僵尸','敌人-CF6女僵尸','敌人-CF6Wings','敌人-CF6特种兵','敌人-CF6持盾特种兵','敌人-CF6光头保安','敌人-CF6变身光头保安']
            .map(linkage=>({linkage,nativeSources:{[measured]:hash('native body')}}))});
    const input=sceneBase+'fixture-source.svg';write(input,'fixture native source');
    for(const [manifestPath,schema,names] of [
        [traversalManifest,'cf6-traversal-native-source.v1',['CF6_Traversal1720_Back','CF6_Traversal1750_Front']],
        [auxManifest,'cf6-auxiliary-native-source.v1',['CF6_AuxDoor1430','CF6_AuxCamera1832']],
        [interactiveManifest,'cf6-interactive-native-source.v1',['CF6_InteractiveBarrel1736','CF6_InteractivePod1939']],
        [transportManifest,'cf6-transport-native-source.v1',['CF6_Transport1868']]]){
        const assets=names.map(name=>nativeFixture(name,'preparation'));const outputs={};
        for(const asset of assets)for(const file of asset.files)outputs[file.path]={sha256:file.sha256,bytes:file.bytes};
        put(manifestPath,{schema,originalSha256:hash(swf()),inputs:{[input]:hash('fixture native source')},assets:assets.map(a=>({name:a.name,xfl:a.xfl,swf:a.swf,
            frames:a.name.includes('1868')?29:a.name.includes('1939')?25:16,dispatchFrame:a.name.includes('1868')?29:undefined,sourceSprite:a.name.includes('1868')?1868:a.name.includes('1939')?1939:a.name.includes('1736')?1736:a.name.includes('1430')?1430:a.name.includes('1832')?1832:a.name.includes('1720')?1720:1750})),outputs});
    }
    const seed='flashswf/backgrounds/cf6/preparation/CF6_TransportTextureSeed';
    const doc=seed+'/DOMDocument.xml',cache=seed+'/bin/M 1 1792735894.dat',dep=seed+'/bin/SymDepend.cache';
    write(doc,'<DOMDocument><media><DOMBitmapItem name="seed" href="texture.png" bitmapDataHRef="M 1 1792735894.dat"/></media></DOMDocument>');
    write(cache,'transport seed');write(dep,'transport dependencies');
    const transport=parse(transportManifest);transport.textureSeed=seed+'/CF6_TransportTextureSeed.xfl';
    for(const ref of [doc,cache,dep,C.ORIGINAL_SWF])transport.inputs[ref]=declared(ref).sha256;
    for(const ref of [sceneBase+'transport-art/CF6_Transport1868/fragment.xml',sceneBase+'transport-art/textures/grain.png',sceneBase+'transport-art/import-textures.jsfl']){
        write(ref,'transport fragment');transport.outputs[ref]=declared(ref);
    }
    put(transportManifest,transport);
    const baseline='<DOMSymbolItem><timeline><DOMSymbolInstance libraryItemName="Fixture/Statue"><matrix><Matrix a="1" d="1"/></matrix></DOMSymbolInstance></timeline></DOMSymbolItem>';
    write(propBase+'baselines/fixture.xml',baseline);write(parentXml,'<DOMSymbolItem><timeline/></DOMSymbolItem>');
    put(propRecipe,{schema:'cf6-prop-calibration-recipe.v1',instances:[{id:'fixture-prop',mapId:'A05',xflDirectory:'flashswf/backgrounds/cf6/CF6_A05_BG',parentFile:'LIBRARY/parent.xml',instanceIndex:0,symbol:'Fixture/Statue',baseline:'baselines/fixture.xml',baselineSha256:hash(baseline),localVisualScale:.5,pivotNative:[0,10]}]});
    const resource=nativeFixture('CF6_Prop_Fixture','props');resource.memberIds=['fixture-prop'];
    put(depthManifest,{schema:'cf6-native-depth-props.v1',groups:[resource]});
    put(propBase+'depth-recipe.json',{schema:'cf6-depth-prop-exclusions.v1',enabled:true,groups:[{name:resource.name,swf:resource.swf,memberIds:resource.memberIds}]});
}
function restoreAssets(){
    const original=C.ORIGINAL_SWF;write(original,swf());
    const originalHash=hash(swf());
    const fragment='tools/cf6-story-migration/generated/comic-story.fragment.json';
    const index='tools/cf6-story-migration/generated/cf6-story-index.extracted.json';
    put(fragment,{source:{sha256:originalHash}});put(index,{});put(comicSource+'MANIFEST.json',{});
    const producer='tools/cf6-story-migration/build_cf6_web_content.py';write(producer,'fixture producer');
    const payloadNames=['cf6-s1/comic.svg','cf6-s1/narration.mp3'];
    for(const name of payloadNames){write(comicSource+name,'fixture '+name);write(comicBase+name,'fixture '+name);}
    const binding={fragment:declared(fragment),index:declared(index),assetManifest:declared(comicSource+'MANIFEST.json'),
        originalSwfSha256:originalHash,scripts:[declared(producer)],assets:payloadNames.map(name=>declared(comicSource+name,name))};
    const bindingHash=E.sha256Text(E.canonicalJson(binding));
    const content={schema:'cf6-book-comic-web-content.v1',sourceBindingSha256:bindingHash,
        pages:[{id:'cf6-s1',image:'assets/book-comic/cf6/cf6-s1/comic.svg',audio:{narration:'assets/book-comic/cf6/cf6-s1/narration.mp3'}}]};
    put(contentPath,content);write(contentJs,'window.BOOK_COMIC_CF6_CONTENT = '+JSON.stringify(content)+';');
    const files=payloadNames.map(name=>declared(comicBase+name,name));
    const manifest={schema:'cf6-book-comic-runtime-manifest.v1',sourceBindingSha256:bindingHash,sourceBinding:binding,
        files,fileCount:files.length,totalBytes:files.reduce((a,b)=>a+b.bytes,0)};put(comicManifest,manifest);
    put(comicAudit,{schema:'cf6-book-comic-integrity-audit.v1',sourceBindingSha256:bindingHash,
        runtimePayload:files,fileCount:files.length,totalBytes:manifest.totalBytes,
        generatedOutputs:[...payloadNames.map(name=>declared(comicBase+name)),declared(contentPath),declared(contentJs),declared(comicManifest)]});
    write(turretBase+'raw-tags/tag-1.bin','fixture raw tag');write(turretBase+'bitmaps/fixture.png','fixture bitmap');
    put(turretBase+'manifest.json',{schema:'cf6-turret-native-tags.v2',sourceSwfSha256:originalHash,
        tags:{1:{file:'raw-tags/tag-1.bin',length:15,sha256:hash('fixture raw tag')}}});
    put('tools/cf6-tutorial-turrets/generated/geometry-r14.json',{schema:'cf6-turret-geometry.v1',sourceSwfSha256:originalHash,
        media:{'fixture.png':{bytes:14,sha256:hash('fixture bitmap')}}});
    put('tools/cf6-tutorial-turrets/tutorial-turrets.fragment.json',{schema:'cf6-tutorial-turrets.v1',sourceSwf:declared(original)});
    for(const name of ['CF6_A01_Turret.xfl','DOMDocument.xml','PublishSettings.xml','LIBRARY/fixture.xml','bin/native.dat'])write(xflBase+'/'+name,'fixture source '+name);
    write(xflBase+'/MobileSettings.xml','');
    write('flashswf/backgrounds/cf6/CF6_A01_Turret.swf',swf());
    restoreSceneAssets();
}
try{
    C.FILES.forEach(ref=>write(ref,/\.swf$/i.test(ref)?swf():Buffer.from('fixture openBookshelfForAgent')));
    restoreAssets();
    write(chapterPath,JSON.stringify(chapter));write(mechanism,'var cutscene="flashswf/backgrounds/cf6/CF6_A21_Transform.swf";');
    const cameraSource='tools/cf6-map-runtime/generated/fixture-camera.as';
    const cameraGeometry='tools/cf6-map-runtime/generated/fixture-geometry.json';
    const cameraPath='tools/cf6-prototype/generated/original-camera-layout.json';
    const cameraHash=crypto.createHash('sha256').update('fixture camera').digest('hex');
    const camera={schema:'cf6-original-camera-layout.v1',maps:[{id:'A20',geometryPath:cameraGeometry,
        geometrySha256:cameraHash,decodedLoad:cameraSource,decodedLoadSha256:cameraHash}]};
    write(cameraSource,'fixture camera');write(cameraGeometry,'fixture camera');write(cameraPath,JSON.stringify(camera));
    for(const [list,base,tags] of C.LISTS){write(list,'<root><'+tags[0]+'>fixture.json</'+tags[0]+'></root>');write(base+'/fixture.json','{}');}
    for(const ref of ['flashswf/backgrounds/cf6/base.swf','flashswf/object.swf','flashswf/overlay.swf','flashswf/backgrounds/cf6/CF6_A21_Transform.swf'])write(ref,swf());
    write('flashswf/object.swf',swf('nested/child.swf'));write('flashswf/nested/child.swf',swf('../leaf.swf'));write('flashswf/leaf.swf',swf());
    let baseline;
    test('closure includes layers, source-bound A21, XML children and recursive SWF imports',()=>{
        baseline=C.capture(root);C.verify(baseline);const names=new Set(baseline.files.map(x=>x.relativePath));
        for(const ref of ['flashswf/overlay.swf','flashswf/backgrounds/cf6/CF6_A21_Transform.swf','flashswf/nested/child.swf','flashswf/leaf.swf','data/shops/fixture.json'])assert(names.has(ref),ref);
        assert(baseline.dependencies.some(x=>x.owner==='flashswf/nested/child.swf'&&x.target==='flashswf/leaf.swf'));
    });
    test('unchanged captures have deterministic digest',()=>assert(C.assertUnchanged(baseline,C.capture(root))));
    test('new consumers, turret assetUrl and actual XFL input tree are bound',()=>{
        const names=new Set(baseline.files.map(row=>row.relativePath));
        for(const ref of ['scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretService.as',
            'scripts/类定义/org/flashNight/arki/scene/Cf6StoryService.as','launcher/src/Audio/AudioCoordinator.cs',
            'flashswf/backgrounds/cf6/CF6_A01_Turret.swf',xflBase+'/bin/native.dat',comicBase+'cf6-s1/narration.mp3'])assert(names.has(ref),ref);
    });
    test('missing turret assetUrl resource is rejected',()=>{fs.unlinkSync(path.join(root,'flashswf/backgrounds/cf6/CF6_A01_Turret.swf'));assert.throws(()=>C.capture(root));restoreAssets();});
    test('assetUrl rejects non-string, remote and escaping values',()=>{
        for(const value of [null,7,'https://host/turret.swf','flashswf/../outside.swf']){
            const bad=JSON.parse(JSON.stringify(chapter));bad.maps[1].mechanism.turrets.assetUrl=value;
            assert.throws(()=>C.chapterResources(bad));
        }
    });
    test('missing actual turret XFL descriptor is rejected',()=>{fs.unlinkSync(path.join(root,xflBase+'/DOMDocument.xml'));assert.throws(()=>C.capture(root),/missing turret XFL source/);restoreAssets();});
    test('saved XFL native cache changes invalidate the journey closure',()=>{write(xflBase+'/bin/native.dat','changed native data');assert.throws(()=>C.assertUnchanged(baseline,C.capture(root)));restoreAssets();});
    test('native empty mobile sidecar is included and content changes invalidate closure',()=>{
        const row=baseline.files.find(value=>value.relativePath===xflBase+'/MobileSettings.xml');
        assert(row);assert.equal(row.bytes,0);assert.equal(row.sha256,hash(''));
        write(xflBase+'/MobileSettings.xml','changed');assert.throws(()=>C.assertUnchanged(baseline,C.capture(root)));restoreAssets();
    });
    test('empty required XFL sources and arbitrary sidecars remain rejected',()=>{
        write(xflBase+'/DOMDocument.xml','');assert.throws(()=>C.capture(root));restoreAssets();
        write(xflBase+'/unexpected.xml','');assert.throws(()=>C.capture(root));fs.unlinkSync(path.join(root,xflBase+'/unexpected.xml'));
    });
    test('comic source, runtime and generator bytes must match their manifests',()=>{
        for(const ref of [comicBase+'cf6-s1/narration.mp3',comicSource+'cf6-s1/comic.svg','tools/cf6-story-migration/build_cf6_web_content.py']){
            write(ref,'changed');assert.throws(()=>C.capture(root),/declared asset digest mismatch/);restoreAssets();
        }
    });
    test('comic inventories cannot silently omit a runtime reference',()=>{
        const m=parse(comicManifest);m.files=m.files.filter(row=>!row.path.endsWith('.mp3'));m.fileCount=m.files.length;m.totalBytes=m.files[0].bytes;put(comicManifest,m);
        const audit=parse(comicAudit);audit.fileCount=m.fileCount;audit.totalBytes=m.totalBytes;audit.runtimePayload=m.files;put(comicAudit,audit);
        assert.throws(()=>C.capture(root),/undeclared asset/);restoreAssets();
    });
    test('comic inventory rejects duplicate paths, traversal and count drift',()=>{
        for(const change of [m=>m.files.push(m.files[0]),m=>m.files[0].path='../escape.mp3',m=>m.fileCount++]){
            const m=parse(comicManifest);change(m);put(comicManifest,m);assert.throws(()=>C.capture(root));restoreAssets();
        }
    });
    test('comic binding digest and generated module digest are verified',()=>{
        const m=parse(comicManifest);m.sourceBindingSha256='0'.repeat(64);put(comicManifest,m);assert.throws(()=>C.capture(root),/comic source binding/);restoreAssets();
        write(contentJs,'changed module');assert.throws(()=>C.capture(root),/declared asset digest mismatch/);restoreAssets();
    });
    test('comic audit must include every generated consumer',()=>{
        const audit=parse(comicAudit);audit.generatedOutputs=audit.generatedOutputs.filter(row=>row.path!==contentJs);put(comicAudit,audit);
        assert.throws(()=>C.capture(root),/missing comic generated output binding/);restoreAssets();
    });
    test('turret media, raw tags and original SWF remain bound to their source identity',()=>{
        for(const ref of [turretBase+'bitmaps/fixture.png',turretBase+'raw-tags/tag-1.bin',C.ORIGINAL_SWF]){
            write(ref,'changed');assert.throws(()=>C.capture(root),/declared asset digest mismatch/);restoreAssets();
        }
    });
    test('original SWF admission is one exact governed path, not the former temporary prefix',()=>{
        const fragmentPath='tools/cf6-tutorial-turrets/tutorial-turrets.fragment.json';
        for(const ref of ['tmp/cf6-roguelike-20261021/kimi-content/extract/crazyflasher6-cn.swf',C.ORIGINAL_SWF.replace('crazyflasher6-cn.swf','other.swf')]){
            const fragment=parse(fragmentPath);fragment.sourceSwf.path=ref;put(fragmentPath,fragment);write(ref,swf());
            assert.throws(()=>C.capture(root),/unexpected turret original source path/);restoreAssets();
        }
    });
    test('temporary export frames never join the consumer closure',()=>{
        write('tools/cf6-story-migration/ffdec-work/large-frame.png','temporary export');
        write('tools/cf6-tutorial-turrets/generated/selftest-xfl/not-an-input.xml','test fixture');
        assert(C.assertUnchanged(baseline,C.capture(root)));
    });
    test('original camera scripts join the source closure and reject stale declared digests',()=>{
        assert(baseline.files.some(row=>row.relativePath===cameraSource));
        write(cameraSource,'changed camera');assert.throws(()=>C.capture(root),/original camera source changed/);write(cameraSource,'fixture camera');
    });
    test('resource byte changes invalidate closure',()=>{write('flashswf/leaf.swf',swf('object.swf'));assert.throws(()=>C.assertUnchanged(baseline,C.capture(root)));write('flashswf/leaf.swf',swf());});
    test('missing imported SWF is never skipped',()=>{fs.unlinkSync(path.join(root,'flashswf/leaf.swf'));assert.throws(()=>C.capture(root));write('flashswf/leaf.swf',swf());});
    test('ambiguous imported URL is rejected',()=>{write('nested/child.swf',swf());assert.throws(()=>C.capture(root));fs.unlinkSync(path.join(root,'nested/child.swf'));});
    test('missing A21 source binding fails closed',()=>{write(mechanism,'fixture');assert.throws(()=>C.capture(root));write(mechanism,'"flashswf/backgrounds/cf6/CF6_A21_Transform.swf"');});
    test('malformed SWF is rejected',()=>{write('flashswf/overlay.swf','not a swf');assert.throws(()=>C.capture(root));write('flashswf/overlay.swf',swf());});
    test('digest corruption fails verification',()=>{const copy=JSON.parse(JSON.stringify(baseline));copy.files[0].bytes++;assert.throws(()=>C.verify(copy));});
    test('absolute, traversal, ADS, encoded and trailing-dot paths fail',()=>{for(const ref of ['../a.swf','C:\\a.swf','/a.swf','//server/a.swf','a.swf:stream','a%2fswf','a./b.swf','a/../b.swf'])assert.throws(()=>C.relative(ref),ref);});
    test('SWF escaping import and external URL fail',()=>{for(const ref of ['../../../../outside.swf','https://host/a.swf','file:///a.swf','%ZZ.swf'])assert.throws(()=>C.resolveImport(root,'flashswf/object.swf',ref),ref);});
    test('encoded local SWF import resolves safely',()=>assert.equal(C.resolveImport(root,'flashswf/object.swf','nested%2Fchild.swf'),'flashswf/nested/child.swf'));
    test('XML comments and entities resolve exact child paths',()=>assert.deepStrictEqual(C.listReferences('<root><!--<items>fake</items>--><items>A &amp; B.xml</items></root>',['items']),['A & B.xml']));
    test('XML external entities, malformed entries and traversal fail',()=>{for(const xml of ['<!DOCTYPE x><items>a</items>','<items x="1">a</items>','<items>../a.xml</items>','<items>&unknown;</items>'])assert.throws(()=>C.listReferences(xml,['items']));});
    test('chapter resources reject remote and non-SWF URLs',()=>{for(const url of ['https://host/a.swf','flashswf/../outside.swf','flashswf/file.json']){const bad=JSON.parse(JSON.stringify(chapter));bad.maps[0].mechanism.layers[0].url=url;assert.throws(()=>C.chapterResources(bad));}});
    test('case alias in chapter resources is rejected',()=>{const bad=JSON.parse(JSON.stringify(chapter));bad.maps[0].mechanism.layers.push({url:'flashswf/OBJECT.swf'});write(chapterPath,JSON.stringify(bad));assert.throws(()=>C.capture(root));write(chapterPath,JSON.stringify(chapter));});
    const sceneBaseline=C.capture(root);
    test('new traversal, pause, depth and source producer identities are bound',()=>{
        const names=new Set(sceneBaseline.files.map(r=>r.relativePath));
        for(const ref of ['scripts/类定义/org/flashNight/arki/scene/Cf6TraversalRules.as',
            'scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskPresentation.as',
            'scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthService.as','scripts/类定义/org/flashNight/arki/pause/PauseManager.as',
            'tools/cf6-prototype/scene-assembly.py',propBase+'calibrate.py',propBase+'build_depth_props.py',parentXml,
            propBase+'baselines/fixture.xml','flashswf/backgrounds/cf6/props/CF6_Prop_Fixture/LIBRARY/one.xml'])assert(names.has(ref),ref);
        const handoffSources=['scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as',
            'scripts/类定义/org/flashNight/arki/scene/StageReturnFlow.as','scripts/类定义/org/flashNight/arki/scene/StageRunSession.as',
            'scripts/类定义/org/flashNight/arki/scene/SceneTransitionGuard.as','scripts/类定义/org/flashNight/arki/ui/SceneTransitionService.as',
            'CRAZYFLASHER7MercenaryEmpire/LIBRARY/sprite/淡出动画.xml',
            'scripts/类定义/org/flashNight/arki/component/Damage/DamageCalculator.as',
            'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/StaticInitializer.as',
            'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Targetcache/FactionManager.as'];
        for(const ref of handoffSources){
            assert(names.has(ref),ref);const original=fs.readFileSync(path.join(root,ref));
            write(ref,Buffer.concat([original,Buffer.from(' changed source identity')]));
            assert.throws(()=>C.assertUnchanged(sceneBaseline,C.capture(root)),/changed during the journey/);write(ref,original);
        }

    });
    test('unused auxiliary and A07 vehicle preparations do not join the consumer closure',()=>{
        write('flashswf/backgrounds/cf6/preparation/CF6_AuxCamera1832/LIBRARY/one.xml','unused changed source');
        write(sceneBase+'vehicle-art/A07-source-only.xml','unrelated');
        assert(C.assertUnchanged(sceneBaseline,C.capture(root)));restoreSceneAssets();
    });
    test('used scene input and native output hashes are verified',()=>{
        for(const ref of [sceneBase+'fixture-source.svg','flashswf/backgrounds/cf6/preparation/CF6_Traversal1720_Back/LIBRARY/one.xml']){
            write(ref,'tampered');assert.throws(()=>C.capture(root),/digest mismatch/);restoreSceneAssets();
        }
    });
    test('exact auxiliary texture seed pins descriptor, referenced native caches and dependency cache',()=>{
        const seed='flashswf/backgrounds/cf6/preparation/CF6_AuxiliaryTextureSeed';
        const doc=seed+'/DOMDocument.xml',cache=seed+'/bin/M 1 1792735894.dat',dep=seed+'/bin/SymDepend.cache';
        write(doc,'<DOMDocument><media><DOMBitmapItem name="seed" href="texture.png" bitmapDataHRef="M 1 1792735894.dat"/></media></DOMDocument>');
        write(cache,'seed pixels');write(dep,'seed dependencies');
        const m=parse(auxManifest);m.textureSeed=seed+'/CF6_AuxiliaryTextureSeed.xfl';
        for(const ref of [doc,cache,dep])m.inputs[ref]=declared(ref).sha256;
        put(auxManifest,m);const captured=C.capture(root),names=new Set(captured.files.map(x=>x.relativePath));
        for(const ref of [doc,cache,dep])assert(names.has(ref),ref);
        write(cache,'changed pixels');assert.throws(()=>C.capture(root),/digest mismatch/);write(cache,'seed pixels');
        for(const ref of [doc,cache]){const bad=JSON.parse(JSON.stringify(m));delete bad.inputs[ref];put(auxManifest,bad);assert.throws(()=>C.capture(root),/omitted native texture seed/);}
        const extra=seed+'/bin/unrelated.dat';write(extra,'extra');const bad=JSON.parse(JSON.stringify(m));bad.inputs[extra]=hash('extra');put(auxManifest,bad);
        assert.throws(()=>C.capture(root),/unreviewed native texture seed/);
        const sibling='flashswf/backgrounds/cf6/preparation/CF6_OtherSeed/DOMDocument.xml';write(sibling,'other');m.inputs[sibling]=hash('other');put(auxManifest,m);
        assert.throws(()=>C.capture(root),/unreviewed native scene input/);restoreSceneAssets();
    });
    test('expanded full-timeline closure still rejects an unbounded resource inventory',()=>{
        const huge=JSON.parse(JSON.stringify(chapter));huge.maps[0].mechanism.layers=Array.from({length:8193},(_,i)=>({url:'flashswf/fixture-large/'+i+'.swf'}));put(chapterPath,huge);
        assert.throws(()=>C.capture(root),/closure resource count exceeded/);put(chapterPath,chapter);
    });
    test('interactive consumers bind exact native source, seed caches and original identity',()=>{
        const selected=JSON.parse(JSON.stringify(chapter));selected.maps[0].mechanism.interactiveProps={schema:'cf6-interactive-props.v1',props:[{url:'flashswf/backgrounds/cf6/preparation/CF6_InteractiveBarrel1736.swf'}]};
        put(chapterPath,selected);
        const seed='flashswf/backgrounds/cf6/preparation/CF6_InteractiveTextureSeed';
        const doc=seed+'/DOMDocument.xml',cache=seed+'/bin/M 1 1792735894.dat',dep=seed+'/bin/SymDepend.cache';
        write(doc,'<DOMDocument><media><DOMBitmapItem name="seed" href="texture.png" bitmapDataHRef="M 1 1792735894.dat"/></media></DOMDocument>');
        write(cache,'interactive seed');write(dep,'interactive dependencies');
        const m=parse(interactiveManifest);m.textureSeed=seed+'/CF6_InteractiveTextureSeed.xfl';
        for(const ref of [doc,cache,dep])m.inputs[ref]=declared(ref).sha256;
        put(interactiveManifest,m);const snapshot=C.capture(root),names=new Set(snapshot.files.map(x=>x.relativePath));
        for(const ref of [doc,cache,dep,'flashswf/backgrounds/cf6/preparation/CF6_InteractiveBarrel1736/LIBRARY/one.xml'])assert(names.has(ref),ref);
        assert(!names.has('flashswf/backgrounds/cf6/preparation/CF6_InteractivePod1939/LIBRARY/one.xml'));
        const missing=JSON.parse(JSON.stringify(m));delete missing.inputs[cache];put(interactiveManifest,missing);assert.throws(()=>C.capture(root),/omitted native texture seed cache/);
        const bad=JSON.parse(JSON.stringify(m));bad.originalSha256='0'.repeat(64);put(interactiveManifest,bad);assert.throws(()=>C.capture(root),/interactive original source digest/);
        const frames=JSON.parse(JSON.stringify(m));frames.assets[0].frames=25;put(interactiveManifest,frames);assert.throws(()=>C.capture(root),/interactive sprite\/frame binding/);
        put(interactiveManifest,m);write(cache,'mutated interactive seed');assert.throws(()=>C.capture(root),/digest mismatch/);
        restoreSceneAssets();put(chapterPath,chapter);
    });
    test('interactive native outputs cannot omit media or refer to unrelated seed directories',()=>{
        const selected=JSON.parse(JSON.stringify(chapter));selected.maps[0].mechanism.interactiveProps={props:[{url:'flashswf/backgrounds/cf6/preparation/CF6_InteractiveBarrel1736.swf'}]};put(chapterPath,selected);
        let m=parse(interactiveManifest);delete m.outputs['flashswf/backgrounds/cf6/preparation/CF6_InteractiveBarrel1736/PublishSettings.xml'];put(interactiveManifest,m);
        assert.throws(()=>C.capture(root),/omitted native source dependency/);restoreSceneAssets();
        m=parse(interactiveManifest);const wrong='flashswf/backgrounds/cf6/preparation/CF6_AuxiliaryTextureSeed/DOMDocument.xml';m.inputs[wrong]=hash('wrong');put(interactiveManifest,m);
        assert.throws(()=>C.capture(root),/unreviewed native scene input/);restoreSceneAssets();
        selected.maps[0].mechanism.interactiveProps.props[0].url='flashswf/backgrounds/cf6/preparation/CF6_InteractiveInvented.swf';put(chapterPath,selected);write(selected.maps[0].mechanism.interactiveProps.props[0].url,swf());
        assert.throws(()=>C.capture(root),/absent from manifest/);put(chapterPath,chapter);
    });
    test('transport service and both exact producer inputs invalidate changed journey identity',()=>{
        const refs=['scripts/类定义/org/flashNight/arki/scene/Cf6TransportService.as',
            'tools/cf6-prototype/transport-assembly.py',sceneBase+'build_transport_art.py'];
        const snapshot=C.capture(root),names=new Set(snapshot.files.map(row=>row.relativePath));
        for(const ref of refs){assert(names.has(ref),ref);const original=fs.readFileSync(path.join(root,ref));
            write(ref,Buffer.concat([original,Buffer.from(' changed transport source')]));
            assert.throws(()=>C.assertUnchanged(snapshot,C.capture(root)),/changed during the journey/);write(ref,original);}
    });
    test('transport consumer binds exact native source, fragments, grain and complete seed hashes',()=>{
        const selected=JSON.parse(JSON.stringify(chapter));selected.maps[0].mechanism.transport={url:'flashswf/backgrounds/cf6/preparation/CF6_Transport1868.swf'};put(chapterPath,selected);
        const seed='flashswf/backgrounds/cf6/preparation/CF6_TransportTextureSeed';
        const refs=[sceneBase+'fixture-source.svg',seed+'/DOMDocument.xml',seed+'/bin/M 1 1792735894.dat',seed+'/bin/SymDepend.cache',
            'flashswf/backgrounds/cf6/preparation/CF6_Transport1868/LIBRARY/one.xml',
            sceneBase+'transport-art/CF6_Transport1868/fragment.xml',sceneBase+'transport-art/textures/grain.png',sceneBase+'transport-art/import-textures.jsfl'];
        const snapshot=C.capture(root),names=new Set(snapshot.files.map(row=>row.relativePath));
        for(const ref of refs){assert(names.has(ref),ref);write(ref,'tampered transport payload');assert.throws(()=>C.capture(root));restoreSceneAssets();}
        for(const ref of [seed+'/DOMDocument.xml',seed+'/bin/M 1 1792735894.dat',C.ORIGINAL_SWF]){
            const m=parse(transportManifest);delete m.inputs[ref];put(transportManifest,m);assert.throws(()=>C.capture(root),/omitted/);restoreSceneAssets();}
        put(chapterPath,chapter);
    });
    test('transport source identity, sprite, frame29 and exact runtime name fail closed',()=>{
        const selected=JSON.parse(JSON.stringify(chapter));selected.maps[0].mechanism.transport={url:'flashswf/backgrounds/cf6/preparation/CF6_Transport1868.swf'};put(chapterPath,selected);
        for(const mutate of [m=>m.originalSha256='0'.repeat(64),m=>m.assets[0].sourceSprite=1869,
            m=>m.assets[0].frames=28,m=>m.assets[0].dispatchFrame=28,m=>m.assets[0].name='CF6_Transport1869']){
            const m=parse(transportManifest);mutate(m);put(transportManifest,m);assert.throws(()=>C.capture(root));restoreSceneAssets();}
        selected.maps[0].mechanism.transport.url='flashswf/backgrounds/cf6/preparation/CF6_TransportInvented.swf';
        write(selected.maps[0].mechanism.transport.url,swf());put(chapterPath,selected);assert.throws(()=>C.capture(root),/absent from manifest/);put(chapterPath,chapter);
    });
    test('transport cannot broaden preparation, fragment, seed or A07 source admission',()=>{
        for(const ref of [sceneBase+'vehicle-art/A07-source-only.xml',
            'flashswf/arts/new/Codex素材源稿/CF6地图/A07-R1/source.xml',
            'flashswf/backgrounds/cf6/preparation/CF6_InteractiveTextureSeed/DOMDocument.xml']){
            write(ref,'forbidden transport source');const m=parse(transportManifest);m.inputs[ref]=hash('forbidden transport source');
            put(transportManifest,m);assert.throws(()=>C.capture(root),/unreviewed native scene input/);restoreSceneAssets();}
        for(const ref of [sceneBase+'transport-art/CF6_Transport1869/fragment.xml',
            'flashswf/backgrounds/cf6/preparation/CF6_Transport1869/LIBRARY/one.xml',sceneBase+'vehicle-art/A07-source-only.xml']){
            write(ref,'forbidden transport output');const m=parse(transportManifest);m.outputs[ref]=declared(ref);
            put(transportManifest,m);assert.throws(()=>C.capture(root),/unreviewed native output/);restoreSceneAssets();}
        const extra='flashswf/backgrounds/cf6/preparation/CF6_TransportTextureSeed/bin/unrelated.dat';write(extra,'not referenced');
        const m=parse(transportManifest);m.inputs[extra]=hash('not referenced');put(transportManifest,m);
        assert.throws(()=>C.capture(root),/unreviewed native texture seed/);restoreSceneAssets();
    });
    test('transport native source omission and output digest or size forgery are rejected',()=>{
        const selected=JSON.parse(JSON.stringify(chapter));selected.maps[0].mechanism.transport={url:'flashswf/backgrounds/cf6/preparation/CF6_Transport1868.swf'};put(chapterPath,selected);
        const ref='flashswf/backgrounds/cf6/preparation/CF6_Transport1868/PublishSettings.xml';
        for(const mutate of [m=>delete m.outputs[ref],m=>m.outputs[ref].sha256='0'.repeat(64),m=>m.outputs[ref].bytes++]){
            const m=parse(transportManifest);mutate(m);put(transportManifest,m);assert.throws(()=>C.capture(root));restoreSceneAssets();}
        put(chapterPath,chapter);
    });
    test('native output declared byte count cannot be forged',()=>{
        const m=parse(auxManifest),key=Object.keys(m.outputs)[0];m.outputs[key].bytes++;put(auxManifest,m);
        assert.throws(()=>C.capture(root),/size mismatch/);restoreSceneAssets();
    });
    test('native manifests reject traversal, self bindings and source-only vehicle inputs',()=>{
        for(const ref of ['../escape.xml',auxManifest,sceneBase+'vehicle-art/A07-source-only.xml']){
            const m=parse(auxManifest);m.inputs[ref]=hash('x');put(auxManifest,m);assert.throws(()=>C.capture(root));restoreSceneAssets();
        }
    });
    test('native output aliases and duplicate asset names are rejected',()=>{
        let m=parse(auxManifest),key=Object.keys(m.outputs)[0];m.outputs[key.replace('DOMDocument','domdocument')]=m.outputs[key];put(auxManifest,m);
        assert.throws(()=>C.capture(root),/duplicate scene asset path/);restoreSceneAssets();
        m=parse(auxManifest);m.assets.push(m.assets[0]);put(auxManifest,m);assert.throws(()=>C.capture(root),/duplicate native scene asset/);restoreSceneAssets();
    });
    test('duplicate JSON object keys cannot hide a forged manifest declaration',()=>{
        const m=parse(auxManifest),key=Object.keys(m.outputs)[0];const raw=JSON.stringify(m).replace('"outputs":{','"outputs":{'+JSON.stringify(key)+':'+JSON.stringify(m.outputs[key])+',');
        write(auxManifest,raw);assert.throws(()=>C.capture(root),/duplicate/i);restoreSceneAssets();
    });
    test('runtime auxiliary resource requires a matching native asset declaration',()=>{
        const bad=JSON.parse(JSON.stringify(chapter));bad.maps[0].mechanism.layers.push({url:'flashswf/backgrounds/cf6/preparation/CF6_AuxUnknown.swf'});put(chapterPath,bad);
        assert.throws(()=>C.capture(root),/absent from manifest/);put(chapterPath,chapter);
    });
    test('missing native Include payload and required descriptor fail despite valid remaining hashes',()=>{
        for(const suffix of ['/LIBRARY/one.xml','/PublishSettings.xml']){
            const m=parse(traversalManifest);delete m.outputs['flashswf/backgrounds/cf6/preparation/CF6_Traversal1720_Back'+suffix];put(traversalManifest,m);
            assert.throws(()=>C.capture(root),/omitted native source dependency/);restoreSceneAssets();
        }
    });
    test('native media cache references must be declared as well as present on disk',()=>{
        const base='flashswf/backgrounds/cf6/preparation/CF6_AuxDoor1430',m=parse(auxManifest);
        write(base+'/DOMDocument.xml','<DOMDocument><media><DOMBitmapItem name="texture" href="texture.png" bitmapDataHRef="native.dat"/></media><symbols><Include href="one.xml"/></symbols></DOMDocument>');
        write(base+'/LIBRARY/texture.png','native bytes');write(base+'/bin/native.dat','native cache');
        for(const ref of [base+'/DOMDocument.xml',base+'/LIBRARY/texture.png',base+'/bin/native.dat']){const row=declared(ref);m.outputs[ref]={sha256:row.sha256,bytes:row.bytes};}
        put(auxManifest,m);C.capture(root);delete m.outputs[base+'/bin/native.dat'];put(auxManifest,m);
        assert.throws(()=>C.capture(root),/omitted native source dependency/);restoreSceneAssets();
    });
    test('native XML cannot refer to an undeclared library symbol',()=>{
        const ref='flashswf/backgrounds/cf6/preparation/CF6_AuxDoor1430/LIBRARY/one.xml',m=parse(auxManifest);
        write(ref,'<DOMSymbolItem><DOMSymbolInstance libraryItemName="absent"/></DOMSymbolItem>');m.outputs[ref]=declared(ref);put(auxManifest,m);
        assert.throws(()=>C.capture(root),/missing Include/);restoreSceneAssets();
    });
    test('native XML entities cannot introduce external inputs',()=>{
        const ref='flashswf/backgrounds/cf6/preparation/CF6_AuxDoor1430/DOMDocument.xml',m=parse(auxManifest);
        write(ref,'<!DOCTYPE x><DOMDocument/>');m.outputs[ref]=declared(ref);put(auxManifest,m);
        assert.throws(()=>C.capture(root),/non-closed native XML/);restoreSceneAssets();
    });
    test('depth prop files reject duplicate, escaping and omitted native entries',()=>{
        for(const mutate of [g=>g.files.push(g.files[0]),g=>g.files[0].path='../escape.xml',g=>g.files=g.files.filter(r=>!r.path.endsWith('/LIBRARY/one.xml'))]){
            const m=parse(depthManifest);mutate(m.groups[0]);put(depthManifest,m);assert.throws(()=>C.capture(root));restoreSceneAssets();
        }
    });
    test('depth prop declared native bytes and digest are both enforced',()=>{
        for(const key of ['bytes','sha256']){const m=parse(depthManifest);m.groups[0].files[0][key]=key==='bytes'?999:'0'.repeat(64);put(depthManifest,m);assert.throws(()=>C.capture(root));restoreSceneAssets();}
    });
    test('prop baseline pins cannot silently follow edited original matrices',()=>{
        write(propBase+'baselines/fixture.xml','changed original');assert.throws(()=>C.capture(root),/digest mismatch/);restoreSceneAssets();
    });
    test('prop recipes reject duplicate instances, selectors and escaping baselines',()=>{
        for(const mutate of [m=>m.instances.push(m.instances[0]),m=>m.instances.push({...m.instances[0],id:'alias'}),m=>m.instances[0].baseline='../outside.xml',m=>m.instances[0].instanceIndex=8]){
            const m=parse(propRecipe);mutate(m);put(propRecipe,m);assert.throws(()=>C.capture(root));restoreSceneAssets();
        }
    });
    test('actual calibrated background bytes are part of journey identity',()=>{
        write(parentXml,'<DOMSymbolItem><!--new bytes--><timeline/></DOMSymbolItem>');assert.throws(()=>C.assertUnchanged(sceneBaseline,C.capture(root)));restoreSceneAssets();
    });
    test('extracted prop may not still be drawn in its background',()=>{
        write(parentXml,fs.readFileSync(path.join(root,propBase+'baselines/fixture.xml')));
        assert.throws(()=>C.capture(root),/background instance inventory mismatch/);restoreSceneAssets();
    });
    test('excluded background prop requires its actual chapter runtime consumer',()=>{
        const bad=JSON.parse(JSON.stringify(chapter));bad.maps[0].mechanism.layers=bad.maps[0].mechanism.layers.filter(r=>!r.url.includes('/props/'));put(chapterPath,bad);
        assert.throws(()=>C.capture(root),/excluded without runtime consumer/);put(chapterPath,chapter);
    });
    test('depth consumer rejects disabled exclusions or invented group members',()=>{
        const depth=propBase+'depth-recipe.json';let m=parse(depth);m.enabled=false;put(depth,m);assert.throws(()=>C.capture(root),/duplicated in background recipe/);restoreSceneAssets();
        m=parse(depthManifest);m.groups[0].memberIds=['not-a-calibrated-instance'];put(depthManifest,m);assert.throws(()=>C.capture(root),/unknown or duplicate depth prop member/);restoreSceneAssets();
    });
    test('bounded future Cf6 spawn-mask consumer dependencies are captured and cycles terminate',()=>{
        const source='scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as',child='scripts/类定义/org/flashNight/arki/scene/Cf6BoundedSpawnMask.as';
        const original=fs.readFileSync(path.join(root,source));
        write(source,'import org.flashNight.arki.scene.Cf6BoundedSpawnMask;');assert.throws(()=>C.capture(root));
        write(child,'import org.flashNight.arki.scene.Cf6TraversalService;');const closure=C.capture(root);
        assert(closure.files.some(r=>r.relativePath===child));assert(closure.dependencies.some(r=>r.owner===source&&r.target===child));write(source,original);
    });
    test('body scale policy binds the exact measured native XML',()=>{
        const ref='flashswf/arts/new/Antigravity专用素材/LIBRARY/body-measurement.xml';
        write(ref,'drifted body');assert.throws(()=>C.capture(root),/digest mismatch/);restoreSceneAssets();
    });
    test('body scale source policy cannot escape the reviewed native libraries',()=>{
        const ref=propBase+'scale-policy.json',m=parse(ref);m.humanoids[0].nativeSources={'launcher/secret.xml':hash('native body')};
        put(ref,m);assert.throws(()=>C.capture(root),/unreviewed native body/);restoreSceneAssets();
    });
    test('dialogue expression bytes are captured and must match the actual catalog',()=>{
        const changed=JSON.parse(JSON.stringify(chapter)),base='launcher/web/assets/dialogue-portraits/';
        changed.maps[0].dialogue=[{speaker:'Andy Law',text:'fixture',char:'Andy Law#普通'}];put(chapterPath,changed);
        const uri='external/p_0123456789ab/e_0123456789ab.webp';write(base+uri,'portrait bytes');
        put(base+'manifest.json',{entries:{'Andy Law':{expressions:{'普通':{uri,sha256:hash('portrait bytes'),bytes:14}}}}});
        const closure=C.capture(root);assert(closure.files.some(row=>row.relativePath===base+uri));
        write(base+uri,'changed portrait');assert.throws(()=>C.capture(root),/digest mismatch/);put(chapterPath,chapter);
    });
    console.log('CF6 source closure offline cases: '+passed+'/'+passed);
}finally{
    const resolved=path.resolve(root);assert.equal(path.dirname(resolved),parent);assert(path.basename(resolved).startsWith('cf7-cf6-closure-fixture-'));
    fs.rmSync(resolved,{recursive:true,force:true});
}
