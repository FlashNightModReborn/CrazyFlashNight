"""Copy a silent, script-free vector explosion into each robot's private library."""
from pathlib import Path
import copy
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
DONOR = ROOT/'flashswf/arts/new/3XD的素材/LIBRARY'
EXPLOSION = '5武器特效和子弹/爆炸狙击子弹/小火焰爆炸'
NS = {'x':'http://ns.adobe.com/xfl/2008/'}


def source_trees():
    trees, pending = {}, [EXPLOSION]
    while pending:
        name = pending.pop()
        if name in trees:
            continue
        tree = E.parse(str(DONOR/(name+'.xml')),E.XMLParser(strip_cdata=False)).getroot()
        # The original bullet has two collision frames and an embedded sound.
        # Only its visual layer is copied; it never creates another damage source.
        for layer in tree.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer',NS):
            if name == EXPLOSION and layer.get('name') != '小爆炸':
                layer.getparent().remove(layer)
        for item in tree.findall('.//x:Actionscript',NS)+tree.findall('.//x:SoundEnvelope',NS):
            item.getparent().remove(item)
        for frame in tree.findall('.//x:DOMFrame',NS):
            for key in list(frame.attrib):
                if key.startswith('sound'):
                    del frame.attrib[key]
        if tree.findall('.//x:DOMBitmapInstance',NS) or tree.findall('.//x:BitmapFill',NS):
            raise ValueError('The explosion must remain native vector art')
        trees[name] = tree
        pending.extend(i.get('libraryItemName') for i in tree.findall('.//x:DOMSymbolInstance',NS))
    return trees


def input_paths():
    return [Path(__file__),Path(__file__).with_name('RobotDeath.as'),
        *[DONOR/(name+'.xml') for name in sorted(source_trees())]]


def add(native, symbols, prefix, body_name, body_matrix, burst_frame, total, hit_helper):
    trees = source_trees()
    rename = {name:prefix+'机械爆裂/'+('演出' if name == EXPLOSION else name.replace('/','_')) for name in trees}
    for old,tree in trees.items():
        item = copy.deepcopy(tree)
        item.set('name',rename[old]);item.set('itemID',native.item_id(rename[old]))
        item.set('symbolType','graphic')
        for key in list(item.attrib):
            if key.startswith('linkage') or key in ('lastModified','lastUniqueIdentifier'):
                del item.attrib[key]
        item.find('x:timeline/x:DOMTimeline',NS).set('name',rename[old].rsplit('/',1)[-1])
        for inst in item.findall('.//x:DOMSymbolInstance',NS):
            inst.set('libraryItemName',rename[inst.get('libraryItemName')])
            inst.set('symbolType','graphic');inst.set('loop','play once')
        symbols[rename[old]] = item
    a,b,c,d,tx,ty = body_matrix
    if b or c or not a or not d:
        raise ValueError('Review rotated death-body registration before adding explosion')
    start = burst_frame-1
    layers = symbols[body_name].find('x:timeline/x:DOMTimeline/x:layers',NS)
    visual_start=max(0,start-2)
    layers.insert(0,native.make_sparse_layer('无音轨机械爆裂',total,{visual_start:{'duration':min(13,total-visual_start),
        'elements':[native.instance(rename[EXPLOSION],matrix=(1.7/a,0,0,1.7/d,-tx/a,(-70-ty)/d))]}}))
    layers.insert(0,native.make_sparse_layer('一次性亡语判定',total,{start:{'elements':[
        native.instance(hit_helper,matrix=(220/(25*a),0,0,160/(25*d),-tx/a,(-70-ty)/d),
            symbol_type='movie clip',name='cf6DeathPoint',alpha_mult=0,
            script='onClipEvent(load){cf6RobotDeathIdentity=_parent.cf6RobotDeathIdentity;}')]}}))
    return {'burstFrame':burst_frame,'powerMultiplier':2,'damageType':'物理','laneRange':80,
        'localArea':[220,160],'visual':'script-free native clone of '+EXPLOSION,
        'audioRoute':'_root.播放音效','sound':'CF6_1009.mp3','damageOnce':True}
