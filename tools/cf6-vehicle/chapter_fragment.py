"""A07-only chapter input. The root assembler owns insertion, story and the one allowance."""
from pathlib import Path
import copy
import hashlib
import json
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SCALE = 1024 / 600
INPUTS = [Path(__file__), HERE/'source/original-nodes.json',
          ROOT/'tools/cf6-scene-completion/source-evidence/original.json',
          ROOT/'tools/cf6-scene-completion/completion-plan.json']
ASSET_URL = 'flashswf/arts/new/CF6Vehicle.swf'
BACKGROUND = 'cf6/CF6_A07_BG.swf'


def mul(outer, inner):
    a,b,c,d,x,y = outer
    e,f,g,h,u,v = inner
    return [a*e+c*f,b*e+d*f,a*g+c*h,b*g+d*h,a*u+c*v+x,b*u+d*v+y]


def scaled(value):
    return round(value*SCALE, 4)


def build(require_swfs=False):
    evidence = json.loads(INPUTS[2].read_text(encoding='utf-8-sig'))
    if evidence['swfSha256'] != 'b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01':
        raise ValueError('A07 source identity changed')
    plan = json.loads(INPUTS[3].read_text(encoding='utf-8-sig'))['vehicle']
    required = [ASSET_URL, 'flashswf/backgrounds/'+BACKGROUND, 'flashswf/backgrounds/cf6/CF6_A07_sky.swf']
    if require_swfs:
        for path in required:
            p = ROOT/path
            if not p.is_file() or p.read_bytes()[:3] not in (b'FWS', b'CWS', b'ZWS'):
                raise ValueError('A07 precise CS6 resource required: '+path)
    rules = {key:copy.deepcopy(plan[key]) for key in ('fps','roadKillThreshold','roadToBossFrames',
             'fireIntervalMs','barrels','bossLoopFrames','bossThrowFrame','bossDeathFirstFrame',
             'bossExitFrame','originalBossHp')}
    spec = {'schema':'cf6-vehicle.v1','mapId':'A07','assetUrl':ASSET_URL,'assetAnchor':'CF6Vehicle',
            'scale':SCALE,'rules':rules,'sourcePlayerHealth':200,'speedX':8,'speedZ':4,
            'projectilePower':20,'projectileSpeed':20,'hazardSpeed':20,
            'sourcePlayerSpawn':[265.45,352.15], 'sourceRoadOrigin':[632.35,250.75],
            'sourceWorldBounds':[50,280,1800,500], 'sourceCameraCanvas':[1150,450],
            'sourceStageCanvas':[600,350], 'sourceCameraRange':[-550,-100,0,0],
            'sourceBudget':[200,15,200], 'sourceConcurrency':[1,1,1],
            'tailCounts':{'raider':2,'shield':5,'obstacle':2},
            'symbols':{'player':'CF6VehiclePlayer','boss':'CF6VehicleArmoredBoss',
                       'road':'CF6VehicleRoad','raider':'CF6VehicleRaider','shield':'CF6VehicleShield',
                       'obstacle':'CF6VehicleRoadblock','grenade':'CF6VehicleGrenade',
                       'bullet':'CF6VehicleBullet','spark':'CF6VehicleSpark','explosion':'CF6VehicleExplosion'}}
    node = {'id':'A07','title':'公路突围','background':BACKGROUND,'dialogue':[],
        'stage':{'BasicInformation':{'PlayerX':scaled(265.45),'PlayerY':scaled(352.15),
                 'Background':'flashswf/backgrounds/'+BACKGROUND,'EndFrame':'房间',
                 'BGM':{'Command':'play','Title':'Bulletproof','Loop':True}},
                 'Wave':{'SubWave':[{'WaveInformation':{'Duration':0,'FinishRequirement':0},
                                    'EnemyGroup':{'Enemy':[]}}]},
                 'Instances':{'Instance':[]},'Pickups':{'Pickup':[]}},
        'mechanism':{'kind':'plain','assetScale':SCALE,'layers':[
            {'id':'sky','role':'screen-fixed','coordinateSpace':'root-stage',
             'url':'flashswf/backgrounds/cf6/CF6_A07_sky.swf','x':0,'y':-110,'width':800,'height':253,'depth':0}],
            'vehicle':spec},
        'presentation':{'scale':SCALE,'backgroundX':0,'backgroundY':0},
        'geometryBasis':{'vehicleSource':{'originalSha256':evidence['swfSha256'],
              'world':1816,'mainFrame':104,'space':'original world coordinates multiplied once by 1024/600',
              'cameraCanvas':[1150,450],'stageCanvas':[600,350],
              'collision':'four original 1433 border markers; no ordinary walking spawn approximation'}},
        'sourceNote':{'vehicle':'fixed original car/dual guns; dedicated actors and collision; current hero owns HP',
                      'allowance':'root moves the existing A08 40000 here exactly once via standard Pickup'}}
    environment = ET.Element('Environment')
    values = {'BackgroundURL':'CF6_A07_BG.swf','Alignment':'true',
        'Xmin':scaled(50),'Ymin':scaled(280),'Xmax':scaled(1800),'Ymax':scaled(500),
        'Width':scaled(1150),'Height':scaled(450),'DisableSky':'true','SpaceCondition':'室外',
        'MaxIllumination':8,'MinIllumination':8}
    for key,value in values.items():
        ET.SubElement(environment,key).text=str(value)
    # Border marker1433 is a transformed 277 rectangle. Keep original physical sides, not a guessed road box.
    marker = [6.18182373046875,0,0,3.9166717529296875,102,47]
    border_audit = []
    for placement in evidence['worlds']['A07']['placements']:
        if placement['id'] != 1433:
            continue
        a,b,c,d,x,y = mul(placement['matrix'],marker)
        points = [(scaled(a*u+c*v+x),scaled(b*u+d*v+y))
                  for u,v in [(-16.5,-12),(16.5,-12),(16.5,12),(-16.5,12)]]
        collision = ET.SubElement(environment,'Collision')
        for px,py in points:
            ET.SubElement(collision,'Point').text=str(px)+','+str(py)
        border_audit.append({'sourceDepth':placement['depth'],'points':points})
    if len(border_audit) != 4:
        raise ValueError('A07 original border inventory changed')
    audit = {'schema':'cf6-vehicle-chapter.v1','mapId':'A07','scale':SCALE,
             'requiredAssets':required,'originalSha256':evidence['swfSha256'], 'borders':border_audit,
             'emptyWavePolicy':'vehicle owner must block clear until actual tail collision',
             'allowanceOwner':'root existing standard Pickup at initial player position; service never credits money',
             'inputs':{p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in INPUTS}}
    return node, environment, audit
