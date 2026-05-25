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
            return state && state.isOpen && !state.loadingVisible && isCanvasCurrent(state) ? state : null;
        }, 3000, 'map ready');
    }

    function isCanvasCurrent(state) {
        var summary;
        if (!state || !state.canvasReady) return true;
        summary = state.canvasLastDrawSummary;
        if (!summary || !(state.canvasDrawCount > 0)) return false;
        if (summary.pageId !== state.activePageId) return false;
        if ((summary.filterId || '') !== (state.activeFilterId || '')) return false;
        if (state.canvasRequestedRevision && state.canvasLastRevision < state.canvasRequestedRevision) return false;
        return true;
    }

    function waitForCanvasCurrent(api, label) {
        return api.waitFor(function() {
            var state = currentState();
            return isCanvasCurrent(state) ? state : null;
        }, 1500, label || 'canvas current');
    }

    function bootMap(api, host, options) {
        var patch = {
            currentHotspotId: '',
            disabledIds: [],
            lockedGroups: [],
            taskNpcHotspots: [],
            failNavigate: false
        };
        var key;
        options = options || {};
        for (key in options) {
            patch[key] = options[key];
        }
        host.setState(patch);
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

    function getHotspotOverlayLabel(hotspotId) {
        return document.querySelector('.map-hotspot-overlay-label[data-hotspot-id="' + hotspotId + '"]');
    }

    function getAvatarSrc() {
        var state = currentState();
        if (state && state.canvasLastDynamicAvatarUrl) return state.canvasLastDynamicAvatarUrl;
        return '';
    }

    function assertCanvasReady(api, label) {
        var state = currentState();
        var canvas = document.getElementById('map-stage-canvas');
        var ctx;
        var pixel;
        api.assert(!!canvas, label + ' canvas missing');
        api.assert(!!state && state.renderer === 'canvas', label + ' should use canvas renderer');
        api.assert(!!state.canvasReady, label + ' canvas renderer not ready');
        api.assert((state.canvasDrawCount || 0) > 0, label + ' canvas draw count should be > 0');
        api.assert(canvas.width > 0 && canvas.height > 0, label + ' canvas backing store should be sized');
        ctx = canvas.getContext && canvas.getContext('2d');
        api.assert(!!ctx, label + ' canvas 2d context missing');
        pixel = ctx.getImageData(Math.floor(canvas.width / 2), Math.floor(canvas.height / 2), 1, 1).data;
        api.assert(pixel[3] > 0, label + ' canvas center pixel should be non-empty');
        return state;
    }

    function getVisibleStaticAvatarSlots(pageId, filterId) {
        var page = MapPanelData.getPage(pageId);
        var visibleHotspots = MapPanelData.getVisibleHotspots(pageId, filterId || '');
        var state = currentState() || {};
        var lookup = {};
        var enabledLookup = {};
        var i;
        for (i = 0; i < visibleHotspots.length; i += 1) {
            lookup[visibleHotspots[i].id] = true;
        }
        (state.enabledHotspotIds || []).forEach(function(id) {
            enabledLookup[id] = true;
        });
        return (page.staticAvatars || []).filter(function(slot) {
            var sourceSlot;
            var hotspotId;
            if (slot.hotspotId && !lookup[slot.hotspotId]) return false;
            if (slot.hotspotId && !enabledLookup[slot.hotspotId]) return false;
            if (!slot.assetUrl) return false;
            if (typeof MapAvatarSourceData === 'undefined' || !MapAvatarSourceData || !MapAvatarSourceData.getByAssetUrl) return true;
            sourceSlot = MapAvatarSourceData.getByAssetUrl(slot.assetUrl);
            if (!sourceSlot || !sourceSlot.size) return false;
            hotspotId = sourceSlot.hotspotId || slot.hotspotId;
            return !!(hotspotId && MapPanelData.findHotspot(pageId, hotspotId));
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

    function rectContainsPoint(rect, x, y) {
        return !!rect &&
            x >= rect.x &&
            x <= rect.x + rect.w &&
            y >= rect.y &&
            y <= rect.y + rect.h;
    }

    function rectCenter(rect) {
        return {
            x: rect.x + (rect.w / 2),
            y: rect.y + (rect.h / 2)
        };
    }

    function pointDistance(a, b) {
        var dx = a.x - b.x;
        var dy = a.y - b.y;
        return Math.sqrt((dx * dx) + (dy * dy));
    }

    function roundAuditValue(value) {
        return Math.round(Number(value || 0) * 10) / 10;
    }

    function buildStaticAvatarOwnershipAudit(pageId) {
        var page = MapPanelData.getPage(pageId);
        var hotspots = page && page.hotspots ? page.hotspots : [];
        var visuals = page && page.sceneVisuals ? page.sceneVisuals : [];
        var hasSourceData = typeof MapAvatarSourceData !== 'undefined'
            && MapAvatarSourceData
            && typeof MapAvatarSourceData.getByAssetUrl === 'function';

        return (page && page.staticAvatars ? page.staticAvatars : []).map(function(slot) {
            var sourceSlot = hasSourceData ? MapAvatarSourceData.getByAssetUrl(slot.assetUrl || '') : null;
            var sourceSize = sourceSlot && sourceSlot.size ? sourceSlot.size : null;
            var halfW = sourceSize ? sourceSize.w / 2 : 0;
            var halfH = sourceSize ? sourceSize.h / 2 : 0;
            // C 阶段后 source-data 不带 rect, 用 hotspotId+relX+relY 推导
            var ownerHotspotId = sourceSlot ? (sourceSlot.hotspotId || slot.hotspotId) : slot.hotspotId;
            var ownerHotspot = ownerHotspotId ? MapPanelData.findHotspot(pageId, ownerHotspotId) : null;
            var center = (sourceSlot && ownerHotspot && ownerHotspot.rect) ? {
                x: ownerHotspot.rect.x + sourceSlot.relX + halfW,
                y: ownerHotspot.rect.y + sourceSlot.relY + halfH
            } : { x: 0, y: 0 };
            var containingHotspotIds = hotspots.filter(function(hotspot) {
                return rectContainsPoint(hotspot.rect, center.x, center.y);
            }).map(function(hotspot) {
                return hotspot.id;
            });
            var containingVisualIds = visuals.filter(function(visual) {
                return rectContainsPoint(visual.rect, center.x, center.y);
            }).map(function(visual) {
                return visual.hotspotIds && visual.hotspotIds.length ? visual.hotspotIds[0] : visual.id;
            });
            var containingIds = sortIds(Array.from(new Set(containingHotspotIds.concat(containingVisualIds))));
            var assignedHotspot = hotspots.filter(function(hotspot) {
                return hotspot.id === slot.hotspotId;
            })[0] || null;
            var assignedDistance = assignedHotspot ? pointDistance(center, rectCenter(assignedHotspot.rect)) : Infinity;
            var nearestContaining = hotspots.filter(function(hotspot) {
                return containingIds.indexOf(hotspot.id) >= 0;
            }).map(function(hotspot) {
                return {
                    id: hotspot.id,
                    distance: pointDistance(center, rectCenter(hotspot.rect))
                };
            }).sort(function(a, b) {
                return a.distance - b.distance;
            });
            var nearestHotspot = hotspots.map(function(hotspot) {
                return {
                    id: hotspot.id,
                    distance: pointDistance(center, rectCenter(hotspot.rect))
                };
            }).sort(function(a, b) {
                return a.distance - b.distance;
            })[0] || null;
            var assignedContains = containingIds.indexOf(slot.hotspotId) >= 0;
            var clearMismatchHotspotId = (!assignedContains && containingIds.length === 1) ? containingIds[0] : '';
            var ambiguousMismatchHotspotId = '';

            if (assignedContains && nearestContaining.length > 0 && nearestContaining[0].id !== slot.hotspotId && isFinite(assignedDistance)) {
                if (nearestContaining[0].distance <= assignedDistance * 0.5) {
                    ambiguousMismatchHotspotId = nearestContaining[0].id;
                }
            }

            return {
                avatarId: slot.id,
                label: slot.label || slot.id,
                assignedHotspotId: slot.hotspotId || '',
                centerX: roundAuditValue(center.x),
                centerY: roundAuditValue(center.y),
                containingHotspotIds: containingHotspotIds,
                containingVisualIds: containingVisualIds,
                containingIds: containingIds,
                assignedContains: assignedContains,
                assignedDistance: isFinite(assignedDistance) ? roundAuditValue(assignedDistance) : null,
                nearestHotspotId: nearestHotspot ? nearestHotspot.id : '',
                nearestHotspotDistance: nearestHotspot ? roundAuditValue(nearestHotspot.distance) : null,
                clearMismatchHotspotId: clearMismatchHotspotId,
                ambiguousMismatchHotspotId: ambiguousMismatchHotspotId
            };
        });
    }

    function runSuite(api, host, caseId) {
        var defs = [
            {
                id: 'map-ui1',
                title: 'default open keeps top chrome hit-testable and uses roomy stage space',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'base', roommateGender: 'male' }).then(function() {
                        return api.waitFor(function() {
                            var s = currentState();
                            return s && s.activePageId === 'base' && s.stageScale > 1 && s.contentFitScale >= 1.02 && isCanvasCurrent(s) ? s : null;
                        }, 1500, 'roomy layout ready').then(function(state) {
                            var closeBtn = document.querySelector('.map-panel-close-btn');
                            var schoolTab = getPageTab('school');
                            var canvasState = assertCanvasReady(api, 'map-ui1');
                            assertHitTest(api, schoolTab, 'school tab');
                            assertHitTest(api, closeBtn, 'close button');
                            api.assertEqual(state.activePageId, 'base', 'default page');
                            api.assert(state.contentFitScale >= 1.02, 'roomy viewport should apply content fit scale');
                            api.assert(state.contentCoverageX >= 0.84, 'content should occupy most stage width');
                            api.assert(state.contentCoverageY >= 0.78, 'content should occupy most stage height');
                            api.assert(canvasState.canvasLastDrawSummary && canvasState.canvasLastDrawSummary.sceneCount > 0, 'base page should render canvas scene visuals');
                            return 'page=' + state.activePageId +
                                ', stageScale=' + state.stageScale.toFixed(3) +
                                ', fit=' + state.contentFitScale.toFixed(3) +
                                ', coverage=' + state.contentCoverageX.toFixed(2) + '/' + state.contentCoverageY.toFixed(2) +
                                ', canvasDraws=' + canvasState.canvasDrawCount;
                        });
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
                            return state && state.activePageId === 'base' && state.activeFilterId === 'hierarchy' && isCanvasCurrent(state) ? state : null;
                        }, 1500, 'switch to hierarchy').then(function(state) {
                            var stage = document.getElementById('map-stage-frame');
                            var currentHotspot = document.querySelector('.map-hotspot.is-current');
                            var mutedHotspots = document.querySelectorAll('.map-hotspot.is-muted');
                            api.assert(stage && stage.classList.contains('is-layer-relation'), 'base hierarchy should enable layer relation mode');
                            api.assert(!!currentHotspot, 'hierarchy mode should preserve current hotspot');
                            api.assert(mutedHotspots.length > 0, 'hierarchy mode should mute non-focused hotspots');
                            api.assert(state.renderer === 'canvas' && state.canvasLastDrawSummary.sceneCount === state.sceneVisualCount, 'canvas should render all relationship scene visuals');
                            return 'focus=' + state.focusHotspotId + ', mutedHotspots=' + mutedHotspots.length + ', canvasScenes=' + state.canvasLastDrawSummary.sceneCount;
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
                                    return state && state.activePageId === pageId && isCanvasCurrent(state) ? state : null;
                                }, 1500, 'switch to ' + pageId).then(function(state) {
                                    var labels = Array.prototype.slice.call(document.querySelectorAll('.map-filter-hotspot-label')).map(function(el) {
                                        return (el.textContent || '').trim();
                                    }).filter(Boolean);
                                    api.assert(state.renderMode === 'assembled', pageId + ' should use assembled render mode');
                                    api.assert(state.renderer === 'canvas', pageId + ' should use canvas renderer');
                                    api.assert(state.sceneVisualCount > 0, pageId + ' should render composite scene visuals');
                                    api.assert(state.canvasLastDrawSummary && state.canvasLastDrawSummary.sceneCount === state.sceneVisualCount, pageId + ' canvas scene visual count mismatch');
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
                title: 'fullscreen roundtrip restores compact stage height and scale',
                run: function() {
                    host.setViewport('1024x576');
                    return bootMap(api, host, { defaultPageId: 'base' }).then(function() {
                        var viewportShell = document.getElementById('viewport-shell').getBoundingClientRect();
                        var body = document.querySelector('.map-panel-body');
                        var stageShell = document.getElementById('map-stage-shell');
                        var stage = document.getElementById('map-stage-frame');
                        var baseTab = getPageTab('base');
                        var closeBtn = document.querySelector('.map-panel-close-btn');
                        var tabProbe = assertHitTest(api, baseTab, 'base tab');
                        var closeProbe = assertHitTest(api, closeBtn, 'close button');
                        var state = currentState();
                        var style = window.getComputedStyle(body);
                        var stageRect = stage.getBoundingClientRect();
                        var compactShellRatio = stageShell.clientHeight / body.clientHeight;
                        api.assert(style.overflowY === 'auto', 'map body should scroll in compact viewport');
                        api.assert(!!state && state.compactMode, 'compact viewport should enable compact mode');
                        api.assert(!!state && state.stageScale < 1, 'compact viewport should scale stage below 1');
                        api.assert(!!state && state.contentFitScale >= 1, 'compact viewport should keep content-fit active');
                        api.assert(!!state && state.contentCoverageX >= 0.8, 'compact viewport should keep good horizontal content coverage');
                        api.assert(!!state && state.contentCoverageY >= 0.74, 'compact viewport should keep good vertical content coverage');
                        api.assert(compactShellRatio >= 0.8, 'compact viewport should keep stage shell vertically engaged');
                        api.assert(tabProbe.point.y >= viewportShell.top && tabProbe.point.y <= viewportShell.bottom, 'tab center fell outside viewport shell');
                        api.assert(closeProbe.point.y >= viewportShell.top && closeProbe.point.y <= viewportShell.bottom, 'close center fell outside viewport shell');
                        api.assert(stageRect.bottom <= viewportShell.bottom + 1, 'stage bottom should fit within viewport shell');
                        var compactDetail = 'overflowY=' + style.overflowY +
                            ', scroll=' + body.scrollHeight + '/' + body.clientHeight +
                            ', scale=' + state.stageScale.toFixed(3) +
                            ', fit=' + state.contentFitScale.toFixed(3) +
                            ', compactShell=' + compactShellRatio.toFixed(3);
                        var baselineCompactScale = state.stageScale;
                        host.setViewport('1920x1080');
                        return api.waitFor(function() {
                            var fullscreened = currentState();
                            return fullscreened && fullscreened.activePageId === 'base' && !fullscreened.compactMode && fullscreened.stageScale > baselineCompactScale ? fullscreened : null;
                        }, 1500, 'grow to fullscreen layout').then(function(fullscreened) {
                            api.assert(fullscreened.contentFitScale >= 1.02, 'fullscreen layout should restore roomy content fit');
                            host.setViewport('1024x576');
                            return api.waitFor(function() {
                                var downshifted = currentState();
                                var refreshedBody = document.querySelector('.map-panel-body');
                                var refreshedShell = document.getElementById('map-stage-shell');
                                if (!downshifted || downshifted.activePageId !== 'base' || !downshifted.compactMode || !refreshedBody || !refreshedShell) {
                                    return null;
                                }
                                var shellRatio = refreshedShell.clientHeight / refreshedBody.clientHeight;
                                return downshifted.stageScale >= baselineCompactScale * 0.97 && shellRatio >= compactShellRatio * 0.95
                                    ? { state: downshifted, shellRatio: shellRatio }
                                    : null;
                            }, 1500, 'return to compact layout').then(function(result) {
                                api.assert(result.state.contentFitScale >= 1, 'compact recovery should keep content fit active');
                                api.assert(result.state.contentCoverageY >= 0.74, 'compact recovery should keep vertical content coverage');
                                return compactDetail +
                                    ', fullScale=' + fullscreened.stageScale.toFixed(3) +
                                    ', returnScale=' + result.state.stageScale.toFixed(3) +
                                    ', returnShell=' + result.shellRatio.toFixed(3);
                            });
                        });
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
                title: 'current location feedback retargets across page snapshot jumps',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'faction', currentHotspotId: 'firing_range' }).then(function(state) {
                        var currentHotspot = document.querySelector('.map-hotspot.is-current');
                        api.assert(!!state.currentHotspotId, 'snapshot should expose currentHotspotId');
                        api.assert(state.canvasLastDrawSummary.markerCount > 0, 'current location marker missing from canvas');
                        api.assert(!!currentHotspot, 'current hotspot missing active state');
                        api.assert(currentHotspot.getAttribute('data-hotspot-id') === state.currentHotspotId, 'stage current hotspot mismatch');
                        api.assertEqual(state.currentHotspotId, 'firing_range', 'initial current hotspot should be firing_range');
                        host.setState({ defaultPageId: 'base', currentHotspotId: 'base_lobby' });
                        host.pushSnapshot('refresh');
                        return api.waitFor(function() {
                            var refreshed = currentState();
                            return refreshed && refreshed.activePageId === 'base' && refreshed.currentHotspotId === 'base_lobby' && isCanvasCurrent(refreshed) ? refreshed : null;
                        }, 1500, 'cross-page current hotspot refresh').then(function(refreshed) {
                            var refreshedCurrentHotspot = document.querySelector('.map-hotspot.is-current');
                            api.assert(refreshed.canvasLastDrawSummary.markerCount > 0, 'refreshed current marker missing from canvas');
                            api.assert(!!refreshedCurrentHotspot, 'refreshed current hotspot missing');
                            api.assertEqual(refreshedCurrentHotspot.getAttribute('data-hotspot-id'), 'base_lobby', 'current hotspot should move to base_lobby');
                            api.assert(getPageTab('base').classList.contains('is-active'), 'base tab should become active after cross-page refresh');
                            return 'current=firing_range->' + refreshed.currentHotspotId;
                        });
                    });
                }
            },
            {
                id: 'map-ui9',
                title: 'locked groups stay spoiler-safe: locked hotspot hidden, hint still surfaces',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'school', lockedGroups: ['schoolInside'] }).then(function(state) {
                        var hotspot = document.querySelector('.map-hotspot[data-hotspot-id="school_dormitory"]');
                        api.assert(state.lockedHotspotIds.indexOf('school_dormitory') >= 0, 'school dormitory should be locked');
                        // 剧透防护: 锁定 hotspot 整体不渲染 (无按钮 / 无轮廓 / 无可达标签)
                        api.assert(!hotspot, 'locked hotspot must not render (spoiler protection)');
                        // 未开放原因仍通过 canvas 上的 flash hint 表达, 玩家可感知
                        api.assert(state.canvasLastDrawSummary.flashHintCount > 0, 'locked filter hint missing from canvas');
                        return 'lockedHotspotHidden flashHints=' + state.canvasLastDrawSummary.flashHintCount;
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
                                    return state && state.activePageId === pageId && isCanvasCurrent(state) ? state : null;
                                }, 1500, 'switch to ' + pageId).then(function(state) {
                                    var visibleSlots = getVisibleStaticAvatarSlots(pageId, state.activeFilterId);
                                    var page = MapPanelData.getPage(pageId);
                                    api.assert(state.canvasLastDrawSummary.staticAvatarCount === visibleSlots.length, pageId + ' canvas static avatar count mismatch');
                                    if (typeof MapAvatarSourceData !== 'undefined' && MapAvatarSourceData && MapAvatarSourceData.getByAssetUrl) {
                                        visibleSlots.forEach(function(slot) {
                                            var sourceSlot = MapAvatarSourceData.getByAssetUrl(slot.assetUrl);
                                            var expectedRect;
                                            api.assert(!!sourceSlot, pageId + ' missing avatar source meta for ' + slot.id);
                                            api.assert(!!(sourceSlot && sourceSlot.size && sourceSlot.hotspotId), pageId + ' avatar missing source schema for ' + slot.id);
                                            var ownerHotspot = MapPanelData.findHotspot(pageId, sourceSlot.hotspotId);
                                            api.assert(!!(ownerHotspot && ownerHotspot.rect), pageId + ' avatar owner hotspot missing for ' + slot.id);
                                            expectedRect = {
                                                x: ownerHotspot.rect.x + sourceSlot.relX,
                                                y: ownerHotspot.rect.y + sourceSlot.relY,
                                                w: sourceSlot.size.w,
                                                h: sourceSlot.size.h
                                            };
                                            api.assert(expectedRect.x >= 0 && expectedRect.x <= page.width, pageId + ' avatar left outside page for ' + slot.id);
                                            api.assert(expectedRect.y >= 0 && expectedRect.y <= page.height, pageId + ' avatar top outside page for ' + slot.id);
                                            api.assert(expectedRect.w > 0 && expectedRect.h > 0, pageId + ' avatar size invalid for ' + slot.id);
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
            },
            {
                id: 'map-ui12',
                title: 'task npc ring anchors to + encircles dynamic roommate avatar',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'school', roommateGender: 'female' }).then(function() {
                        var page = MapPanelData.getPage('school');
                        var slot = null;
                        var dyn = page.dynamicAvatars || [];
                        for (var i = 0; i < dyn.length; i += 1) {
                            if (dyn[i].id === 'roommate') { slot = dyn[i]; break; }
                        }
                        api.assert(!!slot, 'school page missing roommate dynamic slot');

                        clickByHitTest(api, getFilterButton('all'), 'school all filter');
                        return api.waitFor(function() {
                            var s = currentState();
                            return s && s.activeFilterId === 'all' && isCanvasCurrent(s) ? s : null;
                        }, 1500, 'switch to school all').then(function() {
                            var snapshot = host.buildSnapshot();
                            snapshot.markers = (snapshot.markers || []).concat([{
                                id: 'task_npc_室友',
                                kind: 'taskNpc',
                                npcName: '室友',
                                pageId: 'school',
                                hotspotId: 'school_dormitory',
                                point: { x: 130.3, y: 347.3 }
                            }]);
                            snapshot.defaultPageId = 'school';
                            MapPanel._debugApplySnapshot(snapshot);

                            return api.waitFor(function() {
                                var s = currentState();
                                return s && isCanvasCurrent(s) && s.canvasLastDrawSummary && s.canvasLastDrawSummary.taskRingCount > 0 ? s : null;
                            }, 1500, 'task ring appears').then(function(state) {
                                var hotspot = MapPanelData.findHotspot('school', slot.hotspotId);
                                api.assert(!!(hotspot && hotspot.rect), 'school_dormitory hotspot missing rect');
                                var slotX = hotspot.rect.x + slot.relX;
                                var slotY = hotspot.rect.y + slot.relY;
                                var expectedCx = slotX + slot.w / 2;
                                var expectedCy = slotY + slot.h / 2;
                                var expectedAvR = Math.max(slot.w, slot.h) / 2;
                                api.assert(state.canvasLastDrawSummary.taskRingCount === 1, 'canvas should render one task ring');
                                // 无头 harness 验证锚点 + 套头像半径: ring.point 必须命中室友头像中心,
                                // avatarRadius 必须 = 头像半径 (否则说明 npc-key 没匹配上, 回退到了 marker.point)
                                var ring = (state.taskRings || [])[0];
                                api.assert(!!ring, 'debug state should expose the task ring entry');
                                api.assert(Math.abs(ring.point.x - expectedCx) < 0.5,
                                    'ring anchor x should match roommate avatar center (got ' + ring.point.x.toFixed(2) + ', want ' + expectedCx.toFixed(2) + ')');
                                api.assert(Math.abs(ring.point.y - expectedCy) < 0.5,
                                    'ring anchor y should match roommate avatar center (got ' + ring.point.y.toFixed(2) + ', want ' + expectedCy.toFixed(2) + ')');
                                api.assert(Math.abs(ring.avatarRadius - expectedAvR) < 0.5,
                                    'ring should carry roommate avatar radius for encircle sizing (got ' + ring.avatarRadius.toFixed(2) + ', want ' + expectedAvR.toFixed(2) + ')');
                                // 层级: 任务环画布须低于 hotspot/标签层 (否则环盖住"前往选关"卡片), feedback 仍高于标签
                                var ringCanvas = document.getElementById('map-stage-canvas-ring');
                                var fitLayer = document.getElementById('map-stage-content-fit');
                                var fgCanvas = document.getElementById('map-stage-canvas-fg');
                                api.assert(!!ringCanvas, 'task ring canvas layer must exist');
                                var zRing = parseInt(window.getComputedStyle(ringCanvas).zIndex || '0', 10);
                                var zFit = parseInt(window.getComputedStyle(fitLayer).zIndex || '0', 10);
                                var zFg = parseInt(window.getComputedStyle(fgCanvas).zIndex || '0', 10);
                                api.assert(zRing < zFit, 'task ring layer must sit below hotspot/label layer (ring z=' + zRing + ', content-fit z=' + zFit + ')');
                                api.assert(zFg > zFit, 'feedback layer must stay above hotspot/label layer (fg z=' + zFg + ', content-fit z=' + zFit + ')');
                                return 'ringAnchor=' + expectedCx.toFixed(1) + '/' + expectedCy.toFixed(1) +
                                    ' encircleR=' + (expectedAvR + 5).toFixed(1) + ' z(ring/fit/fg)=' + zRing + '/' + zFit + '/' + zFg;
                            });
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
                        var beforeRevision = (currentState() && currentState().canvasLastRevision) || 0;
                        btn.click();
                        btn.click();
                        btn.click();

                        var afterCount = host.getMessages().filter(function(m) { return m && m.cmd === 'navigate'; }).length;
                        api.assert(afterCount - beforeCount === 1, 'expected exactly 1 navigate, got ' + (afterCount - beforeCount));
                        api.assert(btn.disabled === true, 'busy hotspot should be physically disabled');

                        host.setState({ failNavigate: false });
                        return api.waitFor(function() {
                            var s = currentState();
                            return s && s.canvasLastRevision > beforeRevision ? s : null;
                        }, 1500, 'busy canvas redraw').then(function(state) {
                            return 'navigateCount=' + (afterCount - beforeCount) + ' canvasRevision=' + state.canvasLastRevision;
                        });
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

                            // 剧透防护: 禁用 hotspot 整体不渲染, 不可点 (#1)
                            var disabledHs = document.querySelector('.map-hotspot[data-hotspot-id="base_lobby"]');
                            api.assert(!disabledHs, 'disabled hotspot must not render (spoiler protection)');

                            api.assert(!document.querySelector('.map-scene-chip'), 'scene chip strip removed; right rail owns filter/floor navigation now');
                            api.assert(!document.querySelector('.map-scene-strip'), 'scene chip strip container should not be in DOM');

                            // 单次触发断言: overlay click 代理 + 面板 playCue 不可同时响
                            var BA = window.BootstrapAudio;
                            api.assert(!!BA && typeof BA._resetCounts === 'function', 'harness BootstrapAudio counter stub required');

                            // 1) 启用 hotspot click → 只响一次 Transition (面板 requestNavigate 已不再直接播 cue)
                            BA._resetCounts();
                            enabledHs.click();
                            api.assertEqual(BA._counts.Transition || 0, 1, 'enabled hotspot click should fire Transition exactly once');
                            api.assertEqual(BA._counts.Error || 0, 0, 'enabled hotspot click should not fire Error');

                            // 2) 关闭按钮 click → 只响一次 Cancel (finishClose 不再直播 cue)
                            BA._resetCounts();
                            document.querySelector('.map-panel-close-btn').click();
                            api.assertEqual(BA._counts.Cancel || 0, 1, 'close btn click should fire Cancel exactly once');

                            return 'cues=ok single-fire=ok spoiler-safe=ok';
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
                id: 'map-ui16',
                title: 'locked filter stays spoiler-safe: locked filter button not rendered',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'school', lockedGroups: ['schoolInside'] }).then(function() {
                        // 剧透防护: 锁定的 group-mapped filter 整个按钮不渲染 (#2)
                        var lockedBtn = getFilterButton('inside');
                        api.assert(!lockedBtn, 'locked filter button must not render (spoiler protection)');
                        // 解锁的 / meta filter 仍渲染, 且没有任何已渲染 filter 处于 locked 态
                        var visibleFilters = document.querySelectorAll('.map-filter-hotspot');
                        api.assert(visibleFilters.length > 0, 'unlocked filters should still render');
                        for (var i = 0; i < visibleFilters.length; i++) {
                            api.assert(!visibleFilters[i].classList.contains('is-locked'),
                                'no rendered filter should be in locked state: ' + visibleFilters[i].getAttribute('data-filter-id'));
                        }
                        return 'lockedFilterHidden visibleFilters=' + visibleFilters.length;
                    });
                }
            },
            {
                id: 'map-ui17',
                title: 'faction filter switch drives data-active-filter + canvas filter state',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'faction' }).then(function(state) {
                        var stage = document.getElementById('map-stage-frame');
                        api.assert(!!stage, 'stage frame must exist');
                        api.assertEqual(stage.getAttribute('data-page-id'), 'faction', 'stage data-page-id should be faction');
                        api.assertEqual(stage.getAttribute('data-active-filter'), state.activeFilterId, 'stage data-active-filter should match initial filter');
                        api.assert(state.renderer === 'canvas', 'map stage should use canvas renderer');

                        // 切换到 blackiron — 应改写 data-active-filter 并触发 canvas redraw
                        var beforeRevision = state.canvasLastRevision || 0;
                        clickByHitTest(api, getFilterButton('blackiron'), 'blackiron filter');
                        return api.waitFor(function() {
                            var s = currentState();
                            return s && s.activeFilterId === 'blackiron' && s.canvasLastRevision > beforeRevision ? s : null;
                        }, 1500, 'switch to blackiron').then(function() {
                            var blackironState = currentState();
                            api.assertEqual(stage.getAttribute('data-active-filter'), 'blackiron', 'stage attr follows blackiron');
                            api.assertEqual(blackironState.canvasLastDrawSummary.filterId, 'blackiron', 'canvas filter summary follows blackiron');

                            // 再切回 warlord — 再次触发 canvas redraw
                            beforeRevision = blackironState.canvasLastRevision || 0;
                            clickByHitTest(api, getFilterButton('warlord'), 'warlord filter');
                            return api.waitFor(function() {
                                var s = currentState();
                                return s && s.activeFilterId === 'warlord' && s.canvasLastRevision > beforeRevision ? s : null;
                            }, 1500, 'switch to warlord').then(function() {
                                var warlordState = currentState();
                                api.assertEqual(stage.getAttribute('data-active-filter'), 'warlord', 'stage attr follows warlord');
                                api.assertEqual(warlordState.canvasLastDrawSummary.filterId, 'warlord', 'canvas filter summary follows warlord');
                                return 'activeFilter=warlord canvasRevision=' + warlordState.canvasLastRevision;
                            });
                        });
                    });
                }
            },
            {
                id: 'map-ui18',
                title: 'defense restricted filter toggles canvas anomaly state',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'defense' }).then(function() {
                        var initial = currentState();
                        api.assert(!initial.canvasLastDrawSummary.anomalyActive, 'anomaly must be inactive before restricted filter');

                        clickByHitTest(api, getFilterButton('restricted'), 'restricted filter');
                        return api.waitFor(function() {
                            var s = currentState();
                            return s && s.activeFilterId === 'restricted' && isCanvasCurrent(s) ? s : null;
                        }, 1500, 'switch to restricted').then(function() {
                            var restrictedState = currentState();
                            api.assert(restrictedState.canvasLastDrawSummary.anomalyActive, 'canvas anomaly should activate when restricted filter selected');

                            // 切回 first_line — 异常层 deactivate
                            clickByHitTest(api, getFilterButton('first_line'), 'first_line filter');
                            return api.waitFor(function() {
                                var s = currentState();
                                return s && s.activeFilterId === 'first_line' && isCanvasCurrent(s) ? s : null;
                            }, 1500, 'switch to first_line').then(function() {
                                api.assert(!currentState().canvasLastDrawSummary.anomalyActive, 'canvas anomaly should deactivate when leaving restricted filter');
                                return 'anomaly toggle ok';
                            });
                        });
                    });
                }
            },
            {
                id: 'map-ui19',
                title: 'rail accordion: active non-meta filter expands scene sub-list, clicks nav via hotspot path',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'faction' }).then(function() {
                        // default filter is 'all' (meta) — 不应展开
                        api.assert(!document.querySelector('.map-rail-scene-list'), 'meta filter (all) must NOT render scene sub-list');

                        // 切到 warlord — 应展开 3 个子项 (warlord_base / warlord_tent / firing_range)
                        clickByHitTest(api, getFilterButton('warlord'), 'warlord filter');
                        return api.waitFor(function() {
                            var s = currentState();
                            return s && s.activeFilterId === 'warlord' ? s : null;
                        }, 1500, 'switch to warlord').then(function() {
                            var list = document.querySelector('.map-rail-scene-list[data-filter-id="warlord"]');
                            api.assert(!!list, 'warlord filter should expand scene sub-list');
                            var items = list.querySelectorAll('.map-rail-scene-item');
                            api.assertEqual(items.length, 3, 'warlord has 3 hotspots → 3 sub-items');

                            // 验证 hotspotId + 文字 label 对齐数据
                            var firstItem = list.querySelector('.map-rail-scene-item[data-hotspot-id="warlord_base"]');
                            api.assert(!!firstItem, 'warlord_base sub-item must exist');
                            api.assert(firstItem.textContent.indexOf('军阀基地') >= 0, 'warlord_base label should be "军阀基地"');
                            api.assertEqual(firstItem.getAttribute('data-audio-cue'), 'transition', 'enabled sub-item cue = transition');

                            // 点击 sub-item = 触发 navigate (复用 requestNavigate 路径) 且 busy 时物理 disabled
                            host.setState({ failNavigate: true });
                            var beforeNavCount = host.getMessages().filter(function(m) { return m && m.cmd === 'navigate'; }).length;
                            firstItem.click();
                            api.assert(firstItem.classList.contains('is-busy'), 'sub-item should enter busy state immediately after click');
                            api.assertEqual(firstItem.disabled, true, 'sub-item should be physically disabled while busy');
                            var afterNavCount = host.getMessages().filter(function(m) { return m && m.cmd === 'navigate'; }).length;
                            api.assertEqual(afterNavCount - beforeNavCount, 1, 'sub-item click should emit exactly 1 navigate');
                            var lastMsg = host.getMessages()[host.getMessages().length - 1];
                            api.assertEqual(lastMsg.targetId, 'warlord_base', 'navigate targetId should match sub-item hotspot');
                            return api.waitFor(function() {
                                return !firstItem.disabled;
                            }, 1500, 'sub-item busy reset').then(function() {
                                host.setState({ failNavigate: false });
                                clickByHitTest(api, getFilterButton('rock'), 'rock filter');

                                // 切到 rock — 子列表应重建为 rock 的 2 个场景
                                clickByHitTest(api, getFilterButton('rock'), 'rock filter');
                                return api.waitFor(function() {
                                    var s = currentState();
                                    return s && s.activeFilterId === 'rock' ? s : null;
                                }, 1500, 'switch to rock').then(function() {
                                    api.assert(!document.querySelector('.map-rail-scene-list[data-filter-id="warlord"]'), 'warlord sub-list should collapse when leaving warlord');
                                    var rockList = document.querySelector('.map-rail-scene-list[data-filter-id="rock"]');
                                    api.assert(!!rockList, 'rock filter should expand its sub-list');
                                    api.assertEqual(rockList.querySelectorAll('.map-rail-scene-item').length, 2, 'rock has 2 hotspots → 2 sub-items');

                                    // 切到 all (meta) — 子列表应完全消失
                                    clickByHitTest(api, getFilterButton('all'), 'all filter');
                                    return api.waitFor(function() {
                                        var s = currentState();
                                        return s && s.activeFilterId === 'all' ? s : null;
                                    }, 1500, 'switch to all').then(function() {
                                        api.assert(!document.querySelector('.map-rail-scene-list'), 'meta filter (all) must NOT render sub-list');
                                        return 'subList expand/collapse ok busy=ok';
                                    });
                                });
                            });
                        });
                    });
                }
            },
            {
                id: 'map-ui20',
                title: 'rail sub-item: disabled hotspot click pushes locked reason toast, no navigate',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'base', disabledIds: ['armory'] }).then(function() {
                        // 切到 basement1 filter — armory 在其中但 disabled
                        clickByHitTest(api, getFilterButton('basement1'), 'basement1 filter');
                        return api.waitFor(function() {
                            var s = currentState();
                            return s && s.activeFilterId === 'basement1' ? s : null;
                        }, 1500, 'switch to basement1').then(function() {
                            var disabledItem = document.querySelector('.map-rail-scene-item[data-hotspot-id="armory"]');
                            api.assert(!!disabledItem, 'armory sub-item must exist');
                            api.assert(disabledItem.classList.contains('is-disabled'), 'armory sub-item should render disabled');
                            api.assertEqual(disabledItem.getAttribute('data-audio-cue'), 'error', 'disabled sub-item cue = error');

                            var toastBefore = (window.Toast && window.Toast.messages || []).length;
                            var beforeNavCount = host.getMessages().filter(function(m) { return m && m.cmd === 'navigate'; }).length;
                            disabledItem.click();
                            var afterNavCount = host.getMessages().filter(function(m) { return m && m.cmd === 'navigate'; }).length;
                            api.assertEqual(afterNavCount - beforeNavCount, 0, 'disabled sub-item click must NOT emit navigate');
                            api.assert((window.Toast && window.Toast.messages || []).length > toastBefore, 'disabled sub-item click should push locked reason toast');
                            return 'disabled sub-item click blocked';
                        });
                    });
                }
            },
            {
                id: 'map-ui21',
                title: 'filter fit presets expand sparse subsets without losing stage containment',
                run: function() {
                    // Fit floors follow MapFitPresets source-aware caps; capped PNG composites should not be forced past their clarity budget.
                    var probes = [
                        { pageId: 'base', filterId: 'roof', presetId: 'base:roof', minFitScale: 1.68, minX: 0.75, minY: 0.46 },
                        { pageId: 'base', filterId: 'first_floor', presetId: 'base:*', minFitScale: 1.02, minX: 0.88, minY: 0.38 },
                        { pageId: 'base', filterId: 'basement1', presetId: 'base:basement1', minFitScale: 1.68, minX: 0.54, minY: 0.43 },
                        { pageId: 'faction', filterId: 'rock', presetId: 'faction:rock', minFitScale: 1.14, minX: 0.30, minY: 0.48 },
                        { pageId: 'defense', filterId: 'restricted', presetId: 'defense:restricted', minFitScale: 1.14, minX: 0.30, minY: 0.43 },
                        { pageId: 'school', filterId: 'outside', presetId: 'school:outside', minFitScale: 1.0, minX: 0.23, minY: 0.17 }
                    ];
                    var details = [];

                    function activateProbe(probe) {
                        var state = currentState();
                        var flow = Promise.resolve();
                        function matchesProbe(candidate) {
                            return candidate &&
                                candidate.activePageId === probe.pageId &&
                                candidate.activeFilterId === probe.filterId &&
                                candidate.activeFitPresetId === probe.presetId;
                        }

                        if (!state || state.activePageId !== probe.pageId) {
                            flow = flow.then(function() {
                                var tab = getPageTab(probe.pageId);
                                api.assert(!!tab, probe.pageId + ' tab missing');
                                tab.click();
                                return api.waitFor(function() {
                                    var switched = currentState();
                                    return switched && switched.activePageId === probe.pageId ? switched : null;
                                }, 1500, 'switch to ' + probe.pageId);
                            });
                        }

                        return flow.then(function() {
                            if (matchesProbe(currentState())) {
                                return currentState();
                            }
                            var filterButton = getFilterButton(probe.filterId);
                            api.assert(!!filterButton, probe.filterId + ' filter missing');
                            filterButton.click();
                            if (window.MapPanel && typeof MapPanel._debugSyncLayout === 'function') {
                                MapPanel._debugSyncLayout('qa_filter_fit_probe');
                            }
                            return api.waitFor(function() {
                                var switched = currentState();
                                return matchesProbe(switched) ? switched : null;
                            }, 1500, 'switch to ' + probe.pageId + '/' + probe.filterId);
                        });
                    }

                    return bootMap(api, host, { defaultPageId: 'base', currentHotspotId: '' }).then(function() {
                        var flow = Promise.resolve();
                        probes.forEach(function(probe) {
                            flow = flow.then(function() {
                                return activateProbe(probe).then(function(state) {
                                    var shellRect = document.getElementById('map-stage-shell').getBoundingClientRect();
                                    var stageRect = document.getElementById('map-stage-frame').getBoundingClientRect();
                                    api.assertEqual(state.activeFitPresetId, probe.presetId, probe.pageId + '/' + probe.filterId + ' preset mismatch');
                                    api.assert(state.contentFitScale >= probe.minFitScale, probe.pageId + '/' + probe.filterId + ' fit scale too low');
                                    api.assert(state.contentCoverageX >= probe.minX, probe.pageId + '/' + probe.filterId + ' horizontal coverage too low');
                                    api.assert(state.contentCoverageY >= probe.minY, probe.pageId + '/' + probe.filterId + ' vertical coverage too low');
                                    api.assert(stageRect.left >= shellRect.left - 1, probe.pageId + '/' + probe.filterId + ' stage should stay inside shell (left)');
                                    api.assert(stageRect.right <= shellRect.right + 1, probe.pageId + '/' + probe.filterId + ' stage should stay inside shell (right)');
                                    api.assert(stageRect.top >= shellRect.top - 1, probe.pageId + '/' + probe.filterId + ' stage should stay inside shell (top)');
                                    api.assert(stageRect.bottom <= shellRect.bottom + 1, probe.pageId + '/' + probe.filterId + ' stage should stay inside shell (bottom)');
                                    api.assert(!!state.contentFitPreset, probe.pageId + '/' + probe.filterId + ' should expose contentFitPreset debug info');
                                    details.push(
                                        probe.pageId + '/' + probe.filterId +
                                        '=' + state.activeFitPresetId +
                                        ' ' + state.contentCoverageX.toFixed(2) + '/' + state.contentCoverageY.toFixed(2) +
                                        ' pad=' + state.contentFitPadX.toFixed(2) + '/' + state.contentFitPadY.toFixed(2)
                                    );
                                });
                            });
                        });

                        return flow.then(function() {
                            return details.join(' | ');
                        });
                    });
                }
            },
            {
                id: 'map-ui22',
                title: 'school avatar ownership stays aligned with intended scene buckets',
                run: function() {
                    var expectedOwnership = {
                        pe_teacher_avatar: 'university_interior',
                        fengyouquan_avatar: 'kendo_club',
                        vanshuther_avatar: 'workshop'
                    };
                    var reviewOnly = {
                        science_prof_avatar: true,
                        arts_teacher_avatar: true
                    };

                    return bootMap(api, host, { defaultPageId: 'school' }).then(function() {
                        var audit = buildStaticAvatarOwnershipAudit('school');
                        var lookup = {};
                        var clearMismatches;
                        var reviewCandidates;
                        var id;

                        audit.forEach(function(item) {
                            lookup[item.avatarId] = item;
                        });

                        for (id in expectedOwnership) {
                            var slot = lookup[id];
                            api.assert(!!slot, 'school ownership audit missing ' + id);
                            api.assertEqual(slot.assignedHotspotId, expectedOwnership[id], id + ' hotspot ownership mismatch');
                            api.assert(slot.assignedContains, id + ' center should stay inside assigned scene bucket');
                        }
                        api.assert(currentState().canvasLastDrawSummary.staticAvatarCount > 0, 'school canvas should draw static avatars');

                        clearMismatches = audit.filter(function(item) {
                            return item.clearMismatchHotspotId && !reviewOnly[item.avatarId];
                        });
                        api.assert(clearMismatches.length === 0, 'unexpected clear school avatar ownership mismatch: ' + clearMismatches.map(function(item) {
                            return item.avatarId + '->' + item.clearMismatchHotspotId;
                        }).join(','));

                        reviewCandidates = audit.filter(function(item) {
                            return item.clearMismatchHotspotId || item.ambiguousMismatchHotspotId;
                        }).map(function(item) {
                            return item.avatarId + '=' + item.assignedHotspotId + '->' + (item.clearMismatchHotspotId || item.ambiguousMismatchHotspotId);
                        });

                        return 'fixed=' + Object.keys(expectedOwnership).map(function(avatarId) {
                            return avatarId + '->' + lookup[avatarId].assignedHotspotId;
                        }).join(',') +
                            (reviewCandidates.length ? ' review=' + reviewCandidates.join(',') : '');
                    });
                }
            },
            {
                id: 'map-ui23',
                title: 'hotspot corner labels stay attached under content-fit and above avatar chrome',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'defense' }).then(function() {
                        clickByHitTest(api, getFilterButton('first_line'), 'first_line filter');
                        return api.waitFor(function() {
                            var state = currentState();
                            return state && state.activeFilterId === 'first_line' ? state : null;
                        }, 1500, 'switch to first_line').then(function() {
                            var hotspotBtn = document.querySelector('.map-hotspot[data-hotspot-id="first_defense"]');
                            var overlayLabel;
                            var overlayStyle;
                            var labelLayer = document.getElementById('map-hotspot-label-layer');
                            var hotspotRect;
                            var labelRect;
                            api.assert(!!hotspotBtn, 'first_defense hotspot missing');
                            api.assert(!hotspotBtn.querySelector('.map-hotspot-label'), 'hotspot label should no longer live inside hotspot button');

                            hotspotBtn.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));

                            overlayLabel = getHotspotOverlayLabel('first_defense');
                            api.assert(!!overlayLabel, 'first_defense overlay label missing');
                            overlayStyle = window.getComputedStyle(overlayLabel);
                            hotspotRect = hotspotBtn.getBoundingClientRect();
                            labelRect = overlayLabel.getBoundingClientRect();
                            api.assert(!!labelLayer && labelLayer.contains(overlayLabel), 'overlay label should render inside content-fit label layer');
                            api.assert(parseInt(window.getComputedStyle(labelLayer).zIndex || '0', 10) > 0, 'label layer should stay above canvas stage');
                            api.assert(overlayLabel.classList.contains('is-hover'), 'overlay label should track hotspot hover state');
                            api.assert(parseFloat(overlayStyle.opacity || '0') > 0.9, 'overlay label should be visible on hover');
                            api.assert(labelRect.left >= hotspotRect.left - 6, 'overlay label should not drift left of hotspot');
                            api.assert(labelRect.left <= hotspotRect.right + 6, 'overlay label should stay horizontally attached to hotspot');
                            api.assert(labelRect.bottom >= hotspotRect.top - 6, 'overlay label anchor should stay inside hotspot vertical band');
                            api.assert(labelRect.bottom <= hotspotRect.bottom + 6, 'overlay label should not drift below hotspot');
                            // label 高度约束: 不得占 hotspot 高度的一半以上, 否则矮 hotspot 会被 label 盖住上半; 给 2px 容差防 subpixel rounding
                            api.assert(labelRect.height <= (hotspotRect.height * 0.5) + 2,
                                'overlay label height (' + Math.round(labelRect.height) + 'px) should not exceed 50% of hotspot height (' + Math.round(hotspotRect.height) + 'px)');
                            return 'label=' + overlayLabel.textContent +
                                ' z=' + window.getComputedStyle(labelLayer).zIndex +
                                ' anchor=' + Math.round(labelRect.left - hotspotRect.left) + ',' + Math.round(labelRect.bottom - hotspotRect.top) +
                                ' lh/hh=' + Math.round(labelRect.height) + '/' + Math.round(hotspotRect.height);
                        });
                    });
                }
            },
            {
                id: 'map-ui24',
                title: 'stage-select shortcut opens matching stage frame without replacing hotspot navigation',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'faction', currentHotspotId: 'rock_park' }).then(function() {
                        clickByHitTest(api, getFilterButton('rock'), 'rock filter');
                        return api.waitFor(function() {
                            var state = currentState();
                            return state && state.activeFilterId === 'rock' ? state : null;
                        }, 1500, 'switch to rock').then(function(state) {
                            api.assert(state.stageSelectHotspotIds.indexOf('rock_park') >= 0, 'rock_park should expose stage-select shortcut');
                            api.assert(state.stageSelectHotspotIds.indexOf('rock_rehearsal') < 0, 'rock_rehearsal should not expose stage-select shortcut');

                            var action = document.querySelector('.map-rail-stage-select-btn[data-hotspot-id="rock_park"]');
                            var missingAction = document.querySelector('.map-rail-stage-select-btn[data-hotspot-id="rock_rehearsal"]');
                            api.assert(!!action, 'rock_park stage-select action missing');
                            api.assert(!missingAction, 'rock_rehearsal should not render stage-select action');

                            var beforeNavCount = host.getMessages().filter(function(m) { return m && m.cmd === 'navigate'; }).length;
                            var beforeOpenCount = host.getMessages().filter(function(m) { return m && m.cmd === 'open_stage_select'; }).length;
                            clickByHitTest(api, action, 'rock_park stage-select action');
                            var afterNavCount = host.getMessages().filter(function(m) { return m && m.cmd === 'navigate'; }).length;
                            var openMessages = host.getMessages().filter(function(m) { return m && m.cmd === 'open_stage_select'; });
                            api.assertEqual(afterNavCount - beforeNavCount, 0, 'stage-select action must not emit navigate');
                            api.assertEqual(openMessages.length - beforeOpenCount, 1, 'stage-select action should emit one open_stage_select');
                            var msg = openMessages[openMessages.length - 1];
                            api.assertEqual(msg.targetId, 'rock_park', 'open_stage_select targetId');
                            api.assertEqual(msg.frameLabel, '基地车库', 'rock_park opens garage stage-select frame');
                            api.assertEqual(msg.returnFrameLabel, '地图-摇滚公园', 'return frame follows current map hotspot scene');
                            return api.waitFor(function() {
                                var s = currentState();
                                return s && !s.stageSelectBusyHotspotId ? s : null;
                            }, 1500, 'stage-select shortcut busy reset').then(function() {
                                return 'open_stage_select=' + msg.targetId + '->' + msg.frameLabel;
                            });
                        });
                    });
                }
            },
            {
                id: 'map-ui25',
                title: 'host-driven close stops the canvas RAF loop (no hidden-canvas leak)',
                run: function() {
                    function delay(ms) {
                        return new Promise(function(resolve) { setTimeout(resolve, ms); });
                    }
                    // 开图带 currentHotspot → 必有 currentLocation marker, fg 动画循环处于运行态
                    return bootMap(api, host, { defaultPageId: 'faction', currentHotspotId: 'firing_range' }).then(function() {
                        return waitForCanvasCurrent(api, 'pre-close canvas current');
                    }).then(function() {
                        var before = currentState() || {};
                        api.assert(before.canvasReady, 'canvas renderer should be ready before close');
                        api.assert(before.canvasStopped === false, 'renderer should be running before close');
                        var openFrames = before.canvasFrameCount || 0;
                        // 确认 RAF 循环确实在推进 (有 marker → needsAnimation true)
                        return delay(260).then(function() {
                            api.assert((currentState() || {}).canvasFrameCount > openFrames, 'RAF loop should advance while panel open');
                            // host 驱动关闭: 不点关闭按钮, 直接 Panels.close()
                            // (模拟 panel_cmd close / 切面板 / 选关交接 — 不走 finishClose)
                            api.assert(!!(window.Panels && window.Panels.close), 'Panels.close must be available');
                            window.Panels.close();
                            var container = document.getElementById('panel-container');
                            if (container) container.style.display = 'none';
                            // 等 onClose 异步兑现 + 循环排空
                            return delay(140).then(function() {
                                var atClose = currentState() || {};
                                api.assert(atClose.canvasStopped === true, 'renderer must be stopped after host-driven close');
                                var closeFrames = atClose.canvasFrameCount || 0;
                                // 修复前: 隐藏画布上 RAF 持续推进; 修复后: 应冻结
                                return delay(420).then(function() {
                                    var settled = currentState() || {};
                                    if (container) container.style.display = '';
                                    var leaked = (settled.canvasFrameCount || 0) - closeFrames;
                                    api.assert(leaked === 0, 'RAF loop must not advance after close (leaked ' + leaked + ' frames)');
                                    return 'stopped=' + settled.canvasStopped + ' framesLeakedAfterClose=' + leaked;
                                });
                            });
                        });
                    });
                }
            },
            {
                id: 'map-ui26',
                title: 'task badges aggregate scene → filter → page tab (unlocked hotspots only)',
                run: function() {
                    // base 永远解锁，所以 base_lobby + merc_bar 红点必现；
                    // faction warlord 组解锁 → firing_range 红点也现，filter 计数 1，page tab 计数 1。
                    // base page tab 应聚合两个 hotspot 计数 = 2。
                    return bootMap(api, host, {
                        defaultPageId: 'base',
                        taskNpcHotspots: ['base_lobby', 'merc_bar', 'firing_range']
                    }).then(function() {
                        var state = currentState();
                        api.assert(!!state && state.taskBadge, 'taskBadge must be exposed in debug state');

                        // 末端 hotspot 级
                        api.assert(state.taskBadge.byHotspot['base_lobby'] === true, 'base_lobby should be marked');
                        api.assert(state.taskBadge.byHotspot['merc_bar'] === true, 'merc_bar should be marked');
                        api.assert(state.taskBadge.byHotspot['firing_range'] === true, 'firing_range should be marked');

                        // page tab 聚合
                        api.assertEqual(state.taskBadge.byPage['base'], 2, 'base page should aggregate 2 quest hotspots');
                        api.assertEqual(state.taskBadge.byPage['faction'], 1, 'faction page should aggregate 1 quest hotspot');

                        // DOM 验证：base 当前激活页 → scene item 末端 dot 可见
                        var baseTabBadge = document.querySelector('.map-page-tab[data-page-id="base"] .map-page-tab-badge');
                        api.assert(!!baseTabBadge && baseTabBadge.textContent === '2', 'base tab badge should show "2"');
                        api.assert(baseTabBadge.offsetParent !== null, 'base tab badge should be visible');

                        var factionTabBadge = document.querySelector('.map-page-tab[data-page-id="faction"] .map-page-tab-badge');
                        api.assert(!!factionTabBadge && factionTabBadge.textContent === '1', 'faction tab badge should show "1"');

                        // base 没有 taskNpc 的 page（defense / school）— badge 应该隐藏
                        var defenseTabBadge = document.querySelector('.map-page-tab[data-page-id="defense"] .map-page-tab-badge');
                        api.assert(defenseTabBadge && defenseTabBadge.offsetParent === null, 'defense tab badge should be hidden');

                        // filter 聚合 + scene item 末端红点：切到包含 base_lobby 的非 meta filter，确保红点不是只停在 page tab。
                        var basePage = MapPanelData.getPage('base');
                        var lobbyFilter = (basePage.filters || []).filter(function(filter) {
                            return filter.id !== 'all' && filter.id !== 'hierarchy' && (filter.hotspotIds || []).indexOf('base_lobby') >= 0;
                        })[0];
                        api.assert(!!lobbyFilter, 'base_lobby non-meta filter should exist');
                        var lobbyFilterBtn = getFilterButton(lobbyFilter.id);
                        api.assert(!!lobbyFilterBtn, 'base_lobby filter button should render');
                        api.assert(lobbyFilterBtn.classList.contains('has-quest'), 'base_lobby filter should have has-quest class');
                        api.assert(!!lobbyFilterBtn.querySelector('.map-filter-hotspot-badge'), 'base_lobby filter should render task badge');
                        clickByHitTest(api, lobbyFilterBtn, 'base_lobby task filter');
                        return api.waitFor(function() {
                            var s = currentState();
                            return s && s.activeFilterId === lobbyFilter.id ? s : null;
                        }, 1500, 'switch to base_lobby filter').then(function() {
                        var lobbyItem = document.querySelector('.map-rail-scene-item[data-hotspot-id="base_lobby"]');
                            api.assert(!!lobbyItem, 'base_lobby scene item should render after filter opens');
                            api.assert(lobbyItem.classList.contains('has-quest'), 'base_lobby scene item should have has-quest class');
                            api.assert(!!lobbyItem.querySelector('.map-rail-scene-quest'), 'base_lobby scene item should render quest dot');

                        return 'byPage=' + JSON.stringify(state.taskBadge.byPage) +
                            ', byHotspotCount=' + Object.keys(state.taskBadge.byHotspot).length;
                        });
                    });
                }
            },
            {
                id: 'map-ui27',
                title: 'locked group hotspot does not propagate red dot (spoiler protection)',
                run: function() {
                    // warlord 组锁住 → firing_range 是 locked → 红点 marker 喂进来但应被完全过滤掉，
                    // 不允许任何层级（hotspot / filter / page）出现红点。
                    // 同时给一个 base_lobby（永解锁）作 sanity check 证明 pipeline 仍工作。
                    return bootMap(api, host, {
                        defaultPageId: 'base',
                        lockedGroups: ['warlord', 'rock', 'blackiron', 'fallen'],
                        taskNpcHotspots: ['firing_range', 'warlord_base', 'base_lobby']
                    }).then(function() {
                        var state = currentState();
                        api.assert(!!state && state.taskBadge, 'taskBadge must be exposed in debug state');

                        // sanity: base_lobby 仍然点亮
                        api.assert(state.taskBadge.byHotspot['base_lobby'] === true, 'base_lobby should still mark (unlocked)');
                        api.assertEqual(state.taskBadge.byPage['base'], 1, 'base page should still aggregate base_lobby');

                        // 关键：locked hotspots 必须被剔除
                        api.assert(!state.taskBadge.byHotspot['firing_range'], 'firing_range (locked) MUST NOT mark');
                        api.assert(!state.taskBadge.byHotspot['warlord_base'], 'warlord_base (locked) MUST NOT mark');

                        // faction page 整体不点亮（所有 warlord 子项都 locked）
                        api.assert(!state.taskBadge.byPage['faction'], 'faction page MUST NOT aggregate any locked hotspots');

                        // faction page tab badge 必须隐藏（offsetParent null = display:none）
                        var factionTabBadge = document.querySelector('.map-page-tab[data-page-id="faction"] .map-page-tab-badge');
                        api.assert(factionTabBadge && factionTabBadge.offsetParent === null, 'faction tab badge MUST be hidden when only locked hotspots have quests');

                        return 'baseQuestCount=' + state.taskBadge.byPage['base'] +
                            ', factionQuestCount=' + (state.taskBadge.byPage['faction'] || 0) +
                            ', lockedFiltered=ok';
                    });
                }
            },
            {
                id: 'map-ui28',
                title: 'task hotspot stage-select shortcut uses task affordance and opens matching frame',
                run: function() {
                    return bootMap(api, host, {
                        defaultPageId: 'faction',
                        currentHotspotId: 'rock_park',
                        taskNpcHotspots: ['rock_park']
                    }).then(function() {
                        clickByHitTest(api, getFilterButton('rock'), 'rock filter');
                        return api.waitFor(function() {
                            var state = currentState();
                            return state && state.activeFilterId === 'rock' ? state : null;
                        }, 1500, 'switch to rock').then(function(state) {
                            api.assert(state.taskBadge.byHotspot['rock_park'] === true, 'rock_park should be a task hotspot');
                            api.assert(state.taskStageSelectHotspotIds.indexOf('rock_park') >= 0, 'rock_park should be task stage-select hotspot');

                            var action = document.querySelector('.map-rail-stage-select-btn[data-hotspot-id="rock_park"]');
                            api.assert(!!action, 'rock_park task stage-select action missing');
                            api.assert(action.classList.contains('is-task'), 'rail stage-select action should use task class');
                            api.assert((action.textContent || '').indexOf('任务') >= 0, 'rail action label should mention task');

                            var overlayAction = document.querySelector('.map-hotspot-stage-select-btn[data-hotspot-id="rock_park"]');
                            api.assert(!!overlayAction, 'rock_park overlay stage-select action missing');
                            api.assert(overlayAction.classList.contains('is-task'), 'overlay action should use task class');

                            var beforeOpenCount = host.getMessages().filter(function(m) { return m && m.cmd === 'open_stage_select'; }).length;
                            clickByHitTest(api, action, 'rock_park task stage-select action');
                            var openMessages = host.getMessages().filter(function(m) { return m && m.cmd === 'open_stage_select'; });
                            api.assertEqual(openMessages.length - beforeOpenCount, 1, 'task stage-select action should emit one open_stage_select');
                            var msg = openMessages[openMessages.length - 1];
                            api.assertEqual(msg.targetId, 'rock_park', 'task open_stage_select targetId');
                            api.assertEqual(msg.frameLabel, '基地车库', 'task opens matching garage stage-select frame');
                            return 'taskOpenStageSelect=' + msg.targetId + '->' + msg.frameLabel;
                        });
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
        var ownershipAudit = {};
        MapPanelData.getPageOrder().forEach(function(pageId) {
            ownershipAudit[pageId] = buildStaticAvatarOwnershipAudit(pageId);
        });
        return {
            hostState: host.getState(),
            sentMessages: host.getMessages(),
            mapState: currentState(),
            avatarSrc: getAvatarSrc(),
            avatarOwnershipAudit: ownershipAudit,
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
