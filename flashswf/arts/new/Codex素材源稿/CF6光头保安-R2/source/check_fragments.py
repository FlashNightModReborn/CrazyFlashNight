#!/usr/bin/env python3
"""Read-only artwork coverage audit of every bald-guard death/transform bitmap581 fill.

Usage: python source/check_fragments.py [--scale 16] [--workers 4]
       python source/check_fragments.py --review-flagged --scale 64
Requires Inkscape, Pillow, numpy, scipy. Writes only qa/fragment-coverage/.
Each source fill and its vector counterpart use the exact same original path,
bitmap matrix, shape viewBox and raster dimensions. This is not a pixel-equality
check: head contour redesign can change edge coverage legitimately.
"""
from pathlib import Path
import argparse, base64, concurrent.futures, hashlib, json, math, subprocess
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
import fragment_context as b

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/fragment-coverage'
STRUCTURE = np.ones((3, 3), bool)


def isolated_svg(cid, fill, original):
    v = b.S[cid]['viewBox']
    prefix = f'qa_d{cid}_f{fill["fillIndex"]}_'
    atid, clip = prefix + 'atlas581', prefix + 'clip'
    if original:
        data = base64.b64encode((ROOT / 'reference/581.png').read_bytes()).decode()
        atlas = f'<image id="{atid}" width="385" height="321" href="data:image/png;base64,{data}"/>'
    else:
        atlas = f'<g id="{atid}">{b.atlas(prefix)}</g>'
    return (f'<svg xmlns="{b.NS}" width="{v[2]}" height="{v[3]}" viewBox="{" ".join(map(str, v))}">'
            f'<defs>{atlas}<clipPath id="{clip}"><path d="{fill["path"]}"/></clipPath></defs>'
            f'<g clip-path="url(#{clip})"><use href="#{atid}" transform="{b.mat(fill["matrix"])}"/></g></svg>')


