from pathlib import Path
import hashlib, json, re

R = Path.cwd()
D = R / 'tmp/cf6-combat-calibration-20261017/loader-size-followup'
p = R / 'scripts/asLoaderManifest/frame3.as'
before = p.read_bytes()
assert before == (D / 'frame3-before.as').read_bytes()
assert before[:3] == b'\xef\xbb\xbf'
text = before[3:].decode('utf8')
assert text.count('_root.__boot.f3 = function() {') == 1
text = text.replace('_root.__boot.f3 = function() {',
    '// 同一 S1 阶段保序同步执行；Agent 注册独立成段，给 AVM1 单函数体留出余量。\n_root.__boot.f3_1 = function() {')
needle = '    #include "../通信/通信_aka_Agent联动.as"'
assert text.count(needle) == 1
text = text.replace(needle, '};\n_root.__boot.f3_2 = function() {\n' + needle)
assert text.count('_root.__boot.f3();') == 1
text = text.replace('_root.__boot.f3();', '_root.__boot.f3_1();\n_root.__boot.f3_2();')
after = before[:3] + text.encode('utf8')
old_body = before.decode('utf-8-sig').split('_root.__boot.f3 = function() {', 1)[1].rsplit('};', 1)[0]
new_body = text.split('_root.__boot.f3_1 = function() {', 1)[1].rsplit('};', 1)[0]
new_body = new_body.replace('};\n_root.__boot.f3_2 = function() {\n', '')
assert old_body == new_body, 'Body content/order changed'
audit = json.loads((D / 'source-scope-before.json').read_text('utf8'))
assert audit['qualified'] and audit['noOuterLocals']
for row in audit['files']:
    assert hashlib.sha256((R / row['path']).read_bytes()).hexdigest() == row['sha256']
p.write_bytes(after)
(D / 'split-source-proof.json').write_text(json.dumps({
    'qualified': True, 'beforeSha256': hashlib.sha256(before).hexdigest(),
    'afterSha256': hashlib.sha256(after).hexdigest(), 'bodyConcatenationExact': True,
    'includeOrderPreserved': True, 'noOuterLocals': True, 'sameReceiver': '_root.__boot',
    'sameStage': 's1_syncCode', 'execution': 'f3_1 then f3_2, synchronous',
    'businessSourceFilesUnchanged': True, 'utf8Bom': True}, indent=2) + '\n', 'utf8')
print('Communication chunk split: exact body concatenation, source scope and BOM passed.')
