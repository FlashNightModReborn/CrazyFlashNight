"""Plan, freeze and verify module-effective inputs for the AS2 module publisher."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import os
import posixpath
import re
import stat
import sys
import tempfile
import time
from pathlib import Path
from xml.etree import ElementTree as ET


def load_builder():
    path = Path(__file__).with_name('build-asloader-modules.py')
    spec = importlib.util.spec_from_file_location('asloader_module_builder', path)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    return builder


builder = load_builder()
ORDER = builder.ORDER
CLASSES = 'scripts/类定义/'
MIRRORS = 'tmp/asloader-modules/'
CATALOG = 'tools/asloader-modules.json'
MAIN = 'CRAZYFLASHER7MercenaryEmpire.swf'
MARKER = '.asloader-snapshot-v1.json'
RECIPES = ('tools/build-asloader-modules.py', 'tools/asloader_module_api.py',
           'tools/asloader_incremental_inputs.py', 'tools/asloader-definition-frames.js',
           'tools/assemble-collapsed-frame.js', 'scripts/compile_action.jsfl')
VALIDATORS = ('tools/check-bom.js', 'tools/audit-as2-class-embedding.js',
              'tools/check-as2-inheritance-order.js', 'tools/swf-function-sizes.js',
              'tools/asloader-module-catalog.js', 'tools/swf-metadata.js')
COMMENT = re.compile(r'''("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|/\*[\s\S]*?\*/|//[^\r\n]*''')
DIRECTIVE = re.compile(r'^[ \t]*#\s*include\b([^\r\n]*)', re.M)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def key(domain, value):
    return sha(json.dumps([domain, value], ensure_ascii=False, sort_keys=True,
                          separators=(',', ':')).encode())


def relative(base, name):
    name = name.replace('\\', '/')
    if not name or re.search(r'[:*?"<>|\x00-\x1f]', name) or name.startswith('/'):
        raise ValueError('Unsupported source path: ' + name)
    path = posixpath.normpath(posixpath.join(base, name))
    if path in ('.', '..') or path.startswith('../'):
        raise ValueError('Source path escapes snapshot: ' + name)
    return path


def includes(data):
    if b'#' not in data or b'include' not in data:
        return []
    source = data.decode('utf-8-sig')
    source = COMMENT.sub(lambda m: m[1] if m[1] is not None else
                         re.sub(r'[^\r\n]', ' ', m[0]), source)
    targets = []
    for arg in DIRECTIVE.findall(source):
        match = re.fullmatch(r'''[ \t]*(["'])([^"'\r\n]+)\1[ \t]*;?[ \t]*''', arg)
        if not match:
            raise ValueError('Unsupported AS2 include: ' + arg)
        targets.append(match[2])
    return targets


def read_owned(root, rel):
    path = root / rel
    if path.resolve() != path or not path.is_file():
        raise ValueError('Missing or redirected source: ' + rel)
    return path.read_bytes()


def regular_tree(directory, prefix=''):
    """Yield the native path and relative spelling without a second path lookup."""
    with os.scandir(directory) as entries:
        for entry in entries:
            if entry.is_symlink() or (os.name == 'nt' and
                    entry.stat(follow_symlinks=False).st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT):
                raise ValueError('Redirected source in snapshot namespace: ' + entry.path)
            rel = prefix + entry.name
            if entry.is_dir(follow_symlinks=False):
                yield from regular_tree(entry.path, rel + '/')
            elif entry.is_file(follow_symlinks=False):
                yield rel, entry.path
            else:
                raise ValueError('Unsupported file type: ' + entry.path)


def read_batches(entries, read_batch):
    # A small queue overlaps independent NTFS opens without flooding the volume.
    if len(entries) <= 32:
        return read_batch(entries)
    batches = (entries[i:i + 32] for i in range(0, len(entries), 32))
    with ThreadPoolExecutor(max_workers=4) as workers:
        return [row for batch in workers.map(read_batch, batches) for row in batch]


def read_classes(entries):
    result = []
    for rel, path in entries:
        with open(path, 'rb') as source:
            result.append((rel, source.read()))
    return result


def project_bytes(root, rel):
    if relative('', rel) != rel or not rel.startswith('scripts/'):
        raise ValueError('Unmanaged generator output: ' + rel)
    path = root/rel
    if path.resolve() != path:
        raise ValueError('Redirected generator output: ' + rel)
    return read_owned(root, rel) if os.path.lexists(path) else None


def project_inventory(root, catalog, previous):
    projects = {m: catalog[m]['xfl'] for m in ORDER}
    names = {p for row in builder.project_paths(catalog).values() for p in row.values()}
    old = {}
    if previous and previous.get('sourceRoot') == str(root):
        old_catalog = {m: {'xfl': previous['projects'][m]} for m in ORDER}
        allowed = {p for row in builder.project_paths(old_catalog).values() for p in row.values()}
        old = previous['outputs']
        if old.keys() != allowed or any(not re.fullmatch(r'[0-9a-f]{64}', h) for h in old.values()):
            raise ValueError('Invalid previous project-output ownership')
    observed = {p: project_bytes(root, p) for p in sorted(names | old.keys())}
    return projects, names, old, observed


def sync_projects(root, project, files):
    """Only replace captured generator-owned bytes. Other project assets stay untouched."""
    changes = project['changes']
    def inspect(change):
        current = project_bytes(root, change['path'])
        actual = sha(current) if current is not None else None
        if actual not in (change['before'], change['after']):
            raise ValueError('Project output changed after capture: ' + change['path'])
        return actual != change['after']
    for change in changes:
        inspect(change)
    for change in changes:
        if not inspect(change):
            continue
        rel, expected = change['path'], change['after']
        target = root/rel
        if expected is None:
            target.unlink()
        else:
            data = files[rel]
            if sha(data) != expected:
                raise ValueError('Generator output does not match plan: ' + rel)
            write_atomic(target, data)


def collect(root, snapshot, toolchain, validation, *, records_by_module=None,
            project_report=None, previous_projects=None):
    root, snapshot = root.resolve(), snapshot.absolute()
    if not toolchain.strip():
        raise ValueError('Toolchain identity is required')
    if snapshot == root or snapshot in root.parents or (
            root in snapshot.parents and snapshot.relative_to(root).parts[0] != 'tmp'):
        raise ValueError('Use a dedicated snapshot outside the source tree or below its tmp directory')
    catalog_bytes = read_owned(root, CATALOG)
    catalog = json.loads(catalog_bytes)
    observed = None
    if project_report is not None:
        projects, project_names, old_projects, observed = project_inventory(root, catalog, previous_projects)
    templates = None if observed is None else {
        p: observed[p] if p in observed else read_owned(root, p)
        for p in ('scripts/asLoader/PublishSettings.xml', 'scripts/asLoader/DOMDocument.xml')}
    class_dir = root / CLASSES
    if class_dir.resolve() != class_dir:
        raise ValueError('Redirected class source directory')
    class_files = [entry for entry in regular_tree(class_dir) if entry[0].lower().endswith('.as')]
    # Match the generator's platform-specific Path ordering, including on Windows.
    class_files.sort(key=lambda entry: Path(entry[0]))
    class_sources = dict(read_batches(class_files, read_classes))
    profile_bytes = (templates['scripts/asLoader/PublishSettings.xml'] if templates is not None else
                     read_owned(root, 'scripts/asLoader/PublishSettings.xml'))
    common_profile = ET.fromstring(profile_bytes)
    if common_profile.findtext('.//PackagePaths') not in (
            '类定义;', '../tmp/asloader-modules/boot/types;类定义;'):
        raise ValueError('Unmanaged AS2 PackagePaths in boot PublishSettings.xml')
    generated, manifest = builder.plan(root, class_sources=class_sources, template_bytes=templates)
    if project_report is not None:
        desired = {p: sha(data) for p, data in generated.items() if p.startswith('scripts/')}
        if desired.keys() != project_names:
            raise ValueError('Generator project output paths changed during capture')
        changes = []
        for p, data in observed.items():
            before = sha(data) if data is not None else None
            after = desired.get(p)
            if before == after:
                continue
            if after is None and before != old_projects[p]:
                raise ValueError('Retired project file has unrecognized bytes: ' + p)
            if old_projects and before is not None and p not in templates and before != old_projects.get(p):
                raise ValueError('Project file differs from both known and generated bytes: ' + p)
            changes.append({'path': p, 'before': before, 'after': after})
        project_report.update(changes=changes, ownership={'sourceRoot': str(root),
                              'projects': projects, 'outputs': desired})
    if class_sources.keys() != {rel for rel, _ in regular_tree(class_dir) if rel.lower().endswith('.as')}:
        raise ValueError('Class namespace changed during capture')
    frozen = dict(generated)
    owners = {name.replace('.', '/') + '.as': module for module in ORDER
              for name in catalog[module]['classes']}
    for rel, expected in manifest['inputs'].items():
        if rel.startswith(CLASSES):
            name = rel[len(CLASSES):]
            owner = owners.get(name, 'resident')
            data = generated[f'{MIRRORS}{owner}/types/{name}']
        else:
            data = read_owned(root, rel)
        if sha(data) != expected or (rel in generated and generated[rel] != data):
            raise ValueError('Source drift or stale generated input: ' + rel)
        frozen[rel] = data
    if frozen[CATALOG] != catalog_bytes:
        raise ValueError('Module catalog changed during capture')
    for rel in (*RECIPES, *VALIDATORS, MAIN):
        if rel not in frozen:
            frozen[rel] = read_owned(root, rel)
    for name in ('build-asloader-modules.py', 'asloader_module_api.py', 'asloader_incremental_inputs.py'):
        if frozen['tools/' + name] != Path(__file__).with_name(name).read_bytes():
            raise ValueError('Source uses a different planner or generator: ' + name)
    recipe_key = key('asloader-recipe-v1', {p: sha(frozen[p]) for p in RECIPES})
    location = key('asloader-location-v1', [os.path.normcase(str(root)),
                                            os.path.normcase(str(snapshot))])
    memo = {}
    def digest(rel):
        if rel not in memo:
            memo[rel] = sha(frozen[rel])
        return memo[rel]

    def lookup(rel):
        if rel in frozen:
            return True
        # Only the generator owns these paths. A removed local projection must
        # never become visible just because an older live tmp still exists.
        if rel.startswith(MIRRORS):
            return False
        if not (root / rel).is_file():
            return False
        frozen[rel] = read_owned(root, rel)
        return True

    modules = {}
    for module in ORDER:
        row = catalog[module]
        xfl, swf = relative('', row['xfl']), relative('', row['swf'])
        project = posixpath.dirname(xfl)
        if not project.startswith('scripts/') or posixpath.dirname(swf) != 'scripts':
            raise ValueError('Unsupported module layout: ' + module)
        settings = ET.fromstring(generated[project + '/PublishSettings.xml'])
        if settings.findtext('.//flashFileName') != posixpath.basename(swf):
            raise ValueError('Output profile must target the isolated catalog SWF: ' + module)
        format_settings = settings.find('.//PublishFormatProperties')
        if format_settings is None or any(format_settings.findtext(flag) != '0'
                for flag in ('projectorWin', 'projectorMac', 'html', 'gif', 'jpeg', 'png', 'qt', 'rnwk', 'swc')):
            raise ValueError('Unmanaged additional publish outputs: ' + module)
        prefix = f'{MIRRORS}{module}/types/'
        records = {p: digest(p) for p in generated if p.startswith(prefix)}
        assets = {p for p in generated if p.startswith(project + '/')}
        asset_dir = root / project
        if asset_dir.exists():
            if asset_dir.resolve() != asset_dir:
                raise ValueError('Redirected XFL project: ' + project)
            for rel, _ in regular_tree(asset_dir, project + '/'):
                if rel != project + '/bin/SymDepend.cache':
                    assets.add(rel)
        asset_scripts = []
        for rel in sorted(assets):
            if not lookup(rel):
                raise ValueError('Missing XFL asset: ' + rel)
            records[rel] = digest(rel)
            if rel == project + '/DOMDocument.xml' or (
                    rel.startswith(project + '/LIBRARY/') and rel.endswith('.xml')):
                for node in ET.fromstring(frozen[rel]).iter():
                    tag = node.tag.rsplit('}', 1)[-1]
                    if tag == 'script' and node.text:
                        asset_scripts.append((rel, node.text.encode()))
                    if tag == 'Include' and node.get('href'):
                        target = relative(project + '/LIBRARY', node.get('href'))
                        if target not in assets:
                            raise ValueError('Uncaptured XFL library item: ' + target)
                    # Imported media must have its backing data in the XFL.
                    for attr in ('bitmapDataHRef', 'soundDataHRef'):
                        if node.get(attr) and relative(project + '/bin', node.get(attr)) not in assets:
                            raise ValueError('Uncaptured XFL asset: ' + node.get(attr))
                    for attr, value in node.attrib.items():
                        if attr in ('bitmapDataHRef', 'soundDataHRef') or (tag == 'Include' and attr == 'href'):
                            continue
                        if value and any(word in attr.lower() for word in ('href', 'fileexternal', 'filepath', 'libraryurl')):
                            raise ValueError(f'Unmanaged XFL reference {attr}={value} in {rel}')
        visited = set()
        resolving = set()
        def walk(rel, data, origin):
            visit = (rel, origin)
            if visit in resolving:
                raise ValueError('Recursive include: ' + rel)
            if visit in visited:
                return
            resolving.add(visit)
            for target in includes(data):
                bases = [project]
                if origin is not None:
                    # Preserve the projected source's physical directory, its
                    # fallback counterpart, and both configured class roots.
                    bases += [posixpath.dirname(rel), posixpath.dirname(origin),
                              prefix.rstrip('/'), CLASSES.rstrip('/')]
                hits = []
                for candidate in sorted({relative(base, target) for base in bases}):
                    exists = lookup(candidate)
                    records[candidate] = digest(candidate) if exists else None
                    if exists:
                        hits.append(candidate)
                if not hits:
                    raise ValueError(f'Unresolved include {target} from {rel}')
                for found in hits:
                    if not frozen[found].startswith(builder.BOM):
                        raise ValueError('Included AS2 source lacks UTF-8 BOM: ' + found)
                    walk(found, frozen[found], (found if origin is not None else None))
            resolving.remove(visit)
            visited.add(visit)
        for rel in list(records):
            if rel.startswith(prefix):
                walk(rel, frozen[rel], CLASSES + rel[len(prefix):])
        for rel, script in asset_scripts:
            # Multiple frames may carry distinct scripts in the same XML.
            for target in includes(script):
                found = relative(project, target)
                if not lookup(found) or not frozen[found].startswith(builder.BOM):
                    raise ValueError('Missing frame include or UTF-8 BOM: ' + found)
                records[found] = digest(found)
                walk(found, frozen[found], None)
        if records_by_module is not None:
            records_by_module[module] = dict(records)
        compiled = key('asloader-compile-v1', [recipe_key, records])
        modules[module] = {'xfl': xfl, 'swf': swf, 'compileDigest': compiled,
                           'buildKey': key('asloader-build-v1', [module, compiled, location, toolchain]),
                           'inputCount': len(records)}
    hashes = {p: digest(p) for p in frozen}
    result = {'schema': 'asloader-plan-v1', 'snapshotRoot': str(snapshot),
              'sourceSnapshotId': key('asloader-capture-v1', [hashes,
                                      {m: modules[m]['compileDigest'] for m in ORDER}]),
              'toolchainId': toolchain, 'compileLocationId': location,
              'validationKey': key('asloader-validation-v1', [validation,
                                {p: hashes[p] for p in (*VALIDATORS, MAIN, CATALOG)}]),
              'modules': modules}
    return result, frozen


def is_link(path):
    info = path.lstat()
    return (stat.S_ISLNK(info.st_mode) or
            bool(getattr(info, 'st_file_attributes', 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT))


def write_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    # New file objects prevent mutable aliases. Do not backdate from live sources.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.asloader-write-', dir=path.parent,
                                         delete=False) as out:
            temporary = Path(out.name)
            out.write(data)
        if path.exists():
            previous = path.stat().st_mtime_ns
            if temporary.stat().st_mtime_ns <= previous:
                # Two atomic writes can share a clock tick on Windows. Require
                # an observed newer disk timestamp without manufacturing a future one.
                deadline = time.monotonic() + 0.1
                while temporary.stat().st_mtime_ns <= previous:
                    if time.monotonic() >= deadline:
                        raise ValueError('No newer filesystem timestamp: ' + str(path))
                    time.sleep(0.002)
                    os.utime(temporary, None)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def materialize(root, snapshot, result, files, verify=False):
    if snapshot.resolve() != snapshot or any(is_link(p) for p in [snapshot, *snapshot.parents]
                                             if p.exists()):
        raise ValueError('Snapshot path is redirected: ' + str(snapshot))
    marker = snapshot / MARKER
    identity = {'schema': 'asloader-owned-inputs-v1', 'root': str(root),
                'workspace': str(snapshot)}
    previous = set()
    state = {}
    if marker.exists():
        if is_link(marker) or marker.stat().st_nlink != 1:
            raise ValueError('Snapshot marker is redirected')
        state = json.loads(marker.read_bytes())
        if any(state.get(k) != v for k, v in identity.items()):
            raise ValueError('Snapshot belongs to another root')
        previous.update(state['files'])
        if any(relative('', p) != p for p in previous):
            raise ValueError('Invalid snapshot ownership manifest')
        if verify and (state.get('sourceSnapshotId') != result['sourceSnapshotId'] or
                       previous != set(files)):
            raise ValueError('Snapshot changed since prepare')
    elif verify or (snapshot.exists() and any(snapshot.iterdir())):
        raise ValueError('Snapshot must be empty or owned by this planner')
    projections = {v['swf'] for v in result['modules'].values()}
    caches = {posixpath.join(posixpath.dirname(v['xfl']), 'bin/SymDepend.cache')
              for v in result['modules'].values()}
    entries = list(regular_tree(snapshot)) if snapshot.exists() else []
    existing = {rel for rel, _ in entries}
    for rel in existing:
        if (rel not in previous and rel not in files and rel != MARKER and
                rel not in projections and rel not in caches and
                not rel.startswith('tmp/swf-metadata-cache/')):
            raise ValueError('Unowned snapshot file: ' + rel)

    def compare_batch(batch):
        changed = []
        for rel, path in batch:
            if rel in files:
                # Windows DirEntry.stat() may report st_nlink=0. Query the same
                # open file handle that supplies the bytes, including equal-sized files.
                with open(path, 'rb') as stream:
                    if os.fstat(stream.fileno()).st_nlink != 1:
                        raise ValueError('Snapshot contains hard-linked file: ' + rel)
                    if stream.read() != files[rel]:
                        changed.append(rel)
            elif os.stat(path, follow_symlinks=False).st_nlink != 1:
                raise ValueError('Snapshot contains hard-linked file: ' + rel)
        return changed

    stale = set(read_batches(entries, compare_batch))
    stale.update(files.keys() - existing)
    if verify:
        if stale:
            raise ValueError('Frozen input differs: ' + min(stale))
        return
    if not stale and previous == files.keys() and state.get('sourceSnapshotId') == result['sourceSnapshotId']:
        return
    snapshot.mkdir(parents=True, exist_ok=True)
    # Record the complete ownership intent before touching this run's inputs.
    # Interrupted refreshes retain enough information for another prepare.
    intent = {**identity, 'files': sorted(previous | set(files)), 'sourceSnapshotId': None}
    write_atomic(marker, json.dumps(intent, ensure_ascii=False).encode())
    for rel in previous - files.keys():
        if rel in existing:
            (snapshot / rel).unlink()
    for rel in sorted(stale):
        write_atomic(snapshot / rel, files[rel])
    complete = {**identity, 'files': sorted(files), 'sourceSnapshotId': result['sourceSnapshotId']}
    write_atomic(marker, json.dumps(complete, ensure_ascii=False).encode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('plan', 'prepare', 'verify'))
    parser.add_argument('--root', type=Path, default=builder.ROOT)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--toolchain-id', required=True)
    parser.add_argument('--validation-id', default='')
    args = parser.parse_args()
    root, snapshot = args.root.resolve(), args.snapshot.absolute()
    try:
        result, files = collect(root, snapshot, args.toolchain_id, args.validation_id)
        if args.action != 'plan':
            materialize(root, snapshot, result, files, verify=args.action == 'verify')
    except (OSError, ValueError, KeyError, ET.ParseError) as exc:
        print('ASLoader input error: ' + str(exc), file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=True, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    sys.exit(main())
