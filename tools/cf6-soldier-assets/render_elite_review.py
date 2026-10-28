from pathlib import Path
import argparse
import datetime
import hashlib
import html
import json
import os
import re
from PIL import Image, ImageDraw

ACTIONS = {
    'stand': ('站射', 46, 77),
    'retreat': ('后撤双枪', 2, 44),
    'slide': ('滑铲', 166, 248),
}
POSE_RE = re.compile(r'\[SOLDIER_POSE\] (\S+) state=(.*?) frame=(\d+) x=(\S+) z=(\S+) primary=(\S+) secondary=(\S+)')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def url(path, root):
    from urllib.parse import quote
    return quote(os.path.relpath(path, root).replace(os.sep, '/'))


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def contact_sheet(name, paths, output):
    if not paths:
        return
    columns = 8
    rows = (len(paths) + columns - 1) // columns
    sheet = Image.new('RGB', (columns * 200, rows * 155), '#18211d')
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(paths):
        image = Image.open(path).convert('RGB')
        image.thumbnail((192, 129))
        x, y = (index % columns) * 200, (index // columns) * 155
        sheet.paste(image, (x + (200 - image.width) // 2, y + 22 + (129 - image.height) // 2))
        label = path.stem.replace('elite-motion-', '').replace('elite-', '')
        draw.text((x + 5, y + 5), label, fill='#edf2ed')
    sheet.save(output)


def main():
    parser = argparse.ArgumentParser(description='Build a local, evidence-bound 3XF/native elite review player')
    parser.add_argument('--reference-dir', type=Path, required=True)
    parser.add_argument('--native-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--native-trace', type=Path)
    parser.add_argument('--profile', type=Path, default=Path('tools/cf6-soldier-assets/elite-motion-profile.json'))
    parser.add_argument('--protocol', type=Path)
    parser.add_argument('--arena-summary', type=Path)
    parser.add_argument('--candidate-status', type=Path)
    parser.add_argument('--candidate-shot', type=Path)
    parser.add_argument('--native-evidence', type=Path)
    parser.add_argument('--allow-partial', action='store_true')
    args = parser.parse_args()
    partial = args.allow_partial
    if not partial:
        for name in ('native_trace', 'native_evidence', 'protocol', 'arena_summary', 'candidate_status', 'candidate_shot'):
            if getattr(args, name) is None:
                parser.error('--' + name.replace('_', '-') + ' is required for an acceptance review')
    reference = {action: list(range(first, last + 1)) for action, (_, first, last) in ACTIONS.items()}
    missing = []
    for action, frames in reference.items():
        for frame in frames:
            if not (args.reference_dir / f'{frame}.png').is_file():
                missing.append(f'reference:{action}:{frame}')
            if not (args.native_dir / f'elite-motion-{action}-0-{frame}.png').is_file():
                missing.append(f'native:{action}:{frame}')
    if missing and not partial:
        raise ValueError('Incomplete native/reference capture: ' + ', '.join(missing[:16]))
    if (args.output_dir / 'index.html').exists():
        raise FileExistsError('Preserve the existing review; choose a new output directory')
    profile = read_json(args.profile)
    trace_text = args.native_trace.read_text(encoding='utf-8-sig') if args.native_trace else ''
    if trace_text and not re.search(r'Cf6SoldierAssetTest: \d+ passed, 0 failed; 86 actual timeline cases', trace_text) and not partial:
        raise ValueError('Native behavior evidence is not a fresh zero-failure 86-case run')
    if not trace_text and not partial:
        raise ValueError('--native-trace is required for acceptance evidence')
    evidence = read_json(args.native_evidence) if args.native_evidence else None
    if evidence and not partial:
        if (evidence.get('assertionsFailed') != 0 or evidence.get('actualTimelineCases') != 86
                or evidence.get('compilerErrors') != '0/0' or evidence.get('compiler32KRetry') != 0):
            raise ValueError('Native evidence does not bind a healthy 86-case run')
        run_id = evidence['runId']
        start = 'FocusedTestRunId cf6-soldier Start: ' + run_id
        complete = 'FocusedTestRunId cf6-soldier Complete: ' + run_id
        if (trace_text.count(start) != 1 or trace_text.count(complete) != 1
                or trace_text.index(start) > trace_text.index(complete) or '[TEST_FAIL]' in trace_text):
            raise ValueError('Native trace is not one ordered terminal run bound to the evidence')
        for filename, expected in evidence['sourceHashes'].items():
            path = Path(filename)
            if not path.is_file() or sha(path) != expected:
                raise ValueError('Native source or SWF identity changed: ' + filename)
    poses = {match[1]: {'state': match[2], 'frame': int(match[3]), 'x': match[4], 'z': match[5],
             'primary': match[6], 'secondary': match[7]} for match in POSE_RE.finditer(trace_text)}
    summary = read_json(args.arena_summary) if args.arena_summary else None
    comparison = paired = None
    if summary and not partial:
        comparison = next(row for row in summary['analyses']['red']['comparisons'] if row['comparisonId'] == 'ordinary-vs-elite-overall')
        paired = comparison['pairedContrast']
        if (not summary['qualification']['qualified'] or comparison['ci95']['lower'] <= 0
                or not paired['qualified'] or paired['ci95']['lower'] <= 0):
            raise ValueError('Arena evidence has not met the independent and paired effect gates')
        if not summary['qualification']['performanceGatePassed']:
            raise ValueError('The pre-registered arena performance gate has not passed')
        if any(layer['effect'] <= 0 or layer['pairs'] < 30 for layer in paired['layers']):
            raise ValueError('An opponent layer is not positive or lacks 30 pairs')
    status = read_json(args.candidate_status) if args.candidate_status else None
    if status and status.get('deploymentStatus') != 'NOT_DEPLOYED':
        raise ValueError('Review must remain on an isolated, not-deployed candidate')
    if args.candidate_shot and not args.candidate_shot.is_file():
        raise FileNotFoundError(args.candidate_shot)
    if not partial:
        campaign = read_json(args.arena_summary.parent / 'campaign.json')
        if campaign['protocolSha256'] != sha(args.protocol):
            raise ValueError('Arena campaign does not use the supplied protocol')
        if Path(campaign['candidateRoot']).resolve() != Path(status['candidateRoot']).resolve():
            raise ValueError('Arena candidate differs from the review candidate')
        identity = campaign['runtimeIdentity']
        if (identity['coreSha256'] != status['candidateCoreSha256']
                or identity['buildIdentity'] != status['currentBuildIdentityHash']
                or identity['payloadClosure'] != status['payloadClosureHash']):
            raise ValueError('Arena and review candidate identities differ')
        capture = read_json(Path(str(args.candidate_shot) + '.json'))
        if not capture.get('foregroundVerified') or not isinstance(capture.get('pid'), int) or capture['pid'] <= 0:
            raise ValueError('Candidate screenshot does not have a bound foreground process')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    native_paths = {}
    for action, frames in reference.items():
        available = [frame for frame in frames if (args.native_dir / f'elite-motion-{action}-0-{frame}.png').is_file()]
        native_paths[action] = available
        contact_sheet(f'contact-{action}.png', [args.native_dir / f'elite-motion-{action}-0-{frame}.png' for frame in available], args.output_dir / f'contact-{action}.png')
    fixed = sorted(path for path in args.native_dir.glob('elite-*.png') if not path.name.startswith('elite-motion-'))
    if not partial:
        if sum(len(frames) for frames in native_paths.values()) != 158 or len(fixed) != 22:
            raise ValueError('Acceptance requires all 158 motion and 22 fixed native captures')
        for path in [args.native_dir / f'elite-motion-{action}-0-{frame}.png'
                     for action, frames in native_paths.items() for frame in frames] + fixed:
            with Image.open(path) as image:
                if image.size != (640, 430):
                    raise ValueError('Unexpected native capture dimensions: ' + str(path))
    contact_sheet('contact-fixed.png', fixed, args.output_dir / 'contact-fixed.png')
    data = {
        'actions': [{'id': action, 'label': ACTIONS[action][0], 'frames': frames} for action, frames in native_paths.items()],
        'referenceDir': url(args.reference_dir, args.output_dir),
        'nativeDir': url(args.native_dir, args.output_dir),
        'poses': poses,
        'fireEvents': {action: profile['actions'][action]['fireEvents'] for action in ACTIONS},
    }
    comparisons = summary['analyses']['red']['comparisons'] if summary else []
    comparisons_html = html.escape(json.dumps(comparisons, ensure_ascii=False, indent=2))
    status_html = html.escape(json.dumps(status, ensure_ascii=False, indent=2)) if status else '候选状态将由本地开发入口绑定。'
    warning = ('<div class="warning">这是诊断子集，不是完整验收证据。</div>' if partial else
               '<div class="ok">原生帧、候选和斗兽证据分别绑定；页面不代替你的实机验收。</div>')
    shot_html = ''
    if args.candidate_shot:
        shot_html = f'<section><h2>实际候选画面</h2><img class="candidate-shot" src="{url(args.candidate_shot, args.output_dir)}"><p><a href="{url(args.candidate_shot, args.output_dir)}">打开原图</a></p></section>'
    protocol_html = f'<a href="{url(args.protocol, args.output_dir)}">预先登记赛程</a>' if args.protocol else ''
    summary_html = f'<a href="{url(args.arena_summary, args.output_dir)}">斗兽统计与 bootstrap 明细</a>' if args.arena_summary else ''
    trace_html = f'<a href="{url(args.native_trace, args.output_dir)}">原生行为 trace</a>' if args.native_trace else ''
    status_link = f'<a href="{url(args.candidate_status, args.output_dir)}">候选状态</a>' if args.candidate_status else ''
    document = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>CF6 特种精英 · 本地复刻验收</title><style>
:root{color-scheme:dark;font:15px/1.55 system-ui,sans-serif;background:#111914;color:#e8eee9}body{margin:0;max-width:1500px;padding:24px}h1,h2{font-weight:600}h1{font-size:26px}h2{font-size:18px;margin-top:28px}p,small{color:#b7c5ba}a{color:#9ed4ff}section{margin-top:18px}.warning,.ok{padding:12px;border-radius:8px}.warning{background:#593c22}.ok{background:#193f30}.toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:14px 0}.tabs button,.toolbar button,.toolbar select{font:inherit;padding:7px 12px;border:1px solid #506557;border-radius:6px;background:#24372c;color:#e8eee9;cursor:pointer}.tabs button.active{background:#567d64}input[type=range]{flex:1;min-width:180px}.compare{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}.view{background:#e8e6e2;border-radius:8px;overflow:hidden}.view h3{color:#24332a;font-size:14px;margin:8px}.view img{display:block;width:100%;height:58vh;object-fit:contain}.meta{padding:8px;background:#1b2a21;border-radius:8px;min-height:58px}.contact{display:flex;flex-wrap:wrap;gap:12px}.contact a{display:block;max-width:320px}.contact img{display:block;max-width:100%;height:auto}.candidate-shot{display:block;max-width:100%;height:auto}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#19231c;padding:12px;border-radius:8px;max-height:520px;overflow:auto}@media(max-width:800px){body{padding:12px}.compare{grid-template-columns:1fr}.view img{height:48vh}}
</style><main><h1>CF6 特种精英 · 3XF 复刻验收</h1>
<p>左侧为 3XF 原始参考，右侧为真实 Flash 原生帧。保留 CF6 身体与装备，不将它说成逐像素复刻。帧图来自原生测试夹具；实际候选与斗兽证据另列。</p>__WARNING__
<div class="tabs" id="tabs"></div><div class="toolbar"><button id="play">播放</button><button id="prev">上一帧</button><button id="next">下一帧</button><label>速度 <select id="speed"><option value="0.25">0.25×</option><option value="0.5" selected>0.5×</option><option value="1">1×</option><option value="2">2×</option></select></label><input id="frame" type="range" min="0" value="0" aria-label="逐帧选择"><span id="counter"></span></div>
<div class="compare"><div class="view"><h3>3XF 原始参考</h3><img id="source" alt="3XF 原始参考帧"></div><div class="view"><h3>CF6 精英 · Flash 原生帧</h3><img id="native" alt="CF6 精英原生帧"></div></div><div class="meta" id="meta"></div>
<section><h2>全部帧接触表</h2><div class="contact" id="contacts"></div></section>
__SHOT__
<section><h2>证据与边界</h2><p>__TRACE__ __SUMMARY__ __PROTOCOL__ __STATUS__</p><p>站射、后撤与滑铲使用同源关键帧；后撤使用主长枪＋FR506，站射和滑铲不显示副枪。普通兵及真实存档保持原状，玩家双枪模式不在本轮接入范围。韧性 50 与 FR506（重量 5）的差异显式保留，不宣称完整有效面板相等。</p><details><summary>斗兽比较与置信区间</summary><pre>__COMPARISONS__</pre></details><details><summary>候选身份</summary><pre>__STATUS__</pre></details><p>实机验收使用根目录 <code>本地开发启动.cmd</code>，在斗兽场搜索 478 / 479。请分别查看持盾破盾前后的身份、后撤双枪和滑铲衔接。</p></section>
</main><script>const DATA=__DATA__;
const byId=id=>document.getElementById(id);let actionIndex=0,frameIndex=0,playing=false,last=0,acc=0;
const nativePath=(action,frame)=>`${DATA.nativeDir}/elite-motion-${action}-0-${frame}.png`;
const actions=DATA.actions;
function render(){const action=actions[actionIndex],frame=action.frames[frameIndex];byId('source').src=`${DATA.referenceDir}/${frame}.png`;byId('native').src=nativePath(action,frame);byId('counter').textContent=`${frameIndex+1}/${action.frames.length} · 源帧 ${frame}`;byId('frame').max=action.frames.length-1;byId('frame').value=frameIndex;byId('play').textContent=playing?'暂停':'播放';const pose=DATA.poses[`elite-motion-${action}-0-${frame}`];const fire=DATA.fireEvents[action].filter(e=>e.frame===frame).map(e=>e.weapon==='primary'?'主枪':'FR506');byId('meta').textContent=[`动作 ${action.label} / ${frame}`,fire.length?`源射击锚点：${fire.join('、')}`:'无射击锚点',pose?`原生耗弹：主枪 ${pose.primary} / FR506 ${pose.secondary}；x=${pose.x}，z=${pose.z}`:''].filter(Boolean).join('　|　');document.querySelectorAll('[data-action]').forEach(button=>button.classList.toggle('active',button.dataset.action===action.id));}
function selectAction(index){actionIndex=index;frameIndex=0;playing=false;render();}
for(const [index,action] of actions.entries()){const button=document.createElement('button');button.textContent=action.label;button.dataset.action=action.id;button.onclick=()=>selectAction(index);byId('tabs').appendChild(button);const link=document.createElement('a');link.href=`contact-${action.id}.png`;link.target='_blank';link.innerHTML=`<img src="contact-${action.id}.png" alt="${action.label} 全帧接触表">`;byId('contacts').appendChild(link);}
const fixedLink=document.createElement('a');fixedLink.href='contact-fixed.png';fixedLink.target='_blank';fixedLink.innerHTML='<img src="contact-fixed.png" alt="双向固定姿态、装填与破盾接触表">';byId('contacts').appendChild(fixedLink);
byId('play').onclick=()=>{playing=!playing;acc=0;last=performance.now();render();};byId('prev').onclick=()=>{frameIndex=Math.max(0,frameIndex-1);playing=false;render();};byId('next').onclick=()=>{frameIndex=Math.min(actions[actionIndex].frames.length-1,frameIndex+1);playing=false;render();};byId('frame').oninput=event=>{frameIndex=Number(event.target.value);playing=false;render();};byId('speed').onchange=()=>{acc=0;};
function tick(now){if(playing){acc+=now-last;const interval=1000/30/Number(byId('speed').value);if(acc>=interval){const steps=Math.floor(acc/interval);acc-=steps*interval;frameIndex+=steps;if(frameIndex>=actions[actionIndex].frames.length){frameIndex=actions[actionIndex].frames.length-1;playing=false;}render();}}last=now;requestAnimationFrame(tick);}document.addEventListener('keydown',event=>{if(event.target.matches('input,select,textarea'))return;if(event.code==='Space'){event.preventDefault();byId('play').click();}if(event.code==='ArrowLeft')byId('prev').click();if(event.code==='ArrowRight')byId('next').click();});render();requestAnimationFrame(tick);
</script>'''
    document = (document.replace('__WARNING__', warning).replace('__SHOT__', shot_html)
        .replace('__TRACE__', trace_html).replace('__SUMMARY__', summary_html)
        .replace('__PROTOCOL__', protocol_html).replace('__STATUS__', status_link)
        .replace('__COMPARISONS__', comparisons_html).replace('__STATUS__', status_html)
        .replace('__DATA__', json.dumps(data, ensure_ascii=False).replace('</', '<\\/')))
    (args.output_dir / 'index.html').write_text(document, encoding='utf-8')
    inputs = {}
    for path in [args.native_trace, args.native_evidence, args.profile, args.protocol, args.arena_summary,
                 args.candidate_status, args.candidate_shot,
                 Path(str(args.candidate_shot) + '.json') if args.candidate_shot else None,
                 args.arena_summary.parent / 'campaign.json' if summary and not partial else None]:
        if path:
            inputs[str(path)] = sha(path)
    images = {}
    for action, frames in native_paths.items():
        for frame in frames:
            path = args.native_dir / f'elite-motion-{action}-0-{frame}.png'
            images[path.name] = sha(path)
    for path in fixed:
        images[path.name] = sha(path)
    reference_images = {}
    for action, frames in reference.items():
        for frame in frames:
            path = args.reference_dir / f'{frame}.png'
            if path.is_file():
                reference_images[path.name] = sha(path)
    manifest = {
        'schema': 'cf6-soldier.elite-review.v2',
        'generatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'diagnosticSubset': partial,
        'actions': native_paths,
        'requiredMotionFrames': 158,
        'fixedFrames': 22,
        'nativeCaptureDimensions': [640, 430],
        'nativeRunId': evidence['runId'] if evidence else None,
        'candidateRoot': status['candidateRoot'] if status else None,
        'arenaPerformanceGatePassed': summary['qualification']['performanceGatePassed'] if summary else None,
        'pairedContrastCi95': paired['ci95'] if paired else None,
        'inputHashes': inputs,
        'nativeImageHashes': images,
        'referenceImageHashes': reference_images,
        'evidenceBoundary': 'Native fixture, local candidate and real arena evidence; not human acceptance',
    }
    (args.output_dir / 'review-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'output': str(args.output_dir / 'index.html'), 'diagnosticSubset': partial,
        'actions': {key: len(value) for key, value in native_paths.items()}, 'fixedContactFrames': len(fixed)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
