"""Add two bounded native-SFX calls while retaining every original source byte."""
from pathlib import Path
import argparse,hashlib,json,re
from lxml import etree as E
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
NS={'x':'http://ns.adobe.com/xfl/2008/'}
parser=argparse.ArgumentParser();parser.add_argument('--write',action='store_true');args=parser.parse_args()
config=json.loads((HERE/'legacy-cues.json').read_text('utf8'));rows=[]
for row in config['cues']:
    path=ROOT/row['path'];data=path.read_bytes();newline='\r\n' if b'\r\n' in data else '\n'
    index=row['frame']-1;frames=[]
    if index:frames.append(f'            <DOMFrame index="0" duration="{index}" keyMode="9728"><Actionscript><script><![CDATA[cf6LegacyAudioBody=true;]]></script></Actionscript><elements/></DOMFrame>')
    call='cf6LegacyAudioBody=true;if(!_root.暂停 && _parent._currentframe=='+str(row['rootFrame'])+' && _parent[this._name]===this){_root.播放音效('+json.dumps(row['sound'],ensure_ascii=False)+');}'
    frames.append(f'            <DOMFrame index="{index}" duration="{row["totalFrames"]-index}" keyMode="9728"><Actionscript><script><![CDATA[{call}]]></script></Actionscript><elements/></DOMFrame>')
    layer=(newline.join(['',f'        <DOMLayer name="{config["layer"]}" color="#FFFF00" locked="true">','          <frames>',*frames,'          </frames>','        </DOMLayer>'])).encode('utf8')
    pattern=re.escape((newline+'        <DOMLayer name="'+config['layer']+'"').encode('utf8'))+rb'.*?</DOMLayer>'
    base,count=re.subn(pattern,b'',data,flags=re.S);assert count in (0,1)
    assert hashlib.sha256(base).hexdigest()==row['beforeSha256'],'Unreviewed edit: '+row['path']
    assert base.count(b'<layers>')==1
    expected=base.replace(b'<layers>',b'<layers>'+layer,1)
    tree=E.fromstring(expected);assert not tree.findall('.//x:DOMFrame[@soundName]',NS)
    assert (ROOT/'sounds/export/人物'/row['sound']).is_file()
    if args.write:path.write_bytes(expected)
    else:assert data==expected,'Run --write to restore legacy cue: '+row['path']
    rows.append({'path':row['path'],'beforeSha256':row['beforeSha256'],'sha256':hashlib.sha256(expected).hexdigest()})
print(json.dumps({'ok':True,'nativeRoute':'_root.播放音效','calls':len(rows),'files':rows},ensure_ascii=False))
