#!/usr/bin/env node
'use strict';

/**
 * tooltip-parity 编排器：samples+scenarios → web-shoot（Edge 真实渲染）
 * → native-fixture（生产 Widget 离屏 Form）→ compare（PNG/几何/滚动判定）。
 *
 * 用法：
 *   node run.js --samples <f> --scenarios <f> --out <dir>
 *               --baseline <dir> [--baseline <dir>...]
 *               [--mode legacy|doc] [--cases a,b,c]
 *               [--skip-web] [--skip-native] [--skip-compare]
 *               [--dotnet <path>] [--repo <dir>]
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const HERE = __dirname;
const DEFAULT_DOTNET_CANDIDATES = [
    process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Microsoft', 'dotnet', 'dotnet.exe'),
    process.env.ProgramFiles && path.join(process.env.ProgramFiles, 'dotnet', 'dotnet.exe')
].filter(Boolean);

function fail(msg) { console.error('FAIL: ' + msg); process.exit(1); }

function parseArgs(argv) {
    const out = { baselines: [], mode: 'legacy' };
    for (let i = 2; i < argv.length; i++) {
        const a = argv[i], next = () => argv[++i];
        if (a === '--samples') out.samples = next();
        else if (a === '--scenarios') out.scenarios = next();
        else if (a === '--out') out.out = next();
        else if (a === '--baseline') out.baselines.push(next());
        else if (a === '--mode') out.mode = next();
        else if (a === '--cases') out.cases = next();
        else if (a === '--thresholds') out.thresholds = next();
        else if (a === '--preset') out.preset = next();
        else if (a === '--repo') out.repo = next();
        else if (a === '--dotnet') out.dotnet = next();
        else if (a === '--no-png') out.noPng = true;
        else if (a === '--skip-web') out.skipWeb = true;
        else if (a === '--skip-native') out.skipNative = true;
        else if (a === '--skip-compare') out.skipCompare = true;
        else fail('unknown arg: ' + a);
    }
    if (!out.samples || !out.scenarios || !out.out)
        fail('required: --samples --scenarios --out');
    if (!out.skipWeb && !out.baselines.length)
        fail('web side needs at least one --baseline (parity-web 冻结目录 + baseline-extra)');
    out.repo = out.repo || path.resolve(HERE, '..', '..', '..');
    if (!out.dotnet) out.dotnet = DEFAULT_DOTNET_CANDIDATES.find(p => fs.existsSync(p)) || 'dotnet';
    return out;
}

function runStep(name, cmd, args, opts) {
    process.stdout.write('== ' + name + ' ==\n' + cmd + ' ' + args.join(' ') + '\n');
    const r = spawnSync(cmd, args, Object.assign({ stdio: 'inherit', shell: false }, opts || {}));
    if (r.error) fail(name + ' spawn error: ' + r.error.message);
    if (r.status !== 0) fail(name + ' exit ' + r.status);
}

function main() {
    const a = parseArgs(process.argv);
    const out = path.resolve(a.out);
    fs.mkdirSync(out, { recursive: true });
    const manifest = { schema: 'cf7.tooltip-parity-run.v1', at: new Date().toISOString(), args: a, steps: [] };

    if (!a.skipWeb) {
        const args = [path.join(HERE, 'web-shoot.js'),
            '--samples', a.samples, '--scenarios', a.scenarios,
            '--out', out, '--mode', a.mode];
        for (const b of a.baselines) args.push('--baseline', b);
        if (a.cases) args.push('--cases', a.cases);
        if (a.noPng) args.push('--no-png');
        runStep('web-shoot', process.execPath, args);
        manifest.steps.push('web-shoot');
    }
    if (!a.skipNative) {
        runStep('native-build', a.dotnet,
            ['build', path.join(HERE, 'native-fixture', 'ParityFixture.csproj'), '-v:m', '--nologo']);
        const args = ['run', '--project', path.join(HERE, 'native-fixture', 'ParityFixture.csproj'), '--no-build', '--',
            '--samples', a.samples, '--scenarios', a.scenarios, '--out', out, '--repo', a.repo];
        if (a.cases) args.push('--cases', a.cases);
        runStep('native-fixture', a.dotnet, args);
        manifest.steps.push('native-fixture');
    }
    if (!a.skipCompare) {
        const args = [path.join(HERE, 'compare.js'), '--out', out];
        if (a.cases) args.push('--cases', a.cases);
        if (a.thresholds) args.push('--thresholds', a.thresholds);
        if (a.preset) args.push('--preset', a.preset);
        // compare 用 exit 2 表示存在 fail case——编排层不视为运行错误，继续产出 summary。
        process.stdout.write('== compare ==\n');
        const r = spawnSync(process.execPath, args, { stdio: 'inherit' });
        manifest.compareExit = r.status;
        manifest.steps.push('compare');
    }
    fs.writeFileSync(path.join(out, 'run-manifest.json'), JSON.stringify(manifest, null, 1));
    process.stdout.write('run done → ' + out + '\n');
    // 差异证据先落盘，但自动调用者仍须得到失败状态，不能把出图成功当一致。
    if (!a.skipCompare && manifest.compareExit !== 0)
        process.exitCode = manifest.compareExit === 2 ? 2 : 1;
}

main();
