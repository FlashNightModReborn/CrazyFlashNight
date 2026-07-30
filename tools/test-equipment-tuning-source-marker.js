#!/usr/bin/env node
'use strict';

const assert = require('assert');
const Marker = require(
    '../launcher/web/modules/equipment-tuning-source-marker.js');

class ClassList {
    constructor(node) {
        this.node = node;
        this.values = new Set(String(node.className || '').split(/\s+/).filter(Boolean));
    }
    add(...names) { names.forEach(name => this.values.add(name)); this.sync(); }
    remove(...names) { names.forEach(name => this.values.delete(name)); this.sync(); }
    contains(name) { return this.values.has(name); }
    sync() { this.node.className = Array.from(this.values).join(' '); }
}

class Node {
    constructor(className, attributes) {
        this.className = className;
        this.attributes = Object.assign({}, attributes);
        this.classList = new ClassList(this);
        this.disabled = false;
    }
    getAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name)
            ? this.attributes[name] : null;
    }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    removeAttribute(name) { delete this.attributes[name]; }
    hasAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name);
    }
}

function root(inventory, loadout) {
    return {
        querySelectorAll(selector) {
            if (selector === '.inventory-slot-card') return inventory || [];
            if (selector === '.character-build-slot') return loadout || [];
            return [];
        }
    };
}

let passed = 0;
function test(name, fn) {
    fn();
    passed += 1;
    console.log('PASS ' + name);
}

test('inventory marker follows authority source, not transient selection', () => {
    const first = new Node('inventory-slot-card workbench-source-selected', {
        'data-physical-slot':'3',
        'aria-label':'背包槽位 3'
    });
    const second = new Node('inventory-slot-card', {
        'data-physical-slot':'8',
        'aria-label':'背包槽位 8'
    });
    const host = root([first, second]);

    Marker.projectInventory(host, {
        source:{sourceKind:'inventory', slot:8},
        operation:'enhance'
    });
    assert.strictEqual(first.classList.contains('workbench-source-selected'), true);
    assert.strictEqual(first.classList.contains('equipment-tuning-authority-source'), false);
    assert.strictEqual(second.classList.contains('equipment-tuning-authority-source'), true);
    assert.strictEqual(second.getAttribute('data-tuning-source-role'), 'source');
    assert.strictEqual(second.getAttribute('aria-current'), 'true');
    assert.strictEqual(second.getAttribute('aria-label'), '背包槽位 8，当前调制装备');

    Marker.projectInventory(host, {
        source:{sourceKind:'inventory', slot:3},
        operation:'convert'
    });
    assert.strictEqual(second.getAttribute('aria-label'), '背包槽位 8');
    assert.strictEqual(second.getAttribute('aria-current'), null);
    assert.strictEqual(second.getAttribute('data-tuning-source-role'), null);
    assert.strictEqual(first.classList.contains('equipment-conversion-source'), true);
    assert.strictEqual(first.getAttribute('data-tuning-source-role'), 'exchange');
    assert.strictEqual(first.getAttribute('aria-label'), '背包槽位 3，当前调制装备，用于交换');
});

test('loadout projection owns only its temporary disabled state and restores exact bases', () => {
    const weapon = new Node('character-build-slot', {
        'data-slot-protocol-key':'weapon',
        'data-slot-kind':'weapon',
        'aria-label':'主武器'
    });
    const drug = new Node('character-build-slot', {
        'data-slot-protocol-key':'drug',
        'data-slot-kind':'drug',
        'aria-label':'药剂'
    });
    const empty = new Node('character-build-slot', {
        'data-slot-protocol-key':'empty',
        'data-slot-kind':'weapon',
        'data-empty':'true',
        'aria-label':'空槽'
    });
    const blocked = new Node('character-build-slot', {
        'data-slot-protocol-key':'blocked',
        'data-slot-kind':'weapon',
        'data-blocked':'true',
        'aria-label':'锁定槽'
    });
    const originalDisabled = new Node('character-build-slot', {
        'data-slot-protocol-key':'original',
        'data-slot-kind':'weapon',
        'aria-label':'原始禁用槽',
        'aria-disabled':'true'
    });
    originalDisabled.disabled = true;
    const originalAriaFalse = new Node('character-build-slot', {
        'data-slot-protocol-key':'aria-false',
        'data-slot-kind':'weapon',
        'aria-label':'原始可用槽',
        'aria-disabled':'false'
    });
    const nodes = [
        weapon,
        drug,
        empty,
        blocked,
        originalDisabled,
        originalAriaFalse
    ];
    const host = root([], nodes);

    Marker.projectLoadout(host, 'weapon', true);
    assert.strictEqual(weapon.classList.contains('equipment-tuning-authority-source'), true);
    assert.strictEqual(weapon.getAttribute('data-tuning-source-role'), 'source');
    assert.strictEqual(weapon.getAttribute('aria-label'), '主武器，当前调制装备');
    assert.strictEqual(weapon.disabled, true);
    assert.strictEqual(drug.disabled, true);
    assert(nodes.every(node =>
        node.getAttribute('data-tuning-source-disabled-owner') === 'true'));

    Marker.projectLoadout(host, 'weapon', false);
    assert.strictEqual(weapon.disabled, false);
    assert.strictEqual(drug.disabled, true);
    assert.strictEqual(empty.disabled, true);
    assert.strictEqual(blocked.disabled, true);
    assert.strictEqual(originalDisabled.disabled, true);
    assert.strictEqual(originalAriaFalse.disabled, false);

    Marker.projectLoadout(host, '', null);
    assert.strictEqual(weapon.classList.contains('equipment-tuning-authority-source'), false);
    assert.strictEqual(weapon.getAttribute('aria-label'), '主武器');
    assert.strictEqual(weapon.getAttribute('aria-current'), null);
    assert.strictEqual(weapon.getAttribute('data-tuning-source-role'), null);
    assert.strictEqual(weapon.disabled, false);
    assert.strictEqual(weapon.getAttribute('aria-disabled'), null);
    assert.strictEqual(drug.disabled, false);
    assert.strictEqual(drug.getAttribute('aria-disabled'), null);
    assert.strictEqual(empty.disabled, false);
    assert.strictEqual(blocked.disabled, false);
    assert.strictEqual(originalDisabled.disabled, true);
    assert.strictEqual(originalDisabled.getAttribute('aria-disabled'), 'true');
    assert.strictEqual(originalAriaFalse.disabled, false);
    assert.strictEqual(originalAriaFalse.getAttribute('aria-disabled'), 'false');
    assert(nodes.every(node =>
        node.getAttribute('data-tuning-source-disabled-owner') === null
        && node.getAttribute('data-tuning-source-base-disabled') === null
        && node.getAttribute('data-tuning-source-base-aria-disabled') === null));
});

console.log('equipment tuning source marker: ' + passed + ' tests passed');
