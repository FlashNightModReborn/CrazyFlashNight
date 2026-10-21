"""Read actual CS6 SWFs; validate exports, sprite lengths and shared imports."""
from pathlib import Path
import hashlib,json,struct,subprocess,zlib

ROOT=Path(__file__).resolve().parents[2]
def cstring(data,pos):
    end=data.index(0,pos);return data[pos:end].decode('utf-8'),end+1
def tags(data,start):
    pos=start
    while pos<len(data):
        code_len=struct.unpack_from('<H',data,pos)[0];pos+=2;code=code_len>>6;size=code_len&63
        if size==63:size=struct.unpack_from('<I',data,pos)[0];pos+=4
        payload=data[pos:pos+size];assert len(payload)==size;pos+=size
        yield code,payload
        if code==0:break
def scan(raw):
    assert raw[:3] in (b'CWS',b'FWS')
    data=raw[:8]+zlib.decompress(raw[8:]) if raw[:3]==b'CWS' else raw
    assert len(data)==struct.unpack_from('<I',data,4)[0]
    start=8+(5+4*(data[8]>>3)+7)//8+4
    exports={};imports=[];sprites={};sprite_tags={};counts={}
    pos=start
    while pos<len(data):
        code_len=struct.unpack_from('<H',data,pos)[0];pos+=2;code=code_len>>6;size=code_len&63
        if size==63:size=struct.unpack_from('<I',data,pos)[0];pos+=4
        payload=data[pos:pos+size];assert len(payload)==size;pos+=size
        counts[code]=counts.get(code,0)+1
        if code==39:
            sid,frames=struct.unpack_from('<HH',payload);sprites[sid]=frames;sprite_tags[sid]=list(tags(payload,4))
        if code==56:
            total=struct.unpack_from('<H',payload)[0];p=2
            for _ in range(total):
                ident=struct.unpack_from('<H',payload,p)[0];name,p=cstring(payload,p+2);assert name not in exports;exports[name]=ident
        if code in (57,71):
            url,p=cstring(payload,0)
            if code==71:p+=2
            total=struct.unpack_from('<H',payload,p)[0];p+=2;assets=[]
            for _ in range(total):
                ident=struct.unpack_from('<H',payload,p)[0];name,p=cstring(payload,p+2);assets.append(name)
            imports.append({'url':url,'assets':assets})
        if code==0:break
    return {'exports':exports,'imports':imports,'spriteFrames':sprites,'spriteTags':sprite_tags,'topTagCounts':counts}
def attack_contract(swf,linkage):
    # Resolve the action from the real root's frame 42, rather than old SWF ids.
    root=swf['exports'][linkage];display={};frame=1
    for code,payload in swf['spriteTags'][root]:
        if code in (26,70):
            flags=payload[0];offset=2 if code==70 else 1
            depth=struct.unpack_from('<H',payload,offset)[0];offset+=2
            if code==70 and ((payload[1]&8) or ((payload[1]&16) and (flags&2))):_,offset=cstring(payload,offset)
            if flags&2:display[depth]=struct.unpack_from('<H',payload,offset)[0]
        elif code==28:display.pop(struct.unpack_from('<H',payload)[0],None)
        elif code==5:display.pop(struct.unpack_from('<H',payload,2)[0],None)
        elif code==1:
            if frame==42:break
            frame+=1
    actions=[sid for sid in display.values() if swf['spriteFrames'].get(sid)==87]
    assert len(actions)==1,(linkage,actions)
    frame=1;emissions=[];movement=[];emitter_depths=set()
    for code,payload in swf['spriteTags'][actions[0]]:
        if code==1:frame+=1
        elif code in (26,70):
            depth=struct.unpack_from('<H',payload,2 if code==70 else 1)[0]
            if '子弹区域shoot'.encode('utf-8') in payload:emissions.append(frame);emitter_depths.add(depth)
            if frame==8:movement.append({'depth':depth,'move':bool(payload[0]&1),'hasCharacter':bool(payload[0]&2),'clipActions':bool(payload[0]&128)})
    assert emissions==[7,13,16],(linkage,emissions)
    assert len(emitter_depths)==1
    assert any(r['depth'] in emitter_depths and r['move'] and not r['hasCharacter'] and not r['clipActions'] for r in movement)
    return {'attackFrames':87,'emissionFrames':emissions,'frame8ReusesExistingInstance':True}
owner='flashswf/arts/new/Codex专用素材.swf';consumer='flashswf/arts/things-new.swf'
previous=scan(subprocess.check_output(['git','show','HEAD:'+owner],cwd=ROOT))
current=scan((ROOT/owner).read_bytes());shared=scan((ROOT/consumer).read_bytes())
original=scan((ROOT/'flashswf/arts/things1.swf').read_bytes())
links={'敌人-制式军警犬','敌人-盗贼撕咬犬'}
assert set(current['exports'])==set(previous['exports'])|links,'Export set changed outside the dogs'
assert all(current['spriteFrames'][current['exports'][name]]==121 for name in links)
anchor=[row for row in shared['imports'] if 'Codex专用素材' in row['assets']]
assert len(anchor)==1 and 'Codex专用素材.swf' in anchor[0]['url']
contracts={'敌人-僵尸1-狗':attack_contract(original,'敌人-僵尸1-狗')}
contracts.update({name:attack_contract(current,name) for name in links})
print(json.dumps({'result':'PASS','ownerExportCount':len(current['exports']),
    'addedExports':sorted(links),'unchangedExistingExports':len(previous['exports']),
    'newRootFrameCounts':{name:current['spriteFrames'][current['exports'][name]] for name in sorted(links)},
    'sharedAnchor':anchor[0],'actualAttackContracts':contracts,
    'swfs':{p:{'bytes':(ROOT/p).stat().st_size,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()} for p in (owner,consumer)},
    'evidence':'compiled_swf_tag_readback'},ensure_ascii=False))
