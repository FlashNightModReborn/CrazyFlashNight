"""Invoked in the native builder namespace; no shared writes."""

# A short chain belongs to this profile. Native cold poses never render or read
# the real knife slot. Their existing strike/learning/resource scripts survive.
# Preserve the original blade wrapper (1.8, 97.45), grip at outer (0,0),
# and all three native blade emission points. The previous negative-Y chain
# pointed behind the hand while the native pose and hit area faced forward.
grip=(-1.8,-97.45);tip=(12.,261.95)
dx=tip[0]-grip[0];dy=tip[1]-grip[1];span=math.hypot(dx,dy)
ux=dx/span;uy=dy/span
chain_elements=[]
for distance in range(12,int(span)-20,20):
    chain_elements.append(instance(by_id[assets['source/boss-parts/Symbol 496.svg']],
                                   (uy,-ux,ux,uy,grip[0]+ux*distance,grip[1]+uy*distance)))
chain_elements.append(instance(by_id[assets['source/boss-parts/Symbol 499.svg']],(1,0,0,1,*tip)))
for i,(x,y) in enumerate(((-8,33.95),(-9,135.95),tip),1):
    chain_elements.append(instance(contact,(2.8,0,0,2.8,x,y),'刀口位置'+str(i)))
short_chain=static(PREFIX+'冷兵器挂点/短链锤',chain_elements)
chain_holder=static(PREFIX+'冷兵器挂点/刀体',[instance(short_chain,instance_name='装扮')])
chain_outer=static(PREFIX+'冷兵器挂点/主手',[instance(chain_holder,(1,0,0,1,1.8,97.45),instance_name='刀')])
empty=static(PREFIX+'冷兵器挂点/空鞘',[])

original_lib=REFERENCE/'flashswf/arts/things0/LIBRARY'
cloned={};cold_assets=[]
def adapt_code(code):
    unit=r'(_parent(?:\._parent)*|自机|单位)'
    for prop,method in [('刀属性.power','锋利度'),('空手攻击力','空手补项'),('内力','内力'),('mp攻击加成','气伤'),('兵器动作类型','动作类型')]:
        code=re.sub(unit+r'\.'+re.escape(prop)+r'\b',lambda m:'_root.火凤套装接口.'+method+'('+m[1]+')',code)
    # Three legacy invisible contacts in Iai still use the scalar shooter.
    # Project only these cloned calls through the same cold-action snapshot;
    # do not intercept unrelated projectiles in the global shooting function.
    def legacy_contact(match):
        values=match[1].split(',')
        names=['声音','霰弹值','子弹散射度','发射效果','子弹种类','子弹威力','子弹速度','Z轴攻击范围',
               '击中地图效果','发射者','shootX','shootY','shootZ',None,'击倒率','击中后子弹的效果',
               '水平击退速度','垂直击退速度','命中率','固伤','百分比伤害','血量上限击溃','防御粉碎',
               '区域定位area','吸血','毒','最小霰弹值','不硬直','伤害类型','魔法伤害属性',
               '速度X','速度Y','ZY比例','斩杀','暴击','水平击退反向','角度偏移']
        assert 16<=len(values)<=len(names),match[0]
        fields=','.join(name+':'+value for name,value in zip(names,values) if name)
        return ('var hfContact = {'+fields+'};\n'
                '_root.火凤套装接口.冻结子弹(_root.gameworld['+values[9]+'],hfContact);\n'
                '_root.子弹区域shoot传递(hfContact);')
    code=re.sub(r'_root\.子弹区域shoot\(([^;\n]+)\);',legacy_contact,code)
    return code.replace('_root.子弹属性初始化(', '_root.火凤套装接口.子弹初始化(')

def clone_cold(name):
    if name in ('主角肢体素材/刀-主手','主角肢体素材/刀'):return chain_outer
    if name=='主角肢体素材/刀-刀鞘':return empty
    if name in cloned:return cloned[name]
    src=original_lib/(name+'.xml');used_file(src)
    root0=E.parse(src).getroot();newname=PREFIX+'冷兵器复用/'+name;cloned[name]=newname
    root0.set('name',newname)
    root0.set('itemID','78f10000-'+hashlib.sha256(newname.encode()).hexdigest()[:8])
    for key in list(root0.attrib):
        if key.startswith('linkage'):del root0.attrib[key]
    root0.find('x:timeline/x:DOMTimeline',N).set('name',newname.rsplit('/',1)[-1])
    for item in root0.iter():
        assert tag(item) not in ('DOMBitmapInstance','DOMVideoInstance'),(name,tag(item))
        if tag(item)=='DOMSymbolInstance':item.set('libraryItemName',clone_cold(item.get('libraryItemName')))
        if tag(item)=='script':item.text=adapt_code(item.text or '')
    symbols[newname]=root0
    return newname

