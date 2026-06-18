#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const webRoot = path.join(projectRoot, 'launcher', 'web');
const perfRoot = path.join(projectRoot, 'launcher', 'perf');
const playwrightModule = path.join(perfRoot, 'node_modules', 'playwright');

const SLOT_LABELS = {
    head: '头部装备',
    body: '上装装备',
    hand: '手部装备',
    leg: '下装装备',
    foot: '脚部装备',
    neck: '颈部装备',
    primary: '长枪',
    secondary1: '手枪',
    secondary2: '手枪2',
    melee: '刀',
    grenade: '手雷'
};
const ARMOR_SLOTS = ['head', 'body', 'hand', 'leg', 'foot', 'neck'];
const WEAPON_SLOTS = ['primary', 'secondary1', 'secondary2', 'melee', 'grenade'];
const BODY_FIT_FIELDS = [
    '身体', '上臂', '左下臂', '右下臂', '左手', '右手',
    '屁股', '左大腿', '右大腿', '小腿', '脚',
    '脸型', '发型', '面具'
];
const BATTLE_REFERENCE_FIT_FIELDS = [
    '身体', '上臂', '左下臂', '右下臂', '左手', '右手',
    '屁股', '左大腿', '右大腿', '小腿',
    '脸型', '发型', '面具'
];
const FACE_BY_ID = {
    0: '女变装-基本脸型',
    1: '男变装-基本脸型'
};
const TARGETS = [
    { label: 'reference-midnight-neon-battle', mercName: '午夜霓虹', rig: 'battle', stateLabel: '空手站立', fitFields: BATTLE_REFERENCE_FIT_FIELDS, zoom: 1.18 },
    { label: 'female-heavy-weapon', gender: '女', weight: 'heavy', weapon: true },
    { label: 'female-heavy-no-weapon', gender: '女', weight: 'heavy', weapon: false },
    { label: 'male-heavy-weapon', gender: '男', weight: 'heavy', weapon: true },
    { label: 'male-heavy-no-weapon', gender: '男', weight: 'heavy', weapon: false },
    { label: 'male-light-weapon', gender: '男', weight: 'light', weapon: true },
    { label: 'male-light-no-weapon', gender: '男', weight: 'light', weapon: false }
];

function parseArgs(argv) {
    const args = {
        browser: 'edge',
        viewport: '1280x720',
        outDir: path.join('tmp', 'merc-dressup-probe'),
        report: '',
        headed: false
    };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--browser') {
            args.browser = argv[i + 1] || args.browser;
            i += 1;
        } else if (arg === '--viewport') {
            args.viewport = argv[i + 1] || args.viewport;
            i += 1;
        } else if (arg === '--out-dir') {
            args.outDir = argv[i + 1] || args.outDir;
            i += 1;
        } else if (arg === '--report') {
            args.report = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--headed') {
            args.headed = true;
        } else if (arg === '--help' || arg === '-h') {
            printHelp(0);
            return null;
        } else {
            printHelp(1, 'unknown arg: ' + arg);
            return null;
        }
    }
    if (!args.report) args.report = path.join(args.outDir, 'report.json');
    return args;
}

function printHelp(exitCode, error) {
    if (error) console.error(error);
    console.error('usage: node tools/run-merc-dressup-probe.js [--browser edge|chrome] [--viewport 1280x720] [--out-dir tmp/merc-dressup-probe] [--report tmp/merc-dressup-probe/report.json] [--headed]');
    process.exit(exitCode);
}

function readJson(relativePath) {
    return JSON.parse(fs.readFileSync(path.join(projectRoot, relativePath), 'utf8'));
}

function xmlText(value) {
    return String(value || '')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&amp;/g, '&');
}

function parseHairMap() {
    const xml = fs.readFileSync(path.join(projectRoot, 'data', 'items', 'hairstyle.xml'), 'utf8');
    const result = {};
    const re = /<Hair\s+id="(\d+)"[\s\S]*?<Identifier>([\s\S]*?)<\/Identifier>[\s\S]*?<\/Hair>/g;
    let match = null;
    while ((match = re.exec(xml)) !== null) {
        result[Number(match[1])] = xmlText(match[2].trim());
    }
    return result;
}

