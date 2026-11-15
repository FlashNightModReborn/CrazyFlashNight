'use strict';
const fs = require('fs'), path = require('path');
const ORDER = ['resident', 'shared', 'boot'];
function readCatalog(root, options = {}) {
    if (options && options.disableCatalog) return null;
    const explicit = options && options.catalogFile ? path.resolve(options.catalogFile) : null;
    const file = explicit || path.join(root, 'tools/asloader-modules.json');
    if (!fs.existsSync(file)) {
        if (explicit) throw Error('Missing loader module catalog: ' + file);
        return null;
    }
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (data.schema !== 'cf7-asloader-modules.v1') throw Error('Invalid loader module catalog');
    const owners = new Map(), files = new Set();
    for (const name of ORDER) {
        const row = data[name];
        if (!row || !Array.isArray(row.classes) || !row.classes.length
            || !/^scripts\/[\w]+\.swf$/.test(row.swf) || files.has(row.swf)) throw Error('Invalid loader module: '+name);
        files.add(row.swf);
        for (const fqn of row.classes) {
            if (typeof fqn !== 'string' || !/^[\p{L}_$][\p{L}\p{N}_$]*(?:\.[\p{L}_$][\p{L}\p{N}_$]*)*$/u.test(fqn)
                || owners.has(fqn)) throw Error('Invalid or duplicate module class: '+fqn);
            owners.set(fqn, row.swf);
        }
    }
    if (data.resident.swf !== 'scripts/asLoader.swf') throw Error('Original RSL entry moved');
    return {data, owners, files:[...files]};
}
function inspectModule(metadata, catalog, name) {
    const row = catalog.data[name], expected = new Set(row.classes), seen = new Set(), errors=[];
    for (const cls of metadata.classes) {
        if (!expected.has(cls.fqn)) errors.push(row.swf+' embeds a foreign/unregistered class: '+cls.fqn);
        if (seen.has(cls.fqn)) errors.push(row.swf+' defines class twice: '+cls.fqn);
        seen.add(cls.fqn);
    }
    for (const fqn of expected) if (!seen.has(fqn)) errors.push(row.swf+' missing owned class: '+fqn);
    if (metadata.imports.length) errors.push(row.swf+' must not import another code RSL');
    for (const fn of metadata.functions) if (fn.codeSize >= 60000) errors.push(row.swf+' oversized function: '+fn.owner);
    return errors;
}
function coreFiles(root, options) {
    const catalog=readCatalog(root, options);
    return ['CRAZYFLASHER7MercenaryEmpire.swf', ...(catalog ? catalog.files : ['scripts/asLoader.swf'])];
}
module.exports={ORDER,readCatalog,inspectModule,coreFiles};
