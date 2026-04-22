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
        var patch = { currentHotspotId: '' };
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

        return (page && page.staticAvatars ? page.staticAvatars : []).map(function(slot) {
            var center = {
                x: slot.x + (slot.w / 2),
                y: slot.y + (slot.h / 2)
            };
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
                            return s && s.activePageId === 'base' && s.stageScale > 1 ? s : null;
                        }, 1500, 'roomy layout ready').then(function(state) {
                            var closeBtn = document.querySelector('.map-panel-close-btn');
                            var schoolTab = getPageTab('school');
                            var firstSceneNode = document.querySelector('.map-scene-node');
                            var readabilityPlate = firstSceneNode ? window.getComputedStyle(firstSceneNode, '::before') : null;
                            assertHitTest(api, schoolTab, 'school tab');
                            assertHitTest(api, closeBtn, 'close button');
                            api.assertEqual(state.activePageId, 'base', 'default page');
                            api.assert(state.contentFitScale >= 1.02, 'roomy viewport should apply content fit scale');
                            api.assert(state.contentCoverageX >= 0.84, 'content should occupy most stage width');
                            api.assert(state.contentCoverageY >= 0.78, 'content should occupy most stage height');
                            api.assert(!!firstSceneNode, 'base page should render scene nodes');
                            api.assert(!!readabilityPlate && readabilityPlate.backgroundImage !== 'none', 'base scene readability plate missing');
                            api.assert(parseFloat(readabilityPlate.opacity || '0') >= 0.6, 'base scene readability plate should stay visible');
                            return 'page=' + state.activePageId +
                                ', stageScale=' + state.stageScale.toFixed(3) +
                                ', fit=' + state.contentFitScale.toFixed(3) +
                                ', coverage=' + state.contentCoverageX.toFixed(2) + '/' + state.contentCoverageY.toFixed(2) +
                                ', plate=' + (readabilityPlate ? readabilityPlate.opacity : '0');
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
                        var marker = document.querySelector('.map-feedback-marker');
                        var currentHotspot = document.querySelector('.map-hotspot.is-current');
                        api.assert(!!state.currentHotspotId, 'snapshot should expose currentHotspotId');
                        api.assert(!!marker, 'current location marker missing');
                        api.assert(!!currentHotspot, 'current hotspot missing active state');
                        api.assert(currentHotspot.getAttribute('data-hotspot-id') === state.currentHotspotId, 'stage current hotspot mismatch');
                        api.assert(!marker.querySelector('.map-feedback-marker-label'), 'current location marker should no longer render inline label (tips layer owns text)');
                        api.assertEqual(state.currentHotspotId, 'firing_range', 'initial current hotspot should be firing_range');
                        host.setState({ defaultPageId: 'base', currentHotspotId: 'base_lobby' });
                        host.pushSnapshot('refresh');
                        return api.waitFor(function() {
                            var refreshed = currentState();
                            return refreshed && refreshed.activePageId === 'base' && refreshed.currentHotspotId === 'base_lobby' ? refreshed : null;
                        }, 1500, 'cross-page current hotspot refresh').then(function(refreshed) {
                            var refreshedMarker = document.querySelector('.map-feedback-marker');
                            var refreshedCurrentHotspot = document.querySelector('.map-hotspot.is-current');
                            api.assert(!!refreshedMarker, 'refreshed current marker missing');
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

                            // 单次触发断言: overlay click 代理 + 面板 playCue 不可同时响
                            var BA = window.BootstrapAudio;
                            api.assert(!!BA && typeof BA._resetCounts === 'function', 'harness BootstrapAudio counter stub required');

                            // 1) 启用 hotspot click → 只响一次 Transition (面板 requestNavigate 已不再直接播 cue)
                            BA._resetCounts();
                            enabledHs.click();
                            api.assertEqual(BA._counts.Transition || 0, 1, 'enabled hotspot click should fire Transition exactly once');
                            api.assertEqual(BA._counts.Error || 0, 0, 'enabled hotspot click should not fire Error');

                            // 2) 禁用 hotspot click → 只响一次 Error, 依旧推 toast
                            var toastBefore = (window.Toast && window.Toast.messages || []).length;
                            BA._resetCounts();
                            disabledHs.click();
                            api.assertEqual(BA._counts.Error || 0, 1, 'disabled hotspot click should fire Error exactly once');
                            api.assertEqual(BA._counts.Transition || 0, 0, 'disabled hotspot click should not fire Transition');
                            api.assert((window.Toast && window.Toast.messages || []).length > toastBefore, 'disabled hotspot click should still push locked reason toast');

                            // 3) 关闭按钮 click → 只响一次 Cancel (finishClose 不再直播 cue)
                            BA._resetCounts();
                            document.querySelector('.map-panel-close-btn').click();
                            api.assertEqual(BA._counts.Cancel || 0, 1, 'close btn click should fire Cancel exactly once');

                            return 'cues=ok single-fire=ok';
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
                title: 'locked filter click keeps state and surfaces locked reason toast',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'school', lockedGroups: ['schoolInside'] }).then(function(state) {
                        var beforeFilterId = state.activeFilterId;
                        var lockedBtn = getFilterButton('inside');
                        api.assert(!!lockedBtn, 'inside filter button missing');
                        api.assert(lockedBtn.classList.contains('is-locked'), 'inside filter should render in locked state');
                        api.assert(lockedBtn.getAttribute('data-audio-cue') === 'error', 'locked filter cue should be error');

                        var BA = window.BootstrapAudio;
                        var toastBefore = (window.Toast && window.Toast.messages || []).length;
                        if (BA && BA._resetCounts) BA._resetCounts();

                        lockedBtn.click();

                        var after = currentState();
                        api.assertEqual(after.activeFilterId, beforeFilterId, 'locked filter click must not mutate activeFilterId');
                        api.assert((window.Toast && window.Toast.messages || []).length > toastBefore, 'locked filter click should push locked reason toast');
                        if (BA) {
                            api.assertEqual(BA._counts.Error || 0, 1, 'locked filter click should fire Error exactly once');
                            api.assertEqual(BA._counts.Select || 0, 0, 'locked filter click must not fire Select');
                        }
                        return 'lockedFilter=inside activeFilter=' + after.activeFilterId;
                    });
                }
            },
            {
                id: 'map-ui17',
                title: 'faction filter switch drives data-active-filter + filter-overlay attribute',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'faction' }).then(function(state) {
                        var stage = document.getElementById('map-stage-frame');
                        var overlay = document.getElementById('map-stage-filter-overlay');
                        api.assert(!!stage && !!overlay, 'stage frame + filter overlay must exist');
                        api.assertEqual(stage.getAttribute('data-page-id'), 'faction', 'stage data-page-id should be faction');
                        api.assertEqual(stage.getAttribute('data-active-filter'), state.activeFilterId, 'stage data-active-filter should match initial filter');
                        api.assertEqual(overlay.getAttribute('data-page-id'), 'faction', 'overlay data-page-id should be faction');

                        // 切换到 blackiron — 应改写 data-active-filter 并触发 retuning 过渡 class
                        clickByHitTest(api, getFilterButton('blackiron'), 'blackiron filter');
                        return api.waitFor(function() {
                            var s = currentState();
                            return s && s.activeFilterId === 'blackiron' ? s : null;
                        }, 1500, 'switch to blackiron').then(function() {
                            api.assertEqual(stage.getAttribute('data-active-filter'), 'blackiron', 'stage attr follows blackiron');
                            api.assertEqual(overlay.getAttribute('data-active-filter'), 'blackiron', 'overlay attr follows blackiron');
                            api.assert(stage.classList.contains('is-retuning'), 'filter switch should apply is-retuning transition class');

                            // 再切回 warlord — 再次触发 retuning
                            clickByHitTest(api, getFilterButton('warlord'), 'warlord filter');
                            return api.waitFor(function() {
                                var s = currentState();
                                return s && s.activeFilterId === 'warlord' ? s : null;
                            }, 1500, 'switch to warlord').then(function() {
                                api.assertEqual(stage.getAttribute('data-active-filter'), 'warlord', 'stage attr follows warlord');
                                api.assertEqual(overlay.getAttribute('data-active-filter'), 'warlord', 'overlay attr follows warlord');
                                return 'activeFilter=warlord retune=ok';
                            });
                        });
                    });
                }
            },
            {
                id: 'map-ui18',
                title: 'defense restricted filter toggles anomaly layer is-active',
                run: function() {
                    return bootMap(api, host, { defaultPageId: 'defense' }).then(function() {
                        var anomaly = document.getElementById('map-stage-anomaly');
                        api.assert(!!anomaly, 'anomaly layer node must exist');
                        api.assert(!anomaly.classList.contains('is-active'), 'anomaly must be inactive before restricted filter');

                        clickByHitTest(api, getFilterButton('restricted'), 'restricted filter');
                        return api.waitFor(function() {
                            var s = currentState();
                            return s && s.activeFilterId === 'restricted' ? s : null;
                        }, 1500, 'switch to restricted').then(function() {
                            api.assert(anomaly.classList.contains('is-active'), 'anomaly layer should activate when restricted filter selected');
                            var pulseNode = anomaly.querySelector('.map-stage-anomaly-pulse');
                            api.assert(!!pulseNode, 'anomaly pulse node must exist');
                            var pulseRect = pulseNode.getBoundingClientRect();
                            var stageRect = document.getElementById('map-stage-frame').getBoundingClientRect();
                            // 偏心: pulse 中心应落在舞台上半 + 右侧 (x>60%, y<40%)
                            var relX = (pulseRect.left + pulseRect.width / 2 - stageRect.left) / stageRect.width;
                            var relY = (pulseRect.top + pulseRect.height / 2 - stageRect.top) / stageRect.height;
                            api.assert(relX > 0.6 && relY < 0.4, 'anomaly pulse must be offset to upper-right (got x=' + relX.toFixed(2) + ' y=' + relY.toFixed(2) + ')');

                            // 切回 first_line — 异常层 deactivate
                            clickByHitTest(api, getFilterButton('first_line'), 'first_line filter');
                            return api.waitFor(function() {
                                var s = currentState();
                                return s && s.activeFilterId === 'first_line' ? s : null;
                            }, 1500, 'switch to first_line').then(function() {
                                api.assert(!anomaly.classList.contains('is-active'), 'anomaly should deactivate when leaving restricted filter');
                                return 'anomaly toggle ok relX=' + relX.toFixed(2) + ' relY=' + relY.toFixed(2);
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
                    var probes = [
                        { pageId: 'base', filterId: 'roof', presetId: 'base:roof', minFitScale: 1.68, minX: 0.75, minY: 0.46 },
                        { pageId: 'base', filterId: 'first_floor', presetId: 'base:*', minFitScale: 1.02, minX: 0.88, minY: 0.38 },
                        { pageId: 'base', filterId: 'basement1', presetId: 'base:basement1', minFitScale: 1.68, minX: 0.54, minY: 0.58 },
                        { pageId: 'faction', filterId: 'rock', presetId: 'faction:rock', minFitScale: 1.68, minX: 0.44, minY: 0.66 },
                        { pageId: 'defense', filterId: 'restricted', presetId: 'defense:restricted', minFitScale: 1.68, minX: 0.45, minY: 0.6 },
                        { pageId: 'school', filterId: 'outside', presetId: 'school:outside', minFitScale: 1.68, minX: 0.38, minY: 0.28 }
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
                            var avatarEl;
                            api.assert(!!slot, 'school ownership audit missing ' + id);
                            api.assertEqual(slot.assignedHotspotId, expectedOwnership[id], id + ' hotspot ownership mismatch');
                            api.assert(slot.assignedContains, id + ' center should stay inside assigned scene bucket');
                            avatarEl = document.querySelector('.map-static-avatar[data-avatar-id="' + id + '"]');
                            api.assert(!!avatarEl, 'school avatar element missing ' + id);
                            api.assertEqual(avatarEl.getAttribute('data-hotspot-id'), expectedOwnership[id], id + ' rendered hotspot binding mismatch');
                        }

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
                            var avatarLayer = document.getElementById('map-dynamic-avatar-layer');
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
                            api.assert(!!avatarLayer, 'avatar layer missing');
                            api.assert(parseInt(window.getComputedStyle(labelLayer).zIndex || '0', 10) > parseInt(window.getComputedStyle(avatarLayer).zIndex || '0', 10), 'label layer should stay above avatar layer');
                            api.assert(overlayLabel.classList.contains('is-hover'), 'overlay label should track hotspot hover state');
                            api.assert(parseFloat(overlayStyle.opacity || '0') > 0.9, 'overlay label should be visible on hover');
                            api.assert(labelRect.left >= hotspotRect.left - 6, 'overlay label should not drift left of hotspot');
                            api.assert(labelRect.left <= hotspotRect.right + 6, 'overlay label should stay horizontally attached to hotspot');
                            api.assert(labelRect.bottom >= hotspotRect.top - 6, 'overlay label anchor should stay inside hotspot vertical band');
                            api.assert(labelRect.bottom <= hotspotRect.bottom + 6, 'overlay label should not drift below hotspot');
                            return 'label=' + overlayLabel.textContent +
                                ' z=' + window.getComputedStyle(labelLayer).zIndex + '/' + window.getComputedStyle(avatarLayer).zIndex +
                                ' anchor=' + Math.round(labelRect.left - hotspotRect.left) + ',' + Math.round(labelRect.bottom - hotspotRect.top);
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
