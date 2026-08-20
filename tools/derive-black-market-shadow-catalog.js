#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { loadItemMeta } = require("./lib/item-icons.js");

const ROOT = path.resolve(__dirname, "..");
const ITEM_LIST = path.join(ROOT, "data", "items", "list.xml");
const ICON_MANIFEST = path.join(ROOT, "launcher", "web", "icons", "manifest.json");
const ICON_ROOT = path.dirname(ICON_MANIFEST);
const OUTPUT = path.join(ROOT, "launcher", "web", "data", "black-market-shadow-catalog.v1.json");
const CHECK = process.argv.indexOf("--check") >= 0;

function fail(message) {
    throw new Error(message);
}

function readText(file) {
    return fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "");
}

function sha256Bytes(value) {
    return crypto.createHash("sha256").update(value).digest("hex");
}

function sha256File(file) {
    return sha256Bytes(fs.readFileSync(file));
}

function decodeXmlText(value) {
    return String(value || "")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, "\"")
        .replace(/&apos;/g, "'")
        .replace(/&amp;/g, "&");
}

function childText(xml, tagName) {
    const match = new RegExp("<" + tagName + ">\\s*([\\s\\S]*?)\\s*</" + tagName + ">").exec(xml || "");
    return match ? decodeXmlText(match[1].trim()) : "";
}

function frameIconUri(entry, frameNumber) {
    if (!entry || typeof entry !== "object") return null;
    const direct = entry["f" + frameNumber];
    if (typeof direct === "string" && direct) return direct;
    const sequences = [entry.timelineFrames, entry.frames];
    for (const sequence of sequences) {
        if (!Array.isArray(sequence)) continue;
        for (const frame of sequence) {
            if (frame && Number(frame.frame) === frameNumber && typeof frame.uri === "string" && frame.uri) {
                return frame.uri;
            }
        }
    }
    return null;
}

function resolveIconFile(iconUri) {
    if (typeof iconUri !== "string" || !iconUri) return null;
    const iconFile = path.resolve(ICON_ROOT, iconUri);
    const relative = path.relative(path.resolve(ICON_ROOT), iconFile);
    if (!relative || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)) return null;
    return iconFile;
}

function webpDeclaresAlpha(iconUri) {
    const iconFile = resolveIconFile(iconUri);
    if (!iconFile || path.extname(iconFile).toLowerCase() !== ".webp" || !fs.existsSync(iconFile)) return false;
    const bytes = fs.readFileSync(iconFile);
    if (bytes.length < 20 || bytes.toString("ascii", 0, 4) !== "RIFF"
            || bytes.toString("ascii", 8, 12) !== "WEBP" || bytes.readUInt32LE(4) + 8 !== bytes.length) return false;
    let offset = 12;
    while (offset + 8 <= bytes.length) {
        const chunk = bytes.toString("ascii", offset, offset + 4);
        const size = bytes.readUInt32LE(offset + 4);
        const payload = offset + 8;
        const end = payload + size;
        if (end > bytes.length) return false;
        if (chunk === "ALPH") return true;
        if (chunk === "VP8X" && size >= 10 && (bytes[payload] & 0x10) !== 0) return true;
        if (chunk === "VP8L" && size >= 5 && bytes[payload] === 0x2f) {
            const headerBits = bytes.readUInt32LE(payload + 1);
            return ((headerBits >>> 28) & 1) === 1;
        }
        offset = end + (size & 1);
    }
    return false;
}

function selectIconFrame(entry, category) {
    const first = frameIconUri(entry, 1);
    if (category !== "material" && category !== "consumable") {
        return { uri: first, frame: first ? "f1" : null, role: first ? "inventory-icon-proxy" : null,
            backgroundNeutral: false, hiddenColorMode: "proxy",
            rejectReason: first ? null : "missing_icon_manifest_entry" };
    }

    // IconBakeTask 的现役契约：f1=背包图标，f2=掉落物。黑市隐藏态不得显示 f1 的品质底色。
    const second = frameIconUri(entry, 2);
    if (second) {
        if (!webpDeclaresAlpha(second)) {
            return { uri: null, frame: null, role: null, backgroundNeutral: false, hiddenColorMode: null,
                rejectReason: "drop_frame_without_alpha" };
        }
        return { uri: second, frame: "f2", role: "drop-item-frame", backgroundNeutral: true,
            hiddenColorMode: "source", rejectReason: null };
    }
    if (first) {
        return { uri: first, frame: "f1", role: "neutralized-single-frame", backgroundNeutral: false,
            hiddenColorMode: "monochrome", rejectReason: null };
    }
    return { uri: null, frame: null, role: null, backgroundNeutral: false, hiddenColorMode: null,
        rejectReason: "missing_icon_manifest_entry" };
}

function classify(meta) {
    if (meta.type === "武器" || meta.type === "防具") return "equipment";
    if (meta.use === "材料" || (meta.type === "收集品" && meta.use !== "情报")) return "material";
    if (meta.type === "消耗品" && meta.use !== "货币") return "consumable";
    return null;
}

