"""Add ordinary AS2 calls to native SFX; never attach sound tracks to XFL frames."""
from pathlib import Path
import hashlib
import json
from lxml import etree as E

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
NS={'x':'http://ns.adobe.com/xfl/2008/'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sound_name(cid,envelope=None):
    if envelope:
        token=hashlib.sha256(json.dumps(envelope,sort_keys=True,separators=(',',':')).encode()).hexdigest()[:10]
        return f'CF6_{cid:04d}_{token}.wav'
    return f'CF6_{cid:04d}.mp3'


def config(owner):
    cues=json.loads((HERE/'cues.json').read_text('utf8'))
    assets=json.loads((HERE/'assets.json').read_text('utf8'))
    if assets['cuesSha256']!=sha(HERE/'cues.json'):
        raise ValueError('Regenerate the audio asset manifest before assembling XFL')
    for row in assets['files']:
        if sha(ROOT/row['path'])!=row['sha256']:
            raise ValueError('Changed SFX asset: '+row['path'])
    return cues,assets,cues['owners'][owner.name]


def input_rows(owner):
    cues,assets,group=config(owner)
    names={sound_name(cid,row.get('envelope')) for row in group['cues']+group.get('replacements',[]) for cid in row['soundIds']}
    for row in cues['runtimeCues']:
        if row['owner']==owner.name and 'soundId' in row:names.add(sound_name(row['soundId']))
    paths=[HERE/'build.py',HERE/'cues.json',HERE/'assets.json']
    paths += [ROOT/row['path'] for row in assets['files'] if row['name'] in names]
    return [{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p)} for p in sorted(paths)]


def statement(row):
    names=[sound_name(cid,row.get('envelope')) for cid in row['soundIds']]
    expression=json.dumps(names[0],ensure_ascii=False) if len(names)==1 else json.dumps(names,ensure_ascii=False)+'[random('+str(len(names))+')]'
    return '_root.播放音效('+expression+');'


def apply(symbols,owner,make_sparse_layer):
    _,_,group=config(owner)
    removed=[]
    allowed={(r['symbol'],r['frame'],r['soundName']) for r in group.get('removeEmbedded',[])}
    for name,root in symbols.items():
        for frame in root.findall('.//x:DOMFrame[@soundName]',NS):
            key=(name,int(frame.get('index'))+1,frame.get('soundName'))
            if key not in allowed:raise ValueError('Unreviewed embedded sound: '+str(key))
            removed.append(key)
            for attr in list(frame.attrib):
                if attr.startswith('sound'):del frame.attrib[attr]
            for envelope in frame.findall('x:SoundEnvelope',NS):frame.remove(envelope)
    if set(removed)!=allowed:raise ValueError('Expected legacy sound track changed')
    by_symbol={}
    for row in group['cues']:by_symbol.setdefault(row['symbol'],[]).append(row)
    for name,rows in by_symbol.items():
        if name not in symbols:raise ValueError('Missing audio consumer '+name)
        root=symbols[name]
        frames=root.findall('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer/x:frames/x:DOMFrame',NS)
        count=max(int(f.get('index','0'))+int(f.get('duration','1')) for f in frames)
        events={}
        for row in rows:
            index=row['frame']-1
            if not 0<=index<count:raise ValueError('Audio cue outside current action: '+name)
            call=statement(row)
            if row.get('once'):
                call='if(this.cf6DeathVoicePlayed!==true){this.cf6DeathVoicePlayed=true;'+call+'}'
            events.setdefault(index,[]).append(call)
        layer=make_sparse_layer('原生SFX调用',count,{i:{'script':'if(!_root.暂停 && this===_parent.man){'+''.join(calls)+'}'} for i,calls in events.items()})
        root.find('x:timeline/x:DOMTimeline/x:layers',NS).insert(0,layer)
    for row in group.get('replacements',[]):
        found=0
        for node in symbols[row['symbol']].findall('.//x:script',NS):
            text=node.text or ''
            if row['old'] in text:
                found+=text.count(row['old']);node.text=E.CDATA(text.replace(row['old'],statement(row)))
        if found!=1:raise ValueError('Voice replacement no longer matches '+row['symbol'])
    return {'route':'_root.播放音效','timelineCalls':len(group['cues']),
        'voiceReplacements':len(group.get('replacements',[])),'removedEmbeddedTracks':len(removed),
        'inputs':input_rows(owner)}


def check(manifest,owner):
    receipt=manifest.get('audio')
    if receipt is None or receipt['inputs']!=input_rows(owner):
        raise ValueError('Audio inputs changed; regenerate this owned library')
    for row in manifest['outputs']:
        tree=E.parse(str(owner/row['path']))
        if tree.findall('.//x:DOMFrame[@soundName]',NS) or tree.findall('.//x:DOMSoundInstance',NS):
            raise ValueError('Embedded audio is forbidden in CF6 consumers')
