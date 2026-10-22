"""A18/A19/A20/A22 background source generation via the floor_lattice pattern adapter.

Mirrors build-viewport-layer.py: the frozen pinned build-layer.py runs
in-process while batch/pattern_adapter.py extends api.Candidate for the one
confirmed vector-pattern structure. The Astra-owned converter-ready.json is
validated fail-closed through ready_contract before anything runs. Any
pre-existing content in the target layer/candidate directories is recorded
as a SHA snapshot under batch/snapshots/ first and is never trusted as a
reason to skip. CS6 is never started here; --assemble only performs the
native XFL assembly step of build-layer.py for root's serial queue.
"""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ready_contract
from pattern_adapter import candidate_class

HERE = Path(__file__).resolve().parent
NV = HERE.parent
ROOT = NV.parents[2]
SIGNAL = HERE / 'converter-ready.json'
SNAPSHOTS = HERE / 'snapshots'
MAPS = ('A18', 'A19', 'A20', 'A22')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(directory, label, files):
    if not directory.is_dir():
        return
    for path in sorted(directory.rglob('*')):
        if path.is_file():
            files.append({'path': label + '/' + path.relative_to(directory).as_posix(),
                          'sha256': sha(path), 'bytes': path.stat().st_size})


def snapshot(name):
    files = []
    inventory(NV / 'layers' / name, 'layers', files)
    candidate = ROOT / 'flashswf/backgrounds/cf6' / name
    inventory(candidate, 'candidate', files)
    swf = candidate.parent / (name + '.swf')
    if swf.is_file():
        files.append({'path': 'candidate-swf/' + swf.name, 'sha256': sha(swf), 'bytes': swf.stat().st_size})
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    receipt = {'schema': 'cf6-pattern-pre-adapter-snapshot.v1', 'name': name, 'takenAt': stamp, 'files': files,
               'policy': 'SHA snapshot only; pre-existing partial products are never reused by existence'}
    SNAPSHOTS.mkdir(exist_ok=True)
    path = SNAPSHOTS / ('pre-pattern-' + name + '-' + stamp + '.json')
    path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return {'receipt': path.relative_to(ROOT).as_posix(), 'files': len(files)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--map', required=True, choices=MAPS)
    parser.add_argument('--assemble', action='store_true')
    args = parser.parse_args()
    try:
        ready, pinned, jobs = ready_contract.load_ready()
    except ready_contract.ContractError as exc:
        raise SystemExit('ready contract rejected; wrapper refused: ' + str(exc))
    matches = [j for j in jobs if j['map'] == args.map and j['layer'] == 'background']
    if len(matches) != 1:
        raise SystemExit('no ready background job for ' + args.map)
    job = matches[0]
    name = job['name']
    previous = snapshot(name)
    spec = importlib.util.spec_from_file_location('pattern_generic', NV / 'build-layer.py')
    generic = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generic)
    PatternCandidate = candidate_class(generic.api)
    instances = []

    class TrackedCandidate(PatternCandidate):
        def __init__(self, *a, **kw):
            super().__init__(*a, **kw)
            instances.append(self)

    generic.api.Candidate = TrackedCandidate
    sys.argv = [str(NV / 'build-layer.py'), '--map', args.map, '--layer', 'background',
                '--asset-dir', ready_contract.ASSET_DIR] + (['--assemble'] if args.assemble else [])
    generic.main()
    if len(instances) != 1:
        raise ValueError('expected exactly one source converter')
    lattice = [r for r in instances[0].pattern_reports if r.get('kind') == 'native-vector-lattice']
    if len(lattice) != 1:
        raise ValueError('expected exactly one floor_lattice expansion, got ' + str(len(lattice)))
    out = NV / 'layers' / name
    report_path = out / 'report.json'
    report = json.loads(report_path.read_text(encoding='utf-8'))
    scripts = [NV / 'batch/pattern_adapter.py', Path(__file__)]
    dependencies = [{'path': s.relative_to(ROOT).as_posix(), 'sha256': sha(s), 'bytes': s.stat().st_size} for s in scripts]
    report.update(vectorPatterns=lattice, specializedConverterInputs=dependencies,
                  baselineConverterBundleSha256=ready['converterBundleSha256'], baselineSignalSha256=sha(SIGNAL),
                  preExistingProductSnapshot=previous,
                  visualEvidenceScope='Tile clip semantics verified on 2026-10-21 against a real browser engine with a translucent three-tile probe; native candidate still requires root CS6 compile and actual Flash visual comparison.')
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for source in scripts:
        (out / (source.stem + '.source.py')).write_bytes(source.read_bytes())
    print(json.dumps({'name': name, 'vectorPatterns': lattice, 'adapterInputs': dependencies,
                      'previous': previous, 'state': report['state']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
