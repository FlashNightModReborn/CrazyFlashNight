"""Prepare the exact final source list before the staged checkout-byte audit."""
from pathlib import Path
import argparse, hashlib, json

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--head-identity', type=Path)
a = parser.parse_args()
R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
load = lambda p: json.loads(p.read_text('utf-8-sig'))
paths = {row['path'] for row in load(O / 'before-r22-high-level-budget-index.json')}
paths.update(load(O / 'native-r22-final-plan.json')['bindings'])
for label in ['r22-full-awake', 'head-c5-full-awake']:
    identity_path = a.head_identity if label == 'head-c5-full-awake' and a.head_identity else P / 'history' / label / 'plan/input-identity.json'
    paths.update(row['path'] for row in load(identity_path)['sourceBindings'])
paths.update(['tools/cf6-elder-assets/assess-arena-targets.py', 'launcher/README.md',
              'agentsDoc/as2-anti-hallucination.md', 'agentsDoc/art-asset-assembly.md',
              'agentsDoc/game-design.md', 'launcher/src/Guardian/LauncherCommandRouter.cs',
              'launcher/src/RagTerminal/RagTerminalService.cs', 'launcher/src/Program.cs',
              'launcher/tests/Guardian/LauncherCommandRouterTests.cs',
              'launcher/tests/RagTerminal/RagTerminalServiceTests.cs'])
# The ignored pre-existing scratch original is bound only to prove restoration.
# Actual test runner templates and resulting test SWFs are preserved separately.
paths.discard('scripts/TestLoader.as')
strict_checkout_paths = sorted(paths)
host_paths = {row['path'] for row in load(O / 'host-r22-final/source-before.json')['files']}
additional_host_paths = sorted(host_paths - paths)
paths.update(host_paths)
rows = []
for name in sorted(paths):
    data = (R / name).read_bytes()
    rows.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
with a.output.open('x', encoding='utf8') as f:
    json.dump({'files': rows, 'strictCheckoutPaths': strict_checkout_paths,
               'additionalFrozenHostSourcePaths': additional_host_paths,
               'boundary': 'All archive bytes are the actual current/tested bytes. Gameplay, AS2 and original bound inputs require exact Git checkout bytes. Additional Host source snapshots separately retain raw Git-blob identity and explicitly report any existing LF-to-CRLF checkout conversion.'}, f, ensure_ascii=False, indent=2)
print(json.dumps({'files': len(rows), 'bytes': sum(row['bytes'] for row in rows)}))
