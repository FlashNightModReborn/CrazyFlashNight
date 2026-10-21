"""Check actual Flash mouth pixels against the source-bound published resource."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image
import bite_support

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent


def point(matrix,local):
    a,b,c,d,x,y=matrix
    return (a*local[0]+c*local[1]+x,b*local[0]+d*local[1]+y)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('evidence',type=Path)
    ap.add_argument('decoded',type=Path)
    args=ap.parse_args()
    binding=json.loads((args.evidence/'binding.json').read_text(encoding='utf-8-sig'))
    assert binding['guardMode']=='actual published resource via RSL'
    resource=ROOT/'flashswf/arts/new/Codex专用素材.swf'
    assert hashlib.sha256(resource.read_bytes()).hexdigest()==binding['publishedResource']['sha256']
    for row in binding['canonicalSnapshots']:
        assert hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest()==row['sha256']
    archive=ROOT/'flashswf/arts/new/Codex素材源稿/军阀铁卫犬-R2/rig-adaptation'
    rig=json.loads((archive/'rig.json').read_text(encoding='utf-8'))
    rig=bite_support.apply(rig,json.loads((HERE/'bite-support.json').read_text(encoding='utf-8')))
    anchors=json.loads((archive/'mouth-rule.json').read_text(encoding='utf-8'))['anchors']
    checks=[]
    for number in (4,5,6,13,14,15):
        rows={p['depth']:p for p in rig['sequences']['attack']['frames'][number-1]['placements']}
        hinge,upper,lower=(point(rows[anchors[k]['depth']]['matrix'],anchors[k]['local']) for k in ('hinge','upper','lower'))
        for side,sign in (('right',1),('left',-1)):
            image=Image.open(args.decoded/f'guard-{side}-{number}.png')
            assert image.size==(400,240) and image.mode=='RGBA'
            for kind,u,v in (('anteriorGap',.4,.4),('rearCheek',.12,.14),('tongue',.09,.50)):
                pos=[hinge[i]+u*(upper[i]-hinge[i])+v*(lower[i]-hinge[i])for i in (0,1)]
                xy=(round(200+sign*2*(6.45+pos[0])),round(170+2*(-63.5+pos[1])))
                red,green,blue,alpha=image.getpixel(xy)
                valid=alpha<32 if kind=='anteriorGap' else alpha>240
                if kind=='tongue':valid=valid and red>green*1.2 and red>blue
                assert valid,(number,side,kind,xy,(red,green,blue,alpha))
                checks.append({'frame':number,'side':side,'kind':kind,'pixel':xy,'rgba':[red,green,blue,alpha]})
    print(json.dumps({'result':'PASS','pixelChecks':len(checks),'anteriorGapTransparent':True,
        'rearCheekOpaque':True,'tongueVisible':True,'bothDirections':True,
        'resourceSha256':binding['publishedResource']['sha256'],'samples':checks},ensure_ascii=False))


if __name__=='__main__':main()
