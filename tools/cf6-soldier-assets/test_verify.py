"""Keep generic ordinary AI isolated while admitting the exact fixed158 adapter."""
import unittest
from pathlib import Path
from lxml import etree as E
import verify


class OrdinarySidearmScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = E.parse(str(verify.build.OWNER/'LIBRARY/Codex/特种兵/敌人-CF6特种兵.xml'))
        cls.text = '\n'.join(root.xpath('//*[local-name()="script"]/text()'))
        cls.adapter = (Path(__file__).parent/'FixedActionAdapter.as').read_text('utf-8-sig').strip()

    def test_exact_generated_ordinary_root(self):
        verify.verify_ordinary_sidearm_scope(self.text)

    def test_generic_mixed_initialization_is_still_rejected(self):
        with self.assertRaises(AssertionError):
            verify.verify_ordinary_sidearm_scope(self.text+'\n_root.初始化混合双枪(this);')

    def test_elite_motion_is_still_rejected(self):
        with self.assertRaises(AssertionError):
            verify.verify_ordinary_sidearm_scope(self.text+'\neliteMotionConfig={};')

    def test_modified_shared_adapter_is_not_stripped(self):
        changed = self.adapter.replace('cf6FixedInstall', 'changedInstall', 1)
        self.assertNotEqual(changed, self.adapter)
        with self.assertRaises(AssertionError):
            verify.verify_ordinary_sidearm_scope(self.text.replace(self.adapter, changed, 1))

    def test_duplicate_adapter_is_rejected(self):
        with self.assertRaises(AssertionError):
            verify.verify_ordinary_sidearm_scope(self.text+'\n'+self.adapter)


if __name__ == '__main__':
    unittest.main()
