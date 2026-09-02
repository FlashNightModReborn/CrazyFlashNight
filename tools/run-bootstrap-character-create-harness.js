#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const webRoot = path.join(projectRoot, 'launcher', 'web');
const hairstylePath = path.join(projectRoot, 'data', 'items', 'hairstyle.xml');
const itemListPath = path.join(projectRoot, 'data', 'items', 'list.xml');
const iconManifestPath = path.join(webRoot, 'icons', 'manifest.json');
const characterCreationServicePath = path.join(projectRoot, 'scripts', '类定义', 'org', 'flashNight',
    'neur', 'Server', 'CharacterCreationService.as');
const playwrightModule = path.join(projectRoot, 'launcher', 'perf', 'node_modules', 'playwright');

function expect(value, message) {
    if (!value) throw new Error(message);
}

function decodeXml(value) {
    return String(value)
        .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
        .replace(/&#(\d+);/g, (_, decimal) => String.fromCodePoint(Number(decimal)))
        .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}

function tagValue(block, tag) {
    const match = new RegExp('<' + tag + '(?:\\s[^>]*)?>([\\s\\S]*?)</' + tag + '>', 'i').exec(block);
    return match ? decodeXml(match[1].trim()) : '';
}

function escapeHtml(value) {
    return String(value == null ? '' : value)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function buildFixtureIntroHtml(itemBlock, item) {
    const dataMatch = /<data(?:\s[^>]*)?>([\s\S]*?)<\/data>/i.exec(itemBlock);
    const data = dataMatch ? dataMatch[1] : '';
    const facts = [
        ['类别', item.type + (item.use ? ' · ' + item.use : '')],
        ['等级', tagValue(data, 'level') || '1'],
        ['重量', tagValue(data, 'weight')],
        ['防御', tagValue(data, 'defence')],
        ['伤害', tagValue(data, 'damage')],
        ['生命', tagValue(data, 'hp')],
        ['魔法', tagValue(data, 'mp')],
        ['拳术', tagValue(data, 'punch')],
        ['刀术', tagValue(data, 'knifepower')],
        ['枪械', tagValue(data, 'gunpower')]
    ].filter(fact => fact[1] !== '');
    return '<TEXTFORMAT LEADING="2"><P ALIGN="LEFT"><FONT COLOR="#f3d59a" SIZE="18"><B>'
        + escapeHtml(item.displayName) + '</B></FONT></P>'
        + facts.map(fact => '<P ALIGN="LEFT"><FONT COLOR="#d8d3c5" SIZE="14">'
            + escapeHtml(fact[0]) + '：' + escapeHtml(fact[1]) + '</FONT></P>').join('')
        + '</TEXTFORMAT>';
}

function readAppearanceItemProjections(identifiers) {
    const requested = new Set(identifiers);
    const byName = new Map();
    const listXml = fs.readFileSync(itemListPath, 'utf8').replace(/^\uFEFF/, '');
    const files = Array.from(listXml.matchAll(/<items>\s*([^<]+?)\s*<\/items>/g), match =>
        decodeXml(match[1].trim()));
    expect(files.length > 0, 'data/items/list.xml contains no item catalogs');
    for (const relativePath of files) {
        const sourcePath = path.join(path.dirname(itemListPath), relativePath);
        const xml = fs.readFileSync(sourcePath, 'utf8').replace(/^\uFEFF/, '');
        for (const match of xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)) {
            const block = match[1];
            const identifier = tagValue(block, 'name');
            if (!requested.has(identifier) || byName.has(identifier)) continue;
            const displayName = tagValue(block, 'displayname') || identifier;
            const iconName = tagValue(block, 'icon') || identifier;
            const type = tagValue(block, 'type');
            const use = tagValue(block, 'use');
            const description = tagValue(block, 'description');
            expect(displayName && iconName && type && description,
                'appearance item lacks display/icon/type/description in ' + relativePath + ': ' + identifier);
            const item = { identifier, displayName, iconName, type, use };
            byName.set(identifier, {
                identifier,
                name: displayName,
                iconName,
                itemType: type === '消耗品' && use ? use : type,
                introHTML: buildFixtureIntroHtml(block, item),
                descHTML: description
            });
        }
    }
    const iconManifest = JSON.parse(fs.readFileSync(iconManifestPath, 'utf8').replace(/^\uFEFF/, ''));
    for (const identifier of identifiers) {
        const row = byName.get(identifier);
        expect(row, 'appearance identifier is absent from declared item XML: ' + identifier);
        expect(iconManifest[row.iconName], 'appearance icon is absent from Web manifest: '
            + identifier + ' -> ' + row.iconName);
    }
    const alias = byName.get('咖啡色多包短裤');
    expect(alias && alias.iconName === '咖啡色多包裤',
        'real XML icon alias drifted: 咖啡色多包短裤 must resolve through 咖啡色多包裤');
    return byName;
}

function readHairCatalog() {
    const xml = fs.readFileSync(hairstylePath, 'utf8');
    const rows = [];
    for (const match of xml.matchAll(/<Hair\b[^>]*>([\s\S]*?)<\/Hair>/g)) {
        const identifier = /<Identifier>([\s\S]*?)<\/Identifier>/.exec(match[1]);
        const name = /<Name>([\s\S]*?)<\/Name>/.exec(match[1]);
        if (!identifier || !name) throw new Error('Malformed Hair row in ' + hairstylePath);
        rows.push({ identifier: decodeXml(identifier[1].trim()), name: decodeXml(name[1].trim()) });
    }
    expect(rows.length === 77, 'expected 77 hairstyle.xml rows, got ' + rows.length);
    expect(rows[20].identifier === '发型-男式-平头' && rows[32].identifier === '发型-男式-平头',
        'expected the maintained duplicate at source indices 20 and 32');
    return rows;
}

function functionBody(source, name) {
    const match = new RegExp('private static function ' + name
        + '\\([^)]*\\)(?::[A-Za-z]+)?\\s*\\{([\\s\\S]*?)\\r?\\n    \\}', 'm').exec(source);
    if (!match) throw new Error('Cannot parse CharacterCreationService.' + name);
    return match[1];
}

function quotedValues(source) {
    return Array.from(source.matchAll(/"([^"]*)"/g), match => match[1]);
}

function parseGenderDefaults(source) {
    const body = functionBody(source, 'buildDefaults');
    const match = /male:\{([\s\S]*?)\}\s*,\s*female:\{([\s\S]*?)\}\s*\};/.exec(body);
    if (!match) throw new Error('Cannot parse CharacterCreationService buildDefaults genders');
    function parse(block) {
        const result = {};
        for (const key of [
            'height', 'faceIdentifier', 'hairIdentifier', 'upperIdentifier',
            'lowerIdentifier', 'footwearIdentifier', 'difficulty'
        ]) {
            const value = new RegExp(key + ':\\s*(?:"([^"]*)"|(\\d+))').exec(block);
            if (!value) throw new Error('Cannot parse buildDefaults.' + key);
            result[key] = value[1] === undefined ? Number(value[2]) : value[1];
        }
        return result;
    }
    return { male: parse(match[1]), female: parse(match[2]) };
}

function parseGenderIdentifiers(source, functionName) {
    const body = functionBody(source, functionName);
    const match = /gender == "male"\s*\?\s*\[([^\]]*)\]\s*:\s*\[([^\]]*)\]/.exec(body);
    if (!match) throw new Error('Cannot parse CharacterCreationService.' + functionName + ' catalogs');
    return { male: quotedValues(match[1]), female: quotedValues(match[2]) };
}

function parseFaces(source) {
    const body = functionBody(source, 'buildAppearanceCatalog');
    const match = /faces:\{[\s\S]*?male:\{identifier:"([^"]+)",\s*name:"([^"]+)"\},[\s\S]*?female:\{identifier:"([^"]+)",\s*name:"([^"]+)"\}/.exec(body);
    if (!match) throw new Error('Cannot parse CharacterCreationService face catalog');
    return {
        male: { identifier: match[1], name: match[2] },
        female: { identifier: match[3], name: match[4] }
    };
}

function parseDifficulties(source) {
    const body = functionBody(source, 'buildDifficulties');
    const result = [];
    const rowPattern = /\{\s*identifier:"([^"]+)",\s*name:"([^"]+)",\s*description:"([^"]*)",\s*recommended:(true|false)\s*\}/g;
    for (const match of body.matchAll(rowPattern)) {
        result.push({
            identifier: match[1], name: match[2], description: match[3], recommended: match[4] === 'true'
        });
    }
    if (result.length !== 3) throw new Error('Expected exactly three CharacterCreationService difficulties');
    return result;
}

function snapshotTemplate(hairCatalog) {
    const authority = fs.readFileSync(characterCreationServicePath, 'utf8');
    const defaults = parseGenderDefaults(authority);
    const faces = parseFaces(authority);
    const upper = parseGenderIdentifiers(authority, 'upperIdentifiers');
    const lower = parseGenderIdentifiers(authority, 'lowerIdentifiers');
    const footwear = parseGenderIdentifiers(authority, 'footwearIdentifiers');
    const difficulties = parseDifficulties(authority);
    const allAppearanceIdentifiers = Array.from(new Set([
        ...upper.male, ...upper.female, ...lower.male, ...lower.female,
        ...footwear.male, ...footwear.female
    ]));
    const appearanceItems = readAppearanceItemProjections(allAppearanceIdentifiers);
    const richCatalog = identifiers => identifiers.map(identifier => appearanceItems.get(identifier));
    for (const gender of ['male', 'female']) {
        expect(defaults[gender].faceIdentifier === faces[gender].identifier,
            'CharacterCreationService default face drifted from its face catalog');
        expect(hairCatalog.some(row => row.identifier === defaults[gender].hairIdentifier),
            'CharacterCreationService default hair is absent from hairstyle.xml: ' + defaults[gender].hairIdentifier);
        expect(upper[gender].includes(defaults[gender].upperIdentifier),
            'CharacterCreationService default upper is absent from its catalog');
        expect(lower[gender].includes(defaults[gender].lowerIdentifier),
            'CharacterCreationService default lower is absent from its catalog');
        expect(footwear[gender].includes(defaults[gender].footwearIdentifier),
            'CharacterCreationService default footwear is absent from its catalog');
        expect(difficulties.some(row => row.identifier === defaults[gender].difficulty),
            'CharacterCreationService default difficulty is absent from its catalog');
    }
    return {
        cmd: 'character_create_snapshot',
        openRequestId: 'filled-by-harness',
        attemptId: 'filled-by-harness',
        slotKey: 'filled-by-harness',
        constraints: {
            displayNameMin: 1, displayNameMax: 32,
            characterNameMin: 1, characterNameMax: 15,
            heightMin: 150, heightMax: 200
        },
        defaults,
        hairCatalog,
        appearanceCatalog: {
            faces,
            upper: {
                male: richCatalog(upper.male),
                female: richCatalog(upper.female)
            },
            lower: {
                male: richCatalog(lower.male),
                female: richCatalog(lower.female)
            },
            footwear: {
                male: richCatalog(footwear.male),
                female: richCatalog(footwear.female)
            }
        },
        difficulties
    };
}

function verifyGraphemeFallback(template) {
    const source = fs.readFileSync(path.join(webRoot, 'modules', 'bootstrap-character-create-runtime.js'), 'utf8');
    const sandbox = { module: { exports: {} }, Intl: {}, console };
    sandbox.globalThis = sandbox;
    vm.runInNewContext(source, sandbox, { filename: 'bootstrap-character-create-runtime.js' });
    const runtime = sandbox.module.exports;
    const normalized = runtime.normalizeSnapshot(template);
    expect(normalized, 'fallback runtime could not normalize harness snapshot');
    const model = runtime.initialDraft(normalized);
    model.draft.characterName = '角';
    model.displayNameCustomized = true;
    model.displayName = 'é'.repeat(31) + '👩‍🚀';
    expect(runtime.validateSubmission(normalized, model).valid,
        'fallback did not count combining/ZWJ graphemes as 32 visible elements');
    model.displayName += '界';
    expect(!runtime.validateSubmission(normalized, model).valid,
        'fallback accepted 33 visible text elements');
}

function findEdge() {
    const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : null
    ].filter(Boolean);
    const executable = candidates.find(candidate => fs.existsSync(candidate));
    if (!executable) throw new Error('Microsoft Edge executable was not found.');
    return executable;
}

