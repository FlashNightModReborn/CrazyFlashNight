from pathlib import Path
import datetime, hashlib, json, re, shutil, subprocess, zipfile

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
D = O / 'loader-size-followup'
D.mkdir(exist_ok=True)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
frame = R / 'scripts/asLoaderManifest/frame3.as'
original = frame.read_bytes()
assert original.startswith(b'\xef\xbb\xbf')
source = original.decode('utf-8-sig')
includes = re.findall(r'#include "([^"]+)"', source)
paths = [R / 'scripts' / s.removeprefix('../') for s in includes]
assert len(paths) == 9 and paths[-1].name == '通信_aka_Agent联动.as'
token_re = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[\w\u0080-\uffff]+|[^\s]', re.UNICODE)
reports = []
all_tokens = []
for p in paths:
    body = p.read_text('utf-8-sig')
    assert not re.search(r'^\s*#include\s', body, re.M), f'Unexpected nested include: {p}'
    tokens = [(m.group(), body.count('\n', 0, m.start()) + 1) for m in token_re.finditer(body)
              if not m.group().startswith(('//', '/*', '"', "'"))]
    stack, pending, depth = [], False, 0
    outer_vars, outer_declarations = [], []
    for i, (token, line) in enumerate(tokens):
        if token == 'function':
            if depth == 0 and tokens[i+1][0] != '(':
                outer_declarations.append({'name': tokens[i+1][0], 'line': line})
            pending = True
        elif token == '{':
            stack.append(pending)
            depth += int(pending)
            pending = False
        elif token == '}':
            assert stack, p
            depth -= int(stack.pop())
        elif token == 'var' and depth == 0:
            outer_vars.append({'name': tokens[i+1][0], 'line': line})
    assert not stack and depth == 0 and not pending, p
    reports.append({'path': p.relative_to(R).as_posix(), 'sha256': sha(p),
                    'outerVars': outer_vars, 'outerNamedFunctions': outer_declarations})
    all_tokens.append({t for t, _ in tokens})
left_vars = {v['name'] for r in reports[:-1] for v in r['outerVars'] + r['outerNamedFunctions']}
right_vars = {v['name'] for v in reports[-1]['outerVars'] + reports[-1]['outerNamedFunctions']}
cross = sorted((left_vars & all_tokens[-1]) | (right_vars & set.union(*all_tokens[:-1])))
audit = {'schema': 'cf6-loader-size-scope-v1', 'createdAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
         'beforeLoaderSha256': sha(R / 'scripts/asLoader.swf'), 'includeOrder': includes,
         'files': reports, 'crossBoundaryLocalReferences': cross,
         'noOuterLocals': not left_vars and not right_vars, 'qualified': not cross,
         'boundary': 'Static function-scope audit. It does not replace fresh CS6 compilation and current-loader execution.'}
(D / 'source-scope-before.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n', 'utf8')
assert not cross, cross
backup_paths = ['scripts/asLoaderManifest/frame3.as', 'scripts/asLoaderManifest/_collapsed_frame.as',
                'docs/asLoader-README.md', 'scripts/asLoader.swf', 'scripts/compile_test.ps1',
                'tools/assemble-collapsed-frame.js', 'scripts/类定义/org/flashNight/neur/Server/ServerManager.as']
backup_paths += [p.relative_to(R).as_posix() for p in paths]
with zipfile.ZipFile(D / 'before-source-and-loader.zip', 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for name in backup_paths:
        z.write(R / name, name)
shutil.copy2(R / 'scripts/asLoader.swf', D / 'asLoader-c5.swf')
shutil.copy2(frame, D / 'frame3-before.as')
for name in ['as2-ownership-ci-failure.log', 'postpush-asloader-functions.json', 'before-dabd-functions.json', 'large-frame-functions.json']:
    shutil.copy2(O / name, D / name)
print(json.dumps({'qualified': not cross, 'noOuterLocals': audit['noOuterLocals'], 'sourceFiles': reports}, ensure_ascii=False))
