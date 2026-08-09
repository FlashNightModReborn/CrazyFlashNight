#!/usr/bin/env node
"use strict";

const inventory = require("./generate-shipped-audio-assets.js");

try {
    if (process.argv.length !== 2) throw new Error("check-shipped-audio-assets.js accepts no arguments");
    const result = inventory.checkManifest();
    process.stdout.write("shipped audio inventory check passed; bytes=" + result.bytes + "; sha256=" + result.sha256 + "\n");
} catch (error) {
    process.stderr.write("shipped audio inventory check failed: " + (error && error.message ? error.message : String(error)).replace(/[\r\n]+/g, " ") + "\n");
    process.exitCode = 1;
}
