var IntelligenceHarnessQA = (function() {
    'use strict';

    function waitReady(api) {
        return api.waitFor(function() {
            var state = IntelligencePanel && IntelligencePanel._debugGetState ? IntelligencePanel._debugGetState() : null;
            return state && state.hasSnapshot ? state : null;
        }, 2000, 'intelligence snapshot');
    }

    function runSuite(api, host, onlyCase) {
        var cases = [
            ['open-close', 'open and close lifecycle', function() {
                host.open({ itemName: '资料', value: 99, decryptLevel: 10 });
                return waitReady(api).then(function() {
                    api.assertEqual(Panels.getActive(), 'intelligence', 'active panel');
                    var close = document.querySelector('.intel-close-btn');
                    assertHit(api, close, 'close button');
                    close.click();
                    api.assertEqual(Panels.getActive(), null, 'panel closed');
                    api.assert(host.closeCount >= 1, 'host close message recorded');
                    host.open({ itemName: '资料', value: 99, decryptLevel: 10 });
                    return waitReady(api).then(function() { return 'lifecycle ok'; });
                });
            }],
            ['default-fixture', 'default fixture renders progress, icon and 18 pages', function() {
                host.open({ itemName: '资料', value: 99, decryptLevel: 10 });
                return waitReady(api).then(function(state) {
                    api.assertEqual(state.pageCount, 18, 'page count');
                    api.assert(document.querySelector('.intel-name').textContent.indexOf('资料') >= 0, 'name rendered');
                    api.assert(document.querySelector('.intel-meta').textContent.indexOf('18 / 18') >= 0, 'found page count rendered');
                    api.assert(document.querySelector('.intel-progress-value').textContent.indexOf('99 / 99') >= 0, 'progress rendered');
                    api.assert(document.querySelector('.intel-icon').style.display !== 'none', 'icon visible');
                    api.assert(document.querySelectorAll('.intel-catalog-item').length >= 3, 'right catalog rendered');
                    return 'default rendered';
                });
            }],
            ['legacy-tags', 'legacy tags are sanitized and rendered', function() {
                host.open({ itemName: '资料', value: 99, decryptLevel: 10 });
                return waitReady(api).then(function() {
                    var content = document.querySelector('.intel-content');
                    api.assert(content.querySelector('strong'), 'strong rendered');
                    api.assert(content.querySelector('span[style]'), 'font color mapped to span');
                    api.assert(content.querySelector('u'), 'underline rendered');
                    api.assert(!content.querySelector('font'), 'font tag removed');
                    api.assert(content.textContent.indexOf('测试玩家') >= 0, 'PC_NAME replaced');
                    return 'legacy tags ok';
                });
            }],
            ['encrypted-toggle', 'decrypted page can toggle encrypted view', function() {
                host.open({ itemName: '资料', value: 99, decryptLevel: 10 });
                return waitReady(api).then(function() {
                    IntelligencePanel._debugSetPage(1);
                    var before = document.querySelector('.intel-content').textContent;
                    document.querySelector('.intel-toggle-btn').click();
                    var after = document.querySelector('.intel-content').textContent;
                    api.assert(before.indexOf('A兵团') >= 0, 'plain text visible');
                    api.assert(after.indexOf('██') >= 0, 'encrypted replacement visible');
                    return 'toggle ok';
                });
            }],
            ['locked-page', 'locked page shows locked state and disables toggle', function() {
                host.open({ itemName: '资料', value: 1, decryptLevel: 0 });
                return waitReady(api).then(function() {
                    IntelligencePanel._debugSetPage(3);
                    api.assert(document.querySelector('.intel-status').textContent.indexOf('尚未发现') >= 0, 'locked status');
                    api.assert(document.querySelector('.intel-toggle-btn').disabled, 'toggle disabled');
                    api.assert(document.querySelector('.intel-empty').textContent.indexOf('锁定') >= 0, 'locked empty text');
                    return 'locked state ok';
                });
            }],
            ['missing-icon', 'missing icon falls back to placeholder', function() {
                host.open({ itemName: '缺图记录', value: 1, decryptLevel: 0 });
                return waitReady(api).then(function() {
                    api.assert(document.querySelector('.intel-icon').style.display === 'none', 'icon hidden');
                    api.assert(document.querySelector('.intel-icon-placeholder').style.display !== 'none', 'placeholder visible');
                    return 'placeholder ok';
                });
            }],
            ['xml-icon-name', 'item xml icon name resolves when dictionary name has no icon', function() {
                host.open({ itemName: '酒保线报：黑铁会崛起于乡间', value: 99, decryptLevel: 10 });
                return waitReady(api).then(function() {
                    api.assert(document.querySelector('.intel-icon').style.display !== 'none', 'header icon visible through iconName');
                    var item = findCatalogButton('酒保线报：黑铁会崛起于乡间');
                    api.assert(!!item, 'catalog item exists');
                    api.assert(!!item.querySelector('img.intel-catalog-icon'), 'catalog icon visible through iconName');
                    return 'xml icon name ok';
                });
            }],
            ['catalog-drawer', 'right catalog switches items and collapses', function() {
                host.open({ itemName: '资料', value: 99, decryptLevel: 10 });
                return waitReady(api).then(function() {
                    var longItem = findCatalogButton('幻层残响');
                    api.assert(!!longItem, 'long item exists');
                    assertHit(api, longItem, 'long item hit');
                    longItem.click();
                    return api.waitFor(function() {
                        var state = IntelligencePanel._debugGetState();
                        return state.itemName === '幻层残响' ? state : null;
                    }, 1000, 'catalog item switch').then(function(state) {
                        api.assertEqual(state.pageCount, 30, 'switched page count');
                        var toggle = document.querySelector('.intel-catalog-toggle');
                        assertHit(api, toggle, 'catalog toggle');
                        toggle.click();
                        state = IntelligencePanel._debugGetState();
                        api.assert(state.catalogCollapsed, 'catalog collapsed state');
                        api.assert(document.querySelector('.intelligence-panel').classList.contains('is-catalog-collapsed'), 'collapsed class');
                        toggle.click();
                        api.assert(!IntelligencePanel._debugGetState().catalogCollapsed, 'catalog expanded again');
                        return 'catalog drawer ok';
                    });
                });
            }],
            ['long-text-scroll', 'long text stays scrollable without panel overflow', function() {
                host.open({ itemName: '幻层残响', value: 15, decryptLevel: 10 });
                return waitReady(api).then(function(state) {
                    api.assertEqual(state.pageCount, 30, 'long fixture page count');
                    var panel = document.querySelector('.intelligence-panel').getBoundingClientRect();
                    var shell = document.getElementById('viewport-shell').getBoundingClientRect();
                    var content = document.querySelector('.intel-content');
                    api.assert(panel.left >= shell.left - 1 && panel.right <= shell.right + 1, 'panel fits horizontally');
                    api.assert(panel.top >= shell.top - 1 && panel.bottom <= shell.bottom + 1, 'panel fits vertically');
                    api.assert(content.scrollHeight > content.clientHeight, 'content scrolls');
                    return 'scroll fit ok';
                });
            }],
            ['viewports', 'window and fullscreen presets keep core controls usable', function() {
                var presets = ['1024x576', '1366x768', '1600x900', '1920x1080'];
                var baseline = null;
                var chain = Promise.resolve();
                presets.forEach(function(preset) {
                    chain = chain.then(function() {
                        host.setViewport(preset);
                        host.open({ itemName: '资料', value: 99, decryptLevel: 10 });
                        return waitReady(api).then(function() {
                            return api.wait(60).then(function() {
                                var panel = document.querySelector('.intelligence-panel').getBoundingClientRect();
                                var shell = document.getElementById('viewport-shell').getBoundingClientRect();
                                var content = document.querySelector('.intel-content').getBoundingClientRect();
                                var ratios = {
                                    aspect: panel.width / panel.height,
                                    contentW: content.width / panel.width,
                                    contentH: content.height / panel.height
                                };
                                api.assert(panel.width <= shell.width + 1, preset + ' panel width fits');
                                api.assert(panel.height <= shell.height + 1, preset + ' panel height fits');
                                api.assert(panel.left >= shell.left - 1 && panel.right <= shell.right + 1, preset + ' panel stays inside horizontal bounds');
                                api.assert(panel.top >= shell.top - 1 && panel.bottom <= shell.bottom + 1, preset + ' panel stays inside vertical bounds');
                                api.assert(content.width > 300 && content.height > 170, preset + ' content readable area');
                                assertNear(api, ratios.aspect, 1180 / 790, 0.015, preset + ' panel aspect');
                                if (!baseline) baseline = ratios;
                                else {
                                    assertNear(api, ratios.contentW, baseline.contentW, 0.035, preset + ' content width ratio');
                                    assertNear(api, ratios.contentH, baseline.contentH, 0.035, preset + ' content height ratio');
                                }
                                assertHit(api, document.querySelector('.intel-close-btn'), preset + ' close hit');
                                assertHit(api, document.querySelector('.intel-next-btn'), preset + ' next hit');
                                assertHit(api, document.querySelector('.intel-prev-btn'), preset + ' prev hit');
                                assertHit(api, document.querySelector('.intel-catalog-toggle'), preset + ' catalog toggle hit');
                            });
                        });
                    });
                });
                return chain.then(function() { return 'viewports ok'; });
            }],
            ['stale-vars-fit', 'panel ignores stale viewport css vars and fits actual parent', function() {
                document.documentElement.style.setProperty('--panel-w', '2400px');
                document.documentElement.style.setProperty('--panel-h', '1400px');
                host.setViewport('1366x768');
                host.open({ itemName: '黑铁会的秘密情报书', value: 99, decryptLevel: 10 });
                return waitReady(api).then(function() {
                    return api.wait(60).then(function() {
                        var panel = document.querySelector('.intelligence-panel').getBoundingClientRect();
                        var shell = document.getElementById('viewport-shell').getBoundingClientRect();
                        var name = document.querySelector('.intel-name').getBoundingClientRect();
                        var content = document.querySelector('.intel-content').getBoundingClientRect();
                        api.assert(panel.left >= shell.left - 1 && panel.right <= shell.right + 1, 'panel fits shell despite stale vars');
                        api.assert(name.left >= panel.left - 1 && name.right <= panel.right + 1, 'title is not clipped');
                        api.assert(content.left >= panel.left - 1 && content.right <= panel.right + 1, 'content is not clipped');
                        return 'stale vars fit ok';
                    });
                });
            }]
        ];

        if (onlyCase) cases = cases.filter(function(item) { return item[0] === onlyCase; });
        if (onlyCase && !cases.length) cases = [['missing-case', 'requested case exists', function() {
            api.assert(false, 'unknown case ' + onlyCase);
        }]];
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
        api.assert(!!el, label + ' exists');
        var rect = el.getBoundingClientRect();
        api.assert(rect.width >= 24 && rect.height >= 24, label + ' has hit size');
        var x = rect.left + rect.width / 2;
        var y = rect.top + rect.height / 2;
        var hit = document.elementFromPoint(x, y);
        api.assert(hit === el || el.contains(hit), label + ' receives pointer');
    }

    function findCatalogButton(name) {
        var buttons = document.querySelectorAll('.intel-catalog-item');
        for (var i = 0; i < buttons.length; i++) {
            if (buttons[i].getAttribute('data-name') === name) return buttons[i];
        }
        return null;
    }

    function assertNear(api, actual, expected, tolerance, label) {
        api.assert(Math.abs(actual - expected) <= tolerance,
            label + ': expected ' + expected + ' +/- ' + tolerance + ', got ' + actual);
    }

    return {
        runSuite: runSuite
    };
})();
