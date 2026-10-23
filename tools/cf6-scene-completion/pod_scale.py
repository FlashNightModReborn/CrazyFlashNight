"""Shape-local CF6 pod calibration; leaves chronology and gameplay markers untouched."""
import copy
import math


def about_pivot(matrix, scale, pivot):
    a,b,c,d,x,y=matrix
    return [a*scale,b*scale,c*scale,d*scale,pivot[0]+scale*(x-pivot[0]),pivot[1]+scale*(y-pivot[1])]


def calibrate_frames(nodes, policy):
    source=nodes['1939']['frames']
    if len(source)!=25:raise ValueError('pod chronology changed')
    initial,adult=policy['initialScale'],policy['adultScale']
    pivot=policy['containerPivot']
    if not all(type(v) in (int,float) and math.isfinite(v) and 0<v<=2 for v in (initial,adult)):
        raise ValueError('invalid bounded pod scale')
    if pivot!=[-7,8] or policy['referenceLimb']!=264 or policy['sourceAdultFrame1']!=23:
        raise ValueError('unreviewed pod anchor or adult pose')
    bodies=set(policy['bodyParts']);containers=set(policy['containerParts'])
    if bodies!=set(range(262,275)) or containers!={1901,1933,1934,1935,1936,1937,1938}:
        raise ValueError('unreviewed pod part roles')
    adult_limbs=[r for r in source[22].values() if r['id']==264]
    if len(adult_limbs)!=2:raise ValueError('adult body limb binding changed')
    reference=math.hypot(*adult_limbs[0]['matrix'][:2])
    trajectory=policy['bodyFootTrajectory'];feet=trajectory['sourceFootY']
    if len(feet)!=25 or trajectory['sourceFootFrame1']!=23 or feet[23:]!=[None,None]:
        raise ValueError('unreviewed body foot trajectory')
    if any(type(v) not in (int,float) or not math.isfinite(v) for v in feet[:23]):
        raise ValueError('invalid source body foot')
    if trajectory['bodyPivotX']!=-7 or not math.isfinite(trajectory['targetFootY']):
        raise ValueError('invalid body foot alignment')
    if trajectory['transitionStartFrame1']!=7 or trajectory['transitionEndFrame1']!=23:
        raise ValueError('unreviewed body descent window')
    if any(r['id'] in {1901,1933} for f in source[6:] for r in f.values()):
        raise ValueError('intact base overlaps descent')
    result=copy.deepcopy(source);audit=[]
    for index,(original,frame) in enumerate(zip(source,result)):
        limbs=[r for r in original.values() if r['id']==264]
        has_initial=any(r['id']==1906 for r in original.values())
        has_body=any(r['id'] in bodies for r in original.values())
        if has_initial:
            if index!=0 or has_body:raise ValueError('initial nested body moved')
            scale=initial;growth=None
        elif has_body:
            if len(limbs)!=2:raise ValueError('body growth has no exact reference limbs')
            norms=[math.hypot(*r['matrix'][:2]) for r in limbs]
            if min(norms)<=0 or abs(norms[0]-norms[1])>1e-8:raise ValueError('ambiguous body growth')
            growth=norms[0]/reference;scale=adult/growth
        else:
            scale=None;growth=None
            if index<23:raise ValueError('unexpected empty visible body frame')
        count_body=count_container=0
        body_pivot=[trajectory['bodyPivotX'],feet[index]] if scale is not None else None
        progress=max(0,min(1,(index+1-trajectory['transitionStartFrame1'])/16))
        progress=progress*progress*(3-2*progress)
        target_foot=trajectory['holdFootY']+(trajectory['targetFootY']-trajectory['holdFootY'])*progress if scale is not None else None
        for row in frame.values():
            cid=row['id']
            if cid in bodies or cid==1906:
                row['matrix']=about_pivot(row['matrix'],scale,body_pivot)
                row['matrix'][5]+=target_foot-feet[index];count_body+=1
            elif cid in containers:
                row['matrix']=about_pivot(row['matrix'],initial,pivot);count_container+=1
            elif cid not in {277,359,360,1433}:raise ValueError('unknown pod part role')
        audit.append({'frame1':index+1,'bodyPlacementCount':count_body,'containerPlacementCount':count_container,
            'bodyScale':scale,'containerScale':initial if count_container else None,'sourceBodyGrowth':growth,
            'referenceLimbNormAfter':None if not limbs else math.hypot(*limbs[0]['matrix'][:2])*scale,
            'pivot':pivot,'bodyPivot':body_pivot,'sourceFootY':feet[index],'targetFootY':target_foot,
            'emptySourceTerminal':index>=23})
    return result,audit