function contentType(filePath) {
    return ({
        '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
        '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
        '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml',
        '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp',
        '.woff2': 'font/woff2', '.mp4': 'video/mp4', '.bin': 'application/octet-stream'
    })[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
}

function startServer() {
    const server = http.createServer((request, response) => {
        try {
            const requestUrl = new URL(request.url, 'http://127.0.0.1');
            const relativePath = decodeURIComponent(requestUrl.pathname).replace(/^\/+/, '');
            const filePath = path.resolve(webRoot, relativePath || 'bootstrap.html');
            if (filePath !== webRoot && !filePath.startsWith(webRoot + path.sep)) {
                response.writeHead(403).end('forbidden');
                return;
            }
            if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
                response.writeHead(404).end('not found');
                return;
            }
            response.writeHead(200, { 'content-type': contentType(filePath), 'cache-control': 'no-store' });
            response.end(fs.readFileSync(filePath));
        } catch (error) {
            response.writeHead(500).end(String(error));
        }
    });
    return new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function closeServer(server) {
    if (server) await new Promise(resolve => server.close(resolve));
}

async function setupPage(browser, url, viewport, reducedMotion, template, evidence, options = {}) {
    const page = await browser.newPage({ viewport });
    await page.emulateMedia({ reducedMotion: reducedMotion ? 'reduce' : 'no-preference' });
    page.on('pageerror', error => evidence.pageErrors.push(error.message || String(error)));
    page.on('requestfailed', request => evidence.failedRequests.push(request.url() + ' :: '
        + ((request.failure() && request.failure().errorText) || 'failed')));
    await page.route('https://cfn-fonts.local/**', route => route.fulfill({
        status: 204, headers: { 'access-control-allow-origin': '*' }, body: ''
    }));
    if (options.manifestFailure !== false) {
        await page.route('**/assets/dressup/manifest.json', route => route.fulfill({
            status: 503, contentType: 'application/json', body: '{}'
        }));
    }
    await page.addInitScript(init => {
        const snapshot = init.snapshot;
        const deferSnapshot = init.deferSnapshot === true;
        const snapshotDelayMs = Number(init.snapshotDelayMs) || 0;
        const uiFontScale = Number(init.uiFontScale) || 1.35;
        const listeners = [];
        const events = [];
        let serial = 0;
        let activeSnapshot = null;
        const snapshots = [];
        let failNextCommand = null;
        const clone = value => JSON.parse(JSON.stringify(value));
        const emit = payload => {
            const message = clone(payload);
            if (message.cmd === 'character_create_state'
                    && !Object.prototype.hasOwnProperty.call(message, 'openRequestId')
                    && activeSnapshot) {
                message.openRequestId = activeSnapshot.openRequestId;
            }
            events.push({ direction: 'in', message });
            listeners.slice().forEach(listener => listener({ data: JSON.stringify(message) }));
        };
        const slots = [
            {
                slot: 'crazyflasher7_saves', displayName: '远征档', characterName: '阿七',
                mainProgress: '第 3 章', size: 1024, lastModified: '2026-08-29T08:01:02',
                corrupt: false, tombstoned: false, inconsistent: false
            },
            {
                slot: 'crazyflasher7_saves1', displayName: '远征档', characterName: '阿八',
                mainProgress: '第 4 章', size: 2048, lastModified: '2026-08-28T07:01:02',
                corrupt: false, tombstoned: false, inconsistent: false
            },
            {
                slot: 'legacy-rebuild-key-123456', displayName: '旧角色', characterName: '旧佣兵',
                mainProgress: '副本不一致', size: 4096, lastModified: '2026-08-20T07:01:02',
                corrupt: false, tombstoned: false, inconsistent: true
            }
        ];
        const webview = {
            addEventListener(type, listener) { if (type === 'message') listeners.push(listener); },
            postMessage(raw) {
                const message = typeof raw === 'string' ? JSON.parse(raw) : clone(raw);
                if (failNextCommand === message.cmd) {
                    failNextCommand = null;
                    throw new Error('harness postMessage failure: ' + message.cmd);
                }
                events.push({ direction: 'out', message: clone(message) });
                if (message.cmd === 'list') {
                    setTimeout(() => {
                        emit({
                            cmd: 'list_resp', slots, lastPlayedSlot: slots[0].slot,
                            introEnabled: false, sfxEnabled: false, ambientEnabled: false, uiFontScale
                        });
                        emit({ cmd: 'state', state: 'Ready', msg: 'character-create-harness' });
                        emit({ cmd: 'flash_ready' });
                    }, 0);
                } else if (message.cmd === 'fontpack_status') {
                    setTimeout(() => emit({ cmd: 'fontpack_status_resp', ok: true, groups: [] }), 0);
                } else if (message.cmd === 'character_create_open') {
                    serial += 1;
                    activeSnapshot = clone(snapshot);
                    activeSnapshot.openRequestId = message.openRequestId;
                    activeSnapshot.attemptId = 'attempt-' + String(serial).padStart(3, '0');
                    activeSnapshot.slotKey = message.mode === 'rebuild'
                        ? message.slotKey : 'new-slot-' + String(serial).padStart(3, '0');
                    snapshots.push(clone(activeSnapshot));
                    if (!deferSnapshot) setTimeout(() => emit(activeSnapshot), snapshotDelayMs);
                }
            }
        };
        window.chrome = window.chrome || {};
        window.chrome.webview = webview;
        window.__ccHarness = {
            events,
            emit,
            failNext: cmd => { failNextCommand = cmd; },
            activeSnapshot: () => clone(activeSnapshot),
            snapshots: () => clone(snapshots),
            deliverSnapshot: index => {
                const selected = Number.isInteger(index) ? snapshots[index] : activeSnapshot;
                if (selected) emit(selected);
            },
            outbound: cmd => events.filter(event => event.direction === 'out'
                && (!cmd || event.message.cmd === cmd)).map(event => clone(event.message))
        };
    }, {
        snapshot:template,
        deferSnapshot:options.deferSnapshot === true,
        snapshotDelayMs:Number(options.snapshotDelayMs) || 0,
        uiFontScale:Number(options.uiFontScale) || 1.35
    });
    await page.goto(url, { waitUntil: 'load' });
    if (options.resetAppearanceDensity !== false) {
        await page.evaluate(() => localStorage.removeItem('cf7.itemgrid.mode.character-create-appearance'));
    }
    await page.waitForFunction(() => document.querySelectorAll('#cards .card').length === 4, null, { timeout: 10000 });
    return page;
}

async function openCharacterCreate(page, mode = 'new', slotKey = null) {
    const previous = await page.evaluate(() => {
        const state = window.BootstrapCharacterCreate.debugState();
        return state.attemptId || '';
    });
    await page.evaluate(({ mode, slotKey }) => window.BootstrapApp.openCharacterCreate(mode, slotKey), { mode, slotKey });
    await page.waitForFunction(prior => {
        const state = window.BootstrapCharacterCreate.debugState();
        return state.phase === 'editing' && state.attemptId && state.attemptId !== prior;
    }, previous, { timeout: 10000 });
    return page.evaluate(() => window.BootstrapCharacterCreate.debugState());
}

async function fillDefaultDraft(page, displayName, characterName) {
    await page.locator('#cc-display-name').fill(displayName);
    await page.locator('#cc-character-name').fill(characterName);
    await page.locator('#cc-next').click();
    await page.locator('#cc-next').click();
    expect(await page.locator('[data-cc-panel="2"]:not([hidden])').count() === 1,
        'could not reach the final character-create step');
}

async function installPreparationDeadlineProbe(page, acceleratedDelay, leak) {
    await page.evaluate(({ acceleratedDelay, leak }) => {
        const nativeSetTimeout = window.setTimeout.bind(window);
        const nativeClearTimeout = window.clearTimeout.bind(window);
        const deadlineIds = new Set();
        const probe = {
            exactDelay:12000,
            acceleratedDelay,
            scheduled:0,
            fired:0,
            cleared:0,
            leak
        };
        window.setTimeout = function(callback, delay) {
            const args = Array.prototype.slice.call(arguments, 2);
            if (Number(delay) !== probe.exactDelay) {
                return nativeSetTimeout.apply(window, [callback, delay].concat(args));
            }
            probe.scheduled += 1;
            let timerId = null;
            timerId = nativeSetTimeout(function() {
                deadlineIds.delete(timerId);
                probe.fired += 1;
                if (typeof callback === 'function') callback.apply(window, args);
                else window.eval(String(callback));
            }, acceleratedDelay);
            deadlineIds.add(timerId);
            return timerId;
        };
        window.clearTimeout = function(timerId) {
            if (deadlineIds.has(timerId)) {
                probe.cleared += 1;
                if (leak) return;
                deadlineIds.delete(timerId);
            }
            nativeClearTimeout(timerId);
        };
        window.__ccDeadlineProbe = probe;
    }, { acceleratedDelay:Number(acceleratedDelay), leak:leak === true });
}

async function installManualAnimationFrames(page) {
    await page.evaluate(() => {
        const original = window.requestAnimationFrame.bind(window);
        const queue = [];
        let serial = 0;
        window.requestAnimationFrame = callback => {
            const name = callback && callback.name || '';
            const callbackSource = String(callback || '');
            const source = callbackSource.slice(0, 180);
            const ambient = name === 'tickAnimatedIcons'
                || (name === 'tick' && source.includes('FRAME_INTERVAL_MS'));
            // PanelScale and the paper-doll ResizeObserver now legitimately queue
            // their own layout frames during preparation. Keep the two-frame
            // presentation chain separately observable so those frames cannot
            // make a premature-reveal test pass or fail by accident.
            const presentation = callbackSource.includes("phase !== 'preparing'")
                || callbackSource.includes('requestFrame(function()');
            queue.push({
                id:++serial,
                callback,
                ambient,
                presentation,
                name,
                source
            });
            return serial;
        };
        window.__ccManualFrames = {
            // Icons keeps a background RAF alive while animated inventory icons
            // are mounted. It is unrelated to the character-create presentation
            // gate, so expose and advance only non-ambient callbacks here.
            pending:() => queue.filter(entry => !entry.ambient).length,
            pendingPresentation:() => queue.filter(entry => !entry.ambient && entry.presentation).length,
            describe:() => queue.filter(entry => !entry.ambient).slice(0, 4)
                .map(entry => ({ id:entry.id, presentation:entry.presentation,
                    name:entry.name, source:entry.source })),
            flushOne:() => {
                const index = queue.findIndex(entry => !entry.ambient);
                const entry = index >= 0 ? queue.splice(index, 1)[0] : null;
                if (!entry) return false;
                entry.callback(performance.now());
                return true;
            },
            flushPresentation:() => {
                const index = queue.findIndex(entry => !entry.ambient && entry.presentation);
                const entry = index >= 0 ? queue.splice(index, 1)[0] : null;
                if (!entry) return false;
                entry.callback(performance.now());
                return true;
            },
            restore:() => { window.requestAnimationFrame = original; }
        };
    });
}

async function holdRendererCallbacksWithZeroProbe(page) {
    await page.evaluate(() => {
        const originalCreate = window.DressupDollRenderer.create;
        window.DressupDollRenderer.create = function(canvas, options) {
            const pending = [];
            const deliver = options.onRender;
            let holding = true;
            const wrapped = Object.assign({}, options, {
                onRender:meta => {
                    if (holding) pending.push(meta);
                    else deliver(meta);
                }
            });
            const instance = originalCreate.call(window.DressupDollRenderer, canvas, wrapped);
            const originalRender = instance.render.bind(instance);
            let lastState = null;
            instance.render = state => {
                lastState = state;
                const meta = originalRender(state) || {};
                // The real renderer still paints and buffers callbacks, but its
                // synchronous return must not let handleSnapshot bypass this probe.
                return Object.assign({}, meta, {
                    holders:0, totalHolders:0, missing:0,
                    pendingImages:Math.max(1, Number(meta.pendingImages) || 0),
                    failedImages:0, drawnImages:0
                });
            };
            const zeroDraw = {
                gender:'男', holders:0, totalHolders:0, missing:0,
                pendingImages:0, failedImages:0, drawnImages:0
            };
            const isStrict = meta => meta && meta.holders > 0
                && meta.drawnImages > 0 && meta.pendingImages === 0
                && meta.failedImages === 0 && meta.missing === 0;
            window.__ccRenderProbe = {
                pending,
                releaseZero:() => {
                    deliver(zeroDraw);
                    return true;
                },
                releaseFailure:() => {
                    deliver({
                        gender:'男', holders:0, totalHolders:0, missing:0,
                        pendingImages:0, failedImages:1, drawnImages:0
                    });
                    return true;
                },
                strictReady:() => pending.some(isStrict),
                releaseSubthresholdStrict:() => {
                    const strict = pending.slice().reverse().find(isStrict) || {
                        gender:'男', holders:1, totalHolders:1, missing:0,
                        pendingImages:0, failedImages:0, drawnImages:1
                    };
                    pending.length = 0;
                    const context = canvas.getContext('2d');
                    context.save();
                    context.setTransform(1, 0, 0, 1, 0, 0);
                    context.clearRect(0, 0, canvas.width, canvas.height);
                    context.fillStyle = '#fff';
                    context.fillRect(0, 0, 20, 25);
                    context.restore();
                    deliver(strict);
                    return true;
                },
                releaseStrict:() => {
                    const immediate = lastState ? originalRender(lastState) : null;
                    const strict = isStrict(immediate) ? immediate
                        : pending.slice().reverse().find(isStrict);
                    if (!strict) return false;
                    pending.length = 0;
                    deliver(strict);
                    return true;
                }
            };
            return instance;
        };
    });
}

async function flushAnimationFrame(page) {
    return page.evaluate(() => window.__ccManualFrames.flushOne());
}

async function flushPresentationFrame(page) {
    return page.evaluate(() => window.__ccManualFrames.flushPresentation());
}

async function drainAnimationFrames(page, limit = 64) {
    return page.evaluate(maximum => {
        let flushed = 0;
        while (window.__ccManualFrames.pending() > 0 && flushed < maximum) {
            window.__ccManualFrames.flushOne();
            flushed += 1;
        }
        return {
            flushed,
            pending:window.__ccManualFrames.pending(),
            callbacks:window.__ccManualFrames.describe()
        };
    }, limit);
}

async function preparationPresentation(page) {
    return page.evaluate(() => {
        const view = document.getElementById('view-character-create');
        const overlay = document.getElementById('intro-ov');
        const rect = overlay.getBoundingClientRect();
        const name = document.getElementById('cc-character-name');
        return {
            state:window.BootstrapCharacterCreate.debugState(),
            bodyPreparing:document.body.classList.contains('character-create-preparing'),
            overlayOn:overlay.classList.contains('on'),
            overlayLoading:overlay.classList.contains('loading'),
            overlayVisibility:getComputedStyle(overlay).visibility,
            overlayBeforeContent:getComputedStyle(overlay, '::before').content,
            overlayAfterContent:getComputedStyle(overlay, '::after').content,
            overlayRect:{left:rect.left, top:rect.top, right:rect.right, bottom:rect.bottom},
            backgroundMotion:(document.getElementById('bg-gl') || {}).dataset
                ? document.getElementById('bg-gl').dataset.characterCreateMotion || '' : '',
            viewInert:view.hasAttribute('inert'),
            viewBusy:view.getAttribute('aria-busy'),
            viewVisibility:getComputedStyle(view).visibility,
            nameDisabled:name.disabled,
            nameValue:name.value,
            activeId:document.activeElement && document.activeElement.id,
            activeInside:view.contains(document.activeElement),
            loadingText:overlay.querySelector('.loading-text').textContent,
            width:innerWidth,
            height:innerHeight,
            pendingFrames:window.__ccManualFrames ? window.__ccManualFrames.pending() : null,
            pendingPresentationFrames:window.__ccManualFrames
                ? window.__ccManualFrames.pendingPresentation() : null
        };
    });
}

async function run() {
    expect(fs.existsSync(playwrightModule), 'Playwright is missing; run npm --prefix launcher/perf ci --ignore-scripts');
    const hairCatalog = readHairCatalog();
    const template = snapshotTemplate(hairCatalog);
    verifyGraphemeFallback(template);
    const { chromium } = require(playwrightModule);
    const executablePath = findEdge();
    const server = await startServer();
    const url = 'http://127.0.0.1:' + server.address().port + '/bootstrap.html';
    const evidence = { browser: 'edge', executablePath, checks: [], pageErrors: [], failedRequests: [] };
    let browser;

    async function check(id, action) {
        try {
            const detail = await action();
            evidence.checks.push({ id, passed: true, detail: detail || '' });
        } catch (error) {
            evidence.checks.push({ id, passed: false, detail: error.message || String(error) });
        }
    }

    try {
        browser = await chromium.launch({ executablePath, headless: true });
        const viewports = [
            { width: 1920, height: 1080, reduced: false, uiFontScale: 1.35 },
            { width: 1600, height: 900, reduced: false, uiFontScale: 1.35 },
            { width: 1366, height: 768, reduced: false, uiFontScale: 1.75 },
            { width: 1366, height: 768, reduced: true, uiFontScale: 1.9 },
            { width: 1024, height: 576, reduced: true, uiFontScale: 1.35 }
        ];
        for (const viewport of viewports) {
            await check('layout-' + viewport.width + 'x' + viewport.height
                + '-fs' + String(viewport.uiFontScale).replace('.', '')
                + (viewport.reduced ? '-reduced' : ''), async () => {
                const page = await setupPage(browser, url, viewport, viewport.reduced, template, evidence,
                    { uiFontScale:viewport.uiFontScale });
                try {
                    await openCharacterCreate(page);
                    await page.waitForFunction(() => {
                        const shell = document.querySelector('.cc-scale-shell.panel-scale-shell');
                        const view = document.getElementById('view-character-create');
                        return shell && parseFloat(getComputedStyle(shell).getPropertyValue('--panel-scale')) > 0
                            && !view.classList.contains('view-enter')
                            && document.getElementById('bg-gl').dataset.characterCreateMotion === 'ambient';
                    });
                    const scaleLayout = await page.evaluate(() => {
                        const shell = document.querySelector('.cc-scale-shell.panel-scale-shell');
                        const parent = shell && shell.parentElement;
                        const rect = shell.getBoundingClientRect();
                        const parentRect = parent.getBoundingClientRect();
                        const style = getComputedStyle(shell);
                        const matrix = new DOMMatrixReadOnly(style.transform);
                        const expectedScale = Math.min(parent.clientWidth / 1024, parent.clientHeight / 576);
                        return {
                            logicalWidth:shell.offsetWidth,
                            logicalHeight:shell.offsetHeight,
                            scale:parseFloat(style.getPropertyValue('--panel-scale')),
                            expectedScale:expectedScale,
                            matrix:{a:matrix.a, b:matrix.b, c:matrix.c, d:matrix.d, e:matrix.e, f:matrix.f},
                            rect:{left:rect.left, top:rect.top, right:rect.right, bottom:rect.bottom,
                                width:rect.width, height:rect.height},
                            parent:{left:parentRect.left, top:parentRect.top, right:parentRect.right,
                                bottom:parentRect.bottom, width:parentRect.width, height:parentRect.height},
                            gutters:{
                                left:rect.left - parentRect.left,
                                right:parentRect.right - rect.right,
                                top:rect.top - parentRect.top,
                                bottom:parentRect.bottom - rect.bottom
                            }
                        };
                    });
                    expect(scaleLayout.logicalWidth === 1024 && scaleLayout.logicalHeight === 576,
                        'character-create logical canvas is not exactly 1024x576: '
                            + JSON.stringify(scaleLayout));
                    expect(Math.abs(scaleLayout.scale - scaleLayout.expectedScale) <= 0.001
                        && Math.abs(scaleLayout.matrix.a - scaleLayout.scale) <= 0.001
                        && Math.abs(scaleLayout.matrix.d - scaleLayout.scale) <= 0.001
                        && Math.abs(scaleLayout.matrix.a - scaleLayout.matrix.d) <= 0.001
                        && Math.abs(scaleLayout.matrix.b) <= 0.001
                        && Math.abs(scaleLayout.matrix.c) <= 0.001,
                    'PanelScale is not the uniform min(parent/design) scale: '
                        + JSON.stringify(scaleLayout));
                    expect(Math.abs(scaleLayout.rect.width / scaleLayout.rect.height - 16 / 9) <= 0.001
                        && Math.abs(scaleLayout.gutters.left - scaleLayout.gutters.right) <= 1
                        && Math.abs(scaleLayout.gutters.top - scaleLayout.gutters.bottom) <= 1
                        && scaleLayout.gutters.left >= -1 && scaleLayout.gutters.right >= -1
                        && scaleLayout.gutters.top >= -1 && scaleLayout.gutters.bottom >= -1,
                    'scaled 16:9 canvas is distorted, clipped, or not centered: '
                        + JSON.stringify(scaleLayout));

                    // Keep this at the exact player-facing maximum. The protocol can
                    // carry 32 graphemes for displayName, but characterName is 1-15.
                    await page.locator('#cc-character-name').fill('界'.repeat(15));
                    await page.locator('#cc-next').click();
                    const equipmentLayout = await page.evaluate(() => {
                        const doc = document.documentElement;
                        const root = document.getElementById('character-create-root');
                        const shell = document.querySelector('.cc-shell').getBoundingClientRect();
                        const titleNode = document.getElementById('cc-title');
                        const stepsNode = document.querySelector('.cc-steps');
                        const title = titleNode.getBoundingClientRect();
                        const steps = stepsNode.getBoundingClientRect();
                        const titleRow = document.querySelector('.cc-title-row');
                        const panel = document.querySelector('[data-cc-panel="1"]');
                        const equipmentPool = document.getElementById('cc-equipment-pool');
                        const heightControl = document.getElementById('cc-preview-height-control');
                        const height = document.getElementById('cc-height');
                        return {
                            docOverflow: doc.scrollWidth - doc.clientWidth,
                            rootOverflow: root.scrollWidth - root.clientWidth,
                            rootOverflowStyle:getComputedStyle(root).overflowX,
                            shellLeft: shell.left,
                            shellRight: shell.right,
                            width: innerWidth,
                            fontScale:parseFloat(getComputedStyle(doc).getPropertyValue('--fs-scale')),
                            reduced: matchMedia('(prefers-reduced-motion: reduce)').matches,
                            titleAndStepsShareRow:titleNode.parentElement === stepsNode.parentElement
                                && titleNode.parentElement === titleRow,
                            stepsRightOfTitle:steps.left >= title.right - 1
                                && Math.abs((steps.top + steps.bottom - title.top - title.bottom) / 2) <= 8,
                            titleRect:{left:title.left, right:title.right, top:title.top, bottom:title.bottom},
                            stepsRect:{left:steps.left, right:steps.right, top:steps.top, bottom:steps.bottom},
                            stepsWidth:steps.width,
                            workflowWidth:document.getElementById('cc-form').getBoundingClientRect().width,
                            appearanceView:window.BootstrapCharacterCreate.debugState().appearanceView,
                            density:window.BootstrapCharacterCreate.debugState().appearanceDensity,
                            backgroundMotion:document.getElementById('bg-gl').dataset.characterCreateMotion,
                            slots:document.querySelectorAll('.cc-equipped-slot').length,
                            selectedSlots:document.querySelectorAll('.cc-equipped-slot[aria-checked="true"]').length,
                            poolOptions:equipmentPool.querySelectorAll('[role="option"]').length,
                            poolCompact:equipmentPool.classList.contains('item-grid-compact'),
                            poolFull:equipmentPool.classList.contains('cc-choice-pool-full'),
                            panelOverflow:getComputedStyle(panel).overflowY,
                            panelScrollTop:panel.scrollTop,
                            heightInPreview:heightControl.closest('.cc-preview') !== null
                                && !heightControl.hidden && !height.disabled,
                            heightInWorkflow:document.getElementById('cc-form').contains(heightControl),
                            rangeAppearance:getComputedStyle(height).appearance,
                            ranges:document.querySelectorAll('#view-character-create input[type="range"]').length,
                            selects:document.querySelectorAll('#view-character-create select').length,
                            visibleFaceCopy:Array.from(root.querySelectorAll('*')).some(node =>
                                node.children.length === 0 && node.getClientRects().length > 0
                                && node.textContent.trim() === '脸型'),
                            legacySelects:document.querySelectorAll('#cc-upper, #cc-lower, #cc-footwear').length,
                            randomButtons: Array.from(document.querySelectorAll('#view-character-create button'))
                                .filter(button => /随机|random/i.test(button.textContent)).length,
                            canvasTransform:(() => {
                                const matrix = new DOMMatrixReadOnly(getComputedStyle(
                                    document.getElementById('cc-preview-canvas')).transform);
                                return {a:matrix.a, b:matrix.b, c:matrix.c, d:matrix.d};
                            })(),
                            skinRules:(() => {
                                const selectors = [];
                                Array.from(document.styleSheets).forEach(sheet => {
                                    if (!sheet.href || !/\/css\/character-create\.css(?:$|\?)/.test(sheet.href)) return;
                                    function visit(rules) {
                                        Array.from(rules || []).forEach(rule => {
                                            if (rule.selectorText) selectors.push(rule.selectorText);
                                            if (rule.cssRules) visit(rule.cssRules);
                                        });
                                    }
                                    try { visit(sheet.cssRules); } catch (e) {}
                                });
                                return {
                                    rangeTrack:selectors.some(value => value.includes('::-webkit-slider-runnable-track')),
                                    rangeThumb:selectors.some(value => value.includes('::-webkit-slider-thumb')),
                                    scrollbar:selectors.some(value => value.includes('::-webkit-scrollbar')),
                                    scrollbarTrack:selectors.some(value => value.includes('::-webkit-scrollbar-track')),
                                    scrollbarThumb:selectors.some(value => value.includes('::-webkit-scrollbar-thumb'))
                                };
                            })()
                        };
                    });
                    expect(equipmentLayout.docOverflow <= 1,
                        'document horizontal overflow: ' + equipmentLayout.docOverflow);
                    // A fixed 1024 logical child can make scrollWidth exceed the
                    // smaller physical anchor even though PanelScale keeps its
                    // transformed rect entirely in-bounds. The root must clip that
                    // logical bookkeeping overflow; physical containment is checked
                    // by scaleLayout above.
                    expect(equipmentLayout.rootOverflowStyle === 'hidden',
                        'character-create scale anchor does not clip logical overflow: '
                            + JSON.stringify(equipmentLayout));
                    expect(equipmentLayout.shellLeft >= -1
                        && equipmentLayout.shellRight <= equipmentLayout.width + 1,
                    'shell escaped viewport bounds');
                    expect(equipmentLayout.titleAndStepsShareRow && equipmentLayout.stepsRightOfTitle
                        && equipmentLayout.stepsWidth < equipmentLayout.workflowWidth,
                    'step indicator is not compactly placed to the right of the title: '
                        + JSON.stringify(equipmentLayout));
                    expect(equipmentLayout.appearanceView === 'equipment'
                        && equipmentLayout.density.equipment === 'full'
                        && equipmentLayout.density.hair === 'compact'
                        && equipmentLayout.backgroundMotion === 'ambient'
                        && equipmentLayout.slots === 3 && equipmentLayout.selectedSlots === 1
                        && equipmentLayout.poolOptions > 0 && !equipmentLayout.poolCompact
                        && equipmentLayout.poolFull,
                    'equipment-first slot/pool per-view density layout drifted: ' + JSON.stringify(equipmentLayout));
                    expect(equipmentLayout.heightInPreview && !equipmentLayout.heightInWorkflow
                        && equipmentLayout.ranges === 1 && equipmentLayout.rangeAppearance === 'none',
                    'height control is duplicated, misplaced, disabled, or browser-native: '
                        + JSON.stringify(equipmentLayout));
                    expect(equipmentLayout.selects === 0 && !equipmentLayout.visibleFaceCopy
                        && equipmentLayout.legacySelects === 0,
                    'face copy or a browser-native/legacy select leaked into the appearance page');
                    expect(equipmentLayout.skinRules.rangeTrack && equipmentLayout.skinRules.rangeThumb
                        && equipmentLayout.skinRules.scrollbar && equipmentLayout.skinRules.scrollbarTrack
                        && equipmentLayout.skinRules.scrollbarThumb,
                    'character-create range/scrollbar skin is incomplete: '
                        + JSON.stringify(equipmentLayout.skinRules));
                    expect(Math.abs(equipmentLayout.canvasTransform.a - equipmentLayout.canvasTransform.d) <= 0.001
                        && Math.abs(equipmentLayout.canvasTransform.b) <= 0.001
                        && Math.abs(equipmentLayout.canvasTransform.c) <= 0.001,
                    'paper-doll canvas uses a non-uniform transform: '
                        + JSON.stringify(equipmentLayout.canvasTransform));
                    expect(equipmentLayout.panelOverflow === 'hidden' && equipmentLayout.panelScrollTop === 0,
                        'appearance outer panel retained a nested scroll surface');
                    await page.locator('#cc-appearance-tab-hair').click();
                    const hairLayout = await page.evaluate(() => {
                        const hair = document.getElementById('cc-hair-list');
                        const cards = Array.from(hair.querySelectorAll('.cc-hair-option'));
                        const rect = hair.getBoundingClientRect();
                        const rects = cards.map(card => card.getBoundingClientRect());
                        return {
                            count:cards.length,
                            icons:hair.querySelectorAll('.cc-hair-option .cc-hair-icon').length,
                            selected:hair.querySelectorAll('[aria-selected="true"]').length,
                            tabbable:hair.querySelectorAll('[tabindex="0"]').length,
                            slotVisible:document.getElementById('cc-hair-slot').getClientRects().length > 0,
                            compact:hair.classList.contains('item-grid-compact'),
                            allVisible:cards.every(card => !card.hidden && card.getClientRects().length > 0),
                            square:rects.length > 0 && rects.every(cardRect =>
                                Math.abs(cardRect.width - cardRect.height) <= 1),
                            contained:rects.every(cardRect => cardRect.left >= rect.left - 1
                                && cardRect.right <= rect.right + 1 && cardRect.top >= rect.top - 1
                                && cardRect.bottom <= rect.bottom + 1),
                            copyHidden:cards.every(card =>
                                getComputedStyle(card.querySelector('.cc-hair-copy')).display === 'none'),
                            overflow:getComputedStyle(hair).overflowY,
                            noScroll:hair.scrollHeight <= hair.clientHeight + 1
                                && hair.scrollWidth <= hair.clientWidth + 1 && hair.scrollTop === 0,
                            dimensions:{clientWidth:hair.clientWidth, clientHeight:hair.clientHeight,
                                scrollWidth:hair.scrollWidth, scrollHeight:hair.scrollHeight},
                            panelScrollTop:document.querySelector('[data-cc-panel="1"]').scrollTop,
                            pagerAbsent:!document.getElementById('cc-hair-pager')
                        };
                    });
                    expect(hairLayout.count === 77 && hairLayout.icons === 77
                        && hairLayout.selected === 1 && hairLayout.tabbable === 1
                        && hairLayout.slotVisible && hairLayout.compact && hairLayout.allVisible
                        && hairLayout.square && hairLayout.contained && hairLayout.copyHidden
                        && hairLayout.noScroll && hairLayout.overflow === 'auto' && hairLayout.pagerAbsent,
                    '77-card compact hair slot/pool contract drifted: ' + JSON.stringify(hairLayout));
                    const selectedHair = page.locator('#cc-hair-list [tabindex="0"]');
                    await selectedHair.focus();
                    await selectedHair.press('Home');
                    await page.waitForFunction(() =>
                        window.BootstrapCharacterCreate.debugState().hairIndex === 0);
                    const scroll = await page.evaluate(() => ({
                        hair:document.getElementById('cc-hair-list').scrollTop,
                        panel:document.querySelector('[data-cc-panel="1"]').scrollTop,
                        hairIndex:window.BootstrapCharacterCreate.debugState().hairIndex
                    }));
                    expect(scroll.hair === 0 && scroll.panel === 0 && scroll.hairIndex === 0,
                        'compact keyboard navigation moved a forbidden scroll surface: '
                            + JSON.stringify(scroll));

                    const beforeDensityChange = await page.evaluate(() => ({
                        draft:JSON.stringify(window.BootstrapCharacterCreate.debugState().draft),
                        outbound:window.__ccHarness.events.filter(event => event.direction === 'out').length
                    }));
                    await page.locator('.cc-density-option[data-density="full"]').click();
                    const fullLayout = await page.evaluate(() => {
                        const list = document.getElementById('cc-hair-list');
                        const panel = document.querySelector('[data-cc-panel="1"]');
                        const options = Array.from(list.querySelectorAll('.cc-hair-option'));
                        const indices = options.map(option => Number(option.getAttribute('data-index')));
                        const listStyle = getComputedStyle(list);
                        const listRect = list.getBoundingClientRect();
                        const optionRects = options.map(option => option.getBoundingClientRect());
                        const selected = list.querySelector('[aria-selected="true"]');
                        const selectedCopy = selected.querySelector('.cc-hair-copy');
                        const selectedMarker = selected.querySelector('.cc-hair-marker');
                        const copyRect = selectedCopy.getBoundingClientRect();
                        const markerRect = selectedMarker.getBoundingClientRect();
                        const firstName = options[0].querySelector('.cc-hair-copy b');
                        const firstNameStyle = getComputedStyle(firstName);
                        const firstCardStyle = getComputedStyle(options[0]);
                        return {
                            compact:list.classList.contains('item-grid-compact'),
                            optionCount:options.length,
                            indices:indices,
                            allAbsolute:indices.every(Number.isInteger),
                            pagerAbsent:!document.getElementById('cc-hair-pager'),
                            internalScroll:list.scrollHeight > list.clientHeight + 1
                                && list.scrollWidth <= list.clientWidth + 1 && list.scrollTop === 0,
                            panelNoScroll:panel.scrollHeight <= panel.clientHeight + 1 && panel.scrollTop === 0,
                            selectedCount:options.filter(option => option.getAttribute('aria-selected') === 'true').length,
                            tabbableCount:options.filter(option => option.tabIndex === 0).length,
                            allMounted:options.every(option => !option.hidden && option.getClientRects().length > 0),
                            horizontallyContained:optionRects.every(rect => rect.left >= listRect.left - 1
                                && rect.right <= listRect.right + 1),
                            identityVisible:options.every(option => {
                                const text = option.querySelector('.cc-hair-copy b').textContent.trim();
                                return text.length > 0 && !/^发型[-－_]/.test(text);
                            }),
                            rawNamesAccessible:options.every(option => {
                                const label = option.getAttribute('aria-label') || '';
                                return label.startsWith('发型，') && label.length > 3;
                            }),
                            nameWrap:firstNameStyle.whiteSpace === 'normal'
                                && (firstNameStyle.webkitLineClamp === '2' || firstNameStyle.webkitLineClamp === 2),
                            markerSeparated:copyRect.right <= markerRect.left + 1
                                && getComputedStyle(selectedMarker).position === 'static',
                            minimumCardSize:options.every(option => option.offsetHeight >= 58 && option.offsetWidth >= 200),
                            firstCardColumns:firstCardStyle.gridTemplateColumns,
                            dimensions:{
                                clientWidth:list.clientWidth, clientHeight:list.clientHeight,
                                scrollWidth:list.scrollWidth, scrollHeight:list.scrollHeight
                            },
                            grid:{
                                columns:listStyle.gridTemplateColumns,
                                rows:listStyle.gridTemplateRows,
                                columnGap:listStyle.columnGap,
                                rowGap:listStyle.rowGap,
                                padding:[listStyle.paddingTop, listStyle.paddingRight,
                                    listStyle.paddingBottom, listStyle.paddingLeft],
                                physicalColumns:new Set(optionRects.map(rect => rect.left.toFixed(2))).size,
                                physicalRows:new Set(optionRects.map(rect => rect.top.toFixed(2))).size
                            },
                            listRect:{width:listRect.width, height:listRect.height}
                        };
                    });
                    expect(!fullLayout.compact && fullLayout.optionCount === 77 && fullLayout.allAbsolute
                        && fullLayout.indices[0] === 0 && fullLayout.indices[76] === 76
                        && fullLayout.pagerAbsent && fullLayout.internalScroll && fullLayout.panelNoScroll
                        && fullLayout.selectedCount === 1 && fullLayout.tabbableCount === 1
                        && fullLayout.allMounted && fullLayout.horizontallyContained
                        && fullLayout.identityVisible && fullLayout.rawNamesAccessible
                        && fullLayout.nameWrap && fullLayout.markerSeparated && fullLayout.minimumCardSize,
                    'full hair mode is not a large-card 77-item internal scroller: '
                        + JSON.stringify(fullLayout));
                    await page.locator('#cc-appearance-tab-equipment').click();
                    const equipmentFull = await page.evaluate(() => {
                        const cards = Array.from(document.querySelectorAll('#cc-equipment-pool .cc-item-option'));
                        return {
                            count:cards.length,
                            minimumSize:cards.every(card => card.offsetWidth >= 200 && card.offsetHeight >= 58),
                            namesWrap:cards.every(card => getComputedStyle(card.querySelector('.cc-item-copy b')).whiteSpace === 'normal'),
                            markerSeparated:cards.filter(card => card.getAttribute('aria-selected') === 'true').every(card => {
                                const copy = card.querySelector('.cc-item-copy').getBoundingClientRect();
                                const marker = card.querySelector('.cc-item-marker').getBoundingClientRect();
                                return copy.right <= marker.left + 1 && getComputedStyle(card.querySelector('.cc-item-marker')).position === 'static';
                            })
                        };
                    });
                    expect(equipmentFull.count > 0 && equipmentFull.minimumSize
                        && equipmentFull.namesWrap && equipmentFull.markerSeparated,
                    'full equipment cards did not inherit the enlarged non-overlap contract: '
                        + JSON.stringify(equipmentFull));
                    await page.locator('#cc-appearance-tab-hair').click();
                    await page.evaluate(() => {
                        const list = document.getElementById('cc-hair-list');
                        list.scrollTop = list.scrollHeight;
                    });
                    const afterScroll = await page.evaluate(() => ({
                        draft:JSON.stringify(window.BootstrapCharacterCreate.debugState().draft),
                        outbound:window.__ccHarness.events.filter(event => event.direction === 'out').length,
                        scrollTop:document.getElementById('cc-hair-list').scrollTop
                    }));
                    expect(afterScroll.draft === beforeDensityChange.draft
                        && afterScroll.outbound === beforeDensityChange.outbound && afterScroll.scrollTop > 0,
                    'density/scroll navigation mutated the draft, emitted an RPC, or failed to scroll');
                    await page.locator('#cc-hair-list [data-index="76"]').click();
                    await page.locator('.cc-density-option[data-density="compact"]').click();
                    const compactRestored = await page.evaluate(() => {
                        const list = document.getElementById('cc-hair-list');
                        const options = Array.from(list.querySelectorAll('.cc-hair-option'));
                        return {
                            count:options.length,
                            visible:options.filter(option => option.getClientRects().length > 0).length,
                            selected:Number(list.querySelector('[aria-selected="true"]').getAttribute('data-index')),
                            noScroll:list.scrollHeight <= list.clientHeight + 1 && list.scrollTop === 0,
                            pagerAbsent:!document.getElementById('cc-hair-pager')
                        };
                    });
                    expect(compactRestored.count === 77 && compactRestored.visible === 77
                        && compactRestored.selected === 76 && compactRestored.noScroll
                        && compactRestored.pagerAbsent,
                    'compact mode did not restore all 77 options/selection without scrolling: '
                        + JSON.stringify(compactRestored));

                    if (viewport.width === 1600 && viewport.height === 900
                            && viewport.uiFontScale === 1.35) {
                        const geometry = () => page.evaluate(() => {
                            const selectors = ['.cc-scale-shell', '.cc-shell', '.cc-preview', '#cc-form',
                                '[data-cc-panel="1"]', '#cc-hair-list', '.cc-actions'];
                            return {
                                viewport:[innerWidth, innerHeight],
                                rects:selectors.map(selector => {
                                    const rect = document.querySelector(selector).getBoundingClientRect();
                                    return [rect.left, rect.top, rect.width, rect.height];
                                }),
                                scroll:selectors.map(selector => {
                                    const node = document.querySelector(selector);
                                    return [node.clientWidth, node.clientHeight, node.scrollWidth,
                                        node.scrollHeight, node.scrollLeft, node.scrollTop];
                                })
                            };
                        });
                        const beforeFullscreen = await geometry();
                        await page.locator('#btn-fullscreen').click();
                        await page.waitForFunction(() => document.fullscreenElement === document.documentElement);
                        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() =>
                            requestAnimationFrame(resolve))));
                        const afterFullscreen = await geometry();
                        expect(afterFullscreen.viewport[0] === 1600 && afterFullscreen.viewport[1] === 900,
                            'DOM fullscreen changed the fixed 1600x900 CSS viewport');
                        beforeFullscreen.rects.forEach((rect, index) => rect.forEach((value, field) => {
                            expect(Math.abs(value - afterFullscreen.rects[index][field]) <= 1,
                                'DOM fullscreen changed normalized geometry at rect '
                                    + index + '/' + field + ': ' + JSON.stringify({beforeFullscreen,
                                        afterFullscreen}));
                        }));
                        expect(JSON.stringify(afterFullscreen.scroll) === JSON.stringify(beforeFullscreen.scroll),
                            'DOM fullscreen changed client/scroll geometry: '
                                + JSON.stringify({beforeFullscreen, afterFullscreen}));
                        await page.evaluate(() => document.exitFullscreen());
                        await page.waitForFunction(() => !document.fullscreenElement);
                    }

                    await page.locator('#cc-next').click();
                    // 等步骤面板入场动画播完再量 rect；reduced 视口下 cc.js 不加 .cc-panel-enter，立即通过。
                    await page.waitForFunction(() => !document.querySelector('.cc-panel-enter'));
                    const confirmationLayout = await page.evaluate(() => {
                        const panel = document.querySelector('[data-cc-panel="2"]');
                        const panelRect = panel.getBoundingClientRect();
                        const layout = panel.querySelector('.cc-confirm-layout');
                        const layoutRect = layout.getBoundingClientRect();
                        const modes = panel.querySelector('.cc-confirm-modes');
                        const modesRect = modes.getBoundingClientRect();
                        const summary = panel.querySelector('.cc-confirm-summary');
                        const summaryRect = summary.getBoundingClientRect();
                        const difficultyRects = Array.from(document.querySelectorAll('.cc-difficulty'))
                            .map(node => node.getBoundingClientRect());
                        const workflow = document.getElementById('cc-form');
                        const actions = document.querySelector('.cc-actions');
                        const required = [document.querySelector('.cc-difficulties'),
                            document.querySelector('.cc-review')].concat(
                            Array.from(document.querySelectorAll('.cc-difficulty')));
                        return {
                            panelNoScroll:panel.scrollHeight <= panel.clientHeight + 1
                                && panel.scrollWidth <= panel.clientWidth + 1 && panel.scrollTop === 0,
                            panelOverflow:getComputedStyle(panel).overflowY,
                            twoColumns:getComputedStyle(layout).gridTemplateColumns.split(/\s+/).length === 2
                                && modesRect.right < summaryRect.left,
                            columnsUseHeight:modesRect.height >= panelRect.height * .82
                                && summaryRect.height >= panelRect.height * .82,
                            difficultyStack:difficultyRects.length === 3
                                && difficultyRects.every((rect, index) => index === 0
                                    || rect.top > difficultyRects[index - 1].bottom - 1)
                                && difficultyRects.every(rect => Math.abs(rect.left - difficultyRects[0].left) <= 1
                                    && Math.abs(rect.width - difficultyRects[0].width) <= 1),
                            summaryReadable:Array.from(document.querySelectorAll('.cc-review dd')).every(node => {
                                const style = getComputedStyle(node);
                                return style.whiteSpace === 'normal' && style.overflow !== 'hidden';
                            }),
                            layoutFillsPanel:layoutRect.height >= panelRect.height - 2
                                && layoutRect.width >= panelRect.width - 24,
                            requiredContained:required.every(node => {
                                const rect = node.getBoundingClientRect();
                                return rect.left >= panelRect.left - 1 && rect.right <= panelRect.right + 1
                                    && rect.top >= panelRect.top - 1 && rect.bottom <= panelRect.bottom + 1;
                            }),
                            requiredRects:required.map(node => {
                                const rect = node.getBoundingClientRect();
                                return {
                                    name:node.id || node.className,
                                    left:rect.left, top:rect.top, right:rect.right, bottom:rect.bottom,
                                    contained:rect.left >= panelRect.left - 1 && rect.right <= panelRect.right + 1
                                        && rect.top >= panelRect.top - 1 && rect.bottom <= panelRect.bottom + 1
                                };
                            }),
                            panelRect:{left:panelRect.left, top:panelRect.top,
                                right:panelRect.right, bottom:panelRect.bottom},
                            actionsContained:(() => {
                                const rect = actions.getBoundingClientRect();
                                const host = workflow.getBoundingClientRect();
                                return rect.left >= host.left - 1 && rect.right <= host.right + 1
                                    && rect.top >= panelRect.bottom - 1 && rect.bottom <= host.bottom + 1;
                            })(),
                            viewNoScroll:(() => {
                                const view = document.getElementById('view-character-create');
                                return view.scrollHeight <= view.clientHeight + 1
                                    && view.scrollWidth <= view.clientWidth + 1 && view.scrollTop === 0;
                            })(),
                            dimensions:{clientWidth:panel.clientWidth, clientHeight:panel.clientHeight,
                                scrollWidth:panel.scrollWidth, scrollHeight:panel.scrollHeight}
                        };
                    });
                    expect(confirmationLayout.panelNoScroll
                        && confirmationLayout.panelOverflow === 'hidden'
                        && confirmationLayout.twoColumns && confirmationLayout.columnsUseHeight
                        && confirmationLayout.difficultyStack && confirmationLayout.summaryReadable
                        && confirmationLayout.layoutFillsPanel
                        && confirmationLayout.requiredContained && confirmationLayout.actionsContained
                        && confirmationLayout.viewNoScroll,
                    'confirmation page requires scrolling, clips required content, or overlaps actions: '
                        + JSON.stringify(confirmationLayout));
                    expect(equipmentLayout.randomButtons === 0, 'random appearance control must not exist');
                    expect(equipmentLayout.reduced === viewport.reduced, 'reduced-motion emulation mismatch');
                    expect(Math.abs(equipmentLayout.fontScale - viewport.uiFontScale) < 0.001,
                        'font scale did not reach the requested layout matrix value: '
                            + JSON.stringify(equipmentLayout));
                    return 'uniform centered 1024x576 canvas; compact 77/full 77-scroll/two-column confirm; fs='
                        + equipmentLayout.fontScale + '; reduced=' + equipmentLayout.reduced;
                } finally {
                    await page.close();
                }
            });
        }

        await check('preparation-overlay-first-frame-double-raf-gate', async () => {
            const preloadPage = await setupPage(browser, url, { width: 1366, height: 768 }, true,
                template, evidence, { deferSnapshot:true, manifestFailure:false });
            try {
                await installManualAnimationFrames(preloadPage);
                await holdRendererCallbacksWithZeroProbe(preloadPage);
                await preloadPage.evaluate(() => window.BootstrapApp.openCharacterCreate('new', null));
                await preloadPage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    return state.phase === 'starting' && !document.getElementById('view-character-create').hidden;
                });
                await preloadPage.keyboard.type('加载期禁止输入');
                const starting = await preparationPresentation(preloadPage);
                expect(starting.bodyPreparing && starting.overlayOn && starting.overlayLoading
                    && starting.overlayVisibility === 'visible'
                    && starting.overlayBeforeContent === 'none'
                    && starting.overlayAfterContent === 'none'
                    && starting.overlayRect.left === 0 && starting.overlayRect.top === 0
                    && Math.abs(starting.overlayRect.right - starting.width) <= 1
                    && Math.abs(starting.overlayRect.bottom - starting.height) <= 1,
                'preparation overlay is not the plain full-screen loading owner: ' + JSON.stringify(starting));
                expect(starting.viewInert && starting.viewBusy === 'true'
                    && starting.viewVisibility === 'hidden' && starting.nameDisabled
                    && starting.nameValue === '' && !starting.activeInside
                    && starting.loadingText.includes('正在准备角色'),
                'starting phase exposed focus or editing before authoritative data/preview: '
                    + JSON.stringify(starting));
                await preloadPage.evaluate(() => window.__ccHarness.deliverSnapshot());
                await preloadPage.waitForFunction(() => window.__ccRenderProbe);
                const framesBeforeZero = await preloadPage.evaluate(() =>
                    window.__ccManualFrames.pendingPresentation());
                expect(await preloadPage.evaluate(() => window.__ccRenderProbe.releaseZero()),
                    'zero-draw renderer callback could not be injected');
                await preloadPage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    const meta = state.rendererMeta;
                    return state.phase === 'preparing' && meta && meta.holders === 0
                        && meta.drawnImages === 0 && meta.pendingImages === 0
                        && meta.failedImages === 0 && meta.missing === 0;
                }, null, { timeout:30000 });
                const zeroDraw = await preparationPresentation(preloadPage);
                expect(zeroDraw.state.phase === 'preparing'
                    && zeroDraw.pendingPresentationFrames === framesBeforeZero
                    && zeroDraw.bodyPreparing && zeroDraw.overlayOn && zeroDraw.viewInert
                    && zeroDraw.viewVisibility === 'hidden'
                    && zeroDraw.activeId !== 'cc-character-name',
                'zero-draw pending=0 callback prematurely degraded/revealed the form: '
                    + JSON.stringify(zeroDraw));
                await preloadPage.waitForFunction(() =>
                    window.__ccRenderProbe && window.__ccRenderProbe.strictReady(),
                null, { timeout:30000 });
                const preRevealDrain = await drainAnimationFrames(preloadPage);
                expect(preRevealDrain.pending === 0,
                    'renderer-owned animation frames did not drain before reveal test: '
                        + JSON.stringify(preRevealDrain));
                const framesBeforeThreshold = await preloadPage.evaluate(() =>
                    window.__ccManualFrames.pendingPresentation());
                expect(await preloadPage.evaluate(() => window.__ccRenderProbe.releaseSubthresholdStrict()),
                    'strict renderer metadata could not be paired with a 500-alpha-pixel canvas');
                await preloadPage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    const meta = state.rendererMeta;
                    return state.phase === 'preparing' && meta && meta.holders > 0
                        && meta.drawnImages > 0 && meta.pendingImages === 0
                        && state.previewAlphaPixels < state.minimumPreviewAlphaPixels;
                }, null, { timeout:30000 });
                const subthresholdStrict = await preparationPresentation(preloadPage);
                expect(subthresholdStrict.state.phase === 'preparing'
                    && subthresholdStrict.state.previewAlphaPixels === 500
                    && subthresholdStrict.state.minimumPreviewAlphaPixels === 501
                    && subthresholdStrict.pendingPresentationFrames === framesBeforeThreshold
                    && subthresholdStrict.bodyPreparing && subthresholdStrict.overlayOn
                    && subthresholdStrict.viewInert && subthresholdStrict.viewVisibility === 'hidden',
                'strict renderer metadata with only 500 alpha pixels prematurely revealed the form: '
                    + JSON.stringify(subthresholdStrict));
                expect(await preloadPage.evaluate(() => window.__ccRenderProbe.releaseStrict()),
                    'strict renderer repaint was not available for release');
                await preloadPage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    const meta = state.rendererMeta;
                    return state.phase === 'preparing' && meta && meta.holders > 0
                        && meta.drawnImages > 0 && meta.pendingImages === 0
                        && meta.failedImages === 0 && meta.missing === 0
                        && state.previewAlphaPixels >= state.minimumPreviewAlphaPixels
                        && window.__ccManualFrames.pendingPresentation() > 0;
                }, null, { timeout:30000 });
                const rendered = await preloadPage.evaluate(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    const canvas = document.getElementById('cc-preview-canvas');
                    const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
                    let visiblePixels = 0;
                    for (let i = 3; i < pixels.length; i += 4) if (pixels[i] > 0) visiblePixels++;
                    return {state, visiblePixels};
                });
                expect(rendered.visiblePixels > 500,
                    'first-frame production gate accepted an effectively blank canvas: '
                        + JSON.stringify(rendered));
                const beforeFirstFrame = await preparationPresentation(preloadPage);
                expect(beforeFirstFrame.state.phase === 'preparing' && beforeFirstFrame.viewInert
                    && beforeFirstFrame.viewVisibility === 'hidden' && beforeFirstFrame.overlayOn
                    && beforeFirstFrame.activeId !== 'cc-character-name',
                'completed render was revealed before the first presentation frame');
                expect(await flushPresentationFrame(preloadPage),
                    'first reveal animation frame was not queued');
                const betweenFrames = await preparationPresentation(preloadPage);
                expect(betweenFrames.state.phase === 'preparing' && betweenFrames.viewInert
                    && betweenFrames.viewVisibility === 'hidden' && betweenFrames.overlayOn
                    && betweenFrames.pendingPresentationFrames > 0,
                'one animation frame prematurely revealed the character form: '
                    + JSON.stringify(betweenFrames));
                expect(await flushPresentationFrame(preloadPage),
                    'second reveal animation frame was not queued');
                await preloadPage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    return state.phase === 'editing'
                        && !document.getElementById('view-character-create').hasAttribute('inert')
                        && document.activeElement === document.getElementById('cc-character-name');
                });
                await preloadPage.waitForFunction(() =>
                    !document.getElementById('intro-ov').classList.contains('on'));
                const revealed = await preparationPresentation(preloadPage);
                expect(!revealed.bodyPreparing && !revealed.viewInert
                    && revealed.viewBusy === null && revealed.viewVisibility === 'visible'
                    && !revealed.overlayOn && revealed.activeId === 'cc-character-name',
                'double-rAF completion did not atomically reveal/focus the form: '
                    + JSON.stringify(revealed));
                return 'full-screen inert gate holds through complete nonblank first render and reveals/focuses only after two rAFs';
            } finally {
                await preloadPage.close();
            }
        });

        await check('preparation-deadline-degraded-double-raf-gate', async () => {
            const deadlinePage = await setupPage(browser, url, { width:1366, height:768 }, true,
                template, evidence, {
                    deferSnapshot:true,
                    manifestFailure:false
                });
            try {
                await installPreparationDeadlineProbe(deadlinePage, 3000, false);
                await installManualAnimationFrames(deadlinePage);
                await holdRendererCallbacksWithZeroProbe(deadlinePage);
                await deadlinePage.evaluate(() => window.BootstrapApp.openCharacterCreate('new', null));
                await deadlinePage.waitForFunction(() =>
                    window.BootstrapCharacterCreate.debugState().phase === 'starting');
                await deadlinePage.evaluate(() => window.__ccHarness.deliverSnapshot());
                await deadlinePage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    return state.phase === 'preparing' && window.__ccRenderProbe
                        && window.__ccDeadlineProbe && window.__ccDeadlineProbe.scheduled >= 1
                        && window.__ccDeadlineProbe.fired === 0;
                }, null, { timeout:10000 });
                expect(await deadlinePage.evaluate(() => window.__ccRenderProbe.releaseZero()),
                    'deadline probe could not inject the zero-draw intermediate frame');
                await deadlinePage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    const meta = state.rendererMeta;
                    return state.phase === 'preparing' && meta && meta.holders === 0
                        && meta.pendingImages === 0 && meta.drawnImages === 0;
                });
                expect(await deadlinePage.evaluate(() =>
                    window.__ccRenderProbe.releaseSubthresholdStrict()),
                'deadline probe could not inject the 500-alpha-pixel frame');
                await deadlinePage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    return state.phase === 'preparing' && state.previewAlphaPixels === 500
                        && state.minimumPreviewAlphaPixels === 501;
                });
                const beforeDeadline = await preparationPresentation(deadlinePage);
                expect(beforeDeadline.pendingPresentationFrames === 0 && beforeDeadline.bodyPreparing
                    && beforeDeadline.overlayOn && beforeDeadline.viewInert
                    && beforeDeadline.viewVisibility === 'hidden',
                'subthreshold frame queued a reveal before the presentation deadline: '
                    + JSON.stringify(beforeDeadline));
                await deadlinePage.waitForTimeout(3500);
                const timedOut = await preparationPresentation(deadlinePage);
                const deadlineProbe = await deadlinePage.evaluate(() => Object.assign({}, window.__ccDeadlineProbe));
                expect(deadlineProbe.fired === 1 && timedOut.state.rendererIssue === 'render_failed'
                    && timedOut.state.phase === 'preparing' && timedOut.bodyPreparing
                    && timedOut.overlayOn && timedOut.viewInert
                    && timedOut.viewVisibility === 'hidden' && timedOut.pendingPresentationFrames > 0,
                'presentation deadline bypassed the first reveal frame: '
                    + JSON.stringify({ deadlineProbe, timedOut }));
                expect(await flushPresentationFrame(deadlinePage),
                    'deadline reveal did not queue its first animation frame');
                const betweenFrames = await preparationPresentation(deadlinePage);
                expect(betweenFrames.state.phase === 'preparing' && betweenFrames.bodyPreparing
                    && betweenFrames.overlayOn && betweenFrames.viewInert
                    && betweenFrames.viewVisibility === 'hidden'
                    && betweenFrames.pendingPresentationFrames > 0,
                'presentation deadline revealed after only one animation frame: '
                    + JSON.stringify(betweenFrames));
                expect(await flushPresentationFrame(deadlinePage),
                    'deadline reveal did not queue its second animation frame');
                await deadlinePage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    return state.phase === 'editing'
                        && document.activeElement === document.getElementById('cc-character-name')
                        && !document.getElementById('intro-ov').classList.contains('on');
                });
                const degraded = await preparationPresentation(deadlinePage);
                const fallback = await deadlinePage.locator('#cc-preview-fallback').textContent();
                expect(!degraded.bodyPreparing && !degraded.overlayOn && !degraded.viewInert
                    && degraded.viewVisibility === 'visible' && degraded.activeId === 'cc-character-name'
                    && fallback.includes('角色预览暂时不可用'),
                'deadline did not finish as an explicit degraded editing state: '
                    + JSON.stringify({ degraded, fallback }));
                await deadlinePage.locator('#cc-cancel').click();
                return 'exact 12000ms deadline is accelerated in-test; zero/500px remains masked and degraded editing still waits for two rAFs';
            } finally {
                await deadlinePage.close();
            }
        });

        await check('cancel-reopen-stale-deadline-isolation', async () => {
            const staleDeadlinePage = await setupPage(browser, url, { width:1366, height:768 }, true,
                template, evidence, {
                    deferSnapshot:true,
                    manifestFailure:false
                });
            try {
                await installPreparationDeadlineProbe(staleDeadlinePage, 1000, true);
                await installManualAnimationFrames(staleDeadlinePage);
                await holdRendererCallbacksWithZeroProbe(staleDeadlinePage);
                await staleDeadlinePage.evaluate(() => window.BootstrapApp.openCharacterCreate('new', null));
                await staleDeadlinePage.waitForFunction(() =>
                    window.BootstrapCharacterCreate.debugState().phase === 'starting');
                await staleDeadlinePage.evaluate(() => window.__ccHarness.deliverSnapshot(0));
                await staleDeadlinePage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    return state.phase === 'preparing' && window.__ccDeadlineProbe
                        && window.__ccDeadlineProbe.scheduled >= 1;
                });
                const first = await staleDeadlinePage.evaluate(() =>
                    window.BootstrapCharacterCreate.debugState());
                await staleDeadlinePage.keyboard.press('Escape');
                await staleDeadlinePage.waitForFunction(() =>
                    !document.getElementById('view-slots').hidden);
                await staleDeadlinePage.evaluate(() =>
                    window.BootstrapApp.openCharacterCreate('new', null));
                await staleDeadlinePage.waitForFunction(oldToken => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    return state.phase === 'starting' && state.openRequestId !== oldToken;
                }, first.openRequestId);
                const second = await staleDeadlinePage.evaluate(() =>
                    window.BootstrapCharacterCreate.debugState());
                await staleDeadlinePage.waitForTimeout(1500);
                const drained = await drainAnimationFrames(staleDeadlinePage);
                expect(drained.pending === 0,
                    'stale deadline left an undrained reveal callback: ' + JSON.stringify(drained));
                const afterStale = await preparationPresentation(staleDeadlinePage);
                const deadlineProbe = await staleDeadlinePage.evaluate(() =>
                    Object.assign({}, window.__ccDeadlineProbe));
                expect(second.openRequestId !== first.openRequestId
                    && deadlineProbe.fired >= 1 && deadlineProbe.fired <= deadlineProbe.scheduled
                    && deadlineProbe.cleared > 0
                    && afterStale.state.phase === 'starting'
                    && afterStale.state.openRequestId === second.openRequestId
                    && !afterStale.state.attemptId && afterStale.nameValue === ''
                    && afterStale.bodyPreparing && afterStale.overlayOn && afterStale.viewInert
                    && afterStale.viewVisibility === 'hidden'
                    && afterStale.activeId !== 'cc-character-name',
                'canceled generation deadline callback released or populated the reopened request: '
                    + JSON.stringify({ deadlineProbe, first, second, afterStale }));
                await staleDeadlinePage.keyboard.press('Escape');
                await staleDeadlinePage.waitForFunction(() =>
                    !document.getElementById('view-slots').hidden);
                return 'one or more intentionally leaked old deadlines fire after reopen but generation/token guards preserve the new full-screen mask';
            } finally {
                await staleDeadlinePage.close();
            }
        });

        await check('manifest-503-degrades-to-editing', async () => {
            const degradedPage = await setupPage(browser, url, { width:1366, height:768 }, true,
                template, evidence);
            try {
                const state = await openCharacterCreate(degradedPage);
                const presentation = await preparationPresentation(degradedPage);
                const fallback = await degradedPage.locator('#cc-preview-fallback').textContent();
                expect(state.phase === 'editing' && state.rendererIssue === 'manifest_failed'
                    && !presentation.bodyPreparing && !presentation.overlayOn
                    && !presentation.viewInert && presentation.viewVisibility === 'visible'
                    && presentation.activeId === 'cc-character-name'
                    && fallback.includes('角色预览暂时不可用'),
                'manifest 503 did not enter explicit degraded editing: '
                    + JSON.stringify({ state, presentation, fallback }));
                return 'manifest 503 is a visible degraded preview, not a permanent interaction lock';
            } finally {
                await degradedPage.close();
            }
        });

        await check('cancel-reopen-stale-snapshot-and-double-raf-isolation', async () => {
            const latePage = await setupPage(browser, url, { width:1366, height:768 }, true,
                template, evidence, { deferSnapshot:true, manifestFailure:false });
            try {
                await installManualAnimationFrames(latePage);
                await holdRendererCallbacksWithZeroProbe(latePage);
                await latePage.evaluate(() => window.BootstrapApp.openCharacterCreate('new', null));
                await latePage.waitForFunction(() => window.BootstrapCharacterCreate.debugState().phase === 'starting');
                const first = await latePage.evaluate(() => window.BootstrapCharacterCreate.debugState());
                await latePage.evaluate(() => window.__ccHarness.deliverSnapshot(0));
                await latePage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    return state.phase === 'preparing' && state.rendererIssue === ''
                        && window.__ccRenderProbe;
                }, null, { timeout:30000 });
                const firstFrames = await latePage.evaluate(() =>
                    window.__ccManualFrames.pendingPresentation());
                expect(await latePage.evaluate(() => window.__ccRenderProbe.releaseFailure()),
                    'first request did not accept an explicit renderer failure');
                await latePage.waitForFunction(previous =>
                    window.__ccManualFrames.pendingPresentation() > previous,
                    firstFrames);
                await latePage.keyboard.press('Escape');
                await latePage.waitForFunction(() => !document.getElementById('view-slots').hidden);

                await latePage.evaluate(() => window.BootstrapApp.openCharacterCreate('new', null));
                await latePage.waitForFunction(oldId => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    return state.phase === 'starting' && state.openRequestId !== oldId;
                }, first.openRequestId);
                const second = await latePage.evaluate(() => window.BootstrapCharacterCreate.debugState());
                const snapshotCount = await latePage.evaluate(() => window.__ccHarness.snapshots().length);
                expect(first.openRequestId && second.openRequestId
                    && first.openRequestId !== second.openRequestId && snapshotCount === 2,
                'reopen did not allocate an independent openRequestId/snapshot pair');

                await latePage.evaluate(() => window.__ccHarness.deliverSnapshot(0));
                const staleDrain = await drainAnimationFrames(latePage);
                expect(staleDrain.flushed >= 2 && staleDrain.pending === 0,
                    'canceled request stale rAF chain was not retained/drained: '
                        + JSON.stringify(staleDrain));
                const afterOld = await preparationPresentation(latePage);
                expect(afterOld.state.phase === 'starting'
                    && afterOld.state.openRequestId === second.openRequestId
                    && !afterOld.state.attemptId && afterOld.nameValue === ''
                    && afterOld.bodyPreparing && afterOld.overlayOn && afterOld.viewInert
                    && afterOld.viewVisibility === 'hidden',
                'late snapshot or stale double-rAF released the new preparation token: '
                    + JSON.stringify(afterOld));

                await latePage.evaluate(() => window.__ccHarness.deliverSnapshot(1));
                await latePage.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    return state.phase === 'preparing' && state.attemptId === 'attempt-002'
                        && state.rendererIssue === '' && window.__ccRenderProbe;
                }, null, { timeout:30000 });
                const currentFrames = await latePage.evaluate(() =>
                    window.__ccManualFrames.pendingPresentation());
                expect(await latePage.evaluate(() => window.__ccRenderProbe.releaseFailure()),
                    'current request did not accept an explicit renderer failure');
                await latePage.waitForFunction(previous =>
                    window.__ccManualFrames.pendingPresentation() > previous,
                    currentFrames);
                const currentDrain = await drainAnimationFrames(latePage);
                expect(currentDrain.flushed >= 2 && currentDrain.pending === 0,
                    'current request reveal rAF chain did not drain: ' + JSON.stringify(currentDrain));
                await latePage.waitForFunction(() =>
                    window.BootstrapCharacterCreate.debugState().phase === 'editing');
                const accepted = await latePage.evaluate(() => window.BootstrapCharacterCreate.debugState());
                expect(accepted.openRequestId === second.openRequestId && accepted.attemptId === 'attempt-002'
                    && accepted.draft.characterName === ''
                    && await latePage.evaluate(() =>
                        document.activeElement === document.getElementById('cc-character-name')),
                'current snapshot did not own reveal/focus after stale callbacks were rejected');
                await latePage.locator('#cc-cancel').click();
                return 'cancel/reopen allocates a fresh token; old snapshot and both stale rAF callbacks cannot reveal the new request';
            } finally {
                await latePage.close();
            }
        });

        await check('production-renderer-real-defaults', async () => {
            const page = await setupPage(browser, url, { width: 1366, height: 768 }, true,
                template, evidence, { manifestFailure: false });
            try {
                await openCharacterCreate(page);
                await page.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    const meta = state.rendererMeta;
                    return state.rendererIssue === '' && meta && meta.holders > 0
                        && meta.drawnImages > 0 && meta.pendingImages === 0
                        && meta.failedImages === 0 && meta.missing === 0;
                }, null, { timeout: 30000 });
                const render = await page.evaluate(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    const canvas = document.getElementById('cc-preview-canvas');
                    const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
                    var visiblePixels = 0;
                    for (var i = 3; i < pixels.length; i += 4) if (pixels[i] > 0) visiblePixels++;
                    return {
                        meta: state.rendererMeta,
                        issue: state.rendererIssue,
                        visiblePixels,
                        fallbackHidden: document.getElementById('cc-preview-fallback').hidden
                    };
                });
                const screenshot = await page.locator('.cc-preview').screenshot();
                expect(render.meta.holders > 0 && render.meta.drawnImages > 0
                    && render.meta.pendingImages === 0 && render.meta.failedImages === 0
                    && render.meta.missing === 0,
                'real defaults did not satisfy the strict first-frame renderer gate: '
                    + JSON.stringify(render.meta));
                expect(render.visiblePixels > 500, 'real defaults produced an effectively blank preview');
                expect(render.fallbackHidden, 'successfully rendered defaults still show fallback text');
                await page.locator('input[name="cc-gender"][value="female"]').check({ force: true });
                await page.waitForFunction(() => {
                    const state = window.BootstrapCharacterCreate.debugState();
                    const meta = state.rendererMeta;
                    return state.draft.gender === 'female' && meta && meta.gender === '女'
                        && meta.holders > 0 && meta.drawnImages > 0 && meta.missing === 0
                        && meta.pendingImages === 0 && meta.failedImages === 0;
                }, null, { timeout: 30000 });
                expect(screenshot.length > 10000 && screenshot[0] === 137 && screenshot[1] === 80,
                    'preview screenshot gate did not produce a nontrivial PNG');
                await page.locator('#cc-cancel').click();
                await openCharacterCreate(page);
                await page.waitForFunction(() => {
                    const meta = window.BootstrapCharacterCreate.debugState().rendererMeta;
                    return meta && meta.holders > 0 && meta.drawnImages > 0
                        && meta.pendingImages === 0 && meta.failedImages === 0 && meta.missing === 0;
                }, null, { timeout: 10000 });
                return 'CharacterCreationService defaults rendered through production manifest; canvas pixels and PNG gate passed';
            } finally {
                await page.close();
            }
        });

        const page = await setupPage(browser, url, { width: 1366, height: 768 }, true, template, evidence);

        await check('slot-display-disambiguation', async () => {
            const cards = await page.locator('#cards .card').evaluateAll(nodes => nodes.slice(0, 3).map(node => ({
                title: node.querySelector('.slot').textContent,
                progress: node.querySelector('.progress').textContent,
                id: node.querySelector('.slot-id').textContent,
                meta: node.querySelector('.meta').textContent
            })));
            expect(cards[0].title === '阿七' && cards[1].title === '阿八',
                'characterName is not the primary save-card title');
            expect(cards[0].progress.includes('存档名 · 远征档')
                && cards[1].progress.includes('存档名 · 远征档'),
            'displayName is not presented as secondary card metadata');
            expect(cards[0].meta.includes('2026-08-29') && cards[1].meta.includes('2026-08-28'),
                'duplicate display names are not disambiguated by time');
            expect(cards[0].id.includes('槽位 · '), 'short slot key marker is missing');
            return 'characterName is primary; duplicate displayName remains secondary with time/short-slot disambiguators';
        });

        await check('new-open-and-cancel-zero-write', async () => {
            await page.locator('#btn-switch-slot').click();
            await page.evaluate(() => { window.prompt = () => { throw new Error('legacy prompt must not be called'); }; });
            await page.locator('#btn-new').click();
            await page.waitForFunction(() => window.BootstrapCharacterCreate.debugState().phase === 'editing');
            const open = (await page.evaluate(() => window.__ccHarness.outbound('character_create_open'))).at(-1);
            expect(open.mode === 'new' && /^cc-open-[a-z0-9-]+$/.test(open.openRequestId)
                && !Object.prototype.hasOwnProperty.call(open, 'slotKey'),
                'new open envelope is not exact');
            await page.locator('#cc-cancel').click();
            await page.waitForFunction(() => !document.getElementById('view-slots').hidden);
            const outbound = await page.evaluate(() => window.__ccHarness.outbound());
            expect(outbound.filter(message => message.cmd === 'cancel_launch').length === 1,
                'cancel must emit exactly one cancel_launch');
            expect(outbound.filter(message => message.cmd === 'character_create_submit').length === 0,
                'cancel wrote a character draft');
            return 'toolbar new bypasses prompt; cancel emits no character write';
        });

        await check('rebuild-card-open', async () => {
            await page.locator('#cards .card').nth(2).locator('.btn-rebuild').click();
            // 重建确认已从原生 confirm() 迁到终端风 confirm-dialog modal：等框弹出并点「重建」。
            await page.waitForFunction(() => {
                const host = document.getElementById('modal-host');
                return host && host.style.display !== 'none'
                    && document.getElementById('confirm-dialog-ok');
            });
            await page.locator('#confirm-dialog-ok').click();
            await page.waitForFunction(() => window.BootstrapCharacterCreate.debugState().phase === 'editing'
                && window.BootstrapCharacterCreate.debugState().expectedMode === 'rebuild');
            const open = (await page.evaluate(() => window.__ccHarness.outbound('character_create_open'))).at(-1);
            expect(open.mode === 'rebuild' && open.slotKey === 'legacy-rebuild-key-123456'
                && /^cc-open-[a-z0-9-]+$/.test(open.openRequestId),
                'rebuild open envelope is not exact');
            await page.locator('#cc-cancel').click();
            return 'confirmed rebuild opens the same flow with the authoritative slotKey';
        });

        await check('display-name-advanced-follow-override-reset', async () => {
            await openCharacterCreate(page);
            const advanced = page.locator('#cc-advanced');
            expect(!(await advanced.evaluate(node => node.open)), 'save display name advanced section opened by default');
            await page.locator('#cc-character-name').fill('主角甲');
            let names = await page.evaluate(() => ({
                state:window.BootstrapCharacterCreate.debugState(),
                display:document.getElementById('cc-display-name').value
            }));
            expect(names.display === '主角甲' && names.state.displayName === '主角甲'
                && names.state.displayNameCustomized === false,
            'default displayName did not follow characterName');
            await advanced.evaluate(node => { node.open = true; });
            await page.locator('#cc-display-name').fill('自定义档名');
            await page.locator('#cc-character-name').fill('主角乙');
            names = await page.evaluate(() => ({
                state:window.BootstrapCharacterCreate.debugState(),
                display:document.getElementById('cc-display-name').value
            }));
            expect(names.display === '自定义档名' && names.state.displayNameCustomized === true,
                'manual displayName override did not survive a characterName edit');
            await page.locator('#cc-display-reset').click();
            await page.locator('#cc-character-name').fill('主角丙');
            names = await page.evaluate(() => ({
                state:window.BootstrapCharacterCreate.debugState(),
                display:document.getElementById('cc-display-name').value
            }));
            expect(names.display === '主角丙' && names.state.displayName === '主角丙'
                && names.state.displayNameCustomized === false,
            'restore-follow did not rebind displayName to characterName');
            await page.locator('#cc-display-name').fill('');
            names = await page.evaluate(() => ({
                state:window.BootstrapCharacterCreate.debugState(),
                display:document.getElementById('cc-display-name').value
            }));
            expect(names.display === '主角丙' && names.state.displayNameCustomized === false,
                'clearing displayName did not restore the characterName default');
            await page.locator('#cc-next').click();
            await page.locator('#cc-next').click();
            const beforeSubmit = await page.evaluate(() =>
                window.__ccHarness.outbound('character_create_submit').length);
            await page.locator('#cc-next').click();
            await page.waitForFunction(count =>
                window.__ccHarness.outbound('character_create_submit').length === count + 1,
            beforeSubmit);
            const followSubmit = (await page.evaluate(() =>
                window.__ccHarness.outbound('character_create_submit'))).at(-1);
            const followState = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(followSubmit.openRequestId === followState.openRequestId
                && followSubmit.displayNameCustomized === false
                && !Object.prototype.hasOwnProperty.call(followSubmit, 'displayName'),
            'follow-mode display name was not explicit on the submit wire');
            await page.evaluate(state => window.__ccHarness.emit({
                cmd:'character_create_state', attemptId:state.attemptId, slotKey:state.slotKey,
                phase:'rejected', message:'harness follow-mode release'
            }), followState);
            await page.locator('#cc-cancel').click();
            return 'advanced displayName follows/overrides/resets; submit carries explicit false for catalog follow mode';
        });

        await check('appearance-slots-icon-pools-rich-tooltip-no-rpc', async () => {
            await openCharacterCreate(page);
            await page.locator('#cc-character-name').fill('外观验收');
            await page.locator('#cc-next').click();
            const beforeMessages = await page.evaluate(() => window.__ccHarness.outbound().length);
            const aliasRow = template.appearanceCatalog.lower.male[1];
            const beforeDraft = await page.evaluate(() =>
                JSON.stringify(window.BootstrapCharacterCreate.debugState().draft));
            await page.waitForFunction(expected => {
                const host = document.getElementById('cc-equipment-pool');
                return document.querySelectorAll('.cc-equipped-slot').length === 3
                    && host.querySelectorAll('[role="option"]').length === expected
                    && host.querySelectorAll('[data-icon-name], [data-icon-layered-name]').length === expected
                    && !host.querySelector('.cc-item-icon-fallback');
            }, template.appearanceCatalog.upper.male.length, { timeout:10000 });
            await page.locator('.cc-equipped-slot[data-index="1"]').click();
            await page.waitForFunction(expected =>
                document.querySelectorAll('#cc-equipment-pool [role="option"]').length === expected,
            template.appearanceCatalog.lower.male.length);
            await page.locator('#cc-equipment-pool [data-index="1"]').click();
            const aliasButton = page.locator('#cc-equipment-pool [data-index="1"]');
            await aliasButton.press('Tab');
            await aliasButton.focus();
            await page.waitForFunction(() => {
                const button = document.querySelector('#cc-equipment-pool [data-index="1"]');
                const tip = document.getElementById('panel-tooltip');
                return document.activeElement === button && window.PanelTooltip.isVisible()
                    && tip && tip.textContent.includes('咖啡色多包短裤');
            }, null, { timeout:3000 });
            const aliasEvidence = await page.evaluate(() => {
                const button = document.querySelector('#cc-equipment-pool [data-index="1"]');
                const icon = button.querySelector('[data-icon-name], [data-icon-layered-name]');
                const tip = document.getElementById('panel-tooltip');
                const state = window.PanelTooltip.debugState();
                const create = window.BootstrapCharacterCreate.debugState();
                return {
                    iconName:icon && (icon.getAttribute('data-icon-name')
                        || icon.getAttribute('data-icon-layered-name')),
                    describedBy:button.getAttribute('aria-describedby'),
                    rich:!!tip.querySelector('.flash-tt-rich'),
                    desc:!!tip.querySelector('.flash-tt-desc'),
                    text:tip.textContent,
                    keyboardOwner:state.keyboardOwnerActive,
                    activeEquipment:create.activeEquipment,
                    lower:create.draft.lowerIdentifier,
                    upper:create.draft.upperIdentifier,
                    footwear:create.draft.footwearIdentifier,
                    slots:document.querySelectorAll('.cc-equipped-slot').length,
                    poolSelected:document.querySelectorAll('#cc-equipment-pool [aria-selected="true"]').length,
                    poolTabbable:document.querySelectorAll('#cc-equipment-pool [tabindex="0"]').length,
                    legacySelects:document.querySelectorAll('#cc-upper, #cc-lower, #cc-footwear').length
                };
            });
            const descriptionNeedle = aliasRow.descHTML.replace(/<[^>]+>/g, ' ')
                .replace(/\s+/g, '').slice(0, 12);
            expect(aliasRow.identifier === '咖啡色多包短裤'
                && aliasRow.iconName === '咖啡色多包裤'
                && aliasEvidence.iconName === aliasRow.iconName,
            'real XML icon alias was replaced by the item identifier');
            const parsedBeforeDraft = JSON.parse(beforeDraft);
            expect(aliasEvidence.activeEquipment === 1 && aliasEvidence.lower === aliasRow.identifier
                && aliasEvidence.upper === parsedBeforeDraft.upperIdentifier
                && aliasEvidence.footwear === parsedBeforeDraft.footwearIdentifier
                && aliasEvidence.slots === 3 && aliasEvidence.poolSelected === 1
                && aliasEvidence.poolTabbable === 1 && aliasEvidence.legacySelects === 0,
            'slot-first equipment selection changed the wrong field or revived native selectors: '
                + JSON.stringify(aliasEvidence));
            expect(aliasEvidence.describedBy === 'panel-tooltip' && aliasEvidence.keyboardOwner
                && aliasEvidence.rich
                && aliasEvidence.text.replace(/\s+/g, '').includes(descriptionNeedle),
            'keyboard focus did not expose the canonical rich item annotation: '
                + JSON.stringify({ aliasEvidence, descriptionNeedle }));
            await aliasButton.press('Escape');
            await page.waitForFunction(() => !window.PanelTooltip.isVisible());
            const afterTooltipEscape = await page.evaluate(() => ({
                state:window.BootstrapCharacterCreate.debugState(),
                createVisible:!document.getElementById('view-character-create').hidden
            }));
            expect(afterTooltipEscape.createVisible && afterTooltipEscape.state.phase === 'editing'
                && afterTooltipEscape.state.step === 1,
            'Escape closed or navigated the character-create page before dismissing the item annotation');
            await aliasButton.hover();
            await page.waitForTimeout(180);
            await page.locator('#cc-appearance-tab-hair').click();
            const hairBefore = await page.evaluate(() => window.BootstrapCharacterCreate.debugState().draft.hairIdentifier);
            await page.locator('#cc-hair-32').click();
            const hairEvidence = await page.evaluate(() => ({
                view:window.BootstrapCharacterCreate.debugState().appearanceView,
                hair:window.BootstrapCharacterCreate.debugState().draft.hairIdentifier,
                count:document.querySelectorAll('#cc-hair-list .cc-hair-option').length,
                icons:document.querySelectorAll('#cc-hair-list .cc-hair-option .cc-hair-icon').length,
                selected:document.querySelectorAll('#cc-hair-list [aria-selected="true"]').length,
                tabbable:document.querySelectorAll('#cc-hair-list [tabindex="0"]').length,
                slotText:document.getElementById('cc-hair-slot').textContent,
                slotAria:document.getElementById('cc-hair-slot').getAttribute('aria-label') || ''
            }));
            const hairVisibleName = hairCatalog[32].name
                .replace(/^发型[-－_\s]*(男式|女式)[-－_\s]*/, '');
            expect(hairEvidence.view === 'hair' && hairEvidence.hair !== hairBefore
                && hairEvidence.hair === hairCatalog[32].identifier
                && hairEvidence.count === 77 && hairEvidence.icons === 77
                && hairEvidence.selected === 1 && hairEvidence.tabbable === 1
                && hairEvidence.slotText.includes(hairVisibleName)
                && !hairEvidence.slotText.includes('发型-男式-')
                && hairEvidence.slotAria.includes(hairCatalog[32].name),
            'single hair slot + 77-icon pool did not preserve source order/selection: '
                + JSON.stringify(hairEvidence));
            const afterMessages = await page.evaluate(() => window.__ccHarness.outbound().length);
            expect(afterMessages === beforeMessages,
                'appearance focus/hover emitted a Host RPC instead of using the snapshot: '
                + beforeMessages + ' -> ' + afterMessages);
            await page.locator('#cc-cancel').click();
            return '3 equipment slots + one icon pool and 1 hair slot + 77 icons; rich annotation is Esc-first and zero-RPC';
        });

        await check('appearance-density-persistence-focus-and-draft-invariance', async () => {
            await openCharacterCreate(page);
            await page.locator('#cc-character-name').fill('密度验收');
            await page.locator('#cc-next').click();
            const before = await page.evaluate(() => {
                const selected = document.querySelector('#cc-equipment-pool [aria-selected="true"]');
                selected.focus();
                return {
                    messages:window.__ccHarness.outbound().length,
                    draft:JSON.stringify(window.BootstrapCharacterCreate.debugState().draft),
                    order:Array.from(document.querySelectorAll('#cc-equipment-pool [data-choice-key]'))
                        .map(node => node.getAttribute('data-choice-key')),
                    selected:selected.getAttribute('data-choice-key'),
                    active:document.activeElement.getAttribute('data-choice-key'),
                    density:window.BootstrapCharacterCreate.debugState().appearanceDensity,
                    stored:localStorage.getItem('cf7.itemgrid.mode.character-create-appearance')
                };
            });
            expect(before.density.equipment === 'full' && before.density.hair === 'compact'
                && before.stored === null
                && before.selected === before.active,
            'appearance did not default to per-view full/compact with grid focus established: ' + JSON.stringify(before));
            await page.locator('[data-density="compact"]').click();
            const compact = await page.evaluate(() => ({
                messages:window.__ccHarness.outbound().length,
                draft:JSON.stringify(window.BootstrapCharacterCreate.debugState().draft),
                order:Array.from(document.querySelectorAll('#cc-equipment-pool [data-choice-key]'))
                    .map(node => node.getAttribute('data-choice-key')),
                selected:document.querySelector('#cc-equipment-pool [aria-selected="true"]').getAttribute('data-choice-key'),
                roving:document.querySelector('#cc-equipment-pool [tabindex="0"]').getAttribute('data-choice-key'),
                activeDensity:document.activeElement.getAttribute('data-density'),
                density:window.BootstrapCharacterCreate.debugState().appearanceDensity,
                stored:localStorage.getItem('cf7.itemgrid.mode.character-create-appearance'),
                compact:document.getElementById('cc-equipment-pool').classList.contains('item-grid-compact')
            }));
            expect(compact.density.equipment === 'compact' && compact.density.hair === 'compact'
                && JSON.parse(compact.stored).equipment === 'compact'
                && JSON.parse(compact.stored).hair === 'compact' && compact.compact
                && compact.messages === before.messages && compact.draft === before.draft
                && JSON.stringify(compact.order) === JSON.stringify(before.order)
                && compact.selected === before.selected && compact.roving === before.selected
                && compact.activeDensity === 'compact',
            'full → compact changed RPC/draft/order/selection/roving target or pointer focus: '
                + JSON.stringify({before, compact}));
            await page.locator('[data-density="full"]').click();
            const full = await page.evaluate(() => ({
                messages:window.__ccHarness.outbound().length,
                draft:JSON.stringify(window.BootstrapCharacterCreate.debugState().draft),
                order:Array.from(document.querySelectorAll('#cc-equipment-pool [data-choice-key]'))
                    .map(node => node.getAttribute('data-choice-key')),
                selected:document.querySelector('#cc-equipment-pool [aria-selected="true"]').getAttribute('data-choice-key'),
                roving:document.querySelector('#cc-equipment-pool [tabindex="0"]').getAttribute('data-choice-key'),
                activeDensity:document.activeElement.getAttribute('data-density'),
                density:window.BootstrapCharacterCreate.debugState().appearanceDensity,
                stored:localStorage.getItem('cf7.itemgrid.mode.character-create-appearance'),
                compact:document.getElementById('cc-equipment-pool').classList.contains('item-grid-compact')
            }));
            expect(full.density.equipment === 'full' && full.density.hair === 'compact'
                && JSON.parse(full.stored).equipment === 'full'
                && JSON.parse(full.stored).hair === 'compact' && !full.compact
                && full.messages === before.messages && full.draft === before.draft
                && JSON.stringify(full.order) === JSON.stringify(before.order)
                && full.selected === before.selected && full.roving === before.selected
                && full.activeDensity === 'full',
            'compact → full changed RPC/draft/order/selection/roving target or pointer focus: '
                + JSON.stringify({before, full}));
            await page.locator('#cc-cancel').click();
            await openCharacterCreate(page);
            const restored = await page.evaluate(() => window.BootstrapCharacterCreate.debugState().appearanceDensity);
            expect(restored.equipment === 'full' && restored.hair === 'compact',
                'persisted per-view density preference was not restored on reopen: ' + JSON.stringify(restored));
            await page.locator('#cc-cancel').click();
            return 'per-view full/compact defaults and persistence; real pointer switches preserve RPC/draft/order/selection/roving target and keep focus on the density control';
        });

        await check('catalog-defaults-ime-aria', async () => {
            const initial = await openCharacterCreate(page);
            expect(initial.displayName === '' && initial.draft.characterName === '' && initial.draft.gender === 'male',
                'initial names/gender are not deterministic');
            expect(initial.draft.height === template.defaults.male.height
                && initial.draft.faceIdentifier === template.defaults.male.faceIdentifier
                && initial.draft.hairIdentifier === template.defaults.male.hairIdentifier,
                'male defaults do not match Host snapshot');
            expect(JSON.stringify(initial.hairCatalog) === JSON.stringify(hairCatalog.map(row => row.identifier)),
                'hair catalog order changed between hairstyle.xml and production DOM runtime');
            expect(initial.hairCatalog[20] === initial.hairCatalog[32], 'duplicate hairstyle was removed');
            await page.locator('#cc-display-name').fill('不可被快照覆盖');
            await page.evaluate(() => window.__ccHarness.emit(window.__ccHarness.activeSnapshot()));
            const afterReplay = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(afterReplay.displayName === '不可被快照覆盖' && afterReplay.phase === 'editing',
                'duplicate snapshot reset an active draft');

            const aria = await page.evaluate(() => ({
                listRole: document.getElementById('cc-hair-list').getAttribute('role'),
                active: document.getElementById('cc-hair-list').getAttribute('aria-activedescendant'),
                selected: document.querySelectorAll('#cc-hair-list [aria-selected="true"]').length,
                tabbable: document.querySelectorAll('#cc-hair-list [tabindex="0"]').length,
                currentSteps: document.querySelectorAll('.cc-steps [aria-current="step"]').length,
                canvasRole: document.getElementById('cc-preview-canvas').getAttribute('role'),
                displayHelp: document.getElementById('cc-display-name').getAttribute('aria-describedby'),
                faceControls: document.querySelectorAll('[id*="face"], [name*="face"]').length,
                visibleFaceCopy:Array.from(document.querySelectorAll('#character-create-root *')).some(node =>
                    node.children.length === 0 && node.getClientRects().length > 0
                    && node.textContent.trim() === '脸型'),
                heightControls:document.querySelectorAll('#view-character-create input[type="range"]').length,
                heightInPreview:document.querySelector('.cc-preview #cc-preview-height-control') !== null,
                heightHidden:document.getElementById('cc-preview-height-control').hidden,
                heightDisabled:document.getElementById('cc-height').disabled,
                density:window.BootstrapCharacterCreate.debugState().appearanceDensity
            }));
            expect(aria.listRole === 'listbox' && aria.selected === 1 && aria.tabbable === 1 && !aria.active,
                'hair listbox roving/selection ARIA is invalid: ' + JSON.stringify(aria));
            expect(aria.currentSteps === 1 && aria.canvasRole === 'img' && aria.displayHelp.includes('cc-display-help'),
                'step/canvas/input ARIA is incomplete');
            expect(aria.faceControls === 0 && !aria.visibleFaceCopy,
                'fixed protocol face leaked into a visible/control field: ' + JSON.stringify(aria));
            expect(aria.heightControls === 1 && aria.heightInPreview
                && aria.heightHidden && aria.heightDisabled
                && aria.density.equipment === 'full' && aria.density.hair === 'compact',
            'step-0 height/density placement contract drifted: ' + JSON.stringify(aria));

            await page.locator('input[name="cc-gender"][value="female"]').check({ force: true });
            let changed = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(changed.draft.height === template.defaults.female.height
                && changed.draft.faceIdentifier === template.defaults.female.faceIdentifier,
                'female defaults are not deterministic');
            await page.locator('input[name="cc-gender"][value="male"]').check({ force: true });
            changed = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(changed.draft.height === template.defaults.male.height
                && changed.hairIndex === hairCatalog.findIndex(row => row.identifier === template.defaults.male.hairIdentifier),
                'switching back to male did not restore the authority default source match');

            const ime = await page.evaluate(() => {
                const input = document.getElementById('cc-display-name');
                input.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true, data: '远' }));
                input.value = '输入中';
                input.dispatchEvent(new InputEvent('input', {
                    bubbles: true, data: '中', inputType: 'insertCompositionText', isComposing: true
                }));
                input.dispatchEvent(new KeyboardEvent('keydown', {
                    bubbles: true, cancelable: true, key: 'Enter', code: 'Enter',
                    keyCode: 229, which: 229, isComposing: true
                }));
                const during = window.BootstrapCharacterCreate.debugState();
                input.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '输入中' }));
                return during;
            });
            expect(ime.step === 0 && ime.displayName === '输入中', 'IME Enter advanced or lost composed text');
            const graphemes = await page.evaluate(() => {
                const runtime = window.BootstrapCharacterCreateRuntime;
                const normalized = runtime.normalizeSnapshot(window.__ccHarness.activeSnapshot());
                const testModel = runtime.initialDraft(normalized);
                testModel.draft.characterName = '角';
                testModel.displayNameCustomized = true;
                testModel.displayName = 'é'.repeat(31) + '👩‍🚀';
                const valid32 = runtime.validateSubmission(normalized, testModel).valid;
                testModel.displayName += '界';
                return { valid32, valid33: runtime.validateSubmission(normalized, testModel).valid };
            });
            expect(graphemes.valid32 && !graphemes.valid33,
                'Intl.Segmenter path did not enforce 32 visible text elements');
            await page.locator('#cc-character-name').fill('身高焦点验收');
            await page.locator('#cc-next').click();
            const heightFocus = await page.evaluate(() => ({
                step:window.BootstrapCharacterCreate.debugState().step,
                activeId:document.activeElement && document.activeElement.id,
                labelledBy:document.getElementById('cc-height').getAttribute('aria-labelledby'),
                describedBy:document.getElementById('cc-height').getAttribute('aria-describedby'),
                hidden:document.getElementById('cc-preview-height-control').hidden,
                disabled:document.getElementById('cc-height').disabled
            }));
            expect(heightFocus.step === 1 && heightFocus.activeId === 'cc-height'
                && heightFocus.labelledBy === 'cc-step-title-1 cc-height-label'
                && heightFocus.describedBy === 'cc-height-value'
                && !heightFocus.hidden && !heightFocus.disabled,
            'step-1 did not enter the left height control with complete naming: '
                + JSON.stringify(heightFocus));
            await page.keyboard.press('End');
            await page.keyboard.press('Home');
            await page.keyboard.press('ArrowRight');
            const heightKeyboard = await page.evaluate(() => ({
                value:document.getElementById('cc-height').value,
                valueText:document.getElementById('cc-height').getAttribute('aria-valuetext'),
                output:document.getElementById('cc-height-value').textContent,
                draft:window.BootstrapCharacterCreate.debugState().draft.height
            }));
            expect(heightKeyboard.value === '151' && heightKeyboard.valueText === '151 厘米'
                && heightKeyboard.output === '151 cm' && heightKeyboard.draft === 151,
            'height Home/End/Arrow input did not update value, ARIA, output, and draft: '
                + JSON.stringify(heightKeyboard));
            await page.keyboard.press('Tab');
            expect(await page.evaluate(() => document.activeElement.id) === 'cc-appearance-tab-equipment',
                'forward Tab from height did not continue into the appearance workbench');
            await page.locator('#cc-cancel').click();
            return '77 source rows/duplicate/defaults/IME/ARIA preserved; face stays protocol-only; height owns step-1 focus and keyboard updates';
        });

        await check('difficulty-shared-tooltip-focus-hover-escape-no-rpc', async () => {
            await openCharacterCreate(page);
            await fillDefaultDraft(page, '难度说明档', '难度验收');
            const beforeMessages = await page.evaluate(() => window.__ccHarness.outbound().length);
            const selectedIndex = template.difficulties.findIndex(row =>
                row.identifier === template.defaults.male.difficulty);
            const selected = page.locator('#cc-difficulties [data-index="' + selectedIndex + '"]');
            // focusStep reached the default radio from a pointer click. Move focus once
            // through the keyboard path so PanelTooltip's modality gate is exercised.
            await selected.press('Tab');
            await selected.focus();
            await page.waitForFunction(description => {
                const tip = document.getElementById('panel-tooltip');
                return window.PanelTooltip.isVisible() && document.activeElement.getAttribute('role') === 'radio'
                    && tip.textContent.replace(/\s+/g, '') === description.replace(/\s+/g, '');
            }, template.difficulties[selectedIndex].description, { timeout:3000 });
            const focused = await page.evaluate(() => {
                const button = document.activeElement;
                const state = window.PanelTooltip.debugState();
                return {
                    describedBy:button.getAttribute('aria-describedby'),
                    keyboardOwner:state.keyboardOwnerActive,
                    step:window.BootstrapCharacterCreate.debugState().step
                };
            });
            expect(focused.describedBy === 'panel-tooltip' && focused.keyboardOwner && focused.step === 2,
                'difficulty focus did not use the shared keyboard tooltip: ' + JSON.stringify(focused));
            await selected.press('Escape');
            await page.waitForFunction(() => !window.PanelTooltip.isVisible());
            const afterEscape = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(afterEscape.phase === 'editing' && afterEscape.step === 2,
                'difficulty Escape navigated before dismissing PanelTooltip');
            const hoverIndex = (selectedIndex + 1) % template.difficulties.length;
            await page.locator('#cc-difficulties [data-index="' + hoverIndex + '"]').hover();
            await page.waitForFunction(description => {
                const tip = document.getElementById('panel-tooltip');
                return window.PanelTooltip.isVisible()
                    && tip.textContent.replace(/\s+/g, '') === description.replace(/\s+/g, '');
            }, template.difficulties[hoverIndex].description, { timeout:3000 });
            const afterMessages = await page.evaluate(() => window.__ccHarness.outbound().length);
            expect(afterMessages === beforeMessages,
                'difficulty focus/hover emitted a Host RPC: ' + beforeMessages + ' -> ' + afterMessages);
            await page.evaluate(() => window.PanelTooltip.hide());
            await page.locator('#cc-cancel').click();
            return 'difficulty details use shared PanelTooltip with full focus/hover copy, Esc-first dismissal, and zero RPC';
        });

        await check('player-copy-hides-raw-hair-and-development-terms', async () => {
            const copyTemplate = JSON.parse(JSON.stringify(template));
            const rawHairIdentifier = 'hair.internal.catalog.001';
            copyTemplate.hairCatalog[1] = {
                identifier:rawHairIdentifier,
                name:'蓝色头巾',
                sourceIndex:copyTemplate.hairCatalog[1].sourceIndex
            };
            const copyPage = await setupPage(browser, url, { width:1366, height:768 }, true,
                copyTemplate, evidence);
            try {
                await openCharacterCreate(copyPage);
                await copyPage.locator('#cc-character-name').fill('文案验收');
                await copyPage.locator('#cc-next').click();
                await copyPage.locator('#cc-appearance-tab-hair').click();
                await copyPage.locator('#cc-hair-1').click();
                const appearanceCopy = await copyPage.evaluate(() => {
                    const root = document.getElementById('character-create-root');
                    const attributes = [];
                    root.querySelectorAll('*').forEach(node => {
                        if (!node.getClientRects().length) return;
                        ['aria-label','aria-description','title','placeholder','alt'].forEach(name => {
                            if (node.hasAttribute(name)) attributes.push(node.getAttribute(name));
                        });
                    });
                    return {
                        text:root.innerText,
                        attributes:attributes.join('\n'),
                        slot:document.getElementById('cc-hair-slot').textContent,
                        draft:window.BootstrapCharacterCreate.debugState().draft.hairIdentifier
                    };
                });
                const playerCopy = appearanceCopy.text + '\n' + appearanceCopy.attributes;
                const banned = /Flash|本地权威|不在\s*Web\s*复制|预览组件|草稿|提交/i;
                expect(appearanceCopy.draft === rawHairIdentifier
                    && appearanceCopy.slot.includes('蓝色头巾')
                    && !playerCopy.includes(rawHairIdentifier),
                'raw hair identifier leaked into player-visible text/accessible labels: '
                    + JSON.stringify(appearanceCopy));
                expect(!banned.test(playerCopy),
                    'development-only wording leaked into normal player appearance UI: '
                        + String(playerCopy.match(banned)));
                await copyPage.locator('#cc-next').click();
                const confirmCopy = await copyPage.locator('#character-create-root').innerText();
                expect(!banned.test(confirmCopy),
                    'development-only wording leaked into normal confirmation UI: '
                        + String(confirmCopy.match(banned)));
                await copyPage.locator('#cc-cancel').click();
                return 'protocol-only hair identifiers stay in draft while normal appearance/confirmation copy omits development terms';
            } finally {
                await copyPage.close();
            }
        });

        await check('exact-draft-double-submit-and-state-isolation', async () => {
            const femaleCatalog = template.appearanceCatalog;
            const selectedUpper = femaleCatalog.upper.female.at(-1).identifier;
            const selectedLower = femaleCatalog.lower.female.at(-1).identifier;
            const selectedFootwear = femaleCatalog.footwear.female.at(-1).identifier;
            const selectedDifficulty = template.difficulties[2].identifier;
            await openCharacterCreate(page);
            await page.locator('input[name="cc-gender"][value="female"]').check({ force: true });
            await page.locator('#cc-display-name').fill('远征档🚀');
            await page.locator('#cc-character-name').fill('阿九');
            await page.locator('#cc-next').click();
            await page.locator('.cc-equipped-slot[data-index="0"]').click();
            await page.locator('#cc-equipment-pool [data-index="'
                + (femaleCatalog.upper.female.length - 1) + '"]').click();
            await page.locator('.cc-equipped-slot[data-index="1"]').click();
            await page.locator('#cc-equipment-pool [data-index="'
                + (femaleCatalog.lower.female.length - 1) + '"]').click();
            await page.locator('.cc-equipped-slot[data-index="2"]').click();
            await page.locator('#cc-equipment-pool [data-index="'
                + (femaleCatalog.footwear.female.length - 1) + '"]').click();
            await page.locator('#cc-height').fill('199');
            await page.locator('#cc-appearance-tab-hair').click();
            await page.locator('#cc-hair-32').click();
            await page.locator('#cc-next').click();
            await page.locator('#cc-difficulties [data-index="2"]').click();
            const expectedDraft = {
                characterName: '阿九', gender: 'female', height: 199,
                faceIdentifier: template.defaults.female.faceIdentifier, hairIdentifier: '发型-男式-平头',
                upperIdentifier: selectedUpper, lowerIdentifier: selectedLower,
                footwearIdentifier: selectedFootwear, difficulty: selectedDifficulty
            };
            const before = await page.evaluate(() => window.__ccHarness.outbound('character_create_submit').length);
            await page.locator('#cc-next').evaluate(button => { button.click(); button.click(); });
            await page.waitForFunction(count => window.__ccHarness.outbound('character_create_submit').length === count + 1,
                before);
            const submit = (await page.evaluate(() => window.__ccHarness.outbound('character_create_submit'))).at(-1);
            const identity = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(submit.openRequestId === identity.openRequestId
                && submit.displayName === '远征档🚀'
                && submit.displayNameCustomized === true,
            'custom displayName/openRequestId contract changed in submit');
            expect(JSON.stringify(Object.keys(submit.draft)) === JSON.stringify([
                'characterName', 'gender', 'height', 'faceIdentifier', 'hairIdentifier',
                'upperIdentifier', 'lowerIdentifier', 'footwearIdentifier', 'difficulty'
            ]), 'draft key set/order is not frozen');
            expect(JSON.stringify(submit.draft) === JSON.stringify(expectedDraft), 'submitted draft is incomplete or changed');
            expect(!('upperBody' in submit.draft) && !('lowerBody' in submit.draft) && !('shoes' in submit.draft),
                'legacy appearance aliases leaked into submit');

            await page.evaluate(() => window.__ccHarness.emit(window.__ccHarness.activeSnapshot()));
            const afterLateSnapshot = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(afterLateSnapshot.phase === 'submitting'
                && afterLateSnapshot.draft.characterName === '阿九'
                && afterLateSnapshot.draft.height === 199,
                'late snapshot reset a submitted draft');
            await page.evaluate(state => window.__ccHarness.emit({
                cmd: 'character_create_state', attemptId: 'foreign-attempt', slotKey: state.slotKey,
                phase: 'rejected', message: 'foreign'
            }), identity);
            expect((await page.evaluate(() => window.BootstrapCharacterCreate.debugState())).phase === 'submitting',
                'foreign attempt state was accepted');
            await page.evaluate(state => window.__ccHarness.emit({
                cmd: 'character_create_state', attemptId: state.attemptId, slotKey: 'foreign-slot',
                phase: 'rejected', message: 'foreign slot'
            }), identity);
            expect((await page.evaluate(() => window.BootstrapCharacterCreate.debugState())).phase === 'submitting',
                'foreign slot state was accepted');

            await page.evaluate(state => window.__ccHarness.emit({
                cmd: 'character_create_state', attemptId: state.attemptId, slotKey: state.slotKey,
                phase: 'rejected', message: '名称需调整'
            }), identity);
            const rejected = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(rejected.phase === 'rejected' && rejected.retryOnly,
                'matching pre-durable rejection did not enter exact-retry mode');
            expect(await page.locator('#cc-display-name').isDisabled(), 'delivered rejection left displayName editable');
            expect(await page.locator('#cc-character-name').isDisabled(), 'delivered rejection left characterName editable');
            expect(await page.locator('#character-create-root input:not(:disabled), .cc-equipped-slot:not(:disabled), .cc-choice-card:not(:disabled), .cc-appearance-tab:not(:disabled), .cc-density-option:not(:disabled), .cc-difficulty:not(:disabled)').count() === 0,
                'delivered rejection left an appearance or difficulty control editable');
            expect(await page.locator('#cc-back').isDisabled(), 'delivered rejection allowed step navigation');
            expect(!(await page.locator('#cc-cancel').isDisabled()), 'delivered rejection disabled cancel');
            expect(!(await page.locator('#cc-next').isDisabled())
                && await page.locator('#cc-next').textContent() === '重试保存',
                'delivered rejection did not expose exact retry action');
            await page.evaluate(() => {
                const input = document.getElementById('cc-display-name');
                input.value = '恶意改稿';
                input.dispatchEvent(new InputEvent('input', { bubbles:true, data:'稿', inputType:'insertText' }));
            });
            expect((await page.evaluate(() => window.BootstrapCharacterCreate.debugState())).displayName === '远征档🚀',
                'disabled rejected draft accepted a scripted edit');
            await page.locator('#cc-next').evaluate(button => { button.click(); button.click(); });
            await page.waitForFunction(count => window.__ccHarness.outbound('character_create_submit').length === count + 1,
                before + 1);
            const submissions = await page.evaluate(() => window.__ccHarness.outbound('character_create_submit'));
            expect(JSON.stringify(submissions.at(-1)) === JSON.stringify(submissions.at(-2)),
                'AS2 idempotent retry payload changed after pre-durable rejection');
            const retried = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            await page.evaluate(state => window.__ccHarness.emit({
                cmd: 'character_create_state', attemptId: state.attemptId, slotKey: state.slotKey,
                phase: 'unknown', message: '结果未知'
            }), retried);
            const unknownCount = await page.evaluate(() => window.__ccHarness.outbound('character_create_submit').length);
            await page.locator('#cc-next').evaluate(button => button.click());
            await page.evaluate(state => window.__ccHarness.emit({
                cmd: 'character_create_state', attemptId: state.attemptId, slotKey: state.slotKey,
                phase: 'rejected', message: '迟到拒绝'
            }), retried);
            const unknown = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(unknown.phase === 'unknown' && unknown.submitSent,
                'unknown was not latched against replay/rejection');
            expect(await page.evaluate(() => window.__ccHarness.outbound('character_create_submit').length) === unknownCount,
                'unknown state replayed submit');

            await openCharacterCreate(page);
            await fillDefaultDraft(page, '取消重试档', '取消甲');
            const cancelIdentity = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            await page.locator('#cc-next').click();
            await page.evaluate(state => window.__ccHarness.emit({
                cmd:'character_create_state', attemptId:state.attemptId, slotKey:state.slotKey,
                phase:'rejected', message:'flush failed'
            }), cancelIdentity);
            const cancelBefore = await page.evaluate(() => window.__ccHarness.outbound('cancel_launch').length);
            await page.locator('#cc-cancel').click();
            expect(await page.evaluate(() => window.__ccHarness.outbound('cancel_launch').length) === cancelBefore + 1,
                'exact-retry rejection did not allow cancel');

            await openCharacterCreate(page);
            await fillDefaultDraft(page, '本地投递失败档', '投递甲');
            await page.evaluate(() => window.__ccHarness.failNext('character_create_submit'));
            await page.locator('#cc-next').click();
            const localFailure = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(localFailure.phase === 'rejected' && !localFailure.retryOnly,
                'local emit failure incorrectly entered immutable retry mode');
            expect(!(await page.locator('#cc-display-name').isDisabled()) && !(await page.locator('#cc-back').isDisabled()),
                'local emit failure did not restore editable draft');
            return 'exact draft; delivered rejection exact-retry/cancel; local emit failure editable; foreign/unknown isolation verified';
        });

        await check('durable-scene-monotonicity', async () => {
            await openCharacterCreate(page);
            await fillDefaultDraft(page, '持久化失败场景', '场景甲');
            await page.locator('#cc-next').click();
            let state = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            await page.evaluate(value => window.__ccHarness.emit({
                cmd: 'character_create_state', attemptId: value.attemptId, slotKey: value.slotKey, phase: 'durable'
            }), state);
            await page.evaluate(value => window.__ccHarness.emit({
                cmd: 'character_create_state', attemptId: value.attemptId, slotKey: value.slotKey,
                phase: 'rejected', message: '迟到拒绝'
            }), state);
            expect((await page.evaluate(() => window.BootstrapCharacterCreate.debugState())).phase === 'durable',
                'durable regressed after a late rejection');
            await page.evaluate(value => window.__ccHarness.emit({
                cmd: 'character_create_state', attemptId: value.attemptId, slotKey: value.slotKey,
                phase: 'durable_scene_error', message: '场景超时'
            }), state);
            const failed = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(failed.phase === 'durable_scene_error' && failed.durable, 'scene error lost durable fact');
            await page.evaluate(value => window.__ccHarness.emit({
                cmd: 'character_create_state', attemptId: value.attemptId, slotKey: value.slotKey,
                phase: 'scene_ready', message: '迟到场景完成'
            }), state);
            expect((await page.evaluate(() => window.BootstrapCharacterCreate.debugState())).phase === 'durable_scene_error',
                'terminal durable scene error was overwritten by a late receipt');
            const writes = await page.evaluate(() => window.__ccHarness.outbound('character_create_submit').length);
            const retries = await page.evaluate(() => window.__ccHarness.outbound('retry').length);
            const cancels = await page.evaluate(() => window.__ccHarness.outbound('cancel_launch').length);
            const recoveryCopy = await page.evaluate(() => ({
                next:document.getElementById('cc-next').textContent,
                cancel:document.getElementById('cc-cancel').textContent
            }));
            expect(recoveryCopy.next.includes('载入已创建存档') && recoveryCopy.cancel.includes('返回存档列表'),
                'durable scene failure did not expose explicit non-recreate recovery actions');
            await page.locator('#cc-next').evaluate(button => { button.click(); button.click(); });
            expect(await page.evaluate(() => window.__ccHarness.outbound('character_create_submit').length) === writes,
                'durable scene error recreated a character');
            expect(await page.evaluate(() => window.__ccHarness.outbound('retry').length) === retries + 1,
                'durable scene recovery did not emit exactly one existing-slot retry');
            expect(await page.evaluate(() => window.__ccHarness.outbound('cancel_launch').length) === cancels,
                'load-existing recovery unexpectedly canceled the attempt');
            const recovering = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(recovering.phase === 'durable_scene_error' && recovering.recoverySent
                && await page.locator('#cc-next').isDisabled(),
            'durable recovery did not latch against repeated activation');
            await page.evaluate(() => window.__ccHarness.emit({
                cmd:'state', state:'Error', msg:'harness retry remained in Bootstrap'
            }));
            await page.locator('#cc-cancel').click();
            expect(await page.evaluate(() => window.__ccHarness.outbound('cancel_launch').length) === cancels + 1,
                'return-to-slots recovery did not cancel the failed launch exactly once');
            await page.waitForFunction(() => !document.getElementById('view-slots').hidden);

            await openCharacterCreate(page);
            await fillDefaultDraft(page, '持久化成功场景', '场景乙');
            await page.locator('#cc-next').click();
            state = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            await page.evaluate(value => {
                window.__ccHarness.emit({
                    cmd: 'character_create_state', attemptId: value.attemptId, slotKey: value.slotKey, phase: 'durable'
                });
                window.__ccHarness.emit({
                    cmd: 'character_create_state', attemptId: value.attemptId, slotKey: value.slotKey, phase: 'scene_ready'
                });
            }, state);
            const ready = await page.evaluate(() => window.BootstrapCharacterCreate.debugState());
            expect(ready.phase === 'scene_ready' && ready.durable, 'durable → scene_ready did not complete monotonically');
            await page.evaluate(value => window.__ccHarness.emit({
                cmd: 'character_create_state', attemptId: value.attemptId, slotKey: value.slotKey,
                phase: 'durable_scene_error', message: '迟到错误'
            }), state);
            expect((await page.evaluate(() => window.BootstrapCharacterCreate.debugState())).phase === 'scene_ready',
                'terminal scene_ready regressed after a late error');
            return 'durable never recreates; scene failure exposes one-shot load-existing/return recovery; terminal outcomes stay monotonic';
        });

        await check('renderer-fallback-nonblocking', async () => {
            await openCharacterCreate(page);
            await page.waitForFunction(() => {
                const fallback = document.getElementById('cc-preview-fallback');
                return fallback && !fallback.hidden && fallback.textContent.includes('角色预览暂时不可用');
            }, null, { timeout: 10000 });
            expect(!(await page.locator('#cc-display-name').isDisabled()), 'renderer failure blocked the form');
            expect(await page.locator('#cc-preview-canvas').getAttribute('role') === 'img', 'fallback lost preview semantics');
            return 'manifest failure becomes visible degraded-preview text and does not block character creation';
        });

        await page.close();
    } finally {
        if (browser) await browser.close();
        await closeServer(server);
    }

    process.stdout.write(JSON.stringify(evidence, null, 2) + '\n');
    if (evidence.checks.some(check => !check.passed) || evidence.pageErrors.length || evidence.failedRequests.length) {
        process.exitCode = 1;
    }
}

run().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