function parseHelmetSet() {
    const dir = path.join(projectRoot, 'data', 'items');
    const result = new Set();
    fs.readdirSync(dir).filter(name => name.endsWith('.xml')).forEach(fileName => {
        const xml = fs.readFileSync(path.join(dir, fileName), 'utf8');
        const itemRe = /<item\b[\s\S]*?<\/item>/g;
        let itemMatch = null;
        while ((itemMatch = itemRe.exec(xml)) !== null) {
            const block = itemMatch[0];
            if (!/<helmet>\s*true\s*<\/helmet>/i.test(block)) continue;
            const nameMatch = block.match(/<name>([\s\S]*?)<\/name>/);
            if (nameMatch) result.add(xmlText(nameMatch[1].trim()));
        }
    });
    return result;
}

function stripItemSuffix(value) {
    if (value === null || value === undefined) return '';
    return String(value).split('#', 1)[0].trim();
}

function classifyMerc(merc) {
    const equipment = merc.equipment || {};
    const armorCount = ARMOR_SLOTS.reduce((count, slot) => count + (equipment[slot] ? 1 : 0), 0);
    const weaponCount = WEAPON_SLOTS.reduce((count, slot) => count + (equipment[slot] ? 1 : 0), 0);
    let weight = 'medium';
    if (armorCount >= 5) weight = 'heavy';
    if (armorCount <= 3) weight = 'light';
    return {
        armorCount,
        weaponCount,
        weight,
        weapon: weaponCount > 0
    };
}

function chooseSamples(mercenaries) {
    const samples = [];
    const used = new Set();
    TARGETS.forEach(target => {
        if (target.mercName) {
            const named = mercenaries.find(merc => merc.name === target.mercName);
            if (named) {
                used.add(named.id);
                samples.push({ target, merc: named, classification: classifyMerc(named) });
            }
            return;
        }
        const match = mercenaries.find(merc => {
            if (used.has(merc.id)) return false;
            const cls = classifyMerc(merc);
            return merc.gender === target.gender && cls.weight === target.weight && cls.weapon === target.weapon;
        });
        if (match) {
            used.add(match.id);
            samples.push({ target, merc: match, classification: classifyMerc(match) });
        }
    });
    return samples;
}

function buildEquipment(merc) {
    const rawEquipment = merc.equipment || {};
    const equipment = {};
    const slots = [];
    Object.keys(SLOT_LABELS).forEach(slot => {
        const raw = rawEquipment[slot];
        const name = stripItemSuffix(raw);
        if (!name) return;
        equipment[slot] = name;
        slots.push({
            slot,
            label: SLOT_LABELS[slot],
            raw: String(raw),
            name
        });
    });
    return { equipment, slots };
}

function buildAppearance(merc, hairMap, helmetSet, equipment) {
    const faceKey = FACE_BY_ID[Number(merc.face)] || '';
    const hairId = Number(merc.hair);
    const hairKey = Number.isFinite(hairId) ? hairMap[hairId] || '' : '';
    const headItem = equipment.head || '';
    const helmetSuppressesHair = !!(headItem && helmetSet.has(headItem));
    const appearance = {};
    const notes = [];
    if (faceKey) appearance['脸型'] = faceKey;
    if (hairKey && hairKey !== '光头' && !helmetSuppressesHair) appearance['发型'] = hairKey;
    if (!faceKey) notes.push('face id has no local mapping');
    if (hairId >= 0 && !hairKey) notes.push('hair id has no hairstyle.xml mapping');
    if (hairKey === '光头') notes.push('hair is bald and maps to empty holder');
    if (helmetSuppressesHair) notes.push('head item helmet=true suppresses hair');
    return {
        appearance,
        raw: {
            face: merc.face,
            faceKey,
            hair: merc.hair,
            hairKey,
            headItem,
            helmetSuppressesHair
        },
        notes
    };
}

function skinStatus(manifest, skinKey) {
    if (!skinKey) return { status: 'empty' };
    const skin = manifest.skinKeys && manifest.skinKeys[skinKey];
    if (!skin) return { status: 'missing-skin-key' };
    if (skin.covered === false) return { status: 'uncovered' };
    if (!skin.export) return { status: 'missing-export' };
    return {
        status: 'resolved',
        playback: skin.export.playback || 'static',
        frames: skin.frames ? skin.frames.length : 0,
        timelineFrames: skin.timelineFrames ? skin.timelineFrames.length : 0
    };
}