for kind,items in [('技能',['迅斩','瞬步斩','凶斩','火舞旋风','拔刀术']),('兵器攻击',['剑气释放','贯穿突刺','月光斩','蓄力重劈'])]:
    for name in items:
        original='容器/'+kind+'容器/'+kind+'容器-'+name
        new=clone_cold(original);s=symbols[new]
        s.set('linkageIdentifier','火凤套装_冷兵器_'+name);s.set('linkageExportForAS','true');s.set('linkageExportInFirstFrame','true')
        cold_assets.append({'action':name,'source':original,'native':new})

# Jump uses the original cold-weapon branch and its existing learned passives.
# Clip-level load/enterFrame code is moved onto the cloned man at the same depth.
jump=clone_cold('sprite/兵器跳跃');js=symbols[jump]
js.set('linkageIdentifier','火凤套装_冷兵器_跳跃');js.set('linkageExportForAS','true');js.set('linkageExportInFirstFrame','true')
host=next(x for x in player.findall('.//x:DOMSymbolInstance',N) if x.get('name')=='man' and x.get('libraryItemName')=='sprite/兵器跳跃')
host_code='\n'.join(x.text or '' for x in host.findall('x:Actionscript/x:script',N))
def event_body(code,event):
    m=re.search(r'onClipEvent\s*\(\s*'+event+r'\s*\)\s*\{',code)
    if not m:return ''
    # This trusted source has balanced commented braces; reject a malformed body.
    depth=1;i=m.end();start=i
    while depth and i<len(code):
        if code[i]=='{':depth+=1
        elif code[i]=='}':depth-=1
        i+=1
    assert depth==0,event
    return code[start:i-1]
start_code=event_body(host_code,'load').replace('"兵器跳"','"空手跳"')
tick_code=event_body(host_code,'enterFrame')
bootstrap=adapt_code('onEnterFrame = function() {\n'+tick_code+'\n};\n'+start_code)
layers=js.find('x:timeline/x:DOMTimeline/x:layers',N)
layers.insert(0,layer('原生跳跃入口',[(0,[],bootstrap)]))

# Pure vector effects: ring, hit flash and healing cue carry no combat scripts.
def ring(name,frames,linkage,kind):
    fs=[]
    for i in range(frames):
        t=i/(frames-1);els=[]
        if kind=='ember':
            for j in range(9):
                a=j*math.tau/9+t*.6;r0=24+4*math.sin(t*math.tau+j)
                x=math.cos(a)*r0;y=math.sin(a)*r0*.18-3-(i+j*3)%24*.25
                # Native shapes, generated directly from compact SVG primitives.
                e=E.fromstring('<circle cx="'+num(x)+'" cy="'+num(y)+'" r="1.5" fill="#FFB05A"/>')
                writer=V.Writer.__new__(V.Writer);writer.grads={};writer.segment_count=0;writer.shape_count=0
                els.append(writer.shape(e,dict(e.attrib),I))
        else:
            for j in range(7):
                a=j*math.tau/7;rad=3+t*(16 if kind=='hit2' else 10)
                x=math.cos(a)*rad;y=math.sin(a)*rad-(25 if kind=='heal' else 0)
                e=E.fromstring('<circle cx="'+num(x)+'" cy="'+num(y)+'" r="'+num(max(.2,2.5*(1-t)))+'" fill="'+('#FFD778' if kind!='hit' else '#F57636')+'"/>')
                writer=V.Writer.__new__(V.Writer);writer.grads={};writer.segment_count=0;writer.shape_count=0
                els.append(writer.shape(e,dict(e.attrib),I))
        fs.append((i,els,'stop();' if kind=='ember' and i==0 else ('this.removeMovieClip();' if kind!='ember' and i==frames-1 else None)))
    return symbol(PREFIX+'表现/'+name,[layer('纯表现',fs)],linkage)
ring('脚底余烬',24,'火凤套装_余烬','ember')
ring('热附击',10,'火凤套装_热附击','hit')
ring('完整热附击',12,'火凤套装_完整热附击','hit2')
ring('回血提示',16,'火凤套装_回血提示','heal')

