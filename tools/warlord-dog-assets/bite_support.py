"""Attack-only braced stance with four planted paws and rigid limb segments.

The delivered FK retarget follows source angles but only aligns the lowest paw.
Flatten the body trajectory as a connected assembly, then solve all four legs
back to their stance contacts. Retain head motion and limit the long-muzzle jaw's
relative rotation so the mouth does not inherit the old drawing's excessive gape.
"""
import copy
import math


def rotate(v, angle):
    c, s = math.cos(angle), math.sin(angle)
    return (c*v[0]-s*v[1], s*v[0]+c*v[1])


def matrix(angle, scale, origin):
    c, s = math.cos(angle)*scale, math.sin(angle)*scale
    return [c, s, -s, c, *origin]


def solve_leg(rows, bind, depths, toe, ankle_angle):
    upper, middle, lower, paw = depths
    hip = rows[upper]['matrix'][4:]
    origins = [bind[d]['matrix'][4:] for d in depths]
    vectors = [(b[0]-a[0], b[1]-a[1]) for a, b in zip(origins, origins[1:])]
    distal = rotate(vectors[2], ankle_angle)
    ankle = (toe[0]-distal[0], toe[1]-distal[1])
    dx, dy = ankle[0]-hip[0], ankle[1]-hip[1]
    distance = math.hypot(dx, dy)
    l1, l2 = [math.hypot(*v) for v in vectors[:2]]
    if not abs(l1-l2) < distance < l1+l2:
        raise ValueError(f'Unreachable planted foot at {toe}, length={distance}, reach={l1+l2}')
    along = (l1*l1-l2*l2+distance*distance)/(2*distance)
    height = math.sqrt(max(0, l1*l1-along*along))
    ux, uy = dx/distance, dy/distance
    # Select the bend that follows these delivered limb drawings' silhouette.
    choices = [(hip[0]+along*ux-sign*height*uy,
                hip[1]+along*uy+sign*height*ux) for sign in (-1, 1)]
    knee = min(choices, key=lambda p: p[0])
    angles = [math.atan2(knee[1]-hip[1], knee[0]-hip[0])-math.atan2(vectors[0][1], vectors[0][0]),
              math.atan2(ankle[1]-knee[1], ankle[0]-knee[0])-math.atan2(vectors[1][1], vectors[1][0]),
              ankle_angle, 0]
    for depth, origin, angle in zip(depths, (hip, knee, ankle, toe), angles):
        scale = math.hypot(*rows[depth]['matrix'][:2])
        rows[depth]['matrix'] = matrix(angle, scale, origin)


def apply(rig, settings):
    """Return a corrected copy; never alter the immutable delivered rig."""
    result = copy.deepcopy(rig)
    attack = result['sequences']['attack']
    bind = {p['depth']:p for p in attack['frames'][0]['placements']}
    for frame in attack['frames']:
        number = frame['frame']
        phase = next((p for p in settings['phases'] if p['first'] <= number <= p['last']), None)
        if phase is None:
            continue
        rows = {p['depth']:p for p in frame['placements']}
        torso = rows[settings['bodyDepth']]['matrix']
        pivot = torso[4:]
        delta = math.radians(phase['bodyDegrees'])-math.atan2(torso[1], torso[0])
        base = bind[settings['bodyDepth']]['matrix'][4:]
        origin = [a+b for a,b in zip(base,phase['bodyOffset'])]
        # Move armor, neck, head and all four limb roots together. Moving just a
        # shoulder downward would disconnect the short far foreleg from its body.
        for part in frame['placements']:
            m = part['matrix']
            offset = rotate((m[4]-pivot[0],m[5]-pivot[1]),delta)
            part['matrix'] = matrix(math.atan2(m[1],m[0])+delta,
                math.hypot(*m[:2]),(origin[0]+offset[0],origin[1]+offset[1]))
        for leg in settings['legs']:
            depths = leg['depths']
            solve_leg(rows,bind,depths,bind[depths[3]]['matrix'][4:],
                math.radians(leg['ankleDegrees']))
            rows[depths[3]]['matrix'] = list(bind[depths[3]]['matrix'])
        head,jaw = (rows[d]['matrix'] for d in (230,235))
        head_angle = math.atan2(head[1],head[0])
        relative = math.atan2(jaw[1],jaw[0])-head_angle
        minimum,maximum = map(math.radians,settings['jawRelativeDegrees'])
        relative = max(minimum,min(maximum,relative))
        rows[235]['matrix'] = matrix(head_angle+relative,math.hypot(*jaw[:2]),jaw[4:])
    return result
