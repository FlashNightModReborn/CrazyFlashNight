/**
 * Loadout picker slot-grid rendering.
 *
 * Owns the equipped-slot grid projection: structure, focus/selection
 * attributes, owned-card mounting and roving refresh. Slot badges, tuning
 * flags and slot tooltips stay host-injected hooks; authority and transport
 * stay outside. Class prefix and copy are ports; the defaults preserve the
 * character-build vocabulary verbatim.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.LoadoutPickerSlotGrid = api;
        root.LoadoutPickerSlotGrid = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function itemAt(collection, id) {
        return collection && Object.prototype.hasOwnProperty.call(collection, id)
            ? collection[id] : null;
    }

    var DEFAULT_TEXTS = {
        emptyName:'空槽',
        occupiedMeta:'已装备',
        emptyMeta:'点击查看可用候选'
    };
    function noop() { return false; }

    function install(prototype, options) {
        if (!prototype) throw new Error('LoadoutPickerSlotGrid.install requires a view method target');
        options = options || {};
        var classPrefix = typeof options.classPrefix === 'string'
            && options.classPrefix !== '' ? options.classPrefix : 'character-build';
        var texts = {};
        for (var key in DEFAULT_TEXTS) {
            if (!Object.prototype.hasOwnProperty.call(DEFAULT_TEXTS, key)) continue;
            texts[key] = options.texts && typeof options.texts[key] === 'string'
                && options.texts[key] !== '' ? options.texts[key] : DEFAULT_TEXTS[key];
        }
        var hooks = {
            releaseGrid:typeof options.releaseGrid === 'function' ? options.releaseGrid : noop,
            projectSlot:typeof options.projectSlot === 'function' ? options.projectSlot : noop,
            bindSlotTooltip:typeof options.bindSlotTooltip === 'function'
                ? options.bindSlotTooltip : noop,
            decorateSlot:typeof options.decorateSlot === 'function' ? options.decorateSlot : noop
        };

        prototype._renderSlotGroup = function(grid, definitions, collection, kind, roving) {
            var activeElement = this._document.activeElement;
            var restoreFocus = !!(activeElement && grid.contains(activeElement));
            hooks.releaseGrid(this, grid);
            var fragment = this._document.createDocumentFragment();
            for (var i = 0; i < definitions.length; i++) {
                var definition = definitions[i];
                var item = itemAt(collection, definition.id);
                var key = kind + ':' + definition.id;
                var slot = this._document.createElement('button');
                slot.type = 'button';
                slot.className = classPrefix + '-slot';
                slot.setAttribute('role', 'gridcell');
                slot.setAttribute('data-roving-key', key);
                slot.setAttribute('data-slot-id', definition.id);
                slot.setAttribute('data-slot-protocol-key', definition.id);
                slot.setAttribute('data-slot-kind', kind);
                slot.setAttribute('data-empty', item ? 'false' : 'true');
                hooks.projectSlot(this, slot, item, definition);
                slot.setAttribute('data-focus-label', definition.label);
                slot.setAttribute('data-focus-name', item ? item.name : texts.emptyName);
                slot.setAttribute('aria-selected', key === this._selectedSlotKey ? 'true' : 'false');
                if (item && item.blocked) slot.setAttribute('data-blocked', 'true');
                var meta = item ? item.meta || item.type || texts.occupiedMeta : texts.emptyMeta;
                slot.setAttribute('data-focus-meta', meta);
                var card = this._renderOwnedSlot(definition.label, {
                    occupied:!!item,
                    physicalSlot:Number.isFinite(Number(definition.physicalSlot))
                        ? Number(definition.physicalSlot) : i,
                    item:item && item.presentation || {}
                }, {iconHtml:this._iconHtml, allowDiscard:false, tagName:'span'});
                card.classList.add(classPrefix + '-slot-card');
                var ariaLabel = card.getAttribute('aria-label');
                if (definition.drugMeta) {
                    var drugMeta = definition.drugMeta;
                    ariaLabel += '，第 ' + (Number(drugMeta.bank) + 1)
                        + ' 组，通道 ' + (Number(drugMeta.lane) + 1)
                        + '，按键 ' + String(drugMeta.keyLabel || '未绑定')
                        + (drugMeta.active ? '，当前组' : '，备用组')
                        + (drugMeta.ready ? '，冷却就绪' : '，冷却中');
                }
                slot.setAttribute('aria-label', ariaLabel);
                card.setAttribute('aria-hidden', 'true');
                slot.appendChild(card);
                if (item) hooks.bindSlotTooltip(
                    this, slot, key, definition.label, item.presentation || {}, kind, definition.id);
                var label = this._document.createElement('span');
                label.className = classPrefix + '-slot-label';
                label.textContent = definition.label;
                slot.appendChild(label);
                hooks.decorateSlot(this, slot, kind, definition.id);
                fragment.appendChild(slot);
            }
            grid.innerHTML = '';
            grid.appendChild(fragment);
            roving.refresh({
                preferredKey:this._activeSlotKey.indexOf(kind + ':') === 0 ? this._activeSlotKey : '',
                focus:restoreFocus
            });
            return true;
        };
        return prototype;
    }

    return {install:install};
});