def render_one(job):
    cid, fill, original, scale = job
    name = f'{cid}-fill{fill["fillIndex"]}-' + ('original' if original else 'vector')
    svg, png = OUT / f'{name}.svg', OUT / f'{name}.png'
    svg.write_text(isolated_svg(cid, fill, original))
    v = b.S[cid]['viewBox']
    subprocess.run(['inkscape', str(svg), '--export-type=png', '--export-area-page',
                    f'--export-width={round(v[2]*scale)}', f'--export-height={round(v[3]*scale)}',
                    '--export-background-opacity=0', f'--export-filename={png}'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    return name


def regions(mask, pixel_area):
    lab, n = ndi.label(mask, STRUCTURE)
    result = []
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        if sl is None:
            continue
        area = int(np.count_nonzero(lab[sl] == i))
        result.append({'label': i, 'pixels': area, 'areaLocalPx2': area * pixel_area,
                       'bboxRaster': [sl[1].start, sl[0].start, sl[1].stop, sl[0].stop]})
    return lab, result


def local_bbox(box, v, sx, sy):
    x0, y0, x1, y1 = box
    return [v[0] + x0/sx, v[1] + y0/sy, v[0] + x1/sx, v[1] + y1/sy]


def analyze(cid, fill):
    stem = f'{cid}-fill{fill["fillIndex"]}'
    original = np.asarray(Image.open(OUT / f'{stem}-original.png').convert('RGBA'))
    vector = np.asarray(Image.open(OUT / f'{stem}-vector.png').convert('RGBA'))
    assert original.shape == vector.shape
    oa, va = original[..., 3], vector[..., 3]
    v = b.S[cid]['viewBox']; sy, sx = oa.shape[0]/v[3], oa.shape[1]/v[2]
    pixel_area = 1/(sx*sy)
    # Alpha64 suppresses nearly transparent interpolation fringes. All alpha>0
    # counts are still retained, as are every component's statistics.
    om, vm = oa >= 64, va >= 64
    olab, ocs = regions(om, pixel_area)
    _, vcs = regions(vm, pixel_area)
    for c in ocs:
        mask = olab == c['label']
        overlap = int(np.count_nonzero(mask & vm))
        any_overlap = int(np.count_nonzero(mask & (va > 0)))
        c.update(overlapVectorPixels=overlap, overlapVectorFraction=overlap/c['pixels'],
                 anyAlphaOverlapVectorPixels=any_overlap, absentFromVector=any_overlap == 0,
                 bboxLocal=local_bbox(c['bboxRaster'], v, sx, sy))
    threshold_audit = {}
    for threshold in (1, 16, 64, 128, 224):
        labels, count = ndi.label(oa >= threshold, STRUCTURE)
        present = set(np.unique(labels[va > 0]).tolist())
        missing = [i for i in range(1, count + 1) if i not in present]
        threshold_audit[str(threshold)] = {'sourceComponents': count, 'absentComponents': len(missing),
            'absentComponentPixels': [int(np.count_nonzero(labels == i)) for i in missing]}
    # A new transparent hole must be enclosed by the candidate silhouette;
    # source pixels already transparent do not count as newly lost coverage.
    oh = ndi.binary_fill_holes(om, structure=STRUCTURE) & ~om
    vh = ndi.binary_fill_holes(vm, structure=STRUCTURE) & ~vm
    hlabel, holes = regions(vh, pixel_area)
    for hole in holes:
        mask = hlabel == hole['label']
        lost = int(np.count_nonzero(mask & om))
        hole.update(sourceOpaquePixels=lost, newHoleAreaLocalPx2=lost*pixel_area,
                    bboxLocal=local_bbox(hole['bboxRaster'], v, sx, sy))
    # Interior losses are diagnostic only: an intentional contour redraw can
    # create an open notch rather than an enclosed hole.
    dist = ndi.distance_transform_edt(om, sampling=(1/sy, 1/sx))
    lost_core = (dist >= .5) & (va < 16)
    _, lost_regions = regions(lost_core, pixel_area)
    for region in lost_regions:
        region['bboxLocal'] = local_bbox(region['bboxRaster'], v, sx, sy)
    area_o, area_v = float(oa.sum()/255*pixel_area), float(va.sum()/255*pixel_area)
    absent = [c for c in ocs if c['absentFromVector']]
    flags = []
    if np.any(oa) and not np.any(va): flags.append('ENTIRE_FILL_EMPTY')
    if absent: flags.append('SOURCE_COMPONENT_ABSENT')
    if any(h['newHoleAreaLocalPx2'] >= .02 for h in holes): flags.append('NEW_ENCLOSED_TRANSPARENT_HOLE')
    if area_o and area_v/area_o < .90: flags.append('VISIBLE_AREA_LOSS_GT_10_PERCENT')
    if sum(r['areaLocalPx2'] for r in lost_regions) >= .02: flags.append('INTERIOR_LOSS_REVIEW')
    result = {
        'shapeId': cid, 'fillIndex': fill['fillIndex'], 'viewBox': v,
        'bitmapMatrix': fill['matrix'], 'rasterSize': [oa.shape[1], oa.shape[0]],
        'pixelsPerLocalPixel': [sx, sy], 'sourceAnyAlphaPixels': int(np.count_nonzero(oa)),
        'vectorAnyAlphaPixels': int(np.count_nonzero(va)),
        'sourceVisibleAreaLocalPx2': area_o, 'vectorVisibleAreaLocalPx2': area_v,
        'visibleAreaRatio': area_v/area_o if area_o else None,
        'sourceComponents': ocs, 'alphaThresholdAudit': threshold_audit, 'vectorComponentCountAlpha64': len(vcs),
        'sourceHoleCountAlpha64': int(ndi.label(oh, STRUCTURE)[1]), 'vectorHoles': holes,
        'sourceComponentsAbsent': len(absent), 'lostInteriorRegions': lost_regions,
        'flags': flags, 'originalImage': str((OUT / f'{stem}-original.png').relative_to(ROOT)),
        'vectorImage': str((OUT / f'{stem}-vector.png').relative_to(ROOT))}
    if flags:
        # Same union crop in all columns: source, candidate, coverage difference.
        union = (oa > 0) | (va > 0)
        if union.any():
            yy, xx = np.where(union)
            box = (max(0,int(xx.min())-10), max(0,int(yy.min())-10),
                   min(oa.shape[1],int(xx.max())+11), min(oa.shape[0],int(yy.max())+11))
        else: box = (0,0,oa.shape[1],oa.shape[0])
        ims = [Image.fromarray(original).crop(box), Image.fromarray(vector).crop(box)]
        diff = np.zeros_like(original); diff[...,3] = 255
        diff[om & vm] = [120,120,120,255]
        diff[om & ~vm] = [255,70,60,255]
        diff[vm & ~om] = [50,190,255,255]
        ims.append(Image.fromarray(diff).crop(box))
        w,h=ims[0].size
        enlargement = max(1, math.ceil(100 / max(w, h)))
        if enlargement > 1:
            ims = [im.resize((w*enlargement, h*enlargement), Image.Resampling.NEAREST) for im in ims]
            w,h = ims[0].size
        board=Image.new('RGB',(max(550,w*3+40),h+70),(245,245,240)); draw=ImageDraw.Draw(board)
        draw.text((10,5),f'{stem} | source / vector / lost(red), gained(blue)',fill='black')
        draw.text((10,23),f'Area ratio: {area_v/area_o:.4f}; absent components: {len(absent)}',fill='black')
        for k,im in enumerate(ims):
            bg=Image.new('RGBA', im.size,(225,225,225,255)); bg.alpha_composite(im)
            board.paste(bg.convert('RGB'),(10+k*(w+10),55))
        crop = OUT / f'{stem}-comparison.png'; board.save(crop)
        result['comparisonCrop'] = str(crop.relative_to(ROOT))
    return result


def main():
    global OUT
    p=argparse.ArgumentParser(); p.add_argument('--scale',type=int,default=8);p.add_argument('--workers',type=int,default=4)
    p.add_argument('--skip-render',action='store_true'); p.add_argument('--review-flagged',action='store_true'); args=p.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    fills=[(cid,f) for cid,sh in b.S.items() if cid in (601,602,603,880,882,883,884,885,886) for f in sh['fills'] if f['type']=='bitmap']
    assert len(fills)==181
    if args.review_flagged:
        initial=json.loads((OUT/'report.json').read_text())
        selected={(r['shapeId'],r['fillIndex']) for r in initial['fills'] if r['flags']}
        fills=[(cid,f) for cid,f in fills if (cid,f['fillIndex']) in selected]
        OUT=OUT/f'review-{args.scale}x'; OUT.mkdir(parents=True,exist_ok=True)
    if not args.skip_render:
        jobs=[(cid,f,orig,args.scale) for cid,f in fills for orig in (True,False)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
            for n, _ in enumerate(ex.map(render_one,jobs),1):
                if n%40==0: print(f'Rendered {n}/{len(jobs)}',flush=True)
    results=[analyze(cid,f) for cid,f in fills]
    summary={
        'totalBitmapFills':len(results),'mixedShapes':len(set(r['shapeId'] for r in results)),
        'sourceNonemptyFills':sum(r['sourceAnyAlphaPixels']>0 for r in results),
        'vectorNonemptyFills':sum(r['vectorAnyAlphaPixels']>0 for r in results),
        'sourceAlpha64Components':sum(len(r['sourceComponents']) for r in results),
        'absentSourceComponents':sum(r['sourceComponentsAbsent'] for r in results),
        'fillsWithAbsentComponents':sum(bool(r['sourceComponentsAbsent']) for r in results),
        'fillsWithNewEnclosedHole':sum('NEW_ENCLOSED_TRANSPARENT_HOLE' in r['flags'] for r in results),
        'fillsWithAreaLossOver10Percent':sum('VISIBLE_AREA_LOSS_GT_10_PERCENT' in r['flags'] for r in results),
        'fillsWithInteriorLoss':sum('INTERIOR_LOSS_REVIEW' in r['flags'] for r in results),
        'minVisibleAreaRatio':min(r['visibleAreaRatio'] for r in results if r['visibleAreaRatio'] is not None),
        'maxVisibleAreaRatio':max(r['visibleAreaRatio'] for r in results if r['visibleAreaRatio'] is not None),
        'alphaThresholdAudit':{str(t):{'sourceComponents':sum(r['alphaThresholdAudit'][str(t)]['sourceComponents'] for r in results),
            'absentComponents':sum(r['alphaThresholdAudit'][str(t)]['absentComponents'] for r in results)} for t in (1,16,64,128,224)}}
    report={'method':'Isolated original bitmap and live-vector atlas fills, identical exact source paths/matrices/viewBoxes, Inkscape rasterized. Alpha64 components; absence requires no alpha>0 candidate overlap. Holes >=0.02 local pixels squared. Interior losses >=0.5 local pixel from source alpha64 boundary are review flags, not proof of accidental defects. All measurements retained.',
            'scale':args.scale,'inkscapeVersion':subprocess.check_output(['inkscape','--version'],text=True).strip(),
            'inputHashes':{str(x.relative_to(ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted((ROOT/'parts').glob('*.svg'))+list((ROOT/'reference').glob('shape-manifest.json'))+list((ROOT/'reference').glob('581.png'))},
            'summary':summary,'fills':results}
    (OUT/'report.json').write_text(json.dumps(report,indent=2))
    crops=[OUT/Path(r['comparisonCrop']).name for r in results if 'comparisonCrop' in r]
    if crops:
        panels=[Image.open(x).convert('RGB') for x in crops]
        target_width=700
        panels=[im.resize((target_width,round(im.height*target_width/im.width)), Image.Resampling.LANCZOS) for im in panels]
        board=Image.new('RGB',(target_width,sum(im.height for im in panels)+10*(len(panels)-1)),(245,245,240))
        y=0
        for im in panels: board.paste(im,(0,y)); y+=im.height+10
        board.save(OUT/'flagged-comparison-sheet.png')
    print(json.dumps(summary,indent=2),flush=True)
    for r in sorted(results,key=lambda r:r['visibleAreaRatio'] if r['visibleAreaRatio'] is not None else 100)[:20]:
        print(r['shapeId'],r['fillIndex'],round(r['visibleAreaRatio'],4),r['flags'],flush=True)

if __name__=='__main__': main()
