#!/usr/bin/env node
'use strict';

// AS2 defines a subclass prototype when its DoInitAction executes. A late base
// class leaves inherited methods absent even when CS6 reports compiler 0/0.
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const {parseSwf} = require('./swf-metadata');
const ROOT = path.resolve(__dirname, '..');
const CLASS_ROOT = path.join(ROOT, 'scripts', '类定义');

function initializerOrder(raw) {
    const signature = raw.toString('ascii', 0, 3);
    const body = signature === 'FWS' ? raw.subarray(8)
        : signature === 'CWS' ? zlib.inflateSync(raw.subarray(8)) : null;
    if (!body || body.length + 8 !== raw.readUInt32LE(4)) throw Error('Invalid SWF body');
    let offset = Math.ceil((5 + (body[0] >> 3) * 4) / 8) + 4;
    const order = new Map();
    while (offset < body.length) {
        if (offset + 2 > body.length) throw Error('Truncated SWF tag');
        const header = body.readUInt16LE(offset); offset += 2;
        const code = header >> 6; let size = header & 63;
        if (size === 63) {
            if (offset + 4 > body.length) throw Error('Truncated SWF tag length');
            size = body.readUInt32LE(offset); offset += 4;
        }
        if (offset + size > body.length) throw Error('SWF tag exceeds body');
        if (code === 59) {
            if (size < 2) throw Error('Truncated class initializer');
            const id = body.readUInt16LE(offset);
            if (order.has(id)) throw Error('Duplicate class initializer');
            order.set(id, order.size);
        }
        if (code === 0) return order;
        offset += size;
    }
    throw Error('Missing SWF End tag');
}

function inspect(file) {
    const raw = fs.readFileSync(file), metadata = parseSwf(raw);
    const order = initializerOrder(raw), classes = new Map(metadata.classes.map(row => [row.fqn, row]));
    const edges = [], errors = [];
    for (const row of metadata.classes) {
        if (!/^[\p{L}_$][\p{L}\p{N}_$]*(?:\.[\p{L}_$][\p{L}\p{N}_$]*)*$/u.test(row.fqn))
            throw Error('Invalid class name: ' + row.fqn);
        if (!order.has(row.spriteId)) throw Error('Class has no root initializer: ' + row.fqn);
        const source = path.join(CLASS_ROOT, ...row.fqn.split('.')) + '.as';
        if (!fs.existsSync(source)) {
            if (row.fqn.startsWith('org.flashNight.')) throw Error('Missing project class source: ' + row.fqn);
            continue;
        }
        // Mask strings before comments so URL literals cannot swallow code.
        const text = fs.readFileSync(source, 'utf8').replace(
            /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\/\*[\s\S]*?\*\/|\/\/[^\r\n]*/g,
            value => value.replace(/[^\r\n]/g, ' '));
        const declaration = /\bclass\s+([^\s{]+)\s+extends\s+([^\s{]+)/.exec(text);
        if (!declaration) continue;
        if (declaration[1] !== row.fqn) throw Error('Class source identity differs: ' + row.fqn);
        const name = declaration[2];
        let candidates, declared;
        if (name.includes('.')) declared = [name];
        else {
            const imports = [...text.matchAll(/^\s*import\s+([^\s;]+)\s*;?/gm)].map(match => match[1]);
            const local = row.fqn.slice(0, row.fqn.lastIndexOf('.') + 1) + name;
            declared = [...new Set([local, ...imports.map(ref => ref.endsWith('.*')
                ? ref.slice(0, -1) + name : ref.endsWith('.' + name) ? ref : '')])]
                .filter(Boolean);
        }
        candidates = declared.filter(ref => classes.has(ref));
        if (candidates.length > 1) throw Error('Ambiguous parent class: ' + row.fqn);
        if (!candidates.length) {
            const projectParent = declared.find(ref => ref.startsWith('org.flashNight.')
                && fs.existsSync(path.join(CLASS_ROOT, ...ref.split('.')) + '.as'));
            if (name.startsWith('org.flashNight.') || projectParent)
                throw Error('Project parent missing from loader: ' + (projectParent || name));
            continue; // Flash built-ins and external native classes are not loader definitions.
        }
        const parent = classes.get(candidates[0]);
        const edge = {child: row.fqn, parent: parent.fqn,
            childInitOrder: order.get(row.spriteId), parentInitOrder: order.get(parent.spriteId)};
        edges.push(edge);
        if (edge.parentInitOrder >= edge.childInitOrder) errors.push(edge);
    }
    return {schema: 'cf7-as2-inheritance-order.v1', classDefinitions: metadata.classes.length,
        inheritanceEdges: edges.length, errors};
}

if (require.main === module) {
    try {
        let file = path.join(ROOT, 'scripts', 'asLoader.swf');
        const args = process.argv.slice(2);
        for (let index = 0; index < args.length; index++) {
            if (args[index] !== '--swf' || !args[index + 1]) throw Error('Usage: check-as2-inheritance-order.js [--swf file]');
            file = path.resolve(ROOT, args[++index]);
        }
        const result = inspect(file); console.log(JSON.stringify(result, null, 2));
        if (result.errors.length) process.exitCode = 1;
    } catch (error) { console.error(error.message); process.exitCode = 1; }
}
module.exports = {inspect, initializerOrder};
