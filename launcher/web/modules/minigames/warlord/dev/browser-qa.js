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

    function installGraphicsLifecycleProbe() {
        var nativeRequestAnimationFrame = window.requestAnimationFrame;
        var nativeCancelAnimationFrame = window.cancelAnimationFrame;
        var nativeGetContext = HTMLCanvasElement.prototype.getContext;
        var activeFrames = new Set();
        var requestedFrames = 0;
        var completedFrames = 0;
        var cancelledFrames = 0;
        var createdWebglCanvases = 0;
        var lostWebglContexts = 0;

        function qaRequestAnimationFrame(callback) {
            var handle = nativeRequestAnimationFrame.call(window, function (time) {
                activeFrames.delete(handle);
                completedFrames += 1;
                callback.call(window, time);
            });
            requestedFrames += 1;
            activeFrames.add(handle);
            return handle;
        }
        function qaCancelAnimationFrame(handle) {
            if (activeFrames.delete(handle)) cancelledFrames += 1;
            nativeCancelAnimationFrame.call(window, handle);
        }
        function qaGetContext(contextId) {
            var context = nativeGetContext.apply(this, arguments);
            if (context && /^webgl2?$/i.test(String(contextId || ''))
                && this.getAttribute('data-qa-webgl-context') !== 'true') {
                this.setAttribute('data-qa-webgl-context', 'true');
                createdWebglCanvases += 1;
                this.addEventListener('webglcontextlost', function () {
                    lostWebglContexts += 1;
                }, { once: true });
            }
            return context;
        }
        window.requestAnimationFrame = qaRequestAnimationFrame;
        window.cancelAnimationFrame = qaCancelAnimationFrame;
        HTMLCanvasElement.prototype.getContext = qaGetContext;

        var probe = {
            activeFrameCount: function () { return activeFrames.size; },
            snapshot: function () {
                return {
                    activeFrames: activeFrames.size,
                    requestedFrames: requestedFrames,
                    completedFrames: completedFrames,
                    cancelledFrames: cancelledFrames,
                    createdWebglCanvases: createdWebglCanvases,
                    lostWebglContexts: lostWebglContexts,
                    activeWebglContexts: createdWebglCanvases - lostWebglContexts,
                    connectedWebglCanvases: document.querySelectorAll('canvas[data-qa-webgl-context="true"]').length
                };
            },
            dispose: function () {
                if (window.requestAnimationFrame === qaRequestAnimationFrame) {
                    window.requestAnimationFrame = nativeRequestAnimationFrame;
                }
                if (window.cancelAnimationFrame === qaCancelAnimationFrame) {
                    window.cancelAnimationFrame = nativeCancelAnimationFrame;
                }
                if (HTMLCanvasElement.prototype.getContext === qaGetContext) {
                    HTMLCanvasElement.prototype.getContext = nativeGetContext;
                }
                if (window.__WARLORD_QA_GRAPHICS_PROBE__ === probe) {
                    delete window.__WARLORD_QA_GRAPHICS_PROBE__;
                }
            }
        };
        window.__WARLORD_QA_GRAPHICS_PROBE__ = probe;
        return probe;
    }

    function assertPlayerVocabulary(surface) {
        if (!surface) throw new Error('player vocabulary surface missing');
        function visiblePlayerElement(element) {
            if (!element || element.closest('[hidden], [aria-hidden="true"], [data-region="config"], script, style')) return false;
            var style = getComputedStyle(element);
            return style.display !== 'none' && style.visibility !== 'hidden' && element.getClientRects().length > 0;
        }
        var values = [];
        var walker = document.createTreeWalker(surface, NodeFilter.SHOW_TEXT);
        var textNode;
        while ((textNode = walker.nextNode())) {
            var copy = String(textNode.nodeValue || '').trim();
            if (copy && visiblePlayerElement(textNode.parentElement)) values.push(copy);
        }
        Array.from(surface.querySelectorAll('[aria-label], [title]')).filter(visiblePlayerElement).forEach(function (element) {
            values.push(element.getAttribute('aria-label') || '');
            values.push(element.getAttribute('title') || '');
        });
        var copy = values.join('\n');
        var engineering = /\b(?:AP|AUTO|EXACT|AS2|Launcher|WebGL|fixture|XP|MAX)\b|\bLv\.|(?:^|[\s·，：/])(?:R|B)\d|(?:^|[\s·，：/])\d+G(?:$|[\s·，。；/)])/m;
        var rawIdentity = /\b(?:red|blue)-card-\d+|\bbattle[.:_-][a-z0-9_-]+|\b(?:round_start|sniper_volley|battle_end)\b/i;
        if (engineering.test(copy)) throw new Error('engineering vocabulary leaked into player copy: ' + copy.match(engineering)[0]);
        if (rawIdentity.test(copy)) throw new Error('raw identity leaked into player copy: ' + copy.match(rawIdentity)[0]);
        if (/[A-Za-z]/.test(copy)) throw new Error('Latin text leaked into visible player copy: ' + copy.match(/[A-Za-z]+/)[0]);
        return values.length;
    }

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

        async function confirmPlayerAttackFromSupply(root) {
            var navigator = document.querySelector('.warlord-node-strip');
            if (!navigator) throw new Error('node navigator missing');
            if (navigator.getAttribute('data-mode') !== 'all') {
                var scope = navigator.querySelector('[data-action="toggle-node-scope"]');
                if (!scope) throw new Error('node scope toggle missing');
                scope.click();
                await delay(20);
            }
            var supplyCard = document.querySelector('[data-testid="node-R-Supply"]');
            if (!supplyCard) throw new Error('R-Supply card missing in the all-node index');
            supplyCard.click();
            await delay(20);
            var selectAll = document.querySelector('[data-action="select-all-at-node"]:not(:disabled)');
            if (!selectAll) throw new Error('select-all affordance missing');
            selectAll.click();
            await delay(20);
            var boxes = document.querySelectorAll('.warlord-piece input[data-field="piece"]:checked');
            if (boxes.length !== 3 || root.getAttribute('data-selected-piece-count') !== '3') {
                throw new Error('R-Supply retry fixture did not select three pieces');
            }
            var trim = boxes[boxes.length - 1];
            trim.checked = false;
            trim.dispatchEvent(new Event('change', { bubbles: true }));
            await delay(20);
            var attack = document.querySelector('.warlord-node-card[data-command-state="attack"]');
            if (!attack) throw new Error('North-Choke attack preview missing');
            attack.click();
            await delay(30);
            attack = document.querySelector('.warlord-node-card[data-command-state="attack"]');
            if (!attack) throw new Error('armed North-Choke attack preview missing');
            attack.click();
        }

        async function buildAcceptedAs2ResumeFixture() {
            var modules = await Promise.all([
                import('../runtime/core/state.js'),
                import('../runtime/core/pieces.js'),
                import('../runtime/core/factions.js'),
                import('../runtime/battle/as2-authority.js'),
                import('../runtime/data/cards.js')
            ]);
            var state = modules[0].createGame({ seed: 'qa-as2-settled-lifecycle', preset: 'standard', difficulty: 'normal' });
            Object.keys(state.pieces).forEach(function (pieceId) { modules[1].removePieceInPlace(state, pieceId); });
            modules[1].createPieceInPlace(state, 'red', 12, 'R-Supply', 1, { pieceId: 'pet-red-12' });
            modules[1].createPieceInPlace(state, 'blue', 15, 'North-Choke', 1, { pieceId: 'pet-blue-15' });
            state.phase = 'FIRST_FACTION_ACTION';
            state.initiativeFactionId = 'red';
            state.activeFactionId = 'red';
            var red = modules[2].requireFaction(state, 'red');
            red.apLedger = {
                baseGenerated: 4, baseRemaining: 4, baseSpent: 0,
                fieldGenerated: 0, fieldRemaining: 0, fieldSpent: 0
            };
            red.actionPoints = 4;
            red.apGeneratedThisRound = 4;
            red.apSpentThisRound = 0;
            var command = {
                type: 'MOVE_OR_ATTACK', factionId: 'red', pieceIds: ['pet-red-12'],
                originNodeId: 'R-Supply', targetNodeId: 'North-Choke'
            };
            var envelope = await modules[3].buildAs2BattleEnvelope({
                panelInstanceId: 'warlord.panel.qa-settled-lifecycle',
                callId: 'warlord.call.qa-settled-lifecycle',
                sessionId: 'warlord.session.qa-settled-lifecycle',
                requestId: 'warlord.request.qa-settled-lifecycle',
                state: state,
                command: command,
                clientContext: {
                    seed: state.gameSeed,
                    preset: state.preset,
                    difficulty: state.difficulty,
                    mapTheme: 'desert',
                    forceWebglFailure: false,
                    aiSeenTransitions: []
                }
            });
            var attackerDefinition = modules[4].getCardDefinition(12);
            var defenderDefinition = modules[4].getCardDefinition(15);
            return {
                schema: 'warlord.as2-resume.v1',
                request: structuredClone(envelope.request),
                state: structuredClone(envelope.request.state),
                command: structuredClone(envelope.request.command),
                inputDigest: envelope.inputDigest,
                clientContext: structuredClone(envelope.request.clientContext),
                receipt: {
                    schema: 'warlord.as2-battle-receipt.v2',
                    status: 'accepted',
                    sessionId: envelope.request.sessionId,
                    requestId: envelope.request.requestId,
                    inputDigest: envelope.inputDigest,
                    petProjectionProfile: 'catalog_identifier+strategic_progression_v1',
                    playerPetSnapshotUsed: false,
                    participantProjectionProfile: 'discriminated_player_avatar+catalog_pet_v1',
                    playerAvatarProjectionProfile: 'trusted_demo2_commander_v1',
                    playerPersistentSnapshotUsed: false,
                    playerControlledSide: 'none',
                    as2Status: 'finished',
                    as2Winner: 'blue',
                    sideMap: { blue: 'attacker', red: 'defender' },
                    frames: 180,
                    durationMs: 6000,
                    attackerUnits: [{
                        pieceId: 'pet-red-12', factionId: 'red', projectionKind: 'pet_projection',
                        petId: 12, identifier: attackerDefinition.identifier, level: 1,
                        strategicPromotions: [], resolvedType: attackerDefinition.identifier,
                        startMaxHp: 1000, remainHp: 625, hpPermille: 625, alive: true
                    }],
                    defenderUnits: [{
                        pieceId: 'pet-blue-15', factionId: 'blue', projectionKind: 'pet_projection',
                        petId: 15, identifier: defenderDefinition.identifier, level: 1,
                        strategicPromotions: [], resolvedType: defenderDefinition.identifier,
                        startMaxHp: 1000, remainHp: 0, hpPermille: 0, alive: false
                    }],
                    economyObservation: {
                        schema: 'warlord.pet-economy-observation.v1', mode: 'observe_only', writesPlayerState: false,
                        settlementPolicy: 'none', catalogAuthority: 'data/merc/pets.xml',
                        catalogPriceBasis: 'xml_base_price', currentAs2SessionPriceSampled: false,
                        strategicValueBasis: 'piece.productionGoldValue', catalogCurrencyUnit: 'player_gold',
                        strategicCurrencyUnit: 'warlord_gold',
                        attacker: {
                            catalogBaseExposureGold: 8000, catalogBaseLostGold: 0,
                            catalogBaseExposureK: 0, catalogBaseLostK: 0,
                            strategicExposureGold: 8, strategicLostGold: 0,
                            units: [{
                                pieceId: 'pet-red-12', projectionKind: 'pet_projection', petId: 12,
                                identifier: attackerDefinition.identifier, catalogName: attackerDefinition.displayName,
                                rosterType: 'pet', catalogEligible: true, strategicPromotions: [],
                                strategicGoldValue: 8, basePrice: 8000, kPrice: 0, increasePrice: 0,
                                hpPermille: 625, lost: false
                            }]
                        },
                        defender: {
                            catalogBaseExposureGold: 10000, catalogBaseLostGold: 10000,
                            catalogBaseExposureK: 0, catalogBaseLostK: 0,
                            strategicExposureGold: 60, strategicLostGold: 60,
                            units: [{
                                pieceId: 'pet-blue-15', projectionKind: 'pet_projection', petId: 15,
                                identifier: defenderDefinition.identifier, catalogName: defenderDefinition.displayName,
                                rosterType: 'pet', catalogEligible: true, strategicPromotions: [],
                                strategicGoldValue: 60, basePrice: 10000, kPrice: 0, increasePrice: 0,
                                hpPermille: 0, lost: true
                            }]
                        }
                    }
                }
            };
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
        await check('eight-card-roster-and-collapse', async function () {
            var app = document.querySelector('.warlord-app');
            var main = app && app.querySelector('.warlord-main');
            var roster = app && app.querySelector('.warlord-roster');
            var sceneHost = app && app.querySelector('.warlord-scene-host');
            var toggle = roster && roster.querySelector('[data-action="toggle-roster"]');
            var track = roster && roster.querySelector('#warlord-roster-cards');
            if (!app || !main || !roster || !sceneHost || !toggle || !track) {
                throw new Error('roster collapse surface is incomplete');
            }
            var cards = roster.querySelectorAll('.warlord-card[data-testid^="card-"]');
            if (cards.length !== 8) throw new Error('expected 8 cards, found ' + cards.length);
            if (app.getAttribute('data-roster-collapsed') !== 'false'
                || toggle.getAttribute('aria-expanded') !== 'true' || track.hidden) {
                throw new Error('roster did not start expanded');
            }
            var expandedMainHeight = main.getBoundingClientRect().height;
            var expandedRosterHeight = roster.getBoundingClientRect().height;
            var expandedSceneHeight = sceneHost.getBoundingClientRect().height;
            toggle.click();
            await waitFor(function () {
                return app.getAttribute('data-roster-collapsed') === 'true'
                    && roster.getAttribute('data-collapsed') === 'true';
            }, 1000);
            await delay(20);
            var collapsedToggle = roster.querySelector('[data-action="toggle-roster"]');
            var collapsedTrack = roster.querySelector('#warlord-roster-cards');
            var collapsedMainHeight = main.getBoundingClientRect().height;
            var collapsedRosterHeight = roster.getBoundingClientRect().height;
            var collapsedSceneHeight = sceneHost.getBoundingClientRect().height;
            if (!collapsedToggle || !collapsedTrack || collapsedToggle.getAttribute('aria-expanded') !== 'false'
                || !collapsedTrack.hidden || document.activeElement !== collapsedToggle) {
                throw new Error('collapsed roster did not preserve ARIA, focus and hidden content semantics');
            }
            if (Math.abs(collapsedRosterHeight - 32) > 0.75
                || collapsedMainHeight < expandedMainHeight + 87
                || collapsedSceneHeight < expandedSceneHeight + 87
                || collapsedToggle.getBoundingClientRect().height < 26
                || roster.scrollWidth > roster.clientWidth || roster.scrollHeight > roster.clientHeight) {
                throw new Error('collapsed roster did not return 88px to the map without overflow');
            }
            collapsedToggle.click();
            await waitFor(function () { return app.getAttribute('data-roster-collapsed') === 'false'; }, 1000);
            await delay(20);
            var restoredToggle = roster.querySelector('[data-action="toggle-roster"]');
            if (!restoredToggle || restoredToggle.getAttribute('aria-expanded') !== 'true'
                || Math.abs(main.getBoundingClientRect().height - expandedMainHeight) > 0.75
                || Math.abs(roster.getBoundingClientRect().height - expandedRosterHeight) > 0.75
                || roster.querySelectorAll('.warlord-card[data-testid^="card-"]').length !== 8) {
                throw new Error('expanded roster did not restore the eight-card layout');
            }
            return '120px -> 32px · map +88px · focus and ARIA preserved';
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
            var root = document.querySelector('.warlord-scale-shell');
            var app = document.querySelector('.warlord-app');
            var host = document.querySelector('.warlord-scene-host');
            var main = app && app.querySelector('.warlord-main');
            var roster = app && app.querySelector('.warlord-roster');
            var forceRail = app && app.querySelector('.warlord-force-rail');
            var forceList = forceRail && forceRail.querySelector('.warlord-force-list');
            var nodeFacts = forceRail && forceRail.querySelector('.warlord-node-facts');
            var piece = document.querySelector('.warlord-piece input[data-field="piece"]:not(:disabled)');
            var helpButton = document.querySelector('[data-action="open-help"]');
            if (!root || !app || !host || !main || !roster || !forceRail || !forceList || !nodeFacts || !piece || !helpButton) {
                throw new Error('compact layout or help preservation setup missing');
            }
            var mainRect = main.getBoundingClientRect();
            var rosterRect = roster.getBoundingClientRect();
            var forceListRect = forceList.getBoundingClientRect();
            var nodeFactsRect = nodeFacts.getBoundingClientRect();
            if (Math.abs(mainRect.height - 398) > 0.75 || Math.abs(rosterRect.height - 120) > 0.75) {
                throw new Error('logical main/roster rows drifted from 398/120: ' + mainRect.height + '/' + rosterRect.height);
            }
            if (forceListRect.height < 250 || getComputedStyle(forceList).overflowY !== 'auto'
                || forceListRect.bottom > nodeFactsRect.top + 0.75) {
                throw new Error('returned roster height did not become a bounded force-list scroll region: ' + forceListRect.height);
            }
            var cardPortraits = Array.from(roster.querySelectorAll('.warlord-card-portrait'));
            var cardButtons = Array.from(roster.querySelectorAll('.warlord-card-actions button'));
            if (cardPortraits.length !== 8 || cardPortraits.some(function (portrait) {
                return portrait.getBoundingClientRect().height < 63;
            })) throw new Error('blueprint portraits became unreadably short');
            if (cardButtons.length !== 24 || cardButtons.some(function (button) {
                var buttonRect = button.getBoundingClientRect();
                var cardRect = button.closest('.warlord-card').getBoundingClientRect();
                return buttonRect.height < 24 || buttonRect.width < 20
                    || buttonRect.bottom > cardRect.bottom + 0.75 || buttonRect.right > cardRect.right + 0.75;
            })) throw new Error('one or more blueprint actions are clipped or unreachable');
            piece.checked = true;
            piece.dispatchEvent(new Event('change', { bubbles: true }));
            await delay(20);
            var preserved = [
                root.getAttribute('data-phase'),
                root.getAttribute('data-selected-node'),
                root.getAttribute('data-selected-piece-count'),
                host.getAttribute('data-camera-x'),
                host.getAttribute('data-camera-z'),
                host.getAttribute('data-camera-zoom')
            ].join('|');
            helpButton.focus();
            helpButton.click();
            await delay(30);
            var dialog = document.querySelector('.warlord-help-dialog');
            var close = dialog && dialog.querySelector('[data-action="close-help"]');
            if (!dialog || !close || document.activeElement !== close) throw new Error('help did not open with initial focus on close');
            if (dialog.textContent.indexOf('这关怎样获胜') < 0 || dialog.textContent.indexOf('本次最多投入') < 0) {
                throw new Error('help profile is missing core player rules');
            }
            var actionPoints = dialog.querySelector('[data-help-anchor="action-points"]');
            actionPoints.click();
            await delay(30);
            var current = document.querySelector('[data-help-current][data-help-section="action-points"]');
            if (!current || document.activeElement !== current) throw new Error('help section navigation did not move focus to content');
            current.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(30);
            if (!document.querySelector('[data-region="help"][hidden]') || document.activeElement !== helpButton) {
                throw new Error('Escape did not close help and restore trigger focus');
            }
            var afterHelp = [
                root.getAttribute('data-phase'),
                root.getAttribute('data-selected-node'),
                root.getAttribute('data-selected-piece-count'),
                host.getAttribute('data-camera-x'),
                host.getAttribute('data-camera-z'),
                host.getAttribute('data-camera-zoom')
            ].join('|');
            if (afterHelp !== preserved) throw new Error('help changed game, selection or camera state');
            var vocabularyCount = assertPlayerVocabulary(app);
            window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(20);
            return '398/120 layout · force scroll ' + Math.round(forceListRect.height) + 'px · 8/8 readable cards · help focus/state preserved · vocabulary ' + vocabularyCount;
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
            try {
                await waitFor(function () { return hud.getAttribute('data-expanded') === 'true'; }, 1200);
            } catch (error) {
                throw new Error('camera activity did not expand the HUD: expanded=' + hud.getAttribute('data-expanded'));
            }
            // CDP 的 element.click() 不保证像真人点击一样留下焦点；显式聚焦可冻结披露态，
            // 再等待真实 CSS 几何收敛，避免帧饥饿时固定等待先于 140-160ms 过渡结束。
            zoomIn.focus({ preventScroll: true });
            try {
                await waitFor(function () {
                    var currentReadout = hud.querySelector('.warlord-camera-readout');
                    var currentDetail = hud.querySelector('[data-camera-role="detail"]');
                    return currentReadout && currentDetail
                        && visibleControls() === 4
                        && currentReadout.getBoundingClientRect().height >= 28
                        && Number(getComputedStyle(currentReadout).opacity) >= 0.99
                        && getComputedStyle(currentDetail).visibility !== 'hidden';
                }, 3000);
            } catch (error) {
                var stalledReadout = hud.querySelector('.warlord-camera-readout');
                var stalledDetail = hud.querySelector('[data-camera-role="detail"]');
                throw new Error('camera disclosure geometry did not settle: expanded=' + hud.getAttribute('data-expanded')
                    + ' controls=' + visibleControls()
                    + ' readout=' + (stalledReadout ? stalledReadout.getBoundingClientRect().height.toFixed(1) : 'missing')
                    + ' opacity=' + (stalledReadout ? getComputedStyle(stalledReadout).opacity : 'missing')
                    + ' detail=' + (stalledDetail ? getComputedStyle(stalledDetail).visibility : 'missing'));
            }
            var expandedAfterAction = hud.getAttribute('data-expanded');
            var visibleAfterAction = visibleControls();
            var readout = hud.querySelector('.warlord-camera-readout');
            var readoutStyle = getComputedStyle(readout);
            var detailStyle = getComputedStyle(hud.querySelector('[data-camera-role="detail"]'));
            var readoutHeight = readout.getBoundingClientRect().height;
            var disclosureHeldByFocus = document.activeElement === zoomIn;
            if ((expandedAfterAction !== 'true' && !disclosureHeldByFocus)
                || visibleAfterAction !== 4 || readoutHeight < 28) {
                throw new Error('camera reveal incomplete: expanded=' + expandedAfterAction
                    + ' focused=' + disclosureHeldByFocus
                    + ' controls=' + visibleAfterAction + ' readout=' + readoutHeight.toFixed(1)
                    + ' max=' + readoutStyle.maxHeight + ' opacity=' + readoutStyle.opacity
                    + ' detail=' + detailStyle.width + '/' + detailStyle.visibility);
            }
            var zoomed = Number(host.getAttribute('data-camera-zoom'));
            if (!(zoomed > initialZoom)) throw new Error('zoom controls did not increase tactical magnification: initial=' + initialZoom + ' zoomed=' + zoomed);
            var pieceScreenGrowth = Number(host.getAttribute('data-piece-screen-growth'));
            if (host.getAttribute('data-piece-scale-policy') !== 'progressive-art-detail-v2'
                || !(pieceScreenGrowth > 1.15 && pieceScreenGrowth <= 3.4)) {
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
        await check('ai-action-camera-batch-locks-input-and-returns-once', async function () {
            var nativeRequestAnimationFrame = window.requestAnimationFrame;
            var dropNextActionMovementFrame = false;
            var dropNextActionReturnFrame = false;
            var droppedActionMovementFrames = 0;
            var droppedActionReturnFrames = 0;
            function controlledRequestAnimationFrame(callback) {
                return nativeRequestAnimationFrame.call(window, function (time) {
                    var activeHost = document.querySelector('.warlord-scene-host');
                    if (dropNextActionMovementFrame && activeHost
                        && activeHost.getAttribute('data-action-return-state') === 'waiting-movement') {
                        dropNextActionMovementFrame = false;
                        droppedActionMovementFrames += 1;
                        return;
                    }
                    if (dropNextActionReturnFrame && activeHost
                        && activeHost.getAttribute('data-camera-tween-kind') === 'action-return'
                        && activeHost.getAttribute('data-camera-tween-state') === 'running') {
                        dropNextActionReturnFrame = false;
                        droppedActionReturnFrames += 1;
                        return;
                    }
                    callback(time);
                });
            }
            window.requestAnimationFrame = controlledRequestAnimationFrame;

            async function openCameraCase(seed) {
                window.__warlordHarness.close();
                await delay(30);
                window.__warlordHarness.open({ preset: 'all-units', seed: seed });
                var caseRoot = await waitFor(function () {
                    return document.querySelector('.warlord-scale-shell[data-ready="true"]');
                }, 12000);
                var caseHost = caseRoot.querySelector('.warlord-scene-host');
                var caseCanvas = caseRoot.querySelector('.warlord-sandtable-canvas');
                if (!caseHost || !caseCanvas) throw new Error('AI camera follow requires the WebGL sandtable');
                var hq = caseRoot.querySelector('[data-testid="node-R-HQ"]');
                if (!hq) {
                    caseRoot.querySelector('[data-action="toggle-node-scope"]')?.click();
                    await delay(20);
                    hq = caseRoot.querySelector('[data-testid="node-R-HQ"]');
                }
                if (!hq) throw new Error('player headquarters is unavailable for camera setup');
                hq.click();
                caseRoot.querySelector('[data-action="camera-focus"]')?.click();
                caseRoot.querySelector('[data-action="camera-zoom-in"]')?.click();
                await delay(360);
                return { root: caseRoot, host: caseHost, canvas: caseCanvas };
            }

            var automatic = null;
            try {
                automatic = await openCameraCase('qa-ai-camera-return');
                var fallbackBefore = Number(automatic.host.getAttribute('data-camera-tween-fallback-count') || 0);
                var selectedBefore = automatic.root.getAttribute('data-selected-node');
                var xBefore = Number(automatic.host.getAttribute('data-camera-x'));
                var zBefore = Number(automatic.host.getAttribute('data-camera-z'));
                var zoomBefore = Number(automatic.host.getAttribute('data-camera-zoom'));
                var movementFallbackBefore = Number(automatic.host.getAttribute('data-action-movement-fallback-count') || 0);
                var end = automatic.root.querySelector('[data-action="end-action"]:not([aria-disabled="true"])');
                if (!end) throw new Error('player end-action affordance missing before AI follow');
                dropNextActionMovementFrame = true;
                end.click();
                var firstToken = await waitFor(function () {
                    return automatic.host.getAttribute('data-camera-input-locked') === 'true'
                        ? automatic.host.getAttribute('data-action-follow-token') : null;
                }, 5000);
                if (!firstToken) throw new Error('AI camera segment did not expose its lease token');

                var rejectBefore = Number(automatic.host.getAttribute('data-camera-input-reject-count') || 0);
                var rect = automatic.canvas.getBoundingClientRect();
                var pointerX = rect.left + rect.width * 0.5;
                var pointerY = rect.top + rect.height * 0.5;
                automatic.canvas.dispatchEvent(new PointerEvent('pointerdown', {
                    pointerId: 72, button: 0, buttons: 1, clientX: pointerX, clientY: pointerY,
                    bubbles: true, cancelable: true
                }));
                automatic.canvas.dispatchEvent(new PointerEvent('pointercancel', {
                    pointerId: 72, button: 0, buttons: 0, clientX: pointerX, clientY: pointerY,
                    bubbles: true, cancelable: true
                }));
                var wheel = new WheelEvent('wheel', {
                    deltaY: -120, clientX: pointerX, clientY: pointerY,
                    bubbles: true, cancelable: true
                });
                automatic.canvas.dispatchEvent(wheel);
                var key = new KeyboardEvent('keydown', { key: '+', bubbles: true, cancelable: true });
                automatic.canvas.dispatchEvent(key);
                await delay(20);
                var rejectAfter = Number(automatic.host.getAttribute('data-camera-input-reject-count') || 0);
                var hud = automatic.root.querySelector('.warlord-camera-hud');
                if (rejectAfter < rejectBefore + 3 || !wheel.defaultPrevented || !key.defaultPrevented
                    || automatic.host.getAttribute('data-camera-input-locked') !== 'true'
                    || automatic.host.getAttribute('data-action-follow-state') === 'interrupted'
                    || automatic.host.getAttribute('data-action-cancel-token') === firstToken
                    || !hud || hud.getAttribute('data-input-locked') !== 'true'
                    || hud.querySelectorAll('button:not(:disabled)').length !== 0) {
                    throw new Error('manual camera input was not rejected for the complete AI segment');
                }

                await waitFor(function () {
                    return automatic.host.getAttribute('data-action-follow-token') === firstToken
                        && Number(automatic.host.getAttribute('data-action-follow-count')) >= 2;
                }, 5000);
                if (automatic.host.getAttribute('data-action-return-token') === firstToken) {
                    throw new Error('AI camera returned between consecutive enemy movements');
                }
                // 确定性吞掉回位阶段的一帧，证明 rAF 饥饿时统一 fallback 不只落画面，
                // 还会 exact-once 释放 lease/输入锁并重新打开唯一渲染槽。
                dropNextActionReturnFrame = true;
                try {
                    await waitFor(function () {
                        return automatic.host.getAttribute('data-action-return-token') === firstToken;
                    }, 30000);
                } catch (error) {
                    throw new Error('AI camera segment did not return after the final enemy action: ' + JSON.stringify({
                        phase: automatic.root.getAttribute('data-phase'),
                        sceneLifecycle: automatic.root.getAttribute('data-scene-lifecycle'),
                        canvas: automatic.root.querySelector('.warlord-sandtable-canvas') !== null,
                        followToken: automatic.host.getAttribute('data-action-follow-token'),
                        followCount: automatic.host.getAttribute('data-action-follow-count'),
                        followState: automatic.host.getAttribute('data-action-follow-state'),
                        returnToken: automatic.host.getAttribute('data-action-return-token'),
                        returnState: automatic.host.getAttribute('data-action-return-state'),
                        returnCount: automatic.host.getAttribute('data-action-return-count'),
                        inputLocked: automatic.host.getAttribute('data-camera-input-locked'),
                        tweenState: automatic.host.getAttribute('data-camera-tween-state'),
                        tweenKind: automatic.host.getAttribute('data-camera-tween-kind'),
                        tweenSettledKind: automatic.host.getAttribute('data-camera-tween-settled-kind'),
                        tweenCancelReason: automatic.host.getAttribute('data-camera-tween-cancel-reason'),
                        tweenCancelledKind: automatic.host.getAttribute('data-camera-tween-cancelled-kind'),
                        tweenCancelCount: automatic.host.getAttribute('data-camera-tween-cancel-count'),
                        tweenFallbackCount: automatic.host.getAttribute('data-camera-tween-fallback-count'),
                        tweenFallbackKind: automatic.host.getAttribute('data-camera-tween-fallback-kind'),
                        movementState: automatic.host.getAttribute('data-action-movement-state'),
                        movementFallbackCount: automatic.host.getAttribute('data-action-movement-fallback-count'),
                        droppedActionMovementFrames: droppedActionMovementFrames,
                        droppedActionReturnFrames: droppedActionReturnFrames
                    }));
                }
                if (Math.abs(Number(automatic.host.getAttribute('data-action-return-x')) - xBefore) > 0.01
                    || Math.abs(Number(automatic.host.getAttribute('data-action-return-z')) - zBefore) > 0.01
                    || Number(automatic.host.getAttribute('data-action-return-zoom')) !== zoomBefore) {
                    throw new Error('AI action batch did not restore the complete pre-action camera view: '
                        + JSON.stringify({
                            expected: { x: xBefore, z: zBefore, zoom: zoomBefore },
                            actual: {
                                x: automatic.host.getAttribute('data-action-return-x'),
                                z: automatic.host.getAttribute('data-action-return-z'),
                                zoom: automatic.host.getAttribute('data-action-return-zoom')
                            }
                        }));
                }
                if (automatic.root.getAttribute('data-selected-node') !== selectedBefore
                    || automatic.host.getAttribute('data-camera-input-locked') !== 'false'
                    || Number(automatic.host.getAttribute('data-action-return-count')) !== 1) {
                    throw new Error('AI action batch did not return once to the original inspection state');
                }
                if (droppedActionMovementFrames !== 1
                    || Number(automatic.host.getAttribute('data-action-movement-fallback-count') || 0) < movementFallbackBefore + 1
                    || droppedActionReturnFrames > 1
                    || Number(automatic.host.getAttribute('data-camera-tween-fallback-count') || 0) < fallbackBefore + 1
                    || automatic.host.getAttribute('data-camera-tween-fallback-kind') !== 'action-return'
                    || automatic.host.getAttribute('data-camera-tween-settled-kind') !== 'action-return') {
                    throw new Error('action movement/return rAF starvation did not converge through the shared fallbacks: '
                        + JSON.stringify({
                            droppedActionMovementFrames: droppedActionMovementFrames,
                            movementFallbackBefore: movementFallbackBefore,
                            movementFallbackAfter: automatic.host.getAttribute('data-action-movement-fallback-count'),
                            droppedActionReturnFrames: droppedActionReturnFrames,
                            fallbackBefore: fallbackBefore,
                            fallbackAfter: automatic.host.getAttribute('data-camera-tween-fallback-count'),
                            fallbackKind: automatic.host.getAttribute('data-camera-tween-fallback-kind'),
                            settledKind: automatic.host.getAttribute('data-camera-tween-settled-kind')
                        }));
                }
            } finally {
                if (window.requestAnimationFrame === controlledRequestAnimationFrame) {
                    window.requestAnimationFrame = nativeRequestAnimationFrame;
                }
                window.__warlordHarness.close();
                await delay(30);
                window.__warlordHarness.open();
                await waitFor(function () {
                    return document.querySelector('.warlord-scale-shell[data-ready="true"][data-scene-lifecycle="active"]');
                }, 12000);
            }
            return 'one multi-move lease · pointer/wheel/key locked · no intermediate return · movement/return rAF-starved fallbacks · one full-view restore';
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
                var expectedReason = invalid.getAttribute('data-reason-text');
                invalid.click();
                await delay(20);
                if (Number(root.getAttribute('data-selected-piece-count')) !== selectedCount) throw new Error('invalid target cleared the group');
                if (!expectedReason || document.querySelector('[data-region="live"]').textContent !== expectedReason
                    || expectedReason.indexOf('请') < 0) throw new Error('invalid target reason and next step were not announced');
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
        await check('stage-resume-player-avatar-uses-host-paper-doll-portrait', async function () {
            window.__warlordHarness.close();
            await delay(30);
            if (!window.MercPortraits || typeof window.MercPortraits.mount !== 'function') {
                throw new Error('shared MercPortraits renderer is unavailable');
            }
            var originalMount = window.MercPortraits.mount;
            var captured = null;
            window.MercPortraits.mount = function (container, image, merc, options) {
                captured = { merc: merc, options: options };
                return originalMount.call(this, container, image, merc, options);
            };
            try {
                window.__warlordHarness.open({
                    source: 'game_stage',
                    mode: 'stage-v1',
                    battleAuthority: 'as2',
                    scenarioRef: 'warlord_demo_02_v1',
                    panelInstanceId: 'warlord.qa.player-avatar',
                    stageOuterBinding: {
                        schema: 'warlord.stage-outer-binding.v1',
                        runId: 'run.qa.player-avatar',
                        subStageId: 'stage.qa.player-avatar',
                        scenarioRef: 'warlord_demo_02_v1',
                        callId: 'call.qa.player-avatar',
                        revision: 0
                    },
                    playerAvatarPortrait: {
                        schema: 'warlord.player-avatar-portrait.v1',
                        gender: '男',
                        face: '男变装 基本脸型',
                        hair: '发型-男式-平头',
                        equipment: { head: '', body: '', hand: '', leg: '', foot: '', neck: '' }
                    }
                });
                var avatar = await waitFor(function () {
                    return document.querySelector('[data-commander-role="player_avatar"] [data-warlord-player-avatar][data-warlord-portrait-kind="player_avatar"]');
                }, 12000);
                await waitFor(function () { return captured; }, 12000);
                if (avatar.hasAttribute('data-warlord-portrait')) {
                    throw new Error('player commander fell back to EnemyPortraits');
                }
                if (document.querySelector('.warlord-app')?.getAttribute('data-stage-mode') !== 'stage-v1') {
                    throw new Error('stage resume did not retain the stage terminal authority mode');
                }
                if (captured.merc.gender !== '男'
                    || captured.merc.face !== '男变装 基本脸型'
                    || captured.merc.hair !== '发型-男式-平头'
                    || captured.options.variant !== 'card'
                    || captured.options.size !== 112) {
                    throw new Error('Host paper-doll tuple was not preserved for MercPortraits');
                }
                return 'commander.player -> MercPortraits card tuple';
            } finally {
                window.MercPortraits.mount = originalMount;
                window.__warlordHarness.close();
                await delay(30);
                window.__warlordHarness.open();
                await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            }
        });
        await check('fixed-canvas-no-overflow', async function () {
            var stage = document.getElementById('harness-stage');
            if (!stage) throw new Error('host stage missing');
            var sizes = [[1024, 576], [960, 540], [800, 450]];
            var checkedSizes = [];
            for (var sizeIndex = 0; sizeIndex < sizes.length; sizeIndex += 1) {
                var size = sizes[sizeIndex];
                stage.style.width = size[0] + 'px';
                stage.style.height = size[1] + 'px';
                window.dispatchEvent(new Event('resize'));
                await waitFor(function () {
                    var currentApp = document.querySelector('.warlord-app');
                    var currentStageRect = stage.getBoundingClientRect();
                    var currentAppRect = currentApp && currentApp.getBoundingClientRect();
                    var currentLayoutOverflow = size[0] === 1024
                        && (stage.scrollWidth > stage.clientWidth || stage.scrollHeight > stage.clientHeight);
                    return currentApp && currentAppRect && !currentLayoutOverflow
                        && currentAppRect.left >= currentStageRect.left - 0.75
                        && currentAppRect.top >= currentStageRect.top - 0.75
                        && currentAppRect.right <= currentStageRect.right + 0.75
                        && currentAppRect.bottom <= currentStageRect.bottom + 0.75;
                }, 1800);
                var app = document.querySelector('.warlord-app');
                var panel = document.querySelector('.warlord-panel');
                var stageRect = stage.getBoundingClientRect();
                var appRect = app && app.getBoundingClientRect();
                var layoutOverflow = size[0] === 1024
                    && (stage.scrollWidth > stage.clientWidth || stage.scrollHeight > stage.clientHeight);
                if (!app || !panel || !appRect || layoutOverflow
                    || appRect.left < stageRect.left - 0.75 || appRect.top < stageRect.top - 0.75
                    || appRect.right > stageRect.right + 0.75 || appRect.bottom > stageRect.bottom + 0.75) {
                    throw new Error(size[0] + 'x' + size[1] + ' scaled stage overflow');
                }
                var helpButton = app.querySelector('[data-action="open-help"]');
                helpButton.click();
                await delay(30);
                var help = app.querySelector('.warlord-help-dialog');
                var helpRect = help && help.getBoundingClientRect();
                if (!help || !helpRect || helpRect.left < stageRect.left - 0.75 || helpRect.top < stageRect.top - 0.75
                    || helpRect.right > stageRect.right + 0.75 || helpRect.bottom > stageRect.bottom + 0.75
                    || help.scrollWidth > help.clientWidth || help.scrollHeight > help.clientHeight) {
                    throw new Error(size[0] + 'x' + size[1] + ' help overflow');
                }
                assertPlayerVocabulary(help);
                help.querySelector('[data-action="close-help"]').click();
                await delay(20);
                checkedSizes.push(size.join('x'));
            }
            stage.style.width = '1024px';
            stage.style.height = '576px';
            window.dispatchEvent(new Event('resize'));
            await waitFor(function () {
                var app = document.querySelector('.warlord-app');
                var stageRect = stage.getBoundingClientRect();
                var appRect = app && app.getBoundingClientRect();
                return appRect && appRect.right <= stageRect.right + 0.75 && appRect.bottom <= stageRect.bottom + 0.75;
            }, 1800);
            return checkedSizes.join(' · ') + ' no overflow';
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
            function stageBinding(callId, revision) {
                return {
                    schema: 'warlord.stage-outer-binding.v1',
                    runId: 'run.qa.stage',
                    subStageId: 'sub-stage.qa.warlord',
                    scenarioRef: 'warlord_tutorial_v1',
                    callId: callId,
                    revision: revision
                };
            }
            var originalBridgeSend = window.Bridge.send;
            window.__warlordHarness.clearBridgeMessages();
            window.__warlordHarness.open({
                source: 'game_stage', mode: 'stage-v1', panelInstanceId: 'warlord.qa.failed',
                stageOuterBinding: stageBinding('call.qa.failed', 1)
            });
            await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            // Ignore the expected lifecycle "opened" observation. This branch is
            // specifically proving that a rejected terminal never falls through
            // into either stage_terminal delivery or a generic panel close.
            window.__warlordHarness.clearBridgeMessages();
            try {
                window.Bridge.send = function (message) {
                    if (message && message.cmd === 'minigame_session'
                            && message.payload && message.payload.kind === 'stage_terminal') {
                        throw new Error('qa transport rejection');
                    }
                    return originalBridgeSend(message);
                };
                document.querySelector('[data-action="request-close"]').click();
                await delay(30);
            } finally {
                window.Bridge.send = originalBridgeSend;
            }
            if (window.__warlordHarness.bridgeMessages().length !== 0) {
                throw new Error('rejected stage terminal continued into generic close');
            }
            var failedBanner = document.querySelector('[data-region="authority"][data-state="stage-terminal-failed"]');
            if (!failedBanner || failedBanner.textContent.indexOf('页面会保持打开') < 0) {
                throw new Error('stage terminal transport failure was not visibly fail-closed');
            }

            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.clearBridgeMessages();
            window.__warlordHarness.open({
                source: 'game_stage', mode: 'stage-v1', panelInstanceId: 'warlord.qa.stage',
                stageOuterBinding: stageBinding('call.qa.old-generation', 2)
            });
            await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            window.__warlordHarness.rebind({
                source: 'game_stage', mode: 'stage-v1', panelInstanceId: 'warlord.qa.stage',
                stageOuterBinding: stageBinding('call.qa.current-generation', 3)
            });
            await delay(30);
            window.__warlordHarness.clearBridgeMessages();
            var closeButton = document.querySelector('[data-action="request-close"]');
            closeButton.click();
            closeButton.click();
            await delay(30);
            var messages = window.__warlordHarness.bridgeMessages();
            var terminals = messages.filter(function (message) {
                return message && message.cmd === 'minigame_session'
                    && message.payload && message.payload.kind === 'stage_terminal';
            });
            var closes = messages.filter(function (message) {
                return message && message.cmd === 'close' && message.panel === 'warlord';
            });
            if (terminals.length !== 1 || closes.length !== 1) {
                throw new Error('duplicate stage close emitted ' + terminals.length + ' terminals / ' + closes.length + ' closes');
            }
            var terminalEnvelope = terminals[0];
            var envelopeKeys = Object.keys(terminalEnvelope).sort().join(',');
            var payloadKeys = Object.keys(terminalEnvelope.payload || {}).sort().join(',');
            if (envelopeKeys !== 'cmd,panel,panelInstanceId,payload,type'
                    || payloadKeys !== 'data,game,kind'
                    || terminalEnvelope.type !== 'panel'
                    || terminalEnvelope.panel !== 'warlord'
                    || terminalEnvelope.cmd !== 'minigame_session'
                    || terminalEnvelope.panelInstanceId !== 'warlord.qa.stage'
                    || terminalEnvelope.payload.game !== 'warlord'
                    || terminalEnvelope.payload.kind !== 'stage_terminal') {
                throw new Error('stage terminal did not match the exact Host envelope contract');
            }
            var terminal = terminals[0].payload.data;
            if (terminal.terminal !== 'Suspended' || terminal.callId !== 'call.qa.current-generation'
                    || terminal.revision !== 3) {
                throw new Error('stage terminal escaped current generation/binding fence');
            }
            if (messages.indexOf(terminals[0]) > messages.indexOf(closes[0])) {
                throw new Error('exact panel close was sent before Suspended terminal');
            }

            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.clearBridgeMessages();
            window.__warlordHarness.open({
                source: 'game_stage', mode: 'stage-v1', panelInstanceId: 'warlord.qa.malformed',
                stageOuterBinding: Object.assign(stageBinding('bad id', 4), { unexpected: true })
            });
            await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            // As above, discard the normal "opened" lifecycle observation before
            // asserting that malformed authority cannot emit a terminal or close.
            window.__warlordHarness.clearBridgeMessages();
            var blocked = document.querySelector('[data-region="authority"][data-state="stage-blocked"]');
            if (!blocked || blocked.textContent.indexOf('不会退回普通演习') < 0) {
                throw new Error('malformed stage binding did not expose Chinese fail-closed state');
            }
            document.querySelector('[data-action="request-close"]').click();
            await delay(30);
            if (window.__warlordHarness.bridgeMessages().length !== 0) {
                throw new Error('malformed stage binding emitted terminal or generic close');
            }

            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.open({ seed: 'qa-reopen-seed' });
            var root = await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            if (root.getAttribute('data-selected-node') !== 'R-HQ') throw new Error('reopen state not reset');
            return 'stage terminal fenced · malformed/transport fail closed · closed and reopened';
        });
        await check('full-action-planning-production-loop', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.open({ preset: 'all-units', seed: 'qa-full-loop' });
            await waitFor(function () { return document.querySelector('.warlord-scale-shell[data-ready="true"]'); }, 12000);
            var end = document.querySelector('[data-action="end-action"]:not(:disabled):not([aria-disabled="true"])');
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
            var xp = document.querySelector('[data-action="allocate-xp"]:not(:disabled):not([aria-disabled="true"])');
            var production = document.querySelector('[data-action="production"]:not(:disabled):not([aria-disabled="true"])');
            if (!xp || !production) throw new Error('planning upgrade or production action unavailable');
            var consoleBefore = document.querySelector('.warlord-production-console[data-mode="auto"]');
            if (!consoleBefore || document.querySelector('[data-field="slot"]')) {
                throw new Error('default automatic production console is missing or legacy slot radios remain');
            }
            xp.click();
            await delay(30);
            var promotion = document.querySelector('[data-action="promotion"]:not(:disabled):not([aria-disabled="true"])');
            if (promotion) promotion.click();
            await delay(30);
            production = document.querySelector('[data-action="production"]:not(:disabled):not([aria-disabled="true"])');
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
            production = document.querySelector('[data-action="production"]:not(:disabled):not([aria-disabled="true"])');
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
            var commit = document.querySelector('[data-action="commit-planning"]:not(:disabled):not([aria-disabled="true"])');
            if (!commit) throw new Error('commit planning unavailable');
            commit.click();
            return 'action -> AI -> settlement -> auto production portrait -> order-icon locate -> full-refund undo -> exact lane selection without enqueue -> commit';
        });
        await check('encounter-distance-node-and-command-guidance', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.open({ preset: 'all-units', seed: 'qa-encounter-distance' });
            var root = await waitFor(function () {
                return document.querySelector('.warlord-scale-shell[data-ready="true"][data-selected-node="R-Supply"]');
            }, 12000);
            var expected = {
                near: {
                    profile: 'encounter.near',
                    distance: '180',
                    compact: '接敌：近',
                    copy: '接敌距离：近 · 很快接战，突击与持续供弹更容易发挥。'
                },
                medium: {
                    profile: 'encounter.medium',
                    distance: '360',
                    compact: '接敌：中',
                    copy: '接敌距离：中 · 双方都有准备时间。'
                },
                far: {
                    profile: 'encounter.far',
                    distance: '650',
                    compact: '接敌：远',
                    copy: '接敌距离：远 · 狙击先手时间更长。'
                }
            };
            function assertSelectedDistance(band) {
                var region = document.querySelector('[data-region="forces"]');
                var copy = region && region.querySelector('[data-encounter-distance="' + band + '"]');
                if (!region || region.getAttribute('data-encounter-profile-ref') !== expected[band].profile
                    || region.getAttribute('data-distance-band') !== band
                    || region.getAttribute('data-spawn-distance') !== expected[band].distance) {
                    throw new Error('selected-node encounter triple mismatch for ' + band);
                }
                if (!copy || copy.textContent.trim() !== expected[band].compact
                    || copy.getAttribute('aria-label') !== expected[band].copy
                    || copy.getAttribute('role') !== 'note'
                    || copy.getAttribute('data-encounter-profile-ref') !== expected[band].profile
                    || copy.getAttribute('data-spawn-distance') !== expected[band].distance) {
                    throw new Error('selected-node compact/accessibility guidance mismatch for ' + band);
                }
            }
            function assertCommandDistance(nodeId, band) {
                var route = document.querySelector('.warlord-route-actions [data-node="' + nodeId + '"]');
                var copy = route && route.querySelector('[data-encounter-distance="' + band + '"]');
                if (!route || route.getAttribute('data-encounter-profile-ref') !== expected[band].profile
                    || route.getAttribute('data-distance-band') !== band
                    || route.getAttribute('data-spawn-distance') !== expected[band].distance) {
                    throw new Error('command-preview encounter triple mismatch for ' + nodeId);
                }
                if (!copy || copy.textContent.trim() !== expected[band].copy) {
                    throw new Error('command-preview beginner guidance mismatch for ' + nodeId);
                }
            }

            assertSelectedDistance('medium');
            assertCommandDistance('R-HQ', 'near');
            assertCommandDistance('North-Choke', 'far');

            document.querySelector('[data-action="toggle-node-scope"]')?.click();
            await delay(20);
            var north = document.querySelector('[data-testid="node-North-Choke"]');
            if (!north) throw new Error('North-Choke missing from all-node index');
            north.click();
            await waitFor(function () { return root.getAttribute('data-selected-node') === 'North-Choke'; }, 3000);
            assertSelectedDistance('far');

            var hq = document.querySelector('[data-testid="node-R-HQ"]');
            if (!hq) throw new Error('R-HQ missing from all-node index');
            hq.click();
            await waitFor(function () { return root.getAttribute('data-selected-node') === 'R-HQ'; }, 3000);
            assertSelectedDistance('near');
            assertCommandDistance('R-Supply', 'medium');
            return 'selected compact near/medium/far · accessible full copy · command near/medium/far · exact 180/360/650';
        });
        await check('task-group-ui-and-command-element-tokens', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.open({ preset: 'all-units', seed: 'qa-task-group' });
            var root = await waitFor(function () {
                return document.querySelector('.warlord-scale-shell[data-ready="true"][data-selected-node="R-Supply"]');
            }, 12000);
            var forceRegion = document.querySelector('[data-region="forces"]');
            var sceneHost = await waitFor(function () {
                var candidate = document.querySelector('.warlord-scene-host[data-piece-badge-count]');
                return candidate && candidate.getAttribute('data-piece-badge-count') === candidate.getAttribute('data-command-element-badge-count')
                    ? candidate : null;
            }, 12000);
            var initialNodeElements = Number(forceRegion && forceRegion.getAttribute('data-command-element-count'));
            var initialBadgeCount = Number(sceneHost.getAttribute('data-piece-badge-count'));
            if (initialNodeElements !== 3) throw new Error('R-Supply expected 3 command elements, got ' + initialNodeElements);
            if (document.querySelectorAll('.warlord-force-list .warlord-piece input[data-field="piece"]').length !== initialNodeElements) {
                throw new Error('strategic piece controls are not one-per-command-element before merge');
            }

            var beforeAp = document.querySelector('[data-testid="hud-red"]').getAttribute('data-action-points');
            var beforeSpent = document.querySelector('[data-testid="hud-red"]').getAttribute('data-ap-spent');
            document.querySelector('[data-action="select-all-at-node"]:not(:disabled)').click();
            await delay(20);
            var checkedPieces = document.querySelectorAll('.warlord-piece input[data-field="piece"]:checked');
            if (checkedPieces.length !== 3) throw new Error('select-all expected 3 command elements, got ' + checkedPieces.length);
            var trim = checkedPieces[checkedPieces.length - 1];
            trim.checked = false;
            trim.dispatchEvent(new Event('change', { bubbles: true }));
            await delay(20);
            if (root.getAttribute('data-selected-command-element-count') !== '2'
                || root.getAttribute('data-selected-member-count') !== '2') {
                throw new Error('pre-merge selection was not 2 complete command elements');
            }
            var merge = document.querySelector('[data-action="merge-task-group"]:not([aria-disabled="true"])');
            if (!merge) throw new Error('merge affordance unavailable for two same-node elements');
            merge.click();
            var group = await waitFor(function () {
                return document.querySelector('.warlord-task-group[data-member-count="2"]');
            }, 3000);
            sceneHost = await waitFor(function () {
                var candidate = document.querySelector('.warlord-scene-host[data-task-group-badge-count="1"]');
                return candidate && Number(candidate.getAttribute('data-piece-badge-count')) === initialBadgeCount - 1
                    ? candidate : null;
            }, 3000);
            forceRegion = document.querySelector('[data-region="forces"]');
            if (Number(forceRegion.getAttribute('data-command-element-count')) !== initialNodeElements - 1) {
                throw new Error('merge did not replace two child elements with one parent element');
            }
            if (sceneHost.getAttribute('data-piece-badge-count') !== sceneHost.getAttribute('data-command-element-badge-count')) {
                throw new Error('canvas badge count diverged from active command elements after merge');
            }
            if (root.getAttribute('data-selected-command-element-count') !== '1'
                || root.getAttribute('data-selected-member-count') !== '2') {
                throw new Error('merged parent did not expand to its complete member selection');
            }
            if (group.querySelectorAll('.warlord-piece input[data-field="piece"]').length !== 1
                || group.querySelectorAll('input[data-field="task-group-member"]').length !== 2) {
                throw new Error('task-group parent and subordinate member controls are not separated');
            }
            var canvas = document.querySelector('.warlord-sandtable-canvas');
            var representativeId = group.querySelector('.warlord-piece').getAttribute('data-piece-id');
            canvas.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(20);
            var representativePoint = findCanvasPoint(canvas, sceneHost, function (surface) {
                return surface.getAttribute('data-hovered-piece') === representativeId;
            });
            if (!representativePoint) throw new Error('could not ray-pick the task-group representative token');
            clickCanvas(canvas, representativePoint, 121);
            await delay(20);
            if (root.getAttribute('data-selected-command-element-count') !== '1'
                || root.getAttribute('data-selected-member-count') !== '2') {
                throw new Error('representative click did not expand to all task-group members');
            }
            canvas.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(20);
            var marqueeRadius = 44;
            canvas.dispatchEvent(new PointerEvent('pointerdown', { pointerId: 122, button: 0, buttons: 1, shiftKey: true, clientX: representativePoint.x - marqueeRadius, clientY: representativePoint.y - marqueeRadius, bubbles: true, cancelable: true }));
            canvas.dispatchEvent(new PointerEvent('pointermove', { pointerId: 122, button: 0, buttons: 1, shiftKey: true, clientX: representativePoint.x + marqueeRadius, clientY: representativePoint.y + marqueeRadius, bubbles: true, cancelable: true }));
            canvas.dispatchEvent(new PointerEvent('pointerup', { pointerId: 122, button: 0, buttons: 0, shiftKey: true, clientX: representativePoint.x + marqueeRadius, clientY: representativePoint.y + marqueeRadius, bubbles: true, cancelable: true }));
            await delay(30);
            group = document.querySelector('.warlord-task-group');
            if (!group.querySelector('.warlord-piece input[data-field="piece"]:checked')
                || Number(root.getAttribute('data-selected-member-count')) <= Number(root.getAttribute('data-selected-command-element-count'))) {
                throw new Error('representative marquee did not expand the task-group members');
            }
            canvas.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(20);
            group = document.querySelector('.warlord-task-group');
            var groupControl = group.querySelector('.warlord-piece input[data-field="piece"]');
            groupControl.checked = true;
            groupControl.dispatchEvent(new Event('change', { bubbles: true }));
            await delay(20);
            group = document.querySelector('.warlord-task-group');
            ['command-load', 'deployment-size', 'encounter-cost'].forEach(function (metric) {
                if (!group.hasAttribute('data-' + metric) || group.getAttribute('data-' + metric) !== root.getAttribute('data-' + metric)) {
                    throw new Error(metric + ' metric is missing or inconsistent on the task-group surface');
                }
            });
            var route = document.querySelector('.warlord-route-actions [data-command-load][data-deployment-size][data-encounter-cost]');
            if (!route || route.textContent.indexOf('行动点') < 0 || route.textContent.indexOf('规模') < 0
                || route.textContent.indexOf('战斗负载') < 0) {
                throw new Error('route preview does not expose all three Chinese organization metrics');
            }
            if (document.querySelector('[data-testid="hud-red"]').getAttribute('data-action-points') !== beforeAp
                || document.querySelector('[data-testid="hud-red"]').getAttribute('data-ap-spent') !== beforeSpent) {
                throw new Error('merge unexpectedly consumed action points');
            }

            var formations = ['line', 'column', 'wedge', 'shield', 'grid'];
            if (group.querySelectorAll('input[data-field="formation-profile"]').length !== formations.length) {
                throw new Error('formation picker did not expose five profiles');
            }
            for (var formationIndex = 0; formationIndex < formations.length; formationIndex += 1) {
                var formationId = formations[formationIndex];
                group = document.querySelector('.warlord-task-group');
                var radio = group && group.querySelector('input[data-field="formation-profile"][value="' + formationId + '"]');
                if (!radio) throw new Error('formation radio missing: ' + formationId);
                radio.checked = true;
                radio.dispatchEvent(new Event('change', { bubbles: true }));
                group = await waitFor(function () {
                    return document.querySelector('.warlord-task-group[data-formation-profile="' + formationId + '"]');
                }, 3000);
                var effect = group.querySelector('[data-formation-effect]');
                if (!effect || effect.textContent.indexOf('阵位顺序') < 0) {
                    throw new Error('formation semantics missing: ' + formationId);
                }
            }
            if (document.querySelector('[data-testid="hud-red"]').getAttribute('data-action-points') !== beforeAp
                || document.querySelector('[data-testid="hud-red"]').getAttribute('data-ap-spent') !== beforeSpent) {
                throw new Error('formation change unexpectedly consumed action points');
            }

            document.querySelector('[data-action="select-all-at-node"]:not(:disabled)').click();
            var mixedFormationRoute = await waitFor(function () {
                return document.querySelector('.warlord-route-actions [data-reason-code="formation_mix_unsupported"][aria-disabled="true"]');
            }, 3000);
            if (mixedFormationRoute.textContent.indexOf('不同阵型') < 0
                || mixedFormationRoute.getAttribute('data-reason-text').indexOf('同一阵型') < 0) {
                throw new Error('mixed formation route did not expose Chinese reason and next step');
            }
            mixedFormationRoute.click();
            var mixedFormationNotice = await waitFor(function () {
                var live = document.querySelector('[data-region="live"]');
                return live && live.textContent.indexOf('不同阵型') >= 0
                    && live.textContent.indexOf('同一阵型') >= 0 ? live : null;
            }, 3000);
            if (!mixedFormationNotice) throw new Error('mixed formation rejection was not announced');
            var singletonControl = Array.from(document.querySelectorAll('.warlord-force-list .warlord-piece input[data-field="piece"]'))
                .find(function (control) { return !control.closest('.warlord-task-group'); });
            if (!singletonControl) throw new Error('mixed formation fixture lost its singleton command element');
            singletonControl.checked = false;
            singletonControl.dispatchEvent(new Event('change', { bubbles: true }));
            await waitFor(function () {
                return root.getAttribute('data-selected-command-element-count') === '1'
                    && root.getAttribute('data-selected-member-count') === '2' ? root : null;
            }, 3000);

            group = document.querySelector('.warlord-task-group');
            var splitMember = group.querySelector('input[data-field="task-group-member"]');
            splitMember.checked = true;
            splitMember.dispatchEvent(new Event('change', { bubbles: true }));
            await delay(20);
            var split = document.querySelector('[data-action="split-task-group"]:not([aria-disabled="true"])');
            if (!split) throw new Error('split affordance unavailable after choosing one member');
            var groupScroll = document.querySelector('.warlord-force-list');
            split.scrollIntoView({ block: 'nearest' });
            await delay(20);
            var splitRect = split.getBoundingClientRect();
            var groupScrollRect = groupScroll.getBoundingClientRect();
            if (getComputedStyle(groupScroll).overflowY !== 'auto'
                || splitRect.top < groupScrollRect.top - 0.75 || splitRect.bottom > groupScrollRect.bottom + 0.75) {
                throw new Error('task-group split action is not reachable inside the force-list scroller');
            }
            split.click();
            await waitFor(function () {
                var currentHost = document.querySelector('.warlord-scene-host');
                return !document.querySelector('.warlord-task-group')
                    && currentHost
                    && Number(currentHost.getAttribute('data-piece-badge-count')) === initialBadgeCount
                    ? currentHost : null;
            }, 3000);
            forceRegion = document.querySelector('[data-region="forces"]');
            if (Number(forceRegion.getAttribute('data-command-element-count')) !== initialNodeElements
                || root.getAttribute('data-selected-command-element-count') !== '2'
                || root.getAttribute('data-selected-member-count') !== '2') {
                throw new Error('split did not restore two complete singleton command elements');
            }
            if (document.querySelectorAll('.warlord-force-list .warlord-piece input[data-field="piece"]').length !== initialNodeElements) {
                throw new Error('split left a parent/child duplicate strategic control');
            }
            if (document.querySelector('[data-testid="hud-red"]').getAttribute('data-action-points') !== beforeAp
                || document.querySelector('[data-testid="hud-red"]').getAttribute('data-ap-spent') !== beforeSpent) {
                throw new Error('split unexpectedly consumed action points');
            }
            return '3 tokens -> merge 2 as 1 parent -> click/marquee expand members -> five formations -> split to 2 singletons · metrics stable · 0 AP';
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
            if (document.querySelector('.warlord-sandtable-canvas')) {
                throw new Error('battle playback retained the hidden sandtable canvas');
            }
            window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(30);
            if (!document.querySelector('[data-action="battle-close"]:not(:disabled)')) {
                throw new Error('Escape did not skip playback to the settlement point');
            }
            window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await delay(30);
            if (document.querySelector('.warlord-battle-layer:not([hidden])')) {
                throw new Error('second Escape did not close battle playback');
            }
            return 'select-all 3 -> trim 2 · arm -> confirm -> playback -> Esc skip -> Esc close';
        });
        await check('battle-overlay-releases-webgl-and-survives-30-lifecycle-cycles', async function () {
            var cycleCount = 30;
            var firstLayoutReceipt = null;
            var staticDwellReceipt = null;
            var graphicsProbe = installGraphicsLifecycleProbe();
            var totalCreatedBefore = graphicsProbe.snapshot().createdWebglCanvases;
            var resume = await buildAcceptedAs2ResumeFixture();
            var portraitResolver = window.EnemyPortraits ?? window.PortraitResolver;
            if (!portraitResolver || typeof portraitResolver.mount !== 'function') {
                throw new Error('enemy portrait mount probe is unavailable');
            }
            var nativePortraitMount = portraitResolver.mount;
            var portraitMountCount = 0;
            portraitResolver.mount = function () {
                portraitMountCount += 1;
                return nativePortraitMount.apply(this, arguments);
            };
            var finalProbe = null;
            try {
                for (var cycle = 0; cycle < cycleCount; cycle += 1) {
                    window.__WARLORD_QA_PROGRESS__ = { check: 'battle-lifecycle', cycle: cycle + 1, state: 'closing_previous' };
                    window.__warlordHarness.close();
                    await waitFor(function () {
                        return document.querySelectorAll('.warlord-sandtable-canvas').length === 0
                            && graphicsProbe.activeFrameCount() === 0;
                    }, 3000);
                    var beforeResumeOpen = graphicsProbe.snapshot();
                    window.__WARLORD_QA_PROGRESS__.state = 'opening_as2_resume';
                    window.__warlordHarness.open({
                        source: 'runtime',
                        battleAuthority: 'as2',
                        as2BattleSession: true,
                        panelInstanceId: 'warlord.panel.qa-settled-lifecycle',
                        seed: resume.state.gameSeed,
                        preset: resume.state.preset,
                        difficulty: resume.state.difficulty,
                        mapTheme: 'desert',
                        aiSeenTransitions: [],
                        resume: structuredClone(resume)
                    });
                    var firstBattleObservation = null;
                    var settled = await waitFor(function () {
                        var root = document.querySelector('.warlord-scale-shell[data-ready="true"]');
                        var layer = root && root.querySelector('.warlord-battle-layer:not([hidden])');
                        if (layer && firstBattleObservation === null) {
                            firstBattleObservation = {
                                closeEnabled: layer.querySelector('[data-action="battle-close"]:not(:disabled)') !== null,
                                lifecycle: root.getAttribute('data-scene-lifecycle')
                            };
                        }
                        return root && layer
                            && root.getAttribute('data-scene-lifecycle') === 'released_for_battle'
                            && layer.querySelector('[data-action="battle-close"]:not(:disabled)')
                            ? { root: root, layer: layer } : null;
                    }, 12000);
                    window.__WARLORD_QA_PROGRESS__.state = 'asserting_released_overlay';
                    await waitFor(function () {
                        return graphicsProbe.activeFrameCount() === 0
                            && graphicsProbe.snapshot().activeWebglContexts === 0;
                    }, 1000);
                    var root = settled.root;
                    var layer = settled.layer;
                    var released = graphicsProbe.snapshot();
                    if (!firstBattleObservation || firstBattleObservation.closeEnabled !== true
                        || firstBattleObservation.lifecycle !== 'released_for_battle') {
                        throw new Error('cycle ' + (cycle + 1) + ' first AS2 settlement frame was not final/released: '
                            + JSON.stringify(firstBattleObservation));
                    }
                    if (root.querySelectorAll('.warlord-sandtable-canvas').length !== 0
                        || released.connectedWebglCanvases !== 0
                        || released.activeWebglContexts !== 0
                        || released.activeFrames !== 0
                        || released.createdWebglCanvases !== beforeResumeOpen.createdWebglCanvases) {
                        throw new Error('cycle ' + (cycle + 1) + ' AS2 settlement created or retained canvas/WebGL/rAF: '
                            + JSON.stringify({ before: beforeResumeOpen, released: released }));
                    }

                    if (cycle === 0) {
                        var dialog = layer.querySelector('.warlord-battle-dialog');
                        if (!dialog) throw new Error('AS2 settlement dialog is missing');
                        var mountsBeforeDwell = portraitMountCount;
                        var probeBeforeDwell = graphicsProbe.snapshot();
                        await delay(500);
                        var probeAfterDwell = graphicsProbe.snapshot();
                        if (layer.querySelector('.warlord-battle-dialog') !== dialog
                            || portraitMountCount !== mountsBeforeDwell
                            || probeAfterDwell.requestedFrames !== probeBeforeDwell.requestedFrames
                            || probeAfterDwell.createdWebglCanvases !== probeBeforeDwell.createdWebglCanvases
                            || probeAfterDwell.activeFrames !== 0) {
                            throw new Error('static final settlement remounted/rerendered or restarted graphics work: '
                                + JSON.stringify({
                                    mountsBefore: mountsBeforeDwell,
                                    mountsAfter: portraitMountCount,
                                    probeBefore: probeBeforeDwell,
                                    probeAfter: probeAfterDwell,
                                    sameDialog: layer.querySelector('.warlord-battle-dialog') === dialog
                                }));
                        }
                        staticDwellReceipt = '500ms static · portrait mounts/full render/rAF/context unchanged';

                        var formations = layer.querySelector('.warlord-battle-formations');
                        var sections = formations ? formations.querySelectorAll(':scope > section') : [];
                        var defender = sections[1];
                        var sourceCard = defender && defender.querySelector('article');
                        if (!formations || !defender || !sourceCard) {
                            throw new Error('settlement layout structure is incomplete');
                        }
                        while (defender.querySelectorAll('article').length < 7) {
                            defender.appendChild(sourceCard.cloneNode(true));
                        }
                        await delay(20);
                        var controls = layer.querySelector('.warlord-battle-controls');
                        var close = controls && controls.querySelector('[data-action="battle-close"]:not(:disabled)');
                        var stage = document.getElementById('harness-stage');
                        var dialogRect = dialog.getBoundingClientRect();
                        var controlsRect = controls && controls.getBoundingClientRect();
                        var stageRect = stage && stage.getBoundingClientRect();
                        if (defender.querySelectorAll('article').length !== 7
                            || getComputedStyle(formations).overflowY !== 'auto'
                            || formations.scrollHeight <= formations.clientHeight
                            || !controlsRect || !stageRect
                            || dialogRect.top < stageRect.top - 0.75 || dialogRect.bottom > stageRect.bottom + 0.75
                            || controlsRect.top < dialogRect.top || controlsRect.bottom > dialogRect.bottom + 0.75) {
                            throw new Error('seven-unit settlement did not keep a bounded scroll body and fixed controls');
                        }
                        formations.scrollTop = formations.scrollHeight;
                        await delay(20);
                        var closeRect = close && close.getBoundingClientRect();
                        var hit = closeRect && document.elementFromPoint(
                            closeRect.left + closeRect.width / 2,
                            closeRect.top + closeRect.height / 2
                        );
                        if (!close || !closeRect || !hit || (hit !== close && !close.contains(hit))) {
                            throw new Error('seven-unit settlement close action is visually occluded');
                        }
                        firstLayoutReceipt = '7 synthetic defenders · internal scroll · close hit-test';
                    }

                    var contextsBeforeClose = graphicsProbe.snapshot().createdWebglCanvases;
                    window.__WARLORD_QA_PROGRESS__.state = 'restoring_scene';
                    layer.querySelector('[data-action="battle-close"]:not(:disabled)').click();
                    await waitFor(function () {
                        return root.getAttribute('data-scene-lifecycle') === 'active'
                            && !root.querySelector('.warlord-battle-layer:not([hidden])')
                            && root.querySelectorAll('.warlord-sandtable-canvas').length === 1;
                    }, 4000);
                    var resumed = graphicsProbe.snapshot();
                    if (resumed.connectedWebglCanvases !== 1
                        || resumed.activeWebglContexts !== 1
                        || resumed.createdWebglCanvases !== contextsBeforeClose + 1) {
                        throw new Error('cycle ' + (cycle + 1) + ' did not restore exactly one scene: '
                            + JSON.stringify(resumed));
                    }
                }
                window.__warlordHarness.close();
                await waitFor(function () {
                    return document.querySelectorAll('.warlord-sandtable-canvas').length === 0
                        && graphicsProbe.activeFrameCount() === 0
                        && graphicsProbe.snapshot().activeWebglContexts === 0;
                }, 3000);
                finalProbe = graphicsProbe.snapshot();
                if (finalProbe.connectedWebglCanvases !== 0) {
                    throw new Error('final panel disposal retained a connected WebGL canvas');
                }
            } finally {
                portraitResolver.mount = nativePortraitMount;
                window.__warlordHarness.close();
                graphicsProbe.dispose();
            }
            window.__warlordHarness.open();
            await waitFor(function () {
                return document.querySelector('.warlord-scale-shell[data-ready="true"][data-scene-lifecycle="active"]');
            }, 12000);
            return cycleCount + ' accepted AS2 resume settlement/rebuild/dispose cycles · ' + staticDwellReceipt
                + ' · ' + firstLayoutReceipt
                + ' · contexts +' + (finalProbe.createdWebglCanvases - totalCreatedBefore)
                + ' · active WebGL/pending rAF 0 at every settlement';
        });
        await check('outgoing-as2-handoff-releases-graphics-before-host-response', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.clearBridgeMessages();
            window.__warlordHarness.setBattleResponseMode('none');
            var graphicsProbe = installGraphicsLifecycleProbe();
            try {
                window.__warlordHarness.open({
                    source: 'runtime',
                    battleAuthority: 'as2',
                    panelInstanceId: 'warlord.qa.outgoing-handoff',
                    preset: 'all-units',
                    seed: 'qa-as2-outgoing-handoff'
                });
                var root;
                try {
                    root = await waitFor(function () {
                        var candidate = document.querySelector('.warlord-scale-shell[data-ready="true"][data-scene-lifecycle="active"]');
                        return candidate && candidate.querySelectorAll('.warlord-sandtable-canvas').length === 1
                            && graphicsProbe.snapshot().activeWebglContexts === 1 ? candidate : null;
                    }, 12000);
                } catch (error) {
                    throw new Error('outgoing AS2 fixture did not start with exactly one active scene: '
                        + JSON.stringify(graphicsProbe.snapshot()));
                }
                var before = graphicsProbe.snapshot();
                await confirmPlayerAttackFromSupply(root);
                var released;
                try {
                    released = await waitFor(function () {
                        var snapshot = graphicsProbe.snapshot();
                        return root.getAttribute('data-scene-lifecycle') === 'released_for_handoff'
                            && root.querySelectorAll('.warlord-sandtable-canvas').length === 0
                            && snapshot.connectedWebglCanvases === 0
                            && snapshot.activeWebglContexts === 0
                            && snapshot.activeFrames === 0 ? snapshot : null;
                    }, 5000);
                } catch (error) {
                    throw new Error('outgoing AS2 pending boundary retained graphics work: ' + JSON.stringify({
                        lifecycle: root.getAttribute('data-scene-lifecycle'),
                        authority: root.querySelector('.warlord-app')?.getAttribute('data-authority-state'),
                        canvasCount: root.querySelectorAll('.warlord-sandtable-canvas').length,
                        probe: graphicsProbe.snapshot()
                    }));
                }
                await waitFor(function () {
                    return window.__warlordHarness.bridgeMessages().some(function (message) {
                        return message && message.cmd === 'battle_start';
                    });
                }, 12000);
                var app = root.querySelector('.warlord-app');
                if (!app || app.getAttribute('data-authority-state') !== 'handoff'
                    || root.querySelector('.warlord-battle-layer:not([hidden])')
                    || released.createdWebglCanvases !== before.createdWebglCanvases
                    || graphicsProbe.snapshot().activeWebglContexts !== 0
                    || graphicsProbe.snapshot().activeFrames !== 0) {
                    throw new Error('outgoing AS2 handoff did not remain pending with the original scene fully released: '
                        + JSON.stringify({ before: before, released: released }));
                }
                return 'battle_start emitted without Host response · released_for_handoff · canvas/WebGL/rAF 0';
            } finally {
                window.__warlordHarness.close();
                await waitFor(function () {
                    return document.querySelectorAll('.warlord-sandtable-canvas').length === 0
                        && graphicsProbe.activeFrameCount() === 0
                        && graphicsProbe.snapshot().activeWebglContexts === 0;
                }, 3000);
                graphicsProbe.dispose();
                window.__warlordHarness.open();
                await waitFor(function () {
                    return document.querySelector('.warlord-scale-shell[data-ready="true"][data-scene-lifecycle="active"]');
                }, 12000);
            }
        });
        await check('panel-close-intent-quiesces-webgl-and-timeout-restores-one-scene', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.clearBridgeMessages();
            var graphicsProbe = installGraphicsLifecycleProbe();
            var previousTimeout = window.__CF7_PANEL_CLOSE_ACK_TIMEOUT_MS__;
            window.__CF7_PANEL_CLOSE_ACK_TIMEOUT_MS__ = 80;
            try {
                window.__warlordHarness.open({
                    panelInstanceId: 'warlord.qa.close-quiesce',
                    seed: 'qa-close-quiesce'
                });
                var root = await waitFor(function () {
                    var candidate = document.querySelector('.warlord-scale-shell[data-ready="true"][data-scene-lifecycle="active"]');
                    return candidate && graphicsProbe.snapshot().activeWebglContexts === 1
                        ? candidate : null;
                }, 12000);
                if (window.__warlordHarness.requestClose() !== true) {
                    throw new Error('exact close intent was not accepted by the harness bridge');
                }
                var released = await waitFor(function () {
                    var snapshot = graphicsProbe.snapshot();
                    return root.getAttribute('data-scene-lifecycle') === 'released_for_panel_close'
                        && root.querySelectorAll('.warlord-sandtable-canvas').length === 0
                        && snapshot.connectedWebglCanvases === 0
                        && snapshot.activeWebglContexts === 0
                        && snapshot.activeFrames === 0 ? snapshot : null;
                }, 3000);
                var restored = await waitFor(function () {
                    var snapshot = graphicsProbe.snapshot();
                    return root.getAttribute('data-scene-lifecycle') === 'active'
                        && root.querySelectorAll('.warlord-sandtable-canvas').length === 1
                        && snapshot.connectedWebglCanvases === 1
                        && snapshot.activeWebglContexts === 1 ? snapshot : null;
                }, 3000);
                var live = root.querySelector('[data-region="live"]');
                if (!live || live.textContent.indexOf('关闭请求暂时没有响应') < 0
                        || restored.createdWebglCanvases !== released.createdWebglCanvases + 1) {
                    throw new Error('lost close acknowledgement did not restore exactly one usable scene');
                }
                return 'accepted close -> WebGL/rAF 0 before Host ack -> timeout restores exactly one scene';
            } finally {
                if (previousTimeout === undefined) delete window.__CF7_PANEL_CLOSE_ACK_TIMEOUT_MS__;
                else window.__CF7_PANEL_CLOSE_ACK_TIMEOUT_MS__ = previousTimeout;
                window.__warlordHarness.close();
                await waitFor(function () {
                    return document.querySelectorAll('.warlord-sandtable-canvas').length === 0
                        && graphicsProbe.activeFrameCount() === 0
                        && graphicsProbe.snapshot().activeWebglContexts === 0;
                }, 3000);
                graphicsProbe.dispose();
                window.__warlordHarness.open();
                await waitFor(function () {
                    return document.querySelector('.warlord-scale-shell[data-ready="true"][data-scene-lifecycle="active"]');
                }, 12000);
            }
        });
        await check('as2-host-reject-ai-action-is-bounded', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.clearBridgeMessages();
            window.__warlordHarness.setBattleResponseMode('reject');
            try {
                window.__warlordHarness.open({
                    source: 'runtime',
                    battleAuthority: 'as2',
                    panelInstanceId: 'warlord.qa.ai-reject',
                    preset: 'all-units',
                    seed: 'qa-as2-ai-reject'
                });
                var root = await waitFor(function () {
                    return document.querySelector('.warlord-scale-shell[data-ready="true"]');
                }, 12000);
                var end = document.querySelector('[data-action="end-action"]:not([aria-disabled="true"])');
                if (!end) throw new Error('player end-action affordance missing');
                end.click();
                await waitFor(function () {
                    return window.__warlordHarness.bridgeMessages().some(function (message) {
                        return message && message.cmd === 'battle_start';
                    });
                }, 12000);
                await waitFor(function () {
                    var app = document.querySelector('.warlord-app');
                    return root.getAttribute('data-phase') === 'SETTLEMENT_PLANNING'
                        && app && app.getAttribute('data-authority-state') === 'ready';
                }, 5000);
                await delay(1400);
                var battles = window.__warlordHarness.bridgeMessages().filter(function (message) {
                    return message && message.cmd === 'battle_start';
                });
                if (battles.length !== 1) {
                    throw new Error('AI repeated rejected battle_start ' + battles.length + ' times');
                }
                return '1 rejected battle_start · current AI action ended · no resend after 1400ms';
            } finally {
                window.__warlordHarness.setBattleResponseMode('none');
            }
        });
        await check('as2-host-reject-player-can-reselect-and-retry', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.clearBridgeMessages();
            window.__warlordHarness.setBattleResponseMode('reject');
            try {
                window.__warlordHarness.open({
                    source: 'runtime',
                    battleAuthority: 'as2',
                    panelInstanceId: 'warlord.qa.player-retry',
                    preset: 'all-units',
                    seed: 'qa-as2-player-retry'
                });
                var root = await waitFor(function () {
                    return document.querySelector('.warlord-scale-shell[data-ready="true"]');
                }, 12000);
                var beforeAp = document.querySelector('[data-testid="hud-red"]').getAttribute('data-action-points');
                await confirmPlayerAttackFromSupply(root);
                await waitFor(function () {
                    var app = document.querySelector('.warlord-app');
                    var live = document.querySelector('[data-region="live"]');
                    var count = window.__warlordHarness.bridgeMessages().filter(function (message) {
                        return message && message.cmd === 'battle_start';
                    }).length;
                    return count === 1 && app && app.getAttribute('data-authority-state') === 'ready'
                        && live && live.textContent.indexOf('重新选择部队后再试') >= 0;
                }, 5000);
                if (root.getAttribute('data-phase') !== 'FIRST_FACTION_ACTION'
                    || document.querySelector('[data-testid="hud-red"]').getAttribute('data-action-points') !== beforeAp) {
                    throw new Error('rejected player attack changed phase or action points');
                }
                await confirmPlayerAttackFromSupply(root);
                await waitFor(function () {
                    var app = document.querySelector('.warlord-app');
                    var count = window.__warlordHarness.bridgeMessages().filter(function (message) {
                        return message && message.cmd === 'battle_start';
                    }).length;
                    return count === 2 && app && app.getAttribute('data-authority-state') === 'ready';
                }, 5000);
                await delay(700);
                var battles = window.__warlordHarness.bridgeMessages().filter(function (message) {
                    return message && message.cmd === 'battle_start';
                });
                if (battles.length !== 2 || root.getAttribute('data-phase') !== 'FIRST_FACTION_ACTION') {
                    throw new Error('player retry was swallowed or automatically resent');
                }
                return 'reject keeps phase/AP · manual reselect sends exactly one new request';
            } finally {
                window.__warlordHarness.setBattleResponseMode('none');
            }
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
            var app = fallback.closest('.warlord-app');
            var vocabularyCount = assertPlayerVocabulary(app);
            var helpButton = app.querySelector('[data-action="open-help"]');
            helpButton.click();
            await delay(30);
            var help = app.querySelector('.warlord-help-dialog');
            if (!help || help.textContent.indexOf('驻军上限') < 0 || help.textContent.indexOf('行动点') < 0) {
                throw new Error('fallback did not expose the shared help profile');
            }
            assertPlayerVocabulary(help);
            help.querySelector('[data-action="close-help"]').click();
            await delay(20);
            return '9-node simplified map · shared help · vocabulary ' + vocabularyCount;
        });
        await check('demo2-thick-x-large-map-semantic-layout', async function () {
            window.__warlordHarness.close();
            await delay(30);
            window.__warlordHarness.open({
                scenarioRef: 'warlord_demo_02_v1',
                seed: 'qa-demo2-thick-x'
            });
            var root = await waitFor(function () {
                var candidate = document.querySelector('.warlord-scale-shell[data-ready="true"]');
                var tools = candidate && candidate.querySelector('[data-region="large-map"][data-total-nodes="80"]');
                var scene = candidate && candidate.querySelector('.warlord-scene-host[data-landmark-count="80"]');
                return tools && scene ? candidate : null;
            }, 12000);
            var app = root.querySelector('.warlord-app');
            var stage = document.getElementById('harness-stage');
            var commandBar = app && app.querySelector('.warlord-command-bar');
            var factions = app && app.querySelector('[data-region="factions"]');
            var factionCards = factions ? Array.from(factions.querySelectorAll('.warlord-faction')) : [];
            var victoryGroups = new Set(factionCards.map(function (faction) {
                return faction.getAttribute('data-victory-group');
            }).filter(Boolean));
            var main = app && app.querySelector('.warlord-main');
            var forceRail = app && app.querySelector('.warlord-force-rail');
            var mapStage = app && app.querySelector('.warlord-map-stage');
            var actionRail = app && app.querySelector('.warlord-action-rail');
            var roster = app && app.querySelector('.warlord-roster');
            var sceneHost = app && app.querySelector('.warlord-scene-host');
            var largeMap = app && app.querySelector('[data-region="large-map"]');
            var cameraHud = app && app.querySelector('.warlord-camera-hud');
            var nodeStrip = app && app.querySelector('.warlord-node-strip');
            var commanders = largeMap ? largeMap.querySelectorAll('[data-commander-status]') : [];
            if (!app || !stage || !commandBar || !factions || !main || !forceRail || !mapStage
                || !actionRail || !roster || !sceneHost || !largeMap || !cameraHud || !nodeStrip) {
                throw new Error('Demo2 layout surface is incomplete');
            }
            if (factionCards.length !== 4) throw new Error('Demo2 faction HUD count ' + factionCards.length + '/4');
            if (victoryGroups.size !== 3) throw new Error('Demo2 victory-group count ' + victoryGroups.size + '/3');
            if (commanders.length !== 4) throw new Error('Demo2 commander count ' + commanders.length + '/4');
            var commanderText = Array.from(commanders).map(function (commander) {
                return commander.textContent || '';
            }).join('|');
            ['我方主角', '吴豫', '阎凝儿', '袁望'].forEach(function (name) {
                if (commanderText.indexOf(name) < 0) throw new Error('Demo2 commander identity missing: ' + name);
            });
            var playerCommanderCard = forceRail.querySelector('[data-commander-role="player_avatar"]');
            if (!playerCommanderCard || playerCommanderCard.textContent.indexOf('我方主角 · 指挥官') < 0) {
                throw new Error('Demo2 player commander is not visibly bound at the authored headquarters');
            }
            if (largeMap.getAttribute('data-total-nodes') !== '80'
                || sceneHost.getAttribute('data-landmark-count') !== '80') {
                throw new Error('Demo2 map did not project all 80 nodes');
            }
            if (!largeMap.querySelector('[data-field="large-map-sector"]')
                || !largeMap.querySelector('[data-field="large-map-search"]')
                || !largeMap.querySelector('[data-action="large-map-search"]')) {
                throw new Error('Demo2 large-map search tools are missing');
            }
            var largeMapToggle = nodeStrip.querySelector('[data-action="toggle-large-map-tools"]');
            if (!largeMap.hidden || largeMap.getClientRects().length !== 0 || !largeMapToggle
                || largeMapToggle.getAttribute('aria-controls') !== 'warlord-large-map-tools'
                || largeMapToggle.getAttribute('aria-expanded') !== 'false') {
                throw new Error('Demo2 large-map tools did not start as a collapsed navigation drawer');
            }
            largeMapToggle.click();
            await waitFor(function () {
                var currentToggle = nodeStrip.querySelector('[data-action="toggle-large-map-tools"]');
                return !largeMap.hidden && currentToggle && currentToggle.getAttribute('aria-expanded') === 'true';
            }, 1000);
            await delay(20);
            window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            await waitFor(function () {
                var currentToggle = nodeStrip.querySelector('[data-action="toggle-large-map-tools"]');
                return largeMap.hidden && currentToggle && currentToggle.getAttribute('aria-expanded') === 'false'
                    ? currentToggle : null;
            }, 1000);
            var returnedToggle = nodeStrip.querySelector('[data-action="toggle-large-map-tools"]');
            if (!returnedToggle || document.activeElement !== returnedToggle || !app.isConnected) {
                throw new Error('Escape did not close the large-map drawer and return focus without closing Demo2');
            }
            returnedToggle.click();
            await waitFor(function () { return !largeMap.hidden; }, 1000);
            await delay(20);

            var visibleLimit = 6;
            var initialVisible = Number(nodeStrip.getAttribute('data-visible-nodes'));
            if (nodeStrip.getAttribute('data-total-nodes') !== '80'
                || initialVisible < 1 || initialVisible > visibleLimit
                || nodeStrip.querySelectorAll('[data-action="select-node"]').length !== initialVisible) {
                throw new Error('Demo2 context node window is not bounded');
            }
            nodeStrip.querySelector('[data-action="toggle-node-scope"]').click();
            await delay(20);
            var coveredNodes = new Set();
            var visitedPages = 0;
            while (true) {
                var pageCards = Array.from(nodeStrip.querySelectorAll('[data-action="select-node"]'));
                if (pageCards.length < 1 || pageCards.length > visibleLimit
                    || Number(nodeStrip.getAttribute('data-visible-nodes')) !== pageCards.length) {
                    throw new Error('Demo2 all-map page exceeded the six-node window');
                }
                pageCards.forEach(function (node) { coveredNodes.add(node.getAttribute('data-node')); });
                visitedPages += 1;
                var next = nodeStrip.querySelector('[data-action="node-page-next"]:not(:disabled)');
                if (!next) break;
                if (visitedPages > 20) throw new Error('Demo2 node pager did not terminate');
                next.click();
                await delay(20);
            }
            if (coveredNodes.size !== 80) throw new Error('Demo2 paged node index covered ' + coveredNodes.size + '/80');

            function containsRect(outer, inner) {
                return inner.left >= outer.left - 0.75 && inner.top >= outer.top - 0.75
                    && inner.right <= outer.right + 0.75 && inner.bottom <= outer.bottom + 0.75;
            }
            function overlaps(left, right) {
                return left.left < right.right - 0.75 && left.right > right.left + 0.75
                    && left.top < right.bottom - 0.75 && left.bottom > right.top + 0.75;
            }
            function isTopmost(element) {
                var rect = element.getBoundingClientRect();
                var topmost = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
                return Boolean(topmost && (topmost === element || element.contains(topmost)));
            }
            var stageRect = stage.getBoundingClientRect();
            var appRect = app.getBoundingClientRect();
            var commandBarRect = commandBar.getBoundingClientRect();
            var mainRect = main.getBoundingClientRect();
            var forceRect = forceRail.getBoundingClientRect();
            var mapRect = mapStage.getBoundingClientRect();
            var actionRect = actionRail.getBoundingClientRect();
            var rosterRect = roster.getBoundingClientRect();
            var toolsRect = largeMap.getBoundingClientRect();
            var cameraRect = cameraHud.getBoundingClientRect();
            var stripRect = nodeStrip.getBoundingClientRect();
            if (!containsRect(stageRect, appRect)
                || !containsRect(appRect, commandBarRect)
                || !containsRect(appRect, mainRect)
                || !containsRect(appRect, rosterRect)
                || !containsRect(mapRect, toolsRect)
                || forceRect.right > mapRect.left + 0.75
                || mapRect.right > actionRect.left + 0.75
                || mainRect.bottom > rosterRect.top + 0.75
                || commandBarRect.bottom > mainRect.top + 0.75) {
                throw new Error('Demo2 primary panel regions overflow or overlap');
            }
            if (overlaps(toolsRect, cameraRect) || overlaps(toolsRect, stripRect)) {
                throw new Error('Demo2 large-map tools are covered by camera or node navigation');
            }
            var overflowSurfaces = [
                ['app', app],
                ['command', commandBar],
                ['factions', factions],
                ['main', main],
                ['large-map', largeMap]
            ].filter(function (entry) {
                var element = entry[1];
                return element.scrollWidth > element.clientWidth || element.scrollHeight > element.clientHeight;
            }).map(function (entry) {
                var element = entry[1];
                return entry[0] + '=' + element.scrollWidth + '/' + element.clientWidth
                    + 'x' + element.scrollHeight + '/' + element.clientHeight;
            });
            if (overflowSurfaces.length > 0) {
                throw new Error('Demo2 primary panel has clipped overflow: ' + overflowSurfaces.join(', '));
            }
            if (factionCards.some(function (card) { return !containsRect(factions.getBoundingClientRect(), card.getBoundingClientRect()); })) {
                throw new Error('Demo2 four-faction HUD is clipped');
            }
            var sectorControl = largeMap.querySelector('[data-field="large-map-sector"]');
            var searchControl = largeMap.querySelector('[data-field="large-map-search"]');
            var searchButton = largeMap.querySelector('[data-action="large-map-search"]');
            if (![sectorControl, searchControl, searchButton].every(isTopmost)) {
                throw new Error('Demo2 large-map controls are visibly occluded');
            }

            var helpButton = app.querySelector('[data-action="open-help"]');
            helpButton.click();
            await delay(30);
            var help = app.querySelector('.warlord-help-dialog');
            var largeMapHelp = help && help.querySelector('[data-help-anchor="large-map"]');
            if (!largeMapHelp) throw new Error('Demo2 large-map help anchor is missing');
            largeMapHelp.click();
            var largeMapArticle = await waitFor(function () {
                return app.querySelector('[data-help-current][data-help-section="large-map"]');
            }, 3000);
            if (largeMapArticle.textContent.indexOf('四角是基地纵深') < 0
                || largeMapArticle.textContent.indexOf('中间工业环产出高') < 0
                || largeMapArticle.textContent.indexOf('外围仍有侧翼绕行线') < 0
                || largeMapArticle.textContent.indexOf('全部 80 个节点') < 0) {
                throw new Error('Demo2 thick-X navigation guidance is incomplete');
            }
            app.querySelector('.warlord-help-dialog [data-action="close-help"]').click();
            await delay(20);
            return 'scenarioRef Demo2 · default-collapsed drawer + Esc · 80 nodes · 4 factions · 3 victory groups · 4 commanders · '
                + visitedPages + ' bounded pages · thick-X guidance · no primary overlap';
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
