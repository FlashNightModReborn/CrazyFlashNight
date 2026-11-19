#!/usr/bin/env node
'use strict';
const path = require('node:path');
const { compile } = require('./tooltip-catalog.cjs');
const root = path.resolve(__dirname, '..');
function verify() {
    return JSON.parse(compile(root).archive);
}
if (require.main === module) {
    const option = process.argv[2];
    if (option && option !== '--check') throw Error('Expected --check');
    verify();
}
module.exports = { verify };
