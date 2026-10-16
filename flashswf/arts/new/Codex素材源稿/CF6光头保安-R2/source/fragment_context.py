from pathlib import Path
import json
R=Path(__file__).resolve().parents[1]
NS='http://www.w3.org/2000/svg'
S={s['id']:s for s in json.loads((R/'reference/shape-manifest.json').read_text())}
ART=json.loads((R/'source/atlas-art.json').read_text())
def atlas(prefix=''):
 return ''.join(v['body'] for v in ART.values())
def mat(m):return 'matrix('+','.join(map(str,m))+')'
