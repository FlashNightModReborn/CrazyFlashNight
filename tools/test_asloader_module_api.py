import unittest
import importlib.util
from pathlib import Path
import tempfile
from asloader_module_api import declaration
spec=importlib.util.spec_from_file_location('asloader_build',Path(__file__).with_name('build-asloader-modules.py'))
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)

class ModuleApiTests(unittest.TestCase):
    def test_retains_contract_and_removes_implementations(self):
        source='''import p.Base;
class p.Child extends Base implements p.Interface {
    public static var count:Number=call(1,2);
    private var nested:Array=[{v:"} // not a comment"}], other:Number=7;
    function Child(arg:Object) { this.nested=arg; }
    public function read(x:String):Object { var fn:Function=function(){return "{";}; return fn(); }
}'''
        api=declaration(source,'p.Child')
        self.assertIn('intrinsic class p.Child extends Base implements p.Interface',api)
        self.assertIn('public static var count:Number;',api)
        self.assertIn('private var nested:Array, other:Number;',api)
        self.assertIn('function Child(arg:Object) ;',api)
        self.assertIn('public function read(x:String):Object ;',api)
        self.assertNotIn('return fn',api)

    def test_interface_is_not_replaced_by_empty_implementation(self):
        api=declaration('interface p.I { function run(x:Number):Void; }','p.I')
        self.assertIn('interface p.I',api)
        self.assertIn('function run(x:Number):Void;',api)
        self.assertNotIn('intrinsic interface',api)

    def test_accessor_and_literal_comment_tokens(self):
        api=declaration('class p.A { var x:String="https://x.invalid/{"; function get value():String {return x;} }','p.A')
        self.assertIn('var x:String;',api)
        self.assertIn('function get value():String ;',api)

    def test_wrong_class_identity_rejected(self):
        with self.assertRaisesRegex(ValueError,'identity'):
            declaration('class p.A {}','p.B')

    def test_unclosed_member_rejected(self):
        with self.assertRaisesRegex(ValueError,'Unbalanced'):
            declaration('class p.A { function run(){','p.A')

    def test_transitive_business_edit_changes_snapshot(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'frames').mkdir();(root/'logic/battle').mkdir(parents=True);(root/'macros').mkdir()
            frame=root/'frames/boot.as';logic=root/'logic/battle/game.as';helper=root/'macros/helper.as'
            frame.write_text('#include "../logic/battle/game.as"',encoding='utf-8')
            logic.write_text('/*\n#include "missing.as"\n*/\n#include "../macros/helper.as"',encoding='utf-8')
            helper.write_text('value=1;',encoding='utf-8')
            first=builder.include_fingerprints(root,[frame])
            helper.write_text('value=2;',encoding='utf-8')
            second=builder.include_fingerprints(root,[frame])
            self.assertEqual(len(first),3)
            self.assertEqual(first['frames/boot.as'],second['frames/boot.as'])
            self.assertNotEqual(first['macros/helper.as'],second['macros/helper.as'])

    def test_include_cycle_is_not_silently_accepted(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);p=root/'cycle.as';p.write_text('#include "cycle.as"',encoding='utf-8')
            with self.assertRaisesRegex(ValueError,'Cyclic'):
                builder.include_fingerprints(root,[p])

    def test_include_cannot_escape_snapshot_root(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);p=root/'escape.as';p.write_text('#include "../outside.as"',encoding='utf-8')
            with self.assertRaisesRegex(ValueError,'escapes'):
                builder.include_fingerprints(root,[p])

if __name__=='__main__':
    unittest.main()
