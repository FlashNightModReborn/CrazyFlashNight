from evidence_utils import *
import subprocess

out=TMP/'worker-preserved-final'
assert not out.exists(), 'Use a new directory for each preservation attempt'
out.mkdir()
original=ROOT/'tmp/cf6-guard-closeout-20261016/worker-preserved/wings-combat-ignored.zip'
old_index=js(original.with_name('wings-combat-index.json'))
assert sha(original)==old_index['archiveSha256']
prefix='tmp/runtime-candidates/v2/wings-r1/'
old={row['path']:row for row in old_index['preserved']}
report={'originalArchive':str(original),'originalArchiveSha256':sha(original),'workers':[]}
for name in ['headbot-combat','headbot-combat2']:
 root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
 assert root.resolve().parent.name==name
 paths=subprocess.check_output(['git','ls-files','--others','--ignored','--exclude-standard','-z'],cwd=root).decode('utf8').split('\0')
 paths=sorted(set(p for p in paths if p))
 archive=out/(name+'-ignored.zip')
 rows=[]; references=[]; excluded=[]
 with zipfile.ZipFile(lp(archive),'x',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for relative in paths:
   file=root/relative
   if not lp(file).is_file():continue
   # Runtime payload already has an independently retained immutable copy.
   if relative.startswith(prefix) and '/logs/' not in relative:
    data=read(file); previous=old.get(relative)
    assert previous and digest(data)==previous['sha256'] and len(data)==previous['bytes'],relative
    references.append({'path':relative,'bytes':len(data),'sha256':digest(data),'archiveMember':relative})
    continue
   # Cache-only generated material is reproducible and not test evidence.
   if '/node_modules/' in '/'+relative or '/__pycache__/' in '/'+relative:
    excluded.append({'path':relative,'reason':'reproducible dependency or Python cache'});continue
   data=read(file);z.writestr(relative,data)
   rows.append({'path':relative,'bytes':len(data),'sha256':digest(data)})
 with zipfile.ZipFile(lp(archive)) as z:
  assert z.namelist()==[r['path'] for r in rows]
  for row in rows:assert digest(z.read(row['path']))==row['sha256']
 record={'root':str(root),'archive':str(archive),'archiveSha256':sha(archive),'preserved':rows,'runtimeReferences':references,'excluded':excluded}
 jput(out/(name+'-index.json'),record)
 report['workers'].append({'root':str(root),'archive':str(archive),'archiveSha256':record['archiveSha256'],'preservedFiles':len(rows),'runtimeReferenceFiles':len(references),'excludedFiles':len(excluded),'bytes':archive.stat().st_size})
jput(out/'summary.json',report)
print(json.dumps(report,ensure_ascii=False,indent=2))
