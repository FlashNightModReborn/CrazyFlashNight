from pathlib import Path
import datetime,importlib.util,json
R=Path.cwd();T=R/'tmp/cf6-combat-audio-20261017';P=R/'tools/cf6-audio/evidence/20261017-combat-audio';O=R/'tools/cf6-audio/evidence/20261017-combat-audio-closeout'
assert not O.exists()
s=importlib.util.spec_from_file_location('cf6_evidence',R/'tmp/cf6-elder-20261016/evidence_utils.py');u=importlib.util.module_from_spec(s);s.loader.exec_module(u)
checks=u.js(T/'final-checks.json');assert checks['docGovernanceExitCode']==0 and checks['diffCheckExitCode']==0
verification=u.js(T/'package-verification.json');assert verification['ok']
preserved=u.js(T/'preserved-evidence-check-final.json');assert preserved['ok']
assert u.js(T/'arena-final-cleanup.json')['ok'] and u.js(T/'native-cleanup-final.json')['ok']
package=u.Package(O)
for name in ['final-checks.json','doc-governance-after-package.log','diff-check-after-package.log','package-verification.json','preserved-evidence-check-final.json','arena-final-cleanup.json','native-cleanup-final.json']:
    package.copy(T/name,name)
package.copy(P/'integrity.json','primary-package-integrity.json')
u.jput(O/'summary.json',{'ok':True,'timeUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'primaryPackage':'../20261017-combat-audio','primaryIntegritySha256':u.sha(P/'integrity.json'),
 'docGovernance':True,'diffCheck':True,'oldPackagesUnchanged':len(preserved['oldPackages']),
 'oldEvidenceFilesVerified':sum(r['verifiedFiles'] for r in preserved['oldPackages']),
 'verifiedDelivery':verification,'originalCs6EditorPreserved':True,'realPlayerSaveProtectionVerified':True,
 'commitOrPush':False,'formalRuntimePromotion':False,'standardEntryVerified':False,'humanListeningOrAestheticAcceptance':False})
print(json.dumps(package.finish()))
