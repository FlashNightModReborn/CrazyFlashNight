"""Deterministic source-bound B1 subset; never compiles or edits production sources."""
from pathlib import Path
import hashlib, json, re, shutil, sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
RUNTIME = HERE.parent / 'runtime'
BOM = b'\xef\xbb\xbf'
sources = [
    'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as',
    'scripts/逻辑/单位函数/单位函数_fs_装备生命周期配置.as',
    'scripts/逻辑/单位函数/单位函数_fs_装备引用配置.as',
    'scripts/逻辑/单位函数/单位函数_lsy_主角行走状态机.as',
]
outputs = {}
imports_path = ROOT / 'scripts/asLoaderManifest/_collapsed_frame.as'
import_rows = re.findall(r'^import (.*?);', imports_path.read_text('utf-8-sig'), re.M)
imports = '\n'.join('import '+p+';' for p in dict.fromkeys(
    p if p.endswith('.*') else p.rsplit('.',1)[0]+'.*'
    for p in import_rows if not p.startswith('org.flashNight.boot.')))
outputs['ProductionBindings.as'] = imports + '\n' + '\n'.join(
    '// SOURCE: ' + p + '\n' + (ROOT/p).read_text('utf-8-sig') for p in sources)
env_path = ROOT / 'data/environment/scene_environment.xml'
env = next(e for e in ET.parse(env_path).getroot() if e.findtext('BackgroundURL') == '医务室')
data = {k: float(env.findtext(k)) for k in ('Xmin','Xmax','Ymin','Ymax','Width','Height')}
data['collisions'] = [{'Point':[p.text.strip() for p in c.findall('Point')]}
                      for c in env.findall('Collision')]
outputs['MedicalEnvironment.as'] = '// Generated from scene_environment.xml, 医务室 only.\n_root.__b1MedicalEnvironment = ' + json.dumps(data, ensure_ascii=False) + ';\n'
manifest = {'schema':1, 'sources':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest()
    for p in sources + [str(imports_path.relative_to(ROOT)).replace('\\','/'),str(env_path.relative_to(ROOT)).replace('\\','/')]},
    'outputs':{p:hashlib.sha256(BOM+t.encode('utf-8')).hexdigest() for p,t in outputs.items()}}
outputs['source-manifest.json'] = json.dumps(manifest, ensure_ascii=False, indent=2)+'\n'
check = '--check' in sys.argv
for name, text in outputs.items():
    path = HERE/name
    content = (BOM if name.endswith('.as') else b'') + text.encode('utf-8')
    if check:
        if not path.exists() or path.read_bytes() != content:
            raise SystemExit('STALE: '+str(path))
    else:
        if name.endswith('.as') and not path.exists():
            shutil.copyfile(ROOT/sources[0], path)
        path.write_bytes(content)
print('B1 production definitions and medical environment '+('verified' if check else 'generated'))
