from pathlib import Path
import sys,re,json,hashlib,zipfile
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools/cf6-audio'))
from source import Source
original=ROOT/'tmp/cf6-headbot-20261016/original-source.swf'
source=Source(original)
scripts=ROOT/'tmp/cf6-headbot-20261016/original-scripts-simplified/scripts'
units={353:'旧克隆兽',477:'男僵尸',1694:'女僵尸',559:'特种兵',580:'持盾特种兵',692:'蛮蛮',873:'Wings及旧女特工',888:'光头保安',925:'大刀机器人',952:'大头机器人',975:'老头人形',1011:'老头机器人'}
rows=[]
for root,name in units.items():
 closure=source.closure(root)
 events=[r for r in source.events if r['spriteId'] in closure]
 calls=[]
 for directory in scripts.glob('DefineSprite_*'):
  cid=int(re.match(r'DefineSprite_(\d+)',directory.name)[1])
  if cid not in closure:continue
  for p in directory.rglob('*.as'):
   text=p.read_text('utf-8-sig')
   for line in text.splitlines():
    if 'attachSound' in line or re.search(r'(声音|枪声音)\s*=',line):
     calls.append({'path':p.relative_to(scripts).as_posix(),'source':line.strip()})
 rows.append({'root':root,'unit':name,'originalLinkage':source.exports[root],
  'timelineSounds':events,'scriptSoundCalls':calls})
report={'originalSwf':str(original),'sha256':source.sha256,'fps':source.fps,'units':rows,
 'sounds':[source.sound_metadata(cid) for cid in sorted(source.sounds)]}
(HERE/'original-audio-inventory.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf8')
for row in rows:
 print(row['unit'],row['root'],'timeline',[(e['spriteId'],e['frame'],e['soundId']) for e in row['timelineSounds']])
 print('script',[(e['path'],e['source']) for e in row['scriptSoundCalls']])
