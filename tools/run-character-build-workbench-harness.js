#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const HARNESS = 'modules/character-build/dev/workbench-harness.html';
const shotArg = process.argv.find(argument => argument.startsWith('--shot-dir='));

function writeShots(shots, viewport) {
    if (!shotArg) return 0;
    const directory = path.resolve(shotArg.slice('--shot-dir='.length));
    fs.mkdirSync(directory, {recursive:true});
    let written = 0;
    Object.keys(shots || {}).forEach(name => {
        const match = /^data:image\/png;base64,(.+)$/.exec(shots[name]);
        if (!match) throw new Error('invalid Canvas screenshot payload: ' + name);
        fs.writeFileSync(path.join(directory,
            viewport.width + 'x' + viewport.height + '-' + name + '.png'),
        Buffer.from(match[1], 'base64'));
        written++;
    });
    return written;
}

function edgeExecutable() {
    return [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)',
            'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files',
            'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].find(fs.existsSync);
}

function createServer() {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(WEB, pathname));
            const relative = path.relative(WEB, file);
            if (relative.startsWith('..') || path.isAbsolute(relative)) {
                response.writeHead(403);
                response.end();
                return;
            }
            fs.readFile(file, (error, data) => {
                if (error) {
                    response.writeHead(404);
                    response.end();
                    return;
                }
                const extension = path.extname(file);
                response.writeHead(200, {'Content-Type':extension === '.html'
                    ? 'text/html; charset=utf-8'
                    : extension === '.css' ? 'text/css; charset=utf-8'
                        : extension === '.js' ? 'text/javascript; charset=utf-8'
                            : 'application/octet-stream'});
                response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function probePreparationMenuFocusCascade(page) {
    const trigger = page.locator('.inventory-preparation-trigger');
    await trigger.waitFor({state:'visible', timeout:10000});

    async function snapshot(selector) {
        return page.evaluate(targetSelector => {
            const target = document.querySelector(targetSelector);
            if (!target) return {missing:true};
            const shell = target.closest('.workbench-shell');
            const tokenProbe = document.createElement('span');
            tokenProbe.style.cssText =
                'position:absolute;width:0;height:0;color:var(--wb-focus)';
            shell.appendChild(tokenProbe);
            const style = getComputedStyle(target);
            const result = {
                active:document.activeElement === target,
                focusVisible:target.matches(':focus-visible'),
                outlineColor:style.outlineColor,
                outlineStyle:style.outlineStyle,
                outlineWidth:style.outlineWidth,
                outlineOffset:style.outlineOffset,
                focusToken:getComputedStyle(tokenProbe).color,
                reducedMotion:matchMedia('(prefers-reduced-motion: reduce)').matches
            };
            tokenProbe.remove();
            return result;
        }, selector);
    }

    function consumesExactRing(value, reducedMotion) {
        return value.active === true
            && value.focusVisible === true
            && value.outlineColor === value.focusToken
            && value.outlineStyle === 'solid'
            && value.outlineWidth === '2px'
            && value.outlineOffset === '2px'
            && value.reducedMotion === reducedMotion;
    }

    const evidence = {};
    for (const mode of [
        {name:'normal', media:'no-preference', reduced:false},
        {name:'reduced', media:'reduce', reduced:true}
    ]) {
        await page.emulateMedia({reducedMotion:mode.media});
        await page.keyboard.press('Tab');
        await page.evaluate(() => {
            document.querySelector('.inventory-preparation-trigger').focus();
        });
        evidence[mode.name + 'Trigger'] =
            await snapshot('.inventory-preparation-trigger');
        await page.keyboard.press('ArrowDown');
        evidence[mode.name + 'Item'] =
            await snapshot('.inventory-preparation-item[tabindex="0"]');
        if (!consumesExactRing(evidence[mode.name + 'Trigger'], mode.reduced)
                || !consumesExactRing(evidence[mode.name + 'Item'], mode.reduced)) {
            throw new Error('preparation keyboard focus ring drifted in '
                + mode.name + ' motion: ' + JSON.stringify(evidence));
        }
        await page.keyboard.press('Escape');
        await page.waitForFunction(() =>
            document.querySelector('.inventory-preparation-trigger')
                .getAttribute('aria-expanded') === 'false');
    }

    await page.evaluate(() => {
        if (document.activeElement
                && typeof document.activeElement.blur === 'function') {
            document.activeElement.blur();
        }
    });
    const triggerBox = await page.locator('.inventory-preparation-trigger').boundingBox();
    if (!triggerBox) throw new Error('preparation trigger has no pointer hitbox');
    await page.mouse.click(
        triggerBox.x + triggerBox.width / 2,
        triggerBox.y + triggerBox.height / 2);
    evidence.pointerTrigger = await snapshot('.inventory-preparation-trigger');
    if (!(evidence.pointerTrigger.active === true
            && evidence.pointerTrigger.focusVisible === false
            && evidence.pointerTrigger.outlineStyle === 'none')) {
        throw new Error('preparation pointer focus must not fake the keyboard ring: '
            + JSON.stringify(evidence.pointerTrigger));
    }
    await page.mouse.click(
        triggerBox.x + triggerBox.width / 2,
        triggerBox.y + triggerBox.height / 2);
    await page.waitForFunction(() =>
        document.querySelector('.inventory-preparation-trigger')
            .getAttribute('aria-expanded') === 'false');
    await page.emulateMedia({reducedMotion:'reduce'});
    return evidence;
}

async function probePreparationMenuKeyboardAndGeometry(page, viewport) {
    const triggerSelector = '[data-header-action="preparation-menu"]';
    const menuSelector = '.inventory-preparation-popover';
    const expectedRoutes = [
        'equipment', 'battlebox', 'tuning',
        'skills', 'materials', 'intelligence'
    ];
    const tabOrder = await page.evaluate(selector => {
        const candidates = Array.from(document.querySelectorAll(
            'a[href],button,input,select,textarea,[tabindex]'));
        const visible = candidates.filter(node => {
            if (node.disabled || node.tabIndex < 0
                    || node.closest('[hidden],[inert]')) return false;
            const style = getComputedStyle(node);
            const rect = node.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden'
                && rect.width > 0 && rect.height > 0;
        });
        visible.forEach((node, index) => {
            node.setAttribute('data-b7-tab-sequence', String(index));
        });
        const trigger = document.querySelector(selector);
        const index = visible.indexOf(trigger);
        return {
            count:visible.length,
            trigger:index,
            previous:index >= 0
                ? (index - 1 + visible.length) % visible.length : -1,
            next:index >= 0 ? (index + 1) % visible.length : -1,
            nextAction:index >= 0
                ? visible[(index + 1) % visible.length].getAttribute(
                    'data-header-action')
                : null
        };
    }, triggerSelector);
    if (tabOrder.trigger < 0 || tabOrder.count < 3
            || tabOrder.nextAction !== 'stats') {
        throw new Error('preparation trigger is outside the normal header Tab order: '
            + JSON.stringify(tabOrder));
    }

    const evidence = {};
    for (const mode of [
        {name:'normal', media:'no-preference', reduced:false},
        {name:'reduced', media:'reduce', reduced:true}
    ]) {
        await page.emulateMedia({reducedMotion:mode.media});
        await page.keyboard.press('Tab');
        await page.evaluate(selector => document.querySelector(selector).focus(),
            triggerSelector);
        await page.keyboard.press('ArrowDown');
        await page.waitForFunction(selector =>
            document.querySelector(selector).hidden === false, menuSelector);
        const geometry = await page.evaluate(({menuSelector, viewport}) => {
            const menu = document.querySelector(menuSelector);
            const trigger = document.querySelector(
                '[data-header-action="preparation-menu"]');
            const menuRect = menu.getBoundingClientRect();
            const triggerRect = trigger.getBoundingClientRect();
            const style = getComputedStyle(menu);
            const items = Array.from(menu.querySelectorAll(
                '[data-preparation-route]')).map(item => {
                const rect = item.getBoundingClientRect();
                const itemStyle = getComputedStyle(item);
                return {
                    route:item.getAttribute('data-preparation-route'),
                    minHeight:itemStyle.minHeight,
                    left:rect.left,
                    right:rect.right,
                    top:rect.top,
                    bottom:rect.bottom,
                    width:rect.width,
                    height:rect.height
                };
            });
            return {
                reduced:matchMedia('(prefers-reduced-motion: reduce)').matches,
                expanded:trigger.getAttribute('aria-expanded'),
                role:menu.getAttribute('role'),
                display:style.display,
                transitionDuration:style.transitionDuration,
                menu:{
                    cssWidth:style.width,
                    left:menuRect.left,
                    right:menuRect.right,
                    top:menuRect.top,
                    bottom:menuRect.bottom,
                    width:menuRect.width,
                    height:menuRect.height
                },
                triggerBottom:triggerRect.bottom,
                viewport:viewport,
                items:items
            };
        }, {menuSelector, viewport});
        const durations = geometry.transitionDuration.split(',').map(value => {
            const trimmed = value.trim();
            return trimmed.endsWith('ms')
                ? Number(trimmed.slice(0, -2)) / 1000
                : Number(trimmed.replace(/s$/, ''));
        });
        const maxDuration = Math.max.apply(Math, durations);
        const rowsAreSingleColumn = geometry.items.every((item, index, rows) =>
            item.minHeight === '42px'
            && item.height > 0
            && Math.abs(item.left - rows[0].left) <= 1
            && Math.abs(item.right - rows[0].right) <= 1
            && (index === 0 || item.top >= rows[index - 1].bottom));
        const routes = geometry.items.map(item => item.route);
        if (geometry.reduced !== mode.reduced
                || geometry.expanded !== 'true'
                || geometry.role !== 'menu'
                || geometry.display !== 'grid'
                || JSON.stringify(routes) !== JSON.stringify(expectedRoutes)
                || geometry.menu.cssWidth !== '204px'
                || geometry.menu.width > viewport.width - 24 + 1
                || geometry.menu.left < -1
                || geometry.menu.right > viewport.width + 1
                || geometry.menu.top <= geometry.triggerBottom
                || geometry.menu.bottom > viewport.height + 1
                || !rowsAreSingleColumn
                || (mode.reduced ? maxDuration !== 0 : maxDuration <= 0)) {
            throw new Error('preparation menu geometry/motion drifted at '
                + viewport.width + 'x' + viewport.height + ' '
                + mode.name + ': ' + JSON.stringify(geometry));
        }

        await page.keyboard.press('Tab');
        await page.waitForFunction(selector =>
            document.querySelector(selector).getAttribute('aria-expanded') === 'false',
        triggerSelector);
        const tabTarget = await page.evaluate(() => ({
            sequence:Number(document.activeElement
                && document.activeElement.getAttribute('data-b7-tab-sequence')),
            action:document.activeElement
                && document.activeElement.getAttribute('data-header-action'),
            insideMenu:!!(document.activeElement
                && document.activeElement.closest('.inventory-preparation-popover'))
        }));
        if (tabTarget.sequence !== tabOrder.next
                || tabTarget.action !== 'stats'
                || tabTarget.insideMenu) {
            throw new Error('Tab did not resume the normal header order in '
                + mode.name + ': ' + JSON.stringify({tabOrder, tabTarget}));
        }

        await page.evaluate(selector => document.querySelector(selector).focus(),
            triggerSelector);
        await page.keyboard.press('ArrowDown');
        await page.keyboard.press('Shift+Tab');
        await page.waitForFunction(selector =>
            document.querySelector(selector).getAttribute('aria-expanded') === 'false',
        triggerSelector);
        const reverseTarget = await page.evaluate(() => ({
            sequence:Number(document.activeElement
                && document.activeElement.getAttribute('data-b7-tab-sequence')),
            insideMenu:!!(document.activeElement
                && document.activeElement.closest('.inventory-preparation-popover'))
        }));
        if (reverseTarget.sequence !== tabOrder.trigger || reverseTarget.insideMenu) {
            throw new Error('Shift+Tab did not close through the stable trigger in '
                + mode.name + ': ' + JSON.stringify({tabOrder, reverseTarget}));
        }
        await page.keyboard.press('Shift+Tab');
        const reverseContinuation = await page.evaluate(() => ({
            sequence:Number(document.activeElement
                && document.activeElement.getAttribute('data-b7-tab-sequence')),
            expanded:document.querySelector(
                '[data-header-action="preparation-menu"]')
                .getAttribute('aria-expanded'),
            insideMenu:!!(document.activeElement
                && document.activeElement.closest('.inventory-preparation-popover'))
        }));
        // The trigger is the first page Tab stop. A second reverse Tab may move
        // into browser chrome, where document.activeElement intentionally stays
        // on the trigger; only reopening/re-entering the hidden menu is a trap.
        if (reverseContinuation.expanded !== 'false'
                || reverseContinuation.insideMenu) {
            throw new Error('Shift+Tab re-entered the preparation menu in '
                + mode.name + ': '
                + JSON.stringify({tabOrder, reverseTarget, reverseContinuation}));
        }
        evidence[mode.name] = {
            menuWidth:geometry.menu.width,
            menuHeight:geometry.menu.height,
            transitionDuration:geometry.transitionDuration,
            tabTarget:tabTarget,
            reverseTarget:reverseTarget,
            reverseContinuation:reverseContinuation
        };
    }
    await page.evaluate(() => {
        document.querySelectorAll('[data-b7-tab-sequence]').forEach(node => {
            node.removeAttribute('data-b7-tab-sequence');
        });
    });
    await page.emulateMedia({reducedMotion:'reduce'});
    return evidence;
}

async function runStorageToBuildVisibilityProbe(browser, server, shotDirectory) {
    const viewport = {width:1024, height:576};
    const page = await browser.newPage({
        viewport,
        reducedMotion:'reduce',
        deviceScaleFactor:1
    });
    const pageErrors = [];
    const failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    page.on('requestfailed', request => failedRequests.push(request.url()));
    await page.route('https://cfn-fonts.local/**', async route => {
        const fontName = path.basename(new URL(route.request().url()).pathname);
        const fontPath = path.join(process.env.LOCALAPPDATA || '',
            'CF7FlashNight', 'fonts', fontName);
        if (!fs.existsSync(fontPath)) return route.abort('failed');
        return route.fulfill({
            path:fontPath,
            headers:{'access-control-allow-origin':'*'}
        });
    });
    try {
        await page.goto('http://127.0.0.1:' + server.address().port + '/' + HARNESS
            + '?stats-probe=1',
        {waitUntil:'load'});
        try {
            await page.waitForFunction(() => window.__statsProbeReady === true
                || window.__qaReady === true, null,
                {timeout:30000});
        } catch (error) {
            throw new Error('stats probe did not become ready: '
                + JSON.stringify({pageErrors, failedRequests}) + '; ' + error.message);
        }
        const probeState = await page.evaluate(() => ({
            ready:window.__statsProbeReady === true,
            report:window.__qaReport || null
        }));
        if (!probeState.ready) {
            throw new Error('stats probe stopped on an earlier harness failure: '
                + JSON.stringify(probeState.report));
        }
        await page.evaluate(() => {
            const output = document.getElementById('qa-output');
            if (output) output.hidden = true;
        });

        await page.locator('[data-header-action="back-build"]').click();
        await page.waitForFunction(() => InventoryWorkbench.debugState().view === 'build');
        await page.locator('[data-header-action="preparation-menu"]').click();
        await page.locator('[data-preparation-route="battlebox"]').click();
        await page.waitForFunction(() => {
            const state = InventoryWorkbench.debugState();
            return state.view === 'storage' && state.storage && state.storage.active;
        });
        const storageMounted = await page.evaluate(() => {
            const body = document.querySelector('.workbench-shell > .workbench-body');
            const host = document.querySelector('.character-build-host');
            return {
                active:InventoryWorkbench.debugState().storage.active,
                view:InventoryWorkbench.debugState().view,
                bodyHidden:body.hidden,
                bodyDisplay:getComputedStyle(body).display,
                hostHidden:host.hidden,
                hostDisplay:getComputedStyle(host).display
            };
        });
        if (!storageMounted.active || storageMounted.view !== 'storage'
                || storageMounted.bodyHidden || storageMounted.bodyDisplay === 'none'
                || !storageMounted.hostHidden || storageMounted.hostDisplay !== 'none') {
            throw new Error('storage did not mount before build switch: '
                + JSON.stringify(storageMounted));
        }

        await page.locator('[data-header-action="return-build"]').click();
        await page.waitForFunction(() => {
            const state = InventoryWorkbench.debugState();
            return state.view === 'build' && state.build && state.build.mounted
                && state.build.rendererCount === 1
                && state.build.view && state.build.view.candidateCount === 7
                && state.build.view.candidateScope === 'backpack'
                && state.build.view.selectedSlotKey === '';
        }, null, {timeout:30000});
        const switched = await page.evaluate(() => {
            const body = document.querySelector('.workbench-shell > .workbench-body');
            const host = document.querySelector('.character-build-host');
            const action = document.querySelector('[data-doll-preview-open]');
            const bodyRect = body.getBoundingClientRect();
            const hostRect = host.getBoundingClientRect();
            const actionRect = action.getBoundingClientRect();
            const hit = document.elementFromPoint(
                actionRect.left + actionRect.width / 2,
                actionRect.top + actionRect.height / 2);
            return {
                bodyHidden:body.hidden,
                bodyDisplay:getComputedStyle(body).display,
                bodyClientRects:body.getClientRects().length,
                bodyWidth:bodyRect.width,
                bodyHeight:bodyRect.height,
                hostHidden:host.hidden,
                hostDisplay:getComputedStyle(host).display,
                hostVisibility:getComputedStyle(host).visibility,
                hostWidth:hostRect.width,
                hostHeight:hostRect.height,
                actionWidth:actionRect.width,
                actionHeight:actionRect.height,
                actionHit:!!hit && (hit === action || action.contains(hit))
            };
        });
        if (!switched.bodyHidden || switched.bodyDisplay !== 'none'
                || switched.bodyClientRects !== 0
                || switched.bodyWidth !== 0 || switched.bodyHeight !== 0) {
            throw new Error('hidden storage body still paints after build switch: '
                + JSON.stringify(switched));
        }
        if (switched.hostHidden || switched.hostDisplay === 'none'
                || switched.hostVisibility === 'hidden'
                || switched.hostWidth <= 0 || switched.hostHeight <= 0) {
            throw new Error('character host is not visible after storage switch: '
                + JSON.stringify(switched));
        }
        if (!switched.actionHit || switched.actionWidth < 44 || switched.actionHeight < 44) {
            throw new Error('character action is not the pointer hit target after storage switch: '
                + JSON.stringify(switched));
        }
        await page.keyboard.press('Tab');
        const slotFocus = await page.evaluate(() => {
            const slot = document.querySelector('.character-build-slot:not(:disabled)');
            const card = slot && slot.querySelector('.character-build-slot-card');
            if (!slot || !card) return {missing:true};
            const shell = slot.closest('.workbench-shell');
            const focusProbe = document.createElement('span');
            const selectedProbe = document.createElement('span');
            focusProbe.style.cssText = 'position:absolute;width:0;height:0;color:var(--wb-focus)';
            selectedProbe.style.cssText = 'position:absolute;width:0;height:0;color:var(--wb-role-selected)';
            shell.append(focusProbe, selectedProbe);
            const previousSelected = slot.getAttribute('aria-selected');
            slot.setAttribute('aria-selected', 'true');
            slot.focus();
            const slotStyle = getComputedStyle(slot);
            const cardStyle = getComputedStyle(card);
            const result = {
                focusVisible:slot.matches(':focus-visible'),
                slotOutlineStyle:slotStyle.outlineStyle,
                slotOutlineWidth:slotStyle.outlineWidth,
                cardOutlineColor:cardStyle.outlineColor,
                cardOutlineStyle:cardStyle.outlineStyle,
                cardOutlineWidth:cardStyle.outlineWidth,
                cardOutlineOffset:cardStyle.outlineOffset,
                cardBorderColor:cardStyle.borderColor,
                focusToken:getComputedStyle(focusProbe).color,
                selectedToken:getComputedStyle(selectedProbe).color
            };
            if (previousSelected == null) slot.removeAttribute('aria-selected');
            else slot.setAttribute('aria-selected', previousSelected);
            focusProbe.remove();
            selectedProbe.remove();
            return result;
        });
        if (!(slotFocus.focusVisible === true
                && slotFocus.slotOutlineStyle === 'none'
                && slotFocus.slotOutlineWidth === '0px'
                && slotFocus.cardOutlineStyle === 'solid'
                && slotFocus.cardOutlineWidth === '2px'
                && slotFocus.cardOutlineOffset === '-2px'
                && slotFocus.cardOutlineColor === slotFocus.focusToken
                && slotFocus.cardBorderColor === slotFocus.selectedToken
                && slotFocus.focusToken !== slotFocus.selectedToken)) {
            throw new Error('character slot focus exception lost focus/selected role separation: '
                + JSON.stringify(slotFocus));
        }
        const pointerSlotBox = await page.locator(
            '.character-build-slot:not(:disabled)').first().boundingBox();
        if (!pointerSlotBox) throw new Error('character slot pointer focus probe has no hitbox');
        await page.evaluate(() => {
            if (document.activeElement
                    && typeof document.activeElement.blur === 'function') {
                document.activeElement.blur();
            }
        });
        await page.mouse.click(
            pointerSlotBox.x + pointerSlotBox.width / 2,
            pointerSlotBox.y + pointerSlotBox.height / 2);
        const pointerSlotFocus = await page.evaluate(() => {
            const slot = document.querySelector('.character-build-slot:not(:disabled)');
            const card = slot && slot.querySelector('.character-build-slot-card');
            if (!slot || !card) return {missing:true};
            const style = getComputedStyle(card);
            return {
                active:document.activeElement === slot,
                focusVisible:slot.matches(':focus-visible'),
                cardOutlineStyle:style.outlineStyle,
                cardOutlineWidth:style.outlineWidth
            };
        });
        if (!(pointerSlotFocus.active === true
                && pointerSlotFocus.focusVisible === false
                && pointerSlotFocus.cardOutlineStyle === 'none')) {
            throw new Error('pointer focus must not fake the Character slot keyboard ring: '
                + JSON.stringify(pointerSlotFocus));
        }
        await probePreparationMenuFocusCascade(page);
        await probePreparationMenuKeyboardAndGeometry(page, viewport);
        if (shotDirectory) {
            await page.screenshot({
                path:path.join(shotDirectory,
                    '1024x576-character-build-after-storage-switch.png')
            });
        }
        await page.locator('[data-doll-preview-open]').click();
        await page.waitForFunction(() => {
            const state = InventoryWorkbench.debugState();
            return state.build && state.build.view && state.build.view.dollPreviewOpen;
        });
        await page.locator('[data-doll-preview-close]').click();
        await page.waitForFunction(() => {
            const state = InventoryWorkbench.debugState();
            return state.build && state.build.view && !state.build.view.dollPreviewOpen;
        });

        const unexpectedFailedRequests = failedRequests.filter(request =>
            !request.includes('__qa_expected_asset_failure_'));
        if (pageErrors.length || unexpectedFailedRequests.length) {
            throw new Error('storage-to-build visibility probe diagnostics: '
                + JSON.stringify({pageErrors, failedRequests:unexpectedFailedRequests}));
        }
        console.log('1024x576 storage-to-build visibility/focus'
            + ' + preparation keyboard/geometry: 12/12 checks'
            + (shotDirectory ? '; screenshot=1024x576-character-build-after-storage-switch.png'
                : ''));
        return 12;
    } finally {
        await page.close();
    }
}

async function runPreparationMenuViewportMatrix(browser, server, viewports) {
    let passed = 0;
    for (const viewport of viewports) {
        const page = await browser.newPage({
            viewport,
            reducedMotion:'reduce',
            deviceScaleFactor:1
        });
        const pageErrors = [];
        const failedRequests = [];
        page.on('pageerror', error => pageErrors.push(error.message));
        page.on('requestfailed', request => failedRequests.push(request.url()));
        await page.route('https://cfn-fonts.local/**', async route => {
            const fontName = path.basename(new URL(route.request().url()).pathname);
            const fontPath = path.join(process.env.LOCALAPPDATA || '',
                'CF7FlashNight', 'fonts', fontName);
            if (!fs.existsSync(fontPath)) return route.abort('failed');
            return route.fulfill({
                path:fontPath,
                headers:{'access-control-allow-origin':'*'}
            });
        });
        try {
            await page.goto('http://127.0.0.1:' + server.address().port + '/'
                + HARNESS + '?stats-probe=1', {waitUntil:'load'});
            await page.waitForFunction(() => window.__statsProbeReady === true
                || window.__qaReady === true, null, {timeout:30000});
            const ready = await page.evaluate(() => window.__statsProbeReady === true);
            if (!ready) {
                throw new Error('preparation viewport matrix stopped before stats gate: '
                    + JSON.stringify(await page.evaluate(() => window.__qaReport || null)));
            }
            await page.locator('[data-header-action="back-build"]').click();
            await page.waitForFunction(() =>
                InventoryWorkbench.debugState().view === 'build');
            await probePreparationMenuKeyboardAndGeometry(page, viewport);
            const unexpectedFailedRequests = failedRequests.filter(request =>
                !request.includes('__qa_expected_asset_failure_'));
            if (pageErrors.length || unexpectedFailedRequests.length) {
                throw new Error('preparation viewport matrix diagnostics: '
                    + JSON.stringify({
                        viewport,
                        pageErrors,
                        failedRequests:unexpectedFailedRequests
                    }));
            }
            console.log(viewport.width + 'x' + viewport.height
                + ' preparation menu keyboard/geometry normal+reduced: 6/6 checks');
            passed += 6;
        } finally {
            await page.close();
        }
    }
    return passed;
}

(async function main() {
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgeExecutable();
    if (!executablePath) throw new Error('Microsoft Edge not found');
    const source = fs.readFileSync(path.join(WEB, HARNESS), 'utf8');
    [
        'modules/asset-timeline.js',
        'modules/icons.js',
        'modules/dressup/dev/character-build-combination-fixture.js',
        'modules/character-build/dev/stats-fixture.js',
        'modules/dressup-doll-renderer.js',
        'modules/panels.js',
        'modules/panel-scale.js',
        'modules/uidata.js',
        'modules/workbench-profile.js',
        'modules/item-filter.js',
        'modules/inventory-ui.js',
        'modules/equipment-tuning-runtime.js',
        'modules/equipment-tuning-model.js',
        'modules/equipment-tuning-decision-presenter.js',
        'modules/equipment-tuning-render.js',
        'modules/inventory-workbench-config.js',
        'modules/inventory-workbench-preparation-menu.js',
        'modules/equipment-tuning-confirmation.js',
        'modules/equipment-tuning-interaction.js',
        'modules/equipment-tuning-write-lifecycle.js',
        'modules/equipment-tuning-loadout-lifecycle.js',
        'modules/equipment-tuning-source-marker.js',
        'modules/equipment-tuning-view.js',
        'modules/inventory-workbench-navigation.js',
        'modules/overlay-audio-bindings.js',
        'modules/workbench-inspection-viewport.js',
        'modules/inventory-tuning-scope.js',
        'modules/inventory-workbench-feature-loader.js',
        'modules/character-build/character-build-mutation.js',
        'modules/character-build/character-build-drug-layout.js',
        'modules/character-build/character-build-session-contract.js',
        'modules/character-build-session.js',
        'modules/loadout-picker/loadout-picker-action-view.js',
        'modules/character-build/character-build-tuning-adapter.js',
        'modules/character-build/character-build-tuning-ports.js',
        'modules/character-build/character-build-candidate-eligibility.js',
        'modules/loadout-picker/loadout-picker-candidate-state.js',
        'modules/character-build/character-build-facet-counts.js',
        'modules/character-build/character-build-stats-view.js',
        'modules/character-build/character-build-doll-preview.js',
        'modules/character-build/character-build-template.js',
        'modules/character-build/character-build-loadout-presenter.js',
        'modules/loadout-picker/loadout-picker-slot-grid.js',
        'modules/loadout-picker/loadout-picker-drop-policy.js',
        'modules/loadout-picker/loadout-picker-candidate-drag.js',
        'modules/loadout-picker/loadout-picker-candidate-pane.js',
        'modules/loadout-picker/loadout-picker.js',
        'modules/character-build/character-build-tuning.js',
        'modules/character-build/character-build-slot-transition.js',
        'modules/character-build/character-build-pose.js',
        'modules/character-build/character-build-projection.js',
        'modules/character-build/character-build-transport.js',
        'modules/character-build/character-build-candidate-channel.js',
        'modules/character-build.js',
        'modules/inventory-workbench.js'
    ].forEach(asset => {
        if (!source.includes(asset)) throw new Error('integration harness omits ' + asset);
    });
    if (source.includes('window.Icons =') || source.includes('window.DressupDollRenderer = {')) {
        throw new Error('integration harness replaces a production visual dependency');
    }

    const {chromium} = require(PLAYWRIGHT);
    const server = await createServer();
    const browser = await chromium.launch({executablePath, headless:true});
    try {
        const viewports = [
            {width:1024, height:576},
            {width:1366, height:768},
            {width:1920, height:1080}
        ];
        const shotDirectory = shotArg
            ? path.resolve(shotArg.slice('--shot-dir='.length)) : '';
        if (shotDirectory) fs.mkdirSync(shotDirectory, {recursive:true});
        const switchProbePassed = await runStorageToBuildVisibilityProbe(
            browser, server, shotDirectory);
        const preparationMatrixPassed = await runPreparationMenuViewportMatrix(
            browser, server, viewports);
        let passed = 0;
        for (const viewport of viewports) {
            const page = await browser.newPage({
                viewport,
                reducedMotion:'reduce',
                deviceScaleFactor:1
            });
            const pageErrors = [];
            const failedRequests = [];
            page.on('pageerror', error => pageErrors.push(error.message));
            page.on('requestfailed', request => failedRequests.push(request.url()));
            await page.route('https://cfn-fonts.local/**', async route => {
                const fontName = path.basename(new URL(route.request().url()).pathname);
                const fontPath = path.join(process.env.LOCALAPPDATA || '',
                    'CF7FlashNight', 'fonts', fontName);
                if (!fs.existsSync(fontPath)) return route.abort('failed');
                return route.fulfill({
                    path:fontPath,
                    headers:{'access-control-allow-origin':'*'}
                });
            });
            await page.goto('http://127.0.0.1:' + server.address().port + '/' + HARNESS
                + '?stats-probe=1',
                {waitUntil:'load'});
            try {
                await page.waitForFunction(() => window.__statsProbeReady === true, null,
                    {timeout:30000});
            } catch (error) {
                const diagnostic = await page.evaluate(() => ({
                    report:window.__qaReport || null,
                    output:(document.getElementById('qa-output') || {}).textContent || ''
                }));
                throw new Error(error.message + '\n' + JSON.stringify({
                    pageErrors, failedRequests, diagnostic
                }, null, 2));
            }
            await page.evaluate(() => {
                const output = document.getElementById('qa-output');
                if (output) output.hidden = true;
            });
            if (shotDirectory && viewport === viewports[0]) {
                await page.screenshot({
                    path:path.join(shotDirectory,
                        '1024x576-character-build-production-stats-top.png')
                });
            }
            await page.waitForFunction(() => document.activeElement
                === document.querySelector('[data-scroll-region="stats"]'));
            const inputProbe = await page.evaluate(async () => {
                const scroll = document.querySelector('[data-scroll-region="stats"]');
                const tokenProbe = document.createElement('span');
                tokenProbe.style.cssText = 'position:absolute;width:0;height:0;color:var(--wb-focus)';
                scroll.closest('.workbench-shell').appendChild(tokenProbe);
                const focusStyle = getComputedStyle(scroll);
                const before = scroll.scrollTop;
                const result = {
                    reducedMotion:matchMedia('(prefers-reduced-motion: reduce)').matches,
                    keyboardFocused:document.activeElement === scroll,
                    focusVisible:scroll.matches(':focus-visible'),
                    focusOutlineColor:focusStyle.outlineColor,
                    focusOutlineStyle:focusStyle.outlineStyle,
                    focusOutlineWidth:focusStyle.outlineWidth,
                    focusOutlineOffset:focusStyle.outlineOffset,
                    focusToken:getComputedStyle(tokenProbe).color,
                    before,
                    maxScroll:scroll.scrollHeight - scroll.clientHeight
                };
                tokenProbe.remove();
                return result;
            });
            if (!(inputProbe.focusVisible === true
                && inputProbe.focusOutlineColor === inputProbe.focusToken
                && inputProbe.focusOutlineStyle === 'solid'
                && inputProbe.focusOutlineWidth === '2px'
                && inputProbe.focusOutlineOffset === '2px')) {
                throw new Error('stats scroll focus ring does not consume --wb-focus: '
                    + JSON.stringify(inputProbe));
            }
            await page.keyboard.press('PageDown');
            await page.waitForFunction(before => {
                const scroll = document.querySelector('[data-scroll-region="stats"]');
                return scroll.scrollTop > before + 1;
            }, inputProbe.before);
            inputProbe.pageDownDelta = await page.evaluate(() =>
                document.querySelector('[data-scroll-region="stats"]').scrollTop);
            await page.keyboard.press('End');
            await page.waitForFunction(() => {
                const scroll = document.querySelector('[data-scroll-region="stats"]');
                return scroll.scrollTop >= scroll.scrollHeight - scroll.clientHeight - 1;
            });
            Object.assign(inputProbe, await page.evaluate(() => {
                const scroll = document.querySelector('[data-scroll-region="stats"]');
                const last = document.querySelector(
                    '[data-stats-detail-grid] > section:last-child');
                const scrollRect = scroll.getBoundingClientRect();
                const lastRect = last.getBoundingClientRect();
                return {
                    endReached:scroll.getAttribute('data-scroll-position') === 'end',
                    lastVisible:lastRect.top >= scrollRect.top - 1
                        && lastRect.bottom <= scrollRect.bottom + 1
                };
            }));
            if (shotDirectory && viewport === viewports[0]) {
                await page.screenshot({
                    path:path.join(shotDirectory,
                        '1024x576-character-build-production-stats-end.png')
                });
            }
            await page.keyboard.press('Home');
            await page.waitForFunction(() =>
                document.querySelector('[data-scroll-region="stats"]').scrollTop <= 1);
            inputProbe.homeReached = true;
            const scrollRect = await page.locator('[data-scroll-region="stats"]').boundingBox();
            await page.mouse.move(scrollRect.x + scrollRect.width / 2,
                scrollRect.y + scrollRect.height / 2);
            await page.mouse.wheel(0, 360);
            await page.waitForFunction(() =>
                document.querySelector('[data-scroll-region="stats"]').scrollTop > 1);
            inputProbe.wheelDelta = await page.evaluate(() =>
                document.querySelector('[data-scroll-region="stats"]').scrollTop);
            await page.evaluate(probe => {
                window.__routeHarness.statsInputProbe = probe;
                window.__continueStatsProbe();
            }, inputProbe);
            await page.waitForFunction(() => window.__qaReady === true, null, {timeout:30000});
            const report = await page.evaluate(() => window.__qaReport);
            const shots = shotArg && viewport === viewports[0]
                ? await page.evaluate(() => window.__routeHarness.shots) : {};
            if (pageErrors.length) throw new Error(viewport.width + 'x' + viewport.height
                + ' page errors: ' + pageErrors.join(' | '));
            const unexpectedFailedRequests = failedRequests.filter(request =>
                !request.includes('__qa_expected_asset_failure_'));
            if (unexpectedFailedRequests.length) {
                throw new Error(viewport.width + 'x' + viewport.height
                    + ' failed requests: ' + unexpectedFailedRequests.join(' | '));
            }
            const failures = report.checks.filter(check => !check.ok);
            if (failures.length) {
                throw new Error(viewport.width + 'x' + viewport.height + '\n'
                    + failures.map(check =>
                        check.name + (check.detail ? ': ' + check.detail : '')).join('\n'));
            }
            [
                'delayed tuning entry failure rolls back without changing stack or opener focus',
                'standalone tuning waits behind the exact embedded detach barrier',
                'a duplicate embedded detach callback cannot mutate standalone source or history',
                'explicit tuning return preserves Character session and never finalizes',
                'nested standalone tuning keeps one visible explicit Build return',
                'nested standalone tuning explicit return performs one bounded unwind to Build',
                'first Esc from tuning returns only to storage',
                'second Esc from storage returns to build without closing',
                'HUD standalone tuning Escape detaches then closes to game without finalize',
                'HUD standalone storage ordinary Close returns to game without finalize'
            ].forEach(name => {
                if (!report.checks.some(check => check.name === name && check.ok)) {
                    throw new Error('B3 workbench assertion missing: ' + name);
                }
            });
            const loadout = report.sent.filter(message => message.domain === 'loadout');
            const whitelist = [
                'snapshot', 'candidates', 'tooltip', 'flushLive', 'statsSnapshot', 'finalize',
                'equipEquipment', 'unequipEquipment', 'equipDrug', 'unequipDrug'
            ];
            if (!loadout.length || loadout.some(message => !whitelist.includes(message.cmd))) {
                throw new Error('production route escaped the ten-command whitelist');
            }
            if (report.renderer.maxActive !== 1 || report.renderer.active !== 0) {
                throw new Error('renderer ownership did not settle: '
                    + JSON.stringify(report.renderer));
            }
            if (!report.renderer.animationModes.length
                    || report.renderer.animationModes.some(Boolean)) {
                throw new Error('reduced-motion production renderer did not stay on a static frame: '
                    + JSON.stringify(report.renderer.animationModes));
            }
            ['initial', 'candidate', 'restored'].forEach(stage => {
                const visual = report.visual[stage];
                if (!visual || visual.alphaPixels <= 2500
                        || visual.bboxHeightRatio < 0.68 || visual.bboxHeightRatio > 0.92) {
                    throw new Error(stage + ' visual proof outside frozen bounds: '
                        + JSON.stringify(visual));
                }
            });
            if (report.renderer.expectedAssetFailures !== 2
                    || report.shotNames.length !== 34
                    || report.visual.poseMatrix.length !== 35
                    || !report.visual.stats || !report.visual.stats.input
                    || report.visual.stats.input.wheelDelta <= 1
                    || report.boundary.controller !== 'production'
                    || report.boundary.storage !== 'facade_stub'
                    || report.boundary.host !== 'fake_bridge') {
                throw new Error('production pose matrix evidence incomplete: '
                    + JSON.stringify({
                        failures:report.renderer.expectedAssetFailures,
                        shots:report.shotNames.length,
                        poses:report.visual.poseMatrix.length
                    }));
            }
            const written = writeShots(shots, viewport);
            console.log(viewport.width + 'x' + viewport.height + ': '
                + report.checks.length + '/' + report.checks.length
                + ' checks; initial alpha=' + report.visual.initial.alphaPixels
                + ', bbox=' + (report.visual.initial.bboxHeightRatio * 100).toFixed(1) + '%'
                + ', stats=' + report.visual.stats.top.clientHeight + '/'
                    + report.visual.stats.top.scrollHeight
                + ', wheel=' + Math.round(report.visual.stats.input.wheelDelta)
                + (written ? ', screenshots=' + written : ''));
            passed += report.checks.length;
            await page.close();
        }
        console.log('Character-build production controller integration'
            + ' (storage facade + fake Host bridge): ' + passed + '/' + passed
            + ' passed across ' + viewports.length + ' viewports');
        console.log('Storage-to-build hidden-body regression: ' + switchProbePassed + '/'
            + switchProbePassed + ' passed at 1024x576');
        console.log('Preparation menu keyboard/geometry matrix: '
            + preparationMatrixPassed + '/' + preparationMatrixPassed
            + ' passed across ' + viewports.length
            + ' viewports in normal/reduced motion');
            if (shotArg) {
            console.log('Screenshots: ' + shotDirectory);
        }
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
})().catch(error => {
    console.error(error.stack || error);
    process.exit(1);
});
