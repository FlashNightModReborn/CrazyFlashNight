"""Read-only contracts for source motion, equipment and ownership."""
from pathlib import Path
import copy
import json
import math
import subprocess
import tempfile
import unittest
from lxml import etree as E
import elite

ROOT=Path(__file__).resolve().parents[2]
NS=elite.NS


def point(pose, role):
    return pose[elite.DEPTH[role]]['matrix'][4:]


class EliteContracts(unittest.TestCase):
    def test_script_sources_have_utf8_bom(self):
        sources = [
            'tools/cf6-soldier-assets/EliteAI.as',
            'tools/cf6-soldier-assets/SoldierAI.as',
            'scripts/run-cf6-soldier-asset-tests.ps1',
            'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6SoldierAssetTest.as',
            'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootCore.as',
            'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/FireEventComponent.as',
            'scripts/逻辑/单位函数/单位函数_lsy_主角射击函数.as',
        ]
        for source in sources:
            with self.subTest(source=source):
                self.assertEqual((ROOT/source).read_bytes()[:3], b'\xef\xbb\xbf', source)

    def test_fk_bones_scales_and_weapon_contacts(self):
        rig=elite.make_rig();poses=rig.frames();base=rig.reference
        self.assertEqual(len(rig.diagnostics),202)
        self.assertEqual(len(poses),365)
        for index,pose in enumerate(poses):
            for child,parent in elite.elite_anatomy.PARENT.items():
                actual=math.dist(point(pose,child),point(pose,parent))
                self.assertAlmostEqual(actual,rig.target_bone_lengths[child],places=6,
                    msg=(index,child,parent,actual,rig.target_bone_lengths[child]))
            for depth,row in pose.items():
                if depth in (elite.DEPTH['gun'],elite.DEPTH['sidearm']):
                    continue
                a,b,c,d,_,_=row['matrix'];aa,bb,cc,dd,_,_=base[depth]['matrix']
                self.assertAlmostEqual(a*a+b*b,aa*aa+bb*bb,places=8)
                self.assertAlmostEqual(c*c+d*d,cc*cc+dd*dd,places=8)
                self.assertAlmostEqual(abs(a*d-b*c),abs(aa*dd-bb*cc),places=8)
            if index not in rig.diagnostics:
                continue
            # Reload output frames are resampled separately; check each source
            # pose against its own contact solution without retaining rig state.
            pose=rig.pose(index)
            for entry in rig.diagnostics[index]['contacts']:
                side,weapon,grip=entry.split(':')
                desired=elite.elite_anatomy.world(pose[elite.DEPTH[weapon]]['matrix'],
                    rig.target_grip(index,weapon,grip))
                self.assertLess(math.dist(desired,point(pose,side+'Hand')),1e-6,(index,side,weapon,grip))
        self.assertLess(rig.source[20]['backHand'][4],0)
        self.assertGreater(rig.source[20]['frontHand'][4],0)
        self.assertEqual(rig.diagnostics[20]['contacts'],['front:sidearm:front','back:gun:front'])

    def test_source_motion_and_sidearm_coverage(self):
        profile=elite.load_profile();poses=elite.retarget_frames()
        self.assertEqual(profile['sourceBindFrame'],53)
        self.assertEqual(profile['sidearmBindFrame'],22)
        retreat=profile['actions']['retreat']
        retreat_frames=set(range(retreat['first']-1,retreat['last']))
        for name,action in profile['actions'].items():
            frames=list(range(action['first']-1,action['last']))
            unique={json.dumps(poses[index],sort_keys=True) for index in frames}
            if name not in ('run','slide'):
                self.assertGreater(len(unique),{'stand':10,'retreat':20,'reload':8}[name],name)
            for index in range(295):
                has_sidearm=elite.DEPTH['sidearm'] in poses[index]
                self.assertEqual(has_sidearm,index in retreat_frames,(name,index,has_sidearm))
        self.assertEqual([event['frame'] for event in profile['actions']['stand']['fireEvents']], [54,58,62,66,70])
        self.assertEqual([event['frame'] for event in profile['actions']['retreat']['fireEvents']],
            [21,22,27,28,33,34,39,40])
        # R12 split the former 166-248 action into ordinary running fire and
        # the smoke-only slide. Keep the original full-range motion coverage.
        run=profile['actions']['run'];slide=profile['actions']['slide']
        self.assertEqual((run['first'],run['last'],slide['first'],slide['entryFrame'],slide['last']),
                         (166,205,206,212,248))
        combined={json.dumps(poses[index],sort_keys=True) for index in range(165,248)}
        self.assertGreater(len(combined),40)
        self.assertEqual([e['frame'] for e in run['fireEvents']],list(range(174,203,4)))
        self.assertEqual([e['frame'] for e in slide['fireEvents']],list(range(212,229,4)))
        self.assertIn('fireEvents',elite.as2_literal(profile))
        self.assertTrue(all(poses[index][elite.DEPTH['gun']]['id']=='primaryPistol' for index in retreat_frames))
        self.assertTrue(all(poses[index][elite.DEPTH['gun']]['id']=='reloadPistol' for index in range(295,365)))
        for pose in poses[330:365]:
            for side,weapon in [('front','gun'),('back','sidearm')]:
                self.assertLess(math.dist(point(pose,side+'Hand'),point(pose,weapon)),1e-6)
            self.assertGreater(math.dist(point(pose,'gun'),point(pose,'sidearm')),25)

    def test_pair_reload_keeps_body_stable_and_hands_simultaneous(self):
        poses=elite.retarget_frames()[330:365]
        self.assertEqual(len(poses),35)
        for role in ('pelvis','torso','head','frontThigh','frontShin','frontFoot','backThigh','backShin','backFoot'):
            values=[pose[elite.DEPTH[role]]['matrix'] for pose in poses]
            self.assertTrue(all(m==values[0] for m in values),role)
        for weapon in ('gun','sidearm'):
            self.assertGreater(math.dist(point(poses[0],weapon),point(poses[17],weapon)),3)
            self.assertLess(math.dist(point(poses[0],weapon),point(poses[-1],weapon)),1e-6)

    def test_mirrored_art_sockets_remain_attached(self):
        rig=elite.make_rig()
        # Check the visible part's transformed joint, not only the synthetic
        # point distances. Mirroring an arm used to leave its painted wrist
        # pointing away from the hand while the old bone-length test passed.
        for index,pose in enumerate(rig.frames()):
            if index not in rig.diagnostics:continue
            for role,child in elite.elite_anatomy.CHILD.items():
                if role in ('pelvis','torso'):continue
                socket=elite.elite_anatomy.local(rig.reference[elite.DEPTH[role]]['matrix'],rig.target_points[child])
                actual=elite.elite_anatomy.world(pose[elite.DEPTH[role]]['matrix'],socket)
                self.assertLess(math.dist(actual,point(pose,child)),1e-6,(index+1,role,child))

    def test_turning_reference_keeps_elbows_and_slide_leg_shape(self):
        rig=elite.make_rig()
        # Frame 21 changes the display order of the two identical SARM symbols.
        self.assertGreater(rig.source[20]['frontFore'][4],-10)
        self.assertLess(rig.source[20]['backFore'][4],-70)
        for frame in (21,25,33,174,182,210,218,230):
            pose=rig.pose(frame-1)
            for side in ('front','back'):
                for parent,child in (('Thigh','Shin'),('Shin','Foot')):
                    src=elite.elite_anatomy.subtract(rig.source[frame-1][side+child][4:],rig.source[frame-1][side+parent][4:])
                    dst=elite.elite_anatomy.subtract(point(pose,side+child),point(pose,side+parent))
                    self.assertAlmostEqual(sum(a*b for a,b in zip(elite.elite_anatomy.unit(src),elite.elite_anatomy.unit(dst))),1,places=8)

    def test_review_contact_sheet_executes(self):
        import render_elite_review
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)
            for name,color in [('46.png','#ff0000'),('21.png','#00ff00')]:
                render_elite_review.Image.new('RGB',(40,60),color).save(source/name)
            output=Path(directory)/'contact.png'
            render_elite_review.contact_sheet('contact',[source/'46.png',source/'21.png'],output)
            with render_elite_review.Image.open(output) as image:
                self.assertEqual(image.size,(1600,155))

    def test_panels_and_explicit_sidearm_module(self):
        units=json.loads((ROOT/'data/units/units.json').read_text(encoding='utf-8-sig'))
        tuning=json.loads((Path(__file__).parent/'elite-tuning.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(tuning['inheritedPanelExcept'],['韧性系数'])
        self.assertIn(tuning['toughnessCoefficient'],range(50,101))
        self.assertEqual(tuning['sidearmModule']['item'],'FR506')
        self.assertEqual(len({u['id'] for u in units}),len(units))
        properties=E.parse(str(ROOT/'data/enemy_properties/CF6重制敌人.xml'))
        for old,new in ((466,478),(467,479)):
            base=next(u for u in units if u['id']==old)
            derived=next(u for u in units if u['id']==new)
            for key in ('level','height','is_hostile'):
                self.assertEqual(base[key],derived[key],key)
            expected=copy.deepcopy(base['data']);expected['secondary']=expected['secondary2']='FR506'
            self.assertEqual(derived['data'],expected)
            a=copy.deepcopy(properties.getroot().find(base['spritename']))
            b=copy.deepcopy(properties.getroot().find(derived['spritename']))
            a.tag=b.tag='unit';a.tail=b.tail=None
            a.find('displayname').text=b.find('displayname').text='name'
            self.assertEqual(float(b.find('韧性系数').text),tuning['toughnessCoefficient'])
            self.assertEqual(float(a.find('韧性系数').text),5)
            b.find('韧性系数').text=a.find('韧性系数').text
            self.assertEqual(E.tostring(a),E.tostring(b))

    def test_shared_reactions_and_receivers_with_separate_attacks(self):
        owner=ROOT/'flashswf/arts/new/Codex特种兵素材/LIBRARY'
        for source,derived in zip(('敌人-CF6特种兵','敌人-CF6持盾特种兵'),elite.LINKAGES):
            name='flashswf/arts/new/Codex特种兵素材/LIBRARY/Codex/特种兵/'+source+'.xml'
            a=E.parse(str(owner/('Codex/特种兵/'+source+'.xml')))
            b=E.parse(str(owner/('Codex/特种兵/'+derived+'.xml')))
            receiver='.//x:DOMLayer[@name="受击包围盒"]'
            self.assertEqual(E.tostring(a.find(receiver,NS)),E.tostring(b.find(receiver,NS)))
            for frame in a.findall('.//x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame',NS):
                index=frame.get('index')
                if index in ('41','180'):continue
                other=b.find('.//x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame[@index="'+index+'"]',NS)
                self.assertEqual(E.tostring(frame),E.tostring(other),'ordinary appearance state '+index)
            for index in ('130','140','160','190','194','202'):
                frame='.//x:DOMLayer[@name="动作"]/x:frames/x:DOMFrame[@index="'+index+'"]'
                self.assertEqual(E.tostring(a.find(frame,NS)),E.tostring(b.find(frame,NS)))

    def test_legacy_art_cannot_execute_legacy_combat(self):
        library=ROOT/'flashswf/arts/new/Codex特种兵素材/LIBRARY'
        self.assertFalse(list((library/'Codex/特种兵/精英/原生').rglob('*.xml')))
        action=E.parse(str(library/'Codex/特种兵/精英/动作/CF6战术长枪.xml'))
        refs={x.get('libraryItemName') for x in action.findall('.//x:DOMSymbolInstance',NS)}
        self.assertTrue(all(x.startswith('Codex/特种兵/分件/') or x.startswith('Codex/特种兵/武器/')
            or x.startswith('Codex/特种兵/精英/武器/')
            or x=='Codex/特种兵/装备/腿挂匕首' for x in refs))
        knife=E.parse(str(library/'Codex/特种兵/装备/腿挂匕首.xml'))
        self.assertEqual({x.get('libraryItemName') for x in knife.findall('.//x:DOMSymbolInstance',NS)},
                         {'Codex/特种兵/分件/484'})
        self.assertNotIn('FR-506 12.7MM',refs)
        root=E.parse(str(library/'Codex/特种兵/敌人-CF6特种精英.xml'))
        text='\n'.join(s.text or '' for s in root.findall('.//x:script',NS))
        self.assertNotIn('空手攻击力 * 2.5',text)
        self.assertNotIn('空手攻击力 * 5',text)
        self.assertNotIn('刚体=true',text)
        self.assertIn('清理射击任务(this,true)',text)
        self.assertIn('手枪射击=function',text)
        self.assertIn('初始化混合双枪',text)
        self.assertIn('手枪2射击=function',text)
        self.assertIn('eliteMotionConfig',text)


if __name__=='__main__':
    unittest.main()
