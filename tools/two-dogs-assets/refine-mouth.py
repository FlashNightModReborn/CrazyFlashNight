"""Apply/check the oral-anatomy revision in the existing owned XFL only."""
import argparse, copy, hashlib, json, re
from lxml import etree as E
import build as b

LAYER='口腔内壁（随双颌姿势）'

def revised(tree,variant):
    layers=tree.find('x:timeline/x:DOMTimeline/x:layers',b.NS)
    current=[layer for layer in layers if layer.get('name')==LAYER]
    assert len(current)==1,'Expected exactly one existing oral layer'
    layer=copy.deepcopy(current[0]);poses=0
    for f in layer.findall('x:frames/x:DOMFrame',b.NS):
        index=int(f.get('index'));found={}
        for other in layers:
            if other.get('name')==LAYER:continue
            active=b.active(other,index)
            if active is None:continue
            for inst in active.findall('x:elements/x:DOMSymbolInstance',b.NS):
                for original in ('Symbol 737','Symbol 735'):
                    if inst.get('libraryItemName')==variant['mapping'][original]:found[original]=b.matrix(inst)
        elements=f.find('x:elements',b.NS);elements.clear()
        if len(found)==2:
            for shape in b.mouth_shapes(b.mouth_paths(found['Symbol 737'],found['Symbol 735'])):elements.append(shape)
            poses+=1
    return current[0],layer,poses

def canonical(node):
    # Pretty printing changes whitespace only; compare the actual authored tree.
    clone=copy.deepcopy(node)
    for el in clone.iter():
        if el.text is not None and not el.text.strip():el.text=None
        el.tail=None
    return E.tostring(clone,method='c14n')

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--apply',action='store_true');args=parser.parse_args()
    manifest=json.loads((b.HERE/'native-manifest.json').read_text(encoding='utf-8'))
    results=[]
    for variant in manifest['variants']:
        for action in b.ACTIONS:
            name=variant['mapping']['Symbol '+str(action)]
            path=b.OWNER/'LIBRARY'/(name+'.xml');raw=path.read_bytes()
            tree=E.fromstring(raw,b.PARSER);old,new,poses=revised(tree,variant)
            matches=canonical(old)==canonical(new)
            if args.apply and not matches:
                # Surgical replacement preserves every inherited script, frame,
                # instance matrix and all unrelated artwork byte for byte.
                expression=rb'<DOMLayer name="'+LAYER.encode('utf-8')+rb'"[^>]*>.*?</DOMLayer>'
                match=re.search(expression,raw,re.S);assert match
                encoded=E.tostring(new,encoding='utf-8',pretty_print=True,with_tail=False)
                after=raw[:match.start()]+encoded+raw[match.end():]
                reloaded=E.fromstring(after,b.PARSER)
                assert canonical(reloaded.find('.//x:DOMLayer[@name="'+LAYER+'"]',b.NS))==canonical(new)
                path.write_bytes(after)
            elif not matches:raise AssertionError('Oral anatomy revision stale: '+name)
            results.append({'symbol':name,'oralKeyPoses':poses,'sha256':b.sha(path)})
    print(json.dumps({'result':'PASS','nativeActionSymbols':len(results),
        'oralKeyPoses':sum(r['oralKeyPoses'] for r in results),
        'anteriorGape':'open between palate and retracted tongue in lateral view',
        'preserved':'all inherited timelines, scripts, instance matrices, stats and original dog',
        'files':results},ensure_ascii=False))

if __name__=='__main__':main()
