"""Add the two explicitly approved native-frame portraits, preserving the base.

This delta verifies current source frames, human approval, every live subject,
and the untouched prior manifest. It does not recertify historical campaign
source audits. Publication reuses the shared manifest-last writer.
"""
from __future__ import annotations
import argparse
import base64
import copy
import datetime as dt
import hashlib
import importlib.util
import io
import json
import lzma
from pathlib import Path
import shutil
import tempfile
import xml.etree.ElementTree as ET
from PIL import Image, __version__ as PILLOW_VERSION

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "tools/portrait-pilot/evidence/direct-portraits-20261013"
OUTPUT = ROOT / "launcher/web/assets/enemy-portraits"
REFS = {"敌人-前治安官", "敌人-Codex黑仔"}

def sha(data): return hashlib.sha256(data).hexdigest().upper()
def stable(value): return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf8")
def seal(value, field):
    value = copy.deepcopy(value); value.pop(field, None); value[field] = sha(stable(value)); return value
def verify_digest(value, field):
    if value.get(field) != seal(value, field)[field]: raise ValueError(field + " drift")
def read(path): return json.loads(path.read_text("utf8"))
def write(path, value): path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+"\n", encoding="utf8", newline="\n")
def artifact(path): return {"path":path.relative_to(ROOT).as_posix(),"bytes":path.stat().st_size,"sha256":sha(path.read_bytes())}
def verify(record):
    path=(ROOT/record["path"]).resolve()
    if not path.is_relative_to(ROOT) or artifact(path)!=record: raise ValueError("artifact drift: "+record["path"])
    return path
def subject_path(root, record, *, legacy=False):
    prefix="assets/enemy-portraits/subjects/"
    url=record.get("url", "")
    if not url.startswith(prefix) or Path(url).name!=record["sha256"][:24].lower()+Path(url).suffix:
        raise ValueError("subject identity drift")
    path=root/"subjects"/Path(url).name
    blob=path.read_bytes()
    if len(blob)!=record["bytes"] or sha(blob)!=record["sha256"]:
        # The pre-existing SVG checkout uses CRLF while its content hashes bind
        # LF. Permit only that provably identical text conversion on preserved
        # base assets; new assets and all raster files remain byte-exact.
        canonical=blob.replace(b"\r\n",b"\n")
        if not legacy or path.suffix!=".svg" or len(canonical)!=record["bytes"] or sha(canonical)!=record["sha256"]:
            raise ValueError("subject bytes drift: "+url)
    return path
def png_bytes(image):
    stream=io.BytesIO(); image.save(stream,format="PNG",optimize=True); return stream.getvalue()
def alpha(path):
    image=Image.open(path).convert("RGBA"); channel=image.getchannel("A")
    if image.size!=(512,512) or not channel.getbbox() or channel.getextrema()[0]==255: raise ValueError("portrait alpha/size")
    return {"size":[512,512],"alphaExtrema":list(channel.getextrema()),"visibleBounds":list(channel.getbbox())}
def package():
    data=read(EVIDENCE/"render-report.json"); verify_digest(data,"renderDigest")
    approval=read(EVIDENCE/"human-review-receipt.json"); verify_digest(approval,"receiptDigest")
    if (approval.get("schema")!="cf7.direct-portrait-human-review.v1"
        or approval.get("authorizationSource")!="direct_user_reply_to_request_user_input_async"
        or approval.get("requestToolCallId")!="call_305babfa1838451b9218a852bffdbf3c"
        or approval.get("status")!="human_accepted" or approval.get("userReply")!="认可这两张，接入头像库"):
        raise ValueError("explicit human approval missing")
    if (set(data["entries"])!=REFS or len(approval["decisions"])!=2
        or {row["reviewKey"] for row in approval["decisions"]}!={ref+"::default" for ref in REFS}):
        raise ValueError("approved identity set")
    for ref,entry in data["entries"].items():
        variant=entry["variants"]["default"]; row=next(r for r in approval["decisions"] if r["reviewKey"]==ref+"::default")
        source=variant["provenance"]; subject=variant["subject"]
        if (row["status"]!="pass" or row.get("orientationAction")!="keep"
            or row["pngSha256"]!=subject["pngFallback"]["sha256"] or row["svgSha256"]!=subject["svg"]["sha256"]):
            raise ValueError("approval is not bound to these pixels")
        verify(source["sourceSwf"]); verify(source["exporterSource"])
        frame_bytes=lzma.decompress(verify(source["sourceFrameArchive"]).read_bytes())
        if sha(frame_bytes)!=source["sourceFrameSha256"]: raise ValueError("native frame drift")
        frame=Image.open(io.BytesIO(frame_bytes)).convert("RGBA"); crop=source["cropPixels"]
        side=crop[2]-crop[0]
        if side!=crop[3]-crop[1] or not 1024<=side<=4096 or not (0<=crop[0]<crop[2]<=frame.width and 0<=crop[1]<crop[3]<=frame.height):
            raise ValueError("native crop bounds")
        if source["pillowVersion"]!=PILLOW_VERSION: raise ValueError("portrait renderer version drift")
        generated=png_bytes(frame.crop(crop).resize((512,512),Image.Resampling.LANCZOS))
        if sha(generated)!=row["pngSha256"]: raise ValueError("native crop cannot reproduce approved portrait")
    return data, approval
