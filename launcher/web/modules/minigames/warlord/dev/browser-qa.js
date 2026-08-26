(function () {
    'use strict';

    function waitFor(check, timeoutMs) {
        var started = Date.now();
        return new Promise(function (resolve, reject) {
            function poll() {
                var value = check();
                if (value) { resolve(value); return; }
                if (Date.now() - started > timeoutMs) { reject(new Error('timeout')); return; }
                setTimeout(poll, 30);
            }
            poll();
        });
    }

    function delay(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }

    async function run() {
        var results = [];
        async function check(name, operation) {
            try {
                var detail = await operation();
                results.push({ name: name, pass: true, detail: detail || '' });
            } catch (error) {
                results.push({ name: name, pass: false, detail: error && error.message ? error.message : String(error) });
            }
        }

        function findCanvasPoint(canvas, host, predicate) {
            var rect = canvas.getBoundingClientRect();
            for (var y = rect.top + 4; y < rect.bottom - 4; y += 6) {
                for (var x = rect.left + 4; x < rect.right - 4; x += 6) {
                    canvas.dispatchEvent(new PointerEvent('pointermove', {
                        pointerId: 90,
                        clientX: x,
                        clientY: y,
                        bubbles: true,
                        cancelable: true
                    }));
                    if (predicate(host)) return { x: x, y: y };
                }
            }
            return null;
        }

        function clickCanvas(canvas, point, pointerId) {
            canvas.dispatchEvent(new PointerEvent('pointerdown', {
                pointerId: pointerId,
                button: 0,
                buttons: 1,
                clientX: point.x,
                clientY: point.y,
                bubbles: true,
                cancelable: true
            }));
            canvas.dispatchEvent(new PointerEvent('pointerup', {
                pointerId: pointerId,
                button: 0,
                buttons: 0,
                clientX: point.x,
                clientY: point.y,
                bubbles: true,
                cancelable: true
            }));
        }

        await check('runtime-ready', async function () {
            var root = await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            return root.getAttribute('data-runtime-version') || 'ready';
        });
        await check('scalable-context-and-paged-node-navigator', async function () {
            var navigator = document.querySelector('.warlord-node-strip');
            if (!navigator || navigator.getAttribute('data-total-nodes') !== '9') throw new Error('node navigator total is not 9');
            var contextNodes = navigator.querySelectorAll('[data-action="select-node"]');
            if (navigator.getAttribute('data-mode') !== 'context' || contextNodes.length > 6) {
                throw new Error('context navigator did not stay bounded');
            }
            var stripHeight = navigator.getBoundingClientRect().height;
            if (stripHeight > 48.5) throw new Error('node navigator still consumes ' + stripHeight + 'px of sandtable height');
            if (Array.from(contextNodes).some(function (node) { return node.getBoundingClientRect().height < 40; })) {
                throw new Error('compact node navigator reduced a card below the 40px hit target');
            }
            var scope = navigator.querySelector('[data-action="toggle-node-scope"]');
            if (!scope) throw new Error('node scope toggle missing');
            scope.click();
            await delay(20);
            var ids = new Set(Array.from(navigator.querySelectorAll('[data-action="select-node"]')).map(function (node) {
                return node.getAttribute('data-node');
            }));
            var next = navigator.querySelector('[data-action="node-page-next"]:not(:disabled)');
            while (next) {
                next.click();
                await delay(20);
                Array.from(navigator.querySelectorAll('[data-action="select-node"]')).forEach(function (node) {
                    ids.add(node.getAttribute('data-node'));
                });
                next = navigator.querySelector('[data-action="node-page-next"]:not(:disabled)');
            }
            if (ids.size !== 9) throw new Error('paged node index covered ' + ids.size + '/9');
            navigator.querySelector('[data-action="toggle-node-scope"]').click();
            await delay(20);
            return '48px strip · >=40px targets · context <=6 · all-index 9/9';
        });
        await check('eight-card-roster', async function () {
            var cards = document.querySelectorAll('.warlord-card[data-testid^="card-"]');
            if (cards.length !== 8) throw new Error('expected 8 cards, found ' + cards.length);
            return '8/8';
        });
        await check('compact-1024-command-and-roster-copy', async function () {
            var phase = document.querySelector('.warlord-round > span');
            var names = Array.from(document.querySelectorAll('.warlord-card-copy > b'));
            var stats = Array.from(document.querySelectorAll('.warlord-card-stats'));
            if (!phase || phase.scrollWidth > phase.clientWidth || getComputedStyle(phase).whiteSpace !== 'nowrap') {
                throw new Error('top phase status wrapped or clipped');
            }
            if (names.length !== 8 || names.some(function (name) {
                return name.scrollWidth > name.clientWidth || parseFloat(getComputedStyle(name).fontSize) < 10;
            })) throw new Error('one or more card names are clipped or below 10px');
            if (stats.length !== 8 || stats.some(function (stat) { return stat.scrollWidth > stat.clientWidth; })) {
                throw new Error('one or more card key-stat rows are clipped');
            }
            return 'phase one-line · 8/8 names and key stats visible';
        });
        await check('webgl-or-visible-fallback', async function () {
            var canvas = document.querySelector('.warlord-sandtable-canvas');
            var fallback = document.querySelector('.warlord-map-fallback:not([hidden])');
            if (!canvas && !fallback) throw new Error('neither canvas nor fallback visible');
            if (canvas) {
                var host = document.querySelector('.warlord-scene-host');
                if (!host || host.getAttribute('data-piece-visual-style') !== 'tactical-badge-v1'
                    || Number(host.getAttribute('data-piece-badge-count')) < 1) {
                    throw new Error('integrated tactical badge contract is missing');
                }
            }
            return canvas ? 'three-canvas' : 'dom-fallback';
        });
        await check('semantic-landmarks-and-theme-rebind', async function () {
            var host = document.querySelector('.warlord-scene-host');
            var expectedKinds = 'choke,command,depot,economy,hq,supply';
            if (!host || host.getAttribute('data-node-kinds') !== expectedKinds || host.getAttribute('data-landmark-count') !== '9') {
                throw new Error('semantic landmark contract incomplete');
            }
            window.__warlordHarness.rebind({ mapTheme: 'tundra', seed: 'qa-theme-preview' });
            await waitFor(function () {
                var app = document.querySelector('.warlord-app[data-map-theme="tundra"]');
                var scene = document.querySelector('.warlord-scene-host[data-map-theme="tundra"] canvas');
                return app && scene;
            }, 12000);
            window.__warlordHarness.rebind({ mapTheme: 'desert', seed: 'qa-theme-restore' });
            await waitFor(function () {
                return document.querySelector('.warlord-app[data-map-theme="desert"] .warlord-scene-host[data-map-theme="desert"] canvas');
            }, 12000);
            return '6 semantic kinds · desert -> tundra -> desert';
        });
        await check('progressive-camera-pan-zoom-fit', async function () {
            var canvas = document.querySelector('.warlord-sandtable-canvas');
            var host = document.querySelector('.warlord-scene-host');
            var hud = document.querySelector('.warlord-camera-hud');
            var root = document.querySelector('.warlord-scale-shell');
            var zoomIn = document.querySelector('[data-action="camera-zoom-in"]');
            var fit = document.querySelector('[data-action="camera-fit"]');
            if (!canvas || !host || !hud || !root || !zoomIn || !fit) throw new Error('camera surface or controls missing');
            function visibleControls() {
                return Array.from(hud.querySelectorAll('.warlord-camera-controls button')).filter(function (button) {
                    var style = getComputedStyle(button);
                    return style.visibility !== 'hidden' && button.getBoundingClientRect().width > 1;
                }).length;
            }
            if (hud.getAttribute('data-expanded') !== 'false' || visibleControls() !== 2) {
                throw new Error('idle camera did not retain only full-map and locate');
            }
            var initialZoom = Number(host.getAttribute('data-camera-zoom'));
            zoomIn.click();
            zoomIn.click();
            // 程序性相机移动有 240ms 运镜过渡 + 帧饥饿兜底计时器；CSS-B 后展开还有 140-160ms CSS 过渡，等收敛后再断言
            await delay(1000);
            var expandedAfterAction = hud.getAttribute('data-expanded');
            var visibleAfterAction = visibleControls();
            var readout = hud.querySelector('.warlord-camera-readout');
            var readoutStyle = getComputedStyle(readout);
            var detailStyle = getComputedStyle(hud.querySelector('[data-camera-role="detail"]'));
            var readoutHeight = readout.getBoundingClientRect().height;
            if (expandedAfterAction !== 'true' || visibleAfterAction !== 4 || readoutHeight < 28) {
                throw new Error('camera reveal incomplete: expanded=' + expandedAfterAction
                    + ' controls=' + visibleAfterAction + ' readout=' + readoutHeight.toFixed(1)
                    + ' max=' + readoutStyle.maxHeight + ' opacity=' + readoutStyle.opacity
                    + ' detail=' + detailStyle.width + '/' + detailStyle.visibility);
            }
            var zoomed = Number(host.getAttribute('data-camera-zoom'));
            if (!(zoomed > initialZoom)) throw new Error('zoom controls did not increase tactical magnification: initial=' + initialZoom + ' zoomed=' + zoomed);
            var pieceScreenGrowth = Number(host.getAttribute('data-piece-screen-growth'));
            if (host.getAttribute('data-piece-scale-policy') !== 'progressive-art-detail-v1'
                || !(pieceScreenGrowth > 1.15 && pieceScreenGrowth <= 1.8)) {
                throw new Error('piece badge did not progressively reveal art within its tactical cap: ' + pieceScreenGrowth);
            }
            var selectedBefore = root.getAttribute('data-selected-node');
            var xBefore = Number(host.getAttribute('data-camera-x'));
            var zBefore = Number(host.getAttribute('data-camera-z'));
            var rect = canvas.getBoundingClientRect();
            var startX = rect.left + rect.width * 0.48;
            var startY = rect.top + rect.height * 0.48;
            canvas.dispatchEvent(new PointerEvent('pointerdown', { pointerId: 71, button: 0, buttons: 1, clientX: startX, clientY: startY, bubbles: true, cancelable: true }));
            canvas.dispatchEvent(new PointerEvent('pointermove', { pointerId: 71, button: 0, buttons: 1, clientX: startX + 64, clientY: startY + 32, bubbles: true, cancelable: true }));
            canvas.dispatchEvent(new PointerEvent('pointerup', { pointerId: 71, button: 0, buttons: 0, clientX: startX + 64, clientY: startY + 32, bubbles: true, cancelable: true }));
            await delay(40);
            var xAfter = Number(host.getAttribute('data-camera-x'));
            var zAfter = Number(host.getAttribute('data-camera-z'));
            if (Math.abs(xAfter - xBefore) < 0.02 && Math.abs(zAfter - zBefore) < 0.02) throw new Error('drag did not pan tactical camera');
            if (root.getAttribute('data-selected-node') !== selectedBefore) throw new Error('drag was misclassified as a node click');
            var wheel = new WheelEvent('wheel', { deltaY: -120, clientX: startX, clientY: startY, bubbles: true, cancelable: true });
            canvas.dispatchEvent(wheel);
            await delay(30);
            if (!wheel.defaultPrevented) throw new Error('wheel zoom did not suppress document scroll');
            if (Number(host.getAttribute('data-camera-zoom')) <= zoomed) throw new Error('wheel did not zoom around pointer anchor');
            fit.click();
            await waitFor(function () { return hud.getAttribute('data-at-fit') === 'true'; }, 3000);
            canvas.focus();
            canvas.dispatchEvent(new KeyboardEvent('keydown', { key: '+', bubbles: true, cancelable: true }));
            await delay(360);
            if (Number(host.getAttribute('data-camera-zoom')) <= initialZoom) throw new Error('keyboard zoom did not enter tactical camera');
            canvas.dispatchEvent(new KeyboardEvent('keydown', { key: 'Home', bubbles: true, cancelable: true }));
            await waitFor(function () { return hud.getAttribute('data-at-fit') === 'true'; }, 3000);
            if (document.querySelectorAll('.warlord-camera-controls button').length !== 4) throw new Error('camera control surface is incomplete');
            await delay(Number(hud.getAttribute('data-idle-delay')) + 180);
            if (hud.getAttribute('data-expanded') !== 'false' || visibleControls() !== 2) {
                throw new Error('camera details did not return to the idle disclosure state');
            }
            fit.focus();
            await delay(20);
            if (visibleControls() !== 4) throw new Error('keyboard focus did not reveal the complete camera surface');
            fit.blur();
            await delay(180);
            if (visibleControls() !== 2) throw new Error('camera surface did not compact after focus left');
            return 'idle 2 controls · activity/focus 4 controls · drag/wheel/keyboard/fit · no accidental selection';
        });
        await check('canvas-piece-pick-and-double-group', async function () {
            var canvas = document.querySelector('.warlord-sandtable-canvas');
            var host = document.querySelector('.warlord-scene-host');
            var root = document.querySelector('.warlord-scale-shell');
            if (!canvas || !host || !root) throw new Error('canvas selection surface missing');
            var point = findCanvasPoint(canvas, host, function (surface) {
                return surface.getAttribute('data-hovered-piece-faction') === 'red';
            });
            if (!point) throw new Error('could not ray-pick a red piece');
            clickCanvas(canvas, point, 91);
            await delay(20);
            if (root.getAttribute('data-selected-piece-count') !== '1') throw new Error('single piece click did not select exactly one piece');
            clickCanvas(canvas, point, 92);
            await delay(30);
            var selectedCount = Number(root.getAttribute('data-selected-piece-count'));
            var selectableAtNode = document.querySelectorAll('.warlord-piece input[data-field="piece"]:not(:disabled)').length;
            if (selectedCount !== selectableAtNode || selectedCount < 1) {
                throw new Error('double piece click did not select the complete local group: ' + selectedCount + '/' + selectableAtNode);
            }
            canvas.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(20);
            if (root.getAttribute('data-selected-piece-count') !== '0') throw new Error('Escape did not clear piece group');
            return 'ray-pick 1 · double-pick local group ' + selectedCount + ' · Escape clear';
        });
        await check('right-click-cancels-piece-group', async function () {
            var canvas = document.querySelector('.warlord-sandtable-canvas');
            var host = document.querySelector('.warlord-scene-host');
            var root = document.querySelector('.warlord-scale-shell');
            if (!canvas || !host || !root) throw new Error('canvas selection surface missing');
            var point = findCanvasPoint(canvas, host, function (surface) {
                return surface.getAttribute('data-hovered-piece-faction') === 'red';
            });
            if (!point) throw new Error('could not ray-pick a red piece');
            clickCanvas(canvas, point, 95);
            await delay(20);
            if (root.getAttribute('data-selected-piece-count') !== '1') throw new Error('setup click did not select exactly one piece');
            var empty = findCanvasPoint(canvas, host, function (surface) {
                return surface.getAttribute('data-hovered-piece') === '' && surface.getAttribute('data-hovered-node') === '';
            });
            if (!empty) throw new Error('could not find an empty sandtable point');
            canvas.dispatchEvent(new PointerEvent('pointerdown', { pointerId: 96, button: 2, buttons: 2, clientX: empty.x, clientY: empty.y, bubbles: true, cancelable: true }));
            canvas.dispatchEvent(new PointerEvent('pointerup', { pointerId: 96, button: 2, buttons: 0, clientX: empty.x, clientY: empty.y, bubbles: true, cancelable: true }));
            await delay(20);
            if (root.getAttribute('data-selected-piece-count') !== '0') throw new Error('right click did not cancel the piece group');
            var menu = new MouseEvent('contextmenu', { bubbles: true, cancelable: true });
            canvas.dispatchEvent(menu);
            if (!menu.defaultPrevented) throw new Error('contextmenu was not suppressed on canvas');
            return 'right-click cancel == empty click · native menu suppressed';
        });
        await check('marquee-direct-command-and-chain', async function () {
            var canvas = document.querySelector('.warlord-sandtable-canvas');
            var host = document.querySelector('.warlord-scene-host');
            var root = document.querySelector('.warlord-scale-shell');
            if (!canvas || !host || !root) throw new Error('marquee command surface missing');
            var rect = canvas.getBoundingClientRect();
            var start = { x: rect.left + 3, y: rect.top + 3 };
            var end = { x: rect.right - 3, y: rect.bottom - 3 };
            canvas.dispatchEvent(new PointerEvent('pointerdown', { pointerId: 93, button: 0, buttons: 1, shiftKey: true, clientX: start.x, clientY: start.y, bubbles: true, cancelable: true }));
            canvas.dispatchEvent(new PointerEvent('pointermove', { pointerId: 93, button: 0, buttons: 1, shiftKey: true, clientX: end.x, clientY: end.y, bubbles: true, cancelable: true }));
            var marquee = document.querySelector('.warlord-selection-marquee:not([hidden])');
            if (!marquee || marquee.getBoundingClientRect().width < rect.width * 0.9) throw new Error('Shift drag did not expose a visible marquee');
            canvas.dispatchEvent(new PointerEvent('pointerup', { pointerId: 93, button: 0, buttons: 0, shiftKey: true, clientX: end.x, clientY: end.y, bubbles: true, cancelable: true }));
            await delay(40);
            var marqueeCount = Number(root.getAttribute('data-selected-piece-count'));
            if (marqueeCount < 1 || !document.querySelector('.warlord-command-intent:not([hidden])')) {
                throw new Error('marquee did not create an observable same-origin command group');
            }
            while (Number(root.getAttribute('data-selected-piece-count')) > 2) {
                var checkedPieces = document.querySelectorAll('.warlord-piece input[data-field="piece"]:checked');
                var trim = checkedPieces[checkedPieces.length - 1];
                if (!trim) throw new Error('selected group cannot be reduced for the two-hop AP journey');
                trim.checked = false;
                trim.dispatchEvent(new Event('change', { bubbles: true }));
            }
            var selectedCount = Number(root.getAttribute('data-selected-piece-count'));
            document.querySelector('[data-action="toggle-node-scope"]')?.click();
            await delay(20);
            var nonAdjacent = document.querySelector('.warlord-node-card[data-command-state="none"]:not(.selected)');
            if (!nonAdjacent) throw new Error('all-node index did not expose a non-adjacent inspection target');
            nonAdjacent.click();
            await delay(20);
            if (Number(root.getAttribute('data-selected-piece-count')) !== selectedCount) throw new Error('non-adjacent target cleared the group');
            if (document.querySelector('[data-region="live"]').textContent.indexOf('不相邻') < 0) throw new Error('non-adjacent target reason was not announced');
            document.querySelector('[data-action="toggle-node-scope"]')?.click();
            await delay(20);
            var invalid = document.querySelector('.warlord-node-card[data-command-state="invalid"]');
            if (invalid) {
                invalid.click();
                await delay(20);
                if (Number(root.getAttribute('data-selected-piece-count')) !== selectedCount) throw new Error('invalid target cleared the group');
                if (document.querySelector('[data-region="live"]').textContent.indexOf('无法向') < 0) throw new Error('invalid target reason was not announced');
            }
            var target = document.querySelector('.warlord-node-card[data-command-state="move"], .warlord-node-card[data-command-state="partial"]');
            if (!target) throw new Error('no legal non-battle direct target');
            var targetId = target.getAttribute('data-node');
            var targetPoint = findCanvasPoint(canvas, host, function (surface) {
                return surface.getAttribute('data-hovered-node') === targetId
                    && surface.getAttribute('data-hovered-piece') === '';
            });
            if (!targetPoint) throw new Error('could not ray-pick legal node ' + targetId);
            clickCanvas(canvas, targetPoint, 94);
            await delay(100);
            if (root.getAttribute('data-selected-node') !== targetId) throw new Error('canvas node click did not execute direct movement');
            var movedCount = Number(root.getAttribute('data-selected-piece-count'));
            var live = document.querySelector('[data-region="live"]');
            if (movedCount < 1 || !live || live.textContent.indexOf('保持选中') < 0) throw new Error('surviving command group did not follow the move');
            var chain = document.querySelector('.warlord-node-card[data-command-state="move"], .warlord-node-card[data-command-state="partial"]');
            if (!chain) throw new Error('followed group has no chained legal move');
            var chainTarget = chain.getAttribute('data-node');
            chain.click();
            await delay(80);
            if (root.getAttribute('data-selected-node') !== chainTarget || Number(root.getAttribute('data-selected-piece-count')) < 1) {
                throw new Error('second direct command did not preserve the followed group');
            }
            canvas.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(20);
            if (root.getAttribute('data-selected-piece-count') !== '0' || document.querySelector('.warlord-command-intent:not([hidden])')) {
                throw new Error('Escape did not return node clicks to inspection mode');
            }
            return 'Shift marquee ' + marqueeCount + ' · command group ' + selectedCount + ' · non-adjacent retained · canvas direct ' + targetId + ' · chained ' + chainTarget + (invalid ? ' · invalid retained' : '');
        });
        await check('visible-feedback-toast', async function () {
            var toast = document.querySelector('[data-region="toast"]');
            var live = document.querySelector('[data-region="live"]');
            var canvas = document.querySelector('.warlord-sandtable-canvas');
            if (!toast || !live || !canvas) throw new Error('visible toast surface missing');
            var box = document.querySelector('.warlord-piece input[data-field="piece"]:not(:disabled)');
            if (!box) throw new Error('no selectable piece for the toast gate');
            box.checked = true;
            box.dispatchEvent(new Event('change', { bubbles: true }));
            await delay(20);
            document.querySelector('[data-action="toggle-node-scope"]')?.click();
            await delay(20);
            var far = document.querySelector('.warlord-node-card[data-command-state="none"]:not(.selected)');
            if (!far) throw new Error('no non-adjacent node for the toast gate');
            far.click();
            await delay(20);
            if (live.textContent.indexOf('不相邻') < 0) throw new Error('blocked reason not announced');
            if (toast.hidden || toast.textContent !== live.textContent) {
                throw new Error('blocked notice did not surface on the visible toast');
            }
            if (!toast.classList.contains('is-error')) throw new Error('blocked notice did not use the error tone');
            canvas.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(20);
            if (toast.hidden || toast.classList.contains('is-error') || toast.textContent !== live.textContent) {
                throw new Error('info notice did not replace the error toast in the neutral tone');
            }
            document.querySelector('[data-action="toggle-node-scope"]')?.click();
            await delay(20);
            return 'blocked=error tone · Esc cancel=neutral · toast mirrors live';
        });
        await check('form-controls-suppress-global-shortcuts', async function () {
            var toggle = document.querySelector('[data-action="toggle-config"]');
            if (!toggle) throw new Error('config toggle missing');
            toggle.click();
            await delay(20);
            var seed = document.querySelector('[data-field="seed"]');
            var root = document.querySelector('.warlord-scale-shell');
            if (!seed || !root) throw new Error('seed input or runtime root missing');
            var phaseBefore = root.getAttribute('data-phase');
            seed.focus();
            var event = new KeyboardEvent('keydown', { key: 'e', bubbles: true, cancelable: true });
            seed.dispatchEvent(event);
            await delay(40);
            if (event.defaultPrevented) throw new Error('editable key was intercepted');
            if (root.getAttribute('data-phase') !== phaseBefore) throw new Error('editable e shortcut ended the action');
            seed.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(20);
            if (!document.querySelector('[data-region="config"][hidden]')) throw new Error('Escape did not close config');
            return 'input e ignored · Escape retained';
        });
        await check('portrait-resolver-eight-identities', async function () {
            var root = await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-portraits-ready="true"]'); }, 12000);
            var cards = Array.from(root.querySelectorAll('.warlord-card-portrait[data-warlord-portrait]'));
            var refs = new Set(cards.map(function (node) {
                return node.getAttribute('data-portrait-ref');
            }));
            var accepted = cards.filter(function (node) {
                var source = node.getAttribute('data-portrait-source');
                return source === 'svg' || source === 'png';
            });
            if (cards.length !== 8 || refs.size !== 8) throw new Error('expected 8 resolved portrait identities, found ' + refs.size);
            if (accepted.length !== 8) throw new Error('accepted modern portrait sources ' + accepted.length + '/8');
            return '8/8 human-accepted manifest art';
        });
        await check('fixed-canvas-no-overflow', async function () {
            var stage = document.getElementById('harness-stage');
            if (!stage || stage.scrollWidth > stage.clientWidth || stage.scrollHeight > stage.clientHeight) {
                throw new Error('1024x576 stage overflow');
            }
            return stage.clientWidth + 'x' + stage.clientHeight;
        });
        await check('action-scroll-keeps-end-action-visible', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.open({ seed: 'qa-action-scroll' });
            await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            var rail = document.querySelector('.warlord-action-rail[data-mode="action"]');
            var scroller = rail && rail.querySelector('[data-region="action-scroll"]');
            var routes = scroller && scroller.querySelector('.warlord-route-actions');
            var end = rail && rail.querySelector('[data-action="end-action"]');
            if (!rail || !scroller || !routes || !end) throw new Error('action rail scroll structure is incomplete');
            for (var index = 0; index < 14; index += 1) {
                var stress = document.createElement('button');
                stress.type = 'button';
                stress.disabled = true;
                stress.setAttribute('data-layout-stress', 'true');
                stress.innerHTML = '<b>压力节点 ' + (index + 1) + '</b><span>大量可选节点滚动验证</span>';
                routes.appendChild(stress);
            }
            await delay(20);
            var railRect = rail.getBoundingClientRect();
            var endRect = end.getBoundingClientRect();
            var overflowY = getComputedStyle(scroller).overflowY;
            if (overflowY !== 'auto' || scroller.scrollHeight <= scroller.clientHeight) {
                throw new Error('action list did not expose native vertical scrolling under stress');
            }
            if (endRect.top < railRect.top || endRect.bottom > railRect.bottom + 0.5) {
                throw new Error('end action left the visible action rail before scrolling');
            }
            var endTopBefore = endRect.top;
            scroller.scrollTop = scroller.scrollHeight;
            await delay(20);
            var endTopAfter = end.getBoundingClientRect().top;
            if (scroller.scrollTop <= 0 || Math.abs(endTopAfter - endTopBefore) > 0.5) {
                throw new Error('scrolling optional node actions moved the fixed end-action footer');
            }
            Array.from(routes.querySelectorAll('[data-layout-stress="true"]')).forEach(function (node) { node.remove(); });
            scroller.scrollTop = 0;
            return 'native scrollbar · 14 stress nodes · end action fixed';
        });
        await check('dispose-reopen-generation-fence', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.open({ seed: 'qa-reopen-seed' });
            var root = await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            if (root.getAttribute('data-selected-node') !== 'R-HQ') throw new Error('reopen state not reset');
            return 'closed and reopened';
        });
        await check('full-action-planning-production-loop', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.open({ preset: 'all-units', seed: 'qa-full-loop' });
            await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            var end = document.querySelector('[data-action="end-action"]:not(:disabled)');
            if (!end) throw new Error('end action unavailable');
            end.click();
            await waitFor(function () {
                var root = document.querySelector('.warlord-scale-shell');
                return root && root.getAttribute('data-phase') === 'SETTLEMENT_PLANNING';
            }, 24000);
            var cameraZoom = document.querySelector('[data-action="camera-zoom-in"]');
            if (cameraZoom) cameraZoom.click();
            await delay(30);
            var mapStage = document.querySelector('.warlord-map-stage');
            var planningLayer = document.querySelector('.warlord-planning-layer:not([hidden])');
            var cameraHud = document.querySelector('.warlord-camera-hud[data-expanded="true"]');
            if (!mapStage || !planningLayer || !cameraHud) throw new Error('planning or expanded camera surface missing');
            var mapRect = mapStage.getBoundingClientRect();
            var planningRect = planningLayer.getBoundingClientRect();
            var cameraRect = cameraHud.getBoundingClientRect();
            var overlapX = Math.max(0, Math.min(planningRect.right, cameraRect.right) - Math.max(planningRect.left, cameraRect.left));
            var overlapY = Math.max(0, Math.min(planningRect.bottom, cameraRect.bottom) - Math.max(planningRect.top, cameraRect.top));
            if (overlapX > 0 && overlapY > 0) throw new Error('expanded camera surface overlaps settlement planning');
            if (Math.abs(mapRect.right - cameraRect.right) > 11) throw new Error('camera surface is not pinned to the tactical upper-right slot');
            var skip = document.querySelector('[data-action="battle-skip"]');
            if (skip) {
                skip.click();
                await delay(20);
                var close = document.querySelector('[data-action="battle-close"]:not(:disabled)');
                if (close) close.click();
            }
            var nonProduction = document.querySelector('[data-testid="node-Center-Command"]');
            if (!nonProduction) throw new Error('Center-Command missing');
            nonProduction.click();
            await delay(40);
            var xp = document.querySelector('[data-action="allocate-xp"]:not(:disabled)');
            var production = document.querySelector('[data-action="production"]:not(:disabled)');
            if (!xp || !production) throw new Error('planning upgrade or production action unavailable');
            var consoleBefore = document.querySelector('.warlord-production-console[data-mode="auto"]');
            if (!consoleBefore || document.querySelector('[data-field="slot"]')) {
                throw new Error('default automatic production console is missing or legacy slot radios remain');
            }
            xp.click();
            await delay(30);
            var promotion = document.querySelector('[data-action="promotion"]:not(:disabled)');
            if (promotion) promotion.click();
            await delay(30);
            production = document.querySelector('[data-action="production"]:not(:disabled)');
            if (!production) throw new Error('production became unavailable unexpectedly');
            var orderCountBefore = Number(consoleBefore.getAttribute('data-order-count'));
            production.click();
            await delay(40);
            var consoleAfter = document.querySelector('.warlord-production-console[data-mode="auto"]');
            var queuedLane = consoleAfter && consoleAfter.querySelector('[data-queue-length="1"]');
            var live = document.querySelector('[data-region="live"]');
            if (!consoleAfter || Number(consoleAfter.getAttribute('data-order-count')) !== orderCountBefore + 1 || !queuedLane) {
                throw new Error('one-click automatic production was not projected into a lane');
            }
            if (!live || live.textContent.indexOf('自动调度') < 0) throw new Error('automatic destination receipt is not visible');
            var network = consoleAfter.querySelector('.warlord-production-network');
            var networkOrder = network && network.querySelector('[data-action="inspect-production-order"]');
            if (!network || network.getAttribute('data-total-orders') !== String(orderCountBefore + 1)
                || network.getAttribute('data-visible-orders') !== String(orderCountBefore + 1)
                || !networkOrder || !networkOrder.querySelector('[data-warlord-portrait] img')) {
                throw new Error('network production portrait projection is incomplete');
            }
            var iconNode = networkOrder.getAttribute('data-node');
            var productionNodeSelect = consoleAfter.querySelector('[data-field="production-node"]');
            var otherNode = productionNodeSelect && Array.from(productionNodeSelect.options).find(function (option) {
                return option.value !== iconNode;
            });
            if (otherNode) {
                productionNodeSelect.value = otherNode.value;
                productionNodeSelect.dispatchEvent(new Event('change', { bubbles: true }));
                await delay(20);
                networkOrder = document.querySelector('[data-action="inspect-production-order"]');
                networkOrder.click();
                await delay(20);
                var located = document.querySelector('.warlord-production-console[data-mode="auto"]');
                if (!located || located.getAttribute('data-production-node') !== iconNode
                    || Number(located.getAttribute('data-order-count')) !== orderCountBefore + 1) {
                    throw new Error('network order icon did not locate its lane without mutating the queue or mode');
                }
                consoleAfter = located;
            }
            var undo = consoleAfter.querySelector('[data-action="cancel-production"][data-cancellable="true"]');
            if (!undo || undo.textContent.indexOf('撤销') < 0) throw new Error('unstarted production order has no visible cancellation affordance');
            undo.click();
            await waitFor(function () {
                var current = document.querySelector('.warlord-production-console[data-mode="auto"]');
                return current && Number(current.getAttribute('data-order-count')) === orderCountBefore;
            }, 3000);
            if (!live || live.textContent.indexOf('返还') < 0 || live.textContent.indexOf('释放') < 0) {
                throw new Error('production cancellation refund receipt is not observable');
            }
            production = document.querySelector('[data-action="production"]:not(:disabled)');
            if (!production) throw new Error('refunded production action did not become available');
            production.click();
            consoleAfter = await waitFor(function () {
                var current = document.querySelector('.warlord-production-console[data-mode="auto"]');
                return current && Number(current.getAttribute('data-order-count')) === orderCountBefore + 1 ? current : null;
            }, 3000);
            var modeToggle = consoleAfter.querySelector('[data-action="toggle-production-mode"]');
            if (!modeToggle) throw new Error('exact-slot control toggle missing');
            modeToggle.click();
            await delay(20);
            var exactConsole = document.querySelector('.warlord-production-console[data-mode="exact"]');
            var exactLanes = exactConsole && exactConsole.querySelectorAll('[data-action="choose-production-slot"]');
            if (!exactConsole || !exactLanes || exactLanes.length !== 2) throw new Error('exact-slot control did not expand');
            var exactOrderCount = Number(exactConsole.getAttribute('data-order-count'));
            exactLanes[1].click();
            await delay(20);
            if (!document.querySelector('.warlord-production-console[data-mode="exact"] [data-action="choose-production-slot"][aria-pressed="true"]')) {
                throw new Error('exact lane selection is not observable');
            }
            if (Number(document.querySelector('.warlord-production-console[data-mode="exact"]')?.getAttribute('data-order-count')) !== exactOrderCount) {
                throw new Error('selecting an exact lane unexpectedly created or removed an order');
            }
            var commit = document.querySelector('[data-action="commit-planning"]:not(:disabled)');
            if (!commit) throw new Error('commit planning unavailable');
            commit.click();
            return 'action -> AI -> settlement -> auto production portrait -> order-icon locate -> full-refund undo -> exact lane selection without enqueue -> commit';
        });
        await check('attack-arm-then-confirm', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.open({ preset: 'all-units', seed: 'qa-arm-confirm' });
            var root = await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            // 全兵种预设下蓝方在 North-Choke 驻军，与 R-Supply 相邻，首回合即可构造攻击目标
            document.querySelector('[data-action="toggle-node-scope"]')?.click();
            await delay(20);
            var supplyCard = document.querySelector('[data-testid="node-R-Supply"]');
            if (!supplyCard) throw new Error('R-Supply card missing in the all-node index');
            supplyCard.click();
            await delay(20);
            var selectAll = document.querySelector('[data-action="select-all-at-node"]:not(:disabled)');
            if (!selectAll) throw new Error('select-all affordance missing');
            selectAll.click();
            await delay(20);
            if (root.getAttribute('data-selected-piece-count') !== '3') {
                throw new Error('select-all did not group the R-Supply garrison: ' + root.getAttribute('data-selected-piece-count'));
            }
            var boxes = document.querySelectorAll('.warlord-piece input[data-field="piece"]:checked');
            var trim = boxes[boxes.length - 1];
            trim.checked = false;
            trim.dispatchEvent(new Event('change', { bubbles: true }));
            await delay(20);
            var attack = document.querySelector('.warlord-node-card[data-command-state="attack"]');
            if (!attack) throw new Error('no attack preview against the North-Choke garrison');
            attack.click();
            await delay(30);
            if (document.querySelector('.warlord-battle-layer:not([hidden])')) {
                throw new Error('first click executed the attack without confirmation');
            }
            var intent = document.querySelector('.warlord-command-intent:not([hidden])');
            if (!intent || intent.getAttribute('data-armed-target') !== 'North-Choke'
                || !intent.classList.contains('is-armed')) {
                throw new Error('attack target was not armed on the intent bar');
            }
            if (document.querySelector('[data-region="live"]').textContent.indexOf('再次点击确认进攻') < 0) {
                throw new Error('arm notice was not announced');
            }
            attack = document.querySelector('.warlord-node-card[data-command-state="attack"]');
            attack.click();
            await delay(40);
            var layer = document.querySelector('.warlord-battle-layer:not([hidden])');
            if (!layer) throw new Error('confirmed click did not open battle playback');
            var canvas = document.querySelector('.warlord-sandtable-canvas');
            canvas.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(30);
            if (!document.querySelector('[data-action="battle-close"]:not(:disabled)')) {
                throw new Error('Escape did not skip playback to the settlement point');
            }
            canvas.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(30);
            if (document.querySelector('.warlord-battle-layer:not([hidden])')) {
                throw new Error('second Escape did not close battle playback');
            }
            return 'select-all 3 -> trim 2 · arm -> confirm -> playback -> Esc skip -> Esc close';
        });
        await check('forced-webgl-fallback-remains-operable', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.open({ forceWebglFailure: true });
            var fallback = await waitFor(function () { return document.querySelector('.warlord-map-fallback:not([hidden])'); }, 12000);
            var nodes = fallback.querySelectorAll('[data-action="select-node"]');
            if (nodes.length !== 9) throw new Error('fallback node count ' + nodes.length);
            nodes[4].click();
            await delay(20);
            return '9-node DOM fallback';
        });

        window.__warlordHarness.close();
        await delay(20);
        window.__warlordHarness.open();
        var output = document.getElementById('qa-results');
        output.innerHTML = results.map(function (result) {
            return '<div data-pass="' + result.pass + '">' + (result.pass ? 'PASS' : 'FAIL') + ' · '
                + result.name + (result.detail ? ' · ' + result.detail : '') + '</div>';
        }).join('');
        var failed = results.filter(function (result) { return !result.pass; });
        document.documentElement.setAttribute('data-warlord-qa', failed.length ? 'failed' : 'passed');
        window.__WARLORD_QA_RESULTS__ = results;
        return results;
    }

    if (new URLSearchParams(location.search).get('qa') === '1') {
        window.addEventListener('load', function () { void run(); });
    }
    window.runWarlordBrowserQa = run;
})();
