/** Shared storage commands and quantity selection for physical containers and stash. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchStorageControls = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';
    function create(options) {
        var selection = null, amount, quantity = null, moveButton = null, pageButton = null, takePageButton = null, depositPageButton = null, batch = null, dblClickRoot = null, dblClickHandler = null;
        function writable() {
            var state = options.state();
            return options.view() === 'storage' && state.ready
                && !state.busyOwner && !state.refreshRequired;
        }
        function same(row, id) {
            return selection && selection.view.containerId === id
                && selection.item === row;
        }
        function setSelection(value) {
            if (selection === value || selection && value
                    && selection.view === value.view && selection.item === value.item) return;
            selection = value;
            amount = undefined;
            if (quantity) quantity.setValue(Number(value && value.item.item.quantity) || 1);
            update();
        }
        function selectedQuantity() {
            if (!quantity || quantity.root.hidden) return undefined;
            var raw = String(quantity.numberInput.value).trim(), value = Number(raw);
            return /^\d+$/.test(raw) && Number.isSafeInteger(value)
                && value >= 1 && value <= Number(selection.item.item.quantity) ? value : 0;
        }
        function updateMove() {
            if (!moveButton) return;
            var quick = batch.controller.debugState(), id = selection && selection.view.containerId;
            moveButton.hidden = !selection || !!quick.mode;
            moveButton.disabled = !writable() || !!quick.committing || selectedQuantity() === 0
                || batch.rightId() === 'stash' && id === '背包';
            var clearable = id === 'stash' && selection.item.clearableOverflow;
            if (clearable) {
                moveButton.textContent = '清理历史超额';
                moveButton.title = '持有量已满，查看超额数量并确认清理';
                return;
            }
            if (batch.rightId() === 'stash' && id === '背包') {
                moveButton.textContent = '不可存入';
                moveButton.title = '暂存物资只支持取出，不能存入';
                return;
            }
            moveButton.textContent = id === 'stash' ? '领取' : id === '背包' ? '存入' : '取出';
            moveButton.title = id === 'stash' ? '按所选数量领取，自动放入适用位置'
                : '按所选数量移动，优先合并堆叠，再寻找空格';
        }
        function update() {
            if (!quantity) return;
            var quick = batch && batch.controller.debugState();
            if (pageButton) {
                pageButton.hidden = !quick || !quick.mode;
                pageButton.disabled = !writable() || !!quick.committing;
            }
            if (takePageButton && batch) {
                var snapshot = batch.getWindow(batch.rightId());
                var count = snapshot && (snapshot.slots || []).filter(function(row) { return row.occupied; }).length || 0;
                takePageButton.textContent = (batch.rightId() === 'stash' ? '领取本页' : '取出本页') + '（' + count + '）';
                takePageButton.disabled = !writable() || !count || !!quick.committing;
                takePageButton.title = batch.rightId() === 'stash'
                    ? '一次领取当前页所有物资；背包装不下的仍留暂存'
                    : '一次取出当前页所有物品；背包装不下时停止';
            }
            if (depositPageButton && batch) {
                var stashRight = batch.rightId() === 'stash';
                depositPageButton.hidden = stashRight;
                var bagSnapshot = stashRight ? null : batch.getWindow('背包');
                var bagCount = bagSnapshot && (bagSnapshot.slots || []).filter(function(row) { return row.occupied; }).length || 0;
                depositPageButton.textContent = '存入本页（' + bagCount + '）';
                depositPageButton.disabled = stashRight || !writable() || !bagCount || !!quick.committing;
                depositPageButton.title = '一次将当前背包页所有物品存入' + batch.rightId() + '；装不下时停止';
            }
            var item = selection && selection.item.item;
            var maximum = Number(item && item.quantity) || 1;
            quantity.root.hidden = !item || item.itemKind !== 'stack' || maximum <= 1 || !!quick.mode || selection.item.clearableOverflow;
            quantity.update({min:1, max:maximum, presetMax:maximum,
                value:amount === undefined ? maximum : amount, disabled:!writable()});
            updateMove();
        }
        function moveSelected() {
            if (!selection || !writable() || batch.controller.getMode()) return false;
            var value = selectedQuantity();
            if (value === 0) return false;
            var row = selection.item;
            if (selection.view.containerId === 'stash' && row.clearableOverflow === true) {
                var ref = options.slotRef('stash', row, row.quantity);
                if (!ref) return false;
                options.shell().openModal({kind:'discard', title:'清理历史超额情报？',
                    message:String(row.item.displayName || row.item.name) + '：清理暂存中的 ' + row.quantity + ' 件。',
                    detail:'已持有的情报和解锁资格保留。清理不折算金币，确认后无法撤销。',
                    actions:[{id:'cancel',label:'取消',audioCue:'back'},
                        {id:'clear',label:'确认清理',danger:true,audioCue:'destructive',onSelect:function() {
                            if (!writable() || !options.clearOverflow(ref)) options.toast('暂存状态已变化，请重新选择。');
                        }}]});
                return true;
            }
            return batch.controller.enqueue(selection.view.containerId, row, false, value);
        }
        function selectPage() {
            if (!batch || !writable()) return;
            var quick = batch.controller.debugState(), mode = quick.mode;
            if (!mode || quick.committing) return;
            var id = mode === 'deposit' ? '背包' : batch.rightId();
            var snapshot = batch.getWindow(id), rows = snapshot && snapshot.slots || [];
            rows.forEach(function(row) {
                if (!row.occupied) return;
                var key = String(row.entryId || row.physicalSlot);
                var selected = Object.keys(quick.entries).some(function(k) {
                    var entry = quick.entries[k];
                    return entry.containerId === id && String(entry.slot) === key;
                });
                if (!selected) batch.controller.enqueue(id, row, true);
            });
        }
        function takePage() {
            if (!batch || !writable() || batch.controller.isBusy()) return false;
            if (batch.controller.getMode() !== 'withdraw') {
                if (!batch.controller.setMode('withdraw')) return false;
            }
            selectPage();
            return batch.controller.commit({exitAfter:true});
        }
        function depositPage() {
            if (!batch || !writable() || batch.controller.isBusy() || batch.rightId() === 'stash') return false;
            if (batch.controller.getMode() !== 'deposit') {
                if (!batch.controller.setMode('deposit')) return false;
            }
            selectPage();
            return batch.controller.commit({exitAfter:true});
        }
        function handleSlotDblClick(event) {
            if (typeof options.cancelPendingActivate === 'function') options.cancelPendingActivate();
            if (!batch || !writable() || batch.controller.getMode() || batch.controller.isBusy()) return;
            var target = event && event.target;
            if (!target || !target.closest || target.closest('button')) return;
            var card = target.closest('.inventory-slot-card.occupied');
            if (!card) return;
            var containerId = card.getAttribute('data-container-id');
            if (!containerId || (batch.rightId() === 'stash' && containerId === '背包')) return;
            var snapshot = batch.getWindow(containerId);
            var rows = snapshot && snapshot.slots || [];
            var entryId = card.getAttribute('data-entry-id');
            var phys = card.getAttribute('data-physical-slot');
            var row = null;
            for (var i = 0; i < rows.length; i++) {
                if (entryId != null ? String(rows[i].entryId) === entryId
                        : String(rows[i].physicalSlot) === String(phys)) {
                    row = rows[i]; break;
                }
            }
            if (!row || !row.occupied) return;
            event.preventDefault();
            event.stopPropagation();
            if (containerId === 'stash' && row.clearableOverflow === true) {
                setSelection({view:{containerId:containerId}, item:row});
                moveSelected();
                return;
            }
            batch.controller.enqueue(containerId, row, false);
        }
        function attach(bar, transfer) {
            batch = transfer;
            quantity = new options.components.QuantityControl({document:options.document,
                className:'workbench-quantity-control inventory-inline-quantity',
                ariaLabel:'所选物品移动数量', maxLabel:'全部数量', maxAriaLabel:'设为所选物品总数量（不选择其他物品）',
                showPlusFive:false, onChange:function(value) { amount = value; updateMove(); }});
            quantity.root.addEventListener('input', updateMove);
            quantity.root.addEventListener('change', updateMove);
            quantity.root.addEventListener('keydown', updateMove);
            moveButton = options.document.createElement('button');
            moveButton.type = 'button'; moveButton.className = 'workbench-mode-btn inventory-move-selected';
            moveButton.setAttribute('data-audio-cue', 'activate');
            moveButton.addEventListener('click', moveSelected);
            var modes = bar.root.querySelector('.inventory-quick-transfer-modes');
            modes.prepend(moveButton); modes.prepend(quantity.root);
            pageButton = options.document.createElement('button');
            pageButton.type = 'button'; pageButton.className = 'workbench-mode-btn inventory-select-page';
            pageButton.textContent = '选择本页';
            pageButton.addEventListener('click', selectPage);
            bar.root.querySelector('.inventory-quick-transfer-actions').prepend(pageButton);
            takePageButton = options.document.createElement('button');
            takePageButton.type = 'button';
            takePageButton.className = 'workbench-mode-btn inventory-take-page';
            takePageButton.setAttribute('data-audio-cue', 'activate');
            takePageButton.addEventListener('click', takePage);
            bar.root.querySelector('.inventory-quick-transfer-actions').prepend(takePageButton);
            depositPageButton = options.document.createElement('button');
            depositPageButton.type = 'button';
            depositPageButton.className = 'workbench-mode-btn inventory-deposit-page';
            depositPageButton.setAttribute('data-audio-cue', 'activate');
            depositPageButton.addEventListener('click', depositPage);
            bar.root.querySelector('.inventory-quick-transfer-actions').prepend(depositPageButton);
            dblClickRoot = bar.root.closest ? bar.root.closest('.inventory-workbench-panel') : null;
            if (dblClickRoot) {
                dblClickHandler = handleSlotDblClick;
                dblClickRoot.addEventListener('dblclick', dblClickHandler);
            }
            update();
        }
        function discard(containerId, slot) {
            if (!writable() || containerId !== '背包' || !slot.occupied) return;
            var projection = slot.confirmProjection || slot.item || {};
            options.shell().openModal({kind:'discard',
                title:'丢弃 ' + String(projection.displayName || '该物品') + '？',
                message:'将丢弃整组，共 ' + Number(projection.quantity || 1) + ' 件。',
                detail:'丢弃后无法找回。',
                actions:[{id:'cancel',label:'取消',audioCue:'back'},
                    {id:'discard',label:'确认丢弃',danger:true,audioCue:'destructive',onSelect:function() {
                        if (!writable()) return;
                        if (!options.coordinator.discard(options.slotRef(containerId, slot), function(result) {
                            options.render();
                            options.toast(result.success
                                ? (result.discarded && result.discarded.displayIssue === 'balance_summary_invalid'
                                    ? '物品已丢弃。平衡摘要暂不可用。' : '物品已丢弃。')
                                : options.error(result.error));
                        })) options.toast('库存正在处理另一项操作。');
                    }}]
            });
        }
        function sort(containerId, methodName, label) {
            if (!writable() || containerId === 'stash') return;
            options.beforeAction();
            methodName = methodName || 'byType'; label = label || methodName;
            if (!options.coordinator.sortAndMerge(containerId, methodName, function(result) {
                options.render();
                options.toast(result.success
                    ? containerId + '已按' + label + '整理并合并。'
                    : containerId + '整理失败，请重试。');
            })) options.toast('库存正在处理另一项操作。');
        }
        return {attach:attach, update:update, setSelection:setSelection,
            quantityFor:function(id,row) { return same(row,id) ? selectedQuantity() : undefined; },
            discard:discard, sort:sort, destroy:function() {
                if (dblClickRoot && dblClickHandler) dblClickRoot.removeEventListener('dblclick', dblClickHandler);
                if (quantity) quantity.destroy();
                selection = null; quantity = moveButton = pageButton = takePageButton = depositPageButton = batch = dblClickRoot = dblClickHandler = null;
            }};
    }
    return {create:create};
});
