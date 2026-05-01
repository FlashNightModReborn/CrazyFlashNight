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
                    var difficulties = document.querySelectorAll('.stage-select-difficulty');
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
                    api.assertEqual(getComputedStyle(document.querySelector('.stage-select-fixture-label')).display, 'none', 'fixture label hidden');
                    api.assertEqual(getComputedStyle(document.getElementById('stage-select-fixture')).display, 'none', 'fixture select hidden');
                    api.assertEqual(getComputedStyle(document.querySelector('.stage-select-badge')).display, 'none', 'badge hidden');
                    api.assertEqual(getComputedStyle(document.getElementById('stage-select-dev-log')).display, 'none', 'dev log hidden');
                    return 'runtime chrome hidden';
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
            ['runtime-return-close', 'runtime return nav closes panel', function() {
                host.open({ mode: 'runtime', debug: false });
                return waitRuntime(api).then(function() {
                    var manifest = StageSelectData.getManifest();
                    var nav = document.querySelector('.stage-select-nav-button[data-action-kind="flashJumpCurrent"], .stage-select-nav-button[data-action-kind="flashJumpFrameValue"]');
                    if (!nav) {
                        manifest.frameOrder.some(function(label) {
                            StageSelectPanel._debugSetFrame(label, 'qa-return');
                            nav = document.querySelector('.stage-select-nav-button[data-action-kind="flashJumpCurrent"], .stage-select-nav-button[data-action-kind="flashJumpFrameValue"]');
                            return !!nav;
                        });
                    }
                    api.assert(!!nav, 'runtime return nav exists');
                    nav.click();
                    return api.waitFor(function() {
                        return Panels.getActive && Panels.getActive() === null ? true : null;
                    }, 2000, 'return close').then(function() {
                        return 'runtime return closed';
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
                        lockedButton = document.querySelector('.stage-select-stage-button.is-locked');
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
                    var difficulty = document.querySelector('.stage-select-difficulty');
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
                    var difficulty = document.querySelector('.stage-select-difficulty');
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
                    var difficulties = document.querySelectorAll('.stage-select-difficulty');
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
                host.setViewport('1366x768');
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
