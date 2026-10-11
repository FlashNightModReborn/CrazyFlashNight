"""Assemble the sheriff's independent NPC rig from authored player motion.

The player library remains the donor. Only a namespaced dependency closure is
copied into the existing Codex library; the two merchant NPCs are unchanged.
CS6, not this tool, publishes the resulting XFL.
"""
from pathlib import Path
import argparse, copy, hashlib, json, re, shutil
from lxml import etree as E
import build as b

PREFIX = 'Codex/前治安官/'
DONOR = b.ROOT / 'flashswf/arts/things0/LIBRARY'
GENERATED = {}
MAPPING = {}
MEDIA = {}
DONOR_DOC = E.parse(str(DONOR.parent/'DOMDocument.xml'), b.PARSER)
BAKED_PLACEMENTS = 0
ARMOR = {field+'_引用': b.PREFIX+'部件/'+field for field in
         ['身体','上臂','左下臂','右下臂','左手','右手','屁股','左大腿','右大腿','小腿','脚']}
WEAPONS = {'长枪_引用':'枪-长枪-Codex-特勤霰弹枪',
           '手枪_引用':'枪-手枪-Codex-特勤沙鹰','刀_引用':'刀-Codex-特勤警棍'}


def fixed_weapon(ref):
    name=PREFIX+'固定装备/'+ref
    if name not in GENERATED:
        skin=next(E.parse(str(p),b.PARSER).getroot().get('name')
                  for p in (b.OWNER/'LIBRARY'/b.PREFIX).rglob('*.xml')
                  if E.parse(str(p),b.PARSER).getroot().get('linkageIdentifier')==WEAPONS[ref])
        # Preserve the native muzzle/blade path through .装扮, but author it
        # into the timeline instead of running attachMovie at every pose.
        b.symbol(name,[b.layer('固定武器',[b.instance(skin,clip=True,instance_name='装扮')])],clip=True)
        GENERATED[name]=b.GENERATED[name]
    return name


def fixed_head():
    name=PREFIX+'固定装备/头部'
    if name not in GENERATED:
        face=import_symbol('sprite/男变装-基本脸型')
        # XFL elements are back-to-front; explicit layers keep the visor above
        # the unchanged face. Hair exists only in the authored helmet-off frame.
        art=b.layer('固定头部',[b.instance(face),b.instance(b.PREFIX+'部件/头盔')])
        b.frame(art,index=1,elements=[b.instance(face),b.instance(b.PREFIX+'部件/短发及胡须')])
        b.symbol(name,[b.layer('停帧',script='stop();'),art],clip=True)
        GENERATED[name]=b.GENERATED[name]
    return name


def bake_placements(root):
    """Resolve the donor's variable skin holders before traversing dependencies.

    Armor has no load callbacks. Only the fixed head state and functional
    muzzle/blade references have tiny callbacks; no dressup registry/attachment.
    """
    global BAKED_PLACEMENTS
    for el in list(root.findall('.//x:DOMSymbolInstance',b.NS)):
        script=el.find('x:Actionscript/x:script',b.NS)
        code='' if script is None else script.text or ''
        if '配置装扮' not in code and not ('attachMovie' in code and '手枪2_装扮' in code):continue
        refs=set(re.findall(r'"([^"\n]+_引用)"',code))
        if '脸型_引用' in refs:
            target=fixed_head()
            callback='_root.前治安官固定头部(this,_parent._parent._parent);'
        else:
            ref=next(iter(refs),None)
            if len(refs)>1:raise ValueError('Ambiguous fixed placement: '+str(refs))
            target=ARMOR.get(ref)
            callback=None
            if ref in WEAPONS:
                target=fixed_weapon(ref)
                callback='_root.前治安官固定武器(this.装扮,_parent._parent._parent,"'+ref+'");'
            if target is None:
                if ref not in [None,'刀2_引用','刀3_引用','手枪2_引用','手雷_引用']:
                    raise ValueError('Unmapped fixed equipment: '+str(ref))
                el.getparent().remove(el)
                BAKED_PLACEMENTS+=1
                continue
        el.set('libraryItemName',target)
        el.set('symbolType','movie clip' if callback else 'graphic')
        for attr in ['firstFrame','loop']:el.attrib.pop(attr,None)
        for action in list(el.findall('x:Actionscript',b.NS)):el.remove(action)
        if callback:
            b.node('script',parent=b.node('Actionscript',parent=el)).text=E.CDATA('onClipEvent(load) {'+callback+'}')
        BAKED_PLACEMENTS+=1


