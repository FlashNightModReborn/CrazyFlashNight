var MapPanelHarnessQA = (function() {
    'use strict';

    function pointFor(el) {
        var rect = el.getBoundingClientRect();
        return {
            x: rect.left + (rect.width / 2),
            y: rect.top + (rect.height / 2)
        };
    }

    function hitTarget(el) {
        var point = pointFor(el);
        var hit = document.elementFromPoint(point.x, point.y);
        return {
            point: point,
            hit: hit,
            ok: !!hit && (hit === el || el.contains(hit))
        };
    }

    function assertHitTest(api, el, label) {
        api.assert(!!el, label + ' missing');
        var probe = hitTarget(el);
        api.assert(probe.ok, label + ' is covered by ' + describeEl(probe.hit));
        return probe;
    }

    function clickByHitTest(api, el, label) {
        var probe = assertHitTest(api, el, label);
        probe.hit.click();
        return probe;
    }

    function describeEl(el) {
        if (!el) return 'nothing';
        var desc = el.tagName ? el.tagName.toLowerCase() : 'node';
        if (el.id) desc += '#' + el.id;
        if (el.className && typeof el.className === 'string') {
            desc += '.' + el.className.trim().replace(/\s+/g, '.');
        }
        return desc;
    }

    function waitForReady(api) {
        return api.waitFor(function() {
            var state = window.MapPanel && MapPanel._debugGetState ? MapPanel._debugGetState() : null;
            return state && state.isOpen && !state.loadingVisible ? state : null;
        }, 3000, 'map ready');
    }

    function bootMap(api, host, options) {
        host.setState(options || {});
        host.open();
        return waitForReady(api);
    }

    function currentState() {
        return window.MapPanel && MapPanel._debugGetState ? MapPanel._debugGetState() : null;
    }

    function getPageTab(pageId) {
        return document.querySelector('.map-page-tab[data-page-id="' + pageId + '"]');
    }

    function getFilterButton(filterId) {
        return document.querySelector('.map-filter-hotspot[data-filter-id="' + filterId + '"]');
    }

    function getAvatarSrc() {
        var img = document.querySelector('.map-dynamic-avatar-image');
        return img ? img.getAttribute('src') || '' : '';
    }

    function getVisibleStaticAvatarSlots(pageId, filterId) {
        var page = MapPanelData.getPage(pageId);
        var visibleHotspots = MapPanelData.getVisibleHotspots(pageId, filterId || '');
        var lookup = {};
        var i;
        for (i = 0; i < visibleHotspots.length; i += 1) {
            lookup[visibleHotspots[i].id] = true;
        }
        return (page.staticAvatars || []).filter(function(slot) {
            return !slot.hotspotId || lookup[slot.hotspotId];
        });
    }

    function idsEqual(actual, expected) {
        if (actual.length !== expected.length) return false;
        var i;
        for (i = 0; i < actual.length; i += 1) {
            if (actual[i] !== expected[i]) return false;
        }
        return true;
    }

    function sortIds(ids) {
        return (ids || []).slice().sort();
    }

    function unionSceneVisualRect(page, hotspotId) {
        var sceneVisuals = page && page.sceneVisuals ? page.sceneVisuals : [];
        var rect = null;
        var i;

        for (i = 0; i < sceneVisuals.length; i += 1) {
            var visual = sceneVisuals[i];
            if (!visual || !visual.rect || !visual.hotspotIds || visual.hotspotIds.indexOf(hotspotId) < 0) continue;
            if (!rect) {
                rect = {
                    x: visual.rect.x,
                    y: visual.rect.y,
                    w: visual.rect.w,
                    h: visual.rect.h
                };
                continue;
            }

            var minX = Math.min(rect.x, visual.rect.x);
            var minY = Math.min(rect.y, visual.rect.y);
            var maxX = Math.max(rect.x + rect.w, visual.rect.x + visual.rect.w);
            var maxY = Math.max(rect.y + rect.h, visual.rect.y + visual.rect.h);
            rect.x = minX;
            rect.y = minY;
            rect.w = maxX - minX;
            rect.h = maxY - minY;
        }

        return rect;
    }

    function runSuite(api, host, caseId) {
        var defs = [
            {
                id: 'map-ui1',
                title: 'default open keeps top chrome hit-testable',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'base', roommateGender: 'male' }).then(function(state) {
                        var closeBtn = document.querySelector('.map-panel-close-btn');
                        var schoolTab = getPageTab('school');
                        assertHitTest(api, schoolTab, 'school tab');
                        assertHitTest(api, closeBtn, 'close button');
                        api.assertEqual(state.activePageId, 'base', 'default page');
                        return 'page=' + state.activePageId + ', summary=' + state.summary;
                    });
                }
            },
            {
                id: 'map-ui2',
                title: 'top tabs switch page via real hit test',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'base' }).then(function() {
                        clickByHitTest(api, getPageTab('school'), 'school tab');
                        return api.waitFor(function() {
                            var state = currentState();
                            return state && state.activePageId === 'school' ? state : null;
                        }, 1500, 'switch to school').then(function(state) {
                            return 'activePage=' + state.activePageId;
                        });
                    });
                }
            },
            {
                id: 'map-ui3',
                title: 'right rail filter remains clickable and narrows hotspots',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'faction' }).then(function() {
                        clickByHitTest(api, getFilterButton('rock'), 'rock filter');
                        return api.waitFor(function() {
                            var state = currentState();
                            return state && state.activeFilterId === 'rock' ? state : null;
                        }, 1500, 'switch to rock').then(function(state) {
                            var page = MapPanelData.getPage('faction');
                            var expected = sortIds(page.filters[1].hotspotIds);
                            var actual = sortIds(state.visibleHotspotIds);
                            api.assert(idsEqual(actual, expected), 'rock filter visible hotspots mismatch');
                            return 'visible=' + actual.join(',');
                        });
                    });
                }
            },
            {
                id: 'map-ui4',
                title: 'base hierarchy filter enables layer relation focus mode',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'base' }).then(function() {
                        clickByHitTest(api, getFilterButton('hierarchy'), 'hierarchy filter');
                        return api.waitFor(function() {
                            var state = currentState();
                            return state && state.activePageId === 'base' && state.activeFilterId === 'hierarchy' ? state : null;
                        }, 1500, 'switch to hierarchy').then(function(state) {
                            var stage = document.getElementById('map-stage-frame');
                            var currentHotspot = document.querySelector('.map-hotspot.is-current');
                            var mutedHotspots = document.querySelectorAll('.map-hotspot.is-muted');
                            var relationNodes = document.querySelectorAll('.map-scene-node.is-relationship');
                            api.assert(stage && stage.classList.contains('is-layer-relation'), 'base hierarchy should enable layer relation mode');
                            api.assert(!!currentHotspot, 'hierarchy mode should preserve current hotspot');
                            api.assert(mutedHotspots.length > 0, 'hierarchy mode should mute non-focused hotspots');
                            api.assert(relationNodes.length === state.sceneVisualCount, 'all scene visuals should enter relationship mode');
                            return 'focus=' + state.focusHotspotId + ', mutedHotspots=' + mutedHotspots.length;
                        });
                    });
                }
            },
            {
                id: 'map-ui5',
                title: 'all pages expose assembled visuals and labeled right rail buttons',
                run: function() {
                    var pages = ['base', 'faction', 'defense', 'school'];
                    return bootMap(api, host, { defaultPageId: 'base' }).then(function() {
                        var flow = Promise.resolve();

                        pages.forEach(function(pageId) {
                            flow = flow.then(function() {
                                var tab = getPageTab(pageId);
                                clickByHitTest(api, tab, pageId + ' tab');
                                return api.waitFor(function() {
                                    var state = currentState();
                                    return state && state.activePageId === pageId ? state : null;
                                }, 1500, 'switch to ' + pageId).then(function(state) {
                                    var sceneNodes = document.querySelectorAll('.map-scene-node');
                                    var labels = Array.prototype.slice.call(document.querySelectorAll('.map-filter-hotspot-label')).map(function(el) {
                                        return (el.textContent || '').trim();
                                    }).filter(Boolean);
                                    api.assert(state.renderMode === 'assembled', pageId + ' should use assembled render mode');
                                    api.assert(state.sceneVisualCount > 0, pageId + ' should render composite scene nodes');
                                    api.assert(sceneNodes.length === state.sceneVisualCount, pageId + ' scene visual count mismatch');
                                    api.assert(labels.length > 0, pageId + ' filter labels missing');
                                });
                            });
                        });

                        return flow.then(function() {
                            return 'pages=' + pages.join(',');
                        });
                    });
                }
            },
            {
                id: 'map-ui6',
                title: 'school roommate avatar follows snapshot gender',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'school', roommateGender: 'male' }).then(function() {
                        return api.waitFor(function() {
                            var src = getAvatarSrc();
                            return src.indexOf('roommate-male.png') >= 0 ? src : null;
                        }, 1500, 'male roommate avatar');
                    }).then(function() {
                        host.setState({ roommateGender: 'female', defaultPageId: 'school' });
                        host.pushSnapshot('refresh');
                        return api.waitFor(function() {
                            var src = getAvatarSrc();
                            return src.indexOf('roommate-female.png') >= 0 ? src : null;
                        }, 1500, 'female roommate avatar');
                    }).then(function(src) {
                        return 'avatar=' + src.split('/').slice(-1)[0];
                    });
                }
            },
            {
                id: 'map-ui7',
                title: 'compact viewport keeps chrome reachable and fits stage down',
                run: function() {
                    host.setViewport('1366x768');
                    return bootMap(api, host, { defaultPageId: 'base' }).then(function() {
                        var shell = document.getElementById('viewport-shell').getBoundingClientRect();
                        var body = document.querySelector('.map-panel-body');
                        var stage = document.getElementById('map-stage-frame');
                        var baseTab = getPageTab('base');
                        var closeBtn = document.querySelector('.map-panel-close-btn');
                        var tabProbe = assertHitTest(api, baseTab, 'base tab');
                        var closeProbe = assertHitTest(api, closeBtn, 'close button');
                        var state = currentState();
                        var style = window.getComputedStyle(body);
                        var stageRect = stage.getBoundingClientRect();
                        api.assert(style.overflowY === 'auto', 'map body should scroll in compact viewport');
                        api.assert(!!state && state.compactMode, 'compact viewport should enable compact mode');
                        api.assert(!!state && state.stageScale < 1, 'compact viewport should scale stage below 1');
                        api.assert(tabProbe.point.y >= shell.top && tabProbe.point.y <= shell.bottom, 'tab center fell outside viewport shell');
                        api.assert(closeProbe.point.y >= shell.top && closeProbe.point.y <= shell.bottom, 'close center fell outside viewport shell');
                        api.assert(stageRect.bottom <= shell.bottom + 1, 'stage bottom should fit within viewport shell');
                        return 'overflowY=' + style.overflowY + ', scroll=' + body.scrollHeight + '/' + body.clientHeight + ', scale=' + state.stageScale.toFixed(3);
                    }).then(function(detail) {
                        host.setViewport('1600x900');
                        return detail;
                    }, function(err) {
                        host.setViewport('1600x900');
                        throw err;
                    });
                }
            },
            {
                id: 'map-ui8',
                title: 'current location feedback follows snapshot hotspot',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'base' }).then(function(state) {
                        var marker = document.querySelector('.map-feedback-marker');
                        var currentHotspot = document.querySelector('.map-hotspot.is-current');
                        api.assert(!!state.currentHotspotId, 'snapshot should expose currentHotspotId');
                        api.assert(!!marker, 'current location marker missing');
                        api.assert(!!currentHotspot, 'current hotspot missing active state');
                        api.assert(currentHotspot.getAttribute('data-hotspot-id') === state.currentHotspotId, 'stage current hotspot mismatch');
                        api.assert(!marker.querySelector('.map-feedback-marker-label'), 'current location marker should no longer render inline label (tips layer owns text)');
                        return 'current=' + state.currentHotspotId;
                    });
                }
            },
            {
                id: 'map-ui9',
                title: 'locked groups keep hint and locked reason reachable',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'school', lockedGroups: ['schoolInside'] }).then(function(state) {
                        var hotspot = document.querySelector('.map-hotspot[data-hotspot-id="school_dormitory"]');
                        var hint = document.querySelector('.map-feedback-hint');
                        api.assert(state.lockedHotspotIds.indexOf('school_dormitory') >= 0, 'school dormitory should be locked');
                        api.assert(!!hint, 'locked filter hint missing');
                        api.assert(!!hotspot, 'locked hotspot missing');
                        api.assert(!!hotspot.getAttribute('data-locked-reason'), 'locked hotspot reason missing');
                        hotspot.click();
                        api.assert((window.Toast && window.Toast.messages || []).length > 0, 'locked hotspot click should emit toast');
                        return 'toast=' + window.Toast.messages.slice(-1)[0];
                    });
                }
            },
            {
                id: 'map-ui10',
                title: 'static avatar coverage matches visible slots and source metadata',
                run: function() {
                    var pages = ['base', 'faction', 'defense', 'school'];
                    return bootMap(api, host, { defaultPageId: 'base' }).then(function() {
                        var flow = Promise.resolve();

                        pages.forEach(function(pageId) {
                            flow = flow.then(function() {
                                clickByHitTest(api, getPageTab(pageId), pageId + ' tab');
                                return api.waitFor(function() {
                                    var state = currentState();
                                    return state && state.activePageId === pageId ? state : null;
                                }, 1500, 'switch to ' + pageId).then(function(state) {
                                    var visibleSlots = getVisibleStaticAvatarSlots(pageId, state.activeFilterId);
                                    var rendered = document.querySelectorAll('.map-static-avatar');
                                    var page = MapPanelData.getPage(pageId);
                                    api.assert(rendered.length === visibleSlots.length, pageId + ' static avatar count mismatch');
                                    if (typeof MapAvatarSourceData !== 'undefined' && MapAvatarSourceData && MapAvatarSourceData.getByAssetUrl) {
                                        visibleSlots.forEach(function(slot) {
                                            var sourceSlot = MapAvatarSourceData.getByAssetUrl(slot.assetUrl);
                                            var avatarEl;
                                            var expectedRect;
                                            api.assert(!!sourceSlot, pageId + ' missing avatar source meta for ' + slot.id);
                                            avatarEl = document.querySelector('.map-static-avatar[data-avatar-id="' + slot.id + '"]');
                                            api.assert(!!avatarEl, pageId + ' missing avatar element for ' + slot.id);
                                            expectedRect = sourceSlot && sourceSlot.rect
                                                ? sourceSlot.rect
                                                : { x: slot.x, y: slot.y, w: slot.w, h: slot.h };
                                            api.assert(Math.abs(parseFloat(avatarEl.style.left) - ((expectedRect.x / page.width) * 100)) < 0.05, pageId + ' avatar left mismatch for ' + slot.id);
                                            api.assert(Math.abs(parseFloat(avatarEl.style.top) - ((expectedRect.y / page.height) * 100)) < 0.05, pageId + ' avatar top mismatch for ' + slot.id);
                                            api.assert(Math.abs(parseFloat(avatarEl.style.width) - ((expectedRect.w / page.width) * 100)) < 0.05, pageId + ' avatar width mismatch for ' + slot.id);
                                            api.assert(Math.abs(parseFloat(avatarEl.style.height) - ((expectedRect.h / page.height) * 100)) < 0.05, pageId + ' avatar height mismatch for ' + slot.id);
                                        });
                                    }
                                });
                            });
                        });

                        return flow.then(function() {
                            return 'pages=' + pages.join(',');
                        });
                    });
                }
            },
            {
                id: 'map-ui12',
                title: 'task npc ring anchors to dynamic roommate avatar center',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'school', roommateGender: 'female' }).then(function() {
                        var page = MapPanelData.getPage('school');
                        var slot = null;
                        var dyn = page.dynamicAvatars || [];
                        for (var i = 0; i < dyn.length; i += 1) {
                            if (dyn[i].id === 'roommate') { slot = dyn[i]; break; }
                        }
                        api.assert(!!slot, 'school page missing roommate dynamic slot');

                        var snapshot = host.buildSnapshot();
                        snapshot.markers = (snapshot.markers || []).concat([{
                            id: 'task_npc_室友',
                            kind: 'taskNpc',
                            npcName: '室友',
                            pageId: 'school',
                            hotspotId: 'school_dormitory',
                            point: { x: 130.3, y: 347.3 }
                        }]);
                        MapPanel._debugApplySnapshot(snapshot);

                        return api.waitFor(function() {
                            return document.querySelector('.map-avatar-task-ring[data-hotspot-id="school_dormitory"]');
                        }, 1500, 'task ring appears').then(function(ring) {
                            var expectedX = (slot.x + slot.w / 2) / page.width * 100;
                            var expectedY = (slot.y + slot.h / 2) / page.height * 100;
                            var actualX = parseFloat(ring.style.left);
                            var actualY = parseFloat(ring.style.top);
                            api.assert(Math.abs(actualX - expectedX) < 0.02, 'ring x drift: expected=' + expectedX.toFixed(3) + ' actual=' + actualX.toFixed(3));
                            api.assert(Math.abs(actualY - expectedY) < 0.02, 'ring y drift: expected=' + expectedY.toFixed(3) + ' actual=' + actualY.toFixed(3));
                            return 'ringLeft=' + ring.style.left + ' ringTop=' + ring.style.top;
                        });
                    });
                }
            },
            {
                id: 'map-ui13',
                title: 'navigate dedup: double-clicking a hotspot only sends one navigate',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'base', failNavigate: true }).then(function() {
                        var btn = document.querySelector('.map-hotspot[data-hotspot-id="base_entrance"]');
                        api.assert(!!btn, 'base_entrance hotspot button missing');

                        var beforeCount = host.getMessages().filter(function(m) { return m && m.cmd === 'navigate'; }).length;
                        btn.click();
                        btn.click();
                        btn.click();

                        var afterCount = host.getMessages().filter(function(m) { return m && m.cmd === 'navigate'; }).length;
                        api.assert(afterCount - beforeCount === 1, 'expected exactly 1 navigate, got ' + (afterCount - beforeCount));
                        api.assert(btn.disabled === true, 'busy hotspot should be physically disabled');

                        host.setState({ failNavigate: false });
                        return 'navigateCount=' + (afterCount - beforeCount);
                    });
                }
            },
            {
                id: 'map-ui14',
                title: 'audio cue attributes routed for hotspots / tabs / filters / close',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'faction' }).then(function() {
                        var tab = document.querySelector('.map-page-tab[data-page-id="base"]');
                        api.assert(tab && tab.getAttribute('data-audio-cue') === 'select', 'page tab missing select cue');

                        var closeBtn = document.querySelector('.map-panel-close-btn');
                        api.assert(closeBtn && closeBtn.getAttribute('data-audio-cue') === 'cancel', 'close btn missing cancel cue');

                        var filter = document.querySelector('.map-filter-hotspot');
                        api.assert(filter && (filter.getAttribute('data-audio-cue') === 'select' || filter.getAttribute('data-audio-cue') === 'error'), 'filter btn missing cue');

                        return bootMap(api, host, { defaultPageId: 'base', disabledIds: ['base_lobby'] }).then(function() {
                            var enabledHs = document.querySelector('.map-hotspot[data-hotspot-id="base_entrance"]');
                            api.assert(enabledHs && enabledHs.getAttribute('data-audio-cue') === 'transition', 'enabled hotspot should route transition');

                            var disabledHs = document.querySelector('.map-hotspot[data-hotspot-id="base_lobby"]');
                            api.assert(disabledHs && disabledHs.getAttribute('data-audio-cue') === 'error', 'disabled hotspot should route error');

                            api.assert(!document.querySelector('.map-scene-chip'), 'scene chip strip removed; right rail owns filter/floor navigation now');
                            api.assert(!document.querySelector('.map-scene-strip'), 'scene chip strip container should not be in DOM');

                            return 'cues=ok';
                        });
                    });
                }
            },
            {
                id: 'map-ui15',
                title: 'filter rail lives outside stage frame and body has no overflow',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'base' }).then(function() {
                        var stage = document.getElementById('map-stage-frame');
                        var rail = document.getElementById('map-rail-shell');
                        var body = document.querySelector('.map-panel-body');
                        api.assert(!!stage && !!rail && !!body, 'stage / rail / body must exist');
                        api.assert(!stage.contains(rail), 'rail must not live inside stage frame');
                        api.assert(body.contains(rail) && body.contains(stage), 'rail & stage must both be body children');
                        // 过一个 rAF 让 layout 稳定
                        return new Promise(function(resolve) { requestAnimationFrame(function() { requestAnimationFrame(resolve); }); }).then(function() {
                            var overflowY = body.scrollHeight - body.clientHeight;
                            var overflowX = body.scrollWidth - body.clientWidth;
                            api.assert(overflowY <= 1, 'body should not overflow vertically (got ' + overflowY + 'px)');
                            api.assert(overflowX <= 1, 'body should not overflow horizontally (got ' + overflowX + 'px)');
                            var stageRect = stage.getBoundingClientRect();
                            var railRect = rail.getBoundingClientRect();
                            api.assert(railRect.left >= stageRect.right - 1, 'rail should sit to the right of stage (stage.right=' + stageRect.right.toFixed(1) + ', rail.left=' + railRect.left.toFixed(1) + ')');
                            return 'stage=' + Math.round(stageRect.width) + 'x' + Math.round(stageRect.height) + ' rail=' + Math.round(railRect.width) + 'x' + Math.round(railRect.height);
                        });
                    });
                }
            },
            {
                id: 'map-ui11',
                title: 'base hotspot rects stay aligned with assembled scene visuals',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'base' }).then(function() {
                        var page = MapPanelData.getPage('base');
                        var summary = [];

                        page.hotspots.forEach(function(hotspot) {
                            var unionRect = unionSceneVisualRect(page, hotspot.id);
                            api.assert(!!unionRect, 'base missing scene union for ' + hotspot.id);
                            api.assert(Math.abs(hotspot.rect.x - unionRect.x) < 0.05, 'base hotspot x drift for ' + hotspot.id);
                            api.assert(Math.abs(hotspot.rect.y - unionRect.y) < 0.05, 'base hotspot y drift for ' + hotspot.id);
                            api.assert(Math.abs(hotspot.rect.w - unionRect.w) < 0.05, 'base hotspot w drift for ' + hotspot.id);
                            api.assert(Math.abs(hotspot.rect.h - unionRect.h) < 0.05, 'base hotspot h drift for ' + hotspot.id);
                            summary.push(hotspot.id);
                        });

                        return 'hotspots=' + summary.length;
                    });
                }
            }
        ];

        if (caseId) {
            defs = defs.filter(function(item) { return item.id === caseId; });
        }

        var results = [];
        var flow = Promise.resolve();
        defs.forEach(function(def) {
            flow = flow.then(function() {
                return api.runCase(def.id, def.title, def.run);
            }).then(function(result) {
                results.push(result);
            });
        });

        return flow.then(function() {
            return MinigameHarness.normalizeBundle(results);
        });
    }

    function runScenario(api, host, scenario) {
        if (scenario === 'school-female') {
            host.setState({ defaultPageId: 'school', roommateGender: 'female' });
            host.open();
            return waitForReady(api).then(function(state) {
                return 'page=' + state.activePageId + ', avatar=' + getAvatarSrc().split('/').slice(-1)[0];
            });
        }

        if (scenario === 'compact') {
            host.setViewport('1366x768');
            host.open();
            return waitForReady(api).then(function() {
                return 'compact viewport ready';
            });
        }

        if (scenario === 'faction-rock') {
            host.setState({ defaultPageId: 'faction' });
            host.open();
            return waitForReady(api).then(function() {
                clickByHitTest(api, getFilterButton('rock'), 'rock filter');
                return api.waitFor(function() {
                    var state = currentState();
                    return state && state.activeFilterId === 'rock' ? state : null;
                }, 1500, 'switch to rock');
            }).then(function(state) {
                return 'activeFilter=' + state.activeFilterId;
            });
        }

        host.open();
        return waitForReady(api).then(function(state) {
            return 'page=' + state.activePageId;
        });
    }

    function collectDump(host) {
        var shell = document.getElementById('viewport-shell');
        return {
            hostState: host.getState(),
            sentMessages: host.getMessages(),
            mapState: currentState(),
            avatarSrc: getAvatarSrc(),
            toastMessages: window.Toast && window.Toast.messages ? window.Toast.messages.slice() : [],
            viewport: host.getViewport(),
            shellRect: shell ? shell.getBoundingClientRect() : null
        };
    }

    return {
        runSuite: runSuite,
        runScenario: runScenario,
        collectDump: collectDump
    };
})();
