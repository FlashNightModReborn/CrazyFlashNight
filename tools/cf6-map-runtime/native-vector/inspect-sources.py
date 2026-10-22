"""Read-only SVG feature census; counts include definitions, not rendered instances."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
source=ROOT/'tools/cf6-map-source/generated/map-input.json'
data=json.loads(source.read_text(encoding='utf-8'))
rows=[]
for key in sorted(data['maps']):
    for layer in data['maps'][key]['layers']:
        path=ROOT/layer['source']['svg'];root=ET.parse(path).getroot()
        counts=Counter(node.tag.split('}')[-1] for node in root.iter())
        filters=[];images=Counter();patterns=[];texts=[]
        for node in root.iter():
            tag=node.tag.split('}')[-1]
            if tag=='filter':
                filters.append({'id':node.get('id'),'attributes':dict(node.attrib),
                    'operations':[{'kind':child.tag.split('}')[-1],**child.attrib} for child in node]})
            elif tag=='image':
                ref=node.get('href') or node.get('{http://www.w3.org/1999/xlink}href') or ''
                images[ref.split(';',1)[0] if ref.startswith('data:') else 'external/reference']+=1
            elif tag=='pattern':patterns.append({'id':node.get('id'),'attributes':dict(node.attrib),'children':[child.tag.split('}')[-1] for child in node]})
            elif tag=='text':texts.append({'text':''.join(node.itertext()),'attributes':dict(node.attrib)})
        ops=sorted({op['kind'] for f in filters for op in f['operations']})
        rows.append({'map':key,'layer':layer['id'],'source':path.relative_to(ROOT).as_posix(),
                     'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,
                     'viewBox':root.get('viewBox'),'elements':dict(counts),'imagesByEncoding':dict(images),
                     'filterOperations':ops,'filters':filters,'patterns':patterns,'texts':texts,
                     'requiresNewFilterPrimitive':[op for op in ops if op not in ('feGaussianBlur','feColorMatrix','feComponentTransfer')]})
report={'schema':'cf6-native-source-feature-census.v1','mapInputSha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'scope':'raw XML count including defs; not runtime shape count, draw coverage or native conversion acceptance','layers':rows}
(HERE/'source-support-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for row in rows:
    c=row['elements'];print(row['map'],row['layer'],'primitives',sum(c.get(k,0) for k in ('path','rect','ellipse','circle','line','polygon','polyline')),
        'images',sum(row['imagesByEncoding'].values()),'newFilters',','.join(row['requiresNewFilterPrimitive']) or '-',
        'patterns',len(row['patterns']),'texts',len(row['texts']))
