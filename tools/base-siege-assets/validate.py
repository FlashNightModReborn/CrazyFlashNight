"""Validate main34 graph, native source closure and the published asset set."""
from pathlib import Path
from lxml import etree as E
import json,sys,hashlib
ROOT=Path(__file__).resolve().parents[2]
NS={'x':'http://ns.adobe.com/xfl/2008/'}
NAMES=['gk20_1_BG_围攻','gk1_3_BG_围攻','gk1_2_BG_围攻','gk20_5_BG_围攻','base_siege_coil','base_siege_relay','base_siege_hind','base_siege_equipment']
errors=[];symbols=0
def check(condition,message):
    if not condition:errors.append(message)
for name in NAMES:
    folder=ROOT/'flashswf/backgrounds'/name
    check((folder/(name+'.xfl')).is_file(),'missing native entry '+name)
    check((folder/'PublishSettings.xml').is_file(),'missing publish settings '+name)
    check((ROOT/'flashswf/backgrounds'/(name+'.swf')).is_file(),'missing published SWF '+name)
    paths=list((folder/'LIBRARY').rglob('*.xml'))
    items={E.parse(str(p)).getroot().get('name'):p for p in paths};symbols+=len(items)
    check(len(items)==len(paths),'duplicate symbol identities '+name)
    for p in paths:
        r=E.parse(str(p)).getroot()
        check(r.get('linkageExportForAS')!='true','unexpected global export '+str(p.relative_to(ROOT)))
        for e in r.iter():
            ref=e.get('libraryItemName')
            if ref:check(ref in items,'missing '+str(p.relative_to(ROOT))+' -> '+ref)
    document=E.parse(str(folder/'DOMDocument.xml'))
    if name.startswith('base_siege_'):
        count=len(document.findall('.//x:timelines/x:DOMTimeline/x:layers/x:DOMLayer/x:frames/x:DOMFrame',NS))
        check(count==({'base_siege_coil':1,'base_siege_equipment':3}.get(name,1)),'wrong state count '+name)
        if name=='base_siege_coil':
            frames=document.findall('.//x:timelines/x:DOMTimeline/x:layers/x:DOMLayer/x:frames/x:DOMFrame',NS)
            refs=[e.get('libraryItemName') for e in frames[0].findall('.//x:DOMSymbolInstance',NS)]
            check(refs==['R5_MC_tower_to_shield','R5_MC_tower_to_interference','BaseSiege/coil-effect-standby/root','BaseSiege/coil-effect-powered/root'],'R5 host and effect composition')
            check([e.get('name') for e in frames[0].findall('.//x:DOMSymbolInstance',NS)]==['shieldMC','interferenceMC','effectStandby','effectPowered'],'R5 named runtime instances')
            for lib,total,first,last in [('R5_MC_tower_to_shield',73,'tower','shield'),('R5_MC_tower_to_interference',49,'tower','interference')]:
                mc=E.parse(str(folder/'LIBRARY'/(lib+'.xml')))
                mc_frames=mc.findall('.//x:DOMTimeline/x:layers/x:DOMLayer/x:frames/x:DOMFrame',NS)
                check(len(mc_frames)==total and mc_frames[0].get('name')==first and mc_frames[-1].get('name')==last,'R5 frame labels '+lib)
    else:
        check('_root.贴背景图()' in ''.join(document.xpath('//x:script/text()',namespaces=NS)),'bake contract '+name)
stage=E.parse(str(ROOT/'data/stages/基地房顶/基地.xml'));rooms=stage.findall('SubStage')
check([s.get('id') for s in rooms]==list(map(str,range(8))),'continuous eight-scene ids')
check([s.findtext('BasicInformation/CallbackFunction/Parameter') for s in rooms]==[None,'rhino','tigr',None,None,None,None,'roof'],'only relay and roof presentation callbacks remain')
check(not stage.xpath('//Rewards/Reward[Name="军阀前线基地通关证明"]'),'wrong chapter proof drop')
for s in rooms:
    for b in s.findall('BasicInformation/Background'):
        check((ROOT/b.text).is_file(),'missing background '+b.text)
    events={e.findtext('EventName') for e in s.findall('Event')}
    for f in s.findall('.//FollowingEvent/EventName'):check(f.text in events,'dangling dialogue continuation '+f.text)
