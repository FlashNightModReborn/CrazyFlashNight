"""Read-only identity and RSL closure verification; never an execution verdict."""
from pathlib import Path
import argparse
import json
import struct
import subprocess
import zlib
from lxml import etree as E
import build
import mount


def sprite_lengths(path):
    raw=path.read_bytes()
    data=zlib.decompress(raw[8:]) if raw[:3]==b"CWS" else raw[8:]
    pos=(5+(data[0]>>3)*4+7)//8+4
    result=[]
    while pos<len(data):
        header=struct.unpack_from("<H",data,pos)[0];pos+=2
        tag,size=header>>6,header&63
        if size==63:size=struct.unpack_from("<I",data,pos)[0];pos+=4
        if tag==39:result.append(struct.unpack_from("<HH",data,pos))
        if tag==0:break
        pos+=size
    return result


def blended_placements(path):
    raw=path.read_bytes()
    data=zlib.decompress(raw[8:]) if raw[:3]==b"CWS" else raw[8:]
    pos=(5+(data[0]>>3)*4+7)//8+4
    count=0
    def walk(start,limit):
        nonlocal count
        p=start
        while p<limit:
            header=struct.unpack_from("<H",data,p)[0];p+=2
            tag,size=header>>6,header&63
            if size==63:size=struct.unpack_from("<I",data,p)[0];p+=4
            if tag==70 and size>=2 and (data[p+1]&0x02)!=0:count+=1
            elif tag==39 and size>=4:walk(p+4,p+size)
            if tag==0:break
            p+=size
    walk(pos,len(data))
    return count


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--source-only",action="store_true")
    args=parser.parse_args()
    build.check()
    subprocess.run([__import__("sys").executable,"-B","-X","utf8",str(build.HERE/"balance.py")],check=True)
    if not mount.check_mounted(mount.FLA.read_bytes()):
        raise ValueError("The independent RSL is not mounted through things-new")
    relative="flashswf/arts/new/"+build.ANCHOR+".swf"
    source_map=E.parse(str(build.ROOT/"data/items/asset_source_map.xml")).getroot()
    for name in (build.ANCHOR,build.LINKAGE):
        rows=[r for r in source_map if r.get("id")==name]
        if len(rows)!=1 or rows[0].get("swf")!=relative:
            raise ValueError("Missing or ambiguous source-map identity: "+name)
    manifest=json.loads(build.MANIFEST.read_text("utf-8"))
    result={"sourceVerified":True,"executionVerified":False,
            "nativeSymbols":manifest["symbols"],"sourceBitmapCount":manifest["bitmaps"],
            "nativeSourceBytes":sum(r["bytes"] for r in manifest["outputs"]),
            "manifestSha256":build.sha(build.MANIFEST)}
    if not args.source_only:
        reader=build.module("cf2_read_swf_linkages",build.ROOT/"tools/cf6-bladebot-assets/verify.py")
        scanner=build.module("cf2_read_swf_stats",build.ROOT/"tools/swf-audit/swfscan.py")
        swf=build.ROOT/relative
        exports,imports=reader.linkage_records(swf)
        if set(exports)!={build.ANCHOR,build.LINKAGE} or len(exports)!=2 or imports:
            raise ValueError("Independent unit library has an unexpected import/export closure")
        source_max=max(build.total(E.parse(str(p)).getroot()) for p in (build.OWNER/"LIBRARY").rglob("*.xml"))
        bad=[row for row in sprite_lengths(swf) if row[1]>source_max]
        if bad:
            raise ValueError("CS6 merged unrelated private timelines: "+str(bad))
        _,shared=reader.linkage_records(build.ROOT/"flashswf/arts/things-new.swf")
        rows=[r for r in shared if build.ANCHOR in r["names"]]
        if len(rows)!=1 or rows[0]["url"]!=relative:
            raise ValueError("Published things-new does not import the exact independent RSL")
        pixels=scanner.scan(str(swf))
        if not pixels["bitmaps"]:
            raise ValueError("Authored bitmap fills were not compiled; a red placeholder is not a valid conversion")
        blends=blended_placements(swf)
        if blends==0:
            raise ValueError("Published SWF dropped all authored blendMode placements")
        subprocess.run(["node",str(build.ROOT/"tools/audit-as2-class-embedding.js"),
                        "--swf",relative],cwd=build.ROOT,check=True)
        result.update(publishedClosureVerified=True,swf=relative,swfSha256=build.sha(swf),
                      swfBytes=swf.stat().st_size,compiledShapes=pixels["shapes"],
                      compiledSprites=pixels["sprites"],compiledBitmaps=pixels["bitmaps"],
                      compiledBlendedPlacements=blends,exports=exports,sharedImport=rows[0])
    print(json.dumps(result,ensure_ascii=False))


if __name__=="__main__":
    if hasattr(__import__("sys").stdout,"reconfigure"):
        __import__("sys").stdout.reconfigure(encoding="utf-8")
    main()
