"""Inspect the actual published AS2 library without modifying its bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

ROOT=Path(__file__).resolve().parents[2]

def tags(data):
    pos=0
    while pos+2<=len(data):
        h=struct.unpack_from('<H',data,pos)[0];pos+=2
        code,length=h>>6,h&63
        if length==63:length=struct.unpack_from('<I',data,pos)[0];pos+=4
        payload=data[pos:pos+length];pos+=length
        if len(payload)!=length:raise ValueError('Truncated SWF tag')
        yield code,payload
        if code==0:break

def inspect(path):
    raw=Path(path).read_bytes()
    body=zlib.decompress(raw[8:]) if raw[:3]==b'CWS' else raw[8:]
    if raw[:3] not in [b'CWS',b'FWS']:raise ValueError('Unsupported SWF compression')
    rect=(5+4*(body[0]>>3)+7)//8
    fps=struct.unpack_from('<H',body,rect)[0]/256
    exports={};sprites={};fonts={}
    for code,data in tags(body[rect+4:]):
        if code==56:
            pos=2
            for _ in range(struct.unpack_from('<H',data)[0]):
                ident=struct.unpack_from('<H',data,pos)[0];pos+=2
                end=data.index(b'\0',pos)
                exports[data[pos:end].decode('utf-8')]=ident;pos=end+1
        elif code==39:
            ident,n=struct.unpack_from('<HH',data)
            entries=list(tags(data[4:]));children=[]
            for child_code,child in entries:
                if child_code==26 and child[0]&2:
                    children.append(struct.unpack_from('<H',child,3)[0])
            sprites[ident]={'frames':n,'children':sorted(set(children)),
                            'has_mask':any(c==26 and d[0]&0x40 for c,d in entries),
                            'actions':sum(c in [12,59] for c,d in entries)}
        elif code in [48,75]:
            length=data[4];name=data[5:5+length].rstrip(b'\0').decode('utf-8')
            fonts[name]={'glyphs':struct.unpack_from('<H',data,5+length)[0],
                         'hash_without_id':hashlib.sha256(data[2:]).hexdigest()}
    return {'path':str(path),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),
            'fps':fps,'exports':exports,'sprites':sprites,'fonts':fonts}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',default='tmp/tonghe-gold/swf-verification.json');args=parser.parse_args()
    data=inspect(ROOT/'flashswf/arts/素材库-物品技能图标.swf')
    parent=data['sprites'][data['exports']['图标-金钱']]
    children=[data['sprites'][i] for i in parent['children'] if i in data['sprites']]
    assert data['fps']==30 and parent['frames']==1 and len(children)==1
    child=children[0]
    assert child['frames']==32 and child['has_mask'] and child['actions']==0
    expected={'STFangsong':1,'STXingkai':9,'STLiti':5}
    assert all(data['fonts'].get(n,{}).get('glyphs')==count for n,count in expected.items()),data['fonts']
    report={k:v for k,v in data.items() if k not in ['exports','sprites']}
    report.update({'linkage':'图标-金钱','outer':parent,'animation':child,'original_font_families_preserved':True})
    out=ROOT/args.out;out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
