"""Offline source/registration/ZIP boundaries; native behavior has its own runner."""
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
import build
import balance
import mount
import struct
import zlib


class TankAssetTests(unittest.TestCase):
    def test_dat_cache_decoder_handles_raw_and_chunked_premultiplied_argb(self):
        pixels=bytes((255,20,40,60,128,64,32,0))
        header=b"\x03\x05"+struct.pack("<3H4iB",8,2,1,0,40,0,20,1)
        raw=header+b"\x00"+pixels
        image=build.bitmap.decode(raw,2,1)
        self.assertEqual([image.getpixel((x,0)) for x in range(2)],[(20,40,60,255),(128,64,0,128)])
        packed=zlib.compress(pixels)
        compressed=header+b"\x01"+struct.pack("<H",len(packed))+packed+b"\0\0"
        self.assertEqual(build.bitmap.decode(compressed,2,1).tobytes(),image.tobytes())
        self.assertEqual(build.bitmap.unpack(build.bitmap.cache(raw,2,1),2,1)[2],pixels)
        with self.assertRaises(ValueError):build.bitmap.decode(raw,3,1)
        with self.assertRaises(ValueError):build.bitmap.decode(compressed[:-1],2,1)
    def test_source_and_loop_contract(self):
        source,doc,items=build.source()
        self.assertEqual(doc.get("frameRate"),"30")
        self.assertEqual(len(items),73)
        rows={r["action"]:r for r in balance.observed_actions()}
        self.assertEqual({k:v["frames"] for k,v in rows.items()},
                         {"melee":61,"gatling":44,"laser":57,"barrage":170,"mobile":190})
        self.assertEqual(rows["melee"]["contacts"],3)
        self.assertEqual(rows["gatling"]["contacts"],9)
        self.assertEqual(rows["laser"]["contacts"],10)
        self.assertEqual(rows["barrage"]["kinds"],{"melee":0,"gun":36,"cannon":3,"laser":24,"grenade":30})
        self.assertEqual(rows["mobile"]["kinds"],{"melee":0,"gun":33,"cannon":4,"laser":0,"grenade":30})
        self.assertEqual(build.SPEC["tuning"]["deathPower"],2.0)
        for spec in build.SPEC["actions"].values():
            self.assertNotIn("facing",spec)

    def test_generated_source_identity(self):
        build.check()
        root=build.E.parse(str(build.OWNER/"DOMDocument.xml"))
        names={i.get("href")[:-4] for i in root.findall("x:symbols/x:Include",build.NS)}
        folders={i.get("name") for i in root.findall("x:folders/x:DOMFolderItem",build.NS)}
        self.assertFalse(names & folders)
        self.assertEqual(len(names),len(set(names)))
        self.assertEqual(root.find("x:media",build.NS).__len__(),211)
        order=[e.tag.split("}")[-1] for e in root.getroot()]
        self.assertLess(order.index("media"),order.index("symbols"))
        for item in root.findall("x:media/x:DOMBitmapItem",build.NS):
            self.assertTrue((build.OWNER/"bin"/item.get("bitmapDataHRef")).is_file())
            image=build.OWNER/"LIBRARY"/item.get("href")
            self.assertTrue(image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"),str(image))
        for path in (build.OWNER/"LIBRARY").rglob("*.xml"):
            item=build.E.parse(str(path)).getroot()
            for frame in item.findall(".//x:DOMFrame",build.NS):
                self.assertNotIn("parentLayerIndex",frame.attrib)
                self.assertNotIn("rigPropagationMatrix",frame.attrib)

    def test_as2_bom_and_no_foreign_nuclear_death(self):
        paths=[build.HERE/"TankBossAI.as",
               build.ROOT/"scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf2TankBossAssetTest.as",
               build.ROOT/"scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf2TankBossVisualProbe.as",
               build.ROOT/"scripts/test-runners/cf2-tank-boss/TestLoader.as.template",
               build.ROOT/"scripts/test-runners/cf2-tank-boss/TestLoader-capture.as.template"]
        for path in paths:self.assertTrue(path.read_bytes().startswith(b"\xef\xbb\xbf"),str(path))
        text=(build.HERE/"TankBossAI.as").read_text("utf-8-sig")
        self.assertNotIn('子弹种类:"核弹爆炸"',text)
        self.assertNotIn("子弹角度偏移",text)
        self.assertIn("owner.lastDamagePulse=owner.pulse;",text)
        self.assertIn("identity!==body.tankFrameIdentity",text)

    def test_cs6_symbol_types_are_explicit_at_the_visual_boundary(self):
        controlled={build.PREFIX+"原画/坦克大机器人/"+name
                    for name in ("常态","平a","技能","跑步走路")}
        blended={build.PREFIX+"原画/"+name for name in build.BLENDED_SYMBOLS}
        seen_modes=set()
        for path in (build.OWNER/"LIBRARY").rglob("*.xml"):
            item=build.E.parse(str(path)).getroot()
            name=item.get("name")
            if name in blended:
                self.assertEqual(item.get("symbolType"),"movie clip",name)
            elif name.startswith(build.PREFIX+"原画/") and name not in controlled:
                self.assertEqual(item.get("symbolType"),"graphic",name)
            for inst in item.findall(".//x:DOMSymbolInstance",build.NS):
                mode=inst.get("blendMode")
                if mode:
                    seen_modes.add(mode)
                    self.assertEqual(inst.get("symbolType"),"movie clip",name)
        self.assertTrue({"add","lighten"}.issubset(seen_modes),seen_modes)
        for action,spec in build.SPEC["actions"].items():
            if spec["source"]!="技能":
                continue
            sliced=build.OWNER/"LIBRARY"/(build.PREFIX+"动作切片/"+action+".xml")
            self.assertTrue(sliced.is_file(),str(sliced))
            item=build.E.parse(str(sliced)).getroot()
            self.assertEqual(item.get("symbolType"),"movie clip",action)
            self.assertEqual(build.total(item),spec["end"]-spec["start"]+1,action)
        box=build.OWNER/"LIBRARY"/(build.PREFIX+"攻击矩形图形.xml")
        self.assertNotEqual(build.E.parse(str(box)).getroot().get("symbolType"),"graphic")

    def test_parented_art_and_collision_ports_use_native_motion(self):
        motion=build.native_motion()
        _,_,source=build.source()
        for label in ("常态","跑步走路","平a","技能"):
            original=source["坦克大机器人/"+label]
            generated=build.E.parse(str(build.OWNER/"LIBRARY"/(build.PREFIX+"原画/坦克大机器人/"+label+".xml"))).getroot()
            dipan_li=next(i for i,l in enumerate(build.layers(original)) if l.get("name")=="theboss底盘")
            for li,layer in enumerate(build.layers(original)):
                if not any(f.get("parentLayerIndex") is not None for f in build.frames(layer)):
                    continue
                output=build.layers(generated)[li]
                if label=="跑步走路" and layer.get("name")=="示例用管线":
                    self.assertEqual(len(build.frames(output)),len(motion[label]))
                    for fi,pose in enumerate(motion[label]):
                        dm=pose[dipan_li][0]["matrix"]
                        elements=build.active(output,fi).findall("x:elements/x:DOMSymbolInstance",build.NS)
                        self.assertEqual(len(elements),1)
                        self.assertEqual(elements[0].get("libraryItemName"),build.PREFIX+"原画/待整理防具相关汇总/示例用管线")
                        expected=(1,0,0,1,dm[4]+483.5,dm[5]-48.25)
                        self.assertLess(max(abs(a-b) for a,b in zip(build.matrix(elements[0]),expected)),0.00001)
                    continue
                for fi,pose in enumerate(motion[label]):
                    rows=pose.get(li,[])
                    elements=build.active(output,fi).findall("x:elements/x:DOMSymbolInstance",build.NS)
                    self.assertEqual(len(elements),len(rows),(label,li,fi))
                    for element,row in zip(elements,rows):
                        self.assertLess(max(abs(a-b) for a,b in zip(build.matrix(element),row["matrix"])),0.00001)
                        self.assertEqual(element.get("libraryItemName"),build.PREFIX+"原画/"+row["part"])
            if label=="跑步走路":
                self.assertNotIn("PuppetShape_1",build.E.tostring(generated,encoding="unicode"))
        art=source["坦克大机器人/技能"]
        for port,layer_name,tip in (("gun","theboss机枪手",build.SPEC["geometry"]["gunMuzzle"]),
                                    ("cannon","theboss炮塔",build.SPEC["geometry"]["cannonMuzzle"]),
                                    ("grenade","theboss炮塔",[0,0])):
            li=next(i for i,l in enumerate(build.layers(art)) if l.get("name")==layer_name)
            path=build.OWNER/"LIBRARY"/(build.PREFIX+"接口/技能/"+port+"/技能_"+port+"_接口叶.xml")
            layer=build.layers(build.E.parse(str(path)).getroot())[0]
            for fi,pose in enumerate(motion["技能"]):
                rows=pose.get(li,[])
                if port=="gun":
                    candidates=[i for i,l in enumerate(build.layers(art)) if l.get("name") in ("theboss机枪手","theboss斧头手")]
                    rows=[row for index in candidates for row in pose.get(index,[])
                          if row["part"]=="待整理防具相关汇总/theboss机枪手" and row["firstFrame"]==0]
                elements=build.active(layer,fi).findall("x:elements/x:DOMSymbolInstance",build.NS)
                self.assertEqual(len(elements),len(rows),(port,fi))
                for row,element in zip(rows,elements):
                    expected=build.mul(row["matrix"],(1,0,0,1,*tip))
                    self.assertLess(max(abs(a-b) for a,b in zip(build.matrix(element),expected)),0.00001)
        beam_path=build.OWNER/"LIBRARY"/(build.PREFIX+"接口/技能/beam/技能_beam_接口叶.xml")
        beam_layer=build.layers(build.E.parse(str(beam_path)).getroot())[0]
        for fi in range(len(motion["技能"])):
            expected=build.beam_box_matrices(art,motion["技能"],fi)
            elements=build.active(beam_layer,fi).findall("x:elements/x:DOMSymbolInstance",build.NS)
            self.assertEqual(len(elements),len(expected),fi)
            if 60<=fi<=99 or 116<=fi<=167:
                self.assertEqual(len(expected),6,fi)
                self.assertNotEqual(expected[0],expected[-1],fi)
            for element,matrix in zip(elements,expected):
                self.assertLess(max(abs(a-b) for a,b in zip(build.matrix(element),matrix)),0.00001)

    def test_registration_preserves_other_units(self):
        entry,unit,receipt,units=balance.expected()
        text=(build.ROOT/"data/units/units.json").read_text("utf-8-sig")
        result=balance.unit_text(text,unit)
        self.assertEqual(json.loads(result),units)
        altered=dict(unit);altered["id"]=1
        with self.assertRaises(ValueError):balance.unit_text(text,altered)
        self.assertTrue(receipt["stageIsBudgetProxy"])
        self.assertTrue(receipt["placementLevelNotDecided"])
        self.assertEqual(len(entry.findall("掉落物")),0)

    def test_rebuild_refuses_artist_edits(self):
        previous_owner,previous_manifest=build.OWNER,build.MANIFEST
        parent=build.ROOT/"tmp/cf2-boss/tests"
        parent.mkdir(parents=True,exist_ok=True)
        try:
            with tempfile.TemporaryDirectory(dir=parent) as temp:
                build.OWNER=Path(temp)/"owner"
                build.MANIFEST=Path(temp)/"manifest.json"
                build.MANIFEST.write_text(json.dumps({"outputs":[]}),"utf-8")
                build.guard()
                self.assertFalse(build.OWNER.exists())
                build.OWNER.mkdir()
                path=build.OWNER/"DOMDocument.xml";path.write_bytes(b"original")
                build.MANIFEST.write_text(json.dumps({"outputs":[{"path":path.name,"sha256":build.sha(path)}]}),"utf-8")
                build.guard()
                path.write_bytes(b"artist edit")
                with self.assertRaisesRegex(ValueError,"Preserve external artwork"):build.guard()
                path.write_bytes(b"original");(build.OWNER/"new.xml").write_bytes(b"unowned")
                with self.assertRaisesRegex(ValueError,"file set"):build.guard()
        finally:
            build.OWNER,build.MANIFEST=previous_owner,previous_manifest

    def test_raw_fla_updates_preserve_untouched_records_and_descriptors(self):
        class Pipe(io.BytesIO):
            def seekable(self):return False
            def seek(self,*args):raise io.UnsupportedOperation("stream")
        for descriptors in (False,True):
            with self.subTest(descriptors=descriptors):
                buf=Pipe() if descriptors else io.BytesIO()
                with zipfile.ZipFile(buf,"w",zipfile.ZIP_DEFLATED) as archive:
                    archive.writestr("DOMDocument.xml",b"<root>before</root>")
                    archive.writestr("LIBRARY/unchanged.xml",b"<root>retained</root>")
                raw=buf.getvalue()
                new,preserved=mount.patch_zip(raw,{"DOMDocument.xml":b"<root>changed longer</root>"},
                                               ("LIBRARY/new.xml",b"<root/>"))
                self.assertEqual(preserved,1)
                old_rows,_,_=mount.records(raw);new_rows,_,_=mount.records(new)
                old=next(r for r in old_rows if r["name"]=="LIBRARY/unchanged.xml")
                current=next(r for r in new_rows if r["name"]==old["name"])
                self.assertEqual(old["local"],current["local"])
                with zipfile.ZipFile(io.BytesIO(new)) as archive:
                    self.assertIsNone(archive.testzip())
                    self.assertEqual(archive.read("DOMDocument.xml"),b"<root>changed longer</root>")
                with self.assertRaises(ValueError):
                    mount.patch_zip(raw,{},("DOMDocument.xml",b"duplicate"))

    def test_mount_write_readback_receipt_and_idempotence(self):
        original_fla,original_here,original_root=mount.FLA,mount.HERE,build.ROOT
        parent=build.ROOT/"tmp/cf2-boss/tests"
        parent.mkdir(parents=True,exist_ok=True)
        try:
            with tempfile.TemporaryDirectory(dir=parent) as temp:
                mount.HERE=Path(temp);mount.FLA=Path(temp)/"things-new.fla";build.ROOT=Path(temp)
                uri=build.NS["x"]
                doc=('<DOMDocument xmlns="'+uri+'"><symbols></symbols></DOMDocument>').encode()
                main=('<DOMSymbolItem xmlns="'+uri+'"><timeline><DOMTimeline><layers><DOMLayer><frames>'
                      '<DOMFrame index="3"><elements></elements></DOMFrame></frames></DOMLayer>'
                      '</layers></DOMTimeline></timeline></DOMSymbolItem>').encode()
                with zipfile.ZipFile(mount.FLA,"w",zipfile.ZIP_DEFLATED) as archive:
                    archive.writestr("mimetype",b"application/vnd.adobe.xfl",compress_type=zipfile.ZIP_STORED)
                    archive.writestr("DOMDocument.xml",doc)
                    archive.writestr("LIBRARY/things-new.xml",main)
                before=mount.FLA.read_bytes()
                mount.mount()
                after=mount.FLA.read_bytes()
                self.assertTrue(mount.check_mounted(after))
                receipt=json.loads((mount.HERE/"mount-receipt.json").read_text("utf-8"))
                self.assertEqual(receipt["before"],mount.digest(before))
                self.assertEqual(receipt["after"],mount.digest(after))
                mount.mount()
                self.assertEqual(mount.FLA.read_bytes(),after)
        finally:
            mount.FLA,mount.HERE,build.ROOT=original_fla,original_here,original_root


if __name__=="__main__":
    unittest.main(verbosity=2)