function resolveParts(manifest, gender, slots, appearance) {
    const keyMap = {};
    const parts = [];
    const missing = [];
    slots.forEach(slotInfo => {
        const item = manifest.items[slotInfo.name];
        if (!item) {
            const entry = Object.assign({ source: 'equipment', status: 'missing-item' }, slotInfo);
            parts.push(entry);
            missing.push(entry);
            return;
        }
        const fields = item.fieldsByGender && item.fieldsByGender[gender];
        if (!fields || !Object.keys(fields).length) {
            const entry = Object.assign({ source: 'equipment', status: 'non-rendered-equipment' }, slotInfo);
            parts.push(entry);
            return;
        }
        Object.keys(fields).forEach(field => {
            const skinKey = fields[field];
            keyMap[field] = skinKey;
            const status = skinStatus(manifest, skinKey);
            const entry = Object.assign({
                source: 'equipment',
                field,
                skinKey
            }, slotInfo, status);
            parts.push(entry);
            if (status.status !== 'resolved') missing.push(entry);
        });
    });
    Object.keys(appearance || {}).forEach(field => {
        const skinKey = appearance[field];
        keyMap[field] = skinKey;
        const status = skinStatus(manifest, skinKey);
        const entry = Object.assign({
            source: 'appearance',
            field,
            skinKey
        }, status);
        parts.push(entry);
        if (status.status !== 'resolved') missing.push(entry);
    });
    return { keyMap, parts, missing };
}

function findBrowser(name) {
    const candidates = (name === 'chrome' ? [
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Google', 'Chrome', 'Application', 'chrome.exe'),
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Google', 'Chrome', 'Application', 'chrome.exe')
    ] : [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : null
    ]).filter(Boolean);
    for (let i = 0; i < candidates.length; i += 1) {
        if (candidates[i] && fs.existsSync(candidates[i])) return candidates[i];
    }
    throw new Error('Cannot find ' + name + ' executable.');
}

function parseViewport(value) {
    const match = String(value || '').match(/^(\d+)x(\d+)$/);
    return {
        width: match ? Number(match[1]) : 1280,
        height: match ? Number(match[2]) : 720
    };
}

function mimeType(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.html') return 'text/html; charset=utf-8';
    if (ext === '.js') return 'application/javascript; charset=utf-8';
    if (ext === '.css') return 'text/css; charset=utf-8';
    if (ext === '.json') return 'application/json; charset=utf-8';
    if (ext === '.png') return 'image/png';
    if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
    if (ext === '.svg') return 'image/svg+xml; charset=utf-8';
    if (ext === '.woff2') return 'font/woff2';
    return 'application/octet-stream';
}

