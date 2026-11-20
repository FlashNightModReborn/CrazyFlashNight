"""Decode native RLE rows or zlib+Base64 ARGB payloads into lossless PNGs."""
from pathlib import Path
import argparse
import re
import base64
import zlib
from PIL import Image, ImageDraw


def read_trace(path):
    raw=path.read_bytes()
    try:
        return raw.decode('utf-8-sig')
    except UnicodeDecodeError:
        # CS6 may prepend an ANSI warning to the debugger's UTF-8 trace.
        # Decode each complete line strictly; never replace damaged payload bytes.
        lines=[]
        for line in raw.splitlines():
            try:lines.append(line.decode('utf-8-sig'))
            except UnicodeDecodeError:lines.append(line.decode('gb18030'))
        return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('trace', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--continuation', type=Path, action='append', default=[],
        help='Additional original traces from the same asset; all image keys must remain unique')
    parser.add_argument('--skip-primary-prefix', action='append', default=[],
        help='Replace this subset from the first trace with complete captures from a continuation')
    parser.add_argument('--allow-partial', action='store_true',
        help='Decode complete captured images only; diagnostic subset, never acceptance evidence')
    args = parser.parse_args()
    texts=[]
    for index,path in enumerate([args.trace, *args.continuation]):
        lines=read_trace(path).splitlines()
        if index==0 and args.skip_primary_prefix:
            def keep(line):
                record=re.match(r'\[SOLDIER_(?:IMAGE_BEGIN|IMAGE_ROW|IMAGE_B64|IMAGE_END|NATIVE_PIXELS)\] (\S+)',line)
                return not record or not any(record[1].startswith(prefix) for prefix in args.skip_primary_prefix)
            lines=[line for line in lines if keep(line)]
        texts.append('\n'.join(lines))
    trace_text = '\n'.join(texts)
    captures, completed, native_pixels, protocol = {}, set(), {}, None
    for line in trace_text.splitlines():
        if line.startswith('[SOLDIER_CAPTURE_PROTOCOL] '):
            scheme = line.rsplit(' ', 1)[1]
            if scheme not in ('region-rle-v2', 'zlib-base64-v3') or protocol not in (None, scheme):
                raise ValueError('Conflicting or unknown capture protocol: ' + scheme)
            protocol = scheme
            continue
        pixel_match = re.fullmatch(r'\[SOLDIER_NATIVE_PIXELS\] (.+) (\d+)', line)
        if pixel_match:
            if pixel_match[1] in native_pixels and native_pixels[pixel_match[1]] != int(pixel_match[2]):
                raise ValueError('Conflicting native pixel coverage: ' + pixel_match[1])
            native_pixels[pixel_match[1]] = int(pixel_match[2])
        match = re.fullmatch(r'\[SOLDIER_IMAGE_BEGIN\] (.+?) (\d+) (\d+)', line)
        if match:
            name, width, height = match.groups()
            if name in captures:
                raise ValueError('Repeated image: ' + name)
            captures[name] = {'width': int(width), 'height': int(height), 'rows': {}, 'chunks': []}
            continue
        match = re.fullmatch(r'\[SOLDIER_IMAGE_B64\] (.+?) (\d+) ([A-Za-z0-9+/=]+)', line)
        if match:
            name, index, chunk = match.groups()
            if protocol != 'zlib-base64-v3' or name not in captures or name in completed:
                raise ValueError('Unexpected packed image chunk')
            if int(index) != len(captures[name]['chunks']):
                raise ValueError('Out-of-order packed image chunk: ' + name)
            captures[name]['chunks'].append(chunk)
            continue
        match = re.fullmatch(r'\[SOLDIER_IMAGE_ROW\] (.+?) (\d+) (.*)', line)
        if match:
            name, y, encoded = match.groups()
            item, row = captures[name], []
            if int(y) in item['rows'] or name in completed:
                raise ValueError('Repeated or late image row')
            for token in encoded.split(','):
                value, count = token.split(':')
                if not re.fullmatch('[0-9a-f]{8}', value) or not 0 < int(count) <= item['width']:
                    raise ValueError('Invalid RGBA run')
                color = int(value, 16)
                row.extend([(color >> 16 & 255, color >> 8 & 255, color & 255, color >> 24 & 255)] * int(count))
            if len(row) != item['width']:
                raise ValueError('Wrong image row width')
            item['rows'][int(y)] = row
        match = re.fullmatch(r'\[SOLDIER_IMAGE_END\] (.+?)', line)
        if match:
            name = match[1]
            if name not in captures or name in completed:
                raise ValueError('Repeated or unexpected image end')
            if protocol == 'zlib-base64-v3':
                item = captures[name]
                try:
                    raw = zlib.decompress(base64.b64decode(''.join(item['chunks']), validate=True))
                except Exception as error:
                    raise ValueError('Invalid packed image: ' + name) from error
                if len(raw) != item['width'] * item['height'] * 4:
                    raise ValueError('Wrong packed image dimensions: ' + name)
                for y in range(item['height']):
                    row = []
                    for x in range(item['width']):
                        offset = (y * item['width'] + x) * 4
                        row.append((raw[offset+1], raw[offset+2], raw[offset+3], raw[offset]))
                    item['rows'][y] = row
            completed.add(name)
    expected = {'stand', 'shoot', 'knife', 'down', 'death-start', 'death-a0-middle',
                'death-a0-late', 'death-a1-middle', 'death-a1-late', 'death-a2-late', 'airborne-shadow',
                'rifle-M4A1改','rifle-AK74战术版','rifle-DD MK18战术版','rifle-AK47','reload'}
    shield = {'shield-'+pose+'-'+str(side) for pose in ('stand','shoot','knife') for side in (0,1)}
    shield |= {'shield-break-'+str(side)+'-'+mode for side in (0,1) for mode in ('break','breakReload')}
    elite = {'elite-'+pose+'-'+str(side) for pose in ('stand','retreat','slide','reload','break',
        'retreat-fire','slide-low','slide-tail','sidearmReload','sidearmInterrupt','noSidearm') for side in (0,1)}
    motion = {'elite-motion-'+pose+'-0-'+str(frame) for pose,first,last in
        [('stand',46,77),('retreat',2,44),('slide',166,248)]
        for frame in range(first,last+1)}
    accepted_sets = (expected, shield, elite, elite | motion, expected | shield, expected | shield | elite, expected | shield | elite | motion)
    holsters = {'holster-'+pose+'-'+str(side) for pose in
        ('ordinary','idle-stand','idle-externalPair','idle-break','primaryReload','interrupted') for side in (0,1)}
    accepted_sets += tuple(selected | holsters for selected in accepted_sets if selected != shield)
    sequence_rows=re.findall(r'\[ELITE_PAIR_CAPTURE_SEQUENCE\] side=([01]) frames=([0-9,]+)', trace_text)
    if sequence_rows:
        if len(sequence_rows)!=2 or {side for side,_ in sequence_rows}!={'0','1'}:
            raise ValueError('Incomplete paired reload sequence declarations')
        pair_reload={'elite-pair-mixed-'+str(side) for side in (0,1)}
        for side,raw_frames in sequence_rows:
            sequence=[int(value) for value in raw_frames.split(',')]
            if sequence!=sorted(set(sequence)) or not 331<=sequence[0]<=333 or not 363<=sequence[-1]<=365:
                raise ValueError('Invalid paired reload sequence')
            if not {351,363}.issubset(sequence):
                raise ValueError('Missing paired reload gate or simultaneous commit frame')
            if side=='0' and any(b-a>3 for a,b in zip(sequence,sequence[1:])):
                raise ValueError('Gap in actual-speed paired reload capture')
            pair_reload|={'elite-pair-motion-'+side+'-'+str(frame) for frame in sequence}
        accepted_sets+=(pair_reload,)
    review_rows=re.findall(r'\[R8_REVIEW_EXPECTED\] (\d+)', trace_text)
    if review_rows:
        review_specs=[('ordinary-run',1,24),('elite-run',1,24),('ordinary-throw',1,36),
            ('ordinary-bash',35,68),('ordinary-stab',1,34),('shield-cover',1,20),
            ('elite-charge',1,46),('elite-pair',331,365),('death-new',105,139),('shield-break',1,11)]
        review={'r8review-'+name+'-'+str(frame) for name,first,last in review_specs for frame in range(first,last+1)}
        if review_rows!=[str(len(review))]:
            raise ValueError('Invalid R8 review capture declaration')
        accepted_sets+=(review,)
    r9_rows=re.findall(r'\[R9_REVIEW_EXPECTED\] (\d+)', trace_text)
    if r9_rows:
        specs=[('ordinary-run',1,24),('ordinary-throw',1,36),('ordinary-bash',35,68),
            ('ordinary-stab',1,34),('shield-cover',1,20),('elite-charge',1,46),('elite-reload',331,365),
            ('elite-retreat',2,44),('elite-slide',166,248),('instructor-run',1,24),
            ('instructor-throw',1,36),('instructor-bash',35,68),('instructor-charge',1,46),('instructor-retreat',2,44)]
        review={'r9review-'+name+'-'+str(frame) for name,first,last in specs for frame in range(first,last+1)}
        # Historical R9 captures ended the shield bash at frame 68.
        if r9_rows==[str(len(review)+25)]:
            review.update('r9review-instructor-bash-'+str(frame) for frame in range(69,94))
        if any(value!=str(len(review)) for value in r9_rows):raise ValueError('Invalid R9 review capture declaration')
        review|={'r9scene-smoke-'+str(frame) for frame in range(190,361,2)}
        accepted_sets+=(review,)
    r10_rows=re.findall(r'\[R10_SCENE_EXPECTED\] (\d+)', trace_text)
    if r10_rows:
        review={'r10scene-'+name+'-'+str(frame) for name in ('chargeNear','evasion') for frame in range(190,271,2)}
        if r10_rows!=[str(len(review))]:raise ValueError('Invalid R10 scene capture declaration')
        accepted_sets+=(review,)
    r12_http=re.findall(r'\[SOLDIER_IMAGE_HTTP\] (r12scene-\S+)', trace_text)
    if r12_http:
        review={'r12scene-'+name+'-'+str(frame) for name in
            ('instructorLine','instructorBareLine','smoke','run','evasion','retreatBlocked')
            for frame in range(190,279,2)}
        if len(r12_http)!=len(review) or set(r12_http)!=review:
            raise ValueError('Incomplete or repeated R12 HTTP capture acknowledgements')
        accepted_sets+=(review,)
    r13_http=re.findall(r'\[SOLDIER_IMAGE_HTTP\] (r13scene-\S+)', trace_text)
    if r13_http:
        review={f'r13scene-{name}-{frame}' for name,last in
            (('chargeNear',250),('instructorShieldClose',320),('instructorChargeClose',320))
            for frame in range(190,last+1,2)}
        # Accept frozen historical captures and the full longer authored recovery.
        if 'r13scene-instructorShieldClose-344' in r13_http:
            review.update(f'r13scene-instructorShieldClose-{frame}' for frame in range(322,346,2))
        if len(r13_http)!=len(review) or set(r13_http)!=review:
            raise ValueError('Incomplete or repeated R13 HTTP capture acknowledgements')
        accepted_sets+=(review,)
    instructor_rows=re.findall(r'\[INSTRUCTOR_MELEE_REVIEW\] (\d+)',trace_text)
    instructor_boxes={}
    if instructor_rows:
        review={f'instructor-{mode}-{frame}' for mode,last in (('A',34),('B',59)) for frame in range(1,last+1)}
        sent=re.findall(r'\[SOLDIER_IMAGE_HTTP\] (instructor-\S+)',trace_text)
        if instructor_rows!=[str(len(review))] or len(sent)!=len(review) or set(sent)!=review:
            raise ValueError('Incomplete or repeated instructor melee capture')
        for key,x1,y1,x2,y2 in re.findall(r'^\[INSTRUCTOR_MELEE_OVERLAY\] (\S+) (\d+) (\d+) (\d+) (\d+)\r?$',trace_text,re.M):
            if key in instructor_boxes:
                raise ValueError('Duplicate projected contact box: '+key)
            instructor_boxes[key]=tuple(map(int,(x1,y1,x2,y2)))
        if set(instructor_boxes)!={'instructor-A-14','instructor-B-17'}:
            raise ValueError('Missing live contact-frame projection')
        accepted_sets+=(review,)
    if (completed not in accepted_sets or set(captures) != completed) and not args.allow_partial:
        raise ValueError('Expected the complete selected fixed-scale Soldier capture set: ' + str(completed))
    if completed not in accepted_sets or set(captures) != completed:
        print('WARNING: diagnostic subset only; not acceptance evidence; images=' + str(len(completed)))
    args.output.mkdir(parents=True, exist_ok=True)
    for name, item in captures.items():
        if name not in completed:
            continue
        if set(item['rows']) != set(range(item['height'])):
            raise ValueError('Incomplete image: ' + name)
        pixels = sum(item['rows'][y][x][:3] != (232,230,226)
            for y in range(0,item['height'],3) for x in range(0,item['width'],3))
        if protocol == 'region-rle-v2' and (name not in native_pixels or pixels != native_pixels[name]):
            raise ValueError('Decoded raster differs from native pixel coverage: ' + name)
        image = Image.new('RGBA', (item['width'], item['height']))
        image.putdata([pixel for y in range(item['height']) for pixel in item['rows'][y]])
        if name in instructor_boxes:
            x1,y1,x2,y2=instructor_boxes[name]
            if not (0<=x1<x2<image.width and 0<=y1<y2<image.height):
                raise ValueError('Invalid projected contact rectangle: '+name)
            ink=(17,122,82,255)
            ImageDraw.Draw(image).rectangle((x1,y1,x2,y2),outline=ink,width=2)
        target = args.output / (name + '.png')
        if target.exists():
            raise ValueError('Preserve the existing capture: ' + str(target))
        image.save(target)
        if name in instructor_boxes:
            with Image.open(target) as saved:
                border=([(x,y) for x in range(x1,x2+1) for y in (y1,y2)]
                        +[(x,y) for y in range(y1,y2+1) for x in (x1,x2)])
                if any(saved.getpixel(pixel)!=ink for pixel in border):
                    raise ValueError('PNG lacks the complete native contact outline: '+name)
    print('Decoded native Flash captures: ' + ', '.join(sorted(completed)))


if __name__ == '__main__':
    main()