for i in [1,2,7]:
    check(len(rooms[i].findall('Instances/Instance'))==2,'required unbaked state objects '+str(i))
check(rooms[0].findtext('BasicInformation/Environment/Door/Direction')=='左' and float(rooms[0].findtext('BasicInformation/PlayerX'))>1300,'crash starts near wreck and leaves left')
check(rooms[1].findtext('BasicInformation/Environment/Door/Direction')=='左' and float(rooms[1].findtext('BasicInformation/PlayerX'))>1500,'rhino enters right and leaves left')
check(rooms[2].findtext('BasicInformation/Environment/Door/Direction')=='下' and rooms[2].findtext('BasicInformation/Environment/Door/y0')=='610' and rooms[2].findtext('BasicInformation/Environment/Door/x0')=='765' and rooms[2].findtext('BasicInformation/Environment/Door/x1')=='820','tigr lower sandbag exit')
for s in rooms[1:3]:
    counter=s.findall('Wave/SubWave')[1].findall('EnemyGroup/Enemy')
    check(all(e.findtext('TriggerEvent/EventName')=='SiegeCounterattack' and e.findtext('Parameters/threatThreshold')=='15' for e in counter),'guard wave must await activation and target threat')
    activated=next(e for e in s.findall('Event') if e.findtext('EventName')=='SiegeRelayActivated')
    guard=activated.find('Enemy')
    check(guard.findtext('spritename')=='特殊友军-保护仪器' and guard.findtext('Parameters/threat')=='30' and guard.findtext('Parameters/publishStageEvent')=='true','live protection target and named destruction event')
    check(any(e.findtext('EventName')=='UnitDeath' and e.findtext('Parameter')=='siege_relay_guard' and e.findtext('StageProgress')=='Fail' for e in s.findall('Event')),'relay destruction fails defense')
# R3: entry side, loading receipts and explicit developer completion.
check(all(float(p.findtext('x'))<150 for p in rooms[0].findall('SpawnPoint/Point')),'crash pursuers enter left')
arrival=next(e for e in rooms[0].findall('Event') if e.findtext('EventName')=='WaveFinished')
check(all(float(e.findtext('x'))<250 and e.findtext('Parameters/方向')=='右' for e in arrival.findall('Enemy')),'both regular companions enter from left')
units=json.loads((ROOT/'data/units/units.json').read_text(encoding='utf-8-sig'))
ordinary={u['id']:u for u in units}
key_to_id={u['key']:u['id'] for u in units if u.get('key')}
def _resolve_id(t):
    return int(t[2:]) if t and t.startswith('兵种') and t[2:].isdigit() else key_to_id.get(t)
