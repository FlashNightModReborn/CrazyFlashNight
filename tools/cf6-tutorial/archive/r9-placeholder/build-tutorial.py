"""Independent CF6 tutorial stage reusing the existing practice background only.

No base-room scripts, saved character state, weapon grants or shared stage edits.
"""
from pathlib import Path
import argparse
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
ENV=ROOT/'data/environment/stage_environment.xml'
PRACTICE=ROOT/'data/stages/基地门口/新手练习场.xml'
BG=ROOT/'flashswf/backgrounds/gk1_1_BG.swf'


def scalar(text):
    value=(text or '').strip()
    if value=='true':return True
    if value=='false':return False
    try:return int(value)
    except ValueError:
        try:return float(value)
        except ValueError:return value


def read_node(node):
    if len(node)==0:return scalar(node.text)
    result={}
    for child in node:
        value=read_node(child)
        if child.tag in result:
            if not isinstance(result[child.tag],list):result[child.tag]=[result[child.tag]]
            result[child.tag].append(value)
        else:result[child.tag]=value
    return result


def build():
    assert BG.is_file(),'existing practice background is missing'
    environment=next(e for e in ET.parse(ENV).getroot().findall('Environment') if e.findtext('BackgroundURL')=='gk1_1_BG.swf')
    room=ET.parse(PRACTICE).getroot().find('SubStage')
    source_basic=read_node(room.find('BasicInformation'))
    basic={'Background':source_basic['Background'],'PlayerX':source_basic['PlayerX'],'PlayerY':source_basic['PlayerY'],
        'EndFrame':'房间','BGM':source_basic['BGM']}
    # Proposed target group copies the existing first practice stage types/levels;
    # content integration may replace it with an equally small explicitly authored group.
    enemies=[]
    for enemy in room.findall('./Wave/SubWave/EnemyGroup/Enemy'):
        target=read_node(enemy);target['Parameters']={'掉落物':[]};enemies.append(target)
    pickups=[{'Name':'战场长枪弹药包','Value':1,'x':500,'y':460},
             {'Name':'战场复合急救包','Value':1,'x':780,'y':460}]
    stage={'BasicInformation':basic,'Instances':{'Instance':[]},'SpawnPoint':{'Point':[]},
        'Pickups':{'Pickup':pickups},
        'Event':[{'EventName':'Start','Guidance':'引导-拾取',
                  'Message':'行动前训练：向右移动，切换长枪并试射。靠近补给后执行拾取；药品或弹药已满时无需消耗。'},
                 {'EventName':'Clear','Message':'训练目标已清理。完成补给检查后，走到上方路障的箭头区域，进入毒刺行动。'}],
        'Wave':{'SubWave':[{'WaveInformation':{'Duration':0},'EnemyGroup':{'Enemy':enemies}}]}}
    result={'id':'TUTORIAL','title':'行动前训练','background':'gk1_1_BG.swf',
        'mechanism':{'kind':'exit','layers':[]},
        'dialogue':[{'speaker':'Andy','text':'正式行动前，先确认移动与射击操作。M4A1战术版和镜之虎彻已经在初始装备里，训练区不会再发一把枪。'},
                    {'speaker':'Andy','text':'切换到长枪，向右找到训练目标。靠近地面的补给后执行拾取，检查弹药与恢复反馈；具体按键沿用你当前的操作设置。'},
                    {'speaker':'Andy','text':'清理目标后，上方路障会开放。沿箭头离开训练区，进入行动第一现场。'}],
        'stage':stage}
    manifest={'schema':'cf6-tutorial-assembly.v1','mapId':'TUTORIAL',
        'sources':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [ENV,PRACTICE,BG]],
        'environment':read_node(environment),'spawn':[basic['PlayerX'],basic['PlayerY']],
        'borrowedScope':'existing published background and its standard environment only; no base scene business scripts',
        'weaponGrants':0,'externalRewards':0,
        'targetGroup':'proposal copied from first current 新手练习场 substage; content owner integrates final group',
        'tutorialContract':['movement toward target','switch current initial long gun and fire','pick up one ammo and one recovery supply','observe full-state or applied supply feedback','clear targets and use standard upper exit'],
        'acceptanceBoundary':'data/source prepared only; no actual tutorial playthrough claimed'}
    return {'tutorial-map.json':result,'tutorial.manifest.json':manifest}


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    for name,value in build().items():
        path=HERE/'generated'/name;content=(json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()
        if args.check:assert path.read_bytes()==content,'stale '+name
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(content)
    print('TUTORIAL uses existing gk1_1_BG.swf + environment; no new SWF or duplicate weapon grant')
