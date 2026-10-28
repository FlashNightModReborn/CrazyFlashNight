"""Split the archived waist drawing into empty leatherwork and live equipment.

The approved SVG is immutable. Its baked pistol (including the pistol-shaped
silhouette and retaining strap) is removed only in this generated projection.
Holstered skins have separate dressup references so they cannot steal a muzzle.
"""
import copy
import xml.etree.ElementTree as SE

SVG = '{http://www.w3.org/2000/svg}'
PISTOL_PATHS = set(range(6, 20))
FRONT_PATHS = set(range(20, 61))
GRENADE_PATHS = set(range(45, 59))


def empty_drawing(document, front=False, grenades=False):
    result = copy.deepcopy(document)
    drawing = result.find(SVG+'g/'+SVG+'g/'+SVG+'g')
    assert drawing is not None and len(drawing) in (61, 62), 'Archived waist layout changed'
    assert drawing[6].get('d').startswith('M84 218L101 209')
    assert drawing[12].get('d').startswith('M91 271L102 269')
    for index, element in enumerate(list(drawing)):
        keep = index in GRENADE_PATHS if grenades else (index != 0 and index not in PISTOL_PATHS
            and index not in GRENADE_PATHS and ((index in FRONT_PATHS) == front))
        if not keep:
            drawing.remove(element)
    return result


SCRIPT = '''stop();
syncHolster=function(holder:MovieClip,slot:String,drawn:Boolean):Void {
    var unit:MovieClip=this._parent._parent;
    var skin:String=unit.soldierIsElite===true?unit[slot+"_装扮"]:"";
    if(typeof skin!="string")skin="";
    if(holder.holsteredSkin!==skin){
        holder._visible=false;
        holder.holsteredSkin=skin;
        // Separate reference; refreshAll still resolves the real slot skin key.
        _root.装备引用配置.配置装扮(holder,skin,"装扮",slot+"_装扮_引用");
    }
    holder._visible=skin!="" && holder.装扮!=null && !drawn;
};
syncHolsters=function():Void {
    var body:MovieClip=this._parent,unit:MovieClip=body._parent;
    var owner:Object=unit.soldierAttackOwner;
    this.投掷物._visible=unit.soldierIsElite===true?unit.特种兵烟雾弹!==false:unit.特种兵投掷物!==false && unit.特种兵投掷物!=="";
    var active:Boolean=owner.elite===true && owner.active===true && body===unit.man
        && unit.状态=="长枪攻击";
    var primary:Boolean=false,secondary:Boolean=false;
    if(active){
        if(owner.reload){primary=!owner.smokePrepared && (owner.reloadPair===true || owner.reloadSlot=="手枪");secondary=!owner.smokePrepared && (owner.reloadPair===true || owner.reloadSlot=="手枪2");}
        else if(owner.kind=="retreat"){
            primary=true;secondary=unit.eliteSidearmAllowed===true;
        }
    }
    this.syncHolster(this.主手,"手枪",primary);
    this.syncHolster(this.副手,"手枪2",secondary);
};
onEnterFrame=syncHolsters;syncHolsters();'''


def build(source, name, native, vector):
    symbols, stats = {}, {'shapes': 0, 'segments': 0, 'masks': 0}
    for suffix, front in (('空枪套前景', True), ('腰部衣料', False), ('腰部投掷物', True)):
        # A library symbol and a folder cannot both be named "分件/489" in CS6.
        part = vector.NativePart(source, name+'-'+suffix, (0, 0))
        part.svg = empty_drawing(part.svg, front, suffix == '腰部投掷物')
        converted, report = part.build()
        symbols.update(converted)
        for key in stats:
            stats[key] += report[key]

    mount = 'Codex/特种兵/武器/长枪挂点'
    def mask(x, y, width, height):
        rect = SE.Element('rect', x=str(x), y=str(y), width=str(width), height=str(height))
        return part.paint_shape(rect, {'fill': '#ffffff', 'stroke': 'none'}, vector.base.I)

    # Grip-sized openings above the leatherwork. The hidden barrel remains in
    # its holster; long configured short guns cannot stick out through the leg.
    symbols[name] = native.symbol(name, [
        native.layer('装备显隐', [native.frame(script=SCRIPT)]),
        native.layer('按兵种携带投掷物', [native.frame(elements=[native.instance(name+'-腰部投掷物',
            symbol_type='movie clip', name='投掷物')])]),
        native.layer('保留空枪套与腰带', [native.frame(elements=[native.instance(name+'-空枪套前景')])]),
        native.layer('近侧枪套范围', [native.frame(elements=[mask(-120, -110, 100, 112)])], layerType='mask', locked='true'),
        native.layer('主手腰挂', [native.frame(elements=[native.instance(mount,
            matrix=(-0.142, 0.807, -0.807, -0.142, -55, -42), symbol_type='movie clip', name='主手')])], parentLayerIndex='3', locked='true'),
        native.layer('腰部衣料', [native.frame(elements=[native.instance(name+'-腰部衣料')])]),
        native.layer('远侧枪套范围', [native.frame(elements=[mask(-5, -105, 110, 80)])], layerType='mask', locked='true'),
        native.layer('副手腰挂', [native.frame(elements=[native.instance(mount,
            matrix=(0.212, 0.792, -0.792, 0.212, 45, -42), symbol_type='movie clip', name='副手')])], parentLayerIndex='6', locked='true'),
    ], symbol_type='movie clip')
    stats['shapes'] += 2
    stats['masks'] += 2
    return symbols, stats
