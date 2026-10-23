"""Derive explicit tutorial furniture and wall fixtures from the pinned parent."""
import json
import calibrate as c
from derive_laboratory import inverse_point


def derive(recipe=None):
    recipe = json.loads(json.dumps(recipe if recipe is not None else c.read(c.HERE/'recipe.json')))
    policy = c.read(c.HERE/'scale-policy.json')['tutorialDesk']
    baseline = c.HERE/policy['parentBaseline']
    original = baseline.read_bytes()
    instances = c.roots(original)
    expected = ['Tutorial/房间壳-Symbol '+str(i) for i in (2303,2302,1927,2310)]
    rows = []
    for index,symbol in zip(policy['indices'],expected):
        item = instances[index]
        if item.get('libraryItemName') != symbol:raise ValueError('tutorial furniture selector changed')
        before = c.matrix(item.find('./x:matrix/x:Matrix',c.NS).attrib)
        rows.append({'id':'tutorial-right-desk-'+str(index),'mapId':'TUTORIAL','category':'furniture',
            'xflDirectory':'flashswf/backgrounds/cf6/CF6_Tutorial_BG',
            'parentFile':'LIBRARY/Tutorial/房间壳-Symbol 2577.xml','instanceIndex':index,'symbol':symbol,
            'baseline':policy['parentBaseline'],'baselineSha256':c.sha(original),
            'pivotNative':inverse_point(before,policy['parentPivot']),'localVisualScale':policy['localScale'],
            'assemblyId':'tutorial-right-desk-suite','assemblyPivotParent':policy['parentPivot'],
            'derivation':'tutorial-desk-source.v1','sourceArt':'flashswf/levels/基地场景合集/LIBRARY/sprite/Symbol 2577.xml',
            'justification':'桌/桶盖/桶身/台灯共用桌前脚点，仅抵消房壳1.383与地图128/75额外倍率；桌前缘到脚恢复63.075px，约76cm。',
            'collisionPolicy':'不改变房壳、墙、门、地板及地图碰撞；只校准明确子实例。'})
    wall = c.read(c.HERE/'scale-policy.json')['tutorialWall']
    if wall['parentBaseline'] != policy['parentBaseline']:
        raise ValueError('tutorial fixtures must share the reviewed parent baseline')
    approved = {'poster-cluster': ([6,7,8,9,10],[2287,2283,2282,2280,2278]),
                'fire-extinguisher': ([12,13,14],[2293,476,2292])}
    if {group['id'] for group in wall['groups']} != set(approved):
        raise ValueError('unexpected tutorial wall fixture group')
    for group in wall['groups']:
        if (group['indices'],group['symbols']) != approved[group['id']]:
            raise ValueError('tutorial wall fixture selector changed')
        for index,number in zip(group['indices'],group['symbols']):
            item = instances[index]
            symbol = 'Tutorial/房间壳-Symbol '+str(number)
            if item.get('libraryItemName') != symbol:
                raise ValueError('tutorial wall fixture symbol changed')
            before = c.matrix(item.find('./x:matrix/x:Matrix',c.NS).attrib)
            rows.append({'id':'tutorial-wall-'+group['id']+'-'+str(index),
                'mapId':'TUTORIAL','category':'furniture',
                'xflDirectory':'flashswf/backgrounds/cf6/CF6_Tutorial_BG',
                'parentFile':'LIBRARY/Tutorial/房间壳-Symbol 2577.xml',
                'instanceIndex':index,'symbol':symbol,'baseline':wall['parentBaseline'],
                'baselineSha256':c.sha(original),
                'pivotNative':inverse_point(before,group['parentPivot']),
                'localVisualScale':group['localScale'],
                'assemblyId':'tutorial-wall-'+group['id'],
                'assemblyPivotParent':group['parentPivot'],
                'derivation':'tutorial-wall-source.v1',
                'sourceArt':'flashswf/levels/基地场景合集/LIBRARY/sprite/Symbol 2577.xml',
                'justification':group['basis'],
                'collisionPolicy':'只校准明确墙挂实例；墙体、柜门、地板与碰撞保持原状。'})
    recipe['instances']=[r for r in recipe['instances'] if r.get('derivation') not in
                         ('tutorial-desk-source.v1','tutorial-wall-source.v1')]
    recipe['instances'][1:1]=rows
    return recipe

if __name__=='__main__':
    import argparse
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');args=ap.parse_args()
    result=derive();current=c.read(c.HERE/'recipe.json')
    if args.check:
        if result!=current:raise SystemExit('stale tutorial furniture recipe')
    else:(c.HERE/'recipe.json').write_bytes((json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode('utf8'))
    print('tutorial furniture recipe: twelve registered children')
