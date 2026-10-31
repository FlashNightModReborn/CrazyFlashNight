"""CF6 two-phase soldier: native R3/R4 art and standard CF7 long guns."""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import sys
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import elite
import holster
import art_revision
import tactics
ARCHIVE = ROOT / 'flashswf/arts/new/Codex素材源稿/CF6特种兵-R3'
SHIELD_ARCHIVE = ROOT / 'flashswf/arts/new/Codex素材源稿/CF6特种兵-持盾-R4'
OWNER = ROOT / 'flashswf/arts/new/Codex特种兵素材'
ANCHOR = 'Codex特种兵素材'
LINKAGE = '敌人-CF6特种兵'
SHIELD_LINKAGE = '敌人-CF6持盾特种兵'
PREFIX = 'Codex/特种兵/'
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}
N = '{' + NS['x'] + '}'
PARSER = E.XMLParser(remove_blank_text=False, strip_cdata=False, resolve_entities=False)
SEQUENCES = {498:'站立', 500:'行走', 507:'长枪点射与装填', 517:'匕首刺击',
             518:'被击', 519:'被投', 520:'击倒原稿', 558:'死亡'}
SHIELD_SEQUENCES = {562:'持盾站立',563:'持盾行走',564:'持盾点射与装填',
                    573:'持盾匕首刺击',574:'持盾被击',579:'破盾'}
# A single grounding translation applies to every body. The death first pose
# is aligned using the identical pelvis, independently of the image crop.
GROUND_SHIFT = -12.500106811523438
OFFSETS = {498:(25.5,-54.45), 500:(25.6,-53.55), 507:(4.75,-62.05),
           517:(26.5,-53.5), 518:(8.95,-59.95), 519:(16.9,-65.4),
           520:(5.5,-59), 558:(8,-59.9)}
OFFSETS.update({562:(25.5,-54.45),563:(25.6,-53.55),564:(4.75,-62.05),
                573:(26.5,-53.5),574:(7.15,-58.1),579:(25.25,-55.25)})


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


audio = module('cf6_audio_native',ROOT/'tools/cf6-audio/build.py')
common = module('soldier_common', ROOT / 'tools/cf6-manman-assets/build.py')
vector = module('soldier_vector', HERE / 'vector.py')
native = common.native
for key, value in {'ROOT':ROOT, 'HERE':HERE, 'OWNER':OWNER, 'ARCHIVE':ARCHIVE,
                   'ANCHOR':ANCHOR, 'LINKAGE':LINKAGE, 'PREFIX':PREFIX}.items():
    setattr(common, key, value)
native.OWNER, native.HERE = OWNER, HERE
native.MANIFEST_SCHEMA = 'cf6-soldier.native-import.v1'
native.PROJECT_FILES = ('DOMDocument.xml', ANCHOR+'.xfl', 'PublishSettings.xml', 'MobileSettings.xml')
native.SHARED_HELPERS = {old:PREFIX+'CF7/'+old for old in native.SHARED_HELPERS}
H = native.SHARED_HELPERS


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_inputs():
    paths = [HERE/'build.py', HERE/'vector.py', HERE/'holster.py', HERE/'SoldierAI.as',
        ROOT/'tools/cf6-wings-assets/vector.py', ROOT/'tools/cf6-manman-assets/build.py',
        ROOT/'tools/cf6-zombie-assets/build.py', ROOT/'tools/gamma-echo-assets/build.py',
        ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',
        ROOT/'tools/asset-metrology/xfl_geometry.py',
        ROOT/'flashswf/arts/new/Codex黑仔素材/PublishSettings.xml']
    paths += [native.THINGS1/(old+'.xml') for old in sorted(H)]
    paths += [ROOT/'scripts/逻辑/单位函数/单位函数_lsy_主角射击函数.as',
        ROOT/'scripts/逻辑/单位函数/单位函数_lsy_敌人特殊函数.as',
        ROOT/'scripts/逻辑/单位函数/单位函数_fs_装备引用配置.as',
        ROOT/'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as',
        ROOT/'scripts/逻辑/单位函数/单位函数_lsy_主角技能.as',
        SHIELD_ARCHIVE/'archive-origin.json']
    paths += elite.input_paths() + art_revision.input_paths() + tactics.input_paths()
    paths += [ROOT/'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootCore.as',
        ROOT/'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/FireEventComponent.as']
    rows = []
    for p in paths:
        data = p.read_bytes()
        row = {'path':p.relative_to(ROOT).as_posix()}
        # Shared runtime AS2 contracts follow Git's text normalization. Bind the
        # same UTF-8 source across LF/CRLF checkouts without rewriting those files.
        if p.suffix == '.as' and p.parent != HERE:
            data = data.replace(b'\r\n', b'\n')
            row['lineEndingNormalization'] = 'lf'
        row['sha256'] = hashlib.sha256(data).hexdigest()
        rows.append(row)
    return rows


