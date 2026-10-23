"""Restore source transport animation without adding or changing enemy budgets."""
from pathlib import Path
import json
import math

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'tools/cf6-scene-completion/transport-art-manifest.json'
EXPECTED = {'A09':(112,'兵种467',45,5), 'A14':(505,'兵种469',50,7), 'A18':(147,'兵种463',59,5)}

def adapt(chapter, require_swfs=True):
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8-sig'))
    if (manifest['schema'] != 'cf6-transport-native-source.v1'
            or manifest['originalSha256'] != 'b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01'
            or len(manifest['assets']) != 1):
        raise ValueError('unreviewed transport source')
    asset = manifest['assets'][0]
    url = 'flashswf/backgrounds/cf6/preparation/CF6_Transport1868.swf'
    if (asset['sourceSprite'] != 1868 or asset['frames'] != 29 or asset['dispatchFrame'] != 29
            or asset['swf'] != url or asset['localOrigin'] != [0,0]
            or asset['localCompensation'] != [0,0] or asset['visualScale'] != 1
            or not (ROOT / asset['xfl']).is_file()):
        raise ValueError('transport source geometry or timeline changed')
    if require_swfs and (not (ROOT/url).is_file() or (ROOT/url).read_bytes()[:3] not in (b'FWS',b'CWS',b'ZWS')):
        raise ValueError('fresh CS6 transport resource required')
    maps = {m['id']:m for m in chapter['maps']}
    placements = manifest['placements']
    if len(placements) != 3 or {p['mapId'] for p in placements} != set(EXPECTED):
        raise ValueError('transport placement inventory changed')
    audit = []
    for source in placements:
        identity = source['mapId']; stage = maps[identity]
        depth, enemy_type, level, quantity = EXPECTED[identity]
        matrix = source['nativeMatrix']; scale = stage['presentation']['scale']
        if (source['sourceDepth'] != depth or source['sourceSprite'] != 1868
                or matrix[:4] != [1,0,0,1] or len(matrix) != 6
                or any(not math.isfinite(v) for v in matrix)
                or not math.isfinite(scale) or scale <= 0
                or source['coordinateSpace'] != 'original gameworld; transform once in scene assembly'):
            raise ValueError('transport placement transform changed')
        if 'transport' in stage['mechanism']: raise ValueError('transport already assembled')
        waves = stage['stage']['Wave']['SubWave']
        if len(waves) != 2 or len(waves[1]['EnemyGroup']['Enemy']) != 1:
            raise ValueError('transport budget wave changed')
        enemy = waves[1]['EnemyGroup']['Enemy'][0]
        if ((enemy['Type'],enemy['Level'],enemy['Quantity'],enemy['Interval'],enemy['SpawnIndex'])
                != (enemy_type,level,quantity,100,0) or 'TriggerEvent' in enemy):
            raise ValueError('transport existing budget changed')
        token = f'{identity}-transport-{depth}'
        x,y = [round(v*scale,4) for v in matrix[4:]]
        bounds = [round(v*scale,4) for v in manifest['triggers']['1868']['localAabb']]
        stage['mechanism']['transport'] = {
            'schema':'cf6-transport.v1','id':token,'sourceSprite':1868,'url':url,
            'x':x,'y':y,'sortY':round(y+asset['frame1VisualBounds'][3],4),
            'artMatrix':[1,0,0,1,0,0],'hitBounds':bounds,
            'frames':29,'dispatchFrame':29,'subWaveIndex':1}
        enemy['TriggerEvent'] = {'EventName':'Cf6TransportReady','Parameters':[token]}
        enemy['Interval'] = 400
        audit.append({'id':token,'sourceSprite':1868,'sourceDepth':depth,'frames':29,
            'registrationWorld':[x,y],'visualScale':1,'hitBounds':bounds,
            'enemyType':enemy_type,'level':level,'existingQuantity':quantity,'finalQuantity':quantity,
            'subWaveIndex':1,'spawnIndex':0,'intervalMs':400,'effectiveRepeatMs':500,
            'spawnPolicy':'preserve current free-foot spawn point; counted WaveSpawnWheel owns quantities',
            'dispatchPolicy':'frame29 latch; exact same second-wave owner after listener registration; once only'})
    return audit
