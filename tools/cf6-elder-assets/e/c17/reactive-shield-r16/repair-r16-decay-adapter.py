from pathlib import Path
import hashlib, json, zipfile

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
read = lambda p: json.loads(p.read_text('utf-8-sig'))
assert read(O / 'native-r16-reactive-shield/elder-asset/result.json')['exitCode'] == 1
assert read(O / 'native-r16-reactive-shield/player-aim/result.json')['exitCode'] == 0
paths = ['tools/cf6-elder-assets/build-playtest-fixture.py', 'tools/cf6-elder-assets/playtest-fixture-manifest.json',
         'scripts/test-runners/cf6-playtest/PlaytestFixture.as', 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as']
index = []
with zipfile.ZipFile(O / 'before-r16-decay-adapter-repair.zip', 'x', zipfile.ZIP_DEFLATED) as z:
    for name in paths:
        data = (R / name).read_bytes()
        z.writestr(name, data)
        index.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
with (O / 'before-r16-decay-adapter-repair-index.json').open('x', encoding='utf8') as f:
    json.dump(index, f, ensure_ascii=False, indent=2)
p = R / paths[0]
text = p.read_text('utf8')
old = "(shield,'_root.护盾函数.添加临时护盾'),(shield,'_root.护盾函数.移除护盾')"
new = "(shield,'_root.护盾函数.添加临时护盾'),(shield,'_root.护盾函数.添加衰减护盾'),(shield,'_root.护盾函数.移除护盾')"
assert text.count(old) == 1
p.write_text(text.replace(old, new), 'utf8', newline='\n')
p = R / paths[-1]
prior = p.read_bytes()
text = prior.decode('utf-8-sig').replace('\r\n', '\n')
old = '    private static function reactiveShieldTests(actor:MovieClip):Void {\n        actor.elderClearReactiveShield();'
new = '    private static function reactiveShieldTests(actor:MovieClip):Void {\n        var decayApi:Boolean=typeof _root.护盾函数.添加衰减护盾=="function";\n        check(decayApi,"exact production decay adapter is available");if(!decayApi)return;\n        actor.elderClearReactiveShield();'
assert text.count(old) == 1
text = text.replace(old, new)
if b'\r\n' in prior:
    text = text.replace('\n', '\r\n')
p.write_bytes(b'\xef\xbb\xbf' + text.encode('utf8'))
plan = read(O / 'native-r16-reactive-shield-plan.json')
plan['output'] = 'native-r16-decay-adapter-repair'
plan['runs'] = [run for run in plan['runs'] if run['name'] in ['elder-asset', 'player-aim']]
assert len(plan['runs']) == 2
with (O / 'native-r16-decay-adapter-repair-plan.json').open('x', encoding='utf8') as f:
    json.dump(plan, f, ensure_ascii=False, indent=2)
print(json.dumps({'productionBehaviorChanged': False, 'candidateSwfChanged': False,
                  'repair': 'Include the exact production decay-shield adapter in the generated test fixture and assert its presence.',
                  'rerun': ['elder-asset', 'player-aim'], 'originalFailurePreserved': True}))
