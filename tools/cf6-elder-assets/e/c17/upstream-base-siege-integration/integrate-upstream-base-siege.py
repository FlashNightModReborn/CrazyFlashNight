from pathlib import Path
import datetime, hashlib, json, subprocess

R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017/upstream-base-siege-integration'
base='1bdc3ccd7382e84839652c2603f7c943ad20c057';target='937e1815465a5c1c01376b1a947787c0e1b9de8f'
git=lambda *args:subprocess.check_output(['git',*args])
assert git('rev-parse','HEAD').decode().strip()==base and git('rev-parse','origin/main').decode().strip()==target
affected=set(filter(None,git('diff','--name-only','-z',base,target).decode('utf8').split('\0')))
local=set(filter(None,git('diff','HEAD','--name-only','-z').decode('utf8').split('\0')))
local.update(filter(None,git('ls-files','--others','--exclude-standard','-z').decode('utf8').split('\0')))
overlap=['data/units/units.json','launcher/web/modules/arena-unit-catalog.js','scripts/asLoader.swf']
assert affected&local==set(overlap)
assert not Path(git('rev-parse','--git-path','index.lock').decode().strip()).exists()
records=[];index_entries={}
for name in overlap:
    assert (R/name).read_bytes()==(O/'working'/name).read_bytes(),name
    assert git('show',':'+name)==(O/'index'/name).read_bytes(),name
    index_entries[name]=git('ls-files','--stage','--',name).decode('utf8').strip()
    for kind in ['working','index','base','upstream']:
        data=(O/kind/name).read_bytes()
        records.append({'kind':kind,'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
units={kind:{v['id']:v for v in json.loads((O/kind/overlap[0]).read_text('utf-8-sig'))} for kind in ['base','working','upstream']}
assert all(i not in units['upstream'] for i in [472,473,474])
assert units['upstream'][470]['spritename']==units['upstream'][471]['spritename']=='主角-男'
assert {units['working'][i]['spritename'] for i in [470,471,472]}=={'敌人-CF6大头机器人','敌人-CF6老头人形','敌人-CF6老头机器人'}
index_path=Path(git('rev-parse','--git-path','index').decode().strip())
with (O/'index-before.bin').open('xb') as f:f.write(index_path.read_bytes())
entries_before=git('ls-files','--stage','-z').decode('utf8').split('\0')
untouched={line.split('\t',1)[1]:line.split('\t',1)[0] for line in entries_before if line and line.split('\t',1)[1] not in affected}
preservation={'base':base,'upstream':target,'recordedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'upstreamFiles':len(affected),'overlap':overlap,'records':records,'indexEntries':index_entries,
              'registrationCollision':{'upstreamPublished':[470,471],'pendingCf6':[470,471,472]},
              'pendingCf6NewIds':{'headbot':472,'elderHuman':473,'elderRobot':474},
              'boundary':'Preserve published companion IDs; regenerate only the pending CF6 registrations into free slots. Existing historical evidence retains its original IDs.'}
with (O/'preservation.json').open('x',encoding='utf8') as f:json.dump(preservation,f,ensure_ascii=False,indent=2)
subprocess.run(['git','restore','--source=HEAD','--staged','--worktree','--',*overlap],check=True)
merged=subprocess.run(['git','merge','--ff-only',target],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
with (O/'fast-forward.log').open('xb') as f:f.write(merged.stdout)
if merged.returncode:
    assert git('rev-parse','HEAD').decode().strip()==base
    for name in overlap:
        assert (R/name).read_bytes()==(O/'base'/name).read_bytes()
        (R/name).write_bytes((O/'working'/name).read_bytes())
        mode,oid,_=index_entries[name].split('\t')[0].split()
        subprocess.run(['git','update-index','--cacheinfo',mode+','+oid+','+name],check=True)
    raise SystemExit('Fast-forward failed; the three exact local/index versions were restored')
assert git('rev-parse','HEAD').decode().strip()==target
for name in overlap:assert (R/name).read_bytes()==(O/'upstream'/name).read_bytes()
entries_after={line.split('\t',1)[1]:line.split('\t',1)[0] for line in git('ls-files','--stage','-z').decode('utf8').split('\0') if line}
assert all(entries_after.get(name)==value for name,value in untouched.items())
result={'status':'fast-forward-completed; pending-CF6-registration-reallocation-and-merged-loader-publication-required',
        'head':target,'preservedIndexEntriesOutsideUpstream':len(untouched),'overlap':overlap,
        'originalWorkingAndStagedBytesPreserved':True,'workerResourcesChanged':False}
with (O/'integration.json').open('x',encoding='utf8') as f:json.dump(result,f,ensure_ascii=False,indent=2)
print(json.dumps(result,ensure_ascii=False))
