from pathlib import Path
import argparse, hashlib, json, subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
a = parser.parse_args()
R = Path.cwd()
names = subprocess.check_output(['rg', '--files', 'launcher/src', 'launcher/tests', 'launcher/contracts']).decode('utf8').splitlines()
selected = {Path(p).as_posix() for p in names if Path(p).suffix in ('.cs', '.csproj', '.props', '.targets', '.json', '.ps1') and not ({'bin', 'obj', 'TestResults'} & set(Path(p).parts))}
selected.update(['global.json', 'launcher/CRAZYFLASHER7MercenaryEmpire.csproj',
                 'launcher/Directory.Packages.props', 'launcher/packages.lock.json',
                 'launcher/resolve-dotnet.ps1'])
assert all((R / p).is_file() for p in selected)
rows = []
for name in sorted(selected):
    data = (R / name).read_bytes()
    rows.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
with a.output.open('x', encoding='utf8') as f:
    json.dump({'files': rows}, f, ensure_ascii=False, indent=2)
print(json.dumps({'sourceBindings': len(rows)}))
