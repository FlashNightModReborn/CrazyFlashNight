# -*- coding: utf-8 -*-
"""汇总审计：levels 背景实例覆盖度 + 环境 XML 一致性 + backgrounds 体量/孤儿。"""
import json, os, xml.etree.ElementTree as ET

# 仓库根 = 本脚本所在 tools/swf-audit/ 的上两级
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
def P(*a): return os.path.join(ROOT, *a)

levels = json.load(open(P('tmp/bg-audit/scan_levels.json'), encoding='utf-8'))
bgs    = json.load(open(P('tmp/bg-audit/scan_bg.json'), encoding='utf-8'))
bgfiles = {b['file'] for b in bgs}
skyfiles = {fn for fn in os.listdir(P('flashswf/skybox')) if fn.lower().endswith('.swf')}

refcount = {}
for line in open(P('tmp/bg-audit/swf_refs.txt'), encoding='utf-8'):
    line = line.strip()
    if not line: continue
    c, _, tok = line.partition(' ')
    try: refcount[tok.strip()] = int(c)
    except: pass

# 同一 <Environment> 内允许出现多次的子标签
REPEATABLE = {'Collision', 'Skybox', 'Door', 'LeftSpawnLine', 'RightSpawnLine'}
CORE6 = ('Xmin', 'Xmax', 'Ymin', 'Ymax', 'Width', 'Height')

out = []
def w(s=''): out.append(s)
def num(v):
    try: return float(v)
    except: return None

def parse_env(path):
    envs = []
    for env in ET.parse(path).getroot().findall('Environment'):
        tags = [c.tag for c in env]
        d = {}
        for c in env:
            d.setdefault(c.tag, []).append((c.text or '').strip())
        dup = sorted({t for t in tags if tags.count(t) > 1 and t not in REPEATABLE})
        envs.append({'dup': dup, 'd': d})
    return envs

def audit_env(path, label, is_stage):
    w('## %s' % label)
    w('文件: %s   共 %d 个 <Environment>' %
      (os.path.relpath(path, ROOT).replace('\\', '/'), 0))
    envs = parse_env(path)
    out[-1] = out[-1].rsplit('共', 1)[0] + '共 %d 个 <Environment>' % len(envs)
    dup_problems, geom_problems, ref_problems = [], [], []
    seen_bg, missing_core = {}, []
    for i, e in enumerate(envs):
        d = e['d']
        bg = (d.get('BackgroundURL', ['']) or [''])[0]
        tag = bg or '(无BackgroundURL 第%d个)' % (i + 1)
        if e['dup']:
            dup_problems.append('  %-26s 重复单值标签: %s' % (tag, ', '.join(e['dup'])))
        if not bg:
            ref_problems.append('  第 %d 个 Environment 缺 BackgroundURL' % (i + 1))
        else:
            seen_bg.setdefault(bg, []).append(i + 1)
        miss = [f for f in CORE6 if f not in d]
        if len(miss) == 6:
            missing_core.append(tag)
        elif miss:
            geom_problems.append('  %-26s 缺字段: %s' % (tag, ', '.join(miss)))
        xmin, xmax = num(d.get('Xmin',[''])[0]), num(d.get('Xmax',[''])[0])
        ymin, ymax = num(d.get('Ymin',[''])[0]), num(d.get('Ymax',[''])[0])
        wd, ht = num(d.get('Width',[''])[0]), num(d.get('Height',[''])[0])
        if xmin is not None and xmax is not None and xmin >= xmax:
            geom_problems.append('  %-26s Xmin>=Xmax (%s,%s)' % (tag, xmin, xmax))
        if ymin is not None and ymax is not None and ymin >= ymax:
            geom_problems.append('  %-26s Ymin>=Ymax (%s,%s)' % (tag, ymin, ymax))
        if xmax is not None and wd is not None and xmax > wd + 1:
            geom_problems.append('  %-26s Xmax(%s) > Width(%s)' % (tag, xmax, wd))
        if ymax is not None and ht is not None and ymax > ht + 1:
            geom_problems.append('  %-26s Ymax(%s) > Height(%s)' % (tag, ymax, ht))
    for bg, idxs in seen_bg.items():
        if len(idxs) > 1:
            ref_problems.append('  重复 BackgroundURL: %s (第 %s 个 Environment)' % (bg, idxs))
    if is_stage:
        for bg in seen_bg:
            if bg and bg not in bgfiles:
                ref_problems.append('  引用背景文件不存在: %s' % bg)

    w('· 重复单值标签 (%d):' % len(dup_problems))
    for p in dup_problems: w(p)
    w('· 几何字段问题 (%d):' % len(geom_problems))
    for p in geom_problems: w(p)
    w('· 引用问题 (%d):' % len(ref_problems))
    for p in ref_problems: w(p)
    if missing_core:
        w('· 仅有 BackgroundURL（无任何 Xmin/Xmax/Ymin/Ymax/Width/Height）的条目: %d 个' % len(missing_core))
        w('  ' + '  '.join(missing_core[:12]) + (' ...' if len(missing_core) > 12 else ''))
    w('')
    return envs

w('=' * 80)
w('CrazyFlashNight  地图 / 背景层  审计报告')
w('=' * 80); w('')

scene_envs = audit_env(P('data/environment/scene_environment.xml'), 'scene_environment.xml （室内/外部场景）', False)
stage_envs = audit_env(P('data/environment/stage_environment.xml'), 'stage_environment.xml （关卡背景）', True)

