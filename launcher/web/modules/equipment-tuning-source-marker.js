/** Stable authority-source markers for Equipment Tuning entry surfaces. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.EquipmentTuningSourceMarker = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function restore(node) {
        var base = node.getAttribute('data-tuning-source-base-label');
        node.classList.remove(
            'equipment-conversion-source',
            'equipment-tuning-authority-source'
        );
        node.removeAttribute('data-tuning-source-role');
        node.removeAttribute('aria-current');
        if (!base) return;
        node.setAttribute('aria-label', base);
        node.removeAttribute('data-tuning-source-base-label');
    }

    function mark(node, conversion) {
        var base = node.getAttribute('aria-label') || '当前装备';
        node.classList.add('equipment-tuning-authority-source');
        if (conversion) node.classList.add('equipment-conversion-source');
        node.setAttribute('data-tuning-source-base-label', base);
        node.setAttribute('data-tuning-source-role', conversion ? 'exchange' : 'source');
        node.setAttribute('aria-current', 'true');
        node.setAttribute(
            'aria-label',
            base + '，当前调制装备' + (conversion ? '，用于交换' : '')
        );
        return node;
    }

    function projectInventory(root, state) {
        if (!root) return null;
        var nodes = root.querySelectorAll('.inventory-slot-card');
        for (var i = 0; i < nodes.length; i++) restore(nodes[i]);
        var source = state && state.source;
        if (!source || source.sourceKind !== 'inventory') return null;
        for (var j = 0; j < nodes.length; j++) {
            if (Number(nodes[j].getAttribute('data-physical-slot'))
                    === Number(source.slot)) {
                return mark(nodes[j], state.operation === 'convert');
            }
        }
        return null;
    }

    function captureLoadoutDisabled(node) {
        if (node.getAttribute('data-tuning-source-disabled-owner') === 'true') return;
        node.setAttribute('data-tuning-source-disabled-owner', 'true');
        node.setAttribute(
            'data-tuning-source-base-disabled',
            node.disabled ? 'true' : 'false'
        );
        node.setAttribute(
            'data-tuning-source-base-aria-disabled',
            node.hasAttribute('aria-disabled')
                ? String(node.getAttribute('aria-disabled'))
                : '__absent__'
        );
    }

    function restoreLoadoutDisabled(node) {
        if (node.getAttribute('data-tuning-source-disabled-owner') !== 'true') return;
        node.disabled = node.getAttribute('data-tuning-source-base-disabled') === 'true';
        var baseAria = node.getAttribute('data-tuning-source-base-aria-disabled');
        if (baseAria === '__absent__' || baseAria == null) {
            node.removeAttribute('aria-disabled');
        } else {
            node.setAttribute('aria-disabled', baseAria);
        }
        node.removeAttribute('data-tuning-source-disabled-owner');
        node.removeAttribute('data-tuning-source-base-disabled');
        node.removeAttribute('data-tuning-source-base-aria-disabled');
    }

    function projectLoadoutDisabled(node, locked) {
        captureLoadoutDisabled(node);
        var eligible = node.getAttribute('data-slot-kind') !== 'drug'
            && node.getAttribute('data-empty') !== 'true'
            && node.getAttribute('data-blocked') !== 'true';
        var baseDisabled =
            node.getAttribute('data-tuning-source-base-disabled') === 'true';
        node.disabled = baseDisabled || locked || !eligible;
        node.setAttribute('aria-disabled', node.disabled ? 'true' : 'false');
    }

    function projectLoadout(root, slotKey, locked) {
        if (!root) return null;
        var nodes = root.querySelectorAll('.character-build-slot');
        var marked = null;
        for (var i = 0; i < nodes.length; i++) {
            restore(nodes[i]);
            if (slotKey && nodes[i].getAttribute('data-slot-protocol-key') === slotKey) {
                marked = mark(nodes[i], false);
            }
            if (locked === true || locked === false) {
                projectLoadoutDisabled(nodes[i], locked);
            } else {
                restoreLoadoutDisabled(nodes[i]);
            }
        }
        return marked;
    }

    return {
        projectInventory:projectInventory,
        projectLoadout:projectLoadout
    };
});
