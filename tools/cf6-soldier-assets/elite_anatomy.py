import copy
import math
import itertools


PARENT = {
    'torso': 'pelvis', 'head': 'torso',
    'backUpper': 'torso', 'backFore': 'backUpper', 'backHand': 'backFore',
    'frontUpper': 'torso', 'frontFore': 'frontUpper', 'frontHand': 'frontFore',
    'backThigh': 'pelvis', 'backShin': 'backThigh', 'backFoot': 'backShin',
    'frontThigh': 'pelvis', 'frontShin': 'frontThigh', 'frontFoot': 'frontShin'
}
CHILD = {
    'pelvis': 'torso', 'torso': 'head',
    'backUpper': 'backFore', 'backFore': 'backHand',
    'frontUpper': 'frontFore', 'frontFore': 'frontHand',
    'backThigh': 'backShin', 'backShin': 'backFoot',
    'frontThigh': 'frontShin', 'frontShin': 'frontFoot'
}
FREE_ROLES = ('knife', 'gun', 'sidearm')
BODY_ROLES = tuple(['pelvis', 'torso', 'head'] + [
    side + part for side in ('back', 'front')
    for part in ('Upper', 'Fore', 'Hand', 'Thigh', 'Shin', 'Foot')
])


def rotate(angle, point):
    c, s = math.cos(angle), math.sin(angle)
    return c*point[0]-s*point[1], s*point[0]+c*point[1]


def add(a, b):
    return a[0]+b[0], a[1]+b[1]


def subtract(a, b):
    return a[0]-b[0], a[1]-b[1]


def multiply(value, point):
    return value*point[0], value*point[1]


def magnitude(point):
    return math.hypot(*point)


def direction(point):
    return math.atan2(point[1], point[0])


def unit(point):
    length = magnitude(point)
    if length < 1e-9:
        return 1.0, 0.0
    return point[0]/length, point[1]/length


def matrix_angle(matrix):
    return math.atan2(matrix[1], matrix[0])


def matrix_det(matrix):
    return matrix[0]*matrix[3]-matrix[1]*matrix[2]


def matrix_delta(current, bind):
    determinant = matrix_det(bind)
    if abs(determinant) < 1e-12:
        raise ValueError('Singular bind matrix')
    current_angle = matrix_angle(current)+(math.pi if matrix_det(current) < 0 else 0)
    bind_angle = matrix_angle(bind)+(math.pi if determinant < 0 else 0)
    angle = wrap(current_angle-bind_angle)
    mirror = matrix_det(current)*determinant < 0
    return angle, mirror


def wrap(value):
    return (value+math.pi)%(2*math.pi)-math.pi


def near(value, reference):
    return reference+wrap(value-reference)


def ease(value):
    value = max(0.0, min(1.0, value))
    return value*value*(3-2*value)


def world(matrix, point):
    a, b, c, d, x, y = matrix
    return a*point[0]+c*point[1]+x, b*point[0]+d*point[1]+y


def local(matrix, point):
    a, b, c, d, x, y = matrix
    dx, dy = point[0]-x, point[1]-y
    det = matrix_det(matrix)
    if abs(det) < 1e-12:
        raise ValueError('Singular placement matrix')
    return (d*dx-c*dy)/det, (-b*dx+a*dy)/det


def two_bone(start, end, upper, lower, current):
    vector = subtract(end, start)
    distance = magnitude(vector)
    ux, uy = unit(vector)
    reachable = min(upper+lower-1e-6, max(abs(upper-lower)+1e-6, distance))
    adjusted = start[0]+ux*reachable, start[1]+uy*reachable
    along = (upper*upper-lower*lower+reachable*reachable)/(2*reachable)
    height = math.sqrt(max(0.0, upper*upper-along*along))
    candidates = [
        (start[0]+ux*along-uy*height, start[1]+uy*along+ux*height),
        (start[0]+ux*along+uy*height, start[1]+uy*along-ux*height)
    ]
    elbow = min(candidates, key=lambda point: math.dist(point, current))
    return elbow, adjusted