check([_resolve_id(e.findtext('Type')) for e in arrival.findall('Enemy')]==[470,471] and all(e.findtext('Level')=='20' for e in arrival.findall('Enemy')),'ordinary level-20 companions use their own unit entries')
check(ordinary[470]['data']['primary']=='AK74' and ordinary[471]['data']['primary']=='m14','ordinary companion primary weapons are present and upgraded')
check(ordinary[470]['data']['hand']=='A兵团制式战术手套' and ordinary[471]['data']['hand']=='A兵团制式战术手套','ordinary companion handgear uses the formal item name')
companion_dialogue=[d for d in stage.findall('.//Dialogue') if _resolve_id(d.findtext('Type')) in (470,471)]
check(len(companion_dialogue)==9 and all(d.findtext('Char')=='主角模板' for d in companion_dialogue),'companion dialogue uses doll portraits')
blue_radio=[d for d in stage.findall('.//Dialogue') if d.findtext('Name')=='Blue（无线电）']
check(len(blue_radio)==6 and all(d.findtext('Char')=='Blue（无线电）' and d.findtext('Title')=='格斗教练' for d in blue_radio),'base radio uses Blue communication portraits')
check(any(d.findtext('Name')=='Boy（无线电）' and d.findtext('Char')=='boy（无线电）' for d in stage.findall('.//Dialogue')),'Boy radio uses the dedicated portrait key')
portrait_manifest=json.loads((ROOT/'launcher/web/assets/dialogue-portraits/manifest.json').read_text(encoding='utf-8-sig'))
check('Blue（无线电）' in portrait_manifest['entries'] and 'boy（无线电）' in portrait_manifest['entries'],'radio portrait keys exist in the production manifest')
debug=(ROOT/'scripts/逻辑/关卡系统/关卡系统_lsy_无限过图.as').read_text(encoding='utf-8-sig')
check('stageManager.debugClearStage()' in debug,'modifier must use explicit completion path')
manager=(ROOT/'scripts/类定义/org/flashNight/arki/scene/StageManager.as').read_text(encoding='utf-8-sig')
check('BaseSiegeController.prepareDebugClear(this, gameworld)' in manager,'developer completion must retire siege gates')

def digest(e):return hashlib.sha256(E.tostring(e,method='c14n') if e is not None else b'').hexdigest()
baseline=json.loads((ROOT/'tools/base-siege-assets/source/original-base-combat.json').read_text(encoding='utf-8'))
for i,row in enumerate(baseline):
    # Parse again without indentation; whitespace is not gameplay.
    s=E.fromstring(E.tostring(rooms[i+3],encoding="utf-8"),E.XMLParser(remove_blank_text=True))
    # R6 adds optional intelligence to a single existing rooftop carrier only.
    # Compare the original combat fingerprint after removing that exact loot addition.
    for enemy in s.findall('Wave/SubWave/EnemyGroup/Enemy'):
        tnode=enemy.find('Type')
        if tnode is not None and _resolve_id((tnode.text or '').strip()) is not None:
            tnode.text='兵种'+str(_resolve_id((tnode.text or '').strip()))
        params=enemy.find('Parameters')
        if params is not None:
            for drop in list(params.findall('掉落物')):
                if any(d.findtext('名字')=='军阀机降队通讯抄录' for d in params.findall('掉落物')):
                    for owned in list(params.findall('掉落物')):params.remove(owned)
                    break
            if len(params)==0 and not (params.text or '').strip():enemy.remove(params)
    check(digest(s.find('Wave'))==row['waveSha256'],'original base combat changed '+str(i))
    check(digest(s.find('SpawnPoint'))==row['spawnSha256'],'original base spawn point changed '+str(i))
    check(s.findtext('BasicInformation/PlayerX')==row['playerX'] and s.findtext('BasicInformation/PlayerY')==row['playerY'],'original base player entry changed '+str(i))
roof=rooms[7];check(len(roof.findall('BasicInformation/Environment/Collision'))==4,'roof preserves original four collisions')
check(not any(e.findtext('EventName')=='SiegeEscortArrive' for e in roof.findall('Event')),'scripted escort gameplay must remain absent')
controller=(ROOT/'scripts/类定义/org/flashNight/arki/scene/BaseSiegeController.as').read_text(encoding='utf-8-sig')
check('createTextField' not in controller and '当前目标' not in controller and 'advanceEscort' not in controller,'no objective banner or escort control')
for name in ['BaseSiegeRules','BaseSiegeController','BaseSiegeTest']:
    p=ROOT/'scripts/类定义/org/flashNight/arki/scene'/(name+'.as');check(p.read_bytes().startswith(b'\xef\xbb\xbf'),'AS2 BOM '+name)
hair=(ROOT/'tools/base-siege-assets/source/casualty-A-short-crop.svg').read_text(encoding='utf-8')
check('mercenary-short-dark-crop' in hair and '#EAEEF7' not in hair,'mercenary hair replacement')
wave_enemies=sum(int(e.findtext('Quantity','1')) for e in stage.findall('.//Wave/SubWave/EnemyGroup/Enemy') if e.findtext('IsHostile')!='false')