def counts(base):
    result=copy.deepcopy(base["counts"])
    for key in ("identityCount","variantCount","humanAcceptedIdentityCount","humanAcceptedVariantCount"):result[key]+=2
    result["directSupplementalIdentityCount"]=2
    return result
def closure_inputs():
    inputs={name:artifact(EVIDENCE/file) for name,file in {"baseManifest":"base-manifest.json",
        "baseReceipt":"base-promotion-receipt.json","humanReviewReceipt":"human-review-receipt.json","renderReport":"render-report.json"}.items()}
    inputs["controller"]=artifact(Path(__file__))
    inputs["sharedPublisher"]=artifact(ROOT/"tools/portrait-pilot/promote-enemy-portraits-v1.py")
    return inputs
def crop_svg(blob, crop):
    """Keep original Flash vector geometry in exactly the approved crop."""
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    ET.register_namespace("ffdec", "https://www.free-decompiler.com/flash")
    root=ET.fromstring(blob); ns="{http://www.w3.org/2000/svg}"
    if root.findall(".//"+ns+"image"):raise ValueError("native vector must not embed raster images")
    for node in root.iter():
        for key,value in node.attrib.items():
            if key.endswith("href") and not value.startswith("#"):raise ValueError("external vector dependency")
    x,y,right,bottom=crop; side=right-x
    root.set("width","512");root.set("height","512");root.set("viewBox",f"{x} {y} {side} {side}")
    root.set("overflow","hidden")
    content=[node for node in list(root) if node.tag!=ns+"defs"]
    defs=root.find(ns+"defs")
    if defs is None:defs=ET.SubElement(root,ns+"defs")
    clip=ET.SubElement(defs,ns+"clipPath",{"id":"approvedPortraitCrop","clipPathUnits":"userSpaceOnUse"})
    ET.SubElement(clip,ns+"rect",{"x":str(x),"y":str(y),"width":str(side),"height":str(side)})
    group=ET.SubElement(root,ns+"g",{"clip-path":"url(#approvedPortraitCrop)"})
    for node in content:root.remove(node);group.append(node)
    return ET.tostring(root,encoding="utf-8",xml_declaration=False)
def native_package(record):
    data=read(verify(record));verify_digest(data,"compatibilityDigest")
    if data.get("schema")!="cf7.direct-portrait-native-vector.v1" or set(data["entries"])!=REFS:
        raise ValueError("native vector compatibility package")
    for source_record in data["originalPublication"].values():verify(source_record)
    original,approval=package()
    for ref,row in data["entries"].items():
        verify(row["exporterSource"])
        source=lzma.decompress(verify(row["sourceVectorArchive"]).read_bytes())
        provenance=original["entries"][ref]["variants"]["default"]["provenance"]
        if (sha(source)!=row["sourceVectorSha256"] or row["cropPixels"]!=provenance["cropPixels"]
            or row["sourceSwf"]!=provenance["sourceSwf"] or row["renderCharacterId"]!=provenance["renderCharacterId"]
            or row["frame"]!=provenance["frame"] or row["zoom"]!=provenance["zoom"]
            or sha(crop_svg(source,row["cropPixels"]))!=row["svg"]["sha256"]):
            raise ValueError("native vector no longer matches approved frame/crop")
    return data
