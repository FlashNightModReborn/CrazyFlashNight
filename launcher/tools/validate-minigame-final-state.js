#!/usr/bin/env node
"use strict";

var fs = require("fs");
var path = require("path");

var ROOT = path.resolve(__dirname, "..");
var LEGACY_FILES = [
    path.join(ROOT, "web/modules/lockbox-core.js"),
    path.join(ROOT, "web/modules/lockbox-generator.js"),
    path.join(ROOT, "web/modules/lockbox-solver.js"),
    path.join(ROOT, "web/modules/lockbox-audio.js"),
    path.join(ROOT, "web/modules/lockbox-panel.js")
];

var TEXT_EXTS = {
    ".js": true,
    ".css": true,
    ".html": true,
    ".cs": true,
    ".md": true
};

var FORBIDDEN_TEXT = [
    { label: "legacy flat Lockbox path", pattern: /modules\/lockbox-(core|generator|solver|panel|audio)\.js/g },
    { label: "legacy session command", pattern: /\b(lockbox_session|pinalign_session)\b/g }
];

var FORBIDDEN_SHARED_CLASSES = /\b(lockbox-header|lockbox-header-right|lockbox-main|lockbox-side-pane|lockbox-side-section|lockbox-side-title|lockbox-side-title-toggle|lockbox-chrome-btn|lockbox-phase-badge|lockbox-close-btn|lockbox-kicker|lockbox-title)\b/g;

function walk(dir, out) {
    var entries = fs.readdirSync(dir, { withFileTypes: true });
    var i;
    for (i = 0; i < entries.length; i += 1) {
        var full = path.join(dir, entries[i].name);
        if (entries[i].isDirectory()) {
            if (entries[i].name === ".git" || entries[i].name === "node_modules") continue;
            walk(full, out);
        } else {
            out.push(full);
        }
    }
}

function shouldRead(file) {
    return !!TEXT_EXTS[path.extname(file).toLowerCase()];
}

function rel(file) {
    return path.relative(ROOT, file).replace(/\\/g, "/");
}

function main() {
    var failures = [];
    var i;
    for (i = 0; i < LEGACY_FILES.length; i += 1) {
        if (fs.existsSync(LEGACY_FILES[i])) {
            failures.push("legacy file still exists: " + rel(LEGACY_FILES[i]));
        }
    }

    var files = [];
    walk(ROOT, files);
    for (i = 0; i < files.length; i += 1) {
        if (!shouldRead(files[i])) continue;
        if (rel(files[i]) === "tools/validate-minigame-final-state.js") continue;
        var text = fs.readFileSync(files[i], "utf8");
        var j;
        for (j = 0; j < FORBIDDEN_TEXT.length; j += 1) {
            var match = text.match(FORBIDDEN_TEXT[j].pattern);
            if (match) {
                failures.push(rel(files[i]) + ": " + FORBIDDEN_TEXT[j].label + " -> " + match[0]);
            }
        }
        if (/web\/modules\/minigames\//.test(rel(files[i]))) {
            var sharedMatch = text.match(FORBIDDEN_SHARED_CLASSES);
            if (sharedMatch) {
                failures.push(rel(files[i]) + ": legacy shared minigame class -> " + sharedMatch[0]);
            }
        }
    }

    if (failures.length) {
        console.error("[minigame-final-state] failed");
        for (i = 0; i < failures.length; i += 1) console.error(" - " + failures[i]);
        process.exitCode = 1;
        return;
    }

    console.log("[minigame-final-state] ok");
}

main();
