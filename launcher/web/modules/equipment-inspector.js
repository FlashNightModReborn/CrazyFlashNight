/**
 * 通用装备检视器。
 *
 * 展示契约：
 *   - 武器：纸娃娃清单中的完整武器素材（不带人物）。
 *     双刀必须同时展示主刀与副手刀；疾影必须同时展示刀身与刀鞘。
 *   - 防具：按 Flash snapshot 性别绘制装备聚焦；没有对应分支时回退图标。
 *   - 其他：当前图标。
 *
 * 各业务页面的小图仍由 Icons 负责；本模块只在玩家主动打开检视窗口后加载
 * dressup manifest，并且同一时刻只维持一个 live Canvas renderer。
 */
var EquipmentInspector = (function() {
    'use strict';

    var MANIFEST_URL = 'assets/dressup/manifest.json';
    var DEFAULT_ZOOM = 1.85;
    var FIT_ZOOM = 1;
    var MIN_ZOOM = 1;
    var MAX_ZOOM = 4;
    var ZOOM_STEP = 0.2;
    var PAN_STEP = 34;
    var _manifestPromise = null;
    var _manifestUrl = '';

    var WEAPON_FIELDS = {
        '刀': '刀_装扮',
        '长枪': '长枪_装扮',
        '手枪': '手枪_装扮'
    };
    var COMPOSITE_WEAPON_FIELDS = {
        '双刀': {
            id: 'dual-blade',
            label: '完整双刀商品图',
            fields: ['刀_装扮', '刀2_装扮'],
            roles: ['primary', 'offhand']
        },
        '疾影': {
            id: 'blade-sheath',
            label: '刀身与刀鞘商品图',
            fields: ['刀_装扮', '刀3_装扮'],
            roles: ['blade', 'sheath']
        }
    };
    var ARMOR_USES = {
        '头部装备': true,
        '上装装备': true,
        '下装装备': true,
        '手部装备': true,
        '脚部装备': true,
        '颈部装备': true
    };
    var ARMOR_FOCUS_CONTEXT = {
        '头部装备': ['脸型'],
        '上装装备': [],
        '下装装备': [],
        '手部装备': [],
        '脚部装备': [],
        '颈部装备': []
    };

    function text(value) {
        return value == null ? '' : String(value);
    }

    function normalizeGender(value) {
        if (value === '女') return '女';
        if (value === '男') return '男';
        return '';
    }

    function unique(values) {
        var seen = {};
        var result = [];
        for (var index = 0; index < values.length; index++) {
            var value = values[index];
            if (!value || seen[value]) continue;
            seen[value] = true;
            result.push(value);
        }
        return result;
    }

    function itemFields(item, gender, allowGenderFallback) {
        var byGender = item && item.fieldsByGender;
        if (!byGender) return null;
        var fields = byGender[gender];
        if (!fields && allowGenderFallback) fields = byGender['男'] || byGender['女'];
        return fields && Object.keys(fields).length ? fields : null;
    }

    function entryRenderable(manifest, skinKey) {
        var entry = skinKey && manifest && manifest.skinKeys && manifest.skinKeys[skinKey];
        return !!(entry && entry.export);
    }

    function firstRenderableSkin(fields, manifest, preferredField) {
        if (!fields) return null;
        if (preferredField && entryRenderable(manifest, fields[preferredField])) {
            return {field:preferredField, skinKey:fields[preferredField]};
        }
        var names = Object.keys(fields).sort();
        for (var index = 0; index < names.length; index++) {
            if (entryRenderable(manifest, fields[names[index]])) {
                return {field:names[index], skinKey:fields[names[index]]};
            }
        }
        return null;
    }

    function resolveCompositeWeapon(fields, manifest, actionType) {
        var preset = COMPOSITE_WEAPON_FIELDS[actionType];
        if (!preset || !fields) return null;
        var components = [];
        var missingFields = [];
        for (var index = 0; index < preset.fields.length; index++) {
            var field = preset.fields[index];
            var skinKey = fields[field];
            if (!entryRenderable(manifest, skinKey)) {
                missingFields.push(field);
                continue;
            }
            // 保留 holder 身份，不按 skinKey 去重。部分双刀的两个槽位
            // 故意共用同一素材，但商品图仍必须画两次。
            components.push({
                role: preset.roles[index],
                field: field,
                skinKey: skinKey
            });
        }
        return {
            preset: preset,
            components: components,
            missingFields: missingFields,
            complete: components.length === preset.fields.length && missingFields.length === 0
        };
    }

    function resolveProductSource(output, gender, manifest) {
        output = output || {};
        gender = normalizeGender(gender);
        var name = text(output.name);
        var iconName = text(output.icon);
        var majorType = text(output.majorType || output.type);
        var use = text(output.use);
        var actionType = text(output.actionType || output.actiontype);
        var item = manifest && manifest.items ? manifest.items[name] : null;

        if (majorType === '武器') {
            var weaponFields = itemFields(item, gender, true);
            var composite = use === '刀' ? resolveCompositeWeapon(weaponFields, manifest, actionType) : null;
            if (composite && composite.complete) {
                return {
                    kind: 'weapon',
                    label: composite.preset.label,
                    name: name,
                    iconName: iconName,
                    gender: gender,
                    use: use,
                    actionType: actionType,
                    composition: composite.preset.id,
                    components: composite.components,
                    fitFields: composite.preset.fields.slice(0),
                    drawFields: composite.preset.fields.slice(0),
                    reason: ''
                };
            }
            if (composite && !composite.complete) {
                return {
                    kind: 'icon', label: '当前图标', name: name, iconName: iconName,
                    gender: gender, use: use, actionType: actionType,
                    composition: composite.preset.id,
                    missingFields: composite.missingFields,
                    reason: 'weapon_component_missing'
                };
            }
            var weapon = firstRenderableSkin(weaponFields, manifest, WEAPON_FIELDS[use]);
            if (weapon) {
                return {
                    kind: 'weapon',
                    label: '完整武器商品图',
                    name: name,
                    iconName: iconName,
                    gender: gender,
                    use: use,
                    actionType: actionType,
                    composition: 'single',
                    field: weapon.field,
                    skinKey: weapon.skinKey,
                    reason: ''
                };
            }
            return {
                kind: 'icon', label: '当前图标', name: name, iconName: iconName,
                gender: gender, use: use, actionType: actionType,
                reason: item ? 'weapon_asset_missing' : 'dressup_mapping_missing'
            };
        }

        if (majorType === '防具' && ARMOR_USES[use]) {
            // 防具不跨性别借素材：选中的存档性别分支不存在时必须回退当前图标。
            var armorFields = itemFields(item, gender, false);
            var armorFieldNames = armorFields ? Object.keys(armorFields) : [];
            var hasRenderable = false;
            for (var fieldIndex = 0; fieldIndex < armorFieldNames.length; fieldIndex++) {
                if (entryRenderable(manifest, armorFields[armorFieldNames[fieldIndex]])) {
                    hasRenderable = true;
                    break;
                }
            }
            if (hasRenderable) {
                return {
                    kind: 'armor',
                    label: '装备聚焦 · ' + gender,
                    name: name,
                    iconName: iconName,
                    gender: gender,
                    use: use,
                    fitFields: armorFieldNames,
                    drawFields: unique(armorFieldNames.concat(ARMOR_FOCUS_CONTEXT[use] || [])),
                    reason: ''
                };
            }
            return {
                kind: 'icon', label: '当前图标', name: name, iconName: iconName,
                gender: gender, use: use, reason: item ? 'gender_branch_missing' : 'dressup_mapping_missing'
            };
        }

        return {
            kind: 'icon', label: '当前图标', name: name, iconName: iconName,
            gender: gender, use: use, reason: 'non_equipment'
        };
    }

    function loadManifest(url) {
        url = url || MANIFEST_URL;
        if (!_manifestPromise || _manifestUrl !== url) {
            _manifestUrl = url;
            _manifestPromise = DressupDollRenderer.loadManifest(url).catch(function(error) {
                _manifestPromise = null;
                throw error;
            });
        }
        return _manifestPromise;
    }

    function make(tag, className, label) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (label != null) node.textContent = label;
        return node;
    }

    function appearanceForGender(gender) {
        return {'脸型': gender === '女' ? '女变装-基本脸型' : '男变装-基本脸型'};
    }

    function stateForSource(source, manifest) {
        if (source.kind === 'weapon') {
            if (source.composition === 'dual-blade' || source.composition === 'blade-sheath') {
                var componentKeyMap = {};
                for (var componentIndex = 0; componentIndex < source.components.length; componentIndex++) {
                    var component = source.components[componentIndex];
                    componentKeyMap[component.field] = component.skinKey;
                }
                return DressupDollRenderer.buildStateFromEquipment(manifest, {
                    gender: source.gender,
                    // resolveProductSource 可为无性别的武器商品图借用另一性别分支。
                    // 这里必须直接消费已解析的组件，不得再按请求性别重读 item。
                    keyMap: componentKeyMap,
                    fitFields: source.fitFields,
                    drawFields: source.drawFields,
                    strictFields: true,
                    rig: 'battle',
                    stateLabel: '兵器站立',
                    attackMode: source.actionType,
                    zoom: 0.92,
                    margin: 18
                });
            }
            return DressupDollRenderer.buildStateFromEquipment(manifest, {
                gender: source.gender,
                directSkinKey: source.skinKey,
                attackMode: source.use,
                zoom: 0.92,
                margin: 18
            });
        }
        if (source.kind === 'armor') {
            return DressupDollRenderer.buildStateFromEquipment(manifest, {
                gender: source.gender,
                equipment: {preview: source.name},
                appearance: appearanceForGender(source.gender),
                fitFields: source.fitFields,
                drawFields: source.drawFields,
                rig: 'battle',
                stateLabel: '空手站立',
                zoom: 0.88,
                margin: 24
            });
        }
        return null;
    }

    function open(options) {
        options = options || {};
        var shell = options.shell;
        var output = options.item || options.output || {};
        if (!shell || typeof shell.openModal !== 'function'
                || typeof WorkbenchInspectionViewport === 'undefined'
                || !WorkbenchInspectionViewport.create) return null;

        var modalKind = text(options.kind || 'equipment-inspector');
        var kicker = text(options.kicker || '装备检视');
        var closeLabel = text(options.closeLabel || '返回');

        var active = true;
        var renderer = null;
        var renderMeta = null;
        var listeners = [];
        var resizeRequest = null;
        var camera = null;
        var animationEnabled = !(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
        var source = null;
        var iconState = {name:'', reason:'', animated:false, generation:0};
        var modal = shell.openModal({
            kind: modalKind,
            kicker: kicker,
            title: text(output.displayName || kicker),
            actions: [{id:'close', label:closeLabel, primary:true}],
            onClose: function(reason) {
                destroy();
                if (typeof options.onClose === 'function') options.onClose(reason || 'close');
            }
        });
        if (!modal || !modal.dialog) return null;

        var root = make('div', 'equipment-inspector crafting-inspector');
        root.setAttribute('data-inspector-context', text(options.context || 'equipment'));
        var summary = make('div', 'equipment-inspector-summary crafting-inspector-summary');
        var sourceLabel = make('strong', 'equipment-inspector-source crafting-inspector-source', '正在解析素材…');
        var help = make('span', 'equipment-inspector-help crafting-inspector-help', '拖拽移动 · 滚轮缩放 · 方向键平移');
        summary.appendChild(sourceLabel);
        summary.appendChild(help);

        var viewport = make('div', 'equipment-inspector-viewport crafting-inspector-viewport');
        viewport.tabIndex = 0;
        viewport.setAttribute('role', 'region');
        viewport.setAttribute('aria-label', '装备特写预览，可拖拽或使用方向键移动');
        var checker = make('div', 'equipment-inspector-checker crafting-inspector-checker');
        var stage = make('div', 'equipment-inspector-stage crafting-inspector-stage');
        var loading = make('div', 'equipment-inspector-loading crafting-inspector-loading', '加载装备素材…');
        stage.appendChild(loading);
        viewport.appendChild(checker);
        viewport.appendChild(stage);

        var toolbar = make('div', 'equipment-inspector-toolbar crafting-inspector-toolbar');
        root.appendChild(summary);
        root.appendChild(viewport);
        root.appendChild(toolbar);
        var actions = modal.dialog.querySelector('.workbench-modal-actions');
        modal.dialog.insertBefore(root, actions || null);
        var animationButton = button('暂停动效', '切换装备动效播放', function() {
            animationEnabled = !animationEnabled;
            if (renderer && renderer.setAnimationEnabled) renderer.setAnimationEnabled(animationEnabled);
            else if (iconState.animated) renderIcon();
            animationButton.textContent = animationEnabled ? '暂停动效' : '播放动效';
            root.setAttribute('data-animation-paused', animationEnabled ? 'false' : 'true');
        });
        camera = WorkbenchInspectionViewport.create({
            document:document,
            viewport:viewport,
            target:stage,
            controlsHost:toolbar,
            active:true,
            ariaLabel:'装备特写预览，可拖拽或使用方向键移动',
            defaultZoom:DEFAULT_ZOOM,
            fitZoom:FIT_ZOOM,
            minZoom:MIN_ZOOM,
            maxZoom:MAX_ZOOM,
            zoomStep:ZOOM_STEP,
            panStep:PAN_STEP,
            fitLabel:'全貌',
            fitAriaLabel:'显示完整商品图',
            resetLabel:'重置特写',
            resetAriaLabel:'恢复默认高倍特写',
            resetOffset:inspectionOffset,
            controlsClass:'equipment-inspector-toolbar-controls',
            panControlsClass:'equipment-inspector-pan-controls crafting-inspector-pan-controls',
            zoomControlsClass:'equipment-inspector-zoom-controls crafting-inspector-zoom-controls',
            controlClass:'equipment-inspector-control crafting-inspector-control',
            statusClass:'equipment-inspector-status crafting-inspector-status',
            onChange:function(state) {
                root.setAttribute('data-zoom', String(Math.round(state.zoom * 100)));
            }
        });
        camera.getZoomControls().appendChild(animationButton);

        function button(label, ariaLabel, handler) {
            var node = make('button', 'equipment-inspector-control crafting-inspector-control', label);
            node.type = 'button';
            node.setAttribute('aria-label', ariaLabel);
            node.addEventListener('click', handler);
            listeners.push([node, 'click', handler]);
            return node;
        }

        function listen(node, eventName, handler, eventOptions) {
            node.addEventListener(eventName, handler, eventOptions);
            listeners.push([node, eventName, handler, eventOptions]);
        }

        function currentPixelRatio() {
            var viewportRect = viewport.getBoundingClientRect();
            var panelScale = Math.max(
                viewportRect.width / Math.max(1, viewport.clientWidth || viewportRect.width),
                viewportRect.height / Math.max(1, viewport.clientHeight || viewportRect.height)
            );
            return Math.max(2, Math.min(4,
                (Number(window.devicePixelRatio) || 1) * panelScale * DEFAULT_ZOOM));
        }

        function handleResize() {
            camera.resize();
            if (resizeRequest !== null) window.cancelAnimationFrame(resizeRequest);
            // PanelScale 在 resize 后的下一帧写入新比例；同帧稍后重采样，避免放大窗口后 backing 发糊。
            resizeRequest = window.requestAnimationFrame(function() {
                resizeRequest = null;
                if (!active) return;
                camera.resize();
                if (renderer && renderer.setPixelRatio) renderer.setPixelRatio(currentPixelRatio());
            });
        }

        function inspectionOffset(zoom) {
            // 手套和鞋通常是左右分离部件。高倍默认略偏向一侧，避免首屏正好落在透明间隙；
            // “全貌”仍严格归零，方向按钮可访问另一侧。
            var panX = zoom > FIT_ZOOM && source && source.kind === 'armor'
                && (source.use === '手部装备' || source.use === '脚部装备')
                ? (viewport.clientWidth || 1) * 0.18 : 0;
            return {panX:panX};
        }

        function clearRenderer() {
            if (renderer) renderer.destroy();
            renderer = null;
            renderMeta = null;
            root.removeAttribute('data-render-holders');
            root.removeAttribute('data-render-missing');
            root.removeAttribute('data-render-failed');
        }

        function iconIsAnimated(iconName) {
            if (typeof Icons === 'undefined') return false;
            if (Icons.isAnimated && Icons.isAnimated(iconName)) return true;
            var entry = Icons.entry ? Icons.entry(iconName) : null;
            return !!(entry && (entry.animated === true || entry.format === 'webp-animated'));
        }

        function markIconMissing(generation) {
            if (typeof generation === 'number' && generation !== iconState.generation) return;
            stage.innerHTML = '';
            stage.appendChild(make('div', 'equipment-inspector-missing crafting-inspector-missing', '检视素材缺失'));
            root.setAttribute('data-source', 'missing');
            root.setAttribute('data-composition', 'missing');
            sourceLabel.textContent = '素材缺失 · 无法检视';
            animationButton.disabled = true;
            animationButton.textContent = '无动效';
        }

        function renderIcon() {
            var generation = ++iconState.generation;
            stage.innerHTML = '';
            var mounted = false;
            if (animationEnabled && typeof Icons !== 'undefined' && Icons.html) {
                var html = Icons.html(iconState.name, 'equipment-inspector-current-icon crafting-inspector-current-icon');
                if (html) {
                    stage.innerHTML = html;
                    if (Icons.enhance) Icons.enhance(stage);
                    mounted = true;
                }
            } else if (!animationEnabled && typeof Icons !== 'undefined' && Icons.resolveStatic) {
                var staticUrl = Icons.resolveStatic(iconState.name);
                if (staticUrl) {
                    var staticImage = make('img', 'equipment-inspector-current-icon crafting-inspector-current-icon');
                    staticImage.alt = '';
                    staticImage.src = staticUrl;
                    stage.appendChild(staticImage);
                    mounted = true;
                }
            }
            if (!mounted) {
                markIconMissing(generation);
                return false;
            }
            var images = stage.querySelectorAll('img');
            for (var imageIndex = 0; imageIndex < images.length; imageIndex++) {
                images[imageIndex].addEventListener('error', function() { markIconMissing(generation); });
            }
            root.setAttribute('data-source', 'icon');
            root.setAttribute('data-composition', 'icon');
            sourceLabel.textContent = '当前图标' + (iconState.reason === 'gender_branch_missing' ? ' · 对应性别无纸娃娃分支' : '');
            animationButton.disabled = !iconState.animated;
            animationButton.textContent = iconState.animated
                ? (animationEnabled ? '暂停动效' : '播放动效') : '静态图标';
            animationButton.setAttribute('aria-label', iconState.animated ? '切换当前图标动效播放' : '当前图标为静态素材');
            root.setAttribute('data-animation-paused', animationEnabled ? 'false' : 'true');
            return true;
        }

        function mountIcon(reason) {
            clearRenderer();
            iconState.name = source ? source.iconName : text(output.icon);
            iconState.reason = reason || '';
            iconState.animated = iconIsAnimated(iconState.name);
            if (renderIcon()) camera.reset(DEFAULT_ZOOM);
        }

        function mountDressup(manifest) {
            clearRenderer();
            stage.innerHTML = '';
            var canvas = make('canvas', 'equipment-inspector-canvas crafting-inspector-canvas');
            canvas.setAttribute('aria-hidden', 'true');
            stage.appendChild(canvas);
            var failedFallbackScheduled = false;
            // backing 同时覆盖设备 DPR、外层 PanelScale 和默认 185% 特写；上限 4 控制唯一 live
            // Canvas 的内存/24fps 重绘成本。继续放大到 400% 属于探索性放大，不承诺新增源细节。
            renderer = DressupDollRenderer.create(canvas, {
                manifest: manifest,
                fps: 24,
                pixelRatio: currentPixelRatio(),
                ignoreCssTransforms: true,
                animate: animationEnabled,
                onRender: function(meta) {
                    renderMeta = meta || null;
                    if (meta) {
                        root.setAttribute('data-render-holders', String(meta.holders || 0));
                        root.setAttribute('data-render-missing', String(meta.missing || 0));
                        root.setAttribute('data-render-failed', String(meta.failedImages || 0));
                    }
                    if (failedFallbackScheduled || !meta || meta.pendingImages > 0) return;
                    var expectedHolders = source && source.components ? source.components.length : 0;
                    var invalidComposite = expectedHolders > 0 &&
                        (meta.holders !== expectedHolders || meta.missing > 0 || meta.failedImages > 0);
                    var invalidFocusedEquipment = source && source.kind === 'armor' && meta.holders < 1;
                    if (!invalidComposite && !invalidFocusedEquipment && meta.failedImages < 1) return;
                    failedFallbackScheduled = true;
                    var failedRenderer = renderer;
                    var failedSource = source;
                    window.setTimeout(function() {
                        if (!active || renderer !== failedRenderer) return;
                        source = {
                            kind:'icon', label:'当前图标', name:failedSource.name,
                            iconName:failedSource.iconName, gender:failedSource.gender,
                            use:failedSource.use,
                            reason:invalidComposite || invalidFocusedEquipment ? 'holder_contract_failed' : 'asset_load_failed'
                        };
                        mountIcon(source.reason);
                    }, 0);
                }
            });
            var meta = renderer.render(stateForSource(source, manifest));
            renderMeta = meta || null;
            root.setAttribute('data-source', source.kind);
            root.setAttribute('data-gender', source.gender);
            root.setAttribute('data-composition', source.composition || source.kind);
            sourceLabel.textContent = source.label;
            animationButton.disabled = !(meta && meta.animated);
            if (animationButton.disabled) animationButton.textContent = '静态素材';
            else animationButton.textContent = animationEnabled ? '暂停动效' : '播放动效';
            camera.reset(DEFAULT_ZOOM);
        }

        function destroy() {
            if (!active) return;
            active = false;
            if (resizeRequest !== null) {
                window.cancelAnimationFrame(resizeRequest);
                resizeRequest = null;
            }
            if (camera) camera.destroy();
            camera = null;
            clearRenderer();
            for (var index = 0; index < listeners.length; index++) {
                listeners[index][0].removeEventListener(listeners[index][1], listeners[index][2], listeners[index][3]);
            }
            listeners = [];
        }

        listen(window, 'resize', handleResize);
        viewport.focus();

        var outputMajorType = text(output.majorType || output.type);
        if (outputMajorType !== '武器' && outputMajorType !== '防具') {
            source = resolveProductSource(output, options.gender, null);
            mountIcon(source.reason);
        } else loadManifest(options.manifestUrl || MANIFEST_URL).then(function(manifest) {
            if (!active) return;
            source = resolveProductSource(output, options.gender, manifest);
            if (source.kind === 'weapon' || source.kind === 'armor') mountDressup(manifest);
            else mountIcon(source.reason);
        }).catch(function() {
            if (!active) return;
            source = {
                kind:'icon', label:'当前图标', iconName:text(output.icon),
                reason:'manifest_unavailable'
            };
            mountIcon(source.reason);
        });

        return {
            close: function() { return shell.closeModal(modalKind); },
            destroy: destroy,
            debugState: function() {
                var cameraState = camera ? camera.debugState()
                    : {zoom:DEFAULT_ZOOM, panX:0, panY:0};
                return {
                    active: active,
                    source: source ? source.kind : 'loading',
                    gender: source ? source.gender || '' : '',
                    composition: source ? source.composition || '' : '',
                    render: renderMeta ? {
                        holders: renderMeta.holders || 0,
                        missing: renderMeta.missing || 0,
                        pendingImages: renderMeta.pendingImages || 0,
                        failedImages: renderMeta.failedImages || 0,
                        animated: !!renderMeta.animated
                    } : null,
                    zoom: cameraState.zoom,
                    panX: cameraState.panX,
                    panY: cameraState.panY,
                    animationEnabled: animationEnabled
                };
            }
        };
    }

    return {
        loadManifest: loadManifest,
        resolveItemSource: resolveProductSource,
        resolveProductSource: resolveProductSource,
        buildStateForSource: stateForSource,
        open: open,
        constants: {
            defaultZoom: DEFAULT_ZOOM,
            fitZoom: FIT_ZOOM,
            minZoom: MIN_ZOOM,
            maxZoom: MAX_ZOOM
        }
    };
})();