class Cf6Rig:
    def __init__(self, reference, depths, order, source, profile, references, assets):
        self.reference = reference
        self.depths = depths
        self.order = order
        self.source = source
        self.profile = profile
        self.references = references
        self.assets = assets
        self.resolve_source_roles()
        self.bind_index = profile['sourceBindFrame']-1
        self.bind = source[self.bind_index]
        self.sidearm_bind = source[profile['sidearmBindFrame']-1]
        self.weapon_bind = dict(self.bind)
        self.weapon_bind['sidearm'] = self.sidearm_bind['sidearm']
        self.diagnostics = {}
        self.active_index = None
        self.pistol_reference = None
        self.pistol_grips = None
        self.force_pistol = False
        self.part_deltas = {}
        self.target_points = {role: self.point(role) for role in depths}
        self.target_angles = {role: matrix_angle(reference[depths[role]]['matrix']) for role in depths}
        self.target_bone_lengths = {}
        ratios = []
        for role, parent in PARENT.items():
            source_length = math.dist(self.bind[role][4:], self.bind[parent][4:])
            target_length = math.dist(self.target_points[role], self.target_points[parent])
            self.target_bone_lengths[role] = target_length
            if source_length > 1e-6 and target_length > 1e-6:
                ratios.append(target_length/source_length)
        ratios.sort()
        self.scale = ratios[len(ratios)//2]
        if not 0.25 < self.scale < 4:
            raise ValueError('Invalid source/target proportion ratio: '+str(self.scale))
        self.ground = self.sole(reference)
        self.source_ground = max(self.bind[role][5] for role in ('backFoot', 'frontFoot'))
        self.source_grips = {'gun': {}, 'sidearm': {}}
        self.target_grips = {'gun': {}, 'sidearm': {}}
        for weapon in ('gun', 'sidearm'):
            bind = self.bind if weapon == 'gun' else self.sidearm_bind
            for side in ('front', 'back'):
                hand = bind[side+'Hand'] if weapon == 'gun' else bind['__instances'][side+'Hand'][0]
                self.source_grips[weapon][side] = local(bind[weapon], hand[4:])
                self.target_grips[weapon][side] = local(
                    reference[depths[weapon]]['matrix'], self.target_points[side+'Hand'])
        self.prepare_deltas()

    def resolve_source_roles(self):
        bind=copy.deepcopy(self.source[self.profile['sourceBindFrame']-1])
        for source in self.source.values():
            for child,parent in [('Fore','Upper'),('Hand','Fore'),('Shin','Thigh'),('Foot','Shin')]:
                roles=[side+child for side in ('front','back')]
                candidates=list(dict.fromkeys(row for role in roles for row in source['__instances'][role]))
                targets=[]
                for side in ('front','back'):
                    socket=local(bind[side+parent],bind[side+child][4:])
                    targets.append(world(source[side+parent],socket))
                best=min(itertools.permutations(candidates,2),key=lambda pair:sum(math.dist(target,row[4:])**2 for target,row in zip(targets,pair)))
                for role,row in zip(roles,best):source[role]=row


    def point(self, role, frame=None):
        frame = frame or self.reference
        return tuple(frame[self.depths[role]]['matrix'][4:])

    def prepare_deltas(self):
        self.part_mirrors = {}
        for action in self.profile['actions'].values():
            previous_parts = {}
            for index in range(action['first']-1, action['last']):
                pose = self.source[index]
                for role in self.depths:
                    if role not in pose:
                        continue
                    value, mirror = matrix_delta(pose[role], self.weapon_bind.get(role, self.bind[role]))
                    if role in previous_parts:
                        value = near(value, previous_parts[role])
                    previous_parts[role] = value
                    self.part_deltas[index, role] = value
                    self.part_mirrors[index, role] = mirror

    def action_at(self, index):
        for name, action in self.profile['actions'].items():
            if action['first']-1 <= index < action['last']:
                return name, action
        return None, None

    def base_pose(self,index):
        self.active_index = index
        source=self.source[index]
        positions={};deltas={};mirrors={}
        positions['pelvis']=add(self.target_points['pelvis'],multiply(self.scale,
            subtract(source['pelvis'][4:],self.bind['pelvis'][4:])))
        for role in self.depths:
            deltas[role]=self.part_deltas.get((index,role),0)
            mirrors[role]=self.part_mirrors.get((index,role),False)
        # Anatomical segment direction is already in world space. A flipped
        # drawing does not reverse the shoulder->elbow or hip->knee vector.
        for role,child in CHILD.items():
            if role in ('pelvis','torso'):continue
            vector=subtract(self.target_points[child],self.target_points[role])
            if mirrors[role]:
                # Reflect in the part's own basis, then align its socket axis.
                socket=rotate(-self.target_angles[role],vector)
                vector=rotate(self.target_angles[role],(-socket[0],socket[1]))
            desired=subtract(source[child][4:],source[role][4:])
            deltas[role]=direction(desired)-direction(vector)
        for role,parent in PARENT.items():
            vector=subtract(self.target_points[role],self.target_points[parent])
            if mirrors[parent]:
                socket=rotate(-self.target_angles[parent],vector)
                vector=rotate(self.target_angles[parent],(-socket[0],socket[1]))
            positions[role]=add(positions[parent],rotate(deltas[parent],vector))
        for role in FREE_ROLES:
            positions[role]=self.target_points[role]
        rows=self.rows_for(positions,deltas,mirrors)
        contacts=self.source_contacts(index) if self.action_at(index)[1]['weaponMode']=='dual' else [
            (side,'gun',side) for side in ('front','back') if self.contact(index,side)]
        for role in ('gun','sidearm'):
            contact=next((x for x in contacts if x[1]==role and x[2]=='front'),None)
            if contact is None:contact=next((x for x in contacts if x[1]==role),None)
            side,_,grip=contact or ('back',role,'front')
            point=world((*rows[self.depths[role]]['matrix'][:4],0,0),self.target_grip(index,role,grip))
            if contact is None and role == 'sidearm':
                source_grip = world(source[role], self.source_grips[role]['front'])
                grip_position = add(positions['pelvis'], multiply(self.scale,
                    subtract(source_grip, source['pelvis'][4:])))
            else:
                grip_position = positions[side+'Hand']
            positions[role]=subtract(grip_position,point)
        pelvis_matrix=rows[self.depths['pelvis']]['matrix']
        knife_offset=local(self.reference[self.depths['pelvis']]['matrix'],self.target_points['knife'])
        positions['knife']=world(pelvis_matrix,knife_offset)
        return positions,deltas,mirrors


    def placement(self, role, point, delta, mirror, rows):
        row = copy.deepcopy(self.reference[self.depths[role]])
        if role == 'gun' and self.pistol_reference is not None and (self.force_pistol or self.is_dual(self.active_index)):
            row = copy.deepcopy(self.pistol_reference)
        a, b, c, d, _, _ = row['matrix']
        if mirror:
            a, b = -a, -b
        a, b = rotate(delta, (a, b))
        c, d = rotate(delta, (c, d))
        row['matrix'] = [a, b, c, d, *point]
        rows[self.depths[role]] = row

    def is_dual(self, index):
        if index is None:
            return False
        _, action = self.action_at(index)
        return action is not None and action['weaponMode'] == 'dual'

    def target_grip(self, index, weapon, grip):
        if weapon == 'gun' and self.pistol_grips is not None and (self.force_pistol or self.is_dual(index)):
            return self.pistol_grips[grip]
        return self.target_grips[weapon][grip]

    def rows_for(self, positions, deltas, mirrors):
        rows = {}
        for role in self.order:
            if role in positions:
                self.placement(role, positions[role], deltas[role], mirrors[role], rows)
        return rows

    def sole(self, frame):
        values = []
        for role in ('backFoot', 'frontFoot'):
            row = frame[self.depths[role]]
            x, y, w, h = self.assets[496]['viewBox']
            values.extend(world(row['matrix'], (px, y+h))[1] for px in (x, x+w))
        return max(values)

    def body_bottom(self, rows):
        values = []
        for role in BODY_ROLES:
            row = rows[self.depths[role]]
            x, y, w, h = self.assets[row['id']]['viewBox']
            values.extend(world(row['matrix'], (px, py))[1]
                for px in (x, x+w) for py in (y, y+h))
        return max(values)


    def ground_pose(self, index, positions, deltas, mirrors):
        rows = self.rows_for(positions, deltas, mirrors)
        source = self.source[index]
        source_lowest = max(source[role][5] for role in ('backFoot', 'frontFoot'))
        airborne = source_lowest < self.source_ground-12
        foot_shift = 0.0 if airborne else self.ground-self.sole(rows)
        body_shift = self.ground+3-self.body_bottom(rows)
        shift = min(foot_shift, body_shift)
        if abs(shift) > 1e-9:
            for role in positions:
                positions[role] = positions[role][0], positions[role][1]+shift
        return shift

    def contact(self, index, side):
        source = self.source[index]
        desired = world(source['gun'], self.source_grips['gun'][side])
        return math.dist(desired, source[side+'Hand'][4:]) < 20

    def source_contacts(self, index):
        source = self.source[index]
        options = {}
        for side in ('front', 'back'):
            options[side] = [None]
            for weapon in ('gun', 'sidearm'):
                if weapon not in source:
                    continue
                for grip in ('front', 'back'):
                    desired = world(source[weapon], self.source_grips[weapon][grip])
                    error = math.dist(desired, source[side+'Hand'][4:])
                    if error < (20 if weapon == 'gun' else 8):
                        options[side].append((side, weapon, grip, error))
        candidates = []
        for front in options['front']:
            for back in options['back']:
                contacts = [entry for entry in (front, back) if entry]
                if len({(entry[1], entry[2]) for entry in contacts}) < len(contacts):
                    continue
                candidates.append((len(contacts), -sum(entry[3] for entry in contacts), contacts))
        return [entry[:3] for entry in max(candidates, key=lambda candidate: (candidate[0], candidate[1]))[2]]

    def apply_arm_contact(self, side, weapon, grip, positions, deltas, mirrors, rows):
        gun_depth = self.depths[weapon]
        desired = world(rows[gun_depth]['matrix'], self.target_grip(self.active_index,weapon,grip))
        upper_role, fore_role, hand_role = side+'Upper', side+'Fore', side+'Hand'
        upper_length = math.dist(self.target_points[fore_role], self.target_points[upper_role])
        lower_length = math.dist(self.target_points[hand_role], self.target_points[fore_role])
        elbow, adjusted = two_bone(positions[upper_role], desired,
            upper_length, lower_length, positions[fore_role])
        correction = subtract(adjusted, desired)
        if magnitude(correction) > 1e-6:
            positions[weapon] = add(positions[weapon], correction)
            gun = rows[gun_depth]
            gun['matrix'][4] += correction[0]
            gun['matrix'][5] += correction[1]
        positions[fore_role] = elbow
        positions[hand_role] = adjusted
        deltas[upper_role] = self.segment_delta(upper_role, subtract(elbow, positions[upper_role]), mirrors[upper_role])
        deltas[fore_role] = self.segment_delta(fore_role, subtract(adjusted, elbow), mirrors[fore_role])
        rows = self.rows_for(positions, deltas, mirrors)
        return math.dist(adjusted, desired), rows

    def segment_delta(self,role,desired,mirror):
        vector=subtract(self.target_points[CHILD[role]],self.target_points[role])
        if mirror:
            socket=rotate(-self.target_angles[role],vector)
            vector=rotate(self.target_angles[role],(-socket[0],socket[1]))
        return direction(desired)-direction(vector)


    def pose(self,index,force_pistol=False):
        self.force_pistol = force_pistol
        name,action=self.action_at(index)
        positions,deltas,mirrors=self.base_pose(index)
        shift=self.ground_pose(index,positions,deltas,mirrors)
        rows=self.rows_for(positions,deltas,mirrors)
        contacts=self.source_contacts(index) if action['weaponMode']=='dual' else [
            (side,'gun',side) for side in ('front','back') if self.contact(index,side)]
        for _ in range(6):
            for side,weapon,grip in contacts:
                _,rows=self.apply_arm_contact(side,weapon,grip,positions,deltas,mirrors,rows)
        self.diagnostics[index]={'sourceFrame':index+1, 'action':name,
            'contacts':[':'.join(x) for x in contacts], 'groundShift':shift,
            'maximumGripError':max((math.dist(positions[side+'Hand'],
                world(rows[self.depths[weapon]]['matrix'],self.target_grip(index,weapon,grip)))
                for side,weapon,grip in contacts),default=0.0), 'scale':self.scale}
        return rows


    def pair_reload_pose(self,index,offset,cycle):
        self.force_pistol=True
        # Own neutral skeleton: feet, pelvis and shoulders never inherit the
        # donor reload's twisting or stepping. Only the two arms move together.
        positions=copy.deepcopy(self.target_points)
        deltas={role:0 for role in positions}
        mirrors={role:False for role in positions}
        pulse=math.sin(math.pi*offset/34)
        for side,weapon,x,y in [('front','gun',24,-25),('back','sidearm',-17,-28)]:
            desired=add(positions['pelvis'],(x-3*pulse,y+9*pulse))
            upper,fore,hand=side+'Upper',side+'Fore',side+'Hand'
            elbow,wrist=two_bone(positions[upper],desired,self.target_bone_lengths[fore],
                self.target_bone_lengths[hand],positions[fore])
            positions[fore]=elbow;positions[hand]=wrist;positions[weapon]=wrist
            deltas[upper]=self.segment_delta(upper,subtract(elbow,positions[upper]),mirrors[upper])
            deltas[fore]=self.segment_delta(fore,subtract(wrist,elbow),mirrors[fore])
        rows=self.rows_for(positions,deltas,mirrors)
        for weapon,extra in [('gun',0),('sidearm',0.12)]:
            angle=-0.25+0.4*pulse+extra
            rows[self.depths[weapon]]['matrix']=[math.cos(angle),math.sin(angle),-math.sin(angle),math.cos(angle),*positions[weapon]]
        rows[self.depths['gun']]['id']='reloadPistol'
        return rows

    def frames(self):
        frames = []
        for index in range(295):
            name, action = self.action_at(index)
            rows = self.pose(index) if action is not None else copy.deepcopy(self.reference)
            if action is None or action['weaponMode'] != 'dual':
                rows.pop(self.depths['sidearm'], None)
            frames.append(rows)
        reload_action = self.profile['actions']['reload']
        for offset in range(35):
            source_index = reload_action['first']-1+round(offset*(reload_action['last']-reload_action['first'])/34)
            rifle = self.pose(source_index)
            rifle.pop(self.depths['sidearm'],None)
            frames[260+offset] = rifle
            pistol = self.pose(source_index,force_pistol=True)
            pistol.pop(self.depths['sidearm'],None)
            pistol[self.depths['gun']]['id'] = 'reloadPistol'
            frames.append(pistol)
        for offset in range(35):
            frames.append(self.pair_reload_pose(None,offset,0))
        self.force_pistol = False
        return frames


def build_frames(reference, depths, order, source, profile, references, assets):
    return Cf6Rig(reference, depths, order, source, profile, references, assets).frames()