def verify_previous_native_pack():
    """Use byte-bound archived producers to verify the exact prior publication."""
    snapshot=EVIDENCE/"compatibility/native-r1"
    for name,archive in {"manifest.json":"manifest.json","promotion-receipt.json":"receipt.json"}.items():
        if (OUTPUT/name).read_bytes()!=(snapshot/archive).read_bytes():raise ValueError("unexpected prior native publication")
    prior=read(snapshot/"manifest.json");closure=prior["directSupplementalPromotion"]
    mappings={closure["inputs"]["controller"]["path"]:snapshot/"controller.py",
        closure["nativeCompatibility"]["path"]:snapshot/"render-report.json"}
    for record in (closure["inputs"]["controller"],closure["nativeCompatibility"]):
        frozen=artifact(mappings[record["path"]])
        if frozen["bytes"]!=record["bytes"] or frozen["sha256"]!=record["sha256"]:raise ValueError("archived native producer drift")
    spec=importlib.util.spec_from_file_location("cf7_previous_native_portrait_verifier",snapshot/"controller.py")
    previous=importlib.util.module_from_spec(spec);spec.loader.exec_module(previous)
    previous.ROOT=ROOT;previous.EVIDENCE=EVIDENCE;previous.OUTPUT=OUTPUT
    original_verify=previous.verify
    def verify_frozen(record):
        if record["path"] in mappings:
            path=mappings[record["path"]];frozen=artifact(path)
            if frozen["bytes"]!=record["bytes"] or frozen["sha256"]!=record["sha256"]:raise ValueError("frozen producer record drift")
            return path
        return original_verify(record)
    previous.verify=verify_frozen
    previous.closure_inputs=lambda:closure["inputs"]
    previous.check_manifest(OUTPUT/"manifest.json")
def accepted_entry(rendered,ref,inputs,native_record=None,native=None):
    entry=copy.deepcopy(rendered["entries"][ref]);entry["status"]="ready"
    variant=entry["variants"]["default"];variant["status"]="human_accepted"
    variant["provenance"].update(decisionStatus="pass",orientationAction="keep",
        orientationSource="explicit_native_frame_human_approval",rasterOrientationTransform="none",
        humanReceipt=inputs["humanReviewReceipt"],acceptedRenderReport=inputs["renderReport"])
    if native:
        variant["subject"]["svg"]=native["entries"][ref]["svg"]
        variant["provenance"]["nativeRepresentationEvidence"]=native_record
    return entry
