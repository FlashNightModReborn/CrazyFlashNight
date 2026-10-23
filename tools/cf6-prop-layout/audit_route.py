"""Compact audit of all twenty enabled backgrounds plus tutorial, without raster production."""
import argparse
from pathlib import Path
import json
import calibrate as c

REVIEW={
 'TUTORIAL':('furniture','高架床与组合书桌按既有人模校准体量恢复；房间壳不缩；门由通行装配共同处理。'),
 'A01':('environment-composite','残骸堆与大门墙面是整体环境边缘，未将残骸外框当单辆车；地板/土面/墙体/灯光保持地图覆盖。运行时独立道具不由此底图工具修改。'),
 'A02':('environment-composite','废车堆、远景工程机械共用背景轮廓与遮罩，透视层级不同；保留废料地形，不套用A08完整赛车的现实长度。'),
 'A03':('architecture','背景仅连续墙纸/地板/壁灯；门框、门叶、人物与mask由通行装配统一变换。'),
 'A04':('architecture','背景仅连续墙纸/地板/壁灯；入口与出口由通行装配分别围绕门槛校准。'),
 'A05':('statue','两尊雕像恢复210.85px；地毯、画框、墙体不缩，金双门另走统一通行变换。'),
 'A06':('statue-and-armor','两尊雕像恢复210.85px并因前后可达迁出为独立原生depth-prop，底图排除；五套盔甲陈列按175cm裸模145.19px定高；建筑窗帘与墙窗/地毯保留。'),
 'A08':('vehicle','整辆赛车包含车轮/车身/枪/遮罩同变换，恢复约390.18px长；道路与墙体不缩。'),
 'A09':('architecture','连续墙/灯/排气口/安全标识与地面；无已识别大型独立家具，保留。'),
 'A10':('elevator-architecture','整套电梯是地面/护栏/外框/移动幕布的通行结构；不能当道具缩小，否则与电梯窗口、移动地面脱离。'),
 'A11':('laboratory','培养舱1901和内部人像1906同pivot校准，舱壳约366.28px，与现役230cm克隆兽相称；三个89px油桶校准；固定电柜与电梯结构保留。'),
 'A12':('architecture','连续墙/排气口/安全标识与地面，无已识别大型独立家具，保留。'),
 'A13':('elevator-architecture','整电梯通行结构保留，活动幕布与站台坐标由电梯业务统一处理。'),
 'A14':('laboratory','十二组培养舱及内部人像同步缩放；六桶堆叠作为整组共享脚点；电梯与地面不缩。'),
 'A15':('laboratory-and-vehicle','二十四组培养舱同步缩放；装甲车体/车头/三车轮五实例按共同接地pivot校准。'),
 'A16':('laboratory','十七组培养舱同步缩放；中心服务器墙柜及地板/墙体保留，不把连墙结构视为独立家具。'),
 'A17':('laboratory','十二组培养舱同步缩放；中心服务器墙柜及地板/墙体保留。'),
 'A18':('architecture','成片墙面、竖灯、狭长门孔、栅格地板；门孔是墙体部分，未独立缩孔留下破洞。'),
 'A19':('architecture','转角墙/竖灯/墙内门孔/栅格地板连续，保留地形与建筑尺度。'),
 'A20':('architecture','连续转角墙/栅格地板/墙内门孔与标志；保持碰撞和建筑接口。'),
 'A22':('architecture','与A20同类的转角墙/地板/门孔，保留；不以末关整景缩放代替局部校准。'),
}

def produce():
    maps=c.read(c.ROOT/'tools/cf6-map-source/generated/map-input.json')['maps'];recipe=c.read(c.HERE/'recipe.json')
    rows=[]
    for mid in ['TUTORIAL']+sorted(maps):
        instances=[i for i in recipe['instances'] if i['mapId']==mid]
        xfl='flashswf/backgrounds/cf6/'+('CF6_Tutorial_BG' if mid=='TUTORIAL' else 'CF6_'+mid+'_BG')
        source='tools/cf6-tutorial/layout.json' if mid=='TUTORIAL' else maps[mid]['layers'][0]['source']['svg']
        kind,decision=REVIEW[mid]
        rows.append({'mapId':mid,'category':kind,'decision':decision,'source':source,'sourceSha256':c.sha((c.ROOT/source).read_bytes()),
                     'calibratedInstances':len(instances),'status':'native-source-calibrated' if instances else 'audited-retained',
                     'changedParentXml':sorted({i['parentFile'] for i in instances}),
                     'xfl':xfl+'/'+Path(xfl).name+'.xfl','swf':xfl+'.swf',
                     'needsFreshCs6':bool(instances),'validationBoundary':'源文件/原图与静态层级审计；未代替实机截图、穿行与人工比例验收。'})
    if len(maps)!=20 or set(REVIEW)!=set(maps)|{'TUTORIAL'}:raise ValueError('route coverage changed')
    depth=c.read(c.HERE/'generated/depth-props-manifest.json')['groups'] if (c.HERE/'generated/depth-props-manifest.json').exists() else []
    return {'depthProps':[{'name':g['name'],'xfl':g['xfl'],'swf':g['swf']} for g in depth],'schema':'cf6-prop-route-audit.v1','enabledMaps':20,'tutorialAdditional':1,'maps':rows,
            'compileTargets':[{'xfl':r['xfl'],'swf':r['swf']} for r in rows if r['needsFreshCs6']]+[{'xfl':g['xfl'],'swf':g['swf']} for g in depth]}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
    path=c.HERE/'generated/route-audit.json';data=(json.dumps(produce(),ensure_ascii=False,indent=2)+'\n').encode()
    if args.check:
        if path.read_bytes()!=data:raise SystemExit('stale route audit')
    else:path.write_bytes(data)
    print('20 backgrounds + tutorial audited; 9 backgrounds plus 2 extracted native prop CS6 targets')