def depth_layers(timeline, parts):
    layers = []
    for depth in sorted({int(d) for f in timeline for d, row in f.items() if row['id'] in parts}, reverse=True):
        states = [f.get(str(depth)) if f.get(str(depth), {}).get('id') in parts else None for f in timeline]
        frames, start = [], 0
        while start < len(states):
            row, end = states[start], start+1
            def visual(value):
                return None if value is None else (value['id'], value['matrix'], value.get('colorMult'), value.get('colorAdd'))
            while end < len(states) and visual(states[end]) == visual(row):
                end += 1
            elements = []
            if row is not None:
                gun = row['id'] == 492
                inst = native.instance(parts[row['id']], matrix=row['matrix'],
                    **({'symbol_type':'movie clip', 'name':'枪'} if gun else
                       {'symbol_type':'movie clip', 'name':'腰挂'} if row['id'] == 489 else {}))
                if inst.get('symbolType')=='graphic':
                    inst.set('loop','single frame');inst.set('firstFrame','0')
                if row['id'] == 484:
                    inst.set('symbolType','movie clip')
                    inst.set('name','腿挂匕首')
                    script=E.SubElement(E.SubElement(inst,N+'Actionscript'),N+'script')
                    script.text=E.CDATA('onClipEvent(load){_visible=_parent._parent.soldierIsElite!==true || _parent._parent.soldierIsInstructor===true;}')
                mult, add = row.get('colorMult', [256]*4), row.get('colorAdd', [0]*4)
                if mult != [256]*4 or add != [0]*4:
                    color = E.SubElement(E.SubElement(inst, N+'color'), N+'Color')
                    for i, channel in enumerate(('red','green','blue','alpha')):
                        color.set(channel+'Multiplier', native.num(mult[i]/256))
                        color.set(channel+'Offset', native.num(add[i]))
                elements.append(inst)
            frames.append(native.frame(start, end-start, elements))
            start = end
        layers.append(native.layer('原始深度_'+str(depth), frames))
    return layers


def make_body(name, timeline, parts, scripts=None):
    return native.symbol(name, [native.make_sparse_layer('CF7生命周期',len(timeline),scripts or {}),
        *depth_layers(timeline,parts)], symbol_type='movie clip')


