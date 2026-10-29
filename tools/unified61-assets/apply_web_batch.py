"""Apply the five reviewed workbench candidates as one disjoint, backed-up batch.

All original workbench input, output and candidate guards are checked before
writing. This avoids invalidating four sibling candidates by applying only one.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/asset-workbench'))
import core


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--jobs-file', required=True, type=Path)
    args = parser.parse_args()
    jobs = json.loads(args.jobs_file.read_text('utf-8'))
    expected = {s['name'] for s in json.loads((Path(__file__).with_name('design.json')).read_text('utf-8'))['items']}
    assert {j['item'] for j in jobs} == expected and len(jobs) == 5
    batch = ROOT / 'tmp/unified61-assets/web-application'
    journal_path = batch / 'transaction.json'
    with core.workspace_lock():
        if journal_path.exists():
            journal = json.loads(journal_path.read_text('utf-8'))
            if journal['state'] == 'applied':
                assert all(core.digest(core.safe_path(ROOT, r['path'])) == r['after'] for r in journal['files'])
                print(json.dumps({'state': 'applied', 'files': len(journal['files']), 'reused': True}))
                return
            raise RuntimeError('An unfinished batch journal needs exact-file recovery before another write')
        icons = core.read_json(ROOT / core.ICONS / 'manifest.json', {})
        dress = core.read_json(ROOT / core.DRESS / 'manifest.json', {})
        old_icons = dict(icons)
        old_skins = dict(dress.get('skinKeys', {}))
        old_items = dict(dress.get('items', {}))
        files = {}
        selected_icons, selected_skins = set(), set()
        for entry in jobs:
            folder = core.job_path(entry['jobId'])
            job = core.status(entry['jobId'])
            assert job['state'] == 'ready' and job['item'] == entry['item']
            baseline = core.read_json(folder / 'baseline.json')
            core.check_snapshot(baseline['inputs'], 'Source changed')
            core.check_snapshot(baseline['files'], 'Destination changed')
            assert all(core.digest(core.safe_path(folder, p)) == digest for p, digest in baseline['candidates'].items())
            assert (folder / 'source-map.xml').read_bytes() == (ROOT / core.MAP).read_bytes()
            result = core.read_json(folder / 'result.json')
            assert set(result['icons']) == {'Codex-' + entry['item']}
            for name, value in result['icons'].items():
                assert name not in selected_icons
                selected_icons.add(name)
                core.validate_images(value, folder / 'preview/after/icons')
                icons[name] = value
                for uri in core.image_refs(value):
                    files[core.ICONS + '/' + uri] = core.safe_path(folder / 'preview/after/icons', uri).read_bytes()
            for name, value in result['skins'].items():
                assert name not in selected_skins and 'Codex-统合61式' in name
                selected_skins.add(name)
                core.validate_images(value, folder / 'preview/after/dressup', True)
                dress.setdefault('skinKeys', {})[name] = value
                for uri in core.image_refs(value):
                    files[core.DRESS + '/' + uri] = core.safe_path(folder / 'preview/after/dressup', uri).read_bytes()
            dress.setdefault('items', {})[entry['item']] = result['item']
        assert len(selected_icons) == 5 and len(selected_skins) == 20
        assert all(icons[k] == v for k, v in old_icons.items() if k not in selected_icons)
        assert all(dress['skinKeys'][k] == v for k, v in old_skins.items() if k not in selected_skins)
        assert all(dress['items'][k] == v for k, v in old_items.items() if k not in expected)
        files[core.ICONS + '/manifest.json'] = core.json_bytes(icons)
        files[core.DRESS + '/manifest.json'] = core.json_bytes(dress)
        report = core.read_json(ROOT / core.DRESS / 'report.json', {})
        core.module('bake-dressup-offline').attach_animation_summary(dress, report)
        report['unified61Batch'] = {'items': sorted(expected), 'jobs': [j['jobId'] for j in jobs],
                                   'validation': 'frozen_inputs_candidates_and_selected_images_frames_origins'}
        files[core.DRESS + '/report.json'] = core.json_bytes(report)
        batch.mkdir(parents=True, exist_ok=True)
        records = []
        for relative, content in files.items():
            path = core.safe_path(ROOT, relative)
            before = path.read_bytes() if path.exists() else None
            # These are new names. Never overwrite an unrelated hash-collision image.
            if path.suffix.lower() in ('.png', '.webp') and before is not None and before != content:
                raise RuntimeError('Existing image collision: ' + relative)
            if before == content:
                continue
            backup = batch / 'before' / relative
            if before is not None:
                backup.parent.mkdir(parents=True, exist_ok=True)
                backup.write_bytes(before)
            records.append({'path': relative, 'before': sha(before) if before is not None else None, 'after': sha(content)})
        journal = {'state': 'applying', 'items': sorted(expected), 'jobs': jobs, 'files': records}
        core.write_json(journal_path, journal)
        written = []
        try:
            for record in records:
                path = core.safe_path(ROOT, record['path'])
                assert core.digest(path) == record['before']
                path.parent.mkdir(parents=True, exist_ok=True)
                temporary = path.with_name(path.name + '.unified61-' + uuid.uuid4().hex)
                temporary.write_bytes(files[record['path']])
                os.replace(temporary, path)
                written.append(record)
            assert all(core.digest(core.safe_path(ROOT, r['path'])) == r['after'] for r in records)
        except Exception:
            for record in reversed(written):
                path = core.safe_path(ROOT, record['path'])
                if core.digest(path) != record['after']:
                    raise RuntimeError('Output changed during rollback; preserve journal')
                if record['before'] is None:
                    path.unlink()
                else:
                    path.write_bytes((batch / 'before' / record['path']).read_bytes())
            journal['state'] = 'rolled_back'
            core.write_json(journal_path, journal)
            raise
        journal['state'] = 'applied'
        core.write_json(journal_path, journal)
        print(json.dumps({'state': 'applied', 'items': 5, 'skins': 20, 'files': len(records), 'unrelatedEntriesUnchanged': True}))


if __name__ == '__main__':
    main()