# R4 fixed equipment, explicit vehicle scale and dismount geography.
for i,name in [(1,'gk1_3_BG_围攻'),(2,'gk1_2_BG_围攻')]:
    doc=E.parse(str(ROOT/'flashswf/backgrounds'/name/'DOMDocument.xml'))
    ls=doc.findall('x:timelines/x:DOMTimeline/x:layers/x:DOMLayer',NS)
    fixed=next((la for la in ls if la.get('name')=='fixed-coil-equipment'),None)
    check(fixed is None or len(fixed.findall('.//x:DOMSymbolInstance',NS))==0,'no duplicate full coil baked in starting scene '+name)
    armour=next(la for la in ls if la.get('name')=='armour-positions')
    vehicles=armour.findall('.//x:DOMSymbolInstance',NS)
    check(len(vehicles)==2 and all(e.find('x:matrix/x:Matrix',NS).get('a')=='0.45' and e.find('x:matrix/x:Matrix',NS).get('d')=='0.45' for e in vehicles),'defense highland scale '+name)
check(rooms[3].findtext('BasicInformation/Background')=='flashswf/backgrounds/gk20_1_BG_围攻.swf','siege gate must not load the shared helicopter background')
gate=E.parse(str(ROOT/'flashswf/backgrounds/gk20_1_BG_围攻/LIBRARY/BaseSiege/gate-without-helicopter.xml'))
check(not any(33<=int(la.get('name').split()[-1])<=64 for la in gate.findall('.//x:DOMLayer',NS)),'all gate helicopter/shadow placements removed')
hind=E.parse(str(ROOT/'flashswf/backgrounds/base_siege_hind/DOMDocument.xml'))
hull=next(e for e in hind.findall('.//x:DOMSymbolInstance',NS) if e.get('libraryItemName')=='Hind/G02/Assembly/Warlord_Static')
check(float(hull.find('x:matrix/x:Matrix',NS).get('a'))==1,'roof hull matches ordinary base scale')

# R5: the rhino position remains entirely tanks, with far-left reinforcement entry.
rhino=E.parse(str(ROOT/'flashswf/backgrounds/gk1_3_BG_围攻/DOMDocument.xml'))
armour=next(la for la in rhino.findall('.//x:DOMLayer',NS) if la.get('name')=='armour-positions')
check(all(e.get('libraryItemName')=='Practice34/R8/抬炮15度摆件25' for e in armour.findall('.//x:DOMSymbolInstance',NS)),'rhino position contains only rhino tanks')
check(all(float(p.findtext('x'))<100 for p in rooms[1].findall('SpawnPoint/Point')),'rhino reinforcements enter at far left')
crash=E.parse(str(ROOT/'flashswf/backgrounds/gk1_4_BG_坠毁/DOMDocument.xml'))
vehicle=next(e for e in crash.findall('.//x:DOMSymbolInstance',NS) if e.get('libraryItemName')=='Codex/雌鹿G04/坠毁摆件')
mat=vehicle.find('x:matrix/x:Matrix',NS)
check(float(mat.get('a'))==1 and float(mat.get('d'))==1,'crash helicopter matches roof scale')
check(abs(float(mat.get('ty'))+454-258)<.01,'crash helicopter preserves ground contact')


