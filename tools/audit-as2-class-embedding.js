#!/usr/bin/env node

var fs = require("fs");
var path = require("path");
var zlib = require("zlib");

var ROOT = path.resolve(__dirname, "..");
var DEFAULT_MAIN = "CRAZYFLASHER7MercenaryEmpire.swf";
var DEFAULT_LOADER = "scripts/asLoader.swf";
var CLASS_MARKERS = [
    "__Packages.org.flashNight.neur.Server.SaveManager",
    "__Packages.org.flashNight.neur.Server.ServerManager"
];

var options = {
    main: DEFAULT_MAIN,
    loader: DEFAULT_LOADER,
    policy: "child-only",
    markers: ["_repairPending", "applyRepairResolved"],
    reportOnly: false
};

function usage() {
    console.log([
        "Usage: node tools/audit-as2-class-embedding.js [options]",
        "",
        "Options:",
        "  --main <path>              Main SWF path (default: " + DEFAULT_MAIN + ")",
        "  --loader <path>            asLoader SWF path (default: " + DEFAULT_LOADER + ")",
        "  --policy <child-only|dual-build|single-ownership>",
        "                            child-only: main SWF must not embed SaveManager/ServerManager",
        "                            dual-build: main and loader must both contain repair markers",
        "                            single-ownership: main SWF embeds ZERO org.flashNight.*,",
        "                                              and no class is embedded in BOTH SWFs",
        "  --marker <text>            Marker required by policy; may be repeated",
        "  --no-default-markers       Clear default repair markers before adding --marker",
        "  --report-only              Print counts without failing",
        "  -h, --help                 Show this help"
    ].join("\n"));
}

function parseArgs(argv) {
    for (var i = 2; i < argv.length; i++) {
        var arg = argv[i];
        if (arg === "-h" || arg === "--help") {
            usage();
            process.exit(0);
        } else if (arg === "--main") {
            options.main = argv[++i];
        } else if (arg === "--loader") {
            options.loader = argv[++i];
        } else if (arg === "--policy") {
            options.policy = argv[++i];
        } else if (arg === "--marker") {
            options.markers.push(argv[++i]);
        } else if (arg === "--no-default-markers") {
            options.markers = [];
        } else if (arg === "--report-only") {
            options.reportOnly = true;
        } else {
            throw new Error("Unknown argument: " + arg);
        }
    }
    if (options.policy !== "child-only" && options.policy !== "dual-build" && options.policy !== "single-ownership") {
        throw new Error("Invalid --policy: " + options.policy);
    }
    options.markers = options.markers.filter(function(marker, index, arr) {
        return marker && arr.indexOf(marker) === index;
    });
}

function abs(relOrAbs) {
    return path.isAbsolute(relOrAbs) ? relOrAbs : path.join(ROOT, relOrAbs);
}

function loadSwf(relOrAbs) {
    var file = abs(relOrAbs);
    var raw = fs.readFileSync(file);
    var sig = raw.slice(0, 3).toString("ascii");
    if (sig === "CWS") {
        return {
            file: file,
            signature: sig,
            data: Buffer.concat([Buffer.from("FWS"), raw.slice(3, 8), zlib.inflateSync(raw.slice(8))])
        };
    }
    if (sig === "FWS") {
        return { file: file, signature: sig, data: raw };
    }
    throw new Error("Unsupported SWF signature for " + file + ": " + sig);
}

function countNeedle(data, text) {
    var needle = Buffer.from(text, "utf8");
    var count = 0;
    var offset = 0;
    while (true) {
        offset = data.indexOf(needle, offset);
        if (offset < 0) return count;
        count++;
        offset += needle.length;
    }
}

// 枚举一个 SWF 内全部 __Packages.org.flashNight.<FQN> 类名（去前缀、去重、排序）
function extractOrgPackages(data) {
    var text = data.toString("latin1");
    var re = /__Packages\.(org\.flashNight\.[A-Za-z0-9_.$]+)/g;
    var set = {};
    var m;
    while ((m = re.exec(text)) !== null) set[m[1]] = true;
    return Object.keys(set).sort();
}