def build_symbols():
    common.verify_input()
    verify_shield_input()
    timeline = json.loads((ARCHIVE/'reference/timelines.json').read_text(encoding='utf8'))
    shield_timeline = json.loads((SHIELD_ARCHIVE/'reference/timelines.json').read_text(encoding='utf8'))
    timeline.update({str(sid):shield_timeline[str(sid)] for sid in SHIELD_SEQUENCES})
    assets = {r['id']:r for r in json.loads((ARCHIVE/'asset-manifest.json').read_text(encoding='utf8'))['assets']}
    required = {r['id'] for sid in SEQUENCES for f in timeline[str(sid)] for r in f.values()}
    required -= {281,290,299,311,359,360,492,506}
    if len(required) != 58:
        raise ValueError('Ordinary soldier drawing closure changed')
    shield_required = {r['id'] for sid in SHIELD_SEQUENCES for f in timeline[str(sid)] for r in f.values()}
    shield_required -= required | {281,290,299,311,359,360,492,506}
    if shield_required != {561,565,566,567,568,569,570,571,572,575,577,578}:
        raise ValueError('Shield drawing closure changed')
    shield_assets = {r['id']:r for r in json.loads((SHIELD_ARCHIVE/'asset-manifest.json').read_text(encoding='utf8'))['assets']}
    result, parts, stats = native.clone_shared_helpers(), {}, []
    vector.NativePart.shared_references = {}
    for cid in sorted(required | shield_required):
        name = PREFIX+'分件/'+str(cid)
        source = SHIELD_ARCHIVE/shield_assets[cid]['file'] if cid in shield_required else ARCHIVE/assets[cid]['file']
        converted, report = (holster.build(source,name,native,vector) if cid == 489
            else vector.NativePart(source,name,(0,0)).build())
        for key, item in converted.items():
            if key in result and native.xml_bytes(result[key]) != native.xml_bytes(item):
                raise ValueError('Conflicting shared atlas: '+key)
        result.update(converted)
        parts[cid] = name
        stats.append({'id':cid, **report})

    # A graphic instance can be flattened together with neighbouring artwork by
    # CS6. Its clip event must not hide that merged body drawing. Give the knife
    # a real MovieClip boundary before attaching the role visibility event.
    knife_wrapper=PREFIX+'装备/腿挂匕首'
    result[knife_wrapper]=native.symbol(knife_wrapper,[native.layer('独立腿挂',[
        native.frame(script='stop();',elements=[native.instance(parts[484])])])],symbol_type='movie clip')
    parts[484]=knife_wrapper

    # Match the standard man.枪.枪.装扮 path and register only the weapon skin.
    # CF6 body parts stay native; weapon art remains owned by its existing RSL.
    holder = PREFIX+'武器/长枪挂点'
    result[holder] = native.symbol(holder,[native.layer('挂点',[native.frame(script='stop();')])],symbol_type='movie clip')
    weapon = PREFIX+'武器/可配置长枪'
    result[weapon] = native.symbol(weapon,[native.layer('标准长枪引用',[native.frame(
        script='stop();',elements=[native.instance(holder,symbol_type='movie clip',name='枪',matrix=(0.8,0,0,0.8,0,0),
            script='onClipEvent(load){var unit:MovieClip=_parent._parent._parent;_root.装备引用配置.配置装扮(this,unit.长枪_装扮,"装扮","长枪_引用");}')])])],symbol_type='movie clip')
    parts[492] = weapon
    actions = {sid:PREFIX+'动作/'+name for sid,name in SEQUENCES.items()}
    actions.update({sid:PREFIX+'动作/'+name for sid,name in SHIELD_SEQUENCES.items()})
    for sid in actions:
        if any(sum(r['id']==492 for r in f.values())>1 for f in timeline[str(sid)]):
            raise ValueError('More than one gun requires explicit ownership: '+str(sid))

    result[actions[498]] = make_body(actions[498],timeline['498'],parts,
        {4:{'script':'if(_parent.状态=="躲闪" || _parent.状态=="拾取") _parent.动画完毕();'}})
    result[actions[500]] = make_body(actions[500],timeline['500'],parts)
    # The existing shooting scheduler owns emission timing. A real shot selects
    # the CF6 recoil pose; the authored three-shot gesture is no longer a timer.
    # Reload uses the ready pose and a 35-frame standard burden-controlled phase.
    shooting_timeline = timeline['507'] + [copy.deepcopy(timeline['507'][0]) for _ in range(35)]
    result[actions[507]] = native.symbol(actions[507],[
        native.make_sparse_layer('标准射击与装填',49,{
            0:{'script':'_parent.soldierBeginAttack(this,"shoot");'},
            2:{'name':'射击','label_type':'name'},
            5:{'script':'gotoAndStop("空闲");'},
            13:{'name':'空闲','label_type':'name','script':'stop();'},
            14:{'name':'换弹匣','label_type':'name','script':'_parent.soldierReloadStart(this);'},
            34:{'script':'_root.主角函数.换弹门禁(this);'},
            46:{'script':'if(_parent.soldierCanAct(this))换弹匣();'},
            48:{'script':'_parent.soldierReloadEnd(this);'}}),
        native.make_sparse_layer('标准射击许可',49,{0:{'duration':14,'elements':[
            native.instance(holder,symbol_type='movie clip',name='射击许可标签')]}}),
        *depth_layers(shooting_timeline,parts)],symbol_type='movie clip')
    knife_height = 135
    center_y = -knife_height/2 - OFFSETS[517][1] - GROUND_SHIFT
    result[actions[517]] = native.symbol(actions[517],[
        native.make_sparse_layer('攻击生命周期',34,{
            0:{'script':'_parent.soldierBeginAttack(this,"knife");'},
            33:{'script':'_parent.soldierFinishAttack(this);'}}),
        native.make_sparse_layer('真实近战判定',34,{13:{'elements':[
            native.instance(H['Symbol 195'],matrix=(135/25,0,0,knife_height/25,27.3,center_y),
                symbol_type='movie clip',name='攻击点',alpha_mult=0,
                script='onClipEvent(load){ _parent._parent.soldierStab(_parent,this); }')]}}),
        *depth_layers(timeline['517'],parts)],symbol_type='movie clip')
    result[actions[518]] = make_body(actions[518],timeline['518'],parts,{
        0:{'name':'a0','label_type':'name'},12:{'name':'a1','label_type':'name'},
        7:{'script':'_parent.动画完毕();'},18:{'script':'_parent.动画完毕();'}})
    result[actions[519]] = make_body(actions[519],timeline['519'],parts,{12:{'script':'stop();'}})
    airborne, down = PREFIX+'动作/击飞', PREFIX+'动作/倒地恢复'
    result[airborne] = make_body(airborne,timeline['520'][:40],parts,{
        0:{'name':'空手','label_type':'name'},39:{'script':'stop();'}})
    result[down] = make_body(down,timeline['520'][40:],parts,{
        8:{'script':'_parent.死亡检测();'},75:{'script':'_parent.动画完毕();'}})
    result[actions[558]] = make_body(actions[558],timeline['558'],parts,{
        0:{'name':'a0','label_type':'name'},58:{'name':'a1','label_type':'name'},104:{'name':'a2','label_type':'name'},
        57:{'script':'_parent.死亡检测(); stop();'},103:{'script':'_parent.死亡检测(); stop();'},
        138:{'script':'_parent.死亡检测(); stop();'}})

    result[actions[562]] = make_body(actions[562],timeline['562'],parts,{
        4:{'script':'if(_parent.状态=="躲闪" || _parent.状态=="拾取") _parent.动画完毕();'}})
    result[actions[563]] = make_body(actions[563],timeline['563'],parts)
    # Keep the same CF7 lifecycle layers, with the independently authored R4 poses.
    for ordinary,shield in ((507,564),(517,573)):
        layers = result[actions[ordinary]].find('x:timeline/x:DOMTimeline/x:layers',NS)
        artwork = timeline[str(shield)]
        if shield==564:
            artwork = artwork + [copy.deepcopy(artwork[0]) for _ in range(35)]
        result[actions[shield]] = native.symbol(actions[shield],[
            *[copy.deepcopy(x) for x in list(layers)[:2]],*depth_layers(artwork,parts)],symbol_type='movie clip')
    result[actions[574]] = make_body(actions[574],timeline['574'],parts,{
        0:{'name':'a0','label_type':'name'},12:{'name':'a1','label_type':'name'},
        7:{'script':'_parent.动画完毕();'},18:{'script':'_parent.动画完毕();'}})
    result[actions[579]] = make_body(actions[579],timeline['579'],parts,{
        0:{'script':'soldierPhaseToken=_parent.soldierPhaseToken;stop();'},10:{'script':'stop();'}})

    driver = PREFIX+'行为驱动'
    result[driver] = native.symbol(driver,[native.layer('停止',[native.frame(script='stop();')])],symbol_type='movie clip')
    shadow = result[H['Symbol 2']]
    shadow.set('symbolType','movie clip')
    shadow.find('x:timeline/x:DOMTimeline/x:layers',NS).insert(0,native.layer('全状态接地',[native.frame(script='''soldierGround={x:0,y:0};
updateSoldierShadow=function():Void {
    var unit:MovieClip=this._parent;
    var visible:Boolean=_root.是否阴影==true;
    if(this._visible!=visible) this._visible=visible;
    if(isNaN(unit.Z轴坐标)) return;
    var p:Object=this.soldierGround; p.x=unit._x; p.y=unit.Z轴坐标;
    unit._parent.localToGlobal(p);unit.globalToLocal(p);
    if(this._x!=p.x) this._x=p.x;if(this._y!=p.y) this._y=p.y;
    var rotation:Number=unit._xscale<0?unit._rotation:-unit._rotation;
    if(this._rotation!=rotation) this._rotation=rotation;
};
onEnterFrame=updateSoldierShadow;updateSoldierShadow();stop();''')]))

    def body(sid,script=None,name=None):
        x,y = OFFSETS[sid]
        return native.instance(name or actions[sid],matrix=(1,0,0,1,x,y+GROUND_SHIFT),
            symbol_type='movie clip',name='man',script=script)
    states = {1:'长枪站立',9:'长枪行走',19:'长枪跑',29:'长枪跳',37:'近战',41:'长枪攻击',
        51:'拾取',61:'躲闪',71:'被击',79:'击倒',88:'倒地',95:'被投',104:'血腥死',
        130:'持盾站立',140:'持盾行走',160:'持盾跑',180:'持盾攻击',190:'持盾近战',194:'持盾被击',202:'破盾',220:'消失'}
    init = '''hasDressup=true;enableShoot=true;攻击模式="长枪";
x轴攻击范围=0;y轴攻击范围=24;x轴保持距离=190;攻击欲望=3;命中率=20;
if(!长枪){var pool:Array=_root.敌人函数.大学军校学员随机兵器表;长枪=pool[random(pool.length)];}
根据模式重新读取武器加成=_root.主角函数.根据模式重新读取武器加成;
'''+(HERE/'SoldierAI.as').read_text(encoding='utf-8-sig')+'\n'+(HERE/'SoldierRoles.as').read_text(encoding='utf-8-sig')+'''
_root.敌人函数.配置音效("人类",this);
初始化敌人模板=_root.初始化敌人模板;初始化敌人模板();
soldierInitializePhase();
'''
    bodies = {0:(9,body(498)),9:(10,body(500)),19:(10,body(500)),29:(8,body(519)),
        37:(4,body(517)),41:(10,body(507)),51:(10,body(498)),61:(10,body(498)),
        71:(8,body(518,'onClipEvent(load){_parent.soldierCancelAttack();gotoAndPlay("a"+random(2));}')),
        79:(9,body(520,'onClipEvent(load){_parent.soldierCancelAttack();_parent.击飞浮空();}',airborne)),
        88:(7,body(520,'onClipEvent(load){_parent.soldierCancelAttack();_parent.击飞倒地();}',down)),
        95:(9,body(519,'onClipEvent(load){_parent.soldierCancelAttack();}')),
        104:(16,body(558,'onClipEvent(load){_parent.soldierCancelAttack();gotoAndPlay("a"+random(3));}')),
        130:(10,body(562)),140:(20,body(563)),160:(20,body(563)),180:(10,body(564)),
        190:(4,body(573)),194:(8,body(574,'onClipEvent(load){_parent.soldierCancelAttack();gotoAndPlay("a"+random(2));}')),
        202:(18,body(579))}
    root_name = PREFIX+LINKAGE
    result[root_name] = native.symbol(root_name,[
        native.make_sparse_layer('状态标签',225,{i:{'name':s,'label_type':'name'} for i,s in states.items()}),
        native.make_sparse_layer('初始化与消失',225,{0:{'script':'soldierDefaultPhase=2;\n'+init},1:{'script':'this.swapDepths(this._y);'},220:{'script':'hp=0;soldierCancelAttack();'}}),
        native.make_sparse_layer('私有行为',225,{0:{'duration':220,'elements':[
            native.instance(driver,symbol_type='movie clip',name='soldierDriver',script='onClipEvent(enterFrame){_parent.soldierTick();}onClipEvent(unload){_parent.soldierReleaseTactics();}')]}}),
        native.make_sparse_layer('文字信息',225,{0:{'duration':220,'elements':[
            native.instance(H['Symbol 32'],matrix=(1,0,0,1,0,-150),symbol_type='movie clip',name='人物文字信息')]}}),
        native.make_sparse_layer('受击包围盒',225,{0:{'duration':79,'elements':[
            native.instance(H['Symbol 19'],matrix=(3.2,0,0,5.2,-44,-132),symbol_type='movie clip',name='area')]},
            79:{'duration':9,'elements':[native.instance(H['Symbol 19'],matrix=(3.2,0,0,5.2,-44,-132),symbol_type='movie clip',name='area')]},
            88:{'duration':7,'elements':[native.instance(H['Symbol 19'],matrix=(5.4,0,0,1.7,-68,-43),symbol_type='movie clip',name='area')]},
            95:{'duration':9,'elements':[native.instance(H['Symbol 19'],matrix=(3.2,0,0,5.2,-44,-132),symbol_type='movie clip',name='area')]},
            130:{'duration':90,'elements':[native.instance(H['Symbol 19'],matrix=(3.2,0,0,5.2,-44,-132),symbol_type='movie clip',name='area')]}}),
        native.make_sparse_layer('通用索敌',225,{i:{'duration':d,'elements':[native.instance(H['思考标签'],symbol_type='movie clip')]} for i,d in ((0,29),(130,50))}),
        native.make_sparse_layer('行走',225,{i:{'duration':d,'elements':[
            native.instance(driver,symbol_type='movie clip',name='控制块',script='onClipEvent(enterFrame){if(!_root.暂停)_parent.行走();}')]} for i,d in ((0,29),(130,50))}),
        native.make_sparse_layer('动作',225,{i:{'duration':d,'elements':[b]} for i,(d,b) in bodies.items()}),
        native.make_sparse_layer('全状态接地阴影',225,{0:{'duration':220,'elements':[
            native.instance(H['Symbol 2'],matrix=(0.62,0,0,0.14,0,0),symbol_type='movie clip',name='soldierShadow')]}}),
    ],symbol_type='movie clip',linkage=LINKAGE,export_first_frame=True)
    shield_root = PREFIX+SHIELD_LINKAGE
    shield_layers = copy.deepcopy(list(result[root_name].find('x:timeline/x:DOMTimeline/x:layers',NS)))
    script = shield_layers[1].find('.//x:script',NS)
    script.text = E.CDATA(script.text.replace('soldierDefaultPhase=2;','soldierDefaultPhase=1;',1))
    result[shield_root] = native.symbol(shield_root,shield_layers,symbol_type='movie clip',
        linkage=SHIELD_LINKAGE,export_first_frame=True)
    art_revision.install(sys.modules[__name__],result,parts,timeline)
    elite.install(result,native,PREFIX,LINKAGE,SHIELD_LINKAGE)
    art_revision.install_elite(sys.modules[__name__],result)
    tactics.install(sys.modules[__name__],result,parts)
    return result,root_name,stats