# R6: readable combat dialogue, complete optional documents, and damaged rooftop.
intel_names=['军阀装甲分队识别卡','军阀线圈操作须知','军阀阵地异常通报','军阀机降队通讯抄录','军阀撤收命令']
dictionary=E.parse(str(ROOT/'data/dictionaries/information_dictionary.xml'))
item_root=E.parse(str(ROOT/'data/items/收集品_情报.xml'))
indexes=[i.text for i in dictionary.findall('Item/Index')]
check(len(indexes)==len(set(indexes)),'intelligence indexes must be unique')
for name in intel_names:
    item=next((i for i in item_root.findall('item') if i.findtext('name')==name),None)
    check(item is not None and item.findtext('maxvalue')=='1' and item.findtext('use')=='情报','collectible intelligence '+name)
    entry=next((i for i in dictionary.findall('Item') if i.findtext('Name')==name),None)
    check(entry is not None and len(entry.findall('Information'))==1,'single optional page '+name)
    body=json.loads((ROOT/'data/intelligence_h5'/(name+'.json')).read_text(encoding='utf-8-sig'))
    legacy=(ROOT/'data/intelligence'/(name+'.txt')).read_text(encoding='utf-8-sig')
    texts=[node.get('text','') for b in body['pages'][0]['blocks'] for node in b.get('content',[])]
    check(body['itemName']==name and all(t in legacy for t in texts),'legacy/H5 text parity '+name)
outpost=E.parse(str(ROOT/'data/stages/基地房顶/军阀据点.xml'))
for n in intel_names:
    drops=[e for root in [stage,outpost] for e in root.findall('.//Enemy') if any(d.findtext('名字')==n for d in e.findall('Parameters/掉落物'))]
    check(len(drops)==1 and drops[0].findtext('Quantity')=='1','single existing enemy carrier '+n)
    if drops:
        intel=next(d for d in drops[0].findall('Parameters/掉落物') if d.findtext('名字')==n)
        check(intel.findtext('概率')=='100','guaranteed optional document '+n)
        sprite=ordinary[_resolve_id(drops[0].findtext('Type'))]['spritename']
        defaults=E.parse(str(ROOT/'data/enemy_properties/原版敌人 2011-2012.xml')).find(sprite).findall('掉落物')
        actual=[d for d in drops[0].findall('Parameters/掉落物') if d.findtext('名字')!=n]
        def fields(d):return sorted((c.tag,(c.text or '').strip()) for c in d)
        check([fields(d) for d in actual]==[fields(d) for d in defaults],'carrier preserves default drops '+n)
check(not any('军阀撤收命令'==d.findtext('名字') for d in stage.findall('.//掉落物')),'withdrawal account appears only after siege')
check(not any(any(term in (d.findtext('Text') or '') for term in ['犀牛','猛虎','雌鹿','冗余功放','天网复核','按互动键']) for d in stage.findall('.//Dialogue')),'combat lines avoid unexplained names and technical/input exposition')
check('spawner.prepareScene(currentStageInfo)' in manager and manager.index('spawner.prepareScene(currentStageInfo)') < manager.index('gameworld.dispatcher.publish("Start")'),'Start event spawns bind the new world before first wave init')
roof_doc=E.parse(str(ROOT/'flashswf/backgrounds/gk20_5_BG_围攻/DOMDocument.xml'))
roof_layers={l.get('name'):l for l in roof_doc.findall('.//x:DOMLayer',NS)}
check('R7-ground-evidence' in roof_layers and 'R8-fallen-defenders' in roof_layers,'roof includes strafing and fallen defenders')
gate_doc=E.parse(str(ROOT/'flashswf/backgrounds/gk20_1_BG_围攻/DOMDocument.xml'))
identities=['upper-gunner','lower-gunner','retreat-near-room','retreat-near-access']
for scene_doc,body_count,label in [(roof_doc,4,'roof'),(gate_doc,2,'gate')]:
    ls={la.get('name'):la for la in scene_doc.findall('x:timelines/x:DOMTimeline/x:layers/x:DOMLayer',NS)}
    body_layer=ls.get('R8-fallen-defenders');gun_layer=ls.get('R8-grounded-M2-posts')
    body_refs=[e.get('libraryItemName') for e in body_layer.findall('.//x:DOMSymbolInstance',NS)] if body_layer is not None else []
    gun_refs=[e.get('libraryItemName') for e in gun_layer.findall('.//x:DOMSymbolInstance',NS)] if gun_layer is not None else []
    check(body_refs==['BaseSiege/R8/defenders/'+k for k in identities[:body_count]],'gunner identity and defender count '+label)
    check(set(gun_refs)=={'BaseSiege/R8/m2-post-upper','BaseSiege/R8/m2-post-lower','BaseSiege/R8/tripod-grounded'},'whole M2 guns and grounded lower stand '+label)
    check(not any(k in ls for k in ['R7-destroyed-M2-posts','R7-cover-and-wall-strikes','R7-fallen-defenders']),'obsolete R7 gun and body layers removed '+label)
