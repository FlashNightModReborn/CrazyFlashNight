"""Validate native bitmap/media closure without controlling Flash or modifying pixels."""
import hashlib
from pathlib import Path
from lxml import etree as E
from PIL import Image

NS={'x':'http://ns.adobe.com/xfl/2008/'}
BITMAP_POLICY={'compressionType':'lossless','useImportedJPEGData':'false','allowSmoothing':'true'}


def parse(path):
    return E.parse(str(path),E.XMLParser(strip_cdata=False,remove_blank_text=False))


def local_file(base,relative):
    path=(base/relative).resolve()
    if not path.is_relative_to(base.resolve()) or not path.is_file() or path.stat().st_size==0:
        raise ValueError('Missing/unsafe/empty native closure file: '+str(path))
    return path


def fingerprint(path):
    return {'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size}


def audit(source,expected_inputs=(),require_policy=True):
    """Sources must match pinned PNG hashes; bin data is checked for presence and identity.

    Native .dat bytes are opaque: this is not a pixel decode or SWF execution proof.
    """
    base=source.parent
    doc=parse(base/'DOMDocument.xml')
    bitmaps=doc.findall('./x:media/x:DOMBitmapItem',NS)
    expected={Path(row['path']).name:row for row in expected_inputs}
    if len(expected)!=len(expected_inputs):raise ValueError('Ambiguous duplicate source PNG basenames')
    media={}
    for item in bitmaps:
        name=item.get('name')
        if name in media:raise ValueError('Duplicate bitmap media name: '+name)
        png=local_file(base/'LIBRARY',item.get('href',''))
        cache=local_file(base/'bin',item.get('bitmapDataHRef',''))
        if require_policy:
            for key,value in BITMAP_POLICY.items():
                if item.get(key)!=value:raise ValueError(f'{name}: {key} must be {value}')
        with Image.open(png) as image:
            image.load()
            if image.format not in ('PNG','JPEG'):raise ValueError('Expected original PNG/JPEG native import: '+name)
            size=image.size
        if abs(float(item.get('frameRight','0'))-size[0]*20)>0.01 or abs(float(item.get('frameBottom','0'))-size[1]*20)>0.01:
            raise ValueError('Native bitmap dimensions disagree with PNG: '+name)
        fp=fingerprint(png)
        if expected:
            pinned=expected.get(png.name)
            if not pinned or fp!={key:pinned[key] for key in ('sha256','bytes')}:
                raise ValueError('Native PNG differs from pinned runtime input: '+name)
        media[name]={'png':png.relative_to(base).as_posix(),**fp,'pixels':list(size),
                     'cache':cache.relative_to(base).as_posix(),'cacheIdentity':fingerprint(cache)}
    if expected and {Path(row['png']).name for row in media.values()}!=set(expected):
        raise ValueError('Not every pinned input is in native media closure')
    symbol_names=set()
    documents=[doc]
    for include in doc.findall('./x:symbols/x:Include',NS):
        symbol=parse(local_file(base/'LIBRARY',include.get('href','')))
        symbol_names.add(symbol.getroot().get('name'))
        documents.append(symbol)
    references=0
    for tree in documents:
        for node in tree.iter():
            bitmap=node.get('bitmapPath')
            if bitmap is not None:
                references+=1
                if bitmap not in media:raise ValueError('Unresolved native bitmap fill: '+bitmap)
            ref=node.get('libraryItemName')
            if ref is None:continue
            references+=1
            allowed=media if E.QName(node).localname=='DOMBitmapInstance' else symbol_names
            if ref not in allowed:raise ValueError('Unresolved native library reference: '+ref)
    return {'xfl':str(source),'bitmapItems':len(media),'symbolItems':len(symbol_names),
            'libraryReferences':references,'media':media,'scope':'media/source PNG/cache closure; cache pixels and compiled SWF not decoded'}


def finalize(source,swf,expected_inputs=(),check=False):
    # Verify all file/source identities before mutating any XML.
    audit(source,expected_inputs,require_policy=False)
    doc=parse(source.parent/'DOMDocument.xml')
    profile=parse(source.parent/'PublishSettings.xml')
    expected={'flashFileName':swf,'defaultNames':'0','flashDefaultName':'0','flash':'1',
              'html':'0','projectorWin':'0','projectorMac':'0','gif':'0','jpeg':'0','png':'0','swc':'0'}
    for key,value in expected.items():
        node=profile.find('.//PublishFormatProperties/'+key)
        if node is None:raise ValueError('Missing CS6 publish property: '+key)
        if check:
            if node.text!=value:raise ValueError(f'{source}: {key} expected {value}')
        else:node.text=value
    for item in doc.findall('./x:media/x:DOMBitmapItem',NS):
        for key,value in BITMAP_POLICY.items():
            if check:
                if item.get(key)!=value:raise ValueError(f'{source}: {key} expected {value}')
            else:item.set(key,value)
    if not check:
        doc.write(str(source.parent/'DOMDocument.xml'),encoding='utf-8',xml_declaration=False)
        profile.write(str(source.parent/'PublishSettings.xml'),encoding='utf-8',xml_declaration=False)
    return audit(source,expected_inputs)
