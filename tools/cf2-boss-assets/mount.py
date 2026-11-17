"""Mount only this RSL, preserving every untouched FLA local ZIP record verbatim."""
from pathlib import Path
import argparse
import binascii
import hashlib
import io
import json
import re
import struct
import zipfile
import zlib
from lxml import etree as E
import build

HERE = build.HERE
FLA = build.ROOT/"flashswf/arts/things-new.fla"
MEMBER = "LIBRARY/"+build.ANCHOR+".xml"
URL = "flashswf/arts/new/"+build.ANCHOR+".swf"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def records(raw):
    end=raw.rfind(b"PK\x05\x06")
    if end<0:raise ValueError("FLA central directory missing")
    fields=struct.unpack_from("<4s4H2IH",raw,end)
    if fields[1] or fields[2] or fields[3]!=fields[4] or fields[4]==65535:
        raise ValueError("Only single-disk non-ZIP64 FLA is supported")
    pos=fields[6]
    rows=[]
    for _ in range(fields[4]):
        if raw[pos:pos+4]!=b"PK\x01\x02":raise ValueError("Invalid FLA central record")
        n,e,c=struct.unpack_from("<3H",raw,pos+28)
        central=raw[pos:pos+46+n+e+c]
        flags=struct.unpack_from("<H",central,8)[0]
        name=central[46:46+n].decode("utf-8" if flags&0x800 else "cp437")
        rows.append({"name":name,"central":central,"offset":struct.unpack_from("<I",central,42)[0]})
        pos+=len(central)
    if pos!=fields[6]+fields[5]:raise ValueError("FLA directory length mismatch")
    ordered=sorted(rows,key=lambda r:r["offset"])
    for i,row in enumerate(ordered):
        stop=ordered[i+1]["offset"] if i+1<len(ordered) else fields[6]
        row["local"]=raw[row["offset"]:stop]
        if not row["local"].startswith(b"PK\x03\x04"):raise ValueError("Invalid FLA local record")
    return rows,raw[:ordered[0]["offset"]],raw[end:]


def compressed(data,method):
    if method==0:return data
    if method!=8:raise ValueError("Unsupported FLA compression")
    encoder=zlib.compressobj(6,zlib.DEFLATED,-15)
    return encoder.compress(data)+encoder.flush()


def replace_member(row,data):
    local=bytearray(row["local"])
    central=bytearray(row["central"])
    flags,method=struct.unpack_from("<2H",local,6)
    if flags&1:raise ValueError("Encrypted FLA member")
    n,e=struct.unpack_from("<2H",local,26)
    old_size=struct.unpack_from("<I",central,20)[0]
    payload=compressed(data,method)
    crc=binascii.crc32(data)&0xffffffff
    tail=bytearray(local[30+n+e+old_size:])
    if flags&8:
        start=4 if tail[:4]==b"PK\x07\x08" else 0
        if len(tail)<start+12:raise ValueError("Missing FLA data descriptor")
        struct.pack_into("<3I",tail,start,crc,len(payload),len(data))
    for off,value in ((14,crc),(18,len(payload)),(22,len(data))):
        if not flags&8 or struct.unpack_from("<I",local,off)[0]!=0:
            struct.pack_into("<I",local,off,value)
    struct.pack_into("<3I",central,16,crc,len(payload),len(data))
    return {**row,"central":bytes(central),"local":bytes(local[:30+n+e])+payload+bytes(tail)}


def new_member(name,data,timestamp):
    encoded=name.encode("utf-8");payload=compressed(data,8)
    crc=binascii.crc32(data)&0xffffffff
    time,date=timestamp
    local=struct.pack("<4s5H3I2H",b"PK\x03\x04",20,0x800,8,time,date,
                      crc,len(payload),len(data),len(encoded),0)+encoded+payload
    central=struct.pack("<4s6H3I5H2I",b"PK\x01\x02",20,20,0x800,8,time,date,
                        crc,len(payload),len(data),len(encoded),0,0,0,0,32,0)+encoded
    return {"name":name,"local":local,"central":central,"offset":0}


def patch_zip(raw,updates,addition):
    rows,prefix,end=records(raw)
    names={r["name"] for r in rows}
    if not set(updates)<=names or addition[0] in names:raise ValueError("Unexpected FLA mutation set")
    changed=[replace_member(r,updates[r["name"]]) if r["name"] in updates else dict(r) for r in rows]
    doc=next(r for r in rows if r["name"]=="DOMDocument.xml")
    timestamp=struct.unpack_from("<2H",doc["local"],10)
    changed.append(new_member(addition[0],addition[1],timestamp))
    output=bytearray(prefix)
    for row in sorted(changed,key=lambda r:r["offset"] if r["name"] in names else len(raw)):
        row["new_offset"]=len(output);output.extend(row["local"])
    start=len(output)
    for row in changed:
        central=bytearray(row["central"])
        struct.pack_into("<I",central,42,row["new_offset"])
        output.extend(central)
    end=bytearray(end)
    struct.pack_into("<2H",end,8,len(changed),len(changed))
    struct.pack_into("<2I",end,12,len(output)-start,start)
    output.extend(end)
    candidate=bytes(output)
    after,_,_=records(candidate)
    after_by_name={r["name"]:r for r in after}
    for row in rows:
        if row["name"] not in updates and row["local"]!=after_by_name[row["name"]]["local"]:
            raise ValueError("An unrelated FLA member changed")
    with zipfile.ZipFile(io.BytesIO(raw)) as old,zipfile.ZipFile(io.BytesIO(candidate)) as new:
        if new.testzip() is not None:raise ValueError("Candidate FLA failed CRC verification")
        for name in names:
            if new.read(name)!=(updates[name] if name in updates else old.read(name)):
                raise ValueError("FLA payload mismatch: "+name)
    return candidate,len(rows)-len(updates)


