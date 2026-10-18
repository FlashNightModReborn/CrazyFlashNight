from pathlib import Path
import hashlib,json,re,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];TMP=Path(__file__).resolve().parent
actor=sys.argv[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
attempt=TMP/(sys.argv[2] if len(sys.argv)>2 else 'render-pass3')/actor
result=json.loads((attempt/'result.json').read_text('utf-8-sig'))
assert result['exitCode']==0 and result['bindingsUnchanged'],result
dest=TMP/'final-images'/actor/'images'
assert not dest.exists(),'Preserve final images'
dest.mkdir(parents=True)
resource={'headbot':'Codex大头机器人素材','elder':'Codex老头素材','bladebot':'Codex大刀机器人素材'}[actor]
resource_path='flashswf/arts/new/'+resource+'.swf';resource_sha=sha(ROOT/resource_path)
def verify_resource(folder):
    b=json.loads((folder/'bindings-before.json').read_text('utf-8-sig'))
    a=json.loads((folder/'bindings-after.json').read_text('utf-8-sig'))
    assert b==a
    assert next(r['sha256'].lower() for r in a if r['path']==resource_path)==resource_sha
verify_resource(attempt)
decoder=ROOT/f'tools/cf6-{actor}-assets/decode-native-capture.py'
if actor=='headbot':
    # A dedicated exact-two-frame decoder changes only the required key set.
    code=decoder.read_text('utf8')
    code,count=re.subn(r'^    expected = \{.*\}$',"    expected = {'beam-29','beam-30'}",code,count=1,flags=re.M)
    assert count==1
    bounded=TMP/'decode-head-framing-exact.py';bounded.write_text(code,'utf8')
    decoded=attempt/'images'
    subprocess.run([sys.executable,'-X','utf8','-B',str(bounded),str(attempt/'flashlog.txt'),str(decoded)],check=True)
    prior=TMP/'render-pass1/headbot';verify_resource(prior)
    sources={p.name:(p,prior) for p in (prior/'images').glob('*.png')}
    sources.update({p.name:(p,attempt) for p in decoded.glob('*.png')})
    assert len(sources)==20
else:
    args=['--beam-only'] if actor=='bladebot' else []
    subprocess.run([sys.executable,'-X','utf8','-B',str(decoder),str(attempt/'flashlog.txt'),str(attempt/'images'),*args],check=True)
    sources={p.name:(p,attempt) for p in (attempt/'images').glob('*.png')}
    assert len(sources)==({'elder':25,'bladebot':2}[actor])
rows=[]
for name,(p,origin) in sorted(sources.items()):
    shutil.copyfile(p,dest/name)
    trace=(origin/'flashlog.txt').read_text('utf-8-sig')
    run_id=re.search(r'FocusedTestRunId \S+ Start: ([0-9a-f]+)',trace)[1]
    rows.append({'image':name,'sha256':sha(p),'nativeAttempt':origin.relative_to(TMP).as_posix(),'nativeRunId':run_id,'traceSha256':sha(origin/'flashlog.txt'),'testSwfSha256':sha(origin/'TestLoader.swf')})
(dest/'provenance.json').write_text(json.dumps({'resource':resource_path,'resourceSha256':resource_sha,'images':rows,'policy':'Copied original native pixels. Headbot retains the first capture of unaffected frames and replaces the two formerly clipped frames with the successful focused framing run. A failed whole-suite result is not upgraded.'},ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({'actor':actor,'images':len(rows),'resourceSha256':resource_sha},ensure_ascii=False))
