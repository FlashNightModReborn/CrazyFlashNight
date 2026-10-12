"use strict";
const assert = require("assert"), fs = require("fs"), os = require("os"), path = require("path"), zlib = require("zlib");
const { parseSwf, scanSwf, auditOwnership } = require("./swf-metadata");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "cfn-swf-metadata-"));
let tests = 0;
function check(name, body) { body(); tests++; console.log("PASS " + name); }
function word(n) { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; }
function tag(code, body) {
    if (body.length < 63) return Buffer.concat([word((code << 6) | body.length), body]);
    const size = Buffer.alloc(4); size.writeUInt32LE(body.length); return Buffer.concat([word((code << 6) | 63), size, body]);
}
function swf(names = [], imports = [], compressed = false) {
    const tags = [];
    names.forEach((name, i) => {
        const id = i + 1;
        tags.push(tag(39, Buffer.concat([word(id), word(1), word(0)])));
        tags.push(tag(56, Buffer.concat([word(1), word(id), Buffer.from("__Packages." + name + "\0")])));
        tags.push(tag(59, Buffer.concat([word(id), Buffer.from([0])])));
    });
    imports.forEach(url => tags.push(tag(71, Buffer.concat([Buffer.from(url + "\0"), Buffer.from([1, 0]), word(0)]))));
    const body = Buffer.concat([Buffer.from([8, 0, 0, 30, 1, 0]), ...tags, word(0)]);
    const head = Buffer.alloc(8); head.write(compressed ? "CWS" : "FWS"); head[3] = 8; head.writeUInt32LE(body.length + 8, 4);
    return Buffer.concat([head, compressed ? zlib.deflateSync(body) : body]);
}
function write(rel, data) { const p = path.join(tmp, rel); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, data); return p; }
function actionSwf(actions) {
    const body = Buffer.concat([Buffer.from([8, 0, 0, 30, 1, 0]), tag(12, actions), word(0)]);
    const head = Buffer.alloc(8); head.write("FWS"); head[3] = 8; head.writeUInt32LE(body.length + 8, 4);
    return Buffer.concat([head, body]);
}
function fn(name, body, function2 = false) {
    const record = Buffer.concat([Buffer.from(name + "\0"), word(0), ...(function2 ? [Buffer.from([0, 0, 0])] : []), word(body.length)]);
    return Buffer.concat([Buffer.from([function2 ? 0x8e : 0x9b]), word(record.length), record, body]);
}
const loader = "scripts/asLoader.swf", main = "CRAZYFLASHER7MercenaryEmpire.swf", asset = "flashswf/asset.swf";
check("FWS class definitions", () => assert.strictEqual(parseSwf(swf(["org.flashNight.A"])).classes[0].fqn, "org.flashNight.A"));
check("CWS matches FWS definitions", () => assert.deepStrictEqual(parseSwf(swf(["org.flashNight.A"], [], true)).classes, parseSwf(swf(["org.flashNight.A"])).classes));
check("truncated header rejected", () => assert.throws(() => parseSwf(Buffer.from("FWS")), /Truncated/));
check("wrong declared size rejected", () => { const b = swf(); b.writeUInt32LE(999, 4); assert.throws(() => parseSwf(b), /length mismatch/); });
check("truncated tag rejected", () => { const b = swf(); b[b.length-2] = 63; assert.throws(() => parseSwf(b), /Truncated/); });
check("unsupported signature rejected", () => { const b = swf(); b.write("ZWS"); assert.throws(() => parseSwf(b), /Unsupported/); });
check("RSL metadata preserved", () => assert.strictEqual(parseSwf(swf([], ["flashswf/asset.swf"])).imports[0].url, asset));
check("nested function sizes share the metadata scan", () => {
    const inner = fn("inner", Buffer.from([0]), true);
    const r = parseSwf(actionSwf(Buffer.concat([fn("outer", Buffer.concat([inner, Buffer.from([0])])), Buffer.from([0])])));
    assert.strictEqual(r.functions.length, 2);
    assert.strictEqual(r.functions[0].name, "outer");
    assert.strictEqual(r.functions[1].type, "DefineFunction2");
    assert.strictEqual(r.functions[1].codeSize, 1);
});
check("truncated function body rejected", () => {
    const bytes = fn("broken", Buffer.from([0]));
    assert.throws(() => parseSwf(actionSwf(bytes.subarray(0, bytes.length - 1))), /Truncated/);
});
const cache = path.join(tmp, "cache"), file = write(asset, swf(["org.flashNight.A"]));
check("first parse then content hit", () => { assert.strictEqual(scanSwf(file, cache).cacheHit, false); assert.strictEqual(scanSwf(file, cache).cacheHit, true); });
check("artifact change invalidates cache", () => { write(asset, swf(["org.flashNight.B"])); const r=scanSwf(file, cache); assert.strictEqual(r.cacheHit, false); assert.strictEqual(r.classes[0].fqn, "org.flashNight.B"); });
check("valid JSON cache damage is reparsed", () => {
    const r = scanSwf(file, cache), c = path.join(cache, r.parserVersion+"-"+r.sha256+".json");
    const data = JSON.parse(fs.readFileSync(c)); data.classes = []; fs.writeFileSync(c, JSON.stringify(data));
    assert.strictEqual(scanSwf(file, cache).classes.length, 1);
});
write(loader, swf(["org.flashNight.A", "LiteJSON"])); write(main, swf([], [asset]));
check("project class outside loader fails even with identical payload", () => { write(asset, swf(["org.flashNight.A"])); assert(auditOwnership(tmp, [loader,main,asset], cache).errors.some(e=>e.includes("authority"))); });
check("new project class outside loader fails", () => { write(asset, swf(["org.flashNight.New"])); assert(auditOwnership(tmp, [loader,main,asset], cache).errors.some(e=>e.includes("authority"))); });
check("default package loader class protected", () => { write(asset, swf(["LiteJSON"])); assert(auditOwnership(tmp, [loader,main,asset], cache).errors.some(e=>e.includes("authority"))); });
check("resource without classes passes", () => { write(asset, swf()); assert.deepStrictEqual(auditOwnership(tmp, [loader,main,asset], cache).errors, []); });
check("missing RSL fails full closure", () => assert(auditOwnership(tmp, [loader,main], cache).errors.some(e=>e.includes("RSL"))));
check("changed-file check explicitly omits closure", () => { const r=auditOwnership(tmp, [loader,main], cache,{checkImports:false}); assert.deepStrictEqual(r.errors, []); assert.strictEqual(r.closureChecked,false); });
check("missing loader rejected", () => assert.throws(()=>auditOwnership(tmp,[main,asset],cache),/requires/));
check("path outside root rejected", () => assert.throws(()=>auditOwnership(tmp,[loader,main,"../bad.swf"],cache),/escapes/));
console.log("SWF metadata tests: " + tests + " passed");
// Keep the tiny fixture directory on failure; successful fixtures need no cleanup gate.
const resolvedFixture = path.resolve(tmp);
assert.strictEqual(path.dirname(resolvedFixture), path.resolve(os.tmpdir()));
assert(path.basename(resolvedFixture).startsWith("cfn-swf-metadata-"));
fs.rmSync(resolvedFixture, { recursive: true, force: true });
