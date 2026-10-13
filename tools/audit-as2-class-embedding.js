#!/usr/bin/env node
"use strict";
const fs = require("fs"), path = require("path"), cp = require("child_process");
const { createRequire } = require("module");
const { scanSwf, auditOwnership } = require("./swf-metadata");
const ROOT = path.resolve(__dirname, "..");

function productionFiles(root) {
    const req = createRequire(path.join(ROOT, "tools/cf7-packer/package.json"));
    const yaml = req("yaml"), match = req("picomatch");
    const config = yaml.parse(fs.readFileSync(path.join(root, "tools/cf7-packer/pack.config.yaml"), "utf8"));
    const files = cp.execFileSync("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"], { cwd: root, maxBuffer: 50 * 1024 * 1024 }).toString("utf8").split("\0").filter(f => /\.swf$/i.test(f));
    return filterProductionFiles(files, config);
}

function filterProductionFiles(files, config) {
    const req = createRequire(path.join(ROOT, "tools/cf7-packer/package.json"));
    const match = req("picomatch");
    const excluded = (config.globalExclude || []).length ? match(config.globalExclude, { dot: true }) : () => false;
    const layers = config.layers.map(layer => ({ source: layer.source.replace(/\\/g, "/").replace(/\/?$/, "/"), root: layer.source === "." || layer.source === "./", include: match(layer.include, { dot: true }), exclude: layer.exclude.length ? match(layer.exclude, { dot: true }) : () => false }));
    return files.filter(file => {
        if (excluded(file)) return false;
        for (const layer of layers) {
            if (!layer.root && !file.startsWith(layer.source)) continue;
            const rel = layer.root ? file : file.slice(layer.source.length);
            if (!layer.include(rel)) continue;
            return !layer.exclude(rel);
        }
        return false;
    });
}

function main() {
    const args = process.argv.slice(2);
    const options = { policy: "production", root: ROOT, cache: path.join(ROOT, "tmp/swf-metadata-cache"), main: "CRAZYFLASHER7MercenaryEmpire.swf", loader: "scripts/asLoader.swf", markers: ["_repairPending", "applyRepairResolved"] };
    for (let i = 0; i < args.length; i++) {
        const a = args[i];
        if (a === "--help" || a === "-h") { console.log("audit-as2-class-embedding.js [--policy production|single-ownership|core-ownership|child-only|dual-build] [--swf path] [--files-json path] [--root path] [--cache-dir path] [--no-cache] [--json] [--report-only]"); return; }
        if (a === "--json") options.json = true;
        else if (a === "--report-only") options.reportOnly = true;
        else if (a === "--no-cache") options.cache = null;
        else if (a === "--no-default-markers") options.markers = [];
        else if (a === "--marker") options.markers.push(args[++i]);
        else if (["--policy", "--root", "--main", "--loader", "--swf", "--files-json", "--cache-dir"].includes(a)) {
            const value = args[++i]; if (!value || value.startsWith("--")) throw new Error("Missing argument: " + a);
            options[{"--files-json":"filesJson","--cache-dir":"cache"}[a] || a.slice(2)] = value;
        } else throw new Error("Unknown argument: " + a);
    }
    options.root = path.resolve(options.root);
    const start = process.hrtime.bigint(); let result;
    if (options.policy === "production" || options.policy === "single-ownership") {
        if (options.main !== "CRAZYFLASHER7MercenaryEmpire.swf" || options.loader !== "scripts/asLoader.swf") throw new Error("Custom core paths require explicit core-ownership diagnostics");
        const files = options.filesJson ? JSON.parse(fs.readFileSync(options.filesJson === "-" ? 0 : options.filesJson, "utf8")) : options.swf ? [options.main, options.loader, options.swf] : productionFiles(options.root);
        result = auditOwnership(options.root, files, options.cache, { checkImports: !options.swf });
    } else if (["core-ownership", "child-only", "dual-build"].includes(options.policy)) {
        const mainFile = path.resolve(options.root, options.main), loaderFile = path.resolve(options.root, options.loader);
        const m = scanSwf(mainFile, options.cache), l = scanSwf(loaderFile, options.cache); const errors = [];
        if (options.policy === "core-ownership") {
            for (const c of m.classes) if (c.fqn.startsWith("org.flashNight.") || l.classes.some(x => x.fqn === c.fqn)) errors.push("main embeds protected class: " + c.fqn);
            if (!l.classes.some(c => c.fqn.startsWith("org.flashNight."))) errors.push("loader has no project classes");
        } else {
            const zlib = require("zlib");
            const text = file => { const raw=fs.readFileSync(file); return (raw.toString("ascii",0,3)==="CWS" ? zlib.inflateSync(raw.subarray(8)) : raw).toString("utf8"); };
            const mt=text(mainFile),lt=text(loaderFile);
            if(options.policy==="child-only") for(const name of ["SaveManager","ServerManager"]) {
                const marker="__Packages.org.flashNight.neur.Server."+name;
                if(mt.includes(marker)||!lt.includes(marker))errors.push("child-only failed: "+name);
            }
            for(const marker of options.markers) if(!lt.includes(marker)||(options.policy==="dual-build"&&!mt.includes(marker)))errors.push("missing marker: "+marker);
        }
        result={errors,files:2,loaderClasses:l.classes.length};
    } else throw new Error("Invalid policy: " + options.policy);
    result.policy = options.policy; result.milliseconds = Number(process.hrtime.bigint() - start) / 1e6;
    if (options.json) console.log(JSON.stringify(result, null, 2));
    else { console.log("AS2 class ownership: " + JSON.stringify(result)); }
    if (result.errors.length && !options.reportOnly) process.exitCode = 1;
}
module.exports = { productionFiles, filterProductionFiles, auditOwnership };
if (require.main === module) { try { main(); } catch (e) { console.error(e.message); process.exitCode = 1; } }
