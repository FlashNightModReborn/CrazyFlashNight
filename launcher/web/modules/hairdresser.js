/** 理发店 — AS2 权威目录、本地纸娃娃预览、单一 commit 写入口。 */
var HairdresserPanel = (function() {
    'use strict';

    var DESIGN_W = 1024;
    var DESIGN_H = 576;
    var BALD_IDENTIFIER = '光头';
    var _config = (typeof window !== 'undefined' && window.__HAIRDRESSER_CONFIG__) || {};
    var _manifestUrl = _config.manifestUrl || 'assets/dressup/manifest.json';
    var _manifest = null;
    var _manifestPromise = null;
    var _manifestError = '';
    var _manifestLoading = false;

    var _shellEl = null;
    var _rootEl = null;
    var _catalogEl = null;
    var _emptyEl = null;
    var _canvasEl = null;
    var _fallbackEl = null;
    var _previewNameEl = null;
    var _currentEl = null;
    var _countEl = null;
    var _genderEl = null;
    var _faceEl = null;
    var _statusEl = null;
    var _errorEl = null;
    var _retryButton = null;
    var _commitButton = null;
    var _cancelButton = null;
    var _closeButton = null;
    var _scaleHandle = null;
    var _renderer = null;

    var _snapshot = null;
    var _selectedIndex = -1;
    var _busy = false;
    var _snapshotBusy = false;
    var _needsReconcile = false;
    var _needsRefresh = false;
    var _reconcileExpected = '';
    var _reconcileOutcome = '';
    var _hostReconcileFlags = null;
    var _errorText = '';
    var _statusText = '正在同步发型目录…';
    var _statusState = 'loading';
    var _generation = 0;
    var _previewIssue = '';
    var _previewFields = [];
    var _resolvedFaceKey = '';
    var _resolvedHairKey = '';
    var _lastRendererMeta = null;

    var _mux = new HairdresserRuntime.RequestMux({
        send: function(message) { return Bridge.send(message); },
        timeoutMs: _config.requestTimeoutMs,
        sessionNonce: _config.sessionNonce
    });

    Panels.register('hairdresser', {
        create: createDOM,
        onOpen: onOpen,
        onClose: cleanup,
        onRequestClose: requestClose,
        onForceClose: function() {
            cleanup();
            toast('连接已断开，理发店已关闭。');
        }
    });

    function makeNode(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined && text !== null) node.textContent = text;
        return node;
    }

    function makeButton(className, text, ariaLabel) {
        var button = makeNode('button', className, text);
        button.type = 'button';
        if (ariaLabel) button.setAttribute('aria-label', ariaLabel);
        return button;
    }

    function createDOM() {
        _shellEl = makeNode('div', 'panel-scale-shell hairdresser-scale-shell');
        return _shellEl;
    }

    function buildDOM() {
        while (_shellEl.firstChild) _shellEl.removeChild(_shellEl.firstChild);

        _rootEl = makeNode('section', 'hairdresser-panel');
        _rootEl.setAttribute('aria-labelledby', 'hairdresser-title');
        _rootEl.setAttribute('data-state', 'loading');

        var header = makeNode('header', 'hairdresser-header');
        var heading = makeNode('div', 'hairdresser-heading');
        heading.appendChild(makeNode('span', 'hairdresser-kicker', '基地服务 / 免费造型'));
        var title = makeNode('h1', '', '理发店');
        title.id = 'hairdresser-title';
        heading.appendChild(title);
        _currentEl = makeNode('p', 'hairdresser-current', '当前发型：同步中');
        heading.appendChild(_currentEl);
        header.appendChild(heading);

        _statusEl = makeNode('p', 'hairdresser-header-status', _statusText);
        _statusEl.setAttribute('role', 'status');
        _statusEl.setAttribute('aria-live', 'polite');
        header.appendChild(_statusEl);

        _closeButton = makeButton('hairdresser-close', '×', '关闭理发店');
        _closeButton.addEventListener('click', requestClose);
        header.appendChild(_closeButton);
        _rootEl.appendChild(header);

        var body = makeNode('div', 'hairdresser-body');
        body.appendChild(buildPreviewPane());
        body.appendChild(buildCatalogPane());
        _rootEl.appendChild(body);
        _rootEl.appendChild(buildFooter());
        _shellEl.appendChild(_rootEl);
    }

    function buildPreviewPane() {
        var pane = makeNode('section', 'hairdresser-preview-pane');
        pane.setAttribute('aria-labelledby', 'hairdresser-preview-title');
        var titleRow = makeNode('div', 'hairdresser-section-title');
        var title = makeNode('h2', '', '本地试戴');
        title.id = 'hairdresser-preview-title';
        titleRow.appendChild(title);
        titleRow.appendChild(makeNode('span', 'hairdresser-local-badge', '不会写入存档'));
        pane.appendChild(titleRow);

        var stage = makeNode('div', 'hairdresser-preview-stage');
        _canvasEl = makeNode('canvas', 'hairdresser-preview-canvas');
        _canvasEl.width = 360;
        _canvasEl.height = 330;
        _canvasEl.setAttribute('aria-label', '当前选中发型的角色脸部预览');
        stage.appendChild(_canvasEl);
        _fallbackEl = makeNode('p', 'hairdresser-preview-fallback', '');
        _fallbackEl.hidden = true;
        _fallbackEl.setAttribute('role', 'status');
        stage.appendChild(_fallbackEl);
        _previewNameEl = makeNode('div', 'hairdresser-preview-name', '请选择发型');
        stage.appendChild(_previewNameEl);
        pane.appendChild(stage);

        var facts = makeNode('dl', 'hairdresser-preview-facts');
        facts.appendChild(makeNode('dt', '', '角色'));
        _genderEl = makeNode('dd', '', '—');
        facts.appendChild(_genderEl);
        facts.appendChild(makeNode('dt', '', '脸型'));
        _faceEl = makeNode('dd', '', '—');
        facts.appendChild(_faceEl);
        pane.appendChild(facts);
        return pane;
    }

    function buildCatalogPane() {
        var pane = makeNode('section', 'hairdresser-catalog-pane');
        pane.setAttribute('aria-labelledby', 'hairdresser-catalog-title');
        var titleRow = makeNode('div', 'hairdresser-section-title');
        var title = makeNode('h2', '', '发型目录');
        title.id = 'hairdresser-catalog-title';
        titleRow.appendChild(title);
        _countEl = makeNode('span', 'hairdresser-catalog-count', '同步中');
        titleRow.appendChild(_countEl);
        pane.appendChild(titleRow);

        _catalogEl = makeNode('div', 'hairdresser-catalog');
        _catalogEl.setAttribute('role', 'listbox');
        _catalogEl.setAttribute('aria-label', 'AS2 权威发型目录');
        _catalogEl.setAttribute('aria-busy', 'true');
        _catalogEl.addEventListener('click', onCatalogClick);
        _catalogEl.addEventListener('keydown', onCatalogKeyDown);
        pane.appendChild(_catalogEl);

        _emptyEl = makeNode('div', 'hairdresser-empty', '当前没有可用发型。');
        _emptyEl.hidden = true;
        pane.appendChild(_emptyEl);
        return pane;
    }

    function buildFooter() {
        var footer = makeNode('footer', 'hairdresser-footer');
        var messages = makeNode('div', 'hairdresser-messages');
        _errorEl = makeNode('p', 'hairdresser-error', '');
        _errorEl.setAttribute('role', 'alert');
        _errorEl.hidden = true;
        messages.appendChild(_errorEl);
        var hint = makeNode('p', 'hairdresser-hint',
            '目录点击只在浏览器中试戴；确认后才会提交当前选择。');
        messages.appendChild(hint);
        footer.appendChild(messages);

        var actions = makeNode('div', 'hairdresser-actions');
        _retryButton = makeButton('hairdresser-button secondary hairdresser-retry', '重新同步');
        _retryButton.hidden = true;
        _retryButton.addEventListener('click', retry);
        actions.appendChild(_retryButton);
        _cancelButton = makeButton('hairdresser-button secondary hairdresser-cancel', '取消', '取消并关闭理发店');
        _cancelButton.addEventListener('click', requestClose);
        actions.appendChild(_cancelButton);
        _commitButton = makeButton('hairdresser-button primary hairdresser-commit', '确认更换');
        _commitButton.addEventListener('click', commitSelection);
        actions.appendChild(_commitButton);
        footer.appendChild(actions);
        return footer;
    }

    function onOpen() {
        _generation++;
        _snapshot = null;
        _selectedIndex = -1;
        _busy = false;
        _snapshotBusy = false;
        _needsReconcile = false;
        _needsRefresh = false;
        _reconcileExpected = '';
        _reconcileOutcome = '';
        _hostReconcileFlags = null;
        _errorText = '';
        _statusText = '正在同步发型目录…';
        _statusState = 'loading';
        _previewIssue = '';
        _previewFields = [];
        _resolvedFaceKey = '';
        _resolvedHairKey = '';
        _lastRendererMeta = null;
        buildDOM();
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = typeof PanelScale !== 'undefined'
            ? PanelScale.attach(_shellEl, DESIGN_W, DESIGN_H) : null;
        _mux.openSession();
        ensureManifest();
        refreshSnapshot(false);
    }

    function cleanup() {
        _generation++;
        _mux.closeSession();
        if (_scaleHandle) {
            _scaleHandle.detach();
            _scaleHandle = null;
        }
        if (_renderer) {
            _renderer.destroy();
            _renderer = null;
        }
        _snapshot = null;
        _selectedIndex = -1;
        _busy = false;
        _snapshotBusy = false;
        _needsReconcile = false;
        _needsRefresh = false;
        _reconcileExpected = '';
    }

    function ensureManifest() {
        if (_manifest) {
            renderPreview();
            return Promise.resolve(_manifest);
        }
        if (_manifestPromise) return _manifestPromise;
        if (typeof DressupDollRenderer === 'undefined') {
            _manifestError = '纸娃娃预览组件未加载';
            renderPreview();
            return Promise.resolve(null);
        }
        _manifestLoading = true;
        _manifestError = '';
        var generation = _generation;
        _manifestPromise = DressupDollRenderer.loadManifest(_manifestUrl).then(function(manifest) {
            _manifest = manifest;
            _manifestLoading = false;
            _manifestPromise = null;
            if (generation === _generation) renderPreview();
            return manifest;
        }, function(error) {
            _manifestLoading = false;
            _manifestPromise = null;
            _manifestError = error && error.message ? error.message : '预览资源加载失败';
            if (generation === _generation) renderPreview();
            throw error;
        });
        // The readable in-panel fallback is the consumer of this failure.
        _manifestPromise.catch(function() {});
        return _manifestPromise;
    }

    function validateSnapshot(response) {
        if (!response || response.success !== true || response.v !== 1) return null;
        if (typeof response.gender !== 'string'
            || !response.gender
            || typeof response.face !== 'string'
            || typeof response.currentHair !== 'string'
            || !Array.isArray(response.catalog)) {
            return null;
        }
        var catalog = [];
        for (var i = 0; i < response.catalog.length; i++) {
            var row = response.catalog[i];
            if (!row || typeof row.identifier !== 'string' || typeof row.name !== 'string') {
                return null;
            }
            catalog.push({
                identifier: row.identifier,
                name: row.name,
                sourceIndex: i
            });
        }
        return {
            gender: response.gender,
            face: response.face,
            currentHair: response.currentHair,
            catalog: catalog
        };
    }

    function refreshSnapshot(reconciling) {
        if (_snapshotBusy || _busy) return null;
        _snapshotBusy = true;
        if (!reconciling) _needsRefresh = false;
        _errorText = '';
        setStatus(reconciling ? '正在核对刚才的更换结果…' : '正在同步发型目录…', 'loading');
        var generation = _generation;
        var callbackRan = false;
        var callId = _mux.request('snapshot', {v: 1}, function(response) {
            callbackRan = true;
            if (generation !== _generation) return;
            _snapshotBusy = false;
            var snapshot = validateSnapshot(response);
            if (!snapshot) {
                var error = response && response.success === false
                    ? response.error : 'malformed_response';
                _needsRefresh = true;
                _errorText = errorMessage(error);
                setStatus(reconciling
                    ? '对账未完成，请重新同步。'
                    : '目录同步失败，请重试。', 'error');
                refreshControls();
                return;
            }

            _snapshot = snapshot;
            _needsRefresh = false;
            _errorText = '';
            if (reconciling && _reconcileExpected) {
                var expected = _reconcileExpected;
                var applied = snapshot.currentHair === expected;
                // Host flags are diagnostics only. The fresh authoritative value
                // is the sole applied/not-applied decision input.
                _hostReconcileFlags = {
                    reconciled: response.reconciled === true,
                    writeApplied: response.writeApplied === true
                };
                _reconcileOutcome = applied ? 'applied' : 'not_applied';
                _needsReconcile = false;
                _reconcileExpected = '';
                _selectedIndex = firstCatalogIndex(snapshot.currentHair);
                setStatus(applied
                    ? '已从最新存档状态确认更换成功。'
                    : '最新状态显示更换未生效，未自动重试。',
                    applied ? 'ready' : 'warning');
            } else {
                _selectedIndex = firstCatalogIndex(snapshot.currentHair);
                setStatus(snapshot.catalog.length
                    ? '目录已同步，可在本地试戴。'
                    : '目录已同步，但当前没有可用发型。',
                    snapshot.catalog.length ? 'ready' : 'empty');
            }
            renderCatalog();
            renderPreview();
            refreshControls();
        });
        if (!callId && !callbackRan) {
            _snapshotBusy = false;
            _needsRefresh = true;
            _errorText = '理发店会话尚未就绪。';
            setStatus('目录同步失败，请重试。', 'error');
        }
        refreshControls();
        return callId;
    }

    function firstCatalogIndex(identifier) {
        var rows = _snapshot ? _snapshot.catalog : [];
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].identifier === identifier) return i;
        }
        return rows.length ? 0 : -1;
    }

    function selectedRow() {
        var rows = _snapshot ? _snapshot.catalog : [];
        return _selectedIndex >= 0 && _selectedIndex < rows.length
            ? rows[_selectedIndex] : null;
    }

    function renderCatalog() {
        if (!_catalogEl) return;
        while (_catalogEl.firstChild) _catalogEl.removeChild(_catalogEl.firstChild);
        var rows = _snapshot ? _snapshot.catalog : [];
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            var button = makeButton('hairdresser-style-card', '');
            button.setAttribute('role', 'option');
            button.setAttribute('data-index', String(i));
            button.setAttribute('aria-label', '第 ' + (i + 1) + ' 项，' + row.name);
            var ordinal = makeNode('span', 'hairdresser-style-index', padOrdinal(i + 1));
            var copy = makeNode('span', 'hairdresser-style-copy');
            copy.appendChild(makeNode('b', '', row.name || row.identifier));
            copy.appendChild(makeNode('small', '', row.identifier));
            var marker = makeNode('span', 'hairdresser-style-marker', '');
            marker.setAttribute('aria-hidden', 'true');
            button.appendChild(ordinal);
            button.appendChild(copy);
            button.appendChild(marker);
            _catalogEl.appendChild(button);
        }
        _catalogEl.setAttribute('aria-busy', _snapshotBusy ? 'true' : 'false');
        if (_countEl) _countEl.textContent = rows.length + ' 款';
        if (_emptyEl) _emptyEl.hidden = rows.length !== 0;
        refreshCatalogSelection();
    }

    function refreshCatalogSelection() {
        if (!_catalogEl || !_snapshot) return;
        var buttons = _catalogEl.querySelectorAll('.hairdresser-style-card');
        var currentHair = _snapshot ? _snapshot.currentHair : '';
        var locked = _busy || _snapshotBusy || _needsReconcile;
        for (var i = 0; i < buttons.length; i++) {
            var row = _snapshot.catalog[i];
            var selected = i === _selectedIndex;
            var current = row.identifier === currentHair;
            buttons[i].classList.toggle('selected', selected);
            buttons[i].classList.toggle('current', current);
            buttons[i].setAttribute('aria-selected', selected ? 'true' : 'false');
            buttons[i].tabIndex = selected ? 0 : -1;
            buttons[i].disabled = locked;
            var marker = buttons[i].querySelector('.hairdresser-style-marker');
            if (marker) marker.textContent = current ? '当前' : selected ? '试戴' : '';
        }
    }

    function onCatalogClick(event) {
        var node = event.target;
        while (node && node !== _catalogEl && !node.hasAttribute('data-index')) {
            node = node.parentNode;
        }
        if (!node || node === _catalogEl || node.disabled) return;
        var index = Number(node.getAttribute('data-index'));
        if (!isFinite(index) || index < 0 || !_snapshot || index >= _snapshot.catalog.length) return;
        selectCatalogIndex(index, false);
    }

    function onCatalogKeyDown(event) {
        var node = event.target;
        if (!node || !node.hasAttribute('data-index') || node.disabled || !_snapshot) return;
        var index = Number(node.getAttribute('data-index'));
        var next = index;
        if (event.key === 'ArrowDown' || event.key === 'ArrowRight') next++;
        else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') next--;
        else if (event.key === 'Home') next = 0;
        else if (event.key === 'End') next = _snapshot.catalog.length - 1;
        else return;
        next = Math.max(0, Math.min(_snapshot.catalog.length - 1, next));
        event.preventDefault();
        selectCatalogIndex(next, true);
    }

    function selectCatalogIndex(index, focus) {
        if (!_snapshot || index < 0 || index >= _snapshot.catalog.length) return;
        _selectedIndex = index;
        _reconcileOutcome = '';
        _errorText = '';
        setStatus(_snapshot.catalog[index].identifier === _snapshot.currentHair
            ? '这是当前已保存的发型。'
            : '本地试戴中；确认前不会写入游戏。', 'ready');
        refreshCatalogSelection();
        renderPreview();
        refreshControls();
        if (focus && _catalogEl) {
            var nextButton = _catalogEl.querySelector('.hairdresser-style-card[data-index="' + index + '"]');
            if (nextButton) nextButton.focus();
        }
    }

    function hasRenderableSkin(manifest, key) {
        var entry = key && manifest && manifest.skinKeys ? manifest.skinKeys[key] : null;
        return !!(entry && entry.export);
    }

    function resolveAppearanceKey(manifest, field, rawValue) {
        if (hasRenderableSkin(manifest, rawValue)) return rawValue;
        var appearance = manifest && manifest.appearance ? manifest.appearance : {};
        var byId = field === 'face' ? appearance.faceById : appearance.hairById;
        var mapped = byId && Object.prototype.hasOwnProperty.call(byId, rawValue)
            ? byId[rawValue] : '';
        if (field === 'hair' && mapped === BALD_IDENTIFIER) return BALD_IDENTIFIER;
        return hasRenderableSkin(manifest, mapped) ? mapped : '';
    }

    function renderPreview() {
        if (!_canvasEl || !_fallbackEl || !_previewNameEl) return;
        var row = selectedRow();
        _lastRendererMeta = null;
        _resolvedFaceKey = '';
        _resolvedHairKey = '';
        _previewFields = [];
        _previewIssue = '';
        _previewNameEl.textContent = row
            ? (row.name || row.identifier) : '请选择发型';
        if (_genderEl) _genderEl.textContent = _snapshot ? _snapshot.gender : '—';
        if (_faceEl) _faceEl.textContent = _snapshot ? _snapshot.face : '—';

        if (!row || !_snapshot) {
            clearCanvas();
            setPreviewFallback('目录中没有可预览的发型。', true);
            return;
        }
        if (!_manifest) {
            clearCanvas();
            _previewIssue = _manifestError ? 'manifest_error' : 'manifest_loading';
            setPreviewFallback(_manifestError
                ? '预览资源暂不可用，仍可通过名称选择发型。'
                : '预览资源加载中，名称选择仍然可用。', true);
            return;
        }
        if (_snapshot.gender !== '男' && _snapshot.gender !== '女') {
            clearCanvas();
            _previewIssue = 'gender_unsupported';
            setPreviewFallback(
                '当前角色性别没有可用的纸娃娃预览；发型目录与确认操作仍然可用。',
                true
            );
            return;
        }

        _resolvedFaceKey = resolveAppearanceKey(_manifest, 'face', _snapshot.face);
        var mappedHair = resolveAppearanceKey(_manifest, 'hair', row.identifier);
        var bald = row.identifier === BALD_IDENTIFIER || mappedHair === BALD_IDENTIFIER;
        _resolvedHairKey = bald ? '' : mappedHair;
        _previewFields = bald ? ['脸型'] : ['脸型', '发型'];

        var appearance = {};
        if (_resolvedFaceKey) appearance['脸型'] = _resolvedFaceKey;
        if (!bald && _resolvedHairKey) appearance['发型'] = _resolvedHairKey;

        if (!_renderer) {
            _renderer = DressupDollRenderer.create(_canvasEl, {
                manifest: _manifest,
                animate: false,
                strictFields: true,
                fitFields: ['脸型', '发型'],
                drawFields: ['脸型', '发型'],
                margin: 22,
                zoom: 1.08,
                onRender: function(meta) {
                    _lastRendererMeta = copyRendererMeta(meta);
                    updatePreviewFallback();
                }
            });
        } else {
            _renderer.setManifest(_manifest);
            _renderer.setAnimationEnabled(false);
        }

        if (!_resolvedFaceKey) _previewIssue = 'face_missing';
        else if (!bald && !_resolvedHairKey) _previewIssue = 'hair_missing';
        var state = DressupDollRenderer.buildStateFromEquipment(_manifest, {
            gender: _snapshot.gender,
            appearance: appearance,
            rig: 'dialogue',
            strictFields: true,
            fitFields: _previewFields,
            drawFields: _previewFields,
            margin: 22,
            zoom: 1.08
        });
        var meta = _renderer.render(state);
        _lastRendererMeta = copyRendererMeta(meta);
        updatePreviewFallback();
    }

    function copyRendererMeta(meta) {
        if (!meta) return null;
        return {
            holders: meta.holders,
            totalHolders: meta.totalHolders,
            strictFields: meta.strictFields,
            animated: meta.animated,
            missing: meta.missing,
            pendingImages: meta.pendingImages,
            failedImages: meta.failedImages
        };
    }

    function updatePreviewFallback() {
        if (_previewIssue === 'face_missing') {
            setPreviewFallback('当前脸型缺少可读预览资源；发型名称仍可正常选择。', true);
            return;
        }
        if (_previewIssue === 'hair_missing') {
            setPreviewFallback('这款发型缺少可读预览资源；仍可按名称确认选择。', true);
            return;
        }
        if (_lastRendererMeta && _lastRendererMeta.failedImages > 0) {
            _previewIssue = 'asset_failed';
            setPreviewFallback('预览图片加载失败；发型名称与确认操作仍然可用。', true);
            return;
        }
        if (_previewIssue === 'asset_failed') _previewIssue = '';
        setPreviewFallback('', false);
    }

    function setPreviewFallback(message, visible) {
        if (!_fallbackEl) return;
        _fallbackEl.textContent = message || '';
        _fallbackEl.hidden = !visible;
        if (visible) {
            _fallbackEl.id = 'hairdresser-preview-fallback';
            if (_canvasEl) _canvasEl.setAttribute('aria-describedby', _fallbackEl.id);
        } else if (_canvasEl) {
            _canvasEl.removeAttribute('aria-describedby');
        }
    }

    function clearCanvas() {
        if (!_canvasEl) return;
        var context = _canvasEl.getContext('2d');
        if (context) context.clearRect(0, 0, _canvasEl.width, _canvasEl.height);
    }

    function commitSelection() {
        var row = selectedRow();
        if (!row || !_snapshot || _busy || _snapshotBusy || _needsReconcile
            || row.identifier === _snapshot.currentHair) {
            return;
        }
        // The frozen v1 write identity is the identifier string. Duplicate
        // catalog rows stay visible and ordered, but share the same saved value.
        var expected = row.identifier;
        _busy = true;
        _needsRefresh = false;
        _errorText = '';
        _reconcileOutcome = '';
        setStatus('正在确认更换，请稍候…', 'busy');
        refreshControls();
        var generation = _generation;
        var issuing = true;
        var callbackRan = false;
        var callId = _mux.request('commit', {v: 1, hairIdentifier: expected}, function(response) {
            callbackRan = true;
            if (generation !== _generation) return;
            var dispatched = !issuing;
            _busy = false;
            if (isValidCommitSuccess(response, expected)) {
                _snapshot.currentHair = response.currentHair;
                _errorText = '';
                setStatus('发型已更换并标记存档。', 'ready');
                refreshCatalogSelection();
                renderPreview();
                refreshControls();
                return;
            }
            if (response && response.success === true) {
                response = {
                    success: false,
                    error: 'malformed_response',
                    requiresReconcile: true
                };
            }
            if (isWriteAmbiguous(response, dispatched)) {
                _needsReconcile = true;
                _reconcileExpected = expected;
                _errorText = '';
                setStatus('提交结果未知，正在读取最新状态；不会自动重试。', 'reconcile');
                refreshControls();
                refreshSnapshot(true);
                return;
            }
            var error = response && response.error;
            _errorText = errorMessage(error);
            _needsRefresh = error === 'hair_not_found'
                || error === 'catalog_invalid' || error === 'pricing_unsupported';
            setStatus('更换未提交，可检查后手动重试。', 'error');
            refreshControls();
        });
        issuing = false;
        if (!callId && !callbackRan) {
            _busy = false;
            _errorText = '理发店会话尚未就绪。';
            setStatus('更换未提交，可重新尝试。', 'error');
            refreshControls();
        }
    }

    function isValidCommitSuccess(response, expected) {
        return !!response && response.success === true && response.v === 1
            && response.operation === 'commit'
            && typeof response.currentHair === 'string'
            && response.currentHair === expected;
    }

    function isWriteAmbiguous(response, dispatched) {
        if (response && response.requiresReconcile === true) return true;
        var error = response && response.error;
        if (error === 'reconcile_required') return true;
        return dispatched && (error === 'timeout' || error === 'client_timeout'
            || error === 'disconnected' || error === 'malformed_response'
            || error === 'invalid_response');
    }

    function retry() {
        if (_busy || _snapshotBusy) return;
        if (_manifestError) ensureManifest();
        refreshSnapshot(_needsReconcile && !!_reconcileExpected);
    }

    function requestClose() {
        if (_busy) {
            toast('发型更换结果正在确认，请稍候。');
            return false;
        }
        Panels.close();
        Bridge.send({type: 'panel', cmd: 'close', panel: 'hairdresser'});
        return true;
    }

    function setStatus(message, state) {
        _statusText = message;
        _statusState = state || 'ready';
        if (_statusEl) {
            _statusEl.textContent = _statusText;
            _statusEl.setAttribute('data-state', _statusState);
        }
        refreshControls();
    }

    function refreshControls() {
        if (!_rootEl) return;
        var row = selectedRow();
        var sameAsCurrent = !!(row && _snapshot && row.identifier === _snapshot.currentHair);
        var locked = _busy || _snapshotBusy || _needsReconcile;
        var rows = _snapshot ? _snapshot.catalog : [];
        var state = _busy ? 'busy'
            : _needsReconcile ? 'reconcile'
            : _errorText ? 'error'
            : _snapshotBusy ? 'loading'
            : rows.length === 0 && _snapshot ? 'empty' : 'ready';
        _rootEl.setAttribute('data-state', state);
        _rootEl.setAttribute('aria-busy', (_busy || _snapshotBusy) ? 'true' : 'false');
        if (_statusEl) {
            _statusEl.textContent = _statusText;
            _statusEl.setAttribute('data-state', _statusState);
        }
        if (_currentEl) {
            _currentEl.textContent = '当前发型：'
                + (_snapshot ? displayNameForIdentifier(_snapshot.currentHair) : '同步中');
        }
        if (_catalogEl) _catalogEl.setAttribute('aria-busy', _snapshotBusy ? 'true' : 'false');
        if (_errorEl) {
            _errorEl.textContent = _errorText;
            _errorEl.hidden = !_errorText;
        }
        if (_retryButton) {
            _retryButton.hidden = !(_needsRefresh || (_needsReconcile && !_snapshotBusy));
            _retryButton.disabled = _busy || _snapshotBusy;
            _retryButton.textContent = _needsReconcile ? '重新对账' : '重新同步';
        }
        if (_commitButton) {
            _commitButton.disabled = locked || !row || sameAsCurrent;
            _commitButton.textContent = _busy ? '确认中…'
                : _needsReconcile ? '等待对账'
                : sameAsCurrent ? '当前发型' : '确认更换';
        }
        if (_cancelButton) _cancelButton.disabled = _busy;
        if (_closeButton) _closeButton.disabled = _busy;
        refreshCatalogSelection();
    }

    function displayNameForIdentifier(identifier) {
        var rows = _snapshot ? _snapshot.catalog : [];
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].identifier === identifier) return rows[i].name || identifier;
        }
        return identifier || '未设置';
    }

    function padOrdinal(value) {
        return value < 10 ? '0' + value : String(value);
    }

    function toast(message) {
        if (typeof Toast !== 'undefined' && Toast.add) Toast.add(message);
    }

    function errorMessage(error) {
        var messages = {
            not_sent: '当前连接不可用，本次更换没有发出。',
            disconnected: '与游戏的连接已断开。',
            timeout: '游戏响应超时。',
            client_timeout: '游戏响应超时。',
            malformed_response: '游戏回包不完整，需要重新同步。',
            invalid_response: '游戏回包无效，需要重新同步。',
            reconcile_required: '上一次更换仍需对账。',
            busy: '理发店正在处理另一项操作。',
            hair_not_found: '该发型已不在最新目录中，请重新同步。',
            catalog_invalid: '游戏中的发型目录不可用。',
            pricing_unsupported: '目录含有当前 Web 理发店不支持的收费项。',
            invalid_payload: '发型选择无效。',
            actor_unavailable: '当前角色暂不可用。',
            save_unavailable: '存档系统暂不可用。',
            refresh_unavailable: '角色装扮暂时无法刷新。',
            unsupported_version: '理发店协议版本不匹配。',
            unsupported_cmd: '理发店不支持该操作。'
        };
        return messages[error] || '操作失败，请稍后重试。';
    }

    return {
        debugState: function() {
            var row = selectedRow();
            return {
                catalogCount: _snapshot ? _snapshot.catalog.length : 0,
                catalog: _snapshot ? _snapshot.catalog.map(function(item) {
                    return {
                        identifier: item.identifier,
                        name: item.name,
                        sourceIndex: item.sourceIndex
                    };
                }) : [],
                gender: _snapshot ? _snapshot.gender : '',
                face: _snapshot ? _snapshot.face : '',
                currentHair: _snapshot ? _snapshot.currentHair : '',
                selectedIndex: _selectedIndex,
                selectedIdentifier: row ? row.identifier : '',
                busy: _busy,
                snapshotBusy: _snapshotBusy,
                needsReconcile: _needsReconcile,
                needsRefresh: _needsRefresh,
                reconcileExpected: _reconcileExpected,
                reconcileOutcome: _reconcileOutcome,
                hostReconcileFlags: _hostReconcileFlags,
                statusState: _statusState,
                errorText: _errorText,
                manifestReady: !!_manifest,
                manifestLoading: _manifestLoading,
                manifestError: _manifestError,
                previewIssue: _previewIssue,
                previewFields: _previewFields.slice(0),
                resolvedFaceKey: _resolvedFaceKey,
                resolvedHairKey: _resolvedHairKey,
                rendererOptions: {strictFields: true, animate: false},
                rendererMeta: _lastRendererMeta,
                mux: _mux.debugState()
            };
        }
    };
})();
