"""Apply only the six reviewed description edits; preserve XML bytes elsewhere."""
import argparse, hashlib, json, re
from pathlib import Path
import xml.etree.ElementTree as E
from xml.sax.saxutils import escape
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
SOURCE=HERE/'soldier-description-proposals.source.json'
def digest(value):return hashlib.sha256(value).hexdigest()
def without_descriptions(data):
    root=E.fromstring(data)
    for node in root.iter('description'):node.text=''
    return E.tostring(root,encoding='utf-8')
def apply(write=False):
    changes=json.loads(SOURCE.read_text('utf-8'))['changes'];files={};rows=[]
    for change in changes:
        p=ROOT/change['sourcePath']
        if p not in files:files[p]=p.read_bytes()
        raw=files[p];text=raw.decode('utf-8-sig');nl='\r\n' if '\r\n' in text else '\n'
        root=E.fromstring(raw);matches=[x for x in root.findall('item') if x.findtext('name')==change['name']]
        if len(matches)!=1:raise ValueError('Nonunique item: '+change['name'])
        item=matches[0]
        item_match=next((m for m in re.finditer(r'<item(?:\s[^>]*)?>[\s\S]*?</item>',text)
                         if re.search(r'<name>\s*'+re.escape(change['name'])+r'\s*</name>',m.group())),None)
        if item_match is None:raise ValueError('Missing exact raw item block')
        block=item_match.group()
        for update in change['updates']:
            actual=item.findtext(update['xpath'])
            if actual==update['replacementText']:continue
            if actual!=update['expectedText']:raise ValueError('Description source drift: '+change['name']+'/'+update['xpath'])
            if not write:raise ValueError('Unapplied description: '+change['name']+'/'+update['xpath'])
            old=escape(update['expectedText']).replace('\n',nl)
            new=escape(update['replacementText']).replace('\n',nl)
            if block.count(old)!=1:raise ValueError('Ambiguous description bytes: '+change['name'])
            block=block.replace(old,new,1)
        result=text[:item_match.start()]+block+text[item_match.end():]
        encoded=(b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+result.encode('utf-8')
        if without_descriptions(raw)!=without_descriptions(encoded):raise ValueError('Non-description data changed')
        files[p]=encoded
        rows.append(dict(name=change['name'],sourcePath=change['sourcePath'],paths=[u['xpath'] for u in change['updates']]))
    for p,data in files.items():
        if write and p.read_bytes()!=data:p.write_bytes(data)
    result=dict(schema='cf6-fixed-description-application.v1',status='candidate_for_acceptance',
        proposalSha256=digest(SOURCE.read_bytes()),items=rows,
        files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=digest(v),nonDescriptionSha256=digest(without_descriptions(v))) for p,v in files.items()])
    receipt=HERE/'soldier-description-application.json'
    content=(json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if write:receipt.write_bytes(content)
    elif not receipt.exists() or receipt.read_bytes()!=content:raise ValueError('Stale description application receipt')
    print(json.dumps(dict(items=len(rows),files=len(files),onlyDescriptions=True,check=not write),ensure_ascii=False))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--write',action='store_true');parser.add_argument('--check',action='store_true');args=parser.parse_args();apply(args.write)
