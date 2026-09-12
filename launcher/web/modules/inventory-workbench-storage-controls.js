/** Shared storage commands and quantity selection for physical containers and stash. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchStorageControls = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';
    function create(options) {
        var selection = null, amount, quantity = null, moveButton = null, pageButton = null, batch = null;
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
            var item = selection && selection.item.item;
            var maximum = Number(item && item.quantity) || 1;
            quantity.root.hidden = !item || item.itemKind !== 'stack' || maximum <= 1 || !!quick.mode;
            quantity.update({min:1, max:maximum, presetMax:maximum,
                value:amount === undefined ? maximum : amount, disabled:!writable()});
            updateMove();
        }
        function moveSelected() {
            if (!selection || !writable() || batch.controller.getMode()) return false;
            var value = selectedQuantity();
            if (value === 0) return false;
            return batch.controller.enqueue(selection.view.containerId, selection.item, false, value);
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
        function attach(bar, transfer) {
            batch = transfer;
            quantity = new options.components.QuantityControl({document:options.document,
                className:'workbench-quantity-control inventory-inline-quantity',
                ariaLabel:'所选物品移动数量', maxLabel:'全部', maxAriaLabel:'设为所选物品总数量',
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
                            options.toast(result.success ? '物品已丢弃。' : options.error(result.error));
                        })) options.toast('库存正在处理另一项操作。');
                    }}]
            });
        }
        function sort(containerId, methodName, label) {
            if (!writable() || containerId === 'stash') return;
            options.beforeAction();
            methodName = methodName || 'byType'; label = label || methodName;
            options.shell().openModal({kind:'inventory-sort',
                title:'按' + label + '整理' + containerId + '？',
                message:'将重新排列' + (containerId === '战备箱' ? '当前已解锁区域' : '全部物品') + '，并合并可堆叠物品。',
                detail:containerId === '战备箱' ? '未解锁的存档保留区不会被读取或移动。' : '原有摆放顺序会改变。',
                actions:[{id:'cancel',label:'取消',audioCue:'back'},
                    {id:'sort',label:'整理并合并',primary:true,audioCue:'activate',onSelect:function() {
                        if (!writable()) return;
                        options.beforeAction();
                        if (!options.coordinator.sortAndMerge(containerId, methodName, function(result) {
                            options.render();
                            options.toast(result.success ? containerId + '整理完成。' : containerId + '整理失败，请重试。');
                        })) options.toast('库存正在处理另一项操作。');
                    }}]
            });
        }
        return {attach:attach, update:update, setSelection:setSelection,
            quantityFor:function(id,row) { return same(row,id) ? selectedQuantity() : undefined; },
            discard:discard, sort:sort, destroy:function() {
                if (quantity) quantity.destroy();
                selection = null; quantity = moveButton = pageButton = batch = null;
            }};
    }
    return {create:create};
});
