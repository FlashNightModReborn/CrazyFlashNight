from pathlib import Path
import hashlib,json,zipfile
R=Path.cwd();T=R/'tmp/cf6-combat-audio-20261017'
paths=['flashswf/arts/new/素材库-诺亚新敌人.swf','flashswf/arts/new/素材库-诺亚新敌人/LIBRARY/闪6特工/MovieClip/sprite 861.xml','flashswf/arts/new/素材库-诺亚新敌人/LIBRARY/闪6特工/MovieClip/起身.xml','tools/cf6-wings-assets/build.py','tools/cf6-wings-assets/native-manifest.json','tools/cf6-audio/build-legacy-test-fixture.py','tools/cf6-audio/legacy-test-fixture-manifest.json','scripts/test-runners/cf6-audio/LegacyAudioFixture.as','scripts/run-cf6-legacy-audio-tests.ps1','tools/cf6-audio/README.md']
rows=[]
with zipfile.ZipFile(T/'legacy-before-cues.zip','x',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for rel in paths:
        data=(R/rel).read_bytes();z.writestr(rel,data);rows.append({'path':rel,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)})
(T/'legacy-before-cues.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n','utf8')
print(len(rows))
