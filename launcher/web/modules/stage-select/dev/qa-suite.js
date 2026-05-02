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
            ['frame-tabs', 'all frame labels route', function() {
                host.open();
                return waitReady(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    manifest.frameOrder.forEach(function(label) {
                        StageSelectPanel._debugSetFrame(label, 'qa');
                        var state = StageSelectPanel._debugGetState();
                        var frame = StageSelectData.getFrame(label);
                        api.assertEqual(state.frameLabel, label, 'frame routed');
                        api.assertEqual(state.stageButtonCount, frame.stageButtons.length, 'stage button count for ' + label);
                    });
                    return manifest.frameOrder.length + ' frames routed';
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
                    var difficulties = document.querySelectorAll('.stage-select-stage-button:not(.is-direct-entry) .stage-select-difficulty');
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
                    var preview = button.querySelector('.stage-select-preview');
                    var difficulties = button.querySelectorAll('.stage-select-difficulty');
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
                    var detail = btn.querySelector('.stage-select-card-detail');
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
                    var card = btn.querySelector('.stage-select-card');
                    var name = btn.querySelector('.stage-select-card-name');
                    var detail = btn.querySelector('.stage-select-card-detail');
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
                    var difficulty = document.querySelector('.stage-select-stage-button:not(.is-direct-entry) .stage-select-difficulty');
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
                    var difficulty = document.querySelector('.stage-select-stage-button:not(.is-direct-entry) .stage-select-difficulty');
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
            ['challenge-enter', 'challenge mode only sends hell difficulty', function() {
                document.getElementById('stage-fixture-select').value = 'challenge';
                host.open();
                return waitRuntime(api).then(function(state) {
                    api.assert(state.challenge, 'challenge flag set from snapshot');
                    var difficulties = document.querySelectorAll('.stage-select-stage-button:not(.is-direct-entry) .stage-select-difficulty');
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
                    api.assertEqual(checked, 9, 'checked diplomacy map entries');
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
                return waitReady(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    manifest.frameOrder.forEach(function(label) {
                        StageSelectPanel._debugSetFrame(label, 'qa-bg');
                        var frame = StageSelectData.getFrame(label);
                        var expected = frame.background && frame.background.rect;
                        var bg = document.getElementById('stage-select-bg');
                        api.assert(!!expected, 'background rect missing for ' + label);
                        assertNear(api, parseFloat(bg.style.left), expected.x, 0.51, 'bg x ' + label);
                        assertNear(api, parseFloat(bg.style.top), expected.y, 0.51, 'bg y ' + label);
                        assertNear(api, parseFloat(bg.style.width), expected.w, 0.51, 'bg w ' + label);
                        assertNear(api, parseFloat(bg.style.height), expected.h, 0.51, 'bg h ' + label);
                    });
                    return manifest.frameOrder.length + ' background rects checked';
                });
            }],
            ['button-anchors', 'button anchors follow manifest positions', function() {
                host.open();
                return waitReady(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    var checked = 0;
                    manifest.frameOrder.forEach(function(label) {
                        StageSelectPanel._debugSetFrame(label, 'qa-anchor');
                        var frame = StageSelectData.getFrame(label);
                        (frame.stageButtons || []).forEach(function(button) {
                            if (button.entryKind === 'map' || button.entryKind === 'task') return;
                            var node = document.querySelector('.stage-select-stage-button[data-stage-id="' + button.id + '"]');
                            api.assert(!!node, 'missing button node ' + button.id);
                            assertNear(api, parseFloat(node.style.left), button.x, 0.01, 'button x ' + button.id);
                            assertNear(api, parseFloat(node.style.top), button.y, 0.01, 'button y ' + button.id);
                            checked += 1;
                        });
                    });
                    return checked + ' anchors checked';
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
            }]
        ];

        if (onlyCase) {
            cases = cases.filter(function(item) { return item[0] === onlyCase; });
        }
        var chain = Promise.resolve([]);
        cases.forEach(function(item) {
            chain = chain.then(function(results) {
                return api.runCase(item[0], item[1], item[2]).then(function(result) {
                    results.push(result);
                    return results;
                });
            });
        });
        return chain.then(function(results) {
            return MinigameHarness.normalizeBundle(results);
        });
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
