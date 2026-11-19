"""Run module-effective CS6 publishes under the repository publisher's lease."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import asloader_artifact_set as artifact
import asloader_incremental_inputs as inputs
from asloader_toolchain import file_hash, identity, inspect

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / 'tmp/asloader-p1'
ORDER = inputs.ORDER


def write_json(file, obj):
    file.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def validation_identity():
    related = ('scripts/compile_test.ps1', 'scripts/publish-asloader-modules.ps1',
               'tools/publish_asloader_incremental.py', 'tools/asloader_artifact_set.py',
               'tools/asloader_toolchain.py', 'tools/asloader_incremental_inputs.py',
               'tools/build-choice-rewards.py', 'tools/choice_reward_catalog.py')
    return identity({rel: file_hash(ROOT / rel) for rel in related})


def capture(source, workspace, toolchain, validation, layout, records=None, projects=None, previous_projects=None):
    if file_hash(source/'scripts/compile_action.jsfl') != file_hash(ROOT/'scripts/compile_action.jsfl'):
        raise ValueError('The frozen source and the actually bound CS6 control script differ')
    if layout:
        from asloader_overlay_experiment import comparison_plan
        return comparison_plan(source, workspace, toolchain, validation, layout,
                               records_by_module=records, project_report=projects,
                               previous_projects=previous_projects)
    return inputs.collect(source, workspace, toolchain, validation, records_by_module=records,
                          project_report=projects, previous_projects=previous_projects)


def compile_evidence(run, name):
    """Hash and validate the same original bytes for BUILD and reuse."""
    paths = {'compilerSha256':run/name/'compiler_errors.txt', 'outputSha256':run/name/'compile_output.txt',
             'consoleSha256':run/(name+'.log')}
    logs = {}
    for field, path in paths.items():
        if path.resolve() != path or not path.is_file():
            raise ValueError('Missing or redirected compile evidence: ' + str(path))
        logs[field] = path.read_bytes()
        if not logs[field]:
            raise ValueError('Empty compile evidence: ' + str(path))
    diagnostics = logs['compilerSha256'].decode('utf-8-sig').strip()
    output = logs['outputSha256'].decode('utf-8-sig').strip()
    if (not re.fullmatch(r'0\s*(?:个错误|errors?),\s*0\s*(?:个警告|warnings?)', diagnostics, re.I)
            or not output or output.splitlines()[-1].strip() != '[compile] done'
            or 'ASO 32K branch detected' in output):
        raise ValueError('No healthy terminal compile evidence for '+name)
    return {field: hashlib.sha256(data).hexdigest() for field, data in logs.items()}


def origin_valid(row, name, key, sha):
    if not isinstance(row, dict) or not sha or row.get('sha256') != sha or row.get('buildKey') != key:
        return False
    origin = row.get('origin')
    if not isinstance(origin, dict) or not isinstance(origin.get('proof'), dict):
        return False
    proof = origin['proof']
    if not (origin.get('proofHash') == identity(proof)
            and proof.get('module') == name and proof.get('buildKey') == key
            and proof.get('sha256') == sha and proof.get('compilerErrors') == 0
            and proof.get('compilerWarnings') == 0 and proof.get('retry32K') == 0
            and re.fullmatch(r'[0-9]{8}T[0-9]{6}Z-[0-9a-f]{32}', str(proof.get('run','')))):
        return False
    run = LAB/'runs'/proof['run']
    try:
        evidence = compile_evidence(run, name)
    except (OSError, ValueError):
        return False
    return all(proof.get(field) == value for field, value in evidence.items())


def explain_records(row, name, current):
    origin = (row.get('origin') or {}).get('proof') or {}
    run_id = str(origin.get('run',''))
    if not re.fullmatch(r'[0-9]{8}T[0-9]{6}Z-[0-9a-f]{32}', run_id):
        return []
    path = LAB/'runs'/run_id/'effective-inputs.json'
    if not path.is_file() or path.resolve()!=path:
        return []
    try:
        inventory = json.loads(path.read_bytes())
        old = inventory.get(name) if isinstance(inventory, dict) else None
    except (OSError, ValueError):
        old = None
    if not isinstance(old, dict):
        return []
    changes = []
    for key in sorted(old.keys() | current.keys()):
        if key not in old or key not in current or old[key]!=current[key]:
            changes.append({'path':key,'before':old.get(key, 'unlisted'),'after':current.get(key,'unlisted')})
    return changes


def select_layout(experiment_layout, module_layout):
    if experiment_layout is not None:
        if module_layout is not None:
            raise ValueError('Choose either an experimental layout or a module layout')
        return experiment_layout, 'experiment'
    if module_layout is not None:
        return module_layout, 'explicit'
    return 'overlay', 'default'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flash', required=True)
    parser.add_argument('--loader', required=True)
    parser.add_argument('--timeout', type=int, required=True)
    parser.add_argument('--plan-only', action='store_true')
    parser.add_argument('--force-full', action='store_true')
    parser.add_argument('--quit-after-publish', action='store_true')
    parser.add_argument('--experiment-source', action='store_true')
    parser.add_argument('--experiment-output')
    parser.add_argument('--layout', choices=('mirror', 'overlay'))
    parser.add_argument('--module-layout', choices=('mirror', 'overlay'))
    parser.add_argument('--force-module', choices=ORDER)
    args = parser.parse_args()
    if not re.fullmatch(r'm1:[0-9A-F]{24}:' + str(os.getppid()) + r':[0-9a-f]{32}',
                        os.environ.get('CF7_FLASH_COMPILE_LEASE', '')):
        raise ValueError('Use scripts/publish-asloader-modules.ps1 to acquire the repository compile lease')
    if (args.experiment_source or args.layout) and not args.experiment_output:
        raise ValueError('Experimental sources and layouts require an isolated output')
    source = LAB / 'bench-source' if args.experiment_source else ROOT
    destination = ROOT
    if args.experiment_output:
        if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,55}', args.experiment_output):
            raise ValueError('ExperimentOutput must be a short directory name')
        destination = LAB / 'outputs' / args.experiment_output
    layout, selection = select_layout(args.layout, args.module_layout)
    # The paired experiment uses one fixed XFL location for both layouts.
    # A developer can switch back to their existing mirror workspace.
    projection = layout if selection == 'experiment' or layout == 'overlay' else None
    if projection:
        workspace = LAB / ('overlay-workspace' if args.experiment_source else 'overlay-live')
    else:
        workspace = LAB / ('workspace' if args.experiment_source else 'live')
    if any(path.resolve() != path for path in (source, destination, workspace)):
        raise ValueError('Redirected build directories are unsupported')
    if not source.is_dir():
        raise ValueError('Missing build source: ' + str(source))
    if not args.plan_only:
        destination.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex
    run = LAB / 'runs' / run_id
    receipt = {'schema':'cf7-asloader-run.v1', 'run': run_id, 'state':'planning',
               'source':str(source), 'destination':str(destination), 'workspace':str(workspace),
               'layout':layout, 'layoutSelection':selection,
               'runScope':'worktree' if destination == ROOT else 'candidate',
               'forceFull':args.force_full, 'forcedModule':args.force_module,
               'operations':{}, 'phases':{}, 'modules':{}, 'publishCount':0}
    print(f'Module layout: {layout} ({selection})', flush=True)
    if not args.plan_only:
        run.mkdir(parents=True)
        print('Module run:', run, flush=True)

    def timed(label, function, *values, **kwargs):
        begin = time.perf_counter()
        try:
            return function(*values, **kwargs)
        finally:
            receipt['phases'][label] = round(time.perf_counter() - begin, 3)

    def command(label, argv, cwd):
        if args.plan_only:
            subprocess.run(argv, cwd=cwd, check=True, stdout=subprocess.DEVNULL)
            return
        with (run/(label+'.log')).open('wb') as log:
            result = timed(label, subprocess.run, argv, cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise ValueError(f'{label} exited {result.returncode}. See {run/(label+".log")}')

    try:
        prior = timed('readActive', artifact.read_status, destination, diagnostic=args.plan_only)
        if prior.get('state') == 'INVALID':
            receipt['installationBlocked'] = prior['reason']
        # The existing assembler owns the authored boot sources. Keep its public
        # regeneration behavior for builds, and make the read-only entry check it.
        command('assemble', ['node', 'tools/assemble-collapsed-frame.js', '--check'] if args.plan_only
                else ['node','tools/assemble-collapsed-frame.js'], source)
        command('reward-check', [sys.executable,'-B','-X','utf8','tools/build-choice-rewards.py','--check'], source)
        toolchain, toolchain_description = timed('toolchain', inspect, ROOT, args.flash, args.loader)
        validation = validation_identity()
        details = {}
        active = prior['active'] or {}
        receipt['hadActiveSet'] = bool(active)
        receipt['previousLayout'] = active.get('layout')
        previous_projects = active.get('projectOutputs')
        projects = None if selection == 'experiment' else {}
        plan, files = timed('plan', capture, source, workspace, toolchain, validation, projection,
                            details, projects, previous_projects)
        if projects is not None:
            receipt['projectChanges'] = projects['changes']
            if projects['changes'] and not args.plan_only:
                timed('syncProjects', inputs.sync_projects, source, projects, projects.get('canonicalWrites', files))
                # Templates can also be inputs. Rebind the run to the actual
                # synchronized source, including the absence of retired files.
                plan, files = timed('planAfterProjectSync', capture, source, workspace, toolchain,
                                    validation, projection, details, projects, projects['ownership'])
                if projects['changes']:
                    raise ValueError('Project files changed during synchronized generation')
        receipt.update({key: plan[key] for key in ('sourceSnapshotId','validationKey','toolchainId')})
        if 'comparison' in plan:
            receipt['comparison'] = plan['comparison']
        old_rows = active.get('modules', {})
        for name in ORDER:
            row = plan['modules'][name]
            current_hash = prior['installed'][name]
            if args.force_full or args.force_module == name:
                reason = 'forced publish'
            elif not current_hash:
                reason = 'missing installed SWF'
            elif name not in old_rows:
                reason = 'no verified build receipt'
            elif active.get('layout') and active['layout'] != layout:
                reason = f"module layout changed from {active['layout']} to {layout}"
            elif old_rows[name].get('buildKey') != row['buildKey']:
                reason = 'effective module inputs, classpath or toolchain changed'
            elif not origin_valid(old_rows[name], name, row['buildKey'], current_hash):
                reason = 'missing or inconsistent original compile evidence'
            else:
                reason = ''
            receipt['operations'][name] = {'action':'BUILD' if reason else 'SKIP',
                                          'reason':reason or 'verified source key, SWF and compile origin'}
            if name in details and reason and name in old_rows:
                changes = explain_records(old_rows[name], name, details[name])
                receipt['operations'][name]['changedInputs'] = changes
                if changes:
                    print('  changed inputs:', ', '.join(c['path'] for c in changes[:3]),flush=True)
            if not reason:
                receipt['operations'][name]['originRun'] = old_rows[name]['origin']['proof']['run']
            print(name, receipt['operations'][name]['action'], receipt['operations'][name]['reason'], flush=True)
        build = [n for n in ORDER if receipt['operations'][n]['action']=='BUILD']
        if args.plan_only:
            receipt['state'] = 'invalid' if 'installationBlocked' in receipt else 'planned'
            print(json.dumps(receipt, ensure_ascii=True))
            return
        if (not build and active.get('validationKey') == plan['validationKey'] and
                (projects is None or previous_projects == projects['ownership'])):
            del files
            final_toolchain, _ = timed('verifyToolchain', inspect, ROOT, args.flash, args.loader)
            final_projects = None if projects is None else {}
            final_plan, _ = timed('verifyLive', capture, source, workspace, final_toolchain, validation_identity(),
                                  projection, None, final_projects, previous_projects)
            if final_projects is not None and (final_projects['changes'] or
                    final_projects['ownership'] != previous_projects):
                raise ValueError('Project outputs changed during no-op plan')
            if final_plan != plan:
                raise ValueError('Inputs or verification policy changed during no-op plan')
            command('reward-final-check', [sys.executable,'-B','-X','utf8','tools/build-choice-rewards.py','--check'], source)
            if artifact.read_status(destination) != prior:
                raise ValueError('Active set changed during no-op plan')
            receipt['modules'] = old_rows
            receipt['state'] = 'reused'
            return
        write_json(run/'plan.json', plan)
        if build:
            write_json(run/'effective-inputs.json', details)
            write_json(run/'toolchain.json', toolchain_description)
        timed('freeze', inputs.materialize, source, workspace, plan, files, verify=False)
        del files
        if not build:
            # The equal-policy no-op already returned. No child will run its
            # usual frozen BOM gate during this validation-only request.
            command('module-bom',['node','tools/check-bom.js','--root',str(workspace),'--module-scope'],workspace)
        for name in ORDER:
            row = plan['modules'][name]
            swf, xfl = workspace/row['swf'], workspace/row['xfl']
            if name not in build:
                # The active reader snapshot is checked again by set commit.
                shutil.copyfile(destination/row['swf'], swf)
                if file_hash(swf) != prior['installed'][name]:
                    raise ValueError('Changed installed SWF during candidate assembly: '+name)
                receipt['modules'][name] = old_rows[name]
                continue
            argv = ['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'scripts/compile_test.ps1'),
                    '-ModuleWorkspace',str(workspace),'-Target',str(xfl),'-VerifySwf',str(swf),
                    '-PublishOnly','-TimeoutSeconds',str(args.timeout)]
            if args.quit_after_publish:
                argv.append('-QuitFlashAfterPublish')
            receipt['publishCount'] += 1
            stage = run/name
            stage.mkdir()
            try:
                command(name, argv, ROOT)
            finally:
                for filename in ('compiler_errors.txt','compile_output.txt'):
                    src = ROOT/'scripts'/filename
                    if src.is_file():
                        shutil.copyfile(src,stage/filename)
            evidence = compile_evidence(run, name)
            sha = file_hash(swf)
            proof = {'run':run_id,'module':name,'target':str(xfl),'buildKey':row['buildKey'],'sha256':sha,
                     'compilerErrors':0,'compilerWarnings':0,'retry32K':0,
                     **evidence}
            receipt['modules'][name] = {'sha256':sha,'buildKey':row['buildKey'],
                                        'origin':{'proofHash':identity(proof),'proof':proof}}
        command('ownership',['node','tools/audit-as2-class-embedding.js','--swf','scripts/asLoader.swf','--no-cache'],workspace)
        command('inheritance',['node','tools/check-as2-inheritance-order.js','--modules'],workspace)
        final_toolchain, _ = timed('verifyToolchain', inspect, ROOT, args.flash, args.loader)
        final_projects = None if projects is None else {}
        checked, files = timed('verifyLive', capture, source, workspace, final_toolchain, validation_identity(),
                               projection, None, final_projects, projects['ownership'] if projects else None)
        if final_projects is not None and (final_projects['changes'] or
                final_projects['ownership'] != projects['ownership']):
            raise ValueError('Project outputs drifted during compile; preserving the live files')
        if checked != plan:
            raise ValueError('Inputs or verification policy changed while compiling; candidate retained')
        timed('verifyFrozen', inputs.materialize, source, workspace, checked, files, verify=True)
        del files
        command('reward-final-check', [sys.executable,'-B','-X','utf8','tools/build-choice-rewards.py','--check'], source)
        record = {k:receipt[k] for k in ('run','sourceSnapshotId','validationKey','toolchainId','layout','modules')}
        if projects is not None:
            record['projectOutputs'] = projects['ownership']
        timed('setCommit', artifact.commit, destination, workspace, record, prior)
        receipt['state'] = 'compiled' if build else 'revalidated'
    except BaseException as exc:
        receipt['state'] = 'failed'
        receipt['error'] = str(exc)
        raise
    finally:
        receipt['wallSeconds'] = round(time.perf_counter()-started, 3)
        if not args.plan_only:
            write_json(run/'result.json', receipt)
            print(f"{receipt['state']} | {receipt['publishCount']}/3 CS6 publishes | {receipt['wallSeconds']} s | {run}",flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as exc:
        sys.exit('asLoader incremental: ' + str(exc))
