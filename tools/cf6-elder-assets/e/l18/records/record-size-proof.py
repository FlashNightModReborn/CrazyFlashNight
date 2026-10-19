from pathlib import Path
import hashlib,json
R=Path.cwd();D=R/'tmp/cf6-combat-calibration-20261017/loader-size-followup'
load=lambda n:json.loads((D/n).read_text('utf-8-sig'))
def fn(data,name):
    found=[f for f in data['functions'] if f['owner']=='DoAction[sprite=1 frame=0]' and f['preceding'][-1].get('values')==[name]]
    assert len(found)==1,(name,len(found))
    return {k:found[0][k] for k in ['codeSize','bodySha256','offset','owner']}
baseline=fn(load('large-frame-functions-parent.json'),'f3')
c5=fn(load('large-frame-functions.json'),'f3')
c6=load('frame-functions-c6.json')
part1,part2=fn(c6,'f3_1'),fn(c6,'f3_2')
assert baseline['codeSize']==c5['codeSize']==60668 and baseline['bodySha256']==c5['bodySha256']
gate=load('publish/function-sizes-machine.json')
assert gate['max']==60000 and not gate['over']
assert max(f['codeSize'] for f in gate['top'])==53041
proof={'qualified':True,'baselineCommit':'3dd6ca8a1afef1f2479beb7a5b94c08c9a1289c7','calibrationCommit':'dabd11a89570125b6fe2125aa45b5ccaf2d60cd2',
    'baselineCommunicationFunction':baseline,'c5CommunicationFunction':c5,'sameOversizedFunctionBeforeCalibrationCommit':True,
    'c6CommunicationChunks':{'f3_1':part1,'f3_2':part2},'c6MaximumFunctionBytes':53041,'maximumAllowedExclusive':60000,
    'sourceBodyOrderUnchanged':load('split-source-proof.json')['bodyConcatenationExact'],
    'c6LoaderSha256':c6['swfSha256'],'classScope':load('c5-c6-class-scope.json'),
    'upstreamChangeScope':'C6 also compiles the already merged ServerManager read-only allowlist and Agent terminal-availability/fallback registration from main. Combat code and resources are unchanged.',
    'boundary':'60668 exceeds policy, but is below the UI16 65535 representable maximum. A size scan cannot by itself exclude prior overflow wrapping or establish runtime behavior.'}
with (D/'change-analysis.json').open('x',encoding='utf8') as f:json.dump(proof,f,ensure_ascii=False,indent=2)
print(json.dumps({'qualified':True,'before':60668,'f3_1':part1['codeSize'],'f3_2':part2['codeSize'],'largest':53041}))
