from pathlib import Path
import argparse
import copy
import json
import sys

from lxml import etree as E

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import elite


def parse_frames(value):
    result = []
    for part in value.split(','):
        if '-' in part:
            first, last = (int(x) for x in part.split('-', 1))
            result.extend(range(first, last+1))
        else:
            result.append(int(part))
    return result


def render_cell(pose, atlas, frame):
    svg = E.Element('{http://www.w3.org/2000/svg}svg', nsmap={None:'http://www.w3.org/2000/svg'},
        width='400', height='400', viewBox='0 0 400 400')
    scene = E.SubElement(svg, 'g', transform='translate(200 340) scale(2) translate(4.75 -74.550107)')
    for depth, row in sorted(pose.items(), key=lambda item:int(item[0])):
        if row['id'] == 492 or row['id'] not in atlas:
            continue
        item = atlas[row['id']]
        document = E.parse(str(elite.PART_MANIFEST.parent/item['file'])).getroot()
        prefix = 'p'+str(depth)+'-'
        for element in document.iter():
            if element.get('id'):
                element.set('id', prefix+element.get('id'))
            for key, value in list(element.attrib.items()):
                if key == 'id':
                    continue
                if value.startswith('#') and not all(c in '0123456789abcdefABCDEF' for c in value[1:]):
                    element.set(key, '#'+prefix+value[1:])
                elif 'url(#' in value:
                    element.set(key, value.replace('url(#', 'url(#'+prefix))
        group = E.SubElement(scene, 'g', transform='matrix('+' '.join(map(str, row['matrix']))+')')
        for element in document:
            group.append(copy.deepcopy(element))
    label = E.Element('{http://www.w3.org/2000/svg}text', x='15', y='22', fill='#17221c')
    label.text = 'Frame '+str(frame)
    svg.append(label)
    return E.tostring(svg, encoding='unicode')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sequence', default='elite')
    parser.add_argument('--frames', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source-dir', type=Path)
    args = parser.parse_args()
    if args.sequence == 'elite':
        poses = elite.retarget_frames()
    else:
        references = json.loads(elite.REFERENCE.read_text(encoding='utf-8'))
        poses = references[args.sequence]
    frames = parse_frames(args.frames)
    atlas = {row['id']:row for row in json.loads(elite.PART_MANIFEST.read_text(encoding='utf8'))['assets']}
    cells = [render_cell(poses[frame-1], atlas, frame) for frame in frames]
    if args.source_dir:
        source_url = args.source_dir.resolve().relative_to(args.output.parent.resolve()).as_posix()
        body = ''.join('<section><div><b>3XF frame '+str(frame)+'</b><img src="'+source_url+'/'+str(frame)+'.png"></div><div>'+cell+'</div></section>'
            for frame, cell in zip(frames, cells))
        style = ('main{display:grid;grid-template-columns:repeat(2,800px);gap:2px;background:#1b2420}'
            'section{display:grid;grid-template-columns:400px 400px;background:#ece9e3}'
            'div{background:#ece9e3}svg,img{display:block;width:400px;height:400px;object-fit:contain}b{display:block;padding:8px}')
    else:
        body = ''.join(cells)
        style = ('main{display:grid;grid-template-columns:repeat(4,400px);gap:2px;background:#1b2420}'
            'div{background:#ece9e3}svg{display:block}')
    html = ('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>Elite motion preview</title>'
        '<style>body{margin:0;background:#1b2420;color:#17221c;font:16px sans-serif}'+style+'</style><main>'+body+'</main></html>')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(html, encoding='utf-8')
    print(args.output)


if __name__ == '__main__':
    main()