# Skybox 文件存在性（位于 flashswf/skybox/）
w('## Skybox 引用文件存在性')
sroot = ET.parse(P('data/environment/scene_environment.xml')).getroot()
sky_miss = 0
for env in sroot.findall('Environment'):
    bg = (env.findtext('BackgroundURL') or '').strip()
    for sb in env.findall('Skybox'):
        u = (sb.findtext('url') or '').strip()
        if u and u not in skyfiles:
            sky_miss += 1
            w('  缺失: %s  (被 %s 引用)' % (u, bg))
w('  flashswf/skybox/ 共 %d 个 SWF；scene_environment 引用全部存在' % len(skyfiles)
  if sky_miss == 0 else '  缺失 %d 个' % sky_miss)
w('')

# ---------- levels 背景实例覆盖度 ----------
scene_width = {}
for env in sroot.findall('Environment'):
    bg = (env.findtext('BackgroundURL') or '').strip()
    wd = env.findtext('Width')
    if bg and wd:
        try: scene_width[bg] = int(float(wd))
        except: pass

w('## flashswf/levels 背景实例覆盖度（卡顿优化核心）')
w('判定: 地图 SWF 是否含实例名为「背景」的 PlaceObject —— 决定 _root.贴背景图()')
w('能否把背景烤进 deadbody 位图并 unloadMovie 释放矢量内存。无此实例 = 背景矢量常驻 = 卡顿源。')
w('')
ready, needwork = [], []
w('%-22s %-6s %-8s %-8s %-7s %s' % ('地图SWF', '背景实例', 'deadbody', '场景宽度', 'shapes', '判定'))
w('-' * 74)
for m in sorted(levels, key=lambda x: x['file']):
    names = m.get('names') or []
    hb, hd = '背景' in names, 'deadbody' in names
    base = m['file'][:-4] if m['file'].lower().endswith('.swf') else m['file']
    sw = scene_width.get(base, '-')
    note = '' if hd else '  (无deadbody,需复核)'
    if hb:
        ready.append((base, sw, m.get('shapes', 0)))
        verdict = '就绪' + note
    else:
        needwork.append((base, sw, m.get('shapes', 0)))
        verdict = '需施工'
    w('%-22s %-6s %-8s %-8s %-7s %s' %
      (base, '有' if hb else '无', '有' if hd else '无', sw, m.get('shapes', 0), verdict))
w('')
w('就绪 %d / 需施工 %d (共 %d 个地图 SWF)' % (len(ready), len(needwork), len(levels)))
w('')
w('### 需施工地图 — 按场景宽度降序（宽度越大矢量背景越重，卡顿优先级越高）')
def sk(t): return t[1] if isinstance(t[1], int) else -1
for base, sw, sh in sorted(needwork, key=sk, reverse=True):
    flag = '   <== 大图优先(>=1600)' if isinstance(sw, int) and sw >= 1600 else ''
    w('  %-22s 场景宽度=%-7s shapes=%-5s%s' % (base, sw, sh, flag))
w('')

# ---------- backgrounds ----------
w('## flashswf/backgrounds 体量与引用审计')
good = [b for b in bgs if not b.get('error')]
errs = [b for b in bgs if b.get('error')]
tot = sum(b['bytes'] for b in good)
w('共扫描 %d 个 SWF（含 elements/），合计 %.1f MB，解析失败 %d 个' %
  (len(bgs), tot/1048576.0, len(errs)))
for b in errs:
    w('  解析失败: %s — %s' % (b['file'], b.get('error')))
w('')
orphans = [b for b in good if refcount.get(b['file'], 0) == 0]
w('### 疑似孤儿背景 — 文件名未在 data/ scripts/ levels-DOM 中出现: %d 个' % len(orphans))
w('（注意：若代码按 "前缀"+序号+".swf" 动态拼接文件名，则此处可能误报，需人工确认）')
for b in sorted(orphans, key=lambda x: -x['bytes']):
    w('  %-32s %9d B  %5dx%-5d shapes=%-4d' %
      (b['file'], b['bytes'], int(b['w']), int(b['h']), b['shapes']))
w('')
w('### 体量最大的 20 个背景')
for b in sorted(good, key=lambda x: -x['bytes'])[:20]:
    ref = refcount.get(b['file'], 0)
    kind = '矢量重' if b['shapes'] >= 40 else ('位图主' if b['bitmaps'] >= b['shapes'] else '混合')
    w('  %-32s %9dB  %5dx%-5d shp=%-4d bmp=%-3d spr=%-4d ref=%-3d %s' %
      (b['file'], b['bytes'], int(b['w']), int(b['h']),
       b['shapes'], b['bitmaps'], b['sprites'], ref, kind))
w('')
w('### 矢量最重的 15 个背景（DefineShape* 数量）')
for b in sorted(good, key=lambda x: -x['shapes'])[:15]:
    w('  %-32s shapes=%-5d sprites=%-5d %8dB %5dx%-5d' %
      (b['file'], b['shapes'], b['sprites'], b['bytes'], int(b['w']), int(b['h'])))
w('')

w('## 汇总')
w('  levels:       %d 个地图 SWF — 背景实例就绪 %d / 需施工 %d' %
  (len(levels), len(ready), len(needwork)))
w('  backgrounds:  %d 个 SWF，合计 %.1f MB，疑似孤儿 %d' % (len(good), tot/1048576.0, len(orphans)))
w('  scene_environment: %d 场景    stage_environment: %d 关卡背景' % (len(scene_envs), len(stage_envs)))

with open(P('tmp/bg-audit/REPORT.txt'), 'w', encoding='utf-8') as fh:
    fh.write('\n'.join(out))
print('REPORT.txt written, %d lines' % len(out))