def copy_rush():
    original=b.PREFIX+'战技/战技容器-特勤盾冲'
    mapping={}
    def visit(name):
        if name in mapping:return mapping[name]
        # Art, light and collision interfaces have no dressup and stay shared.
        if name!=original and '/战技/挂点/' not in name and not name.endswith('/冲撞判定实体'):return name
        target=PREFIX+'固定盾冲/'+name.rsplit('/',1)[-1]
        mapping[name]=target
        root=E.parse(str(b.OWNER/'LIBRARY'/(name+'.xml')),b.PARSER).getroot()
        root.set('name',target)
        for attr in list(root.attrib):
            if attr.startswith('linkage'):del root.attrib[attr]
        bake_placements(root)
        for el in root.iter():
            ref=el.get('libraryItemName')
            if ref:el.set('libraryItemName',visit(ref))
        GENERATED[target]=root
        return target
    name=visit(original)
    GENERATED[name].set('linkageExportForAS','true')
    GENERATED[name].set('linkageIdentifier','前治安官动作-盾冲')
    return name


def read(name):
    return E.parse(str(DONOR / (name + '.xml')), b.PARSER).getroot()


def import_symbol(name):
    if name.startswith('Codex/'):
        return name
    if name in MAPPING:
        return MAPPING[name]
    renamed = PREFIX + '原生/' + name
    MAPPING[name] = renamed
    if not (DONOR/(name+'.xml')).exists():
        item = next((x for x in DONOR_DOC.findall('x:media/*', b.NS) if x.get('name') == name), None)
        if item is None: raise ValueError('Missing native dependency: '+name)
        item = copy.deepcopy(item)
        item.set('name', renamed)
        item.attrib.pop('itemID', None)
        MEDIA[renamed] = item
        return renamed
    root = copy.deepcopy(read(name))
    root.set('name', renamed)
    for key in list(root.attrib):
        if key.startswith('linkage') or key in ('itemID', 'lastModified'):
            del root.attrib[key]
    root.find('x:timeline/x:DOMTimeline', b.NS).set('name', name.rsplit('/', 1)[-1])
    # Imported player frame facades used a lexical _parent in asLoader.
    # NPC-local facades qualify this._parent and preserve all player callers.
    facade_map = {
        '_root.主角函数.初始化长枪射击函数':'_root.前治安官初始化长枪射击',
        '_root.主角函数.初始化手枪射击函数':'_root.前治安官初始化手枪射击',
        '_root.技能函数.翻滚换弹':'_root.前治安官翻滚换弹'
    }
    for script in root.findall('.//x:script', b.NS):
        text=script.text or ''
        if name == '容器/技能容器/技能容器-小跳' and '小跳移动距离计算("上下跳"' in text:
            text='onClipEvent(enterFrame){ _root.前治安官上下闪避(_parent,_parent._parent); }'
        for old,new in facade_map.items():text=text.replace(old,new)
        script.text=E.CDATA(text)
    bake_placements(root)
    GENERATED[renamed] = root
    for el in root.iter():
        ref = el.get('libraryItemName')
        if ref:
            el.set('libraryItemName', import_symbol(ref))
    return renamed


def copied_element(el):
    el = copy.deepcopy(el)
    for child in el.iter():
        ref = child.get('libraryItemName')
        if ref:
            child.set('libraryItemName', import_symbol(ref))
    return el


def selected_frame(layer, tick):
    return next((f for f in layer.findall('x:frames/x:DOMFrame', b.NS)
                 if int(f.get('index')) <= tick < int(f.get('index')) + int(f.get('duration', '1'))), None)


def visual_slice(source, start, count, name):
    root = copy.deepcopy(read(source))
    root.set('name', name)
    for key in list(root.attrib):
        if key.startswith('linkage') or key in ('itemID', 'lastModified'):
            del root.attrib[key]
    root.find('x:timeline/x:DOMTimeline', b.NS).set('name', name.rsplit('/', 1)[-1])
    for lay in root.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', b.NS):
        frames = lay.find('x:frames', b.NS)
        for f in list(frames):
            at = int(f.get('index')); end = at + int(f.get('duration', '1'))
            if end <= start or at >= start + count:
                frames.remove(f)
                continue
            f.set('index', str(max(at, start)-start))
            f.set('duration', str(min(end, start+count)-max(at, start)))
            f.attrib.pop('name', None); f.attrib.pop('labelType', None)
        # Transition playback belongs to the NPC controller. Do not import
        # the donor's death check, gravity, counterattack, or player key input.
        for script in list(lay.findall('.//x:Actionscript', b.NS)):
            script.getparent().remove(script)
    bake_placements(root)
    for el in root.iter():
        if el.get('libraryItemName'):
            el.set('libraryItemName', import_symbol(el.get('libraryItemName')))
    GENERATED[name] = root
    return name