function createStaticServer(rootDir) {
    const server = http.createServer((req, res) => {
        const rawPath = (req.url || '/').split('?')[0] || '/';
        const decoded = decodeURIComponent(rawPath);
        const safeRel = decoded.replace(/^\/+/, '').replace(/\//g, path.sep);
        const filePath = path.resolve(rootDir, safeRel || 'overlay.html');
        if (!filePath.startsWith(rootDir)) {
            res.writeHead(403);
            res.end('forbidden');
            return;
        }
        fs.stat(filePath, (statErr, stat) => {
            if (statErr || !stat.isFile()) {
                res.writeHead(404);
                res.end('not found');
                return;
            }
            res.writeHead(200, { 'content-type': mimeType(filePath) });
            fs.createReadStream(filePath).pipe(res);
        });
    });
    return new Promise((resolve, reject) => {
        server.on('error', reject);
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

function canvasProbeScript() {
    return () => {
        const canvas = document.querySelector('.dressup-canvas');
        if (!canvas || !canvas.width || !canvas.height) return null;
        const ctx = canvas.getContext('2d');
        const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
        let alphaPixels = 0;
        let hash = 2166136261;
        for (let i = 0; i < data.length; i += 4) {
            const alpha = data[i + 3] || 0;
            if (alpha > 8) alphaPixels += 1;
            hash ^= data[i] || 0;
            hash = Math.imul(hash, 16777619) >>> 0;
            hash ^= data[i + 1] || 0;
            hash = Math.imul(hash, 16777619) >>> 0;
            hash ^= data[i + 2] || 0;
            hash = Math.imul(hash, 16777619) >>> 0;
            hash ^= alpha;
            hash = Math.imul(hash, 16777619) >>> 0;
        }
        return {
            width: canvas.width,
            height: canvas.height,
            alphaPixels,
            hash
        };
    };
}

function safeFileName(value) {
    return String(value || '').replace(/[\\/:*?"<>|\s]+/g, '_').replace(/^_+|_+$/g, '') || 'sample';
}

async function renderSample(page, port, args, sample) {
    const initData = {
        mode: 'merc-probe',
        source: 'merc-dressup-probe',
        debug: false,
        gender: sample.merc.gender,
        equipment: sample.equipment,
        appearance: sample.appearance,
        fitFields: Object.prototype.hasOwnProperty.call(sample.target, 'fitFields') ? sample.target.fitFields : BODY_FIT_FIELDS,
        zoom: typeof sample.target.zoom === 'number' ? sample.target.zoom : 0.96,
        rig: sample.target.rig || '',
        stateLabel: sample.target.stateLabel || '',
        debugPlaceholders: false
    };
    const query = new URLSearchParams();
    query.set('init', JSON.stringify(initData));
    const url = `http://127.0.0.1:${port}/modules/dressup/dev/panel-harness.html?${query.toString()}`;
    await page.goto(url, { waitUntil: 'load' });
    await page.waitForSelector('.dressup-panel', { timeout: 20000 });
    await page.waitForFunction(() => {
        const status = document.querySelector('.dressup-status');
        return status && status.textContent && status.textContent.indexOf('"holders"') >= 0;
    }, null, { timeout: 20000 });
    await page.waitForTimeout(900);
    const firstProbe = await page.evaluate(canvasProbeScript());
    await page.waitForTimeout(650);
    const secondProbe = await page.evaluate(canvasProbeScript());
    const statusText = await page.locator('.dressup-status').innerText();
    const headerText = await page.locator('.dressup-header-status').innerText();
    const shotPath = path.resolve(projectRoot, args.outDir, safeFileName(sample.target.label + '-' + sample.merc.name) + '.png');
    fs.mkdirSync(path.dirname(shotPath), { recursive: true });
    await page.screenshot({ path: shotPath, fullPage: true });
    return {
        url,
        screenshot: path.relative(projectRoot, shotPath).replace(/\\/g, '/'),
        headerText,
        status: JSON.parse(statusText),
        firstProbe,
        secondProbe,
        animationChanged: !!(firstProbe && secondProbe && firstProbe.hash !== secondProbe.hash),
        blank: !firstProbe || firstProbe.alphaPixels < 500
    };
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;
    if (!fs.existsSync(playwrightModule)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }

    const manifest = readJson(path.join('launcher', 'web', 'assets', 'dressup', 'manifest.json'));
    const mercenaries = readJson(path.join('data', 'merc', 'mercenaries.json'));
    const hairMap = parseHairMap();
    const helmetSet = parseHelmetSet();
    const samples = chooseSamples(mercenaries).map(chosen => {
        const equipInfo = buildEquipment(chosen.merc);
        const appearanceInfo = buildAppearance(chosen.merc, hairMap, helmetSet, equipInfo.equipment);
        const resolved = resolveParts(manifest, chosen.merc.gender, equipInfo.slots, appearanceInfo.appearance);
        return Object.assign({}, chosen, equipInfo, appearanceInfo, resolved);
    });

    const { chromium } = require(playwrightModule);
    const executablePath = findBrowser(args.browser);
    const viewport = parseViewport(args.viewport);
    const server = await createStaticServer(webRoot);
    const port = server.address().port;
    const failedRequests = [];
    const pageErrors = [];
    const consoleLogs = [];
    let browser = null;

    try {
        browser = await chromium.launch({
            executablePath,
            headless: !args.headed
        });
        const page = await browser.newPage({ viewport });
        page.on('requestfailed', request => {
            const failure = request.failure();
            if (/^https?:\/\/cfn-fonts\.local\//i.test(request.url())) return;
            failedRequests.push(request.url() + ' :: ' + ((failure && failure.errorText) || 'failed'));
        });
        page.on('pageerror', error => pageErrors.push(error && error.message ? error.message : String(error)));
        page.on('console', msg => consoleLogs.push(msg.type() + ': ' + msg.text()));
        await page.route('https://cfn-fonts.local/**', route => route.fulfill({
            status: 204,
            headers: { 'access-control-allow-origin': '*' },
            body: ''
        }));

        for (const sample of samples) {
            try {
                sample.render = await renderSample(page, port, args, sample);
            } catch (error) {
                sample.render = {
                    error: String(error && error.stack || error)
                };
            }
        }
    } finally {
        if (browser) await browser.close();
        await new Promise(resolve => server.close(resolve));
    }

    const resolvedPartCount = samples.reduce((count, sample) => (
        count + sample.parts.filter(part => part.status === 'resolved').length
    ), 0);
    const totalPartCount = samples.reduce((count, sample) => (
        count + sample.parts.filter(part => part.status !== 'non-rendered-equipment').length
    ), 0);
    const report = {
        generatedAt: new Date().toISOString(),
        source: {
            mercenaries: 'data/merc/mercenaries.json',
            manifest: 'launcher/web/assets/dressup/manifest.json',
            hairstyle: 'data/items/hairstyle.xml'
        },
        sampleTargets: TARGETS,
        coverage: {
            samples: samples.length,
            resolvedPartCount,
            totalPartCount,
            resolvedPartRatio: totalPartCount ? Number((resolvedPartCount / totalPartCount).toFixed(4)) : 0,
            blankScreenshots: samples.filter(sample => sample.render && sample.render.blank).length,
            renderErrors: samples.filter(sample => sample.render && sample.render.error).length,
            nonRenderedEquipment: samples.reduce((count, sample) => (
                count + sample.parts.filter(part => part.status === 'non-rendered-equipment').length
            ), 0),
            missingByStatus: samples.reduce((acc, sample) => {
                sample.missing.forEach(part => {
                    acc[part.status] = (acc[part.status] || 0) + 1;
                });
                return acc;
            }, {})
        },
        notes: [
            'AS2 MercLibrary maps merc[4] from raw.face and merc[5] from raw.hair before unit spawn.',
            'MercPanelService serializes face/hair for runtime panels; this probe cross-checks the same appearance mapping from mercenaries.json.',
            'The reference midnight-neon sample uses the battle rig 空手站立 state from flashswf/arts/things0/LIBRARY/主角-男.xml.',
            'Non-reference probe screenshots fit the body/face/hair/mask holders but still draw weapons, preventing weapon effects from shrinking the character.',
            'Light/heavy buckets are probe-only: armor slots <=3 is light, >=5 is heavy.'
        ],
        browser: {
            requested: args.browser,
            executablePath,
            viewport: args.viewport
        },
        failedRequests,
        pageErrors,
        consoleLogs: consoleLogs.slice(-80),
        samples: samples.map(sample => ({
            target: sample.target,
            classification: sample.classification,
            merc: {
                id: sample.merc.id,
                name: sample.merc.name,
                level: sample.merc.level,
                gender: sample.merc.gender,
                height: sample.merc.height,
                face: sample.merc.face,
                hair: sample.merc.hair
            },
            equipmentSlots: sample.slots,
            appearance: sample.raw,
            appearanceNotes: sample.notes,
            keyMap: sample.keyMap,
            resolvedParts: sample.parts.filter(part => part.status === 'resolved'),
            nonRenderedParts: sample.parts.filter(part => part.status === 'non-rendered-equipment'),
            missingParts: sample.missing,
            render: sample.render
        }))
    };

    const reportPath = path.resolve(projectRoot, args.report);
    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), 'utf8');
    process.stdout.write(JSON.stringify({
        report: path.relative(projectRoot, reportPath).replace(/\\/g, '/'),
        coverage: report.coverage,
        screenshots: report.samples.map(sample => sample.render && sample.render.screenshot).filter(Boolean)
    }, null, 2) + '\n');

    if (report.coverage.renderErrors || report.coverage.blankScreenshots || pageErrors.length || failedRequests.length) {
        process.exit(1);
    }
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
