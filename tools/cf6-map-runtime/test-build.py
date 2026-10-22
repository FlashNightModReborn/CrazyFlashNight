"""Offline asset-contract tests. These do not substitute for AVM1 or visual tests."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from PIL import Image

spec=importlib.util.spec_from_file_location('cf6_map_build',Path(__file__).with_name('build.py'))
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.root=Path(self.tmp.name)
        self.oldroot,self.oldhere=build.ROOT,build.HERE
        build.ROOT=self.root;build.HERE=self.root/'tools/cf6-map-runtime'
        Image.new('RGBA',(80,45),(20,30,40,255)).save(self.root/'background.png')
        self.map={'id':'A01','nativeBounds':[-3.45,-5.85,800,452],'worldScale':1,
            'walkBounds':[10,160,760,440],'spawn':[60,300],
            'exit':{'direction':'右','rect':[730,160,760,440]},'collisions':[],
            'layers':[{'id':'floor','role':'background','sourceKind':'background','png':'background.png',
                'x':-3.45,'y':-5.85,'width':800,'height':452,'depth':1}]}
        self.data={'schema':'cf6-map-input.v1','maps':[self.map]}
    def tearDown(self):
        build.ROOT=self.oldroot;build.HERE=self.oldhere;self.tmp.cleanup()
    def test_native_to_world_once(self):
        self.map['worldScale']=2
        self.assertEqual(build.coordinates(self.map)([-3.45,-5.85]),[0,0])
        self.assertEqual(build.coordinates(self.map)([60,300]),[126.9,611.7])
    def test_valid_background(self):self.assertIs(build.validate(self.data),self.data)
    def test_preview_rejected(self):
        self.map['layers'][0]['sourceKind']='scene-preview'
        with self.assertRaisesRegex(ValueError,'previews'):build.validate(self.data)
    def test_missing_layer_rejected(self):
        self.map['layers'][0]['png']='missing.png'
        with self.assertRaisesRegex(ValueError,'missing'):build.validate(self.data)
    def test_escape_rejected(self):
        self.map['layers'][0]['png']='../background.png'
        with self.assertRaisesRegex(ValueError,'unsafe'):build.validate(self.data)
    def test_output_name_escape_rejected(self):
        self.map['layers'][0]['id']='../unsafe'
        with self.assertRaises(ValueError):build.validate(self.data)
    def test_vehicle_excluded(self):
        self.map['id']='A07'
        with self.assertRaises(ValueError):build.validate(self.data)
    def test_a21_not_a_map(self):
        self.map['id']='A21'
        with self.assertRaises(ValueError):build.validate(self.data)
    def test_duplicate_map(self):
        self.data['maps'].append(copy.deepcopy(self.map))
        with self.assertRaises(ValueError):build.validate(self.data)
    def test_nonfinite_geometry(self):
        self.map['walkBounds'][0]=float('nan')
        with self.assertRaises(ValueError):build.validate(self.data)
    def test_outside_spawn(self):
        self.map['spawn']=[0,0]
        with self.assertRaises(ValueError):build.validate(self.data)
    def test_bad_polygon(self):
        self.map['collisions']=[[[1,2],[3,4]]]
        with self.assertRaises(ValueError):build.validate(self.data)
    def test_spawn_cannot_be_inside_collision(self):
        self.map['collisions']=[[[50,290],[70,290],[70,310],[50,310]]]
        with self.assertRaisesRegex(ValueError,'inside collision'):build.validate(self.data)
    def test_elevator_cannot_be_static(self):
        self.map['id']='A10'
        with self.assertRaisesRegex(ValueError,'flattened'):build.validate(self.data)
    def test_elevator_requires_loop_clip(self):
        self.map['id']='A13';row=copy.deepcopy(self.map['layers'][0]);row['id']='shaft';row['role']='elevator-scroll'
        self.map['layers'].append(row)
        with self.assertRaisesRegex(ValueError,'loopHeight'):build.validate(self.data)
        row.update(loopHeight=541.95,clip=[0,0,600,350]);build.validate(self.data)
    def test_deterministic_recipe_and_fragment(self):
        a=build.build(build.validate(self.data));b=build.build(build.validate(self.data))
        self.assertEqual(a,b)
        self.assertEqual(len(a),3)
        recipe=a[build.HERE/'generated/CF6_A01_BG.jsfl'].decode()
        self.assertIn('fl.createDocument()',recipe)
        self.assertNotIn('.publish(',recipe)
        self.assertNotIn('.testMovie(',recipe)
        self.assertIn('Refusing to overwrite',recipe)
        self.assertEqual(recipe.count('fl.closeDocument(doc, false);'),1)
        self.assertLess(recipe.index('fl.saveDocument(doc,canonicalDocumentURI(target))'),recipe.index('fl.closeDocument(doc, false);'))
        self.assertNotIn('fl.documents',recipe)
        self.assertIn('stop();_root.贴背景图();',recipe)
        self.assertIn('FLfile.platformPathToURI(a.path)',recipe)
        self.assertIn('if (!FLfile.write(receipt',recipe)
        self.assertNotIn('file:///C:',recipe)
        self.assertIn('CF6_NATIVE_IMPORT_STARTED\\n',recipe)
    def test_dynamic_layer_does_not_rebake_background(self):
        row=copy.deepcopy(self.map['layers'][0]);row['id']='foreground';row['role']='foreground';row['sourceKind']='isolated-part'
        self.map['layers'].append(row)
        out=build.build(build.validate(self.data))
        self.assertNotIn('_root.贴背景图()',out[build.HERE/'generated/CF6_A01_foreground.jsfl'].decode())
    def test_no_empty_generation(self):
        self.data['maps']=[]
        with self.assertRaises(ValueError):build.validate(self.data)
    def test_source_mapping_and_attributed_geometry_overlay(self):
        raw={'schema':'cf6-map-input.v1','maps':{'A01':copy.deepcopy(self.map)}}
        result=build.normalize(raw,{'maps':{'A01':{'worldScale':2,'geometryStatus':'prototype','geometryBasis':'explicit fixture'}}})
        self.assertEqual(result['maps'][0]['id'],'A01')
        self.assertEqual(result['maps'][0]['worldScale'],2)
        self.assertEqual(raw['maps']['A01']['worldScale'],1)
        self.assertEqual(result['maps'][0]['geometryStatus'],'prototype')


if __name__=='__main__':unittest.main()