function auditSingleOwnership(mainSwf, loaderSwf, errors) {
    var mainPkgs = extractOrgPackages(mainSwf.data);
    var loaderPkgs = extractOrgPackages(loaderSwf.data);
    var loaderSet = {};
    loaderPkgs.forEach(function(p) { loaderSet[p] = true; });
    var intersection = mainPkgs.filter(function(p) { return loaderSet[p]; });

    console.log("main:   " + path.relative(ROOT, mainSwf.file) + " (" + mainSwf.signature + ")  org.flashNight classes: " + mainPkgs.length);
    console.log("loader: " + path.relative(ROOT, loaderSwf.file) + " (" + loaderSwf.signature + ")  org.flashNight classes: " + loaderPkgs.length);
    console.log("intersection (embedded in BOTH): " + intersection.length);

    function sample(arr) { return arr.slice(0, 20).join(", ") + (arr.length > 20 ? ", …(+" + (arr.length - 20) + ")" : ""); }

    // 断言 1：主 SWF 不得嵌入任何游戏 class（否则其副本会随首注册胜出 shadow 掉 asLoader 重编版本）
    expect(mainPkgs.length === 0,
        "main SWF embeds " + mainPkgs.length + " org.flashNight class(es) — must be 0 (主时间轴误直引用了游戏 class): " + sample(mainPkgs),
        errors);
    // 断言 2：无 class 同时嵌入两个 SWF（每个 class 恰归属一个 SWF）
    expect(intersection.length === 0,
        intersection.length + " class(es) embedded in BOTH main and loader — must be 0 (双嵌→shadow 风险): " + sample(intersection),
        errors);
    // 断言 3（健全性）：loader 应承载全部游戏 class
    expect(loaderPkgs.length > 0,
        "loader SWF embeds 0 org.flashNight classes — unexpected (asLoader 应是类载体子 SWF)",
        errors);
}

function auditOne(label, swf, markers) {
    var counts = {};
    CLASS_MARKERS.concat(markers).forEach(function(marker) {
        counts[marker] = countNeedle(swf.data, marker);
    });
    console.log(label + ": " + path.relative(ROOT, swf.file) + " (" + swf.signature + ")");
    Object.keys(counts).forEach(function(marker) {
        console.log("  " + marker + ": " + counts[marker]);
    });
    return counts;
}

function expect(condition, message, errors) {
    if (!condition) errors.push(message);
}

function main() {
    parseArgs(process.argv);

    var mainSwf = loadSwf(options.main);
    var loaderSwf = loadSwf(options.loader);
    var errors = [];

    if (options.policy === "single-ownership") {
        auditSingleOwnership(mainSwf, loaderSwf, errors);
        if (errors.length > 0) {
            console.error("AS2 class embedding audit failed (single-ownership):");
            errors.forEach(function(error) { console.error("  - " + error); });
            if (!options.reportOnly) process.exit(1);
        } else {
            console.log("AS2 class embedding audit passed (single-ownership).");
        }
        return;
    }

    var mainCounts = auditOne("main", mainSwf, options.markers);
    var loaderCounts = auditOne("loader", loaderSwf, options.markers);

    if (options.policy === "child-only") {
        CLASS_MARKERS.forEach(function(marker) {
            expect(mainCounts[marker] === 0, "main SWF embeds " + marker, errors);
            expect(loaderCounts[marker] > 0, "loader SWF is missing " + marker, errors);
        });
        options.markers.forEach(function(marker) {
            expect(loaderCounts[marker] > 0, "loader SWF is missing marker " + marker, errors);
        });
    } else {
        options.markers.forEach(function(marker) {
            expect(mainCounts[marker] > 0, "main SWF is missing marker " + marker, errors);
            expect(loaderCounts[marker] > 0, "loader SWF is missing marker " + marker, errors);
        });
    }

    if (errors.length > 0) {
        console.error("AS2 class embedding audit failed:");
        errors.forEach(function(error) {
            console.error("  - " + error);
        });
        if (!options.reportOnly) process.exit(1);
    } else {
        console.log("AS2 class embedding audit passed (" + options.policy + ").");
    }
}

try {
    main();
} catch (err) {
    console.error(err.message || String(err));
    process.exit(1);
}
