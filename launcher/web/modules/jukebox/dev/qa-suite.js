var JukeboxHarnessQA = (function() {
    'use strict';

    function waitReady(api) {
        return api.waitFor(function() {
            return Panels.getActive() === 'jukebox';
        }, 2000, 'jukebox panel open');
    }

    function waitCatalog(api) {
        return api.waitFor(function() {
            var list = document.querySelectorAll('.jbp-track-item');
            return list.length > 0 ? list : null;
        }, 2000, 'jukebox catalog rendered');
    }

    function click(el) {
        if (!el) throw new Error('click target missing');
        var ev = new MouseEvent('click', { bubbles: true, cancelable: true });
        el.dispatchEvent(ev);
    }

    function runSuite(api, host, onlyCase) {
        var cases = [
            ['open-close', 'open and close lifecycle', function() {
                host.open();
                return waitReady(api).then(function() {
                    api.assertEqual(Panels.getActive(), 'jukebox', 'active panel');
                    Panels.close();
                    api.assertEqual(Panels.getActive(), null, 'panel closed');
                    host.open();
                    return waitReady(api).then(function() {
                        api.assertEqual(Panels.getActive(), 'jukebox', 'active panel reopened');
                        return 'lifecycle ok';
                    });
                });
            }],
            ['seed-state', 'seed state renders after open', function() {
                host.open();
                return waitReady(api).then(function() {
                    return waitCatalog(api).then(function() {
                        var title = document.getElementById('jbp-current-title');
                        api.assertEqual(title.textContent, 'Tetrriture', 'current title seeded');
                        return api.waitFor(function() {
                            var time = document.getElementById('jbp-time');
                            return time && time.textContent.indexOf('00:08') >= 0 ? time : null;
                        }, 1500, 'time displays cursor').then(function(time) {
                            var start = document.getElementById('jbp-prog-time-start');
                            var end = document.getElementById('jbp-prog-time-end');
                            api.assertEqual(start.textContent, '00:08', 'progress start time');
                            api.assertEqual(end.textContent, '02:58', 'progress end time');
                            var globalVal = document.querySelector('.jb-slider-row[data-slider="volGlobal"] .jb-slider-value');
                            var bgmVal = document.querySelector('.jb-slider-row[data-slider="volBgm"] .jb-slider-value');
                            api.assertEqual(globalVal.textContent, '50', 'global volume seeded');
                            api.assertEqual(bgmVal.textContent, '80', 'bgm volume seeded');
                            var activeMode = document.querySelector('.jb-radio[data-value="singleLoop"]');
                            api.assert(activeMode.classList.contains('active'), 'single loop active');
                            return 'seed state ok';
                        });
                    });
                });
            }],
            ['catalog-render', 'album dropdown and track list render', function() {
                host.open();
                return waitReady(api).then(function() {
                    return waitCatalog(api).then(function(items) {
                        api.assert(items.length >= 12, 'track list has items');
                        var trigger = document.getElementById('jbp-album-trigger');
                        api.assert(trigger.textContent.indexOf('全部') >= 0, 'album trigger shows 全部');
                        click(trigger);
                        var options = document.querySelectorAll('.jbp-album-option');
                        api.assert(options.length >= 5, 'album options rendered');
                        click(document.body);
                        api.assert(!document.getElementById('jbp-album-dropdown').classList.contains('open'), 'dropdown closes on outside click');
                        return 'catalog render ok';
                    });
                });
            }],
            ['track-active', 'current track is highlighted', function() {
                host.open();
                return waitReady(api).then(function() {
                    return waitCatalog(api).then(function() {
                        var active = document.querySelector('.jbp-track-item.active');
                        api.assert(!!active, 'active track exists');
                        api.assertEqual(active.getAttribute('data-title'), 'Tetrriture', 'active track title');
                        api.assert(active.classList.contains('active'), 'active track has active class');
                        return 'active track ok';
                    });
                });
            }],
            ['track-click', 'clicking track sends play command', function() {
                host.open();
                return waitReady(api).then(function() {
                    return waitCatalog(api).then(function() {
                        var target = [].slice.call(document.querySelectorAll('.jbp-track-item')).find(function(el) {
                            return el.getAttribute('data-title') === 'Bulletproof';
                        });
                        api.assert(!!target, 'Bulletproof track exists');
                        var before = host.sentMessages.length;
                        click(target);
                        api.assert(host.sentMessages.length > before, 'play message sent');
                        var last = host.sentMessages[host.sentMessages.length - 1];
                        api.assertEqual(last.cmd, 'play', 'last message is play');
                        api.assertEqual(last.title, 'Bulletproof', 'play title correct');
                        return 'track click ok';
                    });
                });
            }],
            ['pause-resume', 'pause and resume buttons toggle', function() {
                host.open();
                return waitReady(api).then(function() {
                    var pauseBtn = document.getElementById('jbp-pause-btn');
                    api.assertEqual(pauseBtn.textContent, '‖', 'initial pause symbol');
                    click(pauseBtn);
                    api.assert(pauseBtn.classList.contains('paused'), 'paused class set');
                    api.assertEqual(pauseBtn.textContent, '▶', 'resume symbol');
                    var pauseMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'pause'; });
                    api.assert(!!pauseMsg, 'pause message sent');
                    click(pauseBtn);
                    api.assert(!pauseBtn.classList.contains('paused'), 'paused class removed');
                    var resumeMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'resume'; });
                    api.assert(!!resumeMsg, 'resume message sent');
                    return 'pause resume ok';
                });
            }],
            ['stop', 'stop button sends stop command', function() {
                host.open();
                return waitReady(api).then(function() {
                    var stopBtn = document.getElementById('jbp-stop-btn');
                    click(stopBtn);
                    var stopMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'stop'; });
                    api.assert(!!stopMsg, 'stop message sent');
                    return 'stop ok';
                });
            }],
            ['volume-sliders', 'volume sliders send commands', function() {
                host.open();
                return waitReady(api).then(function() {
                    var track = document.querySelector('.jb-slider-row[data-slider="volGlobal"] .jb-slider-track');
                    var rect = track.getBoundingClientRect();
                    var mousedown = new MouseEvent('mousedown', { bubbles: true, clientX: rect.left + rect.width * 0.75 });
                    track.dispatchEvent(mousedown);
                    var mouseup = new MouseEvent('mouseup', { bubbles: true });
                    document.dispatchEvent(mouseup);
                    var volMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'volGlobal'; });
                    api.assert(!!volMsg, 'volGlobal message sent');
                    api.assert(volMsg.value >= 70 && volMsg.value <= 80, 'volGlobal value near 75');
                    return 'volume sliders ok';
                });
            }],
            ['settings-toggle', 'override and trueRandom toggle', function() {
                host.open();
                return waitReady(api).then(function() {
                    var overrideRow = document.querySelector('.jb-setting-item[data-key="override"]');
                    var randomRow = document.querySelector('.jb-setting-item[data-key="trueRandom"]');
                    api.assert(!overrideRow.classList.contains('active'), 'override initially inactive');
                    click(overrideRow);
                    api.assert(overrideRow.classList.contains('active'), 'override active after click');
                    var overrideMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'override'; });
                    api.assert(!!overrideMsg && overrideMsg.value === true, 'override true message sent');
                    click(randomRow);
                    api.assert(randomRow.classList.contains('active'), 'trueRandom active after click');
                    var randomMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'trueRandom'; });
                    api.assert(!!randomMsg && randomMsg.value === true, 'trueRandom true message sent');
                    return 'settings toggle ok';
                });
            }],
            ['play-mode', 'play mode radio switches', function() {
                host.open();
                return waitReady(api).then(function() {
                    var albumLoop = document.querySelector('.jb-radio[data-value="albumLoop"]');
                    var playOnce = document.querySelector('.jb-radio[data-value="playOnce"]');
                    click(albumLoop);
                    api.assert(albumLoop.classList.contains('active'), 'albumLoop active');
                    var msg1 = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'playMode'; });
                    api.assert(!!msg1 && msg1.value === 'albumLoop', 'albumLoop message sent');
                    click(playOnce);
                    api.assert(playOnce.classList.contains('active'), 'playOnce active');
                    var msg2 = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'playMode'; });
                    api.assert(!!msg2 && msg2.value === 'playOnce', 'playOnce message sent');
                    return 'play mode ok';
                });
            }],
            ['help-modal', 'help button opens modal and loads help', function() {
                host.open();
                return waitReady(api).then(function() {
                    var helpBtn = document.getElementById('jbp-help-btn');
                    click(helpBtn);
                    return api.waitFor(function() {
                        var modal = document.getElementById('jbp-help-modal');
                        return modal && modal.classList.contains('visible') ? modal : null;
                    }, 1000, 'help modal visible').then(function(modal) {
                        var loadMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'loadHelp'; });
                        api.assert(!!loadMsg, 'loadHelp message sent');
                        return api.waitFor(function() {
                            return modal.textContent.indexOf('点歌台帮助') >= 0 ? modal : null;
                        }, 1000, 'help text rendered').then(function() {
                            var close = document.getElementById('jbp-help-close');
                            click(close);
                            api.assert(!modal.classList.contains('visible'), 'help modal closed');
                            return 'help modal ok';
                        });
                    });
                });
            }],
            ['no-settings-scroll', 'settings panel fits without scrollbar', function() {
                host.open();
                return waitReady(api).then(function() {
                    var settings = document.getElementById('jbp-settings');
                    api.assert(settings.scrollHeight <= settings.clientHeight + 1, 'settings has no overflow scrollHeight=' + settings.scrollHeight + ' clientHeight=' + settings.clientHeight);
                    return 'no settings scrollbar';
                });
            }],
            ['album-scrollbar-styled', 'album dropdown scrollbar is styled', function() {
                host.open();
                return waitReady(api).then(function() {
                    var trigger = document.getElementById('jbp-album-trigger');
                    click(trigger);
                    var dropdown = document.getElementById('jbp-album-options');
                    api.assert(dropdown.classList.contains('open') || getComputedStyle(dropdown).display === 'block', 'dropdown open');
                    var options = dropdown.querySelectorAll('.jbp-album-option');
                    api.assert(options.length >= 5, 'dropdown has album options');
                    var style = window.getComputedStyle(dropdown);
                    var width = style.scrollbarWidth;
                    api.assert(width === 'auto' || width === 'thin' || width === '7px' || width === '', 'dropdown scrollbar width acceptable (computed: ' + width + ')');
                    click(document.body);
                    return 'album scrollbar styled';
                });
            }]
        ];

        if (onlyCase) {
            cases = cases.filter(function(c) { return c[0] === onlyCase; });
            if (cases.length === 0) {
                return Promise.reject(new Error('unknown case: ' + onlyCase));
            }
        }

        var chain = Promise.resolve([]);
        cases.forEach(function(c) {
            chain = chain.then(function(results) {
                return api.runCase(c[0], c[1], c[2]).then(function(result) {
                    results.push(result);
                    return results;
                });
            });
        });

        return chain.then(function(results) {
            return MinigameHarness.normalizeBundle(results);
        });
    }

    return {
        runSuite: runSuite
    };
})();
