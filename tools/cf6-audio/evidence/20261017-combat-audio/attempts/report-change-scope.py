from pathlib import Path
import hashlib,json,collections
R=Path.cwd();T=R/'tmp/cf6-combat-audio-20261017'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
baseline=json.loads((T/'before-source-index.json').read_text('utf8'))
changed=[];same=[]
for row in baseline['files']:
    p=R/row['path'];current=sha(p) if p.is_file() else None
    if current==row['sha256']:same.append(row['path'])
    else:changed.append({'path':row['path'],'beforeSha256':row['sha256'],'sha256':current})
protected=['data/enemy_properties/CF6重制敌人.xml','data/items/asset_source_map.xml','data/units/units.json','scripts/asLoader.swf','scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as']
assert all(path in same for path in protected)
out={'scope':'Changes since this user request; earlier uncommitted work is not attributed to this task. New files and the separately preserved two old-agent source files are indexed by the final source package.',
     'baselineFiles':len(baseline['files']),'unchangedBaselineFiles':len(same),'changedBaselineFiles':len(changed),
     'unchangedExistingAuthorityInputs':protected,'changes':changed,
     'notCoveredByThisBaseline':['flashswf/arts/things-new.swf']}
(T/'change-scope.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({k:v for k,v in out.items() if k not in ['changes','scope']},ensure_ascii=False))
