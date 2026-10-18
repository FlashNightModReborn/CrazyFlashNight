from pathlib import Path
import json,hashlib,zipfile,subprocess
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
paths=set()
for tool in ROOT.glob('tools/cf6-*-assets'):
 for p in tool.rglob('*'):
  if p.is_file() and not any(x in ('evidence','__pycache__') for x in p.relative_to(tool).parts):paths.add(p)
 manifest=json.loads((tool/'native-manifest.json').read_text('utf8'))
 owner=ROOT/manifest['owner']
 if owner.suffix=='.xfl':owner=owner.parent
 for p in owner.rglob('*'):
  if p.is_file():paths.add(p)
 swf=owner.with_suffix('.swf')
 if swf.exists():paths.add(swf)
for p in (ROOT/'scripts/类定义').rglob('Cf6*.as'):paths.add(p)
for p in (ROOT/'scripts/test-runners').glob('cf6*/*'):
 if p.is_file():paths.add(p)
for p in ROOT.glob('scripts/run-cf6*.ps1'):paths.add(p)
for name in ['data/enemy_properties/CF6重制敌人.xml','data/units/units.json','data/items/asset_source_map.xml',
 'scripts/TestLoader.as','scripts/asLoader.swf','scripts/逻辑/关卡系统/关卡系统_lsy_地图元件.as',
 'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as','tools/cf7-balance-tool/data/monster-flag-ledger.json',
 'agentsDoc/game-design.md','agentsDoc/testing-details.md','launcher/web/modules/arena-unit-catalog.js']:
 paths.add(ROOT/name)
rows=[]
with zipfile.ZipFile(HERE/'before-source.zip','x',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
 for p in sorted(paths):
  b=p.read_bytes();name=p.relative_to(ROOT).as_posix();archive.writestr(name,b)
  rows.append({'path':name,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
sound_rows=[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted((ROOT/'sounds/export').glob('*/*')) if p.is_file()]
data={'files':rows,'soundFiles':sound_rows,'archiveSha256':hashlib.sha256((HERE/'before-source.zip').read_bytes()).hexdigest(),
 'gitHead':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
 'sourceScreenshot':'C:/Users/fs/AppData/Local/Temp/codex-clipboard-d24e0576-aa45-47db-bded-f5f93bada505.png'}
with (HERE/'before-source-index.json').open('x',encoding='utf8') as f:json.dump(data,f,ensure_ascii=False,indent=2)
print(json.dumps({'files':len(rows),'archiveBytes':(HERE/'before-source.zip').stat().st_size,'soundFiles':len(sound_rows),'archiveSha256':data['archiveSha256']}))