def check_manifest(path, *, logical_output=None, superseded_inputs=False):
    manifest=read(path)
    if "nativeDogSupplementalPromotion" in manifest:
        spec=importlib.util.spec_from_file_location("cf7_native_dog_portrait_check",Path(__file__).with_name("promote-dog-portraits-v1.py"))
        dogs=importlib.util.module_from_spec(spec);spec.loader.exec_module(dogs)
        return dogs.check_manifest(path,logical_output=logical_output)
    verify_digest(manifest,"manifestDigest")
    closure=manifest.get("directSupplementalPromotion",{}); verify_digest(closure,"closureDigest")
    if (closure.get("schema")!="cf7.direct-portrait-supplement.v1"
        or closure.get("status")!="human_accepted_direct_portraits_promoted"
        or set(closure.get("portraitRefs",[]))!=REFS
        or closure.get("historicalCampaignEvidence")!="preserved_without_recertification"
        or closure.get("legacyTextCompatibility")!="crlf_to_lf_checksum_only"
        or closure.get("orientationActions")!={ref:"keep" for ref in REFS}):
        raise ValueError("direct portrait closure")
    expected_inputs=closure_inputs()
    if superseded_inputs:
        previous=read(EVIDENCE/"compatibility/base-direct-manifest.json")
        for name,file in {"controller":"previous-direct-controller.py","sharedPublisher":"previous-shared-publisher.py"}.items():
            frozen=artifact(EVIDENCE/"compatibility"/file);old=previous["directSupplementalPromotion"]["inputs"][name]
            if frozen["bytes"]!=old["bytes"] or frozen["sha256"]!=old["sha256"]:raise ValueError("prior producer snapshot drift")
            expected_inputs[name]=old
    if closure.get("inputs")!=expected_inputs:raise ValueError("direct portrait producer inputs drift")
    for name,record in closure["inputs"].items():
        if not superseded_inputs or name not in {"controller","sharedPublisher"}:verify(record)
    base=read(verify(closure["inputs"]["baseManifest"])); verify_digest(base,"manifestDigest")
    base_receipt=read(verify(closure["inputs"]["baseReceipt"])); verify_digest(base_receipt,"receiptDigest")
    if base_receipt["manifestDigest"]!=base["manifestDigest"] or base["manifestDigest"]!=closure["baseManifestDigest"]:
        raise ValueError("prior accepted manifest binding")
    rendered,approval=package()
    native_record=closure.get("nativeCompatibility")
    native=native_package(native_record) if native_record else None
    if set(manifest)!=set(base)|{"directSupplementalPromotion"}:raise ValueError("delta root contract")
    if set(manifest["entries"])!=set(base["entries"])|REFS or REFS&set(base["entries"]):raise ValueError("delta identities")
    for ref,entry in base["entries"].items():
        if manifest["entries"][ref]!=entry:raise ValueError("prior accepted identity changed: "+ref)
    for key,value in base.items():
        if key not in {"entries","counts","manifestDigest","generatedAt"} and manifest.get(key)!=value:
            raise ValueError("prior manifest contract changed: "+key)
    if manifest["counts"]!=counts(base):raise ValueError("direct portrait count drift")
    declared={}
    for ref,entry in manifest["entries"].items():
        for variant in entry["variants"].values():
            if variant.get("status")!="human_accepted":continue
            for record in (variant["subject"]["svg"],variant["subject"]["pngFallback"]):declared[Path(record["url"]).name]=record
    for record in manifest["preservedEvidence"]["subjects"]:declared[Path(record["url"]).name]=record
    if native:
        for record in native["preservedSubjects"]:declared[Path(record["url"]).name]=record
    if {f.name for f in (path.parent/"subjects").iterdir()}!=set(declared):raise ValueError("live subject fileset drift")
    new_files={Path(asset["url"]).name for entry in rendered["entries"].values()
        for asset in (entry["variants"]["default"]["subject"]["svg"],entry["variants"]["default"]["subject"]["pngFallback"])}
    if native:new_files.update(Path(row["svg"]["url"]).name for row in native["entries"].values())
    for name,record in declared.items():subject_path(path.parent,record,legacy=name not in new_files)
    for ref in REFS:
        expected=accepted_entry(rendered,ref,closure["inputs"],native_record,native)
        variant=expected["variants"]["default"]
        if manifest["entries"][ref]!=expected:raise ValueError("approved new entry drift: "+ref)
        subject=variant["subject"]; png=subject_path(path.parent,subject["pngFallback"]); svg=subject_path(path.parent,subject["svg"])
        if alpha(png)!={key:subject["pngFallback"][key] for key in ("size","alphaExtrema","visibleBounds")}:raise ValueError("alpha evidence drift")
        if not native:
            root=ET.fromstring(svg.read_bytes()); images=root.findall("{http://www.w3.org/2000/svg}image")
            if len(images)!=1 or len(list(root))!=1 or root.attrib.get("viewBox")!="0 0 512 512":raise ValueError("native SVG wrapper structure")
            data=images[0].attrib.get("{http://www.w3.org/1999/xlink}href","")
            if not data.startswith("data:image/png;base64,") or base64.b64decode(data.split(",",1)[1],validate=True)!=png.read_bytes():raise ValueError("SVG and PNG pixels differ")
        if subject["preferredFormat"]!="png" or subject["svg"]["flipX"]:raise ValueError("approved orientation/representation drift")
    receipt=read(path.parent/"promotion-receipt.json"); verify_digest(receipt,"receiptDigest")
    expected_path=(logical_output or path.parent)/"manifest.json"
    record={"path":expected_path.relative_to(ROOT).as_posix(),"bytes":path.stat().st_size,"sha256":sha(path.read_bytes())}
    if (receipt["manifestDigest"]!=manifest["manifestDigest"] or receipt["manifest"]!=record or receipt["counts"]!=manifest["counts"]
        or receipt.get("directSupplementalClosureDigest")!=closure["closureDigest"]
        or receipt.get("generatedAt")!=manifest["generatedAt"]
        or set(receipt)!=set(base_receipt)|{"directSupplementalClosureDigest"}):
        raise ValueError("manifest-last receipt drift")
    for key,value in base_receipt.items():
        if key not in {"manifestDigest","manifest","counts","generatedAt","receiptDigest"} and receipt.get(key)!=value:
            raise ValueError("prior receipt contract changed: "+key)
    return manifest