def verify_shield_input():
    origin = json.loads((SHIELD_ARCHIVE/'archive-origin.json').read_text(encoding='utf8'))
    for row in origin['members']:
        if sha(SHIELD_ARCHIVE/row['path'])!=row['sha256']:
            raise ValueError('Frozen shield input changed: '+row['path'])


def import_assets():
    native.guard_overwrite_allowed(False)
    prior_path = HERE/'native-manifest.json'
    prior_bytes = prior_path.read_bytes() if prior_path.exists() else None
    prior = json.loads(prior_bytes) if prior_bytes is not None else None
    symbols,root_name,stats = build_symbols()
    native.guard_overwrite_allowed(False)
    wanted = {'LIBRARY/'+name+'.xml' for name in [*symbols,ANCHOR]}
    obsolete = [row for row in prior['outputs'] if row['path'] not in wanted] if prior else []
    if obsolete:
        backup = (ROOT/'tmp/cf6-soldier-regeneration'/hashlib.sha256(prior_bytes).hexdigest()).resolve()
        if not backup.is_relative_to((ROOT/'tmp').resolve()):
            raise ValueError('Regeneration archive escaped the workspace')
        backup.mkdir(parents=True,exist_ok=True)
        saved_manifest = backup/'native-manifest.json'
        if saved_manifest.exists() and saved_manifest.read_bytes()!=prior_bytes:
            raise ValueError('Prior manifest archive differs')
        saved_manifest.write_bytes(prior_bytes)
        for row in obsolete:
            source = (OWNER/row['path']).resolve()
            target = (backup/row['path']).resolve()
            if not source.is_relative_to(OWNER.resolve()) or not target.is_relative_to(backup) or sha(source)!=row['sha256']:
                raise ValueError('Unowned obsolete native symbol')
            target.parent.mkdir(parents=True,exist_ok=True)
            if target.exists() and sha(target)!=row['sha256']:
                raise ValueError('Obsolete symbol archive differs')
            target.write_bytes(source.read_bytes())
    audio_receipt=audio.apply(symbols,OWNER,native.make_sparse_layer)
    outputs = common.write_workspace(symbols,root_name)
    # List children before their users and keep each Include identity equal to
    # the referenced symbol. Preserve lazy loading to bound CS6 memory use.
    document_path = OWNER/'DOMDocument.xml'
    document = E.parse(str(document_path),PARSER).getroot()
    includes=document.find('x:symbols',NS)
    entries={i.get('href')[:-4]:i for i in includes}
    ordered=[];visiting=set();visited=set()
    def visit(name):
        if name in visiting:raise ValueError('Cyclic native symbol '+name)
        if name in visited:return
        visiting.add(name)
        root=symbols.get(name)
        if root is not None:
            for ref in sorted({i.get('libraryItemName') for i in root.findall('.//x:DOMSymbolInstance',NS)}):
                visit(ref)
        visiting.remove(name);visited.add(name)
        include=entries[name]
        include.set('loadImmediate','false')
        if root is not None and root.get('itemID'):include.set('itemID',root.get('itemID'))
        ordered.append(include)
    for name in sorted(entries):visit(name)
    includes[:]=ordered
    document_path.write_bytes(native.xml_bytes(document))
    # CS6 lazily resolves off-stage export dependencies. An exported root absent
    # from the stage closure compiled its child movies as one-frame placeholders.
    # A stopped, unreachable second anchor frame forces that closure to load,
    # without spawning a second live blueprint while the RSL anchor is loaded.
    anchor_path = OWNER/'LIBRARY'/(ANCHOR+'.xml')
    anchor = E.parse(str(anchor_path),PARSER).getroot()
    anchor.find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer/x:frames',NS).append(
        native.frame(1,elements=[native.instance(PREFIX+SHIELD_LINKAGE,symbol_type='movie clip')]))
    for index,link in enumerate(elite.LINKAGES,2):
        anchor.find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer/x:frames',NS).append(
            native.frame(index,elements=[native.instance(PREFIX+link,symbol_type='movie clip')]))
    for index,link in enumerate(tactics.LINKAGES,4):
        anchor.find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer/x:frames',NS).append(
            native.frame(index,elements=[native.instance(tactics.PREFIX+link,symbol_type='movie clip')]))
    anchor.find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer/x:frames',NS).append(
        native.frame(6,elements=[native.instance(PREFIX+'烟雾/烟雾',symbol_type='movie clip')]))
    anchor_path.write_bytes(native.xml_bytes(anchor))
    for row in outputs:
        if row['path']=='LIBRARY/'+ANCHOR+'.xml':
            row.update(sha256=sha(anchor_path),bytes=anchor_path.stat().st_size)
    for row in obsolete:
        source = (OWNER/row['path']).resolve()
        if not source.is_relative_to(OWNER.resolve()) or sha(source)!=row['sha256']:
            raise ValueError('Obsolete symbol changed during regeneration')
        source.unlink()
    manifest = {'schema':native.MANIFEST_SCHEMA,'owner':OWNER.relative_to(ROOT).as_posix(),
        'approvedInput':ARCHIVE.relative_to(ROOT).as_posix(),'nativeSymbolCount':len(outputs),
        'shieldInput':SHIELD_ARCHIVE.relative_to(ROOT).as_posix(),'shieldRoot':580,
        'phaseLinkages':{LINKAGE:2,SHIELD_LINKAGE:1,elite.LINKAGES[0]:2,elite.LINKAGES[1]:1,tactics.LINKAGES[0]:2,tactics.LINKAGES[1]:1},'phaseParameter':'特种兵初始阶段',
        'shieldBreakFrames':11,'secondLifeRatio':0.35,
        'buildInputs':build_inputs(),'parts':stats,'groundShift':GROUND_SHIFT,
        'sourceOffsets':{str(k):v for k,v in OFFSETS.items()},'ordinaryRoot':559,
        'legacySourceBodyFrames':378,'motionInput':art_revision.SOURCE.relative_to(ROOT).as_posix(),
        'motionEvaluation':'Animate 24 native keyframes with parenting matrices',
        'shootingAuthority':'ShootInitCore / ShootCore / WeaponFireCore',
        'shootingPoseFrame':3,'burstShots':tactics.load_profiles()['roles']['ordinary']['rifleShots'],'reloadFrames':[15,49],'knifeHitFrame':14,
        'deathBranches':[[1,58],[59,104],[105,139]],'airborneFrames':29,'landedFrames':78,
        'deathThirdBranch':'New fall frames 1-14 followed by 21 settled hold frames',
        'ordinaryRole':{'shieldActions':['standShoot','stab','bash'],'grenadeDefault':'高爆手雷',
            'grenadeActionFrames':36,'grenadeReleaseFrame':25,'legKnife':True,'waistGrenades':True},
        'eliteRole':{'shieldActions':['chargeShoot'],'chargeFrames':[10,24,12],
            'pairReloadFrames':[331,365],'pairReloadCommit':363,'legKnife':False,'waistGrenades':True,'reloadVisual':'smoke and authored run','slideEntry':'successful smoke reload only'},
        'instructorRole':{'artSource':tactics.SOURCE.relative_to(ROOT).as_posix(),'strategy':'adaptive','sharedActions':True},
        'tacticalProfiles':tactics.load_profiles(),
        'weaponSource':'Existing long-gun equipment and shared cadet pool; external primary wins',
        'weaponHolderPath':'man.枪.枪.装扮','outputs':outputs,
        'projectFiles':[{'path':p,'sha256':sha(OWNER/p),'bytes':(OWNER/p).stat().st_size} for p in native.PROJECT_FILES]}
    manifest['audio']=audio_receipt
    (HERE/'native-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
    common.mount_shared_library()
    print(json.dumps({'symbols':len(outputs),'linkage':LINKAGE},ensure_ascii=False))


def check():
    common.verify_input()
    verify_shield_input()
    manifest = json.loads((HERE/'native-manifest.json').read_text(encoding='utf8'))
    audio.check(manifest,OWNER)
    errors = native.workspace_identity_failures(manifest)
    if manifest['buildInputs'] != build_inputs():
        errors.append('Generator inputs changed; guarded regeneration required')
    includes = {i.get('href') for i in E.parse(str(OWNER/'DOMDocument.xml')).findall('x:symbols/x:Include',NS)}
    masks_checked = 0
    item_ids = {}
    for row in manifest['outputs']:
        tree = E.parse(str(OWNER/row['path']),PARSER)
        item_id=tree.getroot().get('itemID')
        if item_id:
            if item_id in item_ids:errors.append('Duplicate library itemID '+item_id+': '+item_ids[item_id]+' / '+row['path'])
            item_ids[item_id]=row['path']
        if row['path'][8:] not in includes:
            errors.append('Missing Include: '+row['path'])
        for element in tree.iter():
            ref = element.get('libraryItemName')
            if ref and not (OWNER/'LIBRARY'/(ref+'.xml')).is_file():
                errors.append('Unresolved '+ref)
            if ref and element.find('x:Actionscript',NS) is not None:
                linked=E.parse(str(OWNER/'LIBRARY'/(ref+'.xml')),PARSER).getroot()
                if linked.get('symbolType')=='graphic':
                    errors.append('Clip event requires a real MovieClip library symbol: '+ref)
        if tree.findall('.//x:BitmapFill',NS) or tree.findall('.//x:DOMBitmapInstance',NS):
            errors.append('Unexpected bitmap '+row['path'])
        layers = tree.findall('.//x:DOMLayer',NS)
        if len(layers)==2 and layers[0].get('layerType')=='mask':
            masks_checked += 1
            mask,paint = native._layer_bbox(layers[0]),native._layer_bbox(layers[1])
            if not mask or not paint or min(mask[1],paint[1])<=max(mask[0],paint[0]) or min(mask[3],paint[3])<=max(mask[2],paint[2]):
                errors.append('Empty or disjoint native mask '+row['path'])
    if errors:
        raise ValueError('\n'.join(sorted(set(errors))))
    print(json.dumps({'ok':True,'symbols':len(manifest['outputs']),'projectFiles':len(manifest['projectFiles']),'masksChecked':masks_checked}))


if __name__ == '__main__':
    if hasattr(sys.stdout,'reconfigure'):
        sys.stdout.reconfigure(encoding='utf8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--import-approved',action='store_true')
    parser.add_argument('--check',action='store_true')
    args = parser.parse_args()
    if args.import_approved:
        import_assets()
    check()
