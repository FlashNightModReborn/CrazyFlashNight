#!/usr/bin/env node
'use strict';

// Exercise the validator against isolated lifecycle declarations. The runtime
// accepts READY_STATIC without a cycle; explicitly declared cycles still need
// a callback, and every gated component must initialize.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const source = fs.readFileSync(path.join(__dirname, 'validate-item-sets.js'), 'utf8');
const gate = '<setGate><effectId>combat</effectId><componentId>head</componentId></setGate>';
const init = '<init><initRoutines>fixture.init</initRoutines></init>';

function validate(lifecycle) {
    let diagnostic = '';
    let status = 0;
    const halted = {};
    const meta = {
        head: {name:'head', type:'防具', use:'头部装备', setId:'fixture', source:'fixture', raw:lifecycle},
        chest: {name:'chest', type:'防具', use:'上装装备', setId:'fixture', source:'fixture', raw:''}
    };
    const catalog = [{id:'fixture', name:'测试套装', order:'1', source:'fixture', raw:
        '<effects><effect_0><id>combat</id><threshold>1</threshold><kind>routine</kind>' +
        '<mode>member_components</mode><prepareRoutine>fixture.prepare</prepareRoutine>' +
        '<components><component_0><id>head</id><slot>头部装备</slot></component_0></components>' +
        '</effect_0></effects>'}];
    try {
        vm.runInNewContext(source, {
            __dirname,
            require(name) {
                if (name === 'path') return path;
                assert.strictEqual(name, './lib/item-icons');
                return {loadItemMeta:()=>meta, loadItemSetMeta:()=>catalog};
            },
            process: {argv:[], stdout:{write(){}}, stderr:{write(s){diagnostic += s;}},
                exit(code){status = code; throw halted;}}
        }, {filename:'validate-item-sets.js'});
    } catch (error) { if (error !== halted) throw error; }
    return {status, diagnostic};
}

function lifecycle(body) { return '<lifecycle><attr_0>' + body + '</attr_0></lifecycle>'; }
assert.strictEqual(validate(lifecycle(gate + init)).status, 0, 'READY_STATIC needs no cycle');
assert.strictEqual(validate(lifecycle(gate + init + '<cycle><cycleRoutines>fixture.tick</cycleRoutines></cycle>')).status, 0);
for (const cycle of ['<cycle></cycle>', '<cycle/>', '<cycle><condition>alive</condition></cycle>']) {
    assert.match(validate(lifecycle(gate + init + cycle)).diagnostic, /declared cycle requires cycleRoutines/);
}
assert.match(validate(lifecycle(gate)).diagnostic, /gated component requires initRoutines/);
assert.match(validate(lifecycle(gate.replace('head', 'missing') + init)).diagnostic, /unknown componentId/);
process.stdout.write('Item-set lifecycle validator: 7 cases passed\n');
