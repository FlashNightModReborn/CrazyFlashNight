from pathlib import Path
import hashlib, json, re, subprocess
from PIL import Image

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
N = O / 'native-r22-final/elder-render'
load = lambda p: json.loads(p.read_text('utf-8-sig'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
result = load(N / 'result.json')
assert result['exitCode'] == 0 and result['bindingsUnchanged']
trace = (N / 'flashlog.txt').read_text('utf-8-sig')
starts = re.findall(r'^FocusedTestRunId cf6-elder-render Start: ([0-9a-f]+)$', trace, re.M)
finishes = re.findall(r'^FocusedTestRunId cf6-elder-render Complete: ([0-9a-f]+)$', trace, re.M)
assert len(starts) == len(finishes) == 1 and starts == finishes
expected = {'beam-29', 'beam-32', 'beam-38', 'beam-44', 'heavy-beam-1', 'heavy-beam-34',
            'heavy-beam-35', 'heavy-beam-47', 'heavy-beam-59', 'heavy-beam-71',
            'heavy-beam-106', 'heavy-beam-left-35'}
begin = re.findall(r'^\[ELDER_IMAGE_BEGIN\] ([a-z0-9-]+) 1100 500$', trace, re.M)
end = re.findall(r'^\[ELDER_IMAGE_END\] ([a-z0-9-]+)$', trace, re.M)
assert len(begin) == len(end) == len(expected) and set(begin) == set(end) == expected
assert re.search(r'Cf6ElderRenderTest: 40 passed, 0 failed', trace)
bindings = load(N / 'bindings-before.json')
swf = 'flashswf/arts/new/Codex老头素材.swf'
assert next(row['sha256'].lower() for row in bindings if row['path'] == swf) == sha(R / swf)
output = O / 'native-r22-captures'
assert not output.exists()
subprocess.run(['python', '-X', 'utf8', '-B', 'tools/cf6-elder-assets/decode-native-capture.py',
                str(N / 'flashlog.txt'), str(output), '--partial'], check=True)
files = []
for path in sorted(output.glob('*.png')):
    assert path.stem in expected
    with Image.open(path) as im:
        assert im.size == (1100, 500) and im.mode == 'RGBA'
        bounds = im.getchannel('A').getbbox()
        assert bounds and bounds[0] > 0 and bounds[1] > 0 and bounds[2] < im.width and bounds[3] < im.height
        files.append({'path': path.relative_to(O).as_posix(), 'bytes': path.stat().st_size,
                      'sha256': sha(path), 'size': list(im.size), 'nontransparentBounds': list(bounds)})
assert len(files) == 12
with (O / 'r22-native-render-verification.json').open('x', encoding='utf8') as f:
    json.dump({'ok': True, 'images': 12, 'selectedDrawPoints': 12, 'passedChecks': 40,
               'runId': starts[0], 'traceSha256': sha(N / 'flashlog.txt'), 'currentElderSwfSha256': sha(R / swf),
               'files': files,
               'boundary': 'Twelve explicitly selected points from this completed native charge run. The decoder partial mode is used only to select this charge set, with exact begin/end membership and completed result checked separately. This does not claim the 805-frame full visual scan or human aesthetic acceptance.'},
              f, ensure_ascii=False, indent=2)
print(json.dumps({'ok': True, 'images': len(files), 'currentElderSwfSha256': sha(R / swf)}))
