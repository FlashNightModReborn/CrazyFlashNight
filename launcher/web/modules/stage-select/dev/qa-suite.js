var StageSelectHarnessQA = (function() {
    'use strict';

    function waitReady(api) {
        return api.waitFor(function() {
            var state = StageSelectPanel && StageSelectPanel._debugGetState ? StageSelectPanel._debugGetState() : null;
            return state && state.isOpen ? state : null;
        }, 2000, 'stage-select ready');
    }

    function waitRuntime(api) {
        return api.waitFor(function() {
            var state = StageSelectPanel && StageSelectPanel._debugGetState ? StageSelectPanel._debugGetState() : null;
            return state && state.isOpen && state.runtimeSnapshot ? state : null;
        }, 2000, 'stage-select runtime snapshot');
    }

    // 连续换帧用例必须等当前背景完成，再切下一帧。否则 Edge 会把被替换的正常在途图片
    // 上报为 net::ERR_ABORTED，使网络严格门在所有 DOM 断言通过后仍 exit 1。
    function waitBackgroundReady(api, frame) {
        var assetUrl = frame && frame.background && frame.background.assetUrl || '';
        return api.waitFor(function() {
            var bg = document.getElementById('stage-select-bg');
            if (!bg || !bg.complete || bg.naturalWidth <= 0) return null;
            return !assetUrl || bg.src.indexOf(assetUrl) >= 0 ? bg : null;
        }, 2000, 'background ready: ' + (frame && frame.frameLabel || assetUrl));
    }

    function forEachFrameSettled(api, manifest, source, inspect) {
        var chain = Promise.resolve();
        manifest.frameOrder.forEach(function(label) {
            chain = chain.then(function() {
                StageSelectPanel._debugSetFrame(label, source);
                var frame = StageSelectData.getFrame(label);
                return waitBackgroundReady(api, frame).then(function() {
                    inspect(label, frame);
                });
            });
        });
        return chain;
    }

    function waitCurrentBackgroundReady(api) {
        var bg = document.getElementById('stage-select-bg');
        if (!bg || !bg.getAttribute('src')) return Promise.resolve();
        return api.waitFor(function() {
            return bg.complete && bg.naturalWidth > 0;
        }, 2000, 'current background before next QA case');
    }

    function runSuite(api, host, onlyCase) {
        var cases = [
            ['open-close', 'open and close lifecycle', function() {
                host.open();
                return waitReady(api).then(function() {
                    api.assertEqual(Panels.getActive(), 'stage-select', 'active panel');
                    Panels.close();
                    api.assertEqual(Panels.getActive(), null, 'panel closed');
                    host.open();
                    return waitReady(api).then(function(state) {
                        api.assert(state.layoutWatcherActive, 'layout watcher active after reopen');
                        return 'lifecycle ok';
                    });
                });
            }],
            ['scoped-warlord-test-catalog', 'test-only warlord catalog stays isolated and enters exact stageName', function() {
                var demo1 = '军阀战术演习';
                var demo2 = '军阀四方大战役（Slice 6 验收候选）';
                var productionManifest = StageSelectData.exportManifest();
                var productionNames = {};
                (productionManifest.frames || []).forEach(function(frame) {
                    (frame.stageButtons || []).forEach(function(button) {
                        productionNames[button.stageName || ''] = true;
                    });
                });
                api.assert(!productionNames[demo1] && !productionNames[demo2],
                    'production catalog contains no warlord test entry');
                api.assertEqual(StageSelectData.resolveCatalogId({ frames: [{ stageName: demo2 }] }),
                    StageSelectData.DEFAULT_CATALOG_ID, 'object catalog injection rejected');

                host.open({ catalogId: 'unknown-catalog-id', frameLabel: '军阀演习测试' });
                return waitReady(api).then(function() {
                    api.assertEqual(StageSelectData.getActiveCatalogId(), StageSelectData.DEFAULT_CATALOG_ID,
                        'unknown catalogId falls back to production');
                    api.assertEqual(document.querySelectorAll('.stage-select-stage-button[data-stage-name="' + demo1 + '"]').length,
                        0, 'unknown catalog cannot reveal Demo 1');
                    api.assertEqual(document.querySelectorAll('.stage-select-stage-button[data-stage-name="' + demo2 + '"]').length,
                        0, 'unknown catalog cannot reveal Demo 2');

                    host.enterMessages.length = 0;
                    host.sentMessages.length = 0;
                    host.open({ catalogId: StageSelectData.WARLORD_TEST_CATALOG_ID, frameLabel: '军阀演习测试', mode: 'runtime' });
                    return waitRuntime(api);
                }).then(function(state) {
                    var catalog = StageSelectData.getManifest();
                    var nodes = document.querySelectorAll('.stage-select-stage-button');
                    var snapshotMessages = host.sentMessages.filter(function(message) { return message.cmd === 'snapshot'; });
                    api.assertEqual(StageSelectData.getActiveCatalogId(), 'warlord-game-stage-test',
                        'strict test catalog activated');
                    api.assertEqual(catalog.title, '测试目录 · 军阀演习测试', 'test catalog title');
                    api.assertEqual(state.frameLabel, '军阀演习测试', 'C# fixed frameLabel retained exactly');
                    api.assertEqual(nodes.length, 2, 'test catalog renders exactly two nodes');
                    api.assertEqual(nodes[0].getAttribute('data-stage-name'), demo1, 'Demo 1 exact stageName');
                    api.assertEqual(nodes[1].getAttribute('data-stage-name'), demo2, 'Demo 2 exact stageName');
                    api.assertEqual(nodes[0].getAttribute('data-entry-kind'), 'difficulty', 'Demo 1 uses difficulty entry');
                    api.assertEqual(nodes[1].getAttribute('data-entry-kind'), 'difficulty', 'Demo 2 uses difficulty entry');
                    api.assertEqual(nodes[0].querySelector('.stage-select-stage-name').textContent, '九节点教学',
                        'Demo 1 uses short displayName');
                    api.assertEqual(nodes[1].querySelector('.stage-select-stage-name').textContent, '四方大战役',
                        'Demo 2 uses short displayName');
                    api.assertEqual(document.querySelector('#stage-select-frame-toggle-label').textContent,
                        '军阀演习测试', 'runtime title visibly identifies test catalog');
                    api.assertEqual(document.querySelector('.stage-select-frame-toggle').getAttribute('title'),
                        '测试目录 · 军阀演习测试', 'test-only boundary is persistent in title');
                    api.assertEqual(snapshotMessages.length, 1, 'test catalog sends one snapshot request');
                    api.assertEqual(snapshotMessages[0].stageNames.join('|'), demo1 + '|' + demo2,
                        'snapshot requests only the two exact test stageNames');
                    api.assertEqual(typeof snapshotMessages[0].frameLabel, 'undefined',
                        'test snapshot omits virtual current frame key');
                    api.assertEqual(typeof snapshotMessages[0].returnFrameLabel, 'undefined',
                        'test snapshot omits virtual return frame key');

                    nodes[0].click();
                    var demo1Difficulty = document.querySelector('#stage-select-inspector .stage-select-difficulty');
                    api.assertEqual(demo1Difficulty.getAttribute('data-stage-name'), demo1,
                        'Demo 1 difficulty keeps exact stageName');
                    nodes[1].click();
                    var difficulty = document.querySelector('#stage-select-inspector .stage-select-difficulty');
                    api.assert(!!difficulty, 'Demo 2 inspector exposes difficulty buttons');
                    api.assertEqual(difficulty.getAttribute('data-stage-name'), demo2,
                        'Demo 2 difficulty keeps exact stageName');
                    difficulty.click();
                    api.assertEqual(host.enterMessages.length, 1, 'one enter message sent');
                    api.assertEqual(host.enterMessages[0].stageName, demo2, 'enter keeps Demo 2 exact stageName');
                    api.assertEqual(host.enterMessages[0].entryKind, 'difficulty', 'enter remains normal difficulty route');
                    return api.waitFor(function() {
                        return StageSelectData.getActiveCatalogId() === StageSelectData.DEFAULT_CATALOG_ID
                            && (!Panels.getActive || Panels.getActive() !== 'stage-select');
                    }, 1500, 'test enter closes and restores production catalog').then(function() {
                        return 'production isolated; strict test catalog 2/2; exact enter ok';
                    });
                });
            }],
            ['scoped-warlord-test-close-gate', 'test catalog resets only after close transport is accepted', function() {
                host.open({
                    catalogId: StageSelectData.WARLORD_TEST_CATALOG_ID,
                    frameLabel: '军阀演习测试',
                    mode: 'runtime'
                });
                return waitRuntime(api).then(function() {
                    var rejected = host.withBridgeSendFault('false', function() {
                        return StageSelectRenderer.requestClose('button');
                    });
                    api.assertEqual(rejected, false, 'rejected close returns false');
                    api.assert(Panels.getActive && Panels.getActive() === 'stage-select',
                        'rejected close keeps test panel visible');
                    api.assertEqual(StageSelectData.getActiveCatalogId(), StageSelectData.WARLORD_TEST_CATALOG_ID,
                        'rejected close keeps test catalog active');

                    api.assertEqual(StageSelectRenderer.requestClose('button'), true,
                        'accepted retry closes test panel');
                    api.assert(!Panels.getActive || Panels.getActive() !== 'stage-select',
                        'accepted close removes test panel');
                    api.assertEqual(StageSelectData.getActiveCatalogId(), StageSelectData.DEFAULT_CATALOG_ID,
                        'accepted close restores production catalog');
                    return 'false preserved test; accepted close restored production';
                });
            }],
            ['frame-tabs', 'all frame labels route', function() {
                host.open();
                return waitRuntime(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    return forEachFrameSettled(api, manifest, 'qa', function(label, frame) {
                        var state = StageSelectPanel._debugGetState();
                        api.assertEqual(state.frameLabel, label, 'frame routed');
                        api.assertEqual(state.stageButtonCount, frame.stageButtons.length, 'stage button count for ' + label);
                    }).then(function() {
                        return manifest.frameOrder.length + ' frames routed';
                    });
                });
            }],
            ['fixtures', 'fixture states render', function() {
                host.open();
                return waitReady(api).then(function() {
                    StageSelectPanel._debugSetFixture('mixed');
                    var manifest = StageSelectData.getManifest();
                    var locked = 0;
                    var task = 0;
                    manifest.frameOrder.some(function(label) {
                        StageSelectPanel._debugSetFrame(label, 'qa-fixture');
                        locked = document.querySelectorAll('.stage-select-stage-button.is-locked').length;
                        task = document.querySelectorAll('.stage-select-stage-button.is-task').length;
                        return locked > 0 && task > 0;
                    });
                    api.assert(locked > 0, 'mixed fixture has locked buttons');
                    api.assert(task > 0, 'mixed fixture has task buttons');
                    StageSelectPanel._debugSetFixture('challenge');
                    StageSelectPanel._debugApplySnapshot({
                        unlockedStages: {},
                        isChallengeMode: true,
                        currentFrameLabel: StageSelectPanel._debugGetState().frameLabel
                    });
                    var state = StageSelectPanel._debugGetState();
                    // P2：卡片迁至 .stage-select-card-anchor 层（消除嵌套 button），断言同步改按锚点查询
                    var difficulties = document.querySelectorAll('.stage-select-card-anchor .stage-select-difficulty');
                    api.assert(state.challenge, 'challenge flag set');
                    api.assert(difficulties.length > 0, 'challenge difficulties rendered');
                    api.assert([].every.call(difficulties, function(btn) {
                        return btn.getAttribute('data-difficulty') === '地狱';
                    }), 'challenge only renders hell difficulty');
                    return 'fixture rendering ok';
                });
            }],
            ['hover-preview', 'stage card has preview and difficulty buttons', function() {
                host.open();
                return waitReady(api).then(function() {
                    var button = document.querySelector('.stage-select-stage-button');
                    api.assert(!!button, 'stage button exists');
                    button.focus();
                    // P2：hover 卡在锚点层；focus 驱动 .is-card-open，DOM 恒存在
                    var anchor = findCardAnchor(button.getAttribute('data-stage-id'));
                    api.assert(!!anchor, 'card anchor exists for stage');
                    api.assert(anchor.classList.contains('is-card-open'), 'focus opens hover card');
                    var preview = anchor.querySelector('.stage-select-preview');
                    var difficulties = anchor.querySelectorAll('.stage-select-difficulty');
                    api.assert(!!preview && !!preview.getAttribute('src'), 'preview image src exists');
                    api.assert(difficulties.length >= 1, 'difficulty buttons exist');
                    return 'preview card ok';
                });
            }],
            ['snapshot-live', 'snapshot overrides fixture at runtime', function() {
                host.open();
                return waitRuntime(api).then(function(state) {
                    api.assert(!!state.runtimeSnapshot.unlockedStages, 'runtime unlocked map exists');
                    api.assert(!!state.runtimeSnapshot.stageDetails, 'runtime stage details map exists');
                    api.assertEqual(state.frameLabel, document.getElementById('stage-frame-select').value, 'snapshot frame applied');
                    var detail = document.querySelector('.stage-select-card-detail');
                    api.assert(!!detail && detail.textContent.indexOf('live detail:') >= 0, 'live detail rendered');
                    api.assert(detail.textContent.indexOf('live second line') >= 0, 'encoded BR converted to line text');
                    api.assert(detail.textContent.indexOf('<BR>') < 0, 'flash html tag stripped');
                    return 'live snapshot ok';
                });
            }],
            ['runtime-task-target-indicators', 'runtime task targets stay marked while hover card remains directly actionable', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function(state) {
                    var manifest = StageSelectData.getManifest();
                    var initialFrame = state.frameLabel;
                    var target = null;
                    var findButtonEl = function(stageName) {
                        var nodes = document.querySelectorAll('.stage-select-stage-button');
                        for (var i = 0; i < nodes.length; i += 1) {
                            if (nodes[i].getAttribute('data-stage-name') === stageName) return nodes[i];
                        }
                        return null;
                    };

                    manifest.frames.some(function(frame) {
                        var buttons = frame.stageButtons || [];
                        for (var i = 0; i < buttons.length; i += 1) {
                            if ((buttons[i].entryKind || 'difficulty') !== 'difficulty') continue;
                            if (frame.frameLabel === initialFrame && manifest.frames.length > 1) continue;
                            target = {
                                frameLabel: frame.frameLabel,
                                stageName: buttons[i].stageName
                            };
                            return true;
                        }
                        return false;
                    });

                    api.assert(!!target, 'need a difficulty stage target in manifest');
                    StageSelectPanel._debugSetFixture('allUnlocked');
                    StageSelectPanel._debugApplySnapshot({
                        unlockedStages: (function() {
                            var u = {};
                            u[target.stageName] = true;
                            return u;
                        })(),
                        stageDetails: (function() {
                            var d = {};
                            d[target.stageName] = {
                                exists: true,
                                stageType: '初期关卡',
                                detail: 'live task target',
                                materialDetail: '',
                                limitDetail: '',
                                limitLevel: '',
                                task: true,
                                highestDifficulty: '修罗'
                            };
                            return d;
                        })(),
                        isChallengeMode: false,
                        currentFrameLabel: initialFrame
                    });

                    state = StageSelectPanel._debugGetState();
                    api.assert(!!state.taskTargets.byStage[target.stageName], 'debug task target should include stage');
                    api.assertEqual(state.taskTargets.byFrame[target.frameLabel], 1, 'target frame task count');
                    var toggleBadge = document.querySelector('.stage-select-frame-toggle-task-badge');
                    api.assert(!!toggleBadge && toggleBadge.textContent === '1', 'frame toggle task badge should show total');
                    var targetTab = document.querySelector('.stage-select-tab[data-frame-label="' + target.frameLabel + '"]');
                    api.assert(!!targetTab && targetTab.classList.contains('has-task'), 'target frame tab should be marked');
                    api.assertEqual((targetTab.querySelector('.stage-select-tab-task-badge') || {}).textContent, '1', 'target frame tab badge count');

                    StageSelectPanel._debugSetFrame(target.frameLabel, 'qa-task-target');
                    var targetButton = findButtonEl(target.stageName);
                    api.assert(!!targetButton, 'target stage button should exist after switching frame');
                    api.assert(targetButton.classList.contains('is-task'), 'target stage button should have task class');
                    api.assert(!!targetButton.querySelector('.stage-select-task-pulse'), 'target stage button should render task pulse');
                    targetButton.dispatchEvent(new PointerEvent('pointerenter', { bubbles: true }));
                    var targetAnchor = findCardAnchor(targetButton.getAttribute('data-stage-id'));
                    api.assert(!!targetAnchor && targetAnchor.classList.contains('is-card-open'),
                        'task hover opens local decision card without selecting the node');
                    api.assert(getComputedStyle(targetButton.querySelector('.stage-select-marker')).display !== 'none'
                            && getComputedStyle(targetButton.querySelector('.stage-select-task-pulse')).display !== 'none',
                        'task marker and pulse remain visible throughout hover');
                    api.assert(getComputedStyle(targetAnchor.querySelector('.stage-select-card')).display !== 'none'
                            && !!targetAnchor.querySelector('.stage-select-difficulty'),
                        'task hover card exposes directly clickable difficulty buttons');
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen,
                        'hover alone does not force the pinned inspector');
                    return target.stageName + ' @ ' + target.frameLabel;
                });
            }],
            ['runtime-ui', 'runtime mode hides fixture controls and dev log', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function(state) {
                    api.assertEqual(state.mode, 'runtime', 'runtime mode set');
                    api.assertEqual(getComputedStyle(document.querySelector('.stage-select-title')).display, 'none', 'test title hidden');
                    api.assertEqual(getComputedStyle(document.querySelector('.stage-select-fixture-label')).display, 'none', 'fixture label hidden');
                    api.assertEqual(getComputedStyle(document.getElementById('stage-select-fixture')).display, 'none', 'fixture select hidden');
                    api.assertEqual(getComputedStyle(document.querySelector('.stage-select-badge')).display, 'none', 'badge hidden');
                    api.assertEqual(getComputedStyle(document.getElementById('stage-select-dev-log')).display, 'none', 'dev log hidden');
                    api.assertEqual(getComputedStyle(document.getElementById('stage-select-tabs')).display, 'none', 'frame menu collapsed by default');
                    return 'runtime chrome hidden';
                });
            }],
            ['runtime-map-space', 'runtime layout gives stage most panel space', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var panel = document.querySelector('.stage-select-panel').getBoundingClientRect();
                    var shell = document.querySelector('.stage-select-stage-shell').getBoundingClientRect();
                    var stage = document.getElementById('stage-select-stage').getBoundingClientRect();
                    api.assert(shell.width / panel.width >= 0.94, 'stage shell width ratio');
                    api.assert(shell.height / panel.height >= 0.86, 'stage shell height ratio');
                    api.assert(stage.width / panel.width >= 0.86, 'scaled stage width ratio');
                    api.assert(stage.height / panel.height >= 0.78, 'scaled stage height ratio');
                    return 'runtime stage space ok';
                });
            }],
            ['runtime-frame-menu', 'runtime frame menu expands and syncs frame', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function(state) {
                    host.jumpMessages.length = 0;
                    var manifest = StageSelectData.getManifest();
                    var targetLabel = manifest.frameOrder.filter(function(label) { return label !== state.frameLabel; })[0];
                    var toggle = document.getElementById('stage-select-frame-toggle');
                    var tabs = document.getElementById('stage-select-tabs');
                    api.assert(!!toggle, 'frame toggle exists');
                    api.assertEqual(getComputedStyle(tabs).display, 'none', 'menu starts collapsed');
                    toggle.click();
                    api.assertEqual(StageSelectPanel._debugGetState().frameMenuOpen, true, 'menu state open');
                    api.assert(getComputedStyle(tabs).display !== 'none', 'menu visible');
                    var targetTab = null;
                    var tabNodes = tabs.querySelectorAll('.stage-select-tab');
                    [].some.call(tabNodes, function(tab) {
                        if (tab.getAttribute('data-frame-label') === targetLabel) {
                            targetTab = tab;
                            return true;
                        }
                        return false;
                    });
                    api.assert(!!targetTab, 'target frame tab exists');
                    targetTab.click();
                    return api.waitFor(function() {
                        return host.jumpMessages.length ? host.jumpMessages[0] : null;
                    }, 2000, 'frame menu jump').then(function(msg) {
                        api.assertEqual(msg.cmd, 'jump_frame', 'frame menu jump cmd');
                        api.assertEqual(msg.frameLabel, targetLabel, 'frame menu jump target');
                        api.assertEqual(StageSelectPanel._debugGetState().frameLabel, targetLabel, 'frame changed');
                        api.assertEqual(StageSelectPanel._debugGetState().frameMenuOpen, false, 'menu closes after select');
                        api.assertEqual(getComputedStyle(tabs).display, 'none', 'menu hidden after select');
                        return 'runtime frame menu synced';
                    });
                });
            }],
            ['runtime-frame-counter', 'runtime toggle shows current frame index out of total', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    var counter = document.getElementById('stage-select-frame-toggle-counter');
                    api.assert(!!counter, 'counter element exists');
                    var firstLabel = manifest.frameOrder[0];
                    StageSelectPanel._debugSetFrame(firstLabel, 'qa-counter');
                    api.assertEqual(counter.textContent, '1/' + manifest.frameOrder.length, 'first frame counter');
                    var lastIdx = manifest.frameOrder.length - 1;
                    StageSelectPanel._debugSetFrame(manifest.frameOrder[lastIdx], 'qa-counter');
                    api.assertEqual(counter.textContent, (lastIdx + 1) + '/' + manifest.frameOrder.length, 'last frame counter');
                    return 'counter ok';
                });
            }],
            ['runtime-frame-menu-keyboard', 'runtime frame menu supports arrow / Enter / Esc', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    host.jumpMessages.length = 0;
                    var toggle = document.getElementById('stage-select-frame-toggle');
                    var tabs = document.getElementById('stage-select-tabs');
                    toggle.focus();
                    toggle.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }));
                    api.assertEqual(StageSelectPanel._debugGetState().frameMenuOpen, true, 'menu opens via ArrowDown');
                    api.assert(document.activeElement && document.activeElement.classList.contains('stage-select-tab'), 'focus moved to a tab');
                    var initialActive = document.activeElement;
                    initialActive.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }));
                    api.assert(document.activeElement !== initialActive, 'ArrowDown moved focus');
                    var targetTab = document.activeElement;
                    var targetLabel = targetTab.getAttribute('data-frame-label');
                    targetTab.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    return api.waitFor(function() {
                        return host.jumpMessages.length ? host.jumpMessages[0] : null;
                    }, 2000, 'keyboard select').then(function(msg) {
                        api.assertEqual(msg.frameLabel, targetLabel, 'Enter selects frame');
                        api.assertEqual(StageSelectPanel._debugGetState().frameMenuOpen, false, 'menu closes after Enter');
                        api.assert(document.activeElement === toggle, 'focus returns to toggle after select');
                        toggle.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                        api.assertEqual(StageSelectPanel._debugGetState().frameMenuOpen, true, 'menu re-opens via Enter');
                        var firstFocused = document.activeElement;
                        firstFocused.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
                        api.assertEqual(StageSelectPanel._debugGetState().frameMenuOpen, false, 'Escape closes menu');
                        api.assert(document.activeElement === toggle, 'focus returns to toggle after Escape');
                        return 'keyboard nav ok';
                    });
                });
            }],
            ['runtime-nav-button-breathing', 'runtime entry nav buttons have horizontal padding and min-width', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    StageSelectPanel._debugSetFrame('基地车库', 'qa-nav-pad');
                    var entry = document.querySelector('.stage-select-nav-button.is-entry-yellow, .stage-select-nav-button.is-entry-red');
                    api.assert(!!entry, 'entry nav button exists in 基地车库');
                    var cs = getComputedStyle(entry);
                    var padL = parseFloat(cs.paddingLeft);
                    var padR = parseFloat(cs.paddingRight);
                    api.assert(padL >= 12 && padR >= 12, 'entry nav has horizontal padding >=12 (L=' + padL + ', R=' + padR + ')');
                    api.assert(parseFloat(cs.minWidth) >= 110, 'entry nav min-width >= 110');
                    api.assert(parseFloat(cs.height) >= 34, 'entry nav height >= 34');
                    var ret = document.querySelector('.stage-select-nav-button.is-return, .stage-select-nav-button.is-return-garage');
                    if (ret) {
                        var rcs = getComputedStyle(ret);
                        api.assert(parseFloat(rcs.paddingRight) >= 10, 'return nav has right padding');
                        api.assert(parseFloat(rcs.paddingLeft) >= 20, 'return nav reserves arrow space');
                    }
                    return 'nav buttons breathe';
                });
            }],
            ['runtime-scene-entry-anchor', 'runtime scene-entry ring keeps original map anchor', function() {
                host.setViewport('1366x768');
                host.open({ mode: 'dev' });
                return waitReady(api).then(function() {
                    var target = findFirstSceneEntryNav(api);
                    StageSelectPanel._debugSetFrame(target.frameLabel, 'qa-scene-anchor-dev');
                    var dev = measureSceneEntryMarker(api, target.id);
                    host.open({ mode: 'runtime', debug: false });
                    return waitRuntime(api).then(function() {
                        StageSelectPanel._debugSetFrame(target.frameLabel, 'qa-scene-anchor-runtime');
                        var runtime = measureSceneEntryMarker(api, target.id);
                        assertNear(api, runtime.x, dev.x, 0.75, 'scene-entry marker x');
                        assertNear(api, runtime.y, dev.y, 0.75, 'scene-entry marker y');
                        return target.frameLabel + ' scene-entry anchor stable';
                    });
                });
            }],
            ['runtime-card-height-measured', 'runtime card height comes from real DOM measurement, fits all text', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    var label = manifest.frameOrder[0];
                    StageSelectPanel._debugSetFrame(label, 'qa-height');
                    var btns = document.querySelectorAll('.stage-select-stage-button');
                    api.assert(btns.length > 0, 'stage buttons rendered');
                    var sample = btns[0];
                    var stageName = sample.getAttribute('data-stage-name');
                    StageSelectPanel._debugApplySnapshot({
                        unlockedStages: (function() { var u = {}; u[stageName] = true; return u; })(),
                        stageDetails: (function() {
                            var d = {};
                            d[stageName] = {
                                exists: true,
                                stageType: '初期关卡',
                                detail: '盗贼的势力范围，抢劫、杀人等犯罪是家常便饭，从某种意义上来说此地比废城区更危险。这里可以获得一些中级材料和装备碎片。',
                                materialDetail: '',
                                limitDetail: '',
                                limitLevel: '',
                                task: false,
                                highestDifficulty: '简单'
                            };
                            return d;
                        })(),
                        isChallengeMode: false,
                        currentFrameLabel: label
                    });
                    var btn = document.querySelector('.stage-select-stage-button[data-stage-name="' + stageName + '"]');
                    var declaredHeight = parseFloat(btn.style.getPropertyValue('--stage-card-height')) || 0;
                    api.assert(declaredHeight > 232, 'long text raised height past min (got ' + declaredHeight + ')');
                    btn.focus();
                    // P2：卡片在锚点层，按 stage id 反查
                    var anchor = findCardAnchor(btn.getAttribute('data-stage-id'));
                    var detail = anchor.querySelector('.stage-select-card-detail');
                    var detailScroll = detail.scrollHeight;
                    var detailCssHeight = parseFloat(getComputedStyle(detail).height) || (detail.getBoundingClientRect().height / getStageScale());
                    // declared height = baseline + measured detail. detail rendered height should fit inside card box.
                    api.assert(detailScroll <= detailCssHeight + 4, 'rendered detail fits inside box (scroll=' + detailScroll + ', box=' + Math.round(detailCssHeight) + ')');
                    return 'measured height fits text';
                });
            }],
            ['runtime-card-adaptive-width', 'runtime card stays 167 for short, 195 for medium, 220 for long names', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    var found = { short: null, medium: null, long: null, longest: null };
                    var weighName = function(s) {
                        var w = 0;
                        for (var i = 0; i < s.length; i += 1) w += s.charCodeAt(i) < 128 ? 0.58 : 1;
                        return w;
                    };
                    manifest.frameOrder.some(function(label) {
                        var f = StageSelectData.getFrame(label);
                        (f.stageButtons || []).forEach(function(b) {
                            var w = weighName(b.stageName || '');
                            if (!found.short && w <= 9.4) found.short = { label: label, name: b.stageName };
                            if (!found.medium && w > 9.4 && w <= 12.2) found.medium = { label: label, name: b.stageName };
                            if (!found.long && w > 12.2 && w <= 14.0) found.long = { label: label, name: b.stageName };
                            if (!found.longest && w > 14.0) found.longest = { label: label, name: b.stageName };
                        });
                        return found.short && found.medium && found.long && found.longest;
                    });
                    api.assert(!!found.short, 'short stage exists');
                    api.assert(!!found.medium, 'medium stage exists');
                    var measureCard = function(target) {
                        StageSelectPanel._debugSetFrame(target.label, 'qa-adaptive');
                        var btn = document.querySelector('.stage-select-stage-button[data-stage-name="' + target.name + '"]');
                        api.assert(!!btn, 'stage btn exists: ' + target.name);
                        // Read CSS variable directly: avoids stage-scale distortion in getBoundingClientRect
                        return parseFloat(btn.style.getPropertyValue('--stage-card-width')) || 0;
                    };
                    api.assertEqual(measureCard(found.short), 167, 'short card width = 167 (original)');
                    api.assertEqual(measureCard(found.medium), 195, 'medium card width = 195');
                    if (found.long) api.assertEqual(measureCard(found.long), 220, 'long card width = 220');
                    if (found.longest) {
                        StageSelectPanel._debugSetFrame(found.longest.label, 'qa-adaptive');
                        var btn = document.querySelector('.stage-select-stage-button[data-stage-name="' + found.longest.name + '"]');
                        api.assertEqual(btn.getAttribute('data-card-name-lines'), '2', 'longest uses 2-line title');
                    }
                    return 'adaptive widths ok';
                });
            }],
            ['runtime-panel-centered', 'runtime panel centers symmetrically in viewport', function() {
                host.setViewport(getHitTestViewport());
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var panel = document.querySelector('.stage-select-panel');
                    var rect = panel.getBoundingClientRect();
                    var shell = document.getElementById('viewport-shell').getBoundingClientRect();
                    var leftMargin = rect.left - shell.left;
                    var rightMargin = shell.right - rect.right;
                    api.assert(Math.abs(leftMargin - rightMargin) <= 4, 'left/right margins symmetric (L=' + leftMargin + ', R=' + rightMargin + ')');
                    return 'panel centered';
                });
            }],
            ['runtime-card-fits-long-name', 'runtime hover card widens and 2-line wraps long titles', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    var found = null;
                    var isAllCjk = function(s) {
                        for (var i = 0; i < s.length; i += 1) if (s.charCodeAt(i) < 128) return false;
                        return s.length > 0;
                    };
                    manifest.frameOrder.some(function(label) {
                        var f = StageSelectData.getFrame(label);
                        for (var i = 0; i < (f.stageButtons || []).length; i += 1) {
                            var name = f.stageButtons[i].stageName || '';
                            if (name.length >= 13 && isAllCjk(name)) {
                                found = { label: label, name: name };
                                return true;
                            }
                        }
                        return false;
                    });
                    api.assert(!!found, 'long all-CJK stage exists in fixture');
                    StageSelectPanel._debugSetFrame(found.label, 'qa-card');
                    var btn = document.querySelector('.stage-select-stage-button[data-stage-name="' + found.name + '"]');
                    api.assert(!!btn, 'long stage button rendered');
                    btn.focus();
                    // P2：卡片在锚点层，按 stage id 反查
                    var anchor = findCardAnchor(btn.getAttribute('data-stage-id'));
                    var name = anchor.querySelector('.stage-select-card-name');
                    var detail = anchor.querySelector('.stage-select-card-detail');
                    var cardW = parseFloat(btn.style.getPropertyValue('--stage-card-width')) || 0;
                    api.assert(cardW >= 215, 'runtime card width >= 215px (got ' + cardW + ')');
                    api.assertEqual(getComputedStyle(name).whiteSpace, 'normal', 'card name allows wrap in runtime');
                    api.assert(name.textContent === found.name, 'full title in DOM (no js truncation)');
                    api.assertEqual(btn.getAttribute('data-card-name-lines'), '2', 'long title uses 2-line layout');
                    return 'long title fits';
                });
            }],
            ['runtime-close-button-visible', 'runtime close button has visible glyph', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var close = document.querySelector('.stage-select-close-btn');
                    api.assert(!!close, 'close btn exists');
                    api.assertEqual(close.textContent, '✕', 'uses ✕ glyph');
                    var rect = close.getBoundingClientRect();
                    api.assert(rect.width >= 28 && rect.height >= 28, 'tappable size (>=28px)');
                    var fs = parseFloat(getComputedStyle(close).fontSize);
                    api.assert(fs >= 15, 'glyph >= 15px (got ' + fs + ')');
                    return 'close glyph visible';
                });
            }],
            ['runtime-error-toast-persists', 'logDev no longer wipes runtime error toast', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var log = document.getElementById('stage-select-dev-log');
                    log.classList.add('is-error');
                    log.textContent = 'qa_demo_error';
                    var manifest = StageSelectData.getManifest();
                    var otherLabel = manifest.frameOrder.filter(function(l) { return l !== StageSelectPanel._debugGetState().frameLabel; })[0];
                    StageSelectPanel._debugSetFrame(otherLabel, 'qa-error-keep');
                    api.assert(log.classList.contains('is-error'), 'error class persists across logDev');
                    api.assertEqual(log.textContent, 'qa_demo_error', 'error text persists');
                    return 'error toast persists';
                });
            }],
            ['runtime-local-frame-sync', 'runtime localFrame nav sends one frame sync', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    host.jumpMessages.length = 0;
                    var nav = document.querySelector('.stage-select-nav-button[data-action-kind="localFrame"]');
                    api.assert(!!nav, 'localFrame nav exists');
                    var target = nav.textContent.replace(/^进入/, '') || nav.getAttribute('data-nav-id');
                    nav.click();
                    return api.waitFor(function() {
                        return host.jumpMessages.length ? host.jumpMessages[0] : null;
                    }, 2000, 'jump frame').then(function(msg) {
                        api.assertEqual(host.jumpMessages.length, 1, 'single jump frame message');
                        api.assertEqual(msg.cmd, 'jump_frame', 'jump cmd');
                        api.assert(!!msg.frameLabel, 'jump frame label exists');
                        api.assertEqual(StageSelectPanel._debugGetState().frameLabel, msg.frameLabel, 'web frame switched');
                        return 'runtime localFrame synced ' + (target || msg.frameLabel);
                    });
                });
            }],
            ['runtime-return-close', 'runtime return nav syncs Flash frame and closes panel', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    var initialReturnFrameLabel = StageSelectPanel._debugGetState().returnFrameLabel;
                    host.returnMessages.length = 0;
                    var localNav = document.querySelector('.stage-select-nav-button[data-action-kind="localFrame"]');
                    var afterLocalFrame = Promise.resolve();
                    if (localNav) {
                        host.jumpMessages.length = 0;
                        localNav.click();
                        afterLocalFrame = api.waitFor(function() {
                            return host.jumpMessages.length ? true : null;
                        }, 2000, 'pre-return local frame jump');
                    }
                    return afterLocalFrame.then(function() {
                        var nav = document.querySelector('.stage-select-nav-button[data-action-kind="flashJumpCurrent"], .stage-select-nav-button[data-action-kind="flashJumpFrameValue"]');
                        if (!nav) {
                            manifest.frameOrder.some(function(label) {
                                StageSelectPanel._debugSetFrame(label, 'qa-return');
                                nav = document.querySelector('.stage-select-nav-button[data-action-kind="flashJumpCurrent"], .stage-select-nav-button[data-action-kind="flashJumpFrameValue"]');
                                return !!nav;
                            });
                        }
                        api.assert(!!nav, 'runtime return nav exists');
                        var expected = nav.getAttribute('data-action-kind') === 'flashJumpFrameValue'
                            ? (StageSelectData.getFrame(StageSelectPanel._debugGetState().frameLabel).navButtons.filter(function(item) {
                                return item.id === nav.getAttribute('data-nav-id');
                            })[0] || {}).targetFrameLabel
                            : initialReturnFrameLabel;
                        nav.click();
                        return api.waitFor(function() {
                            return Panels.getActive && Panels.getActive() === null && host.returnMessages.length ? true : null;
                        }, 2000, 'return close').then(function() {
                            api.assertEqual(host.returnMessages[0].cmd, 'return_frame', 'return cmd');
                            api.assertEqual(host.returnMessages[0].returnFrameLabel, expected, 'return frame label');
                            return 'runtime return synced and closed';
                        });
                    });
                });
            }],
            ['locked-no-enter', 'locked stage does not send enter', function() {
                document.getElementById('stage-fixture-select').value = 'mixed';
                host.open();
                return waitRuntime(api).then(function() {
                    api.events.length = 0;
                    host.sentMessages.length = 0;
                    var difficulty = null;
                    var lockedButton = null;
                    var manifest = StageSelectData.getManifest();
                    manifest.frameOrder.some(function(label) {
                        StageSelectPanel._debugSetFrame(label, 'qa-locked');
                        lockedButton = document.querySelector('.stage-select-stage-button.is-locked:not(.is-direct-entry)');
                        if (lockedButton) {
                            difficulty = lockedButton.querySelector('.stage-select-difficulty');
                            return true;
                        }
                        return false;
                    });
                    api.assert(!!lockedButton, 'locked button exists');
                    lockedButton.focus();
                    api.assert(getComputedStyle(lockedButton.querySelector('.stage-select-marker')).display !== 'none', 'locked marker remains visible on focus');
                    api.assert(getComputedStyle(lockedButton.querySelector('.stage-select-stage-name')).visibility !== 'hidden', 'locked label remains visible on focus');
                    // P2：锁定卡永不打开但 DOM 仍在锚点层，合成 click 走同一条 blocked 路径
                    var lockedAnchor = findCardAnchor(lockedButton.getAttribute('data-stage-id'));
                    difficulty = lockedAnchor && lockedAnchor.querySelector('.stage-select-difficulty');
                    api.assert(!!difficulty, 'difficulty button exists');
                    difficulty.click();
                    var state = StageSelectPanel._debugGetState();
                    api.assert(!!state.lastDifficultyClick, 'difficulty click recorded locally');
                    api.assertEqual(state.lastDifficultyClick.blocked, 'locked', 'locked click blocked');
                    api.assertEqual(host.sentMessages.filter(function(msg) { return msg && msg.cmd === 'enter'; }).length, 0, 'no enter Bridge.send for locked');
                    return 'locked click blocked';
                });
            }],
            ['difficulty-enter', 'unlocked difficulty sends enter and closes', function() {
                document.getElementById('stage-fixture-select').value = 'allUnlocked';
                host.open();
                return waitRuntime(api).then(function() {
                    api.events.length = 0;
                    host.enterMessages.length = 0;
                    // P2：先真实走节点 hover 开卡，再从锚点层难度按钮一步提交；不依赖固定检查器。
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    api.assert(!!node, 'unlocked difficulty node exists');
                    node.dispatchEvent(new PointerEvent('pointerenter', { bubbles: true }));
                    var anchor = findCardAnchor(node.getAttribute('data-stage-id'));
                    api.assert(!!anchor && anchor.classList.contains('is-card-open')
                            && getComputedStyle(anchor.querySelector('.stage-select-card')).display !== 'none',
                        'mouse hover visibly opens the local decision card');
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen,
                        'mouse hover direct path does not require pinned inspector');
                    var difficulty = anchor.querySelector('.stage-select-difficulty');
                    api.assert(!!difficulty, 'difficulty button exists');
                    difficulty.click();
                    return api.waitFor(function() {
                        return Panels.getActive && Panels.getActive() === null && host.enterMessages.length ? true : null;
                    }, 2000, 'enter success close').then(function() {
                        api.assertEqual(host.enterMessages[0].panel, 'stage-select', 'enter panel');
                        api.assertEqual(host.enterMessages[0].cmd, 'enter', 'enter cmd');
                        return 'enter sent and panel closed';
                    });
                });
            }],
            ['enter-error', 'enter error keeps panel open', function() {
                document.getElementById('stage-fixture-select').value = 'allUnlocked';
                host.open();
                return waitRuntime(api).then(function() {
                    host.nextEnterError = 'invalid_stage';
                    // P2：hover 卡难度按钮在锚点层
                    var difficulty = document.querySelector('.stage-select-card-anchor .stage-select-difficulty');
                    api.assert(!!difficulty, 'difficulty button exists');
                    difficulty.click();
                    return api.waitFor(function() {
                        var state = StageSelectPanel._debugGetState();
                        return state && state.lastError === 'invalid_stage' ? state : null;
                    }, 2000, 'enter error').then(function(state) {
                        api.assertEqual(Panels.getActive(), 'stage-select', 'panel remains open');
                        api.assertEqual(state.busyStageName, '', 'busy cleared');
                        return 'enter error visible';
                    });
                });
            }],
            ['transport-send-failure-settles', 'Bridge.send false/throw immediately settles every pending request and enter busy', function() {
                document.getElementById('stage-fixture-select').value = 'allUnlocked';
                host.open();
                return waitRuntime(api).then(function(initialState) {
                    function runFault(mode, label, action, expectBusyClear) {
                        var accepted = host.withBridgeSendFault(mode, action);
                        var state = StageSelectPanel._debugGetState();
                        api.assertEqual(accepted, false, label + ' reports local send failure');
                        api.assertEqual(state.pendingCount, 0, label + ' consumes exact pending synchronously');
                        api.assertEqual(state.lastError, 'send_failed', label + ' exposes send_failed instead of timeout');
                        if (expectBusyClear) api.assertEqual(state.busyStageName, '', label + ' clears enter busy');
                    }

                    runFault('false', 'snapshot false', function() {
                        return StageSelectBridge.requestSnapshot();
                    });
                    runFault('throw', 'jump_frame throw', function() {
                        return StageSelectBridge.requestJumpFrame(initialState.frameLabel, null, initialState.frameLabel);
                    });
                    runFault('false', 'enter false', function() {
                        return StageSelectBridge.requestEnter('新手练习场', '简单', 'difficulty');
                    }, true);
                    runFault('throw', 'return_frame throw', function() {
                        return StageSelectBridge.requestReturnFrame(initialState.returnFrameLabel, null);
                    });

                    var beforeRevision = StageSelectPanel._debugGetState().lastAppliedStateRevision;
                    api.assertEqual(StageSelectPanel._debugRequestSnapshot(), true, 'fresh snapshot retry is synchronously delivered');
                    return api.waitFor(function() {
                        var state = StageSelectPanel._debugGetState();
                        return state.pendingCount === 0 && state.lastAppliedStateRevision > beforeRevision
                            && !state.lastError ? state : null;
                    }, 2000, 'transport failure recovery').then(function() {
                        return 'false/throw settle immediately and fresh retry recovers';
                    });
                });
            }],
            ['transport-close-failure-retryable', 'close waits for synchronous transport acceptance and stays retryable on false/throw', function() {
                document.getElementById('stage-fixture-select').value = 'allUnlocked';
                host.open();
                return waitRuntime(api).then(function() {
                    host.nextEnterError = 'qa_hold';
                    api.assertEqual(StageSelectBridge.requestEnter('新手练习场', '简单', 'difficulty'), true,
                        'setup enter request is synchronously accepted');
                    var beforeClose = StageSelectPanel._debugGetState();
                    api.assert(beforeClose.pendingCount > 0, 'setup leaves an exact request pending');
                    api.assertEqual(beforeClose.busyStageName, '新手练习场', 'setup exposes enter busy');

                    var falseResult = host.withBridgeSendFault('false', function() {
                        return StageSelectRenderer.requestClose('button');
                    });
                    var falseState = StageSelectPanel._debugGetState();
                    api.assertEqual(falseResult, false, 'close false is reported');
                    api.assertEqual(Panels.getActive(), 'stage-select', 'close false keeps the current panel visible');
                    api.assertEqual(falseState.lastCloseSendError, 'send_failed', 'close false remains diagnostically explicit');
                    api.assertEqual(falseState.lastError, 'send_failed', 'close false exposes visible send_failed');
                    api.assertEqual(falseState.pendingCount, beforeClose.pendingCount, 'close false preserves exact pending');
                    api.assertEqual(falseState.busyStageName, beforeClose.busyStageName, 'close false preserves enter busy');

                    return api.waitFor(function() {
                        var state = StageSelectPanel._debugGetState();
                        return Panels.getActive() === 'stage-select' && state.pendingCount === 0
                            && state.busyStageName === '' && state.lastError === 'qa_hold' ? state : null;
                    }, 2000, 'preserved enter response').then(function() {
                        api.assertEqual(StageSelectRenderer.requestClose('button'), true,
                            'retry after close false is accepted');
                        api.assertEqual(Panels.getActive(), null, 'accepted retry closes the panel');
                        host.open();
                        return waitRuntime(api);
                    });
                }).then(function() {
                    var throwResult = host.withBridgeSendFault('throw', function() {
                        return StageSelectRenderer.requestClose('button');
                    });
                    var throwState = StageSelectPanel._debugGetState();
                    api.assertEqual(throwResult, false, 'close throw is contained and reported');
                    api.assertEqual(Panels.getActive(), 'stage-select', 'close throw keeps the current panel visible');
                    api.assertEqual(throwState.lastCloseSendError, 'send_failed', 'close throw remains diagnostically explicit');
                    api.assertEqual(throwState.lastError, 'send_failed', 'close throw exposes visible send_failed');
                    var closeCount = host.sentMessages.filter(function(message) {
                        return message && message.cmd === 'close';
                    }).length;
                    api.assertEqual(StageSelectRenderer.requestClose('button'), true, 'retry after close throw is accepted');
                    var finalState = StageSelectPanel._debugGetState();
                    api.assertEqual(Panels.getActive(), null, 'accepted retry closes the panel');
                    api.assertEqual(finalState.lastCloseSendError, '', 'accepted retry clears failure diagnostic');
                    api.assertEqual(host.sentMessages.filter(function(message) {
                        return message && message.cmd === 'close';
                    }).length, closeCount + 1, 'accepted retry emits one Host notification');
                    return 'close false/throw preserve visible state; accepted retry closes';
                });
            }],
            ['challenge-enter', 'challenge mode only sends hell difficulty', function() {
                document.getElementById('stage-fixture-select').value = 'challenge';
                host.open();
                return waitRuntime(api).then(function(state) {
                    api.assert(state.challenge, 'challenge flag set from snapshot');
                    // P2：hover 卡难度按钮在锚点层
                    var difficulties = document.querySelectorAll('.stage-select-card-anchor .stage-select-difficulty');
                    api.assert(difficulties.length > 0, 'challenge difficulty exists');
                    api.assert([].every.call(difficulties, function(btn) {
                        return btn.getAttribute('data-difficulty') === '地狱';
                    }), 'challenge only renders hell difficulty');
                    host.enterMessages.length = 0;
                    difficulties[0].click();
                    return api.waitFor(function() {
                        return host.enterMessages.length ? host.enterMessages[0] : null;
                    }, 2000, 'challenge enter').then(function(msg) {
                        api.assertEqual(msg.difficulty, '地狱', 'hell difficulty sent');
                        return 'challenge enter ok';
                    });
                });
            }],
            ['direct-entry-actions', 'direct map/task entries send entryKind without difficulty', function() {
                document.getElementById('stage-fixture-select').value = 'allUnlocked';
                document.getElementById('stage-frame-select').value = '地下2层';
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    StageSelectPanel._debugSetFrame('地下2层', 'qa-direct-map');
                    var directEntries = document.querySelectorAll('.stage-select-stage-button.is-direct-entry');
                    var sigils = document.querySelectorAll('.stage-select-decoration.is-magic-sigil');
                    var mapEntry = document.querySelector('.stage-select-stage-button.is-map-entry[data-stage-name="幸存者营地"]');
                    var taskEntry = document.querySelector('.stage-select-stage-button.is-task-entry[data-stage-name="菲尼克斯Lv10"]');
                    api.assert(sigils.length === 2, '地下2层 magic sigil base art rendered');
                    api.assert(directEntries.length >= 6, '地下2层 direct entries rendered');
                    api.assert(!!mapEntry, '幸存者营地 map entry rendered');
                    api.assert(!!taskEntry, '菲尼克斯Lv10 task entry rendered');
                    host.enterMessages.length = 0;
                    api.assert(!mapEntry.querySelector('.stage-select-difficulty'), 'map entry has no secondary choice');
                    mapEntry.click();
                    return api.waitFor(function() {
                        return host.enterMessages.length ? host.enterMessages[0] : null;
                    }, 2000, 'direct map enter').then(function(msg) {
                        api.assertEqual(msg.entryKind, 'map', 'map entryKind sent');
                        api.assertEqual(msg.difficulty, '', 'map difficulty empty');
                        api.assertEqual(msg.stageName, '幸存者营地', 'map stage name sent');
                    });
                }).then(function() {
                    document.getElementById('stage-frame-select').value = '地下2层';
                    host.open({ mode: 'runtime', debug: false });
                    return waitRuntime(api).then(function() {
                        StageSelectPanel._debugSetFrame('地下2层', 'qa-direct-task');
                        var taskEntry = document.querySelector('.stage-select-stage-button.is-task-entry[data-stage-name="菲尼克斯Lv10"]');
                        api.assert(!!taskEntry, '菲尼克斯Lv10 task entry rendered after reopen');
                        host.enterMessages.length = 0;
                        api.assert(!taskEntry.querySelector('.stage-select-difficulty'), 'task entry has no secondary choice');
                        taskEntry.click();
                        return api.waitFor(function() {
                            return host.enterMessages.length ? host.enterMessages[0] : null;
                        }, 2000, 'direct task enter').then(function(msg) {
                            api.assertEqual(msg.entryKind, 'task', 'task entryKind sent');
                            api.assertEqual(msg.difficulty, '', 'task difficulty empty');
                            api.assertEqual(msg.stageName, '菲尼克斯Lv10', 'task stage name sent');
                            return 'direct entries ok';
                        });
                    });
                });
            }],
            ['runtime-diplomacy-layout', 'runtime diplomacy map points follow XFL internal marker/text matrices', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    var checked = 0;
                    manifest.frames.forEach(function(frame) {
                        var mapButtons = (frame.stageButtons || []).filter(function(button) {
                            return button.entryKind === 'map';
                        });
                        if (!mapButtons.length) return;
                        StageSelectPanel._debugSetFrame(frame.frameLabel, 'qa-diplomacy-layout');
                        var stage = document.querySelector('.stage-select-stage');
                        var stageRect = stage.getBoundingClientRect();
                        var scale = stageRect.width / 1024;
                        mapButtons.forEach(function(button) {
                            var layout = button.directLayout || {};
                            var markerLayout = layout.marker || {};
                            var textLayout = layout.text || {};
                            var node = document.querySelector('.stage-select-stage-button[data-stage-id="' + button.id + '"]');
                            api.assert(!!node, 'map node exists: ' + button.stageName);
                            var marker = node.querySelector('.stage-select-marker');
                            var label = node.querySelector('.stage-select-stage-name');
                            api.assert(!!marker, 'map marker exists: ' + button.stageName);
                            api.assert(!!label, 'map label exists: ' + button.stageName);

                            var markerRect = marker.getBoundingClientRect();
                            var labelRect = label.getBoundingClientRect();
                            var markerX = (markerRect.left - stageRect.left + markerRect.width / 2) / scale;
                            var markerY = (markerRect.top - stageRect.top + markerRect.height / 2) / scale;
                            var labelX = (labelRect.left - stageRect.left) / scale;
                            var labelY = (labelRect.top - stageRect.top) / scale;
                            var expectedMarkerX = button.x + Number(markerLayout.x || 0);
                            var expectedMarkerY = button.y + Number(markerLayout.y || 0);
                            var expectedLabelX = button.x + Number(textLayout.x || 0);
                            var expectedLabelY = button.y + Number(textLayout.y || 0);
                            api.assert(Math.abs(markerX - expectedMarkerX) < 0.8, 'marker x matches XFL: ' + button.stageName);
                            api.assert(Math.abs(markerY - expectedMarkerY) < 0.8, 'marker y matches XFL: ' + button.stageName);
                            api.assert(Math.abs(labelX - expectedLabelX) < 1.2, 'label x matches XFL: ' + button.stageName);
                            api.assert(Math.abs(labelY - expectedLabelY) < 1.2, 'label y matches XFL: ' + button.stageName);
                            if (textLayout.label) {
                                api.assertEqual(label.textContent, textLayout.label, 'label text matches XFL: ' + button.stageName);
                            }
                            checked += 1;
                        });
                    });
                    api.assertEqual(checked, StageSelectGolden.expected.mapStageButtonInstances, 'checked diplomacy map entries (golden)');
                    return 'diplomacy map layout ok';
                });
            }],
            ['viewports', 'supported viewports keep stage visible', function() {
                var presets = ['1024x576', '1366x768', '1920x1080'];
                presets.forEach(function(preset) {
                    host.setViewport(preset);
                    host.open();
                    var shell = document.querySelector('.stage-select-stage-shell').getBoundingClientRect();
                    var stage = document.getElementById('stage-select-stage').getBoundingClientRect();
                    api.assert(stage.width > 300 && stage.height > 160, 'stage visible at ' + preset);
                    api.assert(stage.left < shell.right && stage.right > shell.left, 'stage intersects shell x at ' + preset);
                    api.assert(stage.top < shell.bottom && stage.bottom > shell.top, 'stage intersects shell y at ' + preset);
                });
                return 'viewport fit ok';
            }],
            ['background-rects', 'background rect follows manifest matrix', function() {
                host.open();
                return waitRuntime(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    return forEachFrameSettled(api, manifest, 'qa-bg', function(label, frame) {
                        var expected = frame.background && frame.background.rect;
                        var bg = document.getElementById('stage-select-bg');
                        api.assert(!!expected, 'background rect missing for ' + label);
                        assertNear(api, parseFloat(bg.style.left), expected.x, 0.51, 'bg x ' + label);
                        assertNear(api, parseFloat(bg.style.top), expected.y, 0.51, 'bg y ' + label);
                        assertNear(api, parseFloat(bg.style.width), expected.w, 0.51, 'bg w ' + label);
                        assertNear(api, parseFloat(bg.style.height), expected.h, 0.51, 'bg h ' + label);
                    }).then(function() {
                        return manifest.frameOrder.length + ' background rects checked';
                    });
                });
            }],
            ['button-anchors', 'button anchors follow manifest positions', function() {
                host.open();
                return waitRuntime(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    var checked = 0;
                    return forEachFrameSettled(api, manifest, 'qa-anchor', function(label, frame) {
                        (frame.stageButtons || []).forEach(function(button) {
                            if (button.entryKind === 'map' || button.entryKind === 'task') return;
                            var node = document.querySelector('.stage-select-stage-button[data-stage-id="' + button.id + '"]');
                            api.assert(!!node, 'missing button node ' + button.id);
                            assertNear(api, parseFloat(node.style.left), button.x, 0.01, 'button x ' + button.id);
                            assertNear(api, parseFloat(node.style.top), button.y, 0.01, 'button y ' + button.id);
                            checked += 1;
                        });
                    }).then(function() {
                        return checked + ' anchors checked';
                    });
                });
            }],
            ['hit-test', 'top controls and sample stage buttons are usable', function() {
                host.setViewport(getHitTestViewport());
                host.open();
                return waitReady(api).then(function() {
                    assertHit(api, document.querySelector('.stage-select-close-btn'), 'close button');
                    assertHit(api, document.querySelector('.stage-select-tab.is-active'), 'active tab');
                    var buttons = document.querySelectorAll('.stage-select-stage-button');
                    var checked = 0;
                    [].some.call(buttons, function(button) {
                        var rect = button.getBoundingClientRect();
                        if (rect.right < 0 || rect.left > window.innerWidth || rect.bottom < 0 || rect.top > window.innerHeight) return false;
                        assertHit(api, button, 'stage button ' + button.getAttribute('data-stage-name'));
                        var hitZone = button.querySelector('.stage-select-hit-zone');
                        var hitRect = hitZone && hitZone.getBoundingClientRect();
                        if (hitRect && hitRect.width > 0 && hitRect.height > 0) {
                            assertHitAt(api, button, hitRect.left + hitRect.width / 2, hitRect.top + hitRect.height / 2, 'stage marker hit-zone ' + button.getAttribute('data-stage-name'));
                        }
                        checked += 1;
                        return checked >= 3;
                    });
                    api.assert(checked >= 1, 'at least one visible stage button hit-tested');
                    return checked + ' stage buttons hit-tested';
                });
            }],
            ['keyboard-enter-opens-inspector', 'Enter on stage node selects and pins inspector with focus inside', function() {
                document.getElementById('stage-fixture-select').value = 'mixed';
                host.open();
                return waitReady(api).then(function() {
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    api.assert(!!node, 'unlocked difficulty node exists');
                    var stageId = node.getAttribute('data-stage-id');
                    node.focus();
                    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    var state = StageSelectPanel._debugGetState();
                    api.assertEqual(state.selectedStageId, stageId, 'node selected via Enter');
                    api.assert(state.inspectorOpen, 'inspector open');
                    api.assert(node.classList.contains('is-selected'), 'node has is-selected');
                    api.assertEqual(node.getAttribute('aria-expanded'), 'true', 'node aria-expanded true');
                    api.assert(getComputedStyle(document.getElementById('stage-select-inspector')).display !== 'none', 'inspector visible');
                    api.assert(document.getElementById('stage-select-inspector-name').textContent.length > 0, 'inspector name filled');
                    api.assert(!!(document.activeElement && document.activeElement.classList.contains('stage-select-difficulty')), 'focus moved into inspector difficulty');
                    var anchor = findCardAnchor(stageId);
                    api.assert(!!anchor && !anchor.classList.contains('is-card-open'), 'selected node suppresses hover card');
                    var difficulties = document.querySelectorAll('#stage-select-inspector-difficulties .stage-select-difficulty');
                    api.assertEqual(difficulties.length, 4, 'inspector renders 4 difficulties');
                    return 'keyboard enter opens inspector';
                });
            }],
            ['inspector-difficulty-enter', 'inspector difficulty button keeps enter payload unchanged', function() {
                document.getElementById('stage-fixture-select').value = 'allUnlocked';
                host.open();
                return waitRuntime(api).then(function() {
                    host.enterMessages.length = 0;
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    var stageName = node.getAttribute('data-stage-name');
                    node.focus();
                    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    var focused = document.activeElement;
                    api.assert(!!(focused && focused.classList.contains('stage-select-difficulty')), 'focus on inspector difficulty');
                    var expectedDifficulty = focused.getAttribute('data-difficulty');
                    api.assert(focused.tabIndex !== -1, 'inspector difficulty is tabbable');
                    api.assert(parseFloat(getComputedStyle(focused).height) >= 40, 'inspector difficulty hit height >= 40 (got ' + getComputedStyle(focused).height + ')');
                    focused.click(); // 与 hover 卡鼠标点击共用 handleDifficultyClick 委派
                    return api.waitFor(function() {
                        return Panels.getActive && Panels.getActive() === null && host.enterMessages.length ? true : null;
                    }, 2000, 'inspector enter close').then(function() {
                        var msg = host.enterMessages[0];
                        api.assertEqual(msg.cmd, 'enter', 'enter cmd');
                        api.assertEqual(msg.stageName, stageName, 'enter stageName unchanged');
                        api.assertEqual(msg.difficulty, expectedDifficulty, 'enter difficulty unchanged');
                        api.assertEqual(msg.entryKind, 'difficulty', 'enter entryKind difficulty');
                        return 'inspector enter payload ok: ' + stageName + ' / ' + expectedDifficulty;
                    });
                });
            }],
            ['inspector-difficulty-arrow-nav', 'inspector arrows cycle difficulties with own-color focus glow; node arrows reclaimed; Enter submits focused', function() {
                document.getElementById('stage-fixture-select').value = 'allUnlocked';
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    var stageId = node.getAttribute('data-stage-id');
                    node.focus();
                    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'inspector open');
                    var activeDiff = function() {
                        return document.activeElement && document.activeElement.classList && document.activeElement.classList.contains('stage-select-difficulty')
                            ? document.activeElement.getAttribute('data-difficulty') : '';
                    };
                    var key = function(k) {
                        document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));
                    };
                    api.assertEqual(activeDiff(), '简单', 'initial focus on first difficulty (no task in allUnlocked)');
                    key('ArrowRight');
                    api.assertEqual(activeDiff(), '冒险', 'ArrowRight moves to next difficulty');
                    key('ArrowRight');
                    key('ArrowRight');
                    api.assertEqual(activeDiff(), '地狱', 'ArrowRight walks to hell');
                    key('ArrowRight');
                    api.assertEqual(activeDiff(), '简单', 'ArrowRight wraps to first (cycle, same as frame menu)');
                    key('ArrowLeft');
                    api.assertEqual(activeDiff(), '地狱', 'ArrowLeft wraps to last (cycle)');
                    // 焦点即选中高亮：各按钮自身色系 outline + 外发光（不套通用蓝环）
                    var glow = getComputedStyle(document.activeElement);
                    api.assert(glow.outlineStyle === 'solid' && cssNumber(glow.outlineWidth) >= 2, 'focused difficulty has solid own-color outline');
                    api.assert(glow.boxShadow.indexOf('rgb') >= 0, 'focused difficulty has glow box-shadow');
                    // ↑/↓ 定义为无操作
                    key('ArrowUp');
                    api.assertEqual(activeDiff(), '地狱', 'ArrowUp is no-op inside inspector');
                    key('ArrowDown');
                    api.assertEqual(activeDiff(), '地狱', 'ArrowDown is no-op inside inspector');
                    // 检查器打开期间节点方向键不再走地图几何导航：截停并回引焦点进检查器
                    node.focus();
                    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true }));
                    api.assert(!!(document.activeElement && document.activeElement.classList.contains('stage-select-difficulty')), 'node arrow reclaimed into inspector difficulty row');
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'inspector survives node arrow reclaim');
                    // 鼠标 hover 卡路径不受影响：悬停其他节点仍开卡，检查器保持 pinned
                    var other = null;
                    var nodes = document.querySelectorAll('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    for (var i = 0; i < nodes.length; i += 1) {
                        if (nodes[i].getAttribute('data-stage-id') !== stageId) { other = nodes[i]; break; }
                    }
                    api.assert(!!other, 'another unlocked node exists');
                    other.dispatchEvent(new PointerEvent('pointerenter', { bubbles: true }));
                    var otherAnchor = findCardAnchor(other.getAttribute('data-stage-id'));
                    api.assert(!!otherAnchor && otherAnchor.classList.contains('is-card-open'), 'hover card still opens for other node');
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'inspector stays pinned while hover card open');
                    other.dispatchEvent(new PointerEvent('pointerleave', { bubbles: true }));
                    // Esc 关检查器并归还焦点到触发节点
                    key('Escape');
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen, 'Esc closes inspector after arrow nav');
                    api.assert(document.activeElement === node, 'Esc returns focus to trigger node');
                    // 重开后 Enter 提交当前焦点难度（走 handleDifficultyClick 委派，payload 不变）
                    host.enterMessages.length = 0;
                    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    key('ArrowRight');
                    api.assertEqual(activeDiff(), '冒险', 'reopened and moved to adventure');
                    key('Enter');
                    return api.waitFor(function() {
                        return Panels.getActive && Panels.getActive() === null && host.enterMessages.length ? true : null;
                    }, 2000, 'arrow-nav enter close').then(function() {
                        var msg = host.enterMessages[0];
                        api.assertEqual(msg.cmd, 'enter', 'enter cmd');
                        api.assertEqual(msg.difficulty, '冒险', 'Enter submits focused difficulty');
                        api.assertEqual(msg.entryKind, 'difficulty', 'entryKind unchanged');
                        return 'arrow nav cycle + enter submit ok';
                    });
                });
            }],
            ['inspector-arrow-challenge-single', 'challenge mode arrow keys stay on single hell difficulty and Enter submits it', function() {
                document.getElementById('stage-fixture-select').value = 'challenge';
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    host.enterMessages.length = 0;
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    var stageName = node.getAttribute('data-stage-name');
                    node.focus();
                    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'challenge inspector open');
                    var difficulties = document.querySelectorAll('#stage-select-inspector-difficulties .stage-select-difficulty');
                    api.assertEqual(difficulties.length, 1, 'challenge single difficulty');
                    api.assert(document.activeElement === difficulties[0], 'focus on hell button');
                    document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true }));
                    api.assert(document.activeElement === difficulties[0], 'ArrowRight stays on single hell');
                    document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true, cancelable: true }));
                    api.assert(document.activeElement === difficulties[0], 'ArrowLeft stays on single hell');
                    document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    return api.waitFor(function() {
                        return host.enterMessages.length ? host.enterMessages[0] : null;
                    }, 2000, 'challenge arrow enter').then(function(msg) {
                        api.assertEqual(msg.difficulty, '地狱', 'challenge submits hell');
                        api.assertEqual(msg.stageName, stageName, 'stageName unchanged');
                        return 'challenge single-key arrow nav ok';
                    });
                });
            }],
            ['inspector-arrow-locked-noop', 'locked inspector arrow keys do not steal focus from close button', function() {
                document.getElementById('stage-fixture-select').value = 'mixed';
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var lockedNode = null;
                    var manifest = StageSelectData.getManifest();
                    manifest.frameOrder.some(function(label) {
                        StageSelectPanel._debugSetFrame(label, 'qa-locked-arrow');
                        lockedNode = document.querySelector('.stage-select-stage-button.is-locked:not(.is-direct-entry)');
                        return !!lockedNode;
                    });
                    api.assert(!!lockedNode, 'locked node exists');
                    lockedNode.focus();
                    lockedNode.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'locked inspector open');
                    var closeEl = document.getElementById('stage-select-inspector-close');
                    api.assert(document.activeElement === closeEl, 'focus on close button for locked');
                    ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].forEach(function(k) {
                        document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));
                        api.assert(document.activeElement === closeEl, k + ' keeps focus on close (no difficulty buttons)');
                    });
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'locked inspector survives arrows');
                    document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen, 'Esc closes locked inspector');
                    api.assert(document.activeElement === lockedNode, 'focus returned to locked node');
                    return 'locked arrow noop ok';
                });
            }],
            ['esc-layering', 'Escape consumes frame menu > inspector > panel in order on both paths', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    node.focus();
                    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'inspector open');
                    var toggle = document.getElementById('stage-select-frame-toggle');
                    toggle.click();
                    api.assertEqual(StageSelectPanel._debugGetState().frameMenuOpen, true, 'frame menu open above inspector');
                    // 页内 Esc 第一层：区域菜单已消费（defaultPrevented），检查器不落穿
                    toggle.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
                    api.assertEqual(StageSelectPanel._debugGetState().frameMenuOpen, false, 'Esc closes frame menu first');
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'inspector survives menu Esc');
                    // 页内 Esc 第二层：关检查器并把焦点还给触发节点
                    document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen, 'Esc closes inspector');
                    api.assertEqual(StageSelectPanel._debugGetState().selectedStageId, '', 'selection cleared');
                    api.assert(document.activeElement === node, 'focus returned to trigger node');
                    api.assertEqual(Panels.getActive(), 'stage-select', 'panel still open after inspector Esc');
                    // 面板级 panel_esc（C# 物理 Esc 路径）同序分层
                    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'inspector reopened');
                    window.chrome.webview.__dispatch({ type: 'panel_esc', reason: 'escape' });
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen, 'panel_esc closes inspector');
                    api.assertEqual(Panels.getActive(), 'stage-select', 'panel survives inspector-level panel_esc');
                    toggle.click();
                    api.assertEqual(StageSelectPanel._debugGetState().frameMenuOpen, true, 'frame menu reopened');
                    window.chrome.webview.__dispatch({ type: 'panel_esc', reason: 'escape' });
                    api.assertEqual(StageSelectPanel._debugGetState().frameMenuOpen, false, 'panel_esc closes menu first');
                    api.assertEqual(Panels.getActive(), 'stage-select', 'panel survives menu-level panel_esc');
                    window.chrome.webview.__dispatch({ type: 'panel_esc', reason: 'escape' });
                    api.assertEqual(Panels.getActive(), null, 'final panel_esc closes panel');
                    return 'esc layering ok';
                });
            }],
            ['arrow-navigation', 'arrow keys move focus to geometric nearest node with roving tabindex', function() {
                host.open();
                return waitReady(api).then(function() {
                    var frame = StageSelectData.getFrame(StageSelectPanel._debugGetState().frameLabel);
                    var buttons = frame.stageButtons || [];
                    api.assert(buttons.length >= 2, 'frame has multiple stage buttons');
                    var found = null;
                    var keys = ['ArrowRight', 'ArrowDown', 'ArrowLeft', 'ArrowUp'];
                    for (var i = 0; i < buttons.length && !found; i += 1) {
                        for (var j = 0; j < keys.length; j += 1) {
                            var target = qaNearest(buttons, buttons[i], keys[j]);
                            if (target) {
                                found = { origin: buttons[i], key: keys[j], target: target };
                                break;
                            }
                        }
                    }
                    api.assert(!!found, 'a navigable origin/direction pair exists');
                    var originNode = document.querySelector('.stage-select-stage-button[data-stage-id="' + found.origin.id + '"]');
                    api.assert(!!originNode, 'origin node exists');
                    originNode.focus();
                    api.assertEqual(originNode.tabIndex, 0, 'focused node is the tab stop');
                    originNode.dispatchEvent(new KeyboardEvent('keydown', { key: found.key, bubbles: true, cancelable: true }));
                    var targetNode = document.querySelector('.stage-select-stage-button[data-stage-id="' + found.target.id + '"]');
                    api.assert(!!targetNode, 'target node exists');
                    api.assert(document.activeElement === targetNode, found.key + ' focused geometric nearest node');
                    api.assertEqual(targetNode.tabIndex, 0, 'roving tabindex moved to target');
                    api.assertEqual(originNode.tabIndex, -1, 'origin roved out of tab order');
                    return found.origin.stageName + ' -> ' + found.key + ' -> ' + found.target.stageName;
                });
            }],
            ['locked-node-inspector', 'locked node is focusable, readable, and inspector shows lock reason', function() {
                document.getElementById('stage-fixture-select').value = 'mixed';
                host.open();
                return waitRuntime(api).then(function() {
                    host.sentMessages.length = 0;
                    var lockedNode = null;
                    var manifest = StageSelectData.getManifest();
                    manifest.frameOrder.some(function(label) {
                        StageSelectPanel._debugSetFrame(label, 'qa-locked-inspector');
                        lockedNode = document.querySelector('.stage-select-stage-button.is-locked:not(.is-direct-entry)');
                        return !!lockedNode;
                    });
                    api.assert(!!lockedNode, 'locked node exists');
                    lockedNode.focus();
                    api.assertEqual(lockedNode.getAttribute('aria-disabled'), 'true', 'locked node aria-disabled');
                    api.assert((lockedNode.getAttribute('aria-label') || '').indexOf('未解锁') >= 0, 'locked node has readable label');
                    api.assertEqual(lockedNode.tabIndex, 0, 'locked node stays in roving tab order');
                    lockedNode.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'inspector opens for locked node');
                    var lockEl = document.getElementById('stage-select-inspector-lock');
                    api.assert(!lockEl.hidden && lockEl.textContent.indexOf('未解锁') >= 0, 'lock reason text shown');
                    // 逐关锁定原因专项：harness mock 对锁定关卡下发具体 lockReason，检查器应原样展示
                    api.assert(lockEl.textContent.indexOf('主线任务进度达到 75 解锁（当前 42）') >= 0, 'inspector shows snapshot-provided lockReason');
                    var difficulties = document.querySelectorAll('#stage-select-inspector-difficulties .stage-select-difficulty');
                    api.assertEqual(difficulties.length, 0, 'locked inspector renders no difficulty buttons');
                    api.assert(document.activeElement === document.getElementById('stage-select-inspector-close'), 'focus lands on inspector close for locked');
                    api.assertEqual(host.sentMessages.filter(function(msg) { return msg && msg.cmd === 'enter'; }).length, 0, 'no enter sent for locked');
                    document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen, 'Esc closes locked inspector');
                    api.assert(document.activeElement === lockedNode, 'focus returned to locked node');
                    return 'locked inspector ok';
                });
            }],
            ['locked-inspector-fallback', 'locked inspector falls back to generic reason when snapshot omits lockReason', function() {
                document.getElementById('stage-fixture-select').value = 'mixed';
                host.open();
                return waitRuntime(api).then(function() {
                    var lockedNode = null;
                    var manifest = StageSelectData.getManifest();
                    manifest.frameOrder.some(function(label) {
                        StageSelectPanel._debugSetFrame(label, 'qa-locked-fallback');
                        lockedNode = document.querySelector('.stage-select-stage-button.is-locked:not(.is-direct-entry)');
                        return !!lockedNode;
                    });
                    api.assert(!!lockedNode, 'locked node exists');
                    var stageName = lockedNode.getAttribute('data-stage-name');
                    var stageId = lockedNode.getAttribute('data-stage-id');
                    // 旧形状快照（stageDetails 无 lockReason 字段）：检查器应回退通用文案
                    var snapshot = {
                        unlockedStages: {},
                        stageDetails: {},
                        isChallengeMode: false,
                        currentFrameLabel: StageSelectPanel._debugGetState().frameLabel
                    };
                    snapshot.unlockedStages[stageName] = false;
                    snapshot.stageDetails[stageName] = {
                        exists: true,
                        stageType: '无限过图',
                        detail: 'live detail: ' + stageName,
                        materialDetail: '',
                        limitations: [],
                        limitLevel: '',
                        task: false,
                        highestDifficulty: '简单'
                    };
                    StageSelectPanel._debugApplySnapshot(snapshot);
                    var rebuilt = document.querySelector('.stage-select-stage-button[data-stage-id="' + stageId + '"]');
                    api.assert(!!rebuilt && rebuilt.classList.contains('is-locked'), 'node stays locked after snapshot');
                    rebuilt.focus();
                    rebuilt.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'inspector opens for locked node');
                    var lockEl = document.getElementById('stage-select-inspector-lock');
                    api.assert(!lockEl.hidden, 'lock line visible');
                    api.assert(lockEl.textContent.indexOf('未解锁：该关卡尚未开放') >= 0, 'generic fallback reason shown');
                    return 'locked inspector fallback ok';
                });
            }],
            ['selection-persists-rebuild', 'selection and inspector survive snapshot merge and same-frame re-render', function() {
                host.open();
                return waitReady(api).then(function() {
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    var stageId = node.getAttribute('data-stage-id');
                    var stageName = node.getAttribute('data-stage-name');
                    node.click();
                    var state = StageSelectPanel._debugGetState();
                    api.assertEqual(state.selectedStageId, stageId, 'click selects node');
                    api.assert(state.inspectorOpen, 'inspector pinned by click');
                    var snapshot = { unlockedStages: {}, stageDetails: {}, isChallengeMode: false, currentFrameLabel: state.frameLabel };
                    snapshot.unlockedStages[stageName] = true;
                    StageSelectPanel._debugApplySnapshot(snapshot);
                    var rebuilt = document.querySelector('.stage-select-stage-button[data-stage-id="' + stageId + '"]');
                    api.assert(!!rebuilt && rebuilt !== node, 'nodes rebuilt by snapshot');
                    api.assert(rebuilt.classList.contains('is-selected'), 'selection restored by stage id');
                    api.assertEqual(rebuilt.getAttribute('aria-expanded'), 'true', 'aria-expanded restored');
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'inspector survives snapshot');
                    api.assert(document.getElementById('stage-select-inspector-name').textContent.length > 0, 'inspector content re-rendered');
                    StageSelectPanel._debugSetFrame(state.frameLabel, 'qa-reselect');
                    var rebuilt2 = document.querySelector('.stage-select-stage-button[data-stage-id="' + stageId + '"]');
                    api.assert(rebuilt2.classList.contains('is-selected'), 'selection survives same-frame setFrame');
                    rebuilt2.focus();
                    StageSelectPanel._debugApplySnapshot(snapshot);
                    var rebuilt3 = document.querySelector('.stage-select-stage-button[data-stage-id="' + stageId + '"]');
                    api.assert(document.activeElement === rebuilt3, 'focus restored to rebuilt node');
                    rebuilt3.click();
                    api.assertEqual(StageSelectPanel._debugGetState().selectedStageId, '', 're-click same node deselects');
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen, 'inspector closed after deselect');
                    return 'selection persists across rebuilds';
                });
            }],
            ['direct-entry-no-inspector', 'direct entries keep one-step enter and never open inspector', function() {
                document.getElementById('stage-fixture-select').value = 'allUnlocked';
                document.getElementById('stage-frame-select').value = '地下2层';
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    StageSelectPanel._debugSetFrame('地下2层', 'qa-direct-no-inspector');
                    var mapEntry = document.querySelector('.stage-select-stage-button.is-map-entry[data-stage-name="幸存者营地"]');
                    api.assert(!!mapEntry, 'map entry rendered');
                    host.enterMessages.length = 0;
                    mapEntry.focus();
                    mapEntry.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen, 'no inspector for map entry');
                    api.assertEqual(StageSelectPanel._debugGetState().selectedStageId, '', 'no selection for map entry');
                    return api.waitFor(function() {
                        return host.enterMessages.length ? host.enterMessages[0] : null;
                    }, 2000, 'direct map enter via keyboard').then(function(msg) {
                        api.assertEqual(msg.entryKind, 'map', 'map entryKind sent');
                        api.assertEqual(msg.difficulty, '', 'map difficulty empty');
                    });
                }).then(function() {
                    document.getElementById('stage-frame-select').value = '地下2层';
                    host.open({ mode: 'runtime', debug: false });
                    return waitRuntime(api).then(function() {
                        StageSelectPanel._debugSetFrame('地下2层', 'qa-direct-no-inspector-task');
                        var taskEntry = document.querySelector('.stage-select-stage-button.is-task-entry[data-stage-name="菲尼克斯Lv10"]');
                        api.assert(!!taskEntry, 'task entry rendered');
                        host.enterMessages.length = 0;
                        taskEntry.focus();
                        taskEntry.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true, cancelable: true }));
                        api.assert(!StageSelectPanel._debugGetState().inspectorOpen, 'no inspector for task entry');
                        return api.waitFor(function() {
                            return host.enterMessages.length ? host.enterMessages[0] : null;
                        }, 2000, 'direct task enter via keyboard').then(function(msg) {
                            api.assertEqual(msg.entryKind, 'task', 'task entryKind sent');
                            api.assertEqual(msg.difficulty, '', 'task difficulty empty');
                            return 'direct entries bypass inspector';
                        });
                    });
                });
            }],
            ['challenge-inspector-hell-only', 'challenge mode inspector renders only hell difficulty', function() {
                document.getElementById('stage-fixture-select').value = 'challenge';
                host.open();
                return waitRuntime(api).then(function(state) {
                    api.assert(state.challenge, 'challenge flag set');
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    api.assert(!!node, 'challenge node exists');
                    node.focus();
                    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'challenge inspector open');
                    var difficulties = document.querySelectorAll('#stage-select-inspector-difficulties .stage-select-difficulty');
                    api.assertEqual(difficulties.length, 1, 'challenge inspector single difficulty');
                    api.assertEqual(difficulties[0].getAttribute('data-difficulty'), '地狱', 'challenge inspector renders hell only');
                    return 'challenge inspector hell only';
                });
            }],
            ['blank-click-clears-selection', 'clicking stage blank area clears selection and inspector', function() {
                host.open();
                return waitReady(api).then(function() {
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    node.click();
                    api.assert(StageSelectPanel._debugGetState().inspectorOpen, 'inspector open after click');
                    document.getElementById('stage-select-bg').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                    api.assertEqual(StageSelectPanel._debugGetState().selectedStageId, '', 'blank click clears selection');
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen, 'inspector hidden after blank click');
                    return 'blank click clears';
                });
            }],
            // ── P3 会话守卫用例（协议加固；mock 回显对位 C# 代封）──────────────────
            ['session-request-envelope', 'requests carry panelInstanceId + sessionGeneration + catalogVersion', function() {
                host.open({ panelInstanceId: 'qa-instance-1' });
                return waitRuntime(api).then(function(state) {
                    api.assertEqual(state.panelInstanceId, 'qa-instance-1', 'bound instance id from initData');
                    var manifest = StageSelectData.getManifest();
                    var snapshotMsg = null;
                    for (var i = host.sentMessages.length - 1; i >= 0; i -= 1) {
                        if (host.sentMessages[i].cmd === 'snapshot') { snapshotMsg = host.sentMessages[i]; break; }
                    }
                    api.assert(!!snapshotMsg, 'snapshot request sent');
                    api.assertEqual(snapshotMsg.panelInstanceId, 'qa-instance-1', 'snapshot carries instance id');
                    api.assertEqual(snapshotMsg.sessionGeneration, state.sessionGeneration, 'snapshot carries session generation');
                    api.assertEqual(snapshotMsg.catalogVersion, manifest.version, 'snapshot carries catalog version');
                    api.assertEqual(snapshotMsg.catalogSchema, manifest.schema, 'snapshot carries catalog schema');
                    api.assert(snapshotMsg.stageNames.length > 0, 'stageNames still full set');
                    api.assertEqual(snapshotMsg.frameLabel, state.frameLabel,
                        'production snapshot explicitly carries current frame');
                    api.assertEqual(snapshotMsg.returnFrameLabel, state.returnFrameLabel,
                        'production snapshot explicitly carries return frame');
                    return 'envelope ok, session=' + state.sessionGeneration;
                });
            }],
            ['session-cross-instance-rejected', 'response with foreign panelInstanceId is rejected, legit retry still applies', function() {
                host.open({ panelInstanceId: 'qa-instance-A' });
                return waitReady(api).then(function() {
                    var snapshotMsg = null;
                    for (var i = host.sentMessages.length - 1; i >= 0; i -= 1) {
                        if (host.sentMessages[i].cmd === 'snapshot') { snapshotMsg = host.sentMessages[i]; break; }
                    }
                    var before = StageSelectPanel._debugGetState().droppedRespCount;
                    // 跨实例回包：callId 在途但 instance 不符 → 拒绝并消费 pending。
                    window.chrome.webview.__dispatch({
                        type: 'panel_resp', panel: 'stage-select', cmd: 'snapshot',
                        callId: snapshotMsg.callId, panelInstanceId: 'qa-instance-B',
                        sessionGeneration: snapshotMsg.sessionGeneration,
                        success: true,
                        snapshot: { unlockedStages: {}, stageDetails: {}, currentFrameLabel: '联合大学' }
                    });
                    var state = StageSelectPanel._debugGetState();
                    api.assertEqual(state.droppedRespCount, before + 1, 'foreign instance response dropped');
                    api.assertEqual(state.pendingCount, 0, 'pending consumed by rejection');
                    api.assert(!state.runtimeSnapshot, 'foreign snapshot not applied');
                    // mock 的迟到正当回包（同 callId）也已无处可投；重新拉快照验证面板仍可自愈。
                    StageSelectPanel._debugRequestSnapshot();
                    return waitRuntime(api).then(function(s2) {
                        api.assert(!!s2.runtimeSnapshot, 'panel recovers with fresh snapshot');
                        return 'cross-instance rejected, recovery ok';
                    });
                });
            }],
            ['session-stale-revision-dropped', 'snapshot with non-monotonic stateRevision does not overwrite newer state', function() {
                host.open();
                return waitRuntime(api).then(function(state) {
                    var appliedRevision = state.lastAppliedStateRevision;
                    api.assert(appliedRevision >= 1, 'initial snapshot revision applied');
                    var before = state.droppedRespCount;
                    StageSelectPanel._debugRequestSnapshot();
                    var snapshotMsg = host.sentMessages[host.sentMessages.length - 1];
                    api.assertEqual(snapshotMsg.cmd, 'snapshot', 'last message is the new snapshot request');
                    // 同步注入乱序回包（revision 不前进），赶在 mock 15ms 正当回包之前。
                    window.chrome.webview.__dispatch({
                        type: 'panel_resp', panel: 'stage-select', cmd: 'snapshot',
                        callId: snapshotMsg.callId,
                        panelInstanceId: snapshotMsg.panelInstanceId,
                        sessionGeneration: snapshotMsg.sessionGeneration,
                        catalogVersion: snapshotMsg.catalogVersion,
                        stateRevision: appliedRevision,
                        success: true,
                        snapshot: { unlockedStages: {}, stageDetails: {}, currentFrameLabel: '联合大学' }
                    });
                    var mid = StageSelectPanel._debugGetState();
                    api.assertEqual(mid.droppedRespCount, before + 1, 'stale revision dropped');
                    api.assertEqual(mid.lastAppliedStateRevision, appliedRevision, 'revision watermark unchanged');
                    api.assertEqual(mid.frameLabel, state.frameLabel, 'stale snapshot did not move frame');
                    // 注入回包已消费该 pending（mock 的迟到正当回包将无处可投）；
                    // 再拉一次快照，mock 自增 revision 的正当回包应正常应用。
                    StageSelectPanel._debugRequestSnapshot();
                    return api.waitFor(function() {
                        var s = StageSelectPanel._debugGetState();
                        return s.lastAppliedStateRevision > appliedRevision ? s : null;
                    }, 2000, 'legit revision applied').then(function(s2) {
                        api.assert(s2.lastAppliedStateRevision > appliedRevision, 'legit revision applied after stale drop');
                        return 'stale revision dropped, legit applied rev=' + s2.lastAppliedStateRevision;
                    });
                });
            }],
            ['session-late-response-after-reopen', 'response from a closed session is dropped after close/reopen', function() {
                host.open({ panelInstanceId: 'qa-instance-old' });
                return waitRuntime(api).then(function(state) {
                    var oldCallId = null;
                    for (var i = host.sentMessages.length - 1; i >= 0; i -= 1) {
                        if (host.sentMessages[i].cmd === 'snapshot') { oldCallId = host.sentMessages[i].callId; break; }
                    }
                    var oldSession = state.sessionGeneration;
                    host.close();
                    host.open({ panelInstanceId: 'qa-instance-new' });
                    return waitRuntime(api).then(function(state2) {
                        api.assert(state2.sessionGeneration > oldSession, 'session rotates on reopen');
                        api.assertEqual(state2.panelInstanceId, 'qa-instance-new', 'instance rotates on reopen');
                        var before = state2.droppedRespCount;
                        // 旧会话回包迟到：pending 已随关闭清空 → 拒绝并记 dev log。
                        window.chrome.webview.__dispatch({
                            type: 'panel_resp', panel: 'stage-select', cmd: 'snapshot',
                            callId: oldCallId, panelInstanceId: 'qa-instance-old',
                            sessionGeneration: oldSession, success: true,
                            snapshot: { unlockedStages: {}, stageDetails: {} }
                        });
                        var after = StageSelectPanel._debugGetState();
                        api.assertEqual(after.droppedRespCount, before + 1, 'late response dropped');
                        api.assertEqual(after.panelInstanceId, 'qa-instance-new', 'new session unaffected');
                        return 'late response dropped across reopen';
                    });
                });
            }],
            ['session-rebind-refreshes-instance', 'same-name Host reopen rebinds session without DOM rebuild', function() {
                host.open({ panelInstanceId: 'qa-instance-1' });
                return waitRuntime(api).then(function(state) {
                    var el = document.querySelector('.stage-select-panel');
                    Panels.open('stage-select', {
                        mode: 'dev', fixture: 'mixed',
                        frameLabel: '基地门口', returnFrameLabel: '基地门口',
                        panelInstanceId: 'qa-instance-2', debug: true
                    });
                    // rebind 是同步路径（panels.js _doOpen → onRebind）：轮换断言立即生效。
                    var mid = StageSelectPanel._debugGetState();
                    api.assert(document.querySelector('.stage-select-panel') === el, 'rebind reuses DOM');
                    api.assertEqual(mid.panelInstanceId, 'qa-instance-2', 'instance rebound');
                    api.assert(mid.sessionGeneration > state.sessionGeneration, 'session rotates on rebind');
                    var last = host.sentMessages[host.sentMessages.length - 1];
                    api.assertEqual(last.cmd, 'snapshot', 'rebind refreshes snapshot');
                    api.assertEqual(last.panelInstanceId, 'qa-instance-2', 'refresh carries new instance');
                    // 等 refresh 回包落地（pending 归零），不能用 waitRuntime——runtimeSnapshot 已被旧态置位。
                    return api.waitFor(function() {
                        var s = StageSelectPanel._debugGetState();
                        return s.pendingCount === 0 && s.panelInstanceId === 'qa-instance-2' ? s : null;
                    }, 2000, 'rebind snapshot settled').then(function() {
                        return 'rebind ok';
                    });
                });
            }],
            ['session-arena-return-chain', 'arena redirect keeps panel open; returnTo reopen rotates session; late responses dropped', function() {
                // 对位 StageSelectPanelService.as 的角斗场重定向（closePanel:false + redirected:'arena'）
                // 与 PanelHostController 的 returnTo 栈（arena 关闭后以 returnToInitData 重开 stage-select）。
                document.getElementById('stage-fixture-select').value = 'allUnlocked';
                document.getElementById('stage-frame-select').value = '基地门口';
                host.open({ panelInstanceId: 'qa-chain-1' });
                return waitRuntime(api).then(function(state) {
                    var oldSnapshotCallId = null;
                    for (var i = host.sentMessages.length - 1; i >= 0; i -= 1) {
                        if (host.sentMessages[i].cmd === 'snapshot') { oldSnapshotCallId = host.sentMessages[i].callId; break; }
                    }
                    var difficulty = document.querySelector('.stage-select-card-anchor .stage-select-difficulty');
                    api.assert(!!difficulty, 'difficulty button exists');
                    difficulty.click();
                    var enterMsg = host.enterMessages[host.enterMessages.length - 1];
                    api.assert(!!enterMsg, 'enter request sent');
                    api.assertEqual(enterMsg.panelInstanceId, 'qa-chain-1', 'enter carries instance');
                    // 抢在 mock 默认回包前同步注入重定向回包（closePanel:false：Host 接管切换，面板不自杀）。
                    window.chrome.webview.__dispatch({
                        type: 'panel_resp', panel: 'stage-select', cmd: 'enter',
                        callId: enterMsg.callId, panelInstanceId: enterMsg.panelInstanceId,
                        sessionGeneration: enterMsg.sessionGeneration,
                        success: true, closePanel: false, redirected: 'arena',
                        stageName: enterMsg.stageName, difficulty: enterMsg.difficulty
                    });
                    var mid = StageSelectPanel._debugGetState();
                    api.assert(mid.isOpen, 'panel stays open on arena redirect (closePanel:false)');
                    api.assertEqual(mid.busyStageName, '', 'busy cleared by redirect response');
                    // arena 阶段：Host 关 stage-select（panel_cmd close 等价物）→ 关 arena 后以
                    // returnToInitData 重开 stage-select（新 instance + returnFrameLabel）。
                    Panels.close();
                    host.open({ panelInstanceId: 'qa-chain-2', returnFrameLabel: '基地门口' });
                    return waitRuntime(api).then(function(state2) {
                        api.assertEqual(state2.panelInstanceId, 'qa-chain-2', 'returnTo reopen binds new instance');
                        api.assert(state2.sessionGeneration > state.sessionGeneration, 'session rotates across arena chain');
                        api.assertEqual(state2.returnFrameLabel, '基地门口', 'returnTo frame restored');
                        var before = state2.droppedRespCount;
                        window.chrome.webview.__dispatch({
                            type: 'panel_resp', panel: 'stage-select', cmd: 'snapshot',
                            callId: oldSnapshotCallId, panelInstanceId: 'qa-chain-1',
                            sessionGeneration: state.sessionGeneration, success: true,
                            snapshot: { unlockedStages: {}, stageDetails: {} }
                        });
                        api.assertEqual(StageSelectPanel._debugGetState().droppedRespCount, before + 1,
                            'pre-arena response dropped after chain reopen');
                        return 'arena chain ok';
                    });
                });
            }],
            ['mouse-select-clean', 'mouse-path select shows no focus ring and no card; anchor mirror hard-hides stale card', function() {
                // 打磨批二轮⑧⑨⑩：实机「选中后蓝环压残留卡」治理——合成鼠标全路径
                // （pointerenter 开卡 → pointerdown 转指针模态 → focus 持焦 → click 选中）。
                host.open();
                return waitReady(api).then(function() {
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    api.assert(!!node, 'unlocked difficulty node exists');
                    var stageId = node.getAttribute('data-stage-id');
                    var anchor = findCardAnchor(stageId);
                    node.dispatchEvent(new PointerEvent('pointerenter', { bubbles: true }));
                    api.assert(anchor.classList.contains('is-card-open'), 'hover opens card before select');
                    node.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
                    node.focus();
                    node.click();
                    api.assertEqual(StageSelectPanel._debugGetState().selectedStageId, stageId, 'node selected via mouse path');
                    api.assert(!anchor.classList.contains('is-card-open'), 'card closes on select');
                    api.assert(anchor.classList.contains('is-selected'), 'selection mirrored to card anchor');
                    api.assert(!node.classList.contains('is-kb-focus'), 'mouse path does not latch keyboard ring');
                    var hitZone = node.querySelector('.stage-select-hit-zone');
                    api.assertEqual(getComputedStyle(hitZone).outlineStyle, 'none', 'no focus ring after mouse select');
                    // DOM 级保险实证：即便事件乱序残留 is-card-open，选中锚点的卡也画不出来
                    anchor.classList.add('is-card-open');
                    api.assertEqual(getComputedStyle(anchor.querySelector('.stage-select-card')).display, 'none',
                        'selected anchor hard-hides card even with stale is-card-open');
                    anchor.classList.remove('is-card-open');
                    // 指针留在节点上（leave→enter 回悬）不再开卡
                    node.dispatchEvent(new PointerEvent('pointerleave', { bubbles: true }));
                    node.dispatchEvent(new PointerEvent('pointerenter', { bubbles: true }));
                    api.assert(!anchor.classList.contains('is-card-open'), 're-hover selected node keeps card closed');
                    return 'mouse select clean';
                });
            }],
            ['deselect-restores-hover-card', 'Esc deselect restores baseline: hover card reopens and keyboard ring yields to open card', function() {
                // 打磨批二轮⑧⑩：取消选中回未选中基线；Esc（键盘模态）归还焦点挂 .is-kb-focus，
                // 但卡恢复打开后 has-open-card 守卫令蓝环让位（卡本体即指示器）。
                host.open();
                return waitReady(api).then(function() {
                    var node = document.querySelector('.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)');
                    var stageId = node.getAttribute('data-stage-id');
                    var anchor = findCardAnchor(stageId);
                    node.dispatchEvent(new PointerEvent('pointerenter', { bubbles: true }));
                    node.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
                    node.focus();
                    node.click();
                    api.assertEqual(StageSelectPanel._debugGetState().selectedStageId, stageId, 'node selected');
                    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
                    api.assertEqual(StageSelectPanel._debugGetState().selectedStageId, '', 'Esc deselects');
                    api.assert(!StageSelectPanel._debugGetState().inspectorOpen, 'inspector closed');
                    api.assert(document.activeElement === node, 'focus restored to trigger node');
                    api.assert(node.classList.contains('is-kb-focus'), 'Esc (keyboard) latches kb-focus class');
                    api.assert(anchor.classList.contains('is-card-open'), 'hover card reopens after deselect');
                    api.assert(node.classList.contains('has-open-card'), 'open card mirrored to node');
                    var hitZone = node.querySelector('.stage-select-hit-zone');
                    api.assertEqual(getComputedStyle(hitZone).outlineStyle, 'none', 'ring yields while card open');
                    return 'deselect restores hover baseline';
                });
            }],
            ['keyboard-focus-ring-semantics', 'keyboard modality shows ring on card-less locked node; pointerdown strips ring without refocus', function() {
                // 打磨批二轮⑧：键盘可达性不退役——锁定节点永不开卡，键盘环必须可见；
                // 「点击已持焦节点、focusin 不重燃」路径由 pointerdown capture 直接剥环。
                document.getElementById('stage-fixture-select').value = 'mixed';
                host.open();
                return waitReady(api).then(function() {
                    StageSelectPanel._debugSetFrame('基地车库', 'qa-kb-ring'); // 摇滚公园/摇滚内战 在 mixed 下锁定
                    var locked = document.querySelector('.stage-select-stage-button.is-locked:not(.is-direct-entry)');
                    api.assert(!!locked, 'locked node exists');
                    locked.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }));
                    locked.focus();
                    api.assert(locked.classList.contains('is-kb-focus'), 'keyboard modality latches kb-focus class');
                    var hitZone = locked.querySelector('.stage-select-hit-zone');
                    api.assertEqual(getComputedStyle(hitZone).outlineStyle, 'solid', 'locked node shows ring under keyboard modality');
                    api.assertEqual(getComputedStyle(hitZone).outlineWidth, '2px', 'ring width 2px');
                    locked.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
                    api.assert(!locked.classList.contains('is-kb-focus'), 'pointerdown strips ring without refocus');
                    api.assertEqual(getComputedStyle(hitZone).outlineStyle, 'none', 'ring gone under pointer modality');
                    return 'keyboard ring semantics ok';
                });
            }]
        ];

        if (onlyCase) {
            cases = cases.filter(function(item) { return item[0] === onlyCase; });
        }
        var chain = Promise.resolve([]);
        cases.forEach(function(item) {
            chain = chain.then(function(results) {
                return api.runCase(item[0], item[1], item[2]).then(function(result) {
                    // 用例完成不等于图片请求已完成；下一用例会 reopen/换帧。这里保持严格网络门，
                    // 先等当前背景落稳再推进，避免把 QA 自己的导航竞争误记为请求失败。
                    return waitCurrentBackgroundReady(api).then(function() {
                        results.push(result);
                        return results;
                    }).catch(function(error) {
                        if (result.pass) {
                            result.pass = false;
                            result.detail = error && error.message ? error.message : String(error);
                        }
                        results.push(result);
                        return results;
                    });
                });
            });
        });
        return chain.then(function(results) {
            return MinigameHarness.normalizeBundle(results);
        });
    }

    // P2：hover 卡已迁至 .stage-select-card-anchor 同位锚点层，统一按 stage id 反查。
    function findCardAnchor(stageId) {
        return document.querySelector('.stage-select-card-anchor[data-stage-id="' + stageId + '"]');
    }

    // 方向键导航 qa 侧独立实现（与面板同款打分）：方向半平面主轴距离 + 2×垂直轴偏差。
    function qaNavPoint(button) {
        var x = Number(button.x) || 0;
        var y = Number(button.y) || 0;
        if (button.entryKind === 'map') {
            var marker = button.directLayout && button.directLayout.marker || {};
            var mx = Number(marker.x); var my = Number(marker.y);
            return { x: x + (isFinite(mx) ? mx : 0), y: y + (isFinite(my) ? my : 120) };
        }
        if (button.entryKind === 'task') {
            return { x: x + 45.5, y: y + 10.5 };
        }
        return { x: x, y: y + 120 };
    }

    function qaNearest(buttons, origin, key) {
        var originPoint = qaNavPoint(origin);
        var best = null;
        var bestScore = Infinity;
        buttons.forEach(function(candidate) {
            if (candidate.id === origin.id) return;
            var point = qaNavPoint(candidate);
            var dx = point.x - originPoint.x;
            var dy = point.y - originPoint.y;
            var primary;
            var cross;
            if (key === 'ArrowRight') { primary = dx; cross = dy; }
            else if (key === 'ArrowLeft') { primary = -dx; cross = dy; }
            else if (key === 'ArrowDown') { primary = dy; cross = dx; }
            else { primary = -dy; cross = dx; }
            if (primary <= 1) return;
            var score = primary + 2 * Math.abs(cross);
            if (score < bestScore) { bestScore = score; best = candidate; }
        });
        return best;
    }

    function findFirstSceneEntryNav(api) {
        var manifest = StageSelectData.getManifest();
        for (var i = 0; i < manifest.frameOrder.length; i += 1) {
            var label = manifest.frameOrder[i];
            var frame = StageSelectData.getFrame(label);
            var navs = frame && frame.navButtons || [];
            for (var j = 0; j < navs.length; j += 1) {
                var item = navs[j].libraryItemName || '';
                if (item.indexOf('选关界面UI/Symbol ') === 0 && item !== '选关界面UI/Symbol 3308') {
                    return { frameLabel: label, id: navs[j].id };
                }
            }
        }
        api.assert(false, 'scene-entry nav exists');
        return null;
    }

    function measureSceneEntryMarker(api, navId) {
        var el = document.querySelector('.stage-select-nav-button.is-scene-entry[data-nav-id="' + navId + '"]');
        api.assert(!!el, 'scene-entry nav node exists: ' + navId);
        var stage = document.getElementById('stage-select-stage');
        api.assert(!!stage, 'stage node exists');
        var scale = getStageScale();
        var stageRect = stage.getBoundingClientRect();
        var rect = el.getBoundingClientRect();
        var before = getComputedStyle(el, '::before');
        var markerWidth = cssNumber(before.width) + cssNumber(before.borderLeftWidth) + cssNumber(before.borderRightWidth);
        var markerHeight = cssNumber(before.height) + cssNumber(before.borderTopWidth) + cssNumber(before.borderBottomWidth);
        return {
            x: (rect.left + (cssNumber(before.left) + markerWidth / 2) * scale - stageRect.left) / scale,
            y: (rect.top + (cssNumber(before.top) + markerHeight / 2) * scale - stageRect.top) / scale
        };
    }

    function getStageScale() {
        var stage = document.getElementById('stage-select-stage');
        if (!stage) return 1;
        var fromVar = parseFloat(getComputedStyle(stage).getPropertyValue('--stage-select-scale'));
        if (fromVar > 0) return fromVar;
        var rect = stage.getBoundingClientRect();
        return rect.width > 0 ? rect.width / 1024 : 1;
    }

    function getHitTestViewport() {
        var width = Math.min(1366, Math.max(800, window.innerWidth || 1366));
        var height = Math.min(768, Math.max(560, window.innerHeight || 768));
        return width + 'x' + height;
    }

    function cssNumber(value) {
        var n = parseFloat(value);
        return isNaN(n) ? 0 : n;
    }

    function assertHit(api, el, label) {
        api.assert(!!el, label + ' missing');
        var rect = el.getBoundingClientRect();
        var x = rect.left + rect.width / 2;
        var y = rect.top + rect.height / 2;
        var hit = document.elementFromPoint(x, y);
        api.assert(!!hit && (hit === el || el.contains(hit) || el.contains(hit.parentNode)), label + ' hit-test covered by ' + describeEl(hit));
        return hit;
    }

    function assertHitAt(api, el, x, y, label) {
        var hit = document.elementFromPoint(x, y);
        api.assert(!!hit && (hit === el || el.contains(hit) || el.contains(hit.parentNode)), label + ' hit-test covered by ' + describeEl(hit));
        return hit;
    }

    function assertNear(api, actual, expected, tolerance, label) {
        api.assert(Math.abs(actual - expected) <= tolerance,
            label + ': expected ' + expected + ' +/- ' + tolerance + ', got ' + actual);
    }

    function describeEl(el) {
        if (!el) return 'nothing';
        var out = el.tagName ? el.tagName.toLowerCase() : 'node';
        if (el.id) out += '#' + el.id;
        if (el.className && typeof el.className === 'string') out += '.' + el.className.trim().replace(/\s+/g, '.');
        return out;
    }

    return {
        runSuite: runSuite
    };
})();
