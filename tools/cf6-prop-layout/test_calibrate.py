import unittest
from pathlib import Path
import calibrate as c

class CalibrationContract(unittest.TestCase):
    def test_field_scale_scopes_and_shared_anchors(self):
        policy=c.read(c.HERE/'scale-policy.json')
        rows=c.read(c.HERE/'recipe.json')['instances']
        self.assertEqual(len(rows),169)
        desks=[r for r in rows if r.get('derivation')=='tutorial-desk-source.v1']
        self.assertEqual({r['instanceIndex'] for r in desks},{2,3,4,5})
        for r in desks:
            self.assertEqual(r['assemblyPivotParent'],[-624.45,4.725])
            self.assertAlmostEqual(r['localVisualScale']*1.383*128/75,1)
        pods=[r for r in rows if r['category']=='cultivation-pod']
        self.assertEqual(len(pods),132)
        for r in pods:
            self.assertAlmostEqual(r['localVisualScale']*128/75,policy['pod']['initialScale'])
        import build_unit_scale
        self.assertEqual(build_unit_scale.TARGET.read_bytes(),build_unit_scale.build())

    def test_wall_fixtures_have_human_scale_without_changing_architecture(self):
        policy=c.read(c.HERE/'scale-policy.json')
        rows=[r for r in c.read(c.HERE/'recipe.json')['instances']
              if r.get('derivation')=='tutorial-wall-source.v1']
        self.assertEqual({r['instanceIndex'] for r in rows},{6,7,8,9,10,12,13,14})
        self.assertFalse({0,1,11,15,16,17,18,19,20,21,22,23} & {r['instanceIndex'] for r in rows})
        scale=policy['tutorialDesk']['sourceRoomScale']*policy['tutorialDesk']['mapScale']
        pixels_per_cm=policy['reference']['relaxedStandingBodyPixels']/175
        fire=next(g for g in policy['tutorialWall']['groups'] if g['id']=='fire-extinguisher')
        self.assertAlmostEqual(fire['bodyNativeHeight']*fire['localScale']*scale/pixels_per_cm,60)
        # Source bottle's handle top -32.35 at placement y=-127.45; floor y=4.725.
        handle_height=(4.725-(-127.45-32.35))*fire['localScale']*scale/pixels_per_cm
        self.assertGreater(handle_height,135)
        self.assertLess(handle_height,150)
        for row in rows:
            if row['assemblyId']=='tutorial-wall-poster-cluster':
                self.assertAlmostEqual(row['localVisualScale']*scale,1)

    def test_sheared_reflected_pivot_and_holder(self):
        for before in [(0.8,0.65,0,0.9,886.6,179.15),(-0.60546875,0,0,0.60546875,151.45,-48),(0,1,-1,0,34,-19)]:
            pivot=(73.25,89.5)
            after=c.about_pivot(before,pivot,75/128)
            self.assertTrue(c.near(c.point(before,pivot),c.point(after,pivot)))
            art=c.holder_matrix([v*128/75 for v in after[:4]],pivot)
            self.assertTrue(c.near(c.point(art,pivot),(0,0)))
    def test_reject_nonfinite_or_nonpositive_scale(self):
        for scale in [0,-1,float('nan'),float('inf')]:
            with self.assertRaises(ValueError):c.about_pivot(c.IDENTITY,(0,0),scale)
    def test_generator_overlay_idempotence_and_unknown_bytes(self):
        recipe=c.read(c.HERE/'recipe.json');originals,full=c.patched_sources(recipe);expected=c.depth_exclusions(full)
        self.assertEqual(c.overlay_outputs(originals),expected)
        self.assertEqual(c.overlay_outputs(full),expected)
        self.assertEqual(c.overlay_outputs(expected),expected)
        path=next(iter(originals))
        with self.assertRaises(ValueError):c.overlay_outputs({path:originals[path]+b' '})
        unrelated=c.ROOT/'tools/cf6-prop-layout/unrelated.xml'
        self.assertEqual(c.overlay_outputs({unrelated:b'unchanged'}),{unrelated:b'unchanged'})
    def test_only_selected_matrices_change(self):
        recipe=c.read(c.HERE/'recipe.json');originals,expected=c.patched_sources(recipe)
        for path,data in expected.items():
            a=c.ET.fromstring(originals[path]);b=c.ET.fromstring(data)
            for root in (a,b):
                for node in root.findall('.//x:Matrix',c.NS):node.attrib.clear()
            self.assertEqual(c.ET.tostring(a),c.ET.tostring(b))
    def test_pod_parts_keep_one_world_pivot(self):
        p=c.HERE/'generated/instance-layout.json'
        groups={}
        for row in c.read(p)['instances']:
            self.assertTrue(c.near(c.point(row['artMatrix'],row['pivotNative']),(0,0)))
            if row.get('assemblyId'):groups.setdefault(row['assemblyId'],[]).append(row)
        for rows in groups.values():
            self.assertGreater(len(rows),1)
            for row in rows:self.assertTrue(c.near(row['worldPivot'],rows[0]['worldPivot']))

    def test_depth_exclusions_and_native_closure(self):
        import build_depth_props as depth
        outputs,groups=depth.generate()
        self.assertEqual(len(groups),2)
        self.assertEqual({g['mapId'] for g in groups},{'A06'})
        for group in groups:
            for file in group['files']:
                path=c.ROOT/file['path']
                self.assertEqual(c.sha(path.read_bytes()),file['sha256'])
            for member in group['excludedBackgroundInstances']:
                path=c.ROOT/member['xflDirectory']/member['parentFile']
                self.assertFalse(any(n.get('libraryItemName')==member['symbol'] for n in c.roots(path.read_bytes())))
            doc=c.ET.fromstring(outputs[(c.ROOT/group['xfl']).parent/'DOMDocument.xml'])
            self.assertEqual(len(doc.findall('.//x:DOMSymbolInstance',c.NS)),len(group['memberIds']))
            profile=c.ET.fromstring(outputs[(c.ROOT/group['xfl']).parent/'PublishSettings.xml'].decode('utf-8'))
            self.assertEqual(profile.findtext('.//PublishFormatProperties/flashFileName'),group['name']+'.swf')
            self.assertEqual(group['layer']['visualScale'],1)
            self.assertEqual(group['layer']['pivot'],{'x':0,'y':0})

if __name__=='__main__':unittest.main()
