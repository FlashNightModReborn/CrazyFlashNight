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

    function key(el, keyName, opts) {
        if (!el) throw new Error('key target missing');
        var init = { key: keyName, bubbles: true, cancelable: true };
        if (opts) { for (var k in opts) init[k] = opts[k]; }
        el.dispatchEvent(new KeyboardEvent('keydown', init));
    }

    // 生产路径：C# 捕获 ESC → bridge panel_esc → panels.js onRequestClose（web 侧刻意无 DOM Esc 监听）
    function dispatchEsc() {
        window.chrome.webview.__dispatch({ type: 'panel_esc' });
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
            }],
            ['keyboard-track', 'track list keyboard navigation and play', function() {
                host.open();
                return waitReady(api).then(function() {
                    return waitCatalog(api).then(function() {
                        // 等 requestCatalog 触发的二次渲染落地，避免操作到已 detach 的旧节点
                        return new Promise(function(resolve) { setTimeout(resolve, 80); });
                    }).then(function() {
                        // 专辑筛选是模块级偏好、跨用例持久：先经下拉 UI 复位到“全部”视图
                        click(document.getElementById('jbp-album-trigger'));
                        click(document.querySelector('.jbp-album-option[data-album=""]'));
                        return api.waitFor(function() {
                            var all = document.querySelectorAll('.jbp-track-item');
                            return all.length >= 12 ? all : null;
                        }, 1000, 'all-view track list restored');
                    }).then(function() {
                        var items = document.querySelectorAll('.jbp-track-item');
                        api.assert(items.length >= 3, 'track items rendered');
                        // roving tabindex：入口项（当前曲目）为 0，其余 -1
                        var activeEntry = document.querySelector('.jbp-track-item.active');
                        api.assertEqual(activeEntry.getAttribute('tabindex'), '0', 'roving entry on active track');
                        api.assertEqual(items[0].getAttribute('tabindex'), '-1', 'non-entry track tabindex -1');
                        api.assertEqual(items[0].getAttribute('role'), 'button', 'track item role=button');
                        items[0].focus();
                        key(items[0], 'ArrowDown');
                        var second = document.querySelectorAll('.jbp-track-item')[1];
                        api.assertEqual(document.activeElement, second, 'ArrowDown moves focus to next track');
                        api.assertEqual(second.getAttribute('tabindex'), '0', 'roving entry follows focus');
                        key(second, 'ArrowUp');
                        api.assertEqual(document.activeElement, items[0], 'ArrowUp moves focus back');
                        // Enter 点曲：与 click 汇聚同一 intent
                        var target = [].slice.call(document.querySelectorAll('.jbp-track-item')).find(function(el) {
                            return el.getAttribute('data-title') === 'Bulletproof';
                        });
                        api.assert(!!target, 'Bulletproof track exists');
                        target.focus();
                        var before = host.sentMessages.length;
                        key(target, 'Enter');
                        api.assert(host.sentMessages.length > before, 'Enter sends play message');
                        var last = host.sentMessages[host.sentMessages.length - 1];
                        api.assertEqual(last.cmd, 'play', 'keyboard play command');
                        api.assertEqual(last.title, 'Bulletproof', 'keyboard play title');
                        api.assert(target.classList.contains('pending'), 'keyboard play sets pending');
                        return 'keyboard track ok';
                    });
                });
            }],
            ['keyboard-slider', 'volume slider arrow keys adjust and send', function() {
                host.open();
                return waitReady(api).then(function() {
                    var track = document.querySelector('.jb-slider-row[data-slider="volGlobal"] .jb-slider-track');
                    api.assertEqual(track.getAttribute('role'), 'slider', 'slider role');
                    api.assertEqual(track.getAttribute('aria-valuenow'), '50', 'slider aria-valuenow seeded');
                    track.focus();
                    key(track, 'ArrowRight');
                    var msg = host.sentMessages[host.sentMessages.length - 1];
                    api.assertEqual(msg.cmd, 'volGlobal', 'ArrowRight sends volGlobal');
                    api.assertEqual(msg.value, 55, 'ArrowRight steps +5');
                    api.assertEqual(track.getAttribute('aria-valuenow'), '55', 'aria-valuenow updated');
                    key(track, 'ArrowLeft');
                    api.assertEqual(host.sentMessages[host.sentMessages.length - 1].value, 50, 'ArrowLeft steps -5');
                    key(track, 'Home');
                    api.assertEqual(host.sentMessages[host.sentMessages.length - 1].value, 0, 'Home sets 0');
                    key(track, 'End');
                    api.assertEqual(host.sentMessages[host.sentMessages.length - 1].value, 100, 'End sets 100');
                    return 'keyboard slider ok';
                });
            }],
            ['keyboard-seek', 'progress bar arrow keys seek', function() {
                host.open();
                return waitReady(api).then(function() {
                    return api.waitFor(function() {
                        var bar = document.getElementById('jbp-progress');
                        return bar && bar.getAttribute('aria-valuemax') === '178' ? bar : null;
                    }, 1500, 'progress aria-valuemax seeded from audio').then(function(bar) {
                        api.assertEqual(bar.getAttribute('role'), 'slider', 'progress role=slider');
                        bar.focus();
                        key(bar, 'ArrowRight');
                        var seekMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'seek'; });
                        api.assert(!!seekMsg, 'seek message sent');
                        api.assert(Math.abs(seekMsg.sec - 13) < 0.01, 'ArrowRight seeks +5s from cursor 8, got ' + seekMsg.sec);
                        key(bar, 'ArrowLeft');
                        var backMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'seek'; });
                        api.assert(Math.abs(backMsg.sec - 8) < 0.01, 'ArrowLeft seeks back -5s, got ' + backMsg.sec);
                        key(bar, 'Home');
                        var homeMsg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'seek'; });
                        api.assertEqual(homeMsg.sec, 0, 'Home seeks to 0');
                        return 'keyboard seek ok';
                    });
                });
            }],
            ['keyboard-settings', 'settings rows activate via Enter/Space with aria-checked sync', function() {
                host.open();
                return waitReady(api).then(function() {
                    var overrideRow = document.querySelector('.jb-setting-item[data-key="override"]');
                    api.assertEqual(overrideRow.getAttribute('role'), 'checkbox', 'override role=checkbox');
                    api.assertEqual(overrideRow.getAttribute('aria-checked'), 'false', 'override aria-checked seeded');
                    overrideRow.focus();
                    key(overrideRow, ' ');
                    api.assert(overrideRow.classList.contains('active'), 'Space toggles override');
                    api.assertEqual(overrideRow.getAttribute('aria-checked'), 'true', 'aria-checked synced on toggle');
                    var msg = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'override'; });
                    api.assert(!!msg && msg.value === true, 'override message sent from keyboard');
                    var albumLoop = document.querySelector('.jb-radio[data-value="albumLoop"]');
                    albumLoop.focus();
                    key(albumLoop, 'Enter');
                    api.assert(albumLoop.classList.contains('active'), 'Enter activates radio');
                    api.assertEqual(albumLoop.getAttribute('aria-checked'), 'true', 'radio aria-checked synced');
                    var singleLoop = document.querySelector('.jb-radio[data-value="singleLoop"]');
                    api.assertEqual(singleLoop.getAttribute('aria-checked'), 'false', 'mutex radio aria-checked cleared');
                    var msg2 = host.sentMessages.slice().reverse().find(function(m) { return m.cmd === 'playMode'; });
                    api.assert(!!msg2 && msg2.value === 'albumLoop', 'playMode message sent from keyboard');
                    return 'keyboard settings ok';
                });
            }],
            ['keyboard-album-dropdown', 'album dropdown keyboard open, navigate, select, esc close', function() {
                host.open();
                return waitReady(api).then(function() {
                    return waitCatalog(api).then(function() {
                        var trigger = document.getElementById('jbp-album-trigger');
                        api.assertEqual(trigger.getAttribute('aria-expanded'), 'false', 'dropdown aria-collapsed');
                        trigger.focus();
                        key(trigger, 'ArrowDown');
                        api.assert(document.getElementById('jbp-album-dropdown').classList.contains('open'), 'ArrowDown opens dropdown');
                        api.assertEqual(trigger.getAttribute('aria-expanded'), 'true', 'aria-expanded true when open');
                        // 焦点延一帧才移入选项（visibility 切换同帧 focus 会被 Blink 拒绝）
                        return api.waitFor(function() {
                            var a = document.activeElement;
                            return a && a.classList.contains('jbp-album-option') ? a : null;
                        }, 1000, 'focus moved into options');
                    }).then(function(focused) {
                        var trigger = document.getElementById('jbp-album-trigger');
                        key(focused, 'ArrowDown');
                        api.assert(document.activeElement !== focused, 'ArrowDown moves to next option');
                        api.assert(document.activeElement.classList.contains('jbp-album-option'), 'focus stays in options');
                        var pb = document.querySelector('.jbp-album-option[data-album="PB"]');
                        pb.focus();
                        key(pb, 'Enter');
                        api.assert(!document.getElementById('jbp-album-dropdown').classList.contains('open'), 'Enter selects and closes');
                        api.assertEqual(document.querySelectorAll('.jbp-track-item').length, 2, 'PB filter applied via keyboard');
                        api.assertEqual(document.activeElement, trigger, 'focus returns to trigger after select');
                        key(trigger, 'Enter');
                        api.assert(document.getElementById('jbp-album-dropdown').classList.contains('open'), 'Enter reopens dropdown');
                        dispatchEsc();
                        api.assert(!document.getElementById('jbp-album-dropdown').classList.contains('open'), 'Esc closes dropdown only');
                        api.assertEqual(Panels.getActive(), 'jukebox', 'panel survives dropdown Esc');
                        return 'keyboard album dropdown ok';
                    });
                });
            }],
            ['esc-layered', 'esc closes help modal first, panel only when no overlay', function() {
                host.open();
                return waitReady(api).then(function() {
                    click(document.getElementById('jbp-help-btn'));
                    return api.waitFor(function() {
                        var modal = document.getElementById('jbp-help-modal');
                        return modal && modal.classList.contains('visible') ? modal : null;
                    }, 1000, 'help modal visible').then(function(modal) {
                        dispatchEsc();
                        api.assert(!modal.classList.contains('visible'), 'Esc closes help modal first');
                        api.assertEqual(Panels.getActive(), 'jukebox', 'panel survives modal Esc');
                        dispatchEsc();
                        api.assertEqual(Panels.getActive(), null, 'Esc closes panel when no overlay open');
                        return 'esc layered ok';
                    });
                });
            }],
            ['help-focus', 'help modal traps tab and restores focus on close', function() {
                host.open();
                return waitReady(api).then(function() {
                    var helpBtn = document.getElementById('jbp-help-btn');
                    click(helpBtn);
                    return api.waitFor(function() {
                        var modal = document.getElementById('jbp-help-modal');
                        return modal && modal.classList.contains('visible') ? modal : null;
                    }, 1000, 'help modal visible').then(function(modal) {
                        var closeBtn = document.getElementById('jbp-help-close');
                        // 焦点延一帧才移入弹窗（visibility 切换同帧 focus 会被 Blink 拒绝）
                        return api.waitFor(function() {
                            return document.activeElement === closeBtn ? closeBtn : null;
                        }, 1000, 'focus moves into modal on open').then(function() {
                            key(closeBtn, 'Tab');
                            api.assertEqual(document.activeElement, closeBtn, 'Tab trapped on single focusable');
                            key(closeBtn, 'Tab', { shiftKey: true });
                            api.assertEqual(document.activeElement, closeBtn, 'Shift+Tab trapped');
                            click(closeBtn);
                            api.assert(!modal.classList.contains('visible'), 'modal closed');
                            api.assertEqual(document.activeElement, helpBtn, 'focus restored to help button');
                            return 'help focus ok';
                        });
                    });
                });
            }],
            ['help-markdown-styled', 'help content uses themed markdown typography', function() {
                host.open();
                return waitReady(api).then(function() {
                    click(document.getElementById('jbp-help-btn'));
                    return api.waitFor(function() {
                        var modal = document.getElementById('jbp-help-modal');
                        return modal && modal.querySelector('.jbp-help-content table') ? modal : null;
                    }, 1500, 'help markdown table rendered').then(function(modal) {
                        var th = modal.querySelector('.jbp-help-content th');
                        api.assertEqual(getComputedStyle(th).color, 'rgb(200, 255, 76)', 'table header themed with phosphor accent');
                        var thBg = getComputedStyle(th).backgroundColor;
                        api.assert(thBg !== 'rgba(0, 0, 0, 0)' && thBg !== 'transparent', 'table header has accent tint background');
                        var h1 = modal.querySelector('.jbp-help-content h1');
                        api.assertEqual(getComputedStyle(h1).color, 'rgb(200, 255, 76)', 'heading themed with phosphor accent');
                        var code = modal.querySelector('.jbp-help-content code');
                        api.assert(!!code, 'inline code rendered');
                        var codeBg = getComputedStyle(code).backgroundColor;
                        api.assert(codeBg !== 'rgba(0, 0, 0, 0)' && codeBg !== 'transparent', 'inline code has themed background');
                        return 'help markdown styled ok';
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
