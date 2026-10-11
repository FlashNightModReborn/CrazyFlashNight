"""Source/compiled contracts for the action-only phase-two deliverable."""
import argparse,hashlib,json,math,struct
from pathlib import Path
from lxml import etree as E
import phase_two as p
from verify import exports
from verify_phase_one import child_tags
b=p.b


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source-only',action='store_true');args=parser.parse_args()
    actions=p.sequence();metadata=json.loads((b.ROOT/'tmp/former-sheriff-phase-two/manifest.json').read_text('utf8'))
    doc=E.parse(str(b.OWNER/'DOMDocument.xml'))
    includes={e.get('href') for e in doc.findall('x:symbols/x:Include',b.NS)}
    media={e.get('name') for e in doc.findall('x:media/*',b.NS)}
    source_map=E.parse(str(b.ROOT/'data/items/asset_source_map.xml'))
    counts={};max_seam=0;max_hand_step=0;all_labels={};max_knee_seam=0;max_wrist_gap=0;max_grip_gap=0
    for action in metadata['actions']:
        name=action['name'];poses=actions[name];counts[name]=len(poses)
        assert poses[0]['parts']==poses[-1]['parts']==p.GUARD['parts'],name
        assert poses[0]['weapon']==poses[-1]['weapon']==p.GUARD['weapon'],name
        assert not poses[0]['active'] and not poses[-1]['active'],name
        assert len(source_map.xpath('asset[@id="'+action['linkage']+'"]'))==1
        path=b.OWNER/'LIBRARY'/(action['symbol']+'.xml')
        assert action['symbol']+'.xml' in includes,name
        root=E.parse(str(path))
        layers=root.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer',b.NS)
        shield_index=next(i for i,l in enumerate(layers) if l.get('name').startswith('左手盾牌'))
        body_layers=[i for i,l in enumerate(layers) if ' / ' in l.get('name') and l.get('name').split(' / ')[-1].isdigit()]
        assert body_layers and max(body_layers)<shield_index<len(layers)-1,name
        assert not any(l.get('name') in ['holster_front','stowed','cradle'] for l in layers),name
        refs={x.get('libraryItemName') for x in root.findall('.//x:DOMSymbolInstance',b.NS)}
        assert not refs.intersection({p.PREFIX+x for x in p.REMOVED_BODY_GEAR})
        assert p.PREFIX+'换弹承托' not in refs,'support must be a child of the shield'
        assert 'getQualifiedClassName' not in E.tostring(root,encoding='unicode')
        labels={}
        for f in layers[0].findall('x:frames/x:DOMFrame',b.NS):
            if f.get('name'):labels[int(f.get('index'))+1]=f.get('name')
        assert labels=={int(k):v for k,v in action['events'].items()},name
        all_labels[name]=labels
        for i,pose in enumerate(poses):
            for m in pose['parts']+[pose['weapon']]:
                assert all(math.isfinite(v) for v in m),name
                assert m[0]*m[3]-m[1]*m[2]>.001,(name,i,'collapsed or flipped part')
            if name!='持盾冲刺':
                for ui,fi,hi in p.ARMS:
                    elbow_a=p.s.point(pose['parts'][ui],(0,47))
                    elbow_b=p.s.point(pose['parts'][fi],(0,-47))
                    seam=math.dist(elbow_a,elbow_b);max_seam=max(max_seam,seam)
                    assert seam<.00001,(name,i,seam)
                for ti,si in [(1,3),(17,19)]:
                    seam=math.dist(p.s.point(pose['parts'][ti],(0,65)),p.s.point(pose['parts'][si],(0,-68)))
                    max_knee_seam=max(max_knee_seam,seam)
                    assert seam<.00001,(name,i,'knee gap',seam)
            if i:max_hand_step=max(max_hand_step,math.dist(pose['parts'][16][4:],poses[i-1]['parts'][16][4:]))
            if pose['active']=='knife':
                wrist_gap=math.dist(p.s.point(pose['parts'][15],(0,47)),p.s.point(pose['parts'][16],p.KNIFE_WRIST))
                grip_gap=math.dist(p.s.point(pose['parts'][16],p.KNIFE_GRIP),pose['prop'][4:])
                max_wrist_gap=max(max_wrist_gap,wrist_gap);max_grip_gap=max(max_grip_gap,grip_gap)
                assert wrist_gap<.00001 and grip_gap<.00001,(name,i,'knife hand registration')
                assert all(abs(a-z)<.00001 for a,z in zip(pose['parts'][16][:4],pose['prop'][:4])),(name,i,'blade rotates apart from fist')
        # The new committed 4-frame lunges intentionally travel farther than
        # R49's slow poke. This is a continuity ceiling, not a style score.
        assert max_hand_step<22,(name,max_hand_step)
    pistol=actions['持盾射击'];pm=next(a for a in metadata['actions'] if a['name']=='持盾射击')
    assert [f for f,x in enumerate(pistol) if x['flash']]==list(p.PISTOL_SHOTS)
    assert len(p.PISTOL_SHOTS)==pm['segments']['defaultMagazine']==8
    assert all(pistol[f]['retained'] and pistol[f]['prop']==p.matrix(.235,0,p.PISTOL_REST) for f in range(93,113))
    assert all(pistol[f]['magazine'] is not None and pistol[f]['retained'] for f in range(101,109))
    assert pm['segments']['shots'][-1]<pm['segments']['reloadEntry']<pm['segments']['reloadCommit']<pm['segments']['stow'][0]
    assert all(pistol[f]['supportStep']==p.SUPPORT_STEPS-1 for f in range(92,114))
    assert pistol[0]['supportStep']==pistol[-1]['supportStep']==0
    # Each transfer keeps the weapon registration point continuous, including
    # the support-to-hand transfer after the fresh magazine is inserted.
    for frames,kind,draw,stow in [(actions['持盾刺击'],'knife',8,67),(pistol,'pistol',8,130)]:
        for f in [draw,stow]:assert math.dist(frames[f]['parts'][16][4:],frames[f]['sockets'][kind])<.00001
    assert math.dist(pistol[92]['prop'][4:],pistol[93]['prop'][4:])<.00001
    assert math.dist(pistol[112]['prop'][4:],pistol[113]['prop'][4:])<.00001
    assert pm['frames']==138 and pm['segments']['reloadEntry']==86 and pm['segments']['reloadCommit']==110
    for ref in p.REMOVED_BODY_GEAR:
        assert p.PREFIX+ref+'.xml' not in includes
    # Support and rest registration live under the shield. Follow both facing
    # directions and nonuniform actor scaling, without a garment transform.
    for step in range(p.SUPPORT_STEPS):
        ref=p.PREFIX+('盾牌' if step==0 else '盾牌-承托'+str(step))
        root=E.parse(str(b.OWNER/'LIBRARY'/(ref+'.xml')))
        support=root.find('.//x:DOMSymbolInstance[@name="换弹承托"]',b.NS)
        port=root.find('.//x:DOMSymbolInstance[@name="承托枪位"]',b.NS)
        assert support is not None and port is not None
        matrix=port.find('x:matrix/x:Matrix',b.NS)
        at=(float(matrix.get('tx','0')),float(matrix.get('ty','0')))
        assert math.dist(p.s.point(p.GUARD['weapon'],at),p.PISTOL_REST)<.00001
    # Validate only the new owned graph. Existing donor bitmap names are
    # registered media, not broken symbol dependencies.
    for file in (b.OWNER/'LIBRARY'/p.PREFIX).glob('*.xml'):
        root=E.parse(str(file));assert root.getroot().get('name')+'.xml' in includes,file
        for e in root.iter():
            ref=e.get('libraryItemName')
            if ref:assert (b.OWNER/'LIBRARY'/(ref+'.xml')).exists() or ref in media,(file,ref)
        for script in root.findall('.//x:script',b.NS):
            assert not any(x in (script.text or '') for x in ['配置装扮','attachMovie','主角函数','伤害计算']),file
    report={'scope':'fixed phase-two animation assets only; no combat decisions or damage',
      'sourceFrames':counts,'sharedGuardExact':True,'maxElbowGap':max_seam,'maxRightHandTravelPerFrame':max_hand_step,
      'maxKneeGap':max_knee_seam,'maxKnifeWristGap':max_wrist_gap,'maxKnifeGripGap':max_grip_gap,
      'pistolMagazineShots':8,'oneHandedSupportedReload':True,'weaponTransfersContinuous':True,
      'addedBodyGear':False,'supportOwnedByShield':True,'supportFoldsWhenIdle':True,
      'shieldBehindAllLimbs':True,'runtimeDressup':False,'sourceDependencyClosure':True,'events':all_labels}
    if not args.source_only:
        swf=b.ROOT/'flashswf/arts/new/Codex专用素材.swf';names,sprites=exports(swf)
        for action in metadata['actions']:
            raw=sprites[names[action['linkage']]]
            assert struct.unpack_from('<H',raw,2)[0]==action['frames'],action['name']
            frame=1;labels={}
            for tag,data in child_tags(raw):
                if tag==43:labels[frame]=data.split(b'\0')[0].decode('utf8')
                elif tag==1:frame+=1
            assert labels==all_labels[action['name']],(action['name'],labels)
        for old in ['战技容器-特勤盾冲','前治安官动作-盾冲']:
            assert struct.unpack_from('<H',sprites[names[old]],2)[0]==152,old
        report['compiledExports']=len(metadata['actions']);report['swfSha256']=hashlib.sha256(swf.read_bytes()).hexdigest()
        report['playerAndPhaseOneRushFrames']=152
    target=b.ROOT/'tmp/former-sheriff-phase-two/verification.json'
    target.write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf8')
    print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__':main()