# Pure Boss flame presentation. No exported projectile or collision code is
# reused; cloning records each current editable source in the build closure.
boss_fx_library=REPO/'flashswf/arts/new/雾人整合特效/LIBRARY'
boss_fx_clones={}
def clone_boss_fire(name):
    if name in boss_fx_clones:return boss_fx_clones[name]
    source=boss_fx_library/(name+'.xml');used_file(source)
    root0=E.parse(source).getroot()
    dest=PREFIX+'表现/原版火焰/'+name.rsplit('/',1)[-1]+'-'+hashlib.sha256(name.encode()).hexdigest()[:8]
    boss_fx_clones[name]=dest
    root0.set('name',dest);root0.set('itemID','78f20000-'+hashlib.sha256(dest.encode()).hexdigest()[:8])
    for key in list(root0.attrib):
        if key.startswith('linkage'):del root0.attrib[key]
    root0.find('x:timeline/x:DOMTimeline',N).set('name',dest.rsplit('/',1)[-1])
    for parent in root0.iter():
        for child in list(parent):
            if tag(child)=='Actionscript':parent.remove(child)
            elif tag(child)=='DOMLayer' and any(x in child.get('name','') for x in ('判定','代码')):parent.remove(child)
            elif tag(child)=='DOMSymbolInstance' and (child.get('name')=='area' or child.get('libraryItemName','').startswith('area')):parent.remove(child)
    for inst in root0.iter():
        if tag(inst)=='DOMSymbolInstance':
            inst.set('libraryItemName',clone_boss_fire(inst.get('libraryItemName')))
            inst.attrib.pop('name',None)
        assert tag(inst) not in ('DOMBitmapInstance','DOMVideoInstance'),name
    symbols[dest]=root0
    return dest
for source,export in [('1.特效文件夹/03.赤橙色系/火焰与爆炸/火攻/火凤火攻','火凤套装_原版火攻'),
                      ('1.特效文件夹/03.赤橙色系/火焰与爆炸/火回旋/火凤回旋','火凤套装_原版回旋')]:
    dest=clone_boss_fire(source);root0=symbols[dest]
    layers0=root0.find('x:timeline/x:DOMTimeline/x:layers',N)
    visible_end=max(int(f.get('index','0'))+int(f.get('duration','1'))
                    for f in layers0.findall('x:DOMLayer/x:frames/x:DOMFrame',N)
                    if len(f.find('x:elements',N))>0)
    for frames0 in layers0.findall('x:DOMLayer/x:frames',N):
        for frame0 in list(frames0):
            start=int(frame0.get('index','0'))
            if start>=visible_end:frames0.remove(frame0)
            elif start+int(frame0.get('duration','1'))>visible_end:frame0.set('duration',str(visible_end-start))
    root0.set('linkageIdentifier',export);root0.set('linkageExportForAS','true');root0.set('linkageExportInFirstFrame','true')
    root0.find('x:timeline/x:DOMTimeline/x:layers',N).insert(0,layer('表现时钟',[(0,[],'stop();')]))

# Match the established armour-icon composition: a 24x24 masked detail with
# the same radial bottom shade, plus an independently addressable full view.
# The source parts remain at their native joint origins; this only changes UI.
template_lib=REPO/'flashswf/arts/things/LIBRARY'
shade_path=template_lib/'无AS链接/Symbol 16.xml';used_file(shade_path)
shade_name=PREFIX+'图标/共同遮罩底影'
static(shade_name,copy.deepcopy(list(E.parse(shade_path).find('.//x:elements',N))))
for item,part,donor in [
    ('火凤头部装备',None,'钛合金61式头部装甲'),
    ('火凤胸甲','torso','钛合金61式胸甲'),
    ('火凤下装','hip','钛合金61式腿甲'),
    ('火凤手甲','hand-near','钛合金61式手甲'),
    ('火凤战靴','foot-near','钛合金61式装甲鞋')]:
    src=template_lib/('待整理防具相关汇总/图标-'+donor+'.xml');used_file(src)
    donor_root=E.parse(src).getroot()
    donor_layers=donor_root.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer',N)
    art=copy.deepcopy(donor_layers[1].find('x:frames/x:DOMFrame/x:elements/x:DOMSymbolInstance',N))
    ref=fields[part] if part else PREFIX+'R9长发/Front'
    art.set('libraryItemName',ref)
    art.attrib.pop('name',None)
    if part:
        node0=next(x for x in SNAP['nodes'] if x['id']==part)
        x,y,w,h=asset_boxes[assets[node0['asset']]]
        full=instance(ref,(.24,0,0,.24,-(x+w/2)*.24,-(y+h/2)*.24))
    else:
        full=instance(ref,(.277,0,0,.277,0,0))
    mask=layer('24px 遮罩',[(0,[instance(shade_name)],'stop();'),(1,[],None)])
    mask.set('layerType','mask');mask.set('locked','true')
    content=layer('部位特写',[(0,[art],None),(1,[],None)])
    content.set('parentLayerIndex','0');content.set('locked','true')
    shade=layer('原版底影',[(0,[instance(shade_name)],None),(1,[],None)])
    display=layer('完整展示',[(0,[],None),(1,[full],'stop();')])
    symbol(PREFIX+'图标/'+item,[mask,content,shade,display],'图标-'+item)

(OUT/'cold-adaptation.json').write_text(json.dumps({'actions':cold_assets,'jumpSource':'sprite/兵器跳跃','clonedSymbols':len(cloned),'crouchBranch':'No standalone crouch attack state exists in 主角-男; directional ground derives use the allowed cold consumers.'},ensure_ascii=False,indent=2),'utf8')
