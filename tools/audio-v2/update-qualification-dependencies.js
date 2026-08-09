#!/usr/bin/env node
"use strict";

// Mechanical maintainer for the source-reviewed Audio v2 qualification replay
// closure. The runner never executes this generator; H2 consumes only the
// canonical, byte-addressed manifest it writes.

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..", "..");
const output = "config/audio-v2/qualification-runner-dependencies.v1.json";
const fixed = [
    "launcher/CRAZYFLASHER7MercenaryEmpire.csproj",
    "launcher/src/AssemblyInfo.cs",
    "launcher/THIRD-PARTY-NOTICES.txt",
    "launcher/app.ico",
    "launcher/app.manifest",
    "launcher/contracts/panel-contracts.v2.json",
    "launcher/native/audio_backend_policy.c",
    "launcher/native/audio_backend_policy.h",
    "launcher/native/audio_bridge_v2.h",
    "launcher/native/miniaudio_bridge.c",
    "launcher/native/tests/audio_backend_policy_contract.c",
    "launcher/native/tests/audio_bridge_v2_runtime_contract.c",
    "launcher/packages.lock.json",
    "launcher/tests/Launcher.Tests.csproj",
    "launcher/tests/xunit.runner.json",
    "scripts/类定义/org/flashNight/arki/audio/AudioBridge.as",
    "scripts/类定义/org/flashNight/arki/audio/SoundEffectManager.as",
    "scripts/类定义/org/flashNight/arki/audio/test/AudioBridgeV2Test.as",
    "scripts/类定义/org/flashNight/neur/Server/ServerManager.as",
    "tools/audio-v2/qualification-offline-probe.c",
    "tools/audio-v2/qualification-observer-client.ps1",
    "tools/audio-v2/qualification-observer.js",
    "tools/audio-v2/qualification-runner.js"
];

function walk(relative, select) {
    const directory = path.join(root, relative.split("/").join(path.sep));
    const result = [];
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
        if (["bin", "obj", ".vs", "node_modules"].includes(entry.name)) return;
        if (["native", "packages", "scripts"].includes(entry.name) && relative === "launcher") return;
        const child = relative + "/" + entry.name;
        if (entry.isDirectory()) result.push(...walk(child, select));
        else if (entry.isFile() && select(child)) result.push(child);
    });
    return result;
}

function sha256(bytes) { return crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase(); }
function blob(bytes) {
    return crypto.createHash("sha1").update(Buffer.from("blob " + bytes.length + "\0", "utf8")).update(bytes).digest("hex");
}
function canonical(value) {
    if (Array.isArray(value)) return value.map(canonical);
    if (value && typeof value === "object") {
        const result = {};
        Object.keys(value).sort().forEach((key) => { result[key] = canonical(value[key]); });
        return result;
    }
    return value;
}

const selected = new Set(fixed);
walk("launcher", (relative) => relative.endsWith(".cs")).forEach((relative) => selected.add(relative));
walk("launcher/src/Guardian/Hud/PlayerInfo/Assets", (relative) => /\.(json|svg)$/.test(relative)).forEach((relative) => selected.add(relative));
walk("launcher/tests/Fixtures", (relative) => relative.endsWith(".json")).forEach((relative) => selected.add(relative));
const dependencies = Array.from(selected).sort().map((relative) => {
    const file = path.join(root, relative.split("/").join(path.sep));
    if (!fs.existsSync(file) || !fs.lstatSync(file).isFile()) throw new Error("missing qualification dependency: " + relative);
    const bytes = fs.readFileSync(file);
    if (bytes.length === 0) throw new Error("empty qualification dependency: " + relative);
    return { blobOid: blob(bytes), bytes: bytes.length, path: relative, sha256: sha256(bytes) };
});
const value = {
    closureSha256: sha256(Buffer.from(JSON.stringify(canonical(dependencies), null, 2) + "\n", "utf8")),
    dependencies,
    runnerPath: "tools/audio-v2/qualification-runner.js",
    schema: "cf7.audio-v2.qualification-runner-dependencies.v1"
};
fs.writeFileSync(path.join(root, output.split("/").join(path.sep)), JSON.stringify(canonical(value), null, 2) + "\n", "utf8");
process.stdout.write("updated " + output + " dependencies=" + dependencies.length + " closure=" + value.closureSha256 + "\n");
