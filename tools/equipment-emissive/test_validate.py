import unittest
import xml.etree.ElementTree as ET
from validate import inspect_item


class EmissiveConfigTests(unittest.TestCase):
    def fixture(self, group="blade", use="刀", adapter="static"):
        return ET.fromstring(f"""<item><name>fixture</name><use>{use}</use><lifecycle>
          <attr_light><skillInteraction>independent</skillInteraction>
          <init><initRoutines>装备自发光初始化</initRoutines><initParam>
          <group>{group}</group><adapter>{adapter}</adapter><radius>100</radius>
          <energy>0.5</energy><color>16711680</color></initParam></init>
          <cycle><cycleRoutines>装备自发光周期</cycleRoutines></cycle></attr_light>
        </lifecycle></item>""")

    def test_valid_body_and_static_blade(self):
        for item in (self.fixture(), self.fixture("body", "上装装备")):
            self.assertFalse(inspect_item(item)[0])

    def test_state_adapter_requires_its_original_initializer(self):
        item = self.fixture(adapter="libra")
        self.assertTrue(inspect_item(item)[0])
        item.find("lifecycle").append(ET.fromstring("<attr_battle><init><initRoutines>光剑天秤初始化</initRoutines></init></attr_battle>"))
        self.assertFalse(inspect_item(item)[0])

    def test_static_armor_can_register_without_a_frame_task(self):
        item = self.fixture("body", "上装装备")
        attr = item.find("lifecycle/attr_light")
        attr.remove(attr.find("cycle"))
        self.assertFalse(inspect_item(item)[0])

    def test_invalid_numeric_values(self):
        for key, value in (("radius", "0"), ("radius", "321"), ("energy", "NaN"), ("energy", "2.1"), ("color", "0.5"), ("color", "16777216")):
            with self.subTest(key=key, value=value):
                item = self.fixture()
                item.find("lifecycle/attr_light/init/initParam/" + key).text = value
                self.assertTrue(inspect_item(item)[0])

    def test_kind_and_slot_mismatch(self):
        for item in (self.fixture("body", "刀"), self.fixture("blade", "长枪"), self.fixture("cone", "刀"), self.fixture(adapter="unknown")):
            self.assertTrue(inspect_item(item)[0])

    def test_no_battle_skill_or_defense_fields(self):
        item = self.fixture()
        item.find("lifecycle/attr_light/skillInteraction").text = "bound"
        self.assertTrue(inspect_item(item)[0])
        item = self.fixture()
        ET.SubElement(item.find("lifecycle/attr_light/init/initParam"), "evasionBonus").text = "20"
        self.assertTrue(inspect_item(item)[0])

    def test_missing_cycle_and_duplicate_configuration(self):
        item = self.fixture()
        attr = item.find("lifecycle/attr_light")
        attr.remove(attr.find("cycle"))
        self.assertTrue(inspect_item(item)[0])
        item = self.fixture()
        params = item.find("lifecycle/attr_light/init/initParam")
        ET.SubElement(params, "color").text = "123"
        self.assertTrue(inspect_item(item)[0])
        item = self.fixture()
        item.find("lifecycle").append(ET.fromstring(ET.tostring(item.find("lifecycle/attr_light"))))
        self.assertTrue(inspect_item(item)[0])


if __name__ == "__main__":
    unittest.main()
