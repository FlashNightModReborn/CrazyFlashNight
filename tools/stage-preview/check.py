#!/usr/bin/env python3
"""Validate the actual selected 99-stage delivery, with no aesthetic-pass claim."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image
from PIL import ImageStat
from build import ROOT,HERE,sha,generator_digest,metadata_inputs
import prepare
import render_v6_6_regions as regions


def dhash(image):
    im=image.convert("L").resize((9,8),Image.Resampling.LANCZOS)
    pixels=im.load();value=0
    for y in range(8):
        for x in range(8):value=(value<<1)|(pixels[x+1,y]>pixels[x,y])
    return value


def stage_sources():
    source_root=ROOT/"data/stages";result={}
    for area in ET.parse(source_root/"list.xml").getroot().findall("stages"):
        folder=source_root/(area.text or "").strip();index=folder/"__list__.xml"
        if not index.exists():continue
        for info in ET.parse(index).getroot().findall("StageInfo"):
            name=info.findtext("Name")
            if name:result[name]=folder/(name+".xml")
    return result


def check(directory):
    report=json.loads((directory/"manifest.json").read_text("utf-8"))
    config=json.loads((HERE/"stages.json").read_text("utf-8"))
    failures=[];warnings=[];details=[];grouped={}
    if report.get("sourceConfigSha256")!=sha(HERE/"stages.json"):failures.append("Stale stage configuration")
    if report.get("generatorSha256")!=generator_digest():failures.append("Stale generator or native-source recipe")
    if report.get("metadataInputs")!=metadata_inputs():failures.append("Stage registry, environment, units or portrait catalog changed after the build")
    if report.get("status")!="candidate_pending_human_review":failures.append("Candidate must not assert human acceptance")
    try:prepare.check(regions.PILOT_DIR)
    except Exception as error:failures.append(str(error))
    registered={e["output"] for e in prepare.load()["inputs"]}
    if set(report.get("cacheFiles",[]))!=registered:failures.append("Native raster dependency closure differs from the registered source recipes")
    entries=report["stages"];ids=[s["id"] for s in entries]
    configured={s["id"]:s for s in config["stages"]}
    if len(ids)!=len(set(ids)):failures.append("Duplicate stage IDs")
    if ids!=[s["id"] for s in config["stages"]]:failures.append("Delivery does not exactly cover the selected stage list")
    # Read the current generated UI registry without executing it.
    code=(ROOT/"launcher/web/modules/stage-select-data.js").read_text("utf-8-sig")
    registry,_=json.JSONDecoder().raw_decode(code[code.index("var manifest = ")+len("var manifest = "):])
    selected_regions={s["region"] for s in entries}
    buttons={s["id"]:s for f in registry["frames"] if f["frameLabel"] in selected_regions for s in f.get("stageButtons",[])}
    if set(ids)!=set(buttons):failures.append("Coverage differs from current UI registry in the seven target regions")
    unit_list=json.loads((ROOT/"data/units/units.json").read_text("utf-8-sig"))
    units={str(u["id"]):u for u in unit_list}
    units_by_key={u["key"]:u for u in unit_list if u.get("key")}
    xml_by_name=stage_sources()
    expected_files=set()
    for entry in entries:
        sid=entry["id"];master=directory/entry["file"];thumb=directory/entry["thumb"]
        selected=configured.get(sid,{})
        if any(entry.get(key)!=value for key,value in selected.items()):failures.append(sid+": selected metadata differs from authoritative configuration")
        if entry["file"]!=f"images/{sid}.png" or entry["thumb"]!=f"images/{sid}-thumb.png":failures.append(sid+": delivery image path is not canonical")
        expected_files.update([master.resolve(),thumb.resolve()])
        if entry["stageName"]!=buttons.get(sid,{}).get("stageName"):failures.append(sid+": stage name drift")
        if not master.is_file() or not thumb.is_file():failures.append(sid+": image missing");continue
        if sha(master)!=entry["sha256"] or sha(thumb)!=entry["thumb_sha256"]:failures.append(sid+": output hash mismatch")
        with Image.open(master) as image,Image.open(thumb) as small:
            image=image.convert("RGB");small=small.convert("RGB")
            if image.size!=(644,276) or small.size!=(161,69):failures.append(sid+": wrong image dimensions")
            elif image.resize((161,69),Image.Resampling.LANCZOS).tobytes()!=small.tobytes():failures.append(sid+": thumbnail differs from its selected master")
            with Image.open(ROOT/entry["baseline"]) as previous:
                same=image.tobytes()==previous.convert("RGB").tobytes()
            if entry["decision"]=="preserve_v6" and not same:failures.append(sid+": frozen V6 pixels changed")
            if entry["decision"]=="refined" and same:failures.append(sid+": marked refined but unchanged")
            grouped.setdefault(entry["region"],[]).append((sid,dhash(image)))
            audit=entry.get("subjectAudit")
            if entry["decision"]=="refined" and entry.get("subjects") and not audit:failures.append(sid+": refined subject lacks its own pixel mask")
            if audit:
                mask_file=directory/audit["file"]
                if sha(mask_file)!=audit["sha256"]:failures.append(sid+": subject mask hash mismatch")
                with Image.open(mask_file) as mask:
                    stats=ImageStat.Stat(image.convert("L"),mask.convert("L"))
                if stats.count[0]<100 or stats.mean[0]<18 or stats.stddev[0]<22:failures.append(sid+": subject-only luminance/contrast below floor")
                for feature in audit["features"]:
                    if not feature["inside"]:failures.append(sid+": protected feature cropped: "+feature["name"])
        if sha(ROOT/entry["baseline"])!=entry["baseline_sha256"]:failures.append(sid+": frozen source hash changed")
        composition=entry.get("composition",{});source=xml_by_name.get(entry["stageName"])
        if source and source.is_file():
            tree=ET.parse(source).getroot();native_names=set()
            for enemy in tree.findall(".//Enemy"):
                type_node=enemy.find("Type")
                for text in type_node.itertext() if type_node is not None else []:
                    stripped=text.strip()
                    if stripped in units_by_key:
                        native_names.add(units_by_key[stripped].get("spritename",""))
                    for number in re.findall(r"兵种(\d+)",text):
                        if number in units:native_names.add(units[number].get("spritename",""))
                if enemy.findtext("spritename"):native_names.add(enemy.findtext("spritename"))
            for subject in entry.get("subjects",[]):
                if subject not in native_names:failures.append(sid+": selected subject absent from current XML: "+subject)
            backgrounds={Path(n.text.strip()).name for n in tree.findall(".//SubStage/BasicInformation/Background") if n.text}
            selected_bg=composition.get("selected_bg") or (composition["bg_stem"]+".swf" if composition.get("bg_stem") else None)
            if selected_bg:
                button=buttons.get(sid,{})
                if button.get("entryKind")=="map":
                    if selected_bg!=button.get("rootFadeTransitionFrame","")+".swf":failures.append(sid+": background differs from the current direct-map destination")
                elif selected_bg not in backgrounds:failures.append(sid+": background absent from current XML: "+selected_bg)
            details.append({"id":sid,"stageXml":source.relative_to(ROOT).as_posix(),"stageXmlSha256":sha(source)})
        elif entry.get("subjects"):
            failures.append(sid+": no current stage XML for selected subjects")
        if entry.get("subjectPolicy") in ["emblem_no_boss_reveal","landmark_no_unverified_enemy"] and entry.get("subjects"):
            failures.append(sid+": an unverified boss leaked into a landmark/emblem selection")
    for region,values in grouped.items():
        for i,(a,ha) in enumerate(values):
            for b,hb in values[i+1:]:
                distance=(ha^hb).bit_count()
                if distance<8:failures.append(f"{region}: {a}/{b} near-duplicate (distance {distance}<8)")
    actual={p.resolve() for p in (directory/"images").glob("*.png")}
    if actual!=expected_files:failures.append("Unreferenced or missing delivery images")
    result={"scope":"selected assets, source identity, native raster pixels, full coverage, unchanged V6 pixels and same-region duplicate check; visual acceptance remains human",
            "stageCount":len(entries),"refined":sum(e["decision"]=="refined" for e in entries),"preserved":sum(e["decision"]=="preserve_v6" for e in entries),
            "regionCount":len(grouped),"imageBytes":sum(e["bytes"] for e in entries),"pass":not failures,"failures":failures,"warnings":warnings,"sourceChecks":details}
    (directory/"check-report.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in result.items() if k!="sourceChecks"},ensure_ascii=False,indent=2))
    return 0 if not failures else 1


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("candidate",type=Path);args=parser.parse_args();raise SystemExit(check(args.candidate))
