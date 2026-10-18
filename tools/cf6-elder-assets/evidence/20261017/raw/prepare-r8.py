from evidence_utils import *
import subprocess

experiment='elder-r7-matrix-20261017'
report=js(ROOT/'tmp/arena-worker-experiments'/experiment/'experiment-report.json')
assert report['qualified'] and report['status']=='completed' and report['completedGroups']==6 and not report['errors']
assert all(g['globalSaveUnchanged'] and g['seedSourcesUnchanged'] and all(o['cleanupVerified'] and o['runtimeResourcesVerified'] and o['protectedSavesVerified'] for o in g['outcomes']) for g in report['groups'])
for index,name in enumerate(['headbot-combat','headbot-combat2'],1):
 root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
 for log in ['launcher.log','launcher.log.1','bootstrap.log']:
  source=root/'logs'/log
  if source.is_file():put(TMP/('r7-matrix-final-w'+str(index)+'-'+log),read(source))
put(TMP/'r7-matrix-diagnostics.jsonl',read(TMP/'live-elder-audit-r7.jsonl'))
for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json','data/enemy_properties/CF6重制敌人.xml']:
 put(TMP/'r7-before-balance'/relative,read(ROOT/relative))
file=ROOT/'tools/cf6-elder-assets/balance.py'
old=read(file).decode('utf8')
before="'growth':1,'attackBias':1,'defenseBias':4}"
after="'growth':1,'attackBias':2,'defenseBias':4}"
assert old.count(before)==1
new=old.replace(before,after)
before="'growth':1,'attackBias':2,'defenseBias':9}"
after="'growth':0.9,'attackBias':2,'defenseBias':28}"
assert new.count(before)==1
new=new.replace(before,after)
file.write_text(new,encoding='utf8',newline='\n')
subprocess.run(['python','-X','utf8','-B',str(file),'--write'],cwd=ROOT,check=True)
subprocess.run(['python','-X','utf8','-B',str(file)],cwd=ROOT,check=True)
changed=[]
for name in ['headbot-combat','headbot-combat2']:
 root=Path('C:/Users/fs/.codex/worktrees')/name/'CrazyFlashNight'
 for relative in ['tools/cf6-elder-assets/balance.py','tools/cf6-elder-assets/balance-inputs.json','data/enemy_properties/CF6重制敌人.xml']:
  destination=lp(root/relative);before=sha(destination);data=read(ROOT/relative);destination.write_bytes(data)
  assert sha(destination)==digest(data)
  changed.append({'root':str(root),'path':relative,'beforeSha256':before,'sha256':digest(data)})
jput(TMP/'worker-copy-r8.json',{'scope':'Only elder balance generation inputs and its XML output; R7 AI and all SWFs remain byte-identical','files':changed})
config=js(TMP/'matrix-r7-config.json')
config.update(experimentId='elder-r8-pilot-20261017',repeat=1,levels=[99,30,60],rivals=['exusiai','beastking'],outputDirectory=str(TMP/'pilot-r8'))
jput(TMP/'pilot-r8-config.json',config)
subprocess.run(['node','tools/cf6-elder-assets/arena-plan.js',str(TMP/'pilot-r8-config.json')],cwd=ROOT,check=True)
print('R8 preparation complete; caller must launch the freshly generated plan.')