function mechanicalRejectReason(meta, category, price, iconSelection) {
    if (meta.use === "货币") return "currency_or_growth_value";
    if (meta.use === "情报") return "intelligence";
    if (!category) return "unsupported_category";
    if (!Number.isSafeInteger(price) || price <= 0) return "nonpositive_or_invalid_price";
    if (iconSelection.rejectReason) return iconSelection.rejectReason;
    if (!iconSelection.uri) return "missing_icon_manifest_entry";
    const iconFile = resolveIconFile(iconSelection.uri);
    if (!iconFile) return "unsafe_icon_path";
    if (!fs.existsSync(iconFile) || !fs.statSync(iconFile).isFile()) return "missing_icon_file";
    return null;
}

function buildCatalog() {
    const iconManifestBytes = fs.readFileSync(ICON_MANIFEST);
    const iconManifest = JSON.parse(iconManifestBytes.toString("utf8").replace(/^\uFEFF/, ""));
    const itemMeta = loadItemMeta(ROOT, fail);
    const entries = [];
    const rejectedByReason = {};
    const mechanicallyRenderableByCategory = { equipment: 0, material: 0, consumable: 0 };

    Object.keys(itemMeta).sort((a, b) => a.localeCompare(b, "zh-CN")).forEach((name) => {
        const meta = itemMeta[name];
        const price = Number(childText(meta.raw, "price"));
        const category = classify(meta);
        const iconKey = meta.icon || meta.name;
        const iconSelection = selectIconFrame(iconManifest[iconKey], category);
        const rejectReason = mechanicalRejectReason(meta, category, price, iconSelection);
        const mechanicallyRenderable = rejectReason === null;
        if (mechanicallyRenderable) mechanicallyRenderableByCategory[category] += 1;
        else rejectedByReason[rejectReason] = (rejectedByReason[rejectReason] || 0) + 1;

        entries.push({
            id: sha256Bytes(meta.source + "\0" + meta.name).slice(0, 24),
            name: meta.name,
            displayName: meta.displayname || meta.name,
            type: meta.type || "",
            use: meta.use || "",
            actionType: meta.actiontype || "",
            category,
            subclass: meta.use || meta.type || "unknown",
            source: "data/items/" + meta.source,
            price: Number.isSafeInteger(price) ? price : null,
            saleValue: Number.isSafeInteger(price) && price > 0 ? Math.floor(price * 0.25) : null,
            iconKey,
            iconUri: iconSelection.uri ? "icons/" + iconSelection.uri : null,
            iconFrame: iconSelection.frame,
            iconFrameRole: iconSelection.role,
            backgroundNeutral: iconSelection.backgroundNeutral,
            hiddenColorMode: iconSelection.hiddenColorMode,
            assetKind: category === "equipment" ? "icon-proxy" : category ? "canonical-icon" : null,
            mechanicallyRenderable,
            mechanicalRejectReason: rejectReason,
            productionEligibility: "review"
        });
    });

    const digestPayload = JSON.stringify(entries);
    return {
        schemaVersion: "black-market-shadow-catalog.v1",
        shadowOnly: true,
        containsPrivateIdentity: true,
        productionEligibilityDefault: "review",
        source: {
            itemList: "data/items/list.xml",
            itemListSha256: sha256File(ITEM_LIST),
            iconManifest: "launcher/web/icons/manifest.json",
            iconManifestSha256: sha256Bytes(iconManifestBytes)
        },
        catalogDigest: sha256Bytes(digestPayload),
        stats: {
            totalItems: entries.length,
            mechanicallyRenderable: entries.filter((entry) => entry.mechanicallyRenderable).length,
            mechanicallyRejected: entries.filter((entry) => !entry.mechanicallyRenderable).length,
            mechanicallyRenderableByCategory,
            rejectedByReason
        },
        entries
    };
}

function main() {
    const output = JSON.stringify(buildCatalog(), null, 2) + "\n";
    if (CHECK) {
        if (!fs.existsSync(OUTPUT)) fail("black-market shadow catalog is missing");
        const current = readText(OUTPUT);
        if (current !== output) fail("black-market shadow catalog is stale; run node tools/derive-black-market-shadow-catalog.js");
        console.log("[black-market-catalog] check ok");
        return;
    }
    fs.mkdirSync(path.dirname(OUTPUT), { recursive: true });
    fs.writeFileSync(OUTPUT, output, "utf8");
    const catalog = JSON.parse(output);
    console.log("[black-market-catalog] wrote " + path.relative(ROOT, OUTPUT).replace(/\\/g, "/"));
    console.log("[black-market-catalog] total=" + catalog.stats.totalItems
        + " renderable=" + catalog.stats.mechanicallyRenderable
        + " rejected=" + catalog.stats.mechanicallyRejected
        + " digest=" + catalog.catalogDigest);
}

main();
