var StageSelectHarnessQA = (function() {
    'use strict';

    function waitReady(api) {
        return api.waitFor(function() {
            var state = StageSelectPanel && StageSelectPanel._debugGetState ? StageSelectPanel._debugGetState() : null;
            return state && state.isOpen ? state : null;
        }, 2000, 'stage-select ready');
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
                    return waitReady(api).then(function() { return 'lifecycle ok'; });
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
            ['difficulty-static', 'difficulty click does not send Bridge command', function() {
                host.open();
                return waitReady(api).then(function() {
                    api.events.length = 0;
                    var difficulty = document.querySelector('.stage-select-difficulty');
                    api.assert(!!difficulty, 'difficulty button exists');
                    difficulty.click();
                    var state = StageSelectPanel._debugGetState();
                    api.assert(!!state.lastDifficultyClick, 'difficulty click recorded locally');
                    api.assertEqual(api.events.length, 0, 'no Bridge.send on difficulty');
                    return 'static difficulty click ok';
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
        return Promise.all(cases.map(function(item) {
            return api.runCase(item[0], item[1], item[2]);
        })).then(function(results) {
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
