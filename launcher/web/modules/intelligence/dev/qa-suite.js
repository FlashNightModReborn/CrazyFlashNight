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
            ['runtime-open-state-snapshot-no-bundle', 'runtime open uses state then one snapshot and never requests bundle', function() {
                var start = host.sentMessages.length;
                host.open({ itemName: '资料', mode: 'prod', source: 'runtime', debug: false });
                return waitReady(api).then(function(state) {
                    var sent = host.sentMessages.slice(start).filter(isIntelPanelMessage);
                    var cmds = sent.map(function(m) { return m.cmd; });
                    api.assertEqual(state.runtime, true, 'runtime flag');
                    api.assert(!state.devbarVisible, 'devbar hidden in runtime');
                    api.assert(cmds.indexOf('state') >= 0, 'runtime requests state');
                    api.assert(cmds.indexOf('snapshot') >= 0, 'runtime requests snapshot');
                    api.assert(cmds.indexOf('bundle') < 0, 'runtime does not request bundle');
                    api.assert(cmds.indexOf('state') < cmds.indexOf('snapshot'), 'state precedes snapshot');
                    api.assertEqual(countCmd(sent, 'snapshot'), 1, 'one snapshot on open');
                    api.assertEqual(state.pageCount, 18, 'default snapshot loaded after state');
                    return 'runtime open ok';
                });
            }],
            ['runtime-catalog-progress-values', 'runtime catalog shows mixed per-item progress values from state packet', function() {
                host.open({ itemName: '资料', mode: 'prod', source: 'runtime', debug: false });
                return waitReady(api).then(function() {
                    var longItem = findCatalogButton('幻层残响');
                    var dataItem = findCatalogButton('资料');
                    api.assert(!!longItem && !!dataItem, 'catalog items exist');
                    api.assert(longItem.querySelector('.intel-catalog-meta').textContent.indexOf('12 / 30') >= 0, 'long item uses runtime value 6');
                    api.assert(dataItem.querySelector('.intel-catalog-meta').textContent.indexOf('18 / 18') >= 0, '资料 item uses runtime value 99');
                    return 'runtime progress ok';
                });
            }],
            ['runtime-click-requests-selected-snapshot-only', 'runtime catalog click requests only selected item snapshot and updates reader', function() {
                host.open({ itemName: '资料', mode: 'prod', source: 'runtime', debug: false });
                return waitReady(api).then(function() {
                    var start = host.sentMessages.length;
                    var longItem = findCatalogButton('幻层残响');
                    longItem.click();
                    return api.waitFor(function() {
                        var state = IntelligencePanel._debugGetState();
                        return state.itemName === '幻层残响' && state.pageCount === 30 ? state : null;
                    }, 1000, 'runtime catalog switch').then(function(state) {
                        var sent = host.sentMessages.slice(start).filter(isIntelPanelMessage);
                        api.assertEqual(countCmd(sent, 'snapshot'), 1, 'one snapshot after click');
                        api.assertEqual(countCmd(sent, 'bundle'), 0, 'no bundle after click');
                        api.assertEqual(countCmd(sent, 'state'), 0, 'no state after item click');
                        api.assertEqual(sent[0].itemName, '幻层残响', 'snapshot requests clicked item only');
                        api.assertEqual(state.value, 6, 'reader value comes from runtime per-item value');
                        return 'runtime click ok';
                    });
                });
            }],
            ['runtime-displayname-used-in-catalog-and-reader', 'runtime catalog label and reader title use displayname (not raw name)', function() {
                host.open({ itemName: '资料', mode: 'prod', source: 'runtime', debug: false });
                return waitReady(api).then(function() {
                    var dataItem = findCatalogButton('资料');
                    var labelEl = dataItem.querySelector('.intel-catalog-name');
                    api.assertEqual(labelEl.textContent, '废城基础资料集', 'catalog list shows displayName');
                    api.assertEqual(dataItem.getAttribute('data-name'), '资料', 'data-name still uses canonical name for routing');
                    var readerTitle = document.querySelector('.intel-name');
                    api.assertEqual(readerTitle.textContent, '废城基础资料集', 'reader title shows displayName');
                    return 'displayName ok';
                });
            }],
            ['runtime-tooltip-basic-rich-and-failure', 'runtime catalog hover shows basic tooltip, async AS2-rich tooltip, and failure fallback', function() {
                host.open({ itemName: '资料', mode: 'prod', source: 'runtime', debug: false });
                return waitReady(api).then(function() {
                    var item = findCatalogButton('酒保线报：黑铁会崛起于乡间');
                    api.assert(!!item, 'hover item exists');
                    item.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, clientX: 260, clientY: 220 }));
                    var tt = document.getElementById('panel-tooltip');
                    api.assert(tt && tt.style.display === 'block', 'tooltip shown immediately');
                    api.assert(tt.textContent.indexOf('加载注释') >= 0, 'basic loading tooltip shown');
                    return api.waitFor(function() {
                        return tt.textContent.indexOf('情报注释') >= 0 ? true : null;
                    }, 1000, 'rich tooltip').then(function() {
                        api.assert(!!tt.querySelector('u'), 'AS2 underline converted');
                        api.assert(!!tt.querySelector('span[style]'), 'AS2 font color converted');
                        item.dispatchEvent(new MouseEvent('mouseleave', { bubbles: true }));
                        api.assert(tt.style.display === 'none', 'tooltip hides on leave');

                        var missing = findCatalogButton('缺图记录');
                        missing.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, clientX: 300, clientY: 260 }));
                        return api.waitFor(function() {
                            return tt.textContent.indexOf('注释暂不可用') >= 0 ? true : null;
                        }, 1000, 'tooltip failure fallback').then(function() {
                            api.assert(tt.textContent.indexOf('缺图记录') >= 0, 'basic tooltip remains useful after failure');
                            missing.dispatchEvent(new MouseEvent('mouseleave', { bubbles: true }));
                            return 'runtime tooltip ok';
                        });
                    });
                });
            }],
            ['runtime-tooltip-no-duplicate-displayname', 'rich tooltip does not render displayname twice (intro carries title, panel does not prepend its own)', function() {
                host.open({ itemName: '资料', mode: 'prod', source: 'runtime', debug: false });
                return waitReady(api).then(function() {
                    var dataItem = findCatalogButton('资料');
                    dataItem.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, clientX: 240, clientY: 200 }));
                    var tt = document.getElementById('panel-tooltip');
                    return api.waitFor(function() {
                        return tt.textContent.indexOf('情报注释') >= 0 ? true : null;
                    }, 1000, 'rich tooltip ready').then(function() {
                        var occurrences = tt.textContent.split('废城基础资料集').length - 1;
                        api.assertEqual(occurrences, 1, 'displayName appears exactly once in rich tooltip');
                        dataItem.dispatchEvent(new MouseEvent('mouseleave', { bubbles: true }));
                        return 'no duplicate ok';
                    });
                });
            }],
            ['prod-mode-hides-devbar', 'production mode hides dev bar and frees vertical space for reader', function() {
                host.open({ itemName: '资料', value: 99, decryptLevel: 10, debug: false, mode: 'prod' });
                return waitReady(api).then(function(state) {
                    api.assert(!state.devbarVisible, 'devbar hidden in prod mode');
                    var devbar = document.querySelector('.intel-devbar');
                    api.assert(devbar.hidden, 'devbar element has hidden attribute');
                    api.assertEqual(devbar.offsetHeight, 0, 'devbar takes no layout space');
                    var reader = document.querySelector('.intel-reader');
                    var content = document.querySelector('.intel-content');
                    api.assert(content.getBoundingClientRect().height >= 460, 'reader area expanded vertically');
                    api.assert(reader.getBoundingClientRect().height >= 540, 'reader frame expanded vertically');
                    host.open({ itemName: '资料', value: 99, decryptLevel: 10, debug: true });
                    return waitReady(api).then(function(stateDev) {
                        api.assert(stateDev.devbarVisible, 'devbar visible in dev mode');
                        api.assert(document.querySelector('.intel-devbar').offsetHeight > 20, 'devbar takes layout space when dev');
                        return 'devbar gating ok';
                    });
                });
            }],
            ['devbar-floats-outside-grid', 'dev bar is absolute-positioned outside .intel-shell, leaves reader/header/footer layout untouched', function() {
                // 先开 prod 模式记录基准布局
                host.open({ itemName: '资料', value: 99, decryptLevel: 10, debug: false, mode: 'prod' });
                return waitReady(api).then(function() {
                    return api.wait(60).then(function() {
                        var prodReader = document.querySelector('.intel-reader').getBoundingClientRect();
                        var prodFooter = document.querySelector('.intel-footer').getBoundingClientRect();
                        var prodHeader = document.querySelector('.intel-header').getBoundingClientRect();
                        // 切到 dev 模式
                        host.open({ itemName: '资料', value: 99, decryptLevel: 10, debug: true });
                        return waitReady(api).then(function() {
                            return api.wait(60).then(function() {
                                var devbar = document.querySelector('.intel-devbar');
                                var shell = document.querySelector('.intel-shell');
                                var devReader = document.querySelector('.intel-reader').getBoundingClientRect();
                                var devFooter = document.querySelector('.intel-footer').getBoundingClientRect();
                                var devHeader = document.querySelector('.intel-header').getBoundingClientRect();

                                // 1. devbar 是 .intel-shell 的子节点（跟随 shell 的 transform scale），
                                //    但通过 position:absolute 脱离 grid 流。
                                api.assert(shell.contains(devbar), 'devbar mounted inside .intel-shell (follows scale)');
                                api.assert(devbar.parentElement === shell, 'devbar is direct child of .intel-shell');

                                // 2. position 是 absolute
                                api.assertEqual(window.getComputedStyle(devbar).position, 'absolute', 'devbar uses absolute positioning');

                                // 3. dev/prod 的正文/footer/header 几何完全一致（容差 1px）—— 这是把 devbar 移出 grid 的核心收益
                                assertNear(api, devReader.height, prodReader.height, 1, 'reader height unchanged between dev and prod');
                                assertNear(api, devReader.top, prodReader.top, 1, 'reader top unchanged');
                                assertNear(api, devFooter.top, prodFooter.top, 1, 'footer top unchanged');
                                assertNear(api, devHeader.height, prodHeader.height, 1, 'header height unchanged');

                                // 4. devbar 实际可见且占据 nonzero 区域
                                api.assert(devbar.offsetWidth > 0 && devbar.offsetHeight > 0, 'devbar has visible footprint');

                                // 5. devbar 不挡关键交互按钮（close / catalog-toggle / footer toggle / page indicator）
                                var devbarRect = devbar.getBoundingClientRect();
                                ['intel-close-btn', 'intel-catalog-toggle', 'intel-toggle-btn', 'intel-page-indicator', 'intel-prev-btn', 'intel-next-btn'].forEach(function(cls) {
                                    var btn = document.querySelector('.' + cls);
                                    var rect = btn.getBoundingClientRect();
                                    var overlap = !(devbarRect.right <= rect.left || devbarRect.left >= rect.right || devbarRect.bottom <= rect.top || devbarRect.top >= rect.bottom);
                                    api.assert(!overlap, 'devbar does not overlap .' + cls);
                                });

                                // 6. devbar 不挡 reader 正文（只允许覆盖 catalog 列表底部）
                                var overlapReader = !(devbarRect.right <= devReader.left || devbarRect.left >= devReader.right || devbarRect.bottom <= devReader.top || devbarRect.top >= devReader.bottom);
                                api.assert(!overlapReader, 'devbar does not overlap reader');

                                return 'devbar floats outside grid ok';
                            });
                        });
                    });
                });
            }],
            ['devbar-narrow-viewport', 'dev bar stays usable on narrow viewport without breaking reader or shifting prod-mode geometry', function() {
                host.setViewport('1024x576');
                // 先 prod 拿基准
                host.open({ itemName: '资料', value: 99, decryptLevel: 10, debug: false, mode: 'prod' });
                return waitReady(api).then(function() {
                    return api.wait(80).then(function() {
                        var prodReader = document.querySelector('.intel-reader').getBoundingClientRect();
                        host.open({ itemName: '资料', value: 99, decryptLevel: 10, debug: true });
                        return waitReady(api).then(function() {
                            return api.wait(80).then(function() {
                                var devbar = document.querySelector('.intel-devbar').getBoundingClientRect();
                                var devReader = document.querySelector('.intel-reader').getBoundingClientRect();
                                var panel = document.querySelector('.intelligence-panel').getBoundingClientRect();
                                api.assert(devbar.right <= panel.right + 1, 'devbar stays inside panel right bound');
                                api.assert(devbar.left >= panel.left - 1, 'devbar stays inside panel left bound');
                                api.assert(devbar.top >= panel.top - 1 && devbar.bottom <= panel.bottom + 1, 'devbar stays inside panel vertical bounds');
                                // reader 在 dev/prod 下尺寸仍然一致
                                assertNear(api, devReader.height, prodReader.height, 1, 'reader height stable across modes on narrow viewport');
                                assertNear(api, devReader.width, prodReader.width, 1, 'reader width stable across modes on narrow viewport');
                                // 还原视口避免污染后续用例
                                host.setViewport('1366x768');
                                return 'narrow viewport ok';
                            });
                        });
                    });
                });
            }],
            ['page-indicator-click-toggle', 'page indicator opens horizontal strip on explicit click only (no hover trap)', function() {
                host.open({ itemName: '资料', value: 99, decryptLevel: 10 });
                return waitReady(api).then(function() {
                    IntelligencePanel._debugSetPage(8);
                    var indicator = document.querySelector('.intel-page-indicator');
                    var strip = document.querySelector('.intel-page-strip');
                    var current = document.querySelector('.intel-page-current');
                    var total = document.querySelector('.intel-page-total');

                    // indicator 是 button + 显示当前/总页数 + chevron
                    api.assertEqual(indicator.tagName, 'BUTTON', 'indicator is a button (not input)');
                    api.assertEqual(current.textContent, '9', 'current page rendered as text (no input)');
                    api.assertEqual(total.textContent, '18', 'total page count rendered');
                    api.assert(!!document.querySelector('.intel-page-chevron'), 'chevron present as click affordance');
                    api.assertEqual(indicator.getAttribute('aria-expanded'), 'false', 'aria-expanded false initially');
                    api.assert(strip.hidden, 'strip hidden initially');

                    // hover 不应该唤起 strip（这是这次迭代的核心修复）
                    indicator.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
                    api.assert(strip.hidden, 'mouseenter does NOT open strip (no hover trap)');
                    indicator.dispatchEvent(new MouseEvent('mousemove', { bubbles: true }));
                    api.assert(strip.hidden, 'mousemove does NOT open strip');

                    // click 显式打开
                    indicator.click();
                    api.assert(!strip.hidden, 'click opens strip');
                    api.assertEqual(indicator.getAttribute('aria-expanded'), 'true', 'aria-expanded true when open');
                    api.assert(IntelligencePanel._debugGetState().pagePopupOpen, 'state reports strip open');

                    var list = strip.querySelector('.intel-page-list');
                    api.assertEqual(window.getComputedStyle(list).flexDirection, 'row', 'strip list flows horizontally');
                    var btns = strip.querySelectorAll('.intel-page-btn');
                    api.assertEqual(btns.length, 18, 'strip renders all 18 pages');

                    // 再次 click 收起（toggle 语义）
                    indicator.click();
                    api.assert(strip.hidden, 'second click closes strip');
                    api.assertEqual(indicator.getAttribute('aria-expanded'), 'false', 'aria-expanded reverts to false');

                    // 打开 → 点 strip 内页号 → 跳转并收起
                    indicator.click();
                    api.assert(!strip.hidden, 'strip re-opens for jump test');
                    strip.querySelectorAll('.intel-page-btn')[12].click();
                    api.assertEqual(IntelligencePanel._debugGetState().pageIndex, 12, 'clicking strip btn jumps page');
                    api.assert(strip.hidden, 'strip auto-closes after page click');
                    api.assertEqual(current.textContent, '13', 'current text updates after jump');

                    // outside click 收起
                    indicator.click();
                    api.assert(!strip.hidden, 'strip re-opens for outside-click test');
                    document.body.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
                    api.assert(strip.hidden, 'outside mousedown closes strip');

                    return 'click toggle ok';
                });
            }],
            ['page-strip-fits-footer', 'strip never overflows footer left edge and avoids unnecessary scroll for typical page counts', function() {
                host.open({ itemName: '资料', value: 99, decryptLevel: 10 });
                return waitReady(api).then(function() {
                    document.querySelector('.intel-page-indicator').click();
                    var strip = document.querySelector('.intel-page-strip');
                    var list = strip.querySelector('.intel-page-list');
                    var footer = document.querySelector('.intel-footer').getBoundingClientRect();
                    var panel = document.querySelector('.intelligence-panel').getBoundingClientRect();
                    var stripRect = strip.getBoundingClientRect();
                    // 1. strip 不能超出 footer / panel 的左边沿（关键回归）
                    api.assert(stripRect.left >= footer.left - 1, 'strip stays within footer left bound');
                    api.assert(stripRect.left >= panel.left - 1, 'strip stays within panel left bound');
                    // 2. strip 也不应该突破 panel 右边沿
                    api.assert(stripRect.right <= panel.right + 1, 'strip stays within panel right bound');
                    // 3. 18 页（资料）不应该出现横向滚动条
                    api.assertEqual(list.scrollWidth, list.clientWidth, '18-page strip fits without horizontal scroll');
                    // 4. 三角顶点对准 indicator 几何中心（容差 2px）
                    var triangleX = parseFloat(strip.style.getPropertyValue('--triangle-x'));
                    var indicator = document.querySelector('.intel-page-indicator').getBoundingClientRect();
                    var expectedTriangleX = indicator.left + indicator.width / 2 - stripRect.left;
                    assertNear(api, triangleX, expectedTriangleX, 2, 'triangle x var aligns with indicator center');
                    // 关掉避免污染
                    document.body.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
                    return 'strip fits ok';
                });
            }],
            ['page-strip-long-fixture', 'long 30-page fixture fits or scrolls cleanly within panel bounds', function() {
                host.open({ itemName: '幻层残响', value: 15, decryptLevel: 0 });
                return waitReady(api).then(function(state) {
                    api.assertEqual(state.pageCount, 30, '30-page fixture loaded');
                    document.querySelector('.intel-page-indicator').click();
                    var strip = document.querySelector('.intel-page-strip');
                    var panel = document.querySelector('.intelligence-panel').getBoundingClientRect();
                    var stripRect = strip.getBoundingClientRect();
                    // 即使 30 页也必须 contained 在 panel 内
                    api.assert(stripRect.left >= panel.left - 1, '30-page strip still inside panel left bound');
                    api.assert(stripRect.right <= panel.right + 1, '30-page strip still inside panel right bound');
                    // 30 页 × 28 + 29 × 3 = 927，刚好略大于 max-width 884，允许小幅滚动
                    var list = strip.querySelector('.intel-page-list');
                    api.assert(list.scrollWidth - list.clientWidth < 80, '30-page strip scroll overflow within reasonable margin');
                    document.body.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
                    return 'long strip ok';
                });
            }],
            ['page-indicator-disabled-when-single-page', 'indicator disabled when only one page (chevron hidden, click is no-op)', function() {
                host.open({ itemName: '缺图记录', value: 1, decryptLevel: 0 });
                return waitReady(api).then(function() {
                    var indicator = document.querySelector('.intel-page-indicator');
                    var state = IntelligencePanel._debugGetState();
                    api.assertEqual(state.pageCount, 1, 'single-page fixture loaded');
                    api.assert(indicator.disabled, 'indicator disabled at single-page item');
                    var chevronVis = window.getComputedStyle(document.querySelector('.intel-page-chevron')).visibility;
                    api.assertEqual(chevronVis, 'hidden', 'chevron hidden when disabled');
                    indicator.click();
                    api.assert(document.querySelector('.intel-page-strip').hidden, 'click is no-op when disabled');
                    return 'disabled state ok';
                });
            }],
            ['keyboard-paging', 'arrow / Home / End / PageUp / PageDown drive paging via document-level listeners', function() {
                host.open({ itemName: '资料', value: 99, decryptLevel: 10 });
                return waitReady(api).then(function() {
                    var current = document.querySelector('.intel-page-current');

                    IntelligencePanel._debugSetPage(3);
                    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
                    api.assertEqual(IntelligencePanel._debugGetState().pageIndex, 4, 'ArrowRight advances');
                    api.assertEqual(current.textContent, '5', 'current text reflects ArrowRight');

                    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }));
                    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }));
                    api.assertEqual(IntelligencePanel._debugGetState().pageIndex, 2, 'ArrowLeft retreats');

                    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'End', bubbles: true }));
                    api.assertEqual(IntelligencePanel._debugGetState().pageIndex, 17, 'End jumps to last');
                    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Home', bubbles: true }));
                    api.assertEqual(IntelligencePanel._debugGetState().pageIndex, 0, 'Home jumps to first');

                    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'PageDown', bubbles: true }));
                    api.assertEqual(IntelligencePanel._debugGetState().pageIndex, 5, 'PageDown advances by 5');
                    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'PageUp', bubbles: true }));
                    api.assertEqual(IntelligencePanel._debugGetState().pageIndex, 0, 'PageUp retreats by 5 (clamped)');

                    // strip 打开时 Esc 关闭
                    document.querySelector('.intel-page-indicator').click();
                    api.assert(IntelligencePanel._debugGetState().pagePopupOpen, 'strip opened to test Esc');
                    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
                    api.assert(!IntelligencePanel._debugGetState().pagePopupOpen, 'Esc closes strip');
                    return 'keyboard paging ok';
                });
            }],
            ['paper-vignette', 'reader paper layer carries warm vignette overlay', function() {
                host.open({ itemName: '资料', value: 99, decryptLevel: 10, debug: false, mode: 'prod' });
                return waitReady(api).then(function() {
                    var reader = document.querySelector('.intel-reader');
                    var bg = window.getComputedStyle(reader).backgroundImage;
                    api.assert(bg.indexOf('radial-gradient') >= 0, 'paper background uses radial-gradient layers');
                    api.assert(bg.split('radial-gradient').length - 1 >= 3, 'paper has at least 3 gradient layers (stipple + grain + warm tint)');
                    var shadow = window.getComputedStyle(reader).boxShadow;
                    api.assert(shadow.indexOf('inset') >= 0, 'inset vignette present');
                    var afterBg = window.getComputedStyle(reader, '::after').backgroundImage;
                    api.assert(afterBg.indexOf('linear-gradient') >= 0, '::after edge gradient present');
                    return 'paper texture ok';
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
                host.setViewport('1366x768');
                document.documentElement.style.setProperty('--panel-w', '2400px');
                document.documentElement.style.setProperty('--panel-h', '1400px');
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

    function isIntelPanelMessage(message) {
        return message && message.panel === 'intelligence' && message.cmd;
    }

    function countCmd(messages, cmd) {
        var count = 0;
        for (var i = 0; i < messages.length; i++) {
            if (messages[i].cmd === cmd) count++;
        }
        return count;
    }

    function assertNear(api, actual, expected, tolerance, label) {
        api.assert(Math.abs(actual - expected) <= tolerance,
            label + ': expected ' + expected + ' +/- ' + tolerance + ', got ' + actual);
    }

    return {
        runSuite: runSuite
    };
})();