check(not any(e.get('libraryItemName')=='Symbol 32' for e in gate.findall('.//x:DOMSymbolInstance',NS)),'gate no longer shows intact original M2 placements')
r8=json.loads((ROOT/'tools/base-siege-assets/source/revision-r8-detail.json').read_text(encoding='utf-8'))
check(len({d['hair'] for d in r8['defenders'].values()})==4,'four distinct rooftop hairstyles')
check(len({d['poseFrame0'] for d in r8['defenders'].values()})==4,'four original bloody-death poses')
for ident,entry in r8['defenders'].items():
    check(entry['hair'] not in ['平头','黑圆平头','黑贴头'],'roof hair avoids both TIGR silhouettes '+ident)
    head=E.parse(str(ROOT/'flashswf/backgrounds/gk20_5_BG_围攻/LIBRARY/BaseSiege/R8/heads'/(ident+'.xml')))
    check('BaseSiege/R8/hair/发型/发型-男式-'+entry['hair'] in [e.get('libraryItemName') for e in head.findall('.//x:DOMSymbolInstance',NS)],'native hairstyle binding '+ident)
for n,h in r8['unchangedTigrBodies'].items():
    p=ROOT/f'flashswf/backgrounds/gk1_2_BG_围攻/LIBRARY/BaseSiege/casualties/part{n}.xml'
    check(hashlib.sha256(p.read_bytes()).hexdigest()==h,'existing TIGR defender remains unchanged '+n)
for model in ['m2-native','m2-post-upper','m2-post-lower','tripod-grounded']+['defenders/'+k for k in identities]+['heads/'+k for k in identities]:
    paths=[ROOT/'flashswf/backgrounds'/s/'LIBRARY/BaseSiege/R8'/(model+'.xml') for s in ['gk20_5_BG_围攻','gk20_1_BG_围攻']]
    check(paths[0].read_bytes()==paths[1].read_bytes(),'two views share damage and defender art '+model)
for scene,original,standing,removed in [('gk20_5_BG_围攻','original-background','Symbol 38','Symbol 33'),('gk20_1_BG_围攻','gate-without-helicopter','Symbol 33','Symbol 28')]:
    bg=E.parse(str(ROOT/'flashswf/backgrounds'/scene/'LIBRARY/BaseSiege'/(original+'.xml')))
    refs=[e.get('libraryItemName') for e in bg.findall('.//x:DOMSymbolInstance',NS)]
    check(refs.count(standing)==1 and removed not in refs,'upper support retained and lower orphan stand removed '+scene)

roof_original=E.parse(str(ROOT/'flashswf/backgrounds/gk20_5_BG_围攻/LIBRARY/BaseSiege/original-background.xml'))
check(not any(e.get('libraryItemName') in ['Symbol 27','Symbol 37'] for e in roof_original.findall('.//x:DOMSymbolInstance',NS)),'intact roof ammunition and sentry guns are removed from original layer')
effect=E.parse(str(ROOT/'flashswf/backgrounds/base_siege_coil/LIBRARY/BaseSiege/coil-effect-powered/root.xml'))
exposures=effect.findall('.//x:DOMFrame',NS)
check(max(int(f.get('index'))+int(f.get('duration','1')) for f in exposures)==36,'coil effect has 36 native frames')

print(json.dumps({'ok':not errors,'scenes':len(rooms),'waveEnemies':wave_enemies,'scriptedReactionEnemies':0,'nativeAssets':len(NAMES),'nativeSymbols':symbols,'errors':errors},ensure_ascii=False))
sys.exit(1 if errors else 0)
