"""Project the captured AS2 inputs into a fixed mirror or overlay CS6 workspace."""
import argparse
import json
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

from asloader_incremental_inputs import (CATALOG, CLASSES, MIRRORS, ORDER,
                                        collect, key, materialize, sha)


def comparison_plan(root, snapshot, toolchain, validation, layout, *, records_by_module=None,
                    project_report=None, previous_projects=None):
    if layout not in ('mirror', 'overlay'):
        raise ValueError('Unsupported module classpath layout: ' + str(layout))
    records = {} if layout == 'overlay' else records_by_module
    result, frozen = collect(root, snapshot, toolchain, validation, records_by_module=records,
                             project_report=project_report, previous_projects=previous_projects)
    if project_report is not None:
        # sync_projects expects the generator's canonical bytes. Keep only its
        # pending writes before replacing the workspace's publish profiles.
        project_report['canonicalWrites'] = {c['path']: frozen[c['path']] for c in project_report['changes']
                                            if c['after'] is not None}
    catalog = json.loads(frozen[CATALOG])
    owners = {name.replace('.', '/') + '.as': module for module in ORDER
              for name in catalog[module]['classes']}
    recipe = sha(Path(__file__).read_bytes())
    source_id = result['sourceSnapshotId']
    counts = {}
    for module in ORDER:
        row = result['modules'][module]
        mirror = f'{MIRRORS}{module}/types/'
        stubs = f'tmp/asloader-overlay/{module}/stubs/'
        profile = str(Path(row['xfl']).parent.as_posix()) + '/PublishSettings.xml'
        old = f'../{mirror.rstrip("/")};类定义;'
        new = f'../{stubs.rstrip("/")};类定义;'
        settings = frozen[profile]
        if ET.fromstring(settings).findtext('.//PackagePaths') != old:
            raise ValueError('Unexpected module classpath: ' + profile)
        declared = effective = 0
        physical = {}
        for rel in [p for p in frozen if p.startswith(mirror)]:
            name = rel[len(mirror):]
            original = frozen[rel]
            foreign = name in owners and owners[name] != module
            if layout == 'overlay':
                del frozen[rel]
                if foreign:
                    frozen[stubs + name] = original
                physical[rel] = (stubs if foreign else CLASSES) + name
                # Simulate ordered lookup of every visible class file. CS6 precedence
                # and runtime behaviour are measured separately by a forced publish.
                if frozen.get(stubs + name, frozen[CLASSES + name]) != original:
                    raise ValueError('Overlay changes effective source bytes: ' + rel)
            declared += int(foreign)
            effective += 1
        if layout == 'overlay':
            before = ('<PackagePaths>' + old + '</PackagePaths>').encode()
            after = ('<PackagePaths>' + new + '</PackagePaths>').encode()
            if settings.count(before) != 1:
                raise ValueError('Module must have exactly one effective classpath: ' + profile)
            frozen[profile] = settings.replace(before, after)
            actual = {}
            for path, digest in records[module].items():
                if path == profile:
                    digest = sha(frozen[profile])
                elif path.startswith(mirror):
                    candidate = stubs + path[len(mirror):]
                    path = physical.get(path, candidate)
                    if path != candidate:
                        # An owned/loose source, including a neighbouring class
                        # macro, falls back only because no foreign stub shadows it.
                        actual[candidate] = None
                elif path.startswith(MIRRORS):
                    if digest is not None:
                        raise ValueError('Cross-module generated include needs an explicit overlay mapping: ' + path)
                    path = 'tmp/asloader-overlay/' + path[len(MIRRORS):]
                if path in actual and actual[path] != digest:
                    raise ValueError('Conflicting effective input bytes: ' + path)
                actual[path] = digest
            row['inputCount'] = len(actual)
            if records_by_module is not None:
                records_by_module[module] = actual
        counts[module] = {'visibleTypes': effective, 'foreignDeclarations': declared,
                          'projectedTypeFiles': declared if layout == 'overlay' else effective}
        inputs = [recipe, layout, row['compileDigest'], sha(frozen[profile])]
        if layout == 'overlay':
            inputs.append(actual)
        row['compileDigest'] = key('overlay-experiment-compile-v1', inputs)
        row['buildKey'] = key('overlay-experiment-build-v1', [row['buildKey'], row['compileDigest']])
    if layout == 'overlay':
        del frozen[MIRRORS + 'manifest.json']  # The mirror generator lists files absent in the overlay.
    result['comparison'] = {'layout': layout, 'sourceId': source_id, 'modules': counts}
    result['sourceSnapshotId'] = key('overlay-experiment-snapshot-v1', [source_id, recipe, layout])
    return result, frozen


def main():
    project = Path(__file__).resolve().parents[1]
    experiment = project / 'tmp/asloader-p1'
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('plan', 'prepare', 'verify'))
    parser.add_argument('--root', type=Path, default=project)
    parser.add_argument('--snapshot', type=Path)
    parser.add_argument('--layout', choices=('mirror', 'overlay'), required=True)
    parser.add_argument('--toolchain-id', required=True)
    parser.add_argument('--validation-id', default='')
    args = parser.parse_args()
    try:
        root = args.root.absolute()
        snapshot = experiment / ('overlay-live' if root == project else 'overlay-workspace')
        if (root not in (project, experiment / 'bench-source') or (args.snapshot and args.snapshot.absolute() != snapshot)
                or root.resolve() != root or snapshot.resolve() != snapshot):
            raise ValueError('Use the fixed overlay-workspace and its project or bench-source.')
        result, files = comparison_plan(root, snapshot, args.toolchain_id, args.validation_id, args.layout)
        if args.action != 'plan':
            materialize(root, snapshot, result, files, verify=args.action == 'verify')
    except (OSError, ValueError, KeyError, ET.ParseError) as exc:
        print('ASLoader overlay experiment: ' + str(exc), file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=True, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    sys.exit(main())
