from pathlib import Path
import json,sys,hashlib
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/cf6-audio'))
from source import Source
s=Source(ROOT/'tmp/cf6-headbot-20261016/original-source.swf')
owners={}
def cue(owner,symbol,frame,ids,source=None,note='',status='missing'):
 row={'symbol':symbol,'frame':frame,'soundIds':ids if isinstance(ids,list) else [ids],
      'statusBefore':status,'source':source,'adaptation':note}
 if source:
  source_event=next((x for x in s.events if x['spriteId']==source[0] and x['frame']==source[1] and x['soundId']==row['soundIds'][0]),None)
  if source_event and source_event.get('envelope'):row['envelope']=source_event['envelope']
 owners.setdefault(owner,{'cues':[]})['cues'].append(row)
def original(owner,prefix,name,sid,offset=0,only=None):
 for e in s.events:
  if e['spriteId']==sid and (only is None or e['frame'] in only):
   cue(owner,prefix+name,e['frame']+offset,e['soundId'],[sid,e['frame']])
o='Codex大头机器人素材';p='Codex/大头机器人/动作/'
original(o,p,'双臂光束',936,18);original(o,p,'伸缩冲击',937);original(o,p,'机械碎裂',951)
o='Codex大刀机器人素材';p='Codex/大刀机器人/动作/'
for name,sid in [('波属性光束',906),('重劈',910),('横扫',912),('机械碎裂',924)]:original(o,p,name,sid)
o='Codex老头素材';p='Codex/老头/'
for sid in [970,972]:original(o,p+'human/动作/',str(sid),sid)
cue(o,p+'human/动作/974',1,[1117,1131],[975,70],'原作根状态的倒地呼声，迁到对应身体入口。')
for sid in [994,997,1007]:original(o,p+'robot/动作/',str(sid),sid)
original(o,p+'robot/动作/','1010',1010,only=[2,14])
cue(o,p+'robot/动作/19940',2,907,[994,2],'新增重束从蓄能开始播放原机械起手声。')
cue(o,p+'robot/动作/19940',52,992,[994,28],'新增24帧蓄能使重束出光提示顺延24帧。')
for frame,cid in [(2,1993),(81,2004)]:cue(o,p+'变身/角色演出',frame,cid,[2008,frame])
cue(o,p+'变身/角色演出',92,2007,[2008,255],'283帧演出收束到93帧交接；末次爆裂提示放在交接前。')
o='Codex蛮蛮素材';p='Codex/蛮蛮/'
for name,sid,rows in [('Symbol 1116',653,[(2,649,2),(13,652,16)]),('Symbol 1117',656,[(2,654,2),(13,655,13)])]:
 for frame,cid,origin in rows:cue(o,p+'CF7/'+name,frame,cid,[sid,origin],'沿当前CF7招式的实际发力时点适配。')
for f in [2,24]:cue(o,p+'CF7/Symbol 1118',f,658,[659,2],'当前两种受击分支各保留一次原作声效。')
cue(o,p+'动作/血腥死',21,303,[691,21])
owners[o]['removeEmbedded']=[{'symbol':p+'CF7/'+n,'frame':13,'soundName':'音效/sound455.mp3'} for n in ['Symbol 1116','Symbol 1117']]
o='Codex特种兵素材';p='Codex/特种兵/动作/'
cue(o,p+'匕首刺击',14,513,[517,14])
cue(o,p+'持盾匕首刺击',14,513,[573,12],'持盾当前伤害帧由正式武器动作统一到第14帧。')
cue(o,p+'破盾',2,576,[579,2])
cue(o,p+'被投',2,[1121,1135,1144],[519,2])
cue(o,p+'击飞',1,[1121,1135,1144],[559,70],'原作根状态的倒地呼声。')
cue(o,p+'倒地恢复',1,303,[520,19],'适配CF7物理落地入口，不在空中提前播放落地声。')
for f in [1,59,105]:cue(o,p+'死亡',f,[1123,1137,1146,1151,1154,1157],[559,77],'当前三个死亡分支各一次原作死亡声。')
o='Codex光头保安素材';p='Codex/光头保安/动作/'
original(o,p,'变身',887)
cue(o,p+'被投',2,[1121,1135,1144],[598,2])
cue(o,p+'击飞',1,[1121,1135,1144],[888,70],'原作根状态的倒地呼声。')
cue(o,p+'倒地恢复',1,303,[875,20],'适配CF7物理落地入口。')
for f in [1,32,78]:cue(o,p+'死亡',f,[1123,1137,1146,1151,1154,1157],[888,77],'当前三个死亡分支各一次原作死亡声。')
o='CodexWings素材';p='Codex/Wings/'
cue(o,p+'CF7/闪6特工/MovieClip/sprite 861',7,513,[868,7],'原作第一段武器起手；保留现有其余五段斩击与后空翻音效。')
cue(o,p+'CF7/闪6特工/MovieClip/sprite 863',1,[1143,1150],[870,2],'击倒/投掷适配到CF7短起手。')
cue(o,p+'CF7/闪6特工/MovieClip/起身',1,303,[871,15],'当前物理落地入口。')
for f in [1,59,96]:cue(o,p+'动作/死亡',f,[1120,1134],[873,77],'三种原生死亡分支各一次。')
o='Antigravity专用素材'
for form,attack,throw,fall in [('CF6普通男僵尸',405,407,408),('CF6女僵尸',1631,1633,1634)]:
 p='Antigravity/'+form+'/动作/'
 cue(o,p+'攻击',2,288,[attack,2])
 for f in [2,24]:cue(o,p+'被投',f,288,[throw,2],'两种当前被投姿势。')
 cue(o,p+'倒地',1,303,[fall,12],'物理落地入口；保留已有僵尸死亡呼声。')
owners[o]['replacements']=[{'symbol':'Antigravity/CF6女僵尸/动作/击倒',
 'old':'_root.播放音效("僵尸0" + (random(6) + 1) + ".wav");','soundIds':[1143,1150]},
 {'symbol':'Antigravity/CF6女僵尸/敌人-CF6女僵尸',
 'old':'_root.播放音效("僵尸0" + (random(6) + 1) + ".wav");','soundIds':[1143,1150]}]
data={'schema':'cf6.audio-cues.v1','sourceSwfSha256':s.sha256,'route':'_root.播放音效',
 'embeddedSoundTracksAllowed':False,'owners':owners,
 'runtimeCues':[{'owner':'Codex老头素材','source':[1010,30],'soundId':1009,'at':'robot death frame 32','adaptation':'与碎裂和一次性亡语同步，顺延两帧。'},
 {'owner':'Codex大头机器人素材','soundId':1009,'at':'death frame 19','adaptation':'新增机械爆裂'},
 {'owner':'Codex大刀机器人素材','soundId':1009,'at':'death frame 5','adaptation':'新增机械爆裂'},
 {'owner':'Codex老头素材','sound':'shoot.wav','at':'human burst actual emission','adaptation':'原作此场枪声音为无；当前穿刺枪新增既有CF7射击声。'}]}
path=ROOT/'tools/cf6-audio/cues.json'
with path.open('x',encoding='utf8') as f:json.dump(data,f,ensure_ascii=False,indent=2)
print(json.dumps({'owners':len(owners),'timelineCues':sum(len(v['cues']) for v in owners.values()),'sourceSha256':s.sha256}))
