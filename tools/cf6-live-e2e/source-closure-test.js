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
    stage:{Instances:[{url:'flashswf/object.swf'}]},mechanism:{layers:[{url:'flashswf/overlay.swf'}]}},
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
    console.log('CF6 source closure offline cases: '+passed+'/'+passed);
}finally{
    const resolved=path.resolve(root);assert.equal(path.dirname(resolved),parent);assert(path.basename(resolved).startsWith('cf7-cf6-closure-fixture-'));
    fs.rmSync(resolved,{recursive:true,force:true});
}
