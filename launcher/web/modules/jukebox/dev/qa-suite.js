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

    function findTrack(title) {
        return [].slice.call(document.querySelectorAll('.jbp-track-item')).find(function(el) {
            return el.getAttribute('data-title') === title;
        });
    }

    function playMessageCount(host) {
        return host.sentMessages.filter(function(message) {
            return message && message.type === 'jukebox' && message.cmd === 'play';
        }).length;
    }

    function availabilityFixture() {
        return [
            { title: 'Available Track', album: 'Gate', availability: 'available', reason: '' },
            { title: 'Probing Track', album: 'Gate', availability: 'probing', reason: 'probe_pending' },
            { title: 'Unavailable Track', album: 'Gate', availability: 'unavailable', reason: 'unsupported_codec' },
            { title: 'Legacy Track', album: 'Gate' },
            { title: 'Invalid Track', album: 'Gate', availability: 'ready', reason: 'non_contract_state' }
        ];
    }

    function openWithCatalog(api, host, tracks) {
        host.open();
        return waitReady(api).then(function() {
            // open 的 requestCatalog 在 15ms 后回默认目录；先等它落地，再下发目标 fixture，避免旧 DOM 误通过。
            return new Promise(function(resolve) { setTimeout(resolve, 60); });
        }).then(function() {
            host.dispatchCatalog(tracks);
            return api.waitFor(function() {
                var items = document.querySelectorAll('.jbp-track-item');
                return items.length === tracks.length ? items : null;
            }, 1000, 'availability fixture rendered');
        });
    }

    function runSuite(api, host, onlyCase) {
        var cases = [
            ['open-close', 'open and close lifecycle', function() {
                host.open();
                // CRT 开机动画：open 后同步可见 is-booting（animationend 后由面板自清除）
                var bootEl = document.querySelector('.jbp-panel');
                api.assert(bootEl && bootEl.classList.contains('is-booting'), 'boot animation class present on open');
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
                            var start = document.getElementById('jbp-prog-time-start');
                            return start && start.textContent.indexOf('00:08') >= 0 ? start : null;
                        }, 1500, 'progress start displays cursor').then(function(start) {
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
            ['album-chip-catalog-reconcile', 'catalog arrival resolves seeded title album chip', function() {
                host.open();
                return waitReady(api).then(function() {
                    // 模拟首次 lazy open：标题 seed 已有，但目录尚未到达。
                    host.dispatchCatalog([]);
                    UiData.dispatch('bgm:Tetrriture');
                    var chip = document.getElementById('jbp-album-chip');
                    api.assertEqual(getComputedStyle(chip).display, 'none', 'chip hidden before catalog');
                    host.dispatchCatalog();
                    return api.waitFor(function() {
                        return chip.textContent === 'Rammstein' && getComputedStyle(chip).display !== 'none'
                            ? chip : null;
                    }, 1000, 'catalog resolves album chip').then(function() {
                        return 'album chip reconciled';
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
            ['availability-render', 'availability disables non-playable tracks and exposes reasons', function() {
                return openWithCatalog(api, host, availabilityFixture()).then(function() {
                    var available = findTrack('Available Track');
                    var probing = findTrack('Probing Track');
                    var unavailable = findTrack('Unavailable Track');
                    var legacy = findTrack('Legacy Track');
                    var invalid = findTrack('Invalid Track');
                    api.assert(!!available && !!probing && !!unavailable && !!legacy && !!invalid, 'all availability rows rendered');
                    api.assertEqual(available.getAttribute('data-availability'), 'available', 'available state preserved');
                    api.assertEqual(available.getAttribute('aria-disabled'), 'false', 'available row enabled');
                    api.assertEqual(available.tabIndex, 0, 'available row keyboard reachable');
                    api.assertEqual(probing.getAttribute('aria-disabled'), 'true', 'probing row disabled');
                    api.assertEqual(probing.tabIndex, -1, 'probing row removed from tab order');
                    api.assert(probing.classList.contains('is-disabled'), 'probing row visibly disabled');
                    api.assert(parseFloat(getComputedStyle(probing).opacity) < 1, 'probing row dimmed');
                    var probingReason = probing.querySelector('.jbp-track-reason');
                    api.assert(probingReason.textContent.indexOf('probe_pending') >= 0, 'probing reason retained');
                    api.assert(getComputedStyle(probingReason).display !== 'none'
                        && probingReason.getBoundingClientRect().height > 0, 'probing reason visibly laid out');
                    api.assertEqual(unavailable.getAttribute('data-reason'), 'unsupported_codec', 'unavailable reason retained');
                    api.assertEqual(getComputedStyle(unavailable).cursor, 'not-allowed', 'unavailable row has disabled cursor');
                    var unavailableReason = unavailable.querySelector('.jbp-track-reason');
                    api.assert(unavailableReason.textContent.indexOf('unsupported_codec') >= 0, 'unavailable reason retained in text');
                    api.assert(getComputedStyle(unavailableReason).display !== 'none'
                        && unavailableReason.getBoundingClientRect().height > 0, 'unavailable reason visibly laid out');
                    api.assertEqual(legacy.getAttribute('data-availability'), 'unavailable', 'missing availability fails closed');
                    api.assert(legacy.querySelector('.jbp-track-reason').textContent.indexOf('availability') >= 0, 'missing availability explains failure');
                    api.assertEqual(invalid.getAttribute('data-availability'), 'unavailable', 'unknown availability fails closed');
                    return 'availability rendering ok';
                });
            }],
            ['availability-click-guard', 'synthetic and forged clicks cannot play non-available tracks', function() {
                return openWithCatalog(api, host, availabilityFixture()).then(function() {
                    var before = playMessageCount(host);
                    click(findTrack('Probing Track'));
                    click(findTrack('Unavailable Track'));
                    click(findTrack('Legacy Track'));
                    click(findTrack('Invalid Track'));
                    api.assertEqual(playMessageCount(host), before, 'disabled rows emit no play message');

                    var forged = findTrack('Unavailable Track');
                    forged.setAttribute('data-availability', 'available');
                    forged.setAttribute('aria-disabled', 'false');
                    forged.classList.remove('is-disabled', 'is-unavailable');
                    click(forged);
                    api.assertEqual(playMessageCount(host), before, 'forged DOM state cannot bypass catalog check');

                    forged.setAttribute('data-title', 'Available Track');
                    click(forged);
                    api.assertEqual(playMessageCount(host), before, 'forged title cannot impersonate canonical available row');

                    click(findTrack('Available Track'));
                    api.assertEqual(playMessageCount(host), before + 1, 'available row emits exactly one play message');
                    var last = host.sentMessages[host.sentMessages.length - 1];
                    api.assertEqual(last.title, 'Available Track', 'available title forwarded');
                    return 'availability click guard ok';
                });
            }],
            ['catalog-update-availability', 'catalogUpdate replaces and re-gates track availability', function() {
                var initial = [{ title: 'Mutable Track', album: 'Gate', availability: 'probing', reason: 'probe_pending' }];
                return openWithCatalog(api, host, initial).then(function() {
                    var before = playMessageCount(host);
                    click(findTrack('Mutable Track'));
                    api.assertEqual(playMessageCount(host), before, 'probing update seed cannot play');

                    host.dispatchCatalogUpdate([
                        { title: 'Mutable Track', album: 'Gate', availability: 'available', reason: '' }
                    ], []);
                    var available = findTrack('Mutable Track');
                    api.assertEqual(document.querySelectorAll('.jbp-track-item').length, 1, 'status update replaces instead of duplicating title');
                    api.assertEqual(available.getAttribute('aria-disabled'), 'false', 'available update enables row');
                    click(available);
                    api.assertEqual(playMessageCount(host), before + 1, 'available update permits one play');

                    host.dispatchCatalogUpdate([
                        { title: 'Mutable Track', album: 'Gate', availability: 'unavailable', reason: 'decode_probe_failed' }
                    ], []);
                    var unavailable = findTrack('Mutable Track');
                    api.assertEqual(unavailable.getAttribute('aria-disabled'), 'true', 'unavailable update disables row');
                    api.assert(unavailable.textContent.indexOf('decode_probe_failed') >= 0, 'update reason visible');
                    click(unavailable);
                    api.assertEqual(playMessageCount(host), before + 1, 'unavailable update blocks synthetic click');

                    host.dispatchCatalogUpdate([
                        { title: 'Mutable Track', album: 'Gate', reason: 'legacy_update' }
                    ], []);
                    var legacy = findTrack('Mutable Track');
                    api.assertEqual(legacy.getAttribute('data-availability'), 'unavailable', 'legacy update fails closed');
                    click(legacy);
                    api.assertEqual(playMessageCount(host), before + 1, 'legacy update cannot restore play');
                    return 'catalog update availability ok';
                });
            }],
            ['pause-resume', 'pause and resume buttons toggle', function() {
                host.open();
                return waitReady(api).then(function() {
                    var pauseBtn = document.getElementById('jbp-pause-btn');
                    api.assertEqual(pauseBtn.getAttribute('data-icon'), 'pause', 'initial pause icon');
                    click(pauseBtn);
                    api.assert(pauseBtn.classList.contains('paused'), 'paused class set');
                    api.assertEqual(pauseBtn.getAttribute('data-icon'), 'play', 'resume play icon');
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
                    return waitCatalog(api).then(function() {
                        // 先确保至少处理过一个音频包，再验证停止后仍能进入待机绘制。
                        return new Promise(function(resolve) { setTimeout(resolve, 40); });
                    }).then(function() {
                        var canvas = document.getElementById('jbp-wave');
                        var ctx = canvas.getContext('2d');
                        var originalFillText = ctx.fillText;
                        var standbyDraws = 0;
                        ctx.fillText = function(text) {
                            if (String(text).indexOf('STANDBY') >= 0) standbyDraws++;
                            return originalFillText.apply(this, arguments);
                        };
                        var stopBtn = document.getElementById('jbp-stop-btn');
                        click(stopBtn);
                        var stopMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'stop'; });
                        api.assert(!!stopMsg, 'stop message sent');
                        return api.waitFor(function() {
                            return standbyDraws > 0;
                        }, 1000, 'standby canvas rendered after stop').then(function() {
                            ctx.fillText = originalFillText;
                            return 'stop and standby ok';
                        }, function(err) {
                            ctx.fillText = originalFillText;
                            throw err;
                        });
                    });
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
            }],
            ['track-pending', 'clicked track shows pending until bgm confirms', function() {
                host.open();
                return waitReady(api).then(function() {
                    return waitCatalog(api).then(function() {
                        // open 会触发 requestCatalog → ~15ms 后重渲染并整体替换列表节点；
                        // 等刷新落地再取元素，避免点击到上一次渲染的已 detach 旧节点
                        return new Promise(function(resolve) { setTimeout(resolve, 80); });
                    }).then(function() {
                        var findBulletproof = function() {
                            return [].slice.call(document.querySelectorAll('.jbp-track-item')).find(function(el) {
                                return el.getAttribute('data-title') === 'Bulletproof';
                            });
                        };
                        var target = findBulletproof();
                        api.assert(!!target, 'Bulletproof track exists');
                        click(target);
                        api.assert(target.classList.contains('pending'), 'pending class set right after click');
                        api.assert(!target.classList.contains('active'), 'not active before bgm confirm');
                        return api.waitFor(function() {
                            var el = findBulletproof();
                            return el && el.classList.contains('active') ? el : null;
                        }, 1000, 'bgm confirm turns pending into active').then(function(el) {
                            api.assert(!el.classList.contains('pending'), 'pending cleared after confirm');
                            return 'track pending ok';
                        });
                    });
                });
            }],
            ['album-groups', 'all view groups tracks by album with sticky headers', function() {
                host.open();
                return waitReady(api).then(function() {
                    return waitCatalog(api).then(function() {
                        var groups = document.querySelectorAll('.jbp-album-group');
                        api.assert(groups.length >= 5, 'album group headers rendered in all view');
                        api.assertEqual(groups[0].textContent, 'BONUS', 'groups sorted alphabetically');
                        click(document.getElementById('jbp-album-trigger'));
                        var pbOpt = document.querySelector('.jbp-album-option[data-album="PB"]');
                        api.assert(!!pbOpt, 'PB album option exists');
                        click(pbOpt);
                        api.assert(document.querySelectorAll('.jbp-album-group').length === 0, 'no group headers in single album view');
                        api.assert(document.querySelectorAll('.jbp-track-item').length === 2, 'PB album has 2 tracks');
                        return 'album groups ok';
                    });
                });
            }],
            ['theme-toggle', 'phosphor theme radio switches and persists locally', function() {
                try { localStorage.removeItem('cf7-jukebox-theme'); } catch (e) {}
                host.open();
                return waitReady(api).then(function() {
                    var panel = document.querySelector('.jbp-panel');
                    var greenRow = document.querySelector('.jb-radio[data-key="phosphor"][data-value="green"]');
                    var amberRow = document.querySelector('.jb-radio[data-key="phosphor"][data-value="amber"]');
                    api.assert(!!greenRow && !!amberRow, 'phosphor radio rows exist');
                    api.assert(greenRow.classList.contains('active'), 'green phosphor default active');
                    api.assert(!amberRow.classList.contains('active'), 'amber phosphor default inactive');
                    click(amberRow);
                    api.assert(amberRow.classList.contains('active'), 'amber active after click');
                    api.assert(!greenRow.classList.contains('active'), 'green inactive after amber click (mutex)');
                    api.assertEqual(panel.style.getPropertyValue('--jb-accent'), '#ffb000', 'amber accent applied inline');
                    var saved = '';
                    try { saved = localStorage.getItem('cf7-jukebox-theme') || ''; } catch (e) {}
                    api.assertEqual(saved, 'amber', 'theme persisted to localStorage');
                    click(greenRow);
                    api.assert(greenRow.classList.contains('active'), 'green restored');
                    api.assertEqual(panel.style.getPropertyValue('--jb-accent'), '#c8ff4c', 'green accent restored');
                    return 'theme radio ok';
                });
            }],
            ['led-state', 'LED reflects playing and paused states', function() {
                host.open();
                return waitReady(api).then(function() {
                    return api.waitFor(function() {
                        var led = document.getElementById('jbp-led');
                        return led && led.classList.contains('is-live') ? led : null;
                    }, 1500, 'LED live while playing').then(function(led) {
                        click(document.getElementById('jbp-pause-btn'));
                        api.assert(led.classList.contains('is-paused'), 'LED amber while paused');
                        api.assert(!led.classList.contains('is-live'), 'LED not live while paused');
                        click(document.getElementById('jbp-pause-btn'));
                        api.assert(led.classList.contains('is-live'), 'LED live after resume');
                        return 'led state ok';
                    });
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
