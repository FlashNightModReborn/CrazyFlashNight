/* A withdrawal-only stash composed from the existing battlebox presentation. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildStashView = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';
    function open(view, itemUse, ports) {
        if (!view || !view.root || view._destroyed) return false;
        if (view._stashClose) view._stashClose();
        var document = view.root.ownerDocument;
        var panel = document.createElement('section');
        panel.className = 'character-build-stash inventory-workbench-panel';
        panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-label', '暂存物资');
        panel.setAttribute('aria-modal', 'true');
        panel.innerHTML = '<div class="stash-body"><div data-stash-grid-host></div>'
            + '<aside class="workbench-view stash-detail"><div class="workbench-view-header"><h3>物品详情</h3></div>'
            + '<div data-stash-detail class="stash-detail-copy">选择物品查看详情。</div>'
            + '<div class="stash-take-controls"><label>取出数量 <input class="stash-quantity" type="number" min="1" value="1" aria-label="取出数量"></label>'
            + '<button type="button" class="inventory-toolbar-btn" data-stash-take disabled>取出</button></div></aside></div>'
            + '<footer class="stash-footer"><span data-stash-status role="status">正在读取…</span>'
            + '<span>只取不存 · 背包放不下的物资继续保管</span></footer>';
        var toolbar = document.createElement('div');
        toolbar.className = 'inventory-warehouse-toolbar inventory-container-toolbar inventory-battlebox-toolbar';
        toolbar.innerHTML = '<div class="stash-actions"><button type="button" class="inventory-toolbar-btn" data-stash-back>返回物品页</button>'
            + '<button type="button" class="inventory-toolbar-btn" data-stash-all>尽量全部取出</button>'
            + '<button type="button" class="inventory-toolbar-btn" data-stash-batch aria-pressed="false">批量选择</button>'
            + '<button type="button" class="inventory-toolbar-btn" data-stash-selected disabled>取出所选</button>'
            + '<button type="button" class="inventory-toolbar-btn" data-stash-retry hidden>继续确认保存</button></div>';
        var underlay = view.root.querySelector('[data-build-underlay]');
        var focusBefore = document.activeElement;
        view.root.appendChild(panel);
        var alive = true, page = null, snapshot = null, busy = false, all = false;
        var blocked = new Set(), selected = new Map(), epoch = 0, batch = false, inspected = null, detailEpoch = 0;
        var status = panel.querySelector('[data-stash-status]');
        var detail = panel.querySelector('[data-stash-detail]');
        var quantity = panel.querySelector('.stash-quantity');
        var mode = Workbench.ItemGrid.getLayoutMode('inventory', 'compact');
        var owned = new InventoryUI.OwnedInventoryViewShell({
            containerId:'暂存区', instanceKey:'reward-stash', title:'暂存物资', kicker:'战利品保管',
            meta:'按需取出，稍后再整理', layoutMode:mode,
            className:'inventory-owned-view inventory-owned-warehouse inventory-owned-battlebox',
            gridClassName:'inventory-owned-grid stash-owned-grid',
            getItems:function() { return snapshot ? snapshot.slots : []; },
            // Physical slot is display position only. Every write uses the durable entry identity.
            keyOf:function(slot) { return slot.entry.entryId; },
            renderItem:function(slot) {
                var node = InventoryUI.renderOwnedSlot('暂存区', slot, {iconHtml:view._iconHtml.bind(view),allowDiscard:false});
                node.setAttribute('data-stash-entry', slot.entry.entryId);
                node.setAttribute('role', 'button'); node.setAttribute('tabindex', '-1');
                node.setAttribute('aria-pressed', 'false');
                return node;
            },
            bindItem:function(node, slot) {
                node.addEventListener('click', function(event) { activate(slot.entry, event.ctrlKey); });
                node.addEventListener('keydown', function(event) {
                    if (event.key === 'Enter' || event.key === ' ') {
                        event.preventDefault(); activate(slot.entry, event.ctrlKey);
                    }
                });
            },
            exportOffer:function() { return null; },
            probeAccept:function() { return {accepted:false,reason:'direction_forbidden'}; }
        });
        var pager = new InventoryUI.InventoryWindowPager({containerId:'暂存区',containerLabel:'暂存物资',
            defaultLimit:32,defaultCapacity:0,maxPageOptions:15,
            getSnapshot:function() { return snapshot; },
            getRequest:function() { return {offset:page ? page.offset : 0,limit:32}; },
            shortcutEnabled:function() { return alive && panel.contains(document.activeElement); },
            onRequest:function(offset, limit, callback) { all = false; load(offset,function() { callback({success:true}); }); return true; }
        });
        pager.prevButton.setAttribute('data-stash-prev', ''); pager.nextButton.setAttribute('data-stash-next', '');
        var controls = document.createElement('div'); controls.className = 'stash-window-controls';
        controls.appendChild(Workbench.ItemGrid.createToggle('inventory', mode, function(next) { owned.grid.setLayoutMode(next); }));
        controls.appendChild(pager.root); toolbar.appendChild(controls);
        owned.setToolbar(toolbar, null, pager);
        owned.view.mount(panel.querySelector('[data-stash-grid-host]')); pager.attach();
        var grid = owned.view.renderer.root; grid.setAttribute('data-stash-grid', '');
        var roving = new WorkbenchFocus.RovingGridFocus({root:grid,columns:function() { return 6; },
            itemSelector:'[data-stash-entry]',getKey:function(node) { return node.getAttribute('data-stash-entry'); }});
        var focus = new WorkbenchFocus.FocusScope({root:panel,underlay:underlay,
            initialFocus:toolbar.querySelector('[data-stash-back]'),onEscape:function() {
                if (!pager.menu.hidden) { pager.setMenuOpen(false, true); return false; }
                close(); return false;
            }});
        function close() {
            if (!alive) return;
            alive = false; all = false; epoch++; detailEpoch++;
            clearInterval(timer); pager.detach(); roving.destroy();
            focus.deactivate('close'); focus.destroy();
            owned.view.renderer.destroy(); owned.view.unmount();
            panel.remove(); view._stashClose = null;
            if (focusBefore && focusBefore.isConnected && focusBefore.focus) focusBefore.focus();
        }
        view._stashClose = close;
        function message(response) {
            var code = response && response.error;
            return code === 'commit_pending' ? '物资仍在安全保管中，等待保存结果。'
                : code === 'save_not_committed' || code === 'not_committed' ? '本次保存未完成，物品已保留，可以重试。'
                : code === 'stale_stash' || code === 'stale_entry' ? '物资已变化，已刷新列表。'
                : code === 'legacy_recovery_required' ? '上次领取需要先恢复，请返回后重新打开暂存入口。'
                : '暂时无法完成操作，物资仍会保留。';
        }
        function canTake() {
            return !busy && page && !page.pendingOperationId && itemUse.debugState().state === 'idle';
        }
        function syncButtons() {
            var state = itemUse.debugState().state, allowed = canTake();
            panel.querySelector('[data-stash-retry]').hidden = state !== 'needs_reconcile' && !(page && page.pendingOperationId);
            panel.querySelector('[data-stash-all]').textContent = all ? '停止批量取出' : '尽量全部取出';
            panel.querySelector('[data-stash-all]').disabled = !all && (!allowed || page.total < 1);
            panel.querySelector('[data-stash-selected]').disabled = !allowed || selected.size === 0;
            panel.querySelector('[data-stash-take]').disabled = !allowed || !inspected;
            panel.querySelector('[data-stash-batch]').disabled = busy;
            quantity.disabled = !allowed || !inspected;
            pager.setDisabled(busy);
        }
        function paintSelection() {
            grid.querySelectorAll('[data-stash-entry]').forEach(function(node) {
                var id = node.getAttribute('data-stash-entry');
                var active = batch ? selected.has(id) : inspected && inspected.entryId === id;
                node.classList.toggle('workbench-source-selected', !!active);
                node.setAttribute('aria-pressed', active ? 'true' : 'false');
            });
        }
        function inspect(entry) {
            inspected = entry; quantity.max = String(entry.quantity); quantity.value = String(entry.quantity);
            detail.textContent = '';
            var slot = InventoryUI.renderOwnedSlot('暂存区', {occupied:true,physicalSlot:0,item:entry.item},
                {iconHtml:view._iconHtml.bind(view),allowDiscard:false});
            detail.appendChild(slot);
            var note = document.createElement('p'); note.textContent = '已保管 ' + entry.quantity + ' 件'; detail.appendChild(note);
            var version = ++detailEpoch;
            if (typeof itemUse.requestStashTooltip === 'function') itemUse.requestStashTooltip(page.storeId, entry, function(data) {
                if (!alive || version !== detailEpoch || !data || !data.tooltip || typeof PanelTooltip === 'undefined') return;
                var info = data.tooltip;
                detail.innerHTML = PanelTooltip.buildItemRichHtml({
                    iconHtml:PanelTooltip.dynamicIconHtml(info.iconName),iconUrl:PanelTooltip.staticIconUrl(info.iconName),
                    introHTML:info.introHTML,descHTML:info.descHTML,document:info.document,
                    rootClass:'kshop-tt-rich-context inventory-owned-tt-context',
                    layoutType:PanelTooltip.inferLayoutType(info.itemType)});
            });
        }
        function activate(entry, quick) {
            if (busy) return;
            inspect(entry);
            if (quick && canTake()) submit([{entryId:entry.entryId,revision:entry.revision,quantity:entry.quantity}]);
            else if (batch) {
                if (selected.has(entry.entryId)) selected.delete(entry.entryId);
                else selected.set(entry.entryId,{entryId:entry.entryId,revision:entry.revision,quantity:entry.quantity});
            }
            paintSelection(); syncButtons();
        }
        function render() {
            var previous = inspected && inspected.entryId;
            selected.clear(); inspected = null; detailEpoch++;
            snapshot = {containerId:'暂存区',offset:page.offset,limit:32,capacity:page.total,accessibleCapacity:page.total,
                slots:page.entries.map(function(entry,index) { return {occupied:true,physicalSlot:page.offset+index,item:entry.item,entry:entry}; })};
            owned.syncSnapshot(snapshot,{meta:page.total+' 项 · 空间随物资扩展',emptyText:'暂存区是空的。新的战利品会在这里等你。'});
            roving.refresh({preferredKey:previous});
            var same = page.entries.find(function(entry) { return entry.entryId === previous; });
            if (same) inspect(same);
            else { detail.textContent = '选择物品查看详情。Ctrl + 点击可直接取出。'; quantity.value = '1'; }
            paintSelection();
            status.textContent = page.pendingOperationId ? '有一笔物资正在确认保存。' : page.total + ' 项物资正在保管';
            syncButtons();
        }
        function load(offset, continuation) {
            if (!alive) return;
            var version = ++epoch; busy = true; syncButtons();
            itemUse.requestStashPage(offset, function(data, response) {
                if (!alive || version !== epoch) return;
                busy = false;
                if (!data) { all = false; status.textContent = message(response); syncButtons(); return; }
                if (data.migrationRequired && !data.pendingOperationId) {
                    busy = true;
                    var migrating = itemUse.invokeStash('stashMigrate', {storeId:data.storeId, expectedRevision:data.revision}, function(result, ok) {
                        if (!alive) return; busy = false;
                        if (ok) load(0, continuation);
                        else { status.textContent = message(result); syncButtons(); }
                    });
                    if (!migrating) { busy = false; status.textContent = '请先确认上次操作的保存结果。'; }
                    syncButtons(); return;
                }
                if (data.offset > 0 && !data.entries.length) { load(Math.max(0, Math.floor((data.total - 1) / 32) * 32), continuation); return; }
                page = data; render();
                if (continuation) continuation();
            });
        }
        function submit(entries, continuation) {
            if (!alive || !canTake() || !entries.length) return;
            busy = true; syncButtons();
            var issued = itemUse.invokeStash('stashTake', {storeId:page.storeId, expectedRevision:page.revision, entries:entries}, function(result, ok) {
                busy = false;
                if (ports.changed && ok) ports.changed();
                if (!alive) return;
                if (!ok) { all = false; status.textContent = message(result); load(page.offset); return; }
                (result.blocked || []).forEach(function(row) { blocked.add(row.entryId); });
                var offset = page.offset;
                load(offset, continuation);
            });
            if (!issued) { busy = false; all = false; status.textContent = '请先确认上次操作的保存结果。'; syncButtons(); }
        }
        function takeNext() {
            if (!alive || !all || !page) return;
            var entries = page.entries.filter(function(row) { return !blocked.has(row.entryId); })
                .map(function(row) { return {entryId:row.entryId, revision:row.revision, quantity:row.quantity}; });
            if (entries.length) { submit(entries, function() { setTimeout(takeNext, 0); }); return; }
            if (page.offset + page.entries.length < page.total) { load(page.offset + page.entries.length, takeNext); return; }
            all = false; status.textContent = page.total ? '能放下的物资已取出，其余继续保管。' : '物资已全部取出。'; syncButtons();
        }
        panel.querySelector('[data-stash-back]').addEventListener('click', close);
        panel.querySelector('[data-stash-all]').addEventListener('click', function() {
            if (all) { all = false; syncButtons(); return; }
            all = true; blocked.clear(); load(0, takeNext);
        });
        panel.querySelector('[data-stash-selected]').addEventListener('click', function() { submit(Array.from(selected.values())); });
        panel.querySelector('[data-stash-batch]').addEventListener('click', function() { batch = !batch; selected.clear(); this.setAttribute('aria-pressed', batch ? 'true' : 'false'); paintSelection(); syncButtons(); });
        panel.querySelector('[data-stash-take]').addEventListener('click', function() {
            var count = Number(quantity.value);
            if (inspected && Number.isSafeInteger(count) && count > 0 && count <= inspected.quantity)
                submit([{entryId:inspected.entryId,revision:inspected.revision,quantity:count}]);
        });
        panel.querySelector('[data-stash-retry]').addEventListener('click', function() {
            if (itemUse.debugState().state === 'needs_reconcile') itemUse.reconcile();
            else if (page && page.pendingOperationId) itemUse.resumeStash(page.pendingOperationId, function() { load(page.offset); });
            syncButtons();
        });
        var timer = setInterval(function() { if (!alive || view._destroyed) { clearInterval(timer); if (alive) close(); return; } syncButtons(); }, 250);
        focus.activate({opener:focusBefore}); load(0);
        return true;
    }
    return {open:open};
});
