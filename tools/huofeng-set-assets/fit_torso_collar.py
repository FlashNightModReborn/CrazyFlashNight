"""Fit the collar around the native player neck, in torso coordinates."""

# Frozen R2 contour vertices -> fitted native torso coordinates. Repeated
# vertices are shared by the material fills, clipping mask and outlines.
COLLAR = {
    (14.45,-40.55):(-7.5,-91), (18.2,-37.65):(-10,-87),
    (18.2,-27.25):(-11,-77), (21.8,-23.75):(-12,-74),
    (20,-22.2):(-11,-72), (15.85,-18.7):(-6,-68.5),
    (11.25,-16):(1,-67), (7.5,-13.8):(6,-66.5),
    (3.45,-12.1):(10,-67), (2.9,-11.9):(11,-67),
    (-.2,-10.7):(13,-67.5), (-.85,-11.25):(14,-68.5),
    (-.85,-15.85):(13,-72), (1.1,-16.5):(8,-71.5),
    (3,-17.4):(3,-72), (6.85,-19.3):(-3,-73),
    (10.45,-22.25):(-7,-76.5), (7.05,-20.55):(-2,-74.5),
    (3.1,-19.15):(4,-74), (-.4,-18.05):(12.5,-74.5),
    (-.7,-18.3):(12.7,-74.8), (-.9,-18.5):(13,-75),
    (-.9,-25.05):(14,-82.5), (1.35,-25.65):(9,-81.5),
    (3.65,-26.75):(3,-81.5), (7.55,-28.65):(-3,-82.5),
    (11.5,-32.1):(-7,-85.5), (14.25,-33.95):(-8,-86.5),
    (-6.65,-37.05):(17,-89), (-1.6,-40.05):(14.5,-91),
    (-1.6,-31.75):(14.5,-85), (-1.55,-28.65):(14.5,-82.8),
    (-2.2,-28.2):(15,-82.5), (-4.9,-31.35):(16.5,-85.5),
    (-7.9,-21.3):(17.5,-75.5), (-8.55,-22.85):(18,-77.5),
    (-5.35,-25.6):(16.5,-79.5), (-1,-26.95):(14,-83.5),
    (3.8,-28.4):(6,-82.5), (8,-29.95):(-2,-83),
    (-2.3,-12.55):(15.3,-70), (-3.55,-14.2):(16,-72),
    (-6,-17.25):(17,-73),
    (2.9,-11.7):(11,-66.7), (.75,-10):(12.7,-65.5),
    (-3.05,-20.45):(15,-76), (-5.2,-24.35):(16.5,-78.5),
    (14.8,-24.5):(-9,-77),
}

def fit_torso_collar(root,vector):
    changed=0
    def inverse(m):
        a,b,c,d,x,y=m;det=a*d-b*c
        return d/det,-b/det,-c/det,a/det,(c*y-d*x)/det,(b*x-a*y)/det
    def walk(element,parent_matrix=vector.I,equipment=False):
        nonlocal changed
        matrix=vector.mul(parent_matrix,vector.transform(element.get('transform')))
        equipment=equipment or element.get('data-layer')=='equipment'
        if equipment and vector.tag(element)=='path':
            back=inverse(matrix);moved=[False]
            def point(p):
                x,y=vector.point(p,matrix)
                # Preserve the previous strap taper away from the collar.
                weight=max(0.,min(1.,(-45.-y)/10.))
                if weight:
                    x += ((.8*x+4.35)-x)*weight;moved[0]=True
                key=tuple(round(t,6) for t in p)
                if key in COLLAR:
                    x,y=COLLAR[key];moved[0]=True
                return vector.point((x,y),back)
            def pair(p):return ' '.join(vector.fmt(t) for t in point(p))
            paths=[]
            for start,segments,closed in vector.parse_path(element.get('d','')):
                parts=['M '+pair(start)]
                parts.extend(segment[0]+' '+' '.join(pair(p) for p in segment[1:]) for segment in segments)
                if closed:parts.append('Z')
                paths.append(' '.join(parts))
            if moved[0]:element.set('d',' '.join(paths));changed+=1
        for child in element:walk(child,matrix,equipment)
    walk(root)
    if changed!=7:raise ValueError('R2 collar source changed: expected seven fill/mask/outline paths, got '+str(changed))
    return changed