def check_mounted(raw):
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        names=archive.namelist()
        if MEMBER not in names:return False
        declaration=E.fromstring(archive.read(MEMBER))
        if any(declaration.get(k)!=v for k,v in {
                "linkageIdentifier":build.ANCHOR,"linkageImportForRS":"true","linkageURL":URL}.items()):
            raise ValueError("Existing tank RSL declaration differs")
        doc=E.fromstring(archive.read("DOMDocument.xml"))
        includes=doc.findall('x:symbols/x:Include[@href="'+build.ANCHOR+'.xml"]',build.NS)
        main=E.fromstring(archive.read("LIBRARY/things-new.xml"))
        mounts=main.findall('.//x:DOMFrame[@index="3"]/x:elements/x:DOMSymbolInstance[@libraryItemName="'+build.ANCHOR+'"]',build.NS)
        if len(includes)!=1 or includes[0].get("itemID")!=declaration.get("itemID") or len(mounts)!=1:
            raise ValueError("Partial tank RSL mount must be reviewed, not overwritten")
        return True


def mount():
    raw=FLA.read_bytes()
    if check_mounted(raw):
        print(json.dumps({"ok":True,"alreadyMounted":True}));return
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        doc=archive.read("DOMDocument.xml").decode("utf-8")
        main=archive.read("LIBRARY/things-new.xml").decode("utf-8")
    item_id=build.native.item_id(build.ANCHOR)
    if doc.count("</symbols>")!=1:raise ValueError("Unexpected things-new symbols container")
    include='<Include href="'+build.ANCHOR+'.xml" itemID="'+item_id+'" loadImmediate="false"/>'
    doc=doc.replace("</symbols>",include+"\n</symbols>",1)
    main_tree=E.fromstring(main.encode("utf-8"))
    if len(main_tree.findall('.//x:DOMFrame[@index="3"]/x:elements',build.NS))!=1:
        raise ValueError("Ambiguous things-new fourth-frame mount")
    instance=('<DOMSymbolInstance libraryItemName="'+build.ANCHOR+'"><matrix><Matrix tx="1800" ty="500"/>'
              '</matrix><transformationPoint><Point/></transformationPoint></DOMSymbolInstance>')
    pattern=r'(<DOMFrame\b[^>]*\bindex="3"[^>]*>.*?<elements>)(.*?)(</elements>)'
    main,count=re.subn(pattern,lambda m:m[1]+m[2]+instance+m[3],main,count=1,flags=re.S)
    if count!=1:raise ValueError("Fourth-frame raw XML insertion failed")
    declaration=build.native.symbol(build.ANCHOR,[build.native.layer("导入",[build.native.frame()])],
                                     symbol_type="movie clip")
    declaration.attrib.update({"linkageImportForRS":"true","linkageExportInFirstFrame":"false",
                               "linkageIdentifier":build.ANCHOR,"linkageURL":URL})
    candidate,preserved=patch_zip(raw,{"DOMDocument.xml":doc.encode("utf-8"),
                                      "LIBRARY/things-new.xml":main.encode("utf-8")},
                                 (MEMBER,build.native.xml_bytes(declaration)))
    if not check_mounted(candidate):raise ValueError("Candidate RSL mount not complete")
    before=digest(raw);out=build.ROOT/"tmp/cf2-boss/mount"/before
    out.mkdir(parents=True,exist_ok=True)
    backup=out/"things-new-before.fla"
    if backup.exists() and backup.read_bytes()!=raw:raise ValueError("Mount backup collision")
    if not backup.exists():backup.write_bytes(raw)
    pending=FLA.with_suffix(".cf2-tank-mount.tmp")
    if pending.exists():raise ValueError("Unresolved prior tank mount candidate")
    pending.write_bytes(candidate)
    if FLA.read_bytes()!=raw:raise ValueError("Shared FLA changed during tank mount")
    pending.replace(FLA)
    receipt={"schema":"cf2-tank-boss.mount.v1","before":before,"after":digest(candidate),
             "changedMembers":["DOMDocument.xml","LIBRARY/things-new.xml"],
             "addedMember":MEMBER,"untouchedLocalRecordsByteIdentical":preserved}
    (HERE/"mount-receipt.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(receipt,ensure_ascii=False))


if __name__=="__main__":
    if hasattr(__import__("sys").stdout,"reconfigure"):__import__("sys").stdout.reconfigure(encoding="utf-8")
    parser=argparse.ArgumentParser();parser.add_argument("--write",action="store_true");args=parser.parse_args()
    if args.write:mount()
    elif not check_mounted(FLA.read_bytes()):raise ValueError("Tank RSL is not mounted")
    else:print('{"ok":true,"mounted":true}')
