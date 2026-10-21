"""Guard four planted paws, connected armor/limbs and the original action timing."""
import json
import math
from pathlib import Path
import bite_support

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent


def local_origin(part,body):
    offset=(part[4]-body[4],part[5]-body[5])
    return bite_support.rotate(offset,-math.atan2(body[1],body[0]))


def main():
    original=json.loads((ROOT/'flashswf/arts/new/Codex素材源稿/军阀铁卫犬-R2/rig-adaptation/rig.json').read_text(encoding='utf-8'))
    settings=json.loads((HERE/'bite-support.json').read_text(encoding='utf-8'))
    corrected=bite_support.apply(original,settings)
    legs=settings['legs']
    paws={leg['depths'][3] for leg in legs}
    assert paws=={60,100,150,190},'Four distinct fore/rear stance contacts required'
    limb_parts={d for leg in legs for d in leg['depths']}
    limb_roots={leg['depths'][0] for leg in legs}
    bind={p['depth']:p for p in original['sequences']['attack']['frames'][0]['placements']}
    changed=0
    contacts=0
    max_root_shift_y=0
    for name,seq in original['sequences'].items():
        after=corrected['sequences'][name]
        if name!='attack':
            assert seq==after,name
            continue
        assert {k:v for k,v in seq.items() if k!='frames'}=={k:v for k,v in after.items() if k!='frames'}
        assert len(seq['frames'])==len(after['frames'])
        for before,frame in zip(seq['frames'],after['frames']):
            assert before['frame']==frame['frame']
            active=4<=frame['frame']<=21
            assert {k:v for k,v in before.items() if k!='placements'}=={k:v for k,v in frame.items() if k!='placements'}
            assert len(before['placements'])==len(frame['placements'])
            for a,b in zip(before['placements'],frame['placements']):
                if a==b:
                    continue
                assert active
                assert {k:v for k,v in a.items() if k!='matrix'}=={k:v for k,v in b.items() if k!='matrix'}
                m,n=a['matrix'],b['matrix']
                # The delivered paw keys contain <0.1% quantization scale drift;
                # planted paws use the identical stance matrix for the full loop.
                if a['depth'] not in paws:
                    assert abs(math.hypot(*m[:2])-math.hypot(*n[:2]))<1e-10
                assert abs(math.hypot(*n[:2])-math.hypot(*n[2:4]))<1e-10
                assert abs(n[0]*n[2]+n[1]*n[3])<1e-10
                changed+=1
            rows={p['depth']:p for p in frame['placements']}
            # Fixed XY and angle across the entire attack, including preparation
            # and recovery: no lifted foot, toe rocking, or stance-foot skating.
            for d in paws:
                assert math.dist(rows[d]['matrix'],bind[d]['matrix'])<1e-9,(frame['frame'],d)
                contacts+=1
            if active:
                old={p['depth']:p for p in before['placements']}
                oldbody=old[110]['matrix'];body=rows[110]['matrix']
                assert -5<=math.degrees(math.atan2(body[1],body[0]))<=0
                for d in rows:
                    if d in limb_roots or d not in limb_parts:
                        assert math.dist(local_origin(rows[d]['matrix'],body),
                            local_origin(old[d]['matrix'],oldbody))<1e-9,(frame['frame'],d,'body attachment')
                    if d not in limb_parts and d!=235:
                        oldangle=math.atan2(old[d]['matrix'][1],old[d]['matrix'][0])-math.atan2(oldbody[1],oldbody[0])
                        angle=math.atan2(rows[d]['matrix'][1],rows[d]['matrix'][0])-math.atan2(body[1],body[0])
                        assert abs(oldangle-angle)<1e-9,(frame['frame'],d,'relative head/armor angle')
                head,jaw=(rows[d]['matrix'] for d in (230,235))
                gap=math.degrees(math.atan2(jaw[1],jaw[0])-math.atan2(head[1],head[0]))
                assert -8-1e-9<=gap<=18+1e-9,(frame['frame'],'controlled attack gape',gap)
                hinge=(head[4]+head[0]*60+head[2]*110,head[5]+head[1]*60+head[3]*110)
                assert math.dist(hinge,jaw[4:])<1e-9,'Jaw remains attached to the head hinge'
                for d in limb_roots:
                    shift=abs(rows[d]['matrix'][5]-bind[d]['matrix'][5])
                    max_root_shift_y=max(max_root_shift_y,shift)
                    assert shift<3,'Body must remain in a low braced stance'
                for leg in legs:
                    ds=leg['depths']
                    for a,b in zip(ds,ds[1:]):
                        local=(bind[b]['matrix'][4]-bind[a]['matrix'][4],bind[b]['matrix'][5]-bind[a]['matrix'][5])
                        m=rows[a]['matrix'];angle=math.atan2(m[1],m[0])
                        offset=bite_support.rotate(local,angle)
                        expected=(m[4]+offset[0],m[5]+offset[1])
                        actual=rows[b]['matrix'][4:]
                        assert math.dist(expected,actual)<1e-9,(frame['frame'],a,b)
    assert changed>0
    print(json.dumps({'changedMatrices':changed,'activeFrames':18,'legScalePreserved':True,
        'connectedJoints':True,'fixedPawContactsChecked':contacts,'allFourSolesPlanted':True,
        'stanceFootSkating':False,'maximumRootVerticalShift':max_root_shift_y,
        'unchangedHeadMotionRelativeToBody':True,'connectedLimbRootsAndArmor':True,
        'attackJawRelativeDegrees':[-8,18],'connectedJawHinge':True,
        'unchangedOtherSequences':6,'unchangedTimingAndGameplayEmitters':True},ensure_ascii=False))


if __name__=='__main__':main()
