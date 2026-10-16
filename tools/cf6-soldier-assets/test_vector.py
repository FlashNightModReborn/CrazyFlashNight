"""Independent affine/clip/reference cases for the soldier atlas adapter."""
from pathlib import Path
import tempfile
from lxml import etree as E
import vector

ROOT = Path(__file__).resolve().parents[2]
NS = {'x':'http://ns.adobe.com/xfl/2008/'}


def convert(directory, content):
    path = directory/'fixture.svg'
    path.write_text(content,encoding='utf8')
    vector.NativePart.shared_references = {}
    return vector.NativePart(path,'test/soldier',(0,0)).build()


def main():
    with tempfile.TemporaryDirectory(prefix='cf6-soldier-vector-',dir=ROOT/'tmp') as name:
        directory = Path(name).resolve()
        assert directory.is_relative_to((ROOT/'tmp').resolve())
        prefix = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 80 60"><defs><g id="atlas"><path d="M0 0 L10 0 L10 5 L0 5 Z" fill="#e01327"/></g><clipPath id="clip"><path d="M0 0 L8 0 L8 8 L0 8 Z"/></clipPath></defs>'
        symbols,report = convert(directory,prefix+'<use href="#atlas" x="3" y="4" transform="matrix(2 0 0 2 5 7)"/><g clip-path="url(#clip)"><use href="#atlas" transform="matrix(1 0 0 1 2 3)"/></g></svg>')
        atlas = [n for n in symbols if n.startswith('Codex/特种兵/共用矢量图集/')]
        assert len(atlas)==1, 'Repeated crops must share one vector atlas'
        instances = [i for s in symbols.values() for i in s.findall('.//x:DOMSymbolInstance',NS) if i.get('libraryItemName')==atlas[0]]
        assert len(instances)==2
        matrices = {tuple(float(i.find('x:matrix/x:Matrix',NS).get(k,str(default))) for k,default in [('a',1),('b',0),('c',0),('d',1),('tx',0),('ty',0)]) for i in instances}
        assert matrices=={(2,0,0,2,11,15),(1,0,0,1,2,3)},matrices
        assert report['masks']==1
        assert sum(len(s.findall('.//x:DOMLayer[@layerType="mask"]',NS)) for s in symbols.values())==1
        assert all(not s.findall('.//x:BitmapFill',NS) for s in symbols.values())
        transformed_clip = '<svg xmlns="http://www.w3.org/2000/svg"><defs><clipPath id="c" transform="translate(10 20)"><path d="M0 0 L8 0 L8 8 L0 8 Z" transform="translate(5 7)"/></clipPath></defs><g transform="translate(-2 -3)"><g clip-path="url(#c)"><path d="M0 0 L40 0 L40 40 L0 40 Z"/></g></g></svg>'
        symbols,_ = convert(directory,transformed_clip)
        contours = []
        for symbol in symbols.values():
            for mask in symbol.findall('.//x:DOMLayer[@layerType="mask"]',NS):
                for edge in mask.findall('.//x:Edge',NS):
                    contours.extend(vector.wings.geo.segments(edge.get('edges','')))
        assert vector.wings.geo.bounds(contours) == [13,24,21,32], vector.wings.geo.bounds(contours)
        for fragment in ['<use href="https://example.invalid/atlas.svg#x"/>','<use href="#missing"/>','<use href="#atlas" width="20"/>']:
            try:
                convert(directory,prefix+fragment+'</svg>')
            except ValueError:
                pass
            else:
                raise AssertionError('Unexpected reference accepted: '+fragment)
        nested = '<svg xmlns="http://www.w3.org/2000/svg"><defs><g id="loop"><use href="#loop"/></g></defs><use href="#loop"/></svg>'
        try:
            convert(directory,nested)
        except ValueError:
            pass
        else:
            raise AssertionError('Recursive reference accepted')
    print('PASS: shared atlas, independent affine transforms, clip ownership, pure vectors and rejected unsafe/unsupported references')


if __name__=='__main__':
    main()