def assemble():
    original = read('主角-男')
    source_layers = original.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer', b.NS)
    states = [('容器', 1), ('空手站立', 2), ('长枪站立', 142), ('长枪行走', 151),
              ('长枪跑', 161), ('手枪站立', 191), ('手枪行走', 200), ('手枪跑', 210),
              ('兵器站立', 407), ('兵器行走', 416), ('兵器跑', 426),
              ('被击', 71), ('击倒', 79), ('倒地', 88), ('血腥死', 480)]
    # CS6 compacts a label layer that starts at index 1. Keep the explicit blank
    # first frame so every label retains the same index as its visual layers.
    labels = b.layer('状态标签')
    scripts = b.layer('初始化', script='_root.前治安官初始化(this); stop();')
    layers = [labels, scripts]
    keep = {'人物文字信息', 'area', '持枪下身上层', '动画层', '持枪下身下层',
            '底层背景', '啥时候把阴影放到外面图层来啊'}
    for src in source_layers:
        if src.get('name') not in keep:
            continue
        lay = b.node('DOMLayer', dict(src.attrib)); b.node('frames', parent=lay)
        initial = selected_frame(src, 2)
        b.frame(lay, index=0, elements=[] if initial is None else
                [copied_element(e) for e in initial.findall('x:elements/*', b.NS)])
        # The common enemy initializer replaces this authored placeholder with
        # the shared nameplate. Never recreate the placeholder on state changes.
        if src.get('name') == '人物文字信息':
            lay.find('x:frames/x:DOMFrame', b.NS).set('duration',str(len(states)+4))
            layers.append(lay)
            continue
        for index, (_, tick) in enumerate(states, 1):
            f = selected_frame(src, tick)
            elements = [] if f is None else [copied_element(e) for e in f.findall('x:elements/*', b.NS)]
            # The independent hit/transition controller owns knockdown; remove
            # the player's random NPC recovery hook from the mount itself.
            if tick == 79:
                for el in elements:
                    for action in list(el.findall('x:Actionscript', b.NS)):
                        el.remove(action)
            b.frame(lay, index=index, elements=elements)
        layers.append(lay)
    for index, (label, _) in enumerate(states, 1):
        f = b.frame(labels, index=index); f.set('name', label); f.set('labelType', 'name')
    # Both slices have finite authored ranges. Symbol 144's frame 26+ is an
    # unrelated counterattack and must never be played as a get-up animation.
    for label, source, start, count, native_tick in [
            ('转阶段击倒', 'sprite/被击飞击倒', 0, 9, 79),
            ('转阶段落地', 'sprite/Symbol 144', 0, 9, 88),
            ('转阶段起身', 'sprite/Symbol 144', 9, 16, 88)]:
        index = len(states)+1
        ref = visual_slice(source, start, count, PREFIX+label)
        for lay in layers[2:]:
            if lay.get('name') == '人物文字信息':continue
            src = next(s for s in source_layers if s.get('name') == lay.get('name'))
            f = selected_frame(src, native_tick)
            els = [] if f is None else [copied_element(e) for e in f.findall('x:elements/*', b.NS)]
            for el in els:
                if el.get('name') == 'man':
                    el.set('libraryItemName', ref)
                    for action in list(el.findall('x:Actionscript', b.NS)): el.remove(action)
            b.frame(lay, index=index, elements=els)
        f = b.frame(labels, index=index); f.set('name',label); f.set('labelType','name')
        states.append((label, native_tick))
    name = PREFIX+'敌人-前治安官'
    b.symbol(name, layers, export='敌人-前治安官', clip=True)
    GENERATED[name] = b.GENERATED[name]
    # Helmet only: no face/neck/body is duplicated into the flying prop.
    helmet = PREFIX+'飞盔'
    b.symbol(helmet, [b.layer('盔壳', [b.instance('Codex/重装特勤/部件/头盔',
             (.24,0,0,.24,0,0))])], export='特勤飞盔', clip=True)
    GENERATED[helmet] = b.GENERATED[helmet]
    # A loaded SWF owns its attachMovie linkage scope. Give the NPC its own
    # exports rather than relying on player containers from a sibling SWF.
    actions = {x:'容器/技能容器/技能容器-'+x for x in ['小跳','翻滚换弹','兴奋剂','铁布衫']}
    actions['棍棒'] = '容器/兵器攻击容器/平A/兵器攻击容器-棍棒1连招'
    for action, source in actions.items():
        name = import_symbol(source)
        root = GENERATED[name]
        root.set('linkageExportForAS','true')
        root.set('linkageIdentifier','前治安官动作-'+action)
        first = root.find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer/x:frames/x:DOMFrame', b.NS)
        script = first.find('x:Actionscript/x:script', b.NS)
        if script is None:
            holder=b.node('Actionscript',parent=first);script=b.node('script',parent=holder)
        script.text=E.CDATA((script.text or '')+'\n_root.前治安官绑定动作(this);')
    copy_rush()
    return states


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--check', action='store_true')
    args = parser.parse_args(); states = assemble()
    stale = []
    for name, root in GENERATED.items():
        # Donor scripts contain tab-only blank lines and mixed indentation.
        # Normalize lexical whitespace without touching strings or art data.
        for script in root.findall('.//x:script', b.NS):
            code = script.text or ''
            normalized = '\n'.join(re.sub(r'^[ \t]+',
                lambda m: m.group(0).expandtabs(4), line).rstrip(' \t')
                for line in code.split('\n'))
            assert [line.strip() for line in code.split('\n')] == [line.strip() for line in normalized.split('\n')]
            script.text = E.CDATA(normalized)
        path = b.OWNER/'LIBRARY'/(name+'.xml')
        raw = E.tostring(root, encoding='utf-8', pretty_print=True)
        if not path.exists() or path.read_bytes() != raw:
            stale.append(name)
            if not args.check: b.write_xml(path, root)
    if args.check and stale: raise SystemExit('Stale sheriff symbols: '+str(stale[:8]))
    if not args.check:
        # Retire only this generator's obsolete closure, never donor/player art.
        owned=(b.OWNER/'LIBRARY'/PREFIX).resolve()
        for path in owned.rglob('*.xml'):
            if not path.resolve().is_relative_to(owned):raise ValueError('Outside owned namespace')
            name=path.relative_to(b.OWNER/'LIBRARY').with_suffix('').as_posix()
            if name not in GENERATED:path.unlink()
        doc=E.parse(str(b.OWNER/'DOMDocument.xml'),b.PARSER)
        for inc in doc.findall('x:symbols/x:Include',b.NS):
            href=inc.get('href','')
            if href.startswith(PREFIX) and href.removesuffix('.xml') not in GENERATED:
                inc.getparent().remove(inc)
        b.write_xml(b.OWNER/'DOMDocument.xml',doc.getroot())
        b.append_to_document(b.OWNER, GENERATED)
        doc = E.parse(str(b.OWNER/'DOMDocument.xml'), b.PARSER)
        media = doc.getroot().find('x:media', b.NS)
        if media is None: media = b.node('media', parent=doc.getroot())
        for name, item in MEDIA.items():
            old = next((x for x in media if x.get('name') == name), None)
            if old is not None: media.remove(old)
            media.append(item)
            for attr, folder in [('bitmapDataHRef','bin'), ('soundDataHRef','bin'), ('href','LIBRARY')]:
                ref = item.get(attr)
                if not ref: continue
                src = DONOR.parent/folder/ref
                if not src.exists(): continue  # bitmap DAT is the XFL authority
                dst = b.OWNER/folder/ref
                if dst.exists() and dst.read_bytes() != src.read_bytes():
                    raise ValueError('Media collision: '+str(dst))
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src,dst)
        b.write_xml(b.OWNER/'DOMDocument.xml', doc.getroot())
    report = {'unit':'敌人-前治安官', 'owner':str(b.OWNER.relative_to(b.ROOT)),
              'symbols':len(GENERATED), 'media':len(MEDIA), 'states':[x[0] for x in states],
              'donor':'flashswf/arts/things0', 'genericAI':False,
              'runtimeDressup':False,'bakedPlacements':BAKED_PLACEMENTS,
              'transitionFrames':{'knockdown':9,'landing':9,'getup':16},
              'sourceSha256':hashlib.sha256((DONOR/'主角-男.xml').read_bytes()).hexdigest()}
    if not args.check:
        out=b.ROOT/'tmp/former-sheriff-phase-one';out.mkdir(parents=True,exist_ok=True)
        (out/'asset-manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf8')
    print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__': main()