def promote():
    if "nativeDogSupplementalPromotion" in read(OUTPUT/"manifest.json"):
        check_manifest(OUTPUT/"manifest.json");print("Already superseded by verified native dog supplement");return
    data,approval=package(); base=read(EVIDENCE/"base-manifest.json"); verify_digest(base,"manifestDigest")
    native_record=artifact(EVIDENCE/"compatibility/native-render-report.json")
    native=native_package(native_record)
    if sha((OUTPUT/"manifest.json").read_bytes())!=sha((EVIDENCE/"base-manifest.json").read_bytes()):
        live=read(OUTPUT/"manifest.json")
        if live.get("directSupplementalPromotion",{}).get("nativeCompatibility")==native_record:
            check_manifest(OUTPUT/"manifest.json");print("Already applied: "+live["manifestDigest"]);return
        if live.get("directSupplementalPromotion",{}).get("nativeCompatibility"):
            verify_previous_native_pack()
        else:
            if ((OUTPUT/"manifest.json").read_bytes()!=(EVIDENCE/"compatibility/base-direct-manifest.json").read_bytes()
                or (OUTPUT/"promotion-receipt.json").read_bytes()!=(EVIDENCE/"compatibility/base-direct-receipt.json").read_bytes()):
                raise ValueError("unexpected live pack before native compatibility update")
            check_manifest(OUTPUT/"manifest.json",superseded_inputs=True)
    manifest=copy.deepcopy(base); manifest["generatedAt"]=dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00","Z")
    inputs=closure_inputs()
    closure=seal({"schema":"cf7.direct-portrait-supplement.v1","status":"human_accepted_direct_portraits_promoted",
        "baseManifestDigest":base["manifestDigest"],"portraitRefs":sorted(REFS),"inputs":inputs,
        "historicalCampaignEvidence":"preserved_without_recertification","legacyTextCompatibility":"crlf_to_lf_checksum_only",
        "orientationActions":{ref:"keep" for ref in sorted(REFS)},"nativeCompatibility":native_record},"closureDigest")
    for ref in REFS:
        manifest["entries"][ref]=accepted_entry(data,ref,inputs,native_record,native)
    manifest["counts"]=counts(base);manifest["directSupplementalPromotion"]=closure;manifest=seal(manifest,"manifestDigest")
    work_root=(ROOT/"tmp/portrait-pilot").resolve()
    work_root.mkdir(parents=True,exist_ok=True)
    temporary=Path(tempfile.mkdtemp(prefix="direct-20261013-staging-",dir=work_root)).resolve()
    if not temporary.is_relative_to(work_root):raise ValueError("staging escaped portrait workspace")
    shutil.copytree(OUTPUT,temporary,dirs_exist_ok=True)
    for f in (EVIDENCE/"subjects").iterdir():shutil.copy2(f,temporary/"subjects"/f.name)
    write(temporary/"manifest.json",manifest)
    receipt=read(EVIDENCE/"base-promotion-receipt.json");receipt.update(manifestDigest=manifest["manifestDigest"],
        counts=manifest["counts"],generatedAt=manifest["generatedAt"],directSupplementalClosureDigest=closure["closureDigest"],
        manifest={"path":(OUTPUT/"manifest.json").relative_to(ROOT).as_posix(),"bytes":(temporary/"manifest.json").stat().st_size,"sha256":sha((temporary/"manifest.json").read_bytes())})
    write(temporary/"promotion-receipt.json",seal(receipt,"receiptDigest"))
    check_manifest(temporary/"manifest.json",logical_output=OUTPUT)
    module_spec=importlib.util.spec_from_file_location("cf7_direct_shared_publisher",ROOT/"tools/portrait-pilot/promote-enemy-portraits-v1.py")
    publisher=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(publisher)
    backup=Path(tempfile.mkdtemp(prefix="direct-20261013-backup-",dir=work_root)).resolve()
    if not backup.is_relative_to(work_root):raise ValueError("backup escaped portrait workspace")
    shutil.copytree(OUTPUT,backup,dirs_exist_ok=True)
    publisher.publish_staged_pack(temporary,OUTPUT,backup)
    print(json.dumps({"status":"direct_portraits_promoted","manifestDigest":manifest["manifestDigest"],"portraitRefs":sorted(REFS)},ensure_ascii=False))
def main():
    parser=argparse.ArgumentParser();parser.add_argument("command",choices=["check","promote"]);args=parser.parse_args()
    if args.command=="promote":promote()
    else:
        manifest=check_manifest(OUTPUT/"manifest.json");print(json.dumps({"status":"direct_delta_and_preserved_base_verified","counts":manifest["counts"]},ensure_ascii=False))
if __name__=="__main__":main()
