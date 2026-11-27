/**
 * KShop claim-batch multiselect — legacy 待领取整批原子收尾 UI。
 *
 * 只在可选行 ≥2 时展示多选；任何列表刷新都先作废旧选择；发起时按当前视图
 * 顺序构造冻结有序 fingerprints（顺序是 operation identity），在途期间
 * 不得复用；unknown 结果只复用 coordinator 的 bulkQuery 对账，绝不自动重放。
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.KShopClaimBatch = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function create(options) {
        options = options || {};
        var _coordinator = options.coordinator;
        var _inventoryCoordinator = options.inventoryCoordinator;
        var _getPurchased = options.getPurchased || function() { return []; };
        var _isOpen = options.isOpen || function() { return true; };
        var _canStartWrite = options.canStartWrite || function() { return true; };
        var _toast = options.toast || function() {};
        var _messageForError = options.messageForError || function(scope, error) { return error; };
        var _applyResult = options.applyResult || function() {};
        var _renderOwned = options.renderOwned || function() {};
        var _refreshControls = options.refreshControls || function() {};
        var _cue = options.cue || function() {};
        var _cueForError = options.cueForError || function() { _cue('rejected'); };

        var MAX_BATCH_ROWS = 40;
        var _bar = null;
        var _gridRoot = null;
        var _button = null;
        var _allButton = null;
        var _hint = null;
        var _selection = {};
        var _selectionSize = 0;
        var _blocked = false;
        var _operationSeq = 0;

        function multiActive() {
            return _getPurchased().length >= 2;
        }

        function attachBar(gridView) {
            if (_bar || !gridView || !gridView.root || !gridView.renderer) return;
            _gridRoot = gridView.renderer.root;
            _bar = document.createElement('div');
            _bar.className = 'kshop-claim-batch-bar';
            _bar.hidden = true;
            _bar.innerHTML =
                '<button type="button" class="kshop-claim-all-btn" data-audio-cue="activate">全部领取</button>' +
                '<button type="button" class="kshop-claim-batch-btn" data-audio-cue="activate">批量领取</button>' +
                '<small class="kshop-claim-batch-hint"></small>';
            _allButton = _bar.querySelector('.kshop-claim-all-btn');
            _button = _bar.querySelector('.kshop-claim-batch-btn');
            _hint = _bar.querySelector('.kshop-claim-batch-hint');
            _allButton.addEventListener('click', onClaimAll);
            _button.addEventListener('click', onClaimBatch);
            gridView.root.insertBefore(_bar, gridView.renderer.root);
        }

        // 任何列表刷新（含成功写后重投影）都先作废多选，再由行渲染重建。
        function reset() {
            _selection = {};
            _selectionSize = 0;
            updateBar();
        }

        function checkboxHtml() {
            return multiActive()
                ? '<input type="checkbox" class="kshop-claim-check" aria-label="勾选整批领取" />' : '';
        }

        function syncCheckboxes() {
            if (!_gridRoot || typeof _gridRoot.querySelectorAll !== 'function') return;
            var checks = _gridRoot.querySelectorAll('.kshop-claim-check');
            for (var i = 0; i < checks.length; i++) {
                checks[i].disabled = _blocked;
                var fp = checks[i].getAttribute && checks[i].getAttribute('data-fp');
                if (fp) checks[i].checked = !!_selection[fp];
            }
        }

        function bindRow(row, purchasedItem) {
            var check = row.querySelector('.kshop-claim-check');
            if (!check) return;
            var initialFp = String(purchasedItem && purchasedItem.rowFingerprint || '');
            if (check.setAttribute) check.setAttribute('data-fp', initialFp);
            check.checked = !!(initialFp && _selection[initialFp]);
            check.disabled = _blocked;
            check.addEventListener('click', function(e) { e.stopPropagation(); });
            check.addEventListener('change', function() {
                if (_blocked) { check.checked = !!(initialFp && _selection[initialFp]); return; }
                var fingerprint = String(purchasedItem && purchasedItem.rowFingerprint || '');
                if (!fingerprint) { check.checked = false; return; }
                if (check.checked && !_selection[fingerprint]) {
                    if (_selectionSize >= MAX_BATCH_ROWS) {
                        check.checked = false;
                        _toast('单批最多勾选 ' + MAX_BATCH_ROWS + ' 项，请先领取当前批次。', 'warning');
                        return;
                    }
                    _selection[fingerprint] = true;
                    _selectionSize++;
                } else if (!check.checked && _selection[fingerprint]) {
                    delete _selection[fingerprint];
                    _selectionSize--;
                }
                updateBar();
                _refreshControls();
            });
        }

        function selectionHint() {
            if (_selectionSize >= MAX_BATCH_ROWS) {
                return '已勾选 ' + _selectionSize + ' 项（已达单批上限 ' + MAX_BATCH_ROWS + ' 项），整批一次领取';
            }
            return _selectionSize > 0
                ? '已勾选 ' + _selectionSize + ' 项，整批一次领取' : '可全部领取，或勾选至少 2 项分批领取';
        }

        function updateBar() {
            if (!_bar) return;
            var active = multiActive();
            _bar.hidden = !active;
            if (!active) return;
            var totalCount = _getPurchased().length;
            if (_allButton) _allButton.textContent = totalCount > MAX_BATCH_ROWS
                ? '领取前 ' + MAX_BATCH_ROWS + ' 项'
                : '全部领取（' + totalCount + '）';
            _button.textContent = _selectionSize > 0
                ? '批量领取（' + _selectionSize + '）' : '批量领取';
            _hint.textContent = selectionHint();
        }

        function setBlocked(blocked) {
            _blocked = !!blocked;
            if (_allButton) _allButton.disabled = _blocked || !multiActive();
            if (_button) _button.disabled = _blocked || _selectionSize < 2;
            syncCheckboxes();
            if (_hint && multiActive()) {
                _hint.textContent = _blocked ? '当前有写入或同步进行中，暂不可批量领取' : selectionHint();
            }
        }

        function nextOperationId() {
            _operationSeq++;
            return 'kcb.' + Date.now().toString(36) + '.' + _operationSeq.toString(36);
        }

        function consumeDispatchedSelection(frozenRows) {
            for (var i = 0; i < frozenRows.length; i++) {
                var fp = String(frozenRows[i] || '');
                if (fp && _selection[fp]) {
                    delete _selection[fp];
                    _selectionSize = Math.max(0, _selectionSize - 1);
                }
            }
            syncCheckboxes();
            updateBar();
        }

        function restoreDispatchedSelection(frozenRows) {
            for (var i = 0; i < frozenRows.length; i++) {
                var fp = String(frozenRows[i] || '');
                if (fp && !_selection[fp] && _selectionSize < MAX_BATCH_ROWS) {
                    _selection[fp] = true;
                    _selectionSize++;
                }
            }
            syncCheckboxes();
            updateBar();
        }

        function submitRows(frozenRows, fromManualSelection) {
            var operationId = nextOperationId();
            var inventoryWrite = _inventoryCoordinator.beginExternalWrite('shop.claimBatch');
            if (!inventoryWrite) {
                _toast('背包尚未同步或正在处理另一笔写入。', 'warning');
                return;
            }
            if (!_coordinator.claimBatch(operationId, frozenRows, function(resp) {
                if (!_isOpen()) return;
                var needsInventoryRefresh = !!resp.success
                    || (!!resp.reconciled && resp.error !== 'stale_state' && resp.error !== 'unknown_row');
                if (!_inventoryCoordinator.completeExternalWrite(
                        inventoryWrite, needsInventoryRefresh, function(refreshResult) {
                    if (!_isOpen()) return;
                    if (resp.success) _applyResult(resp);
                    else if (fromManualSelection && !resp.reconciled) {
                        restoreDispatchedSelection(frozenRows);
                    }
                    _renderOwned();
                    if (resp.success && resp.replayed === true) {
                        _toast('该批次此前已领取，结果已核对。', 'success', {silent:true});
                        _cue('success');
                    } else if (resp.success && refreshResult.success) {
                        _toast('批量领取成功，背包已刷新！', 'success', {silent:true});
                        _cue('success');
                    } else if (resp.success) {
                        _toast('批量领取已成功，但背包刷新失败；请点击“重试库存同步”。', 'warning', {silent:true});
                        _cue('success');
                    } else {
                        _toast(_messageForError('claimBatch', resp.error), 'error', {silent:true});
                        _cueForError(resp.error);
                    }
                })) return;
            })) {
                _inventoryCoordinator.completeExternalWrite(inventoryWrite, false);
                _toast('商城正在处理另一笔写入，请稍后再领取。', 'warning');
                return;
            }
            // 仅在写入已正式接纳后消费本次已派发的条目，避免繁忙阻断或未发条目丢失。
            consumeDispatchedSelection(frozenRows);
        }

        function onClaimAll() {
            if (!multiActive()) return;
            if (!_canStartWrite()) {
                _toast('商城尚未同步，请稍后再领取。', 'warning');
                return;
            }
            var purchased = _getPurchased();
            var frozenRows = [];
            for (var i = 0; i < purchased.length; i++) {
                var fingerprint = String(purchased[i].rowFingerprint || '');
                if (fingerprint) {
                    frozenRows.push(fingerprint);
                    if (frozenRows.length >= MAX_BATCH_ROWS) break;
                }
            }
            if (frozenRows.length < 2) {
                _toast('待领取列表已变化，请重试。', 'warning');
                return;
            }
            submitRows(frozenRows, false);
        }

        function onClaimBatch() {
            if (!multiActive()) return;
            if (!_canStartWrite()) {
                _toast('商城尚未同步，请稍后再领取。', 'warning');
                return;
            }
            var purchased = _getPurchased();
            var frozenRows = [];
            for (var i = 0; i < purchased.length; i++) {
                var fingerprint = String(purchased[i].rowFingerprint || '');
                if (fingerprint && _selection[fingerprint]) {
                    frozenRows.push(fingerprint);
                    if (frozenRows.length >= MAX_BATCH_ROWS) break;
                }
            }
            if (frozenRows.length < 2) {
                _toast('请至少勾选两项待领取商品。', 'warning');
                return;
            }
            submitRows(frozenRows, true);
        }

        return {
            attachBar:attachBar,
            reset:reset,
            multiActive:multiActive,
            checkboxHtml:checkboxHtml,
            bindRow:bindRow,
            updateBar:updateBar,
            setBlocked:setBlocked,
            selectionSize:function() { return _selectionSize; }
        };
    }

    return { create:create };
});
