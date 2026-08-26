#!/usr/bin/env node
/*
 * 黑市匿名视觉池清单生成器（版本化生成器，产物可复验重建）
 *
 * 设计前提（2026-08-26 与设计者确认）：盲盒鉴定是经济投送点，覆泥母版故意留出
 * 特征点让玩家"能猜、但猜不准价"。注释全量内容（描述/属性/获取方式）不在此清单内——
 * 运行时由面板经 Host → AS2 `blackmarketTooltip` 问游戏权威数据源要（与商店/情报同一套
 * PanelTooltip + buildItemRichHtml 呈现），本清单只保留"渲染 + 身份绑定"最小字段，
 * 避免派生副本随平衡性调整漂移。
 *
 * 产物 visual-pool-manifest.js 每条字段（刻意短键，紧凑）：
 *   u=图标路径  h=hiddenColorMode  g=同组配对分组键（subclass 粗分类）
 *   n=名称  t=类型  sc=小类  p=目录价  s=回售价  at=actionType  e=释放资格（默认放行；"banned" 扣下）
 *   k=内部名（AS2 Web物品注释HTML 的查询键，与 displayName 同源同身份级）
 * 像素与名称/目录价可见；购买前快照仍零身份字段（bm22/bm-ui2/bm24 锁死）。
 *
 * 用法：
 *   node tools/bake-black-market-visual-pool.js           # 生成
 *   node tools/bake-black-market-visual-pool.js --check   # 复验产物与目录推导一致
 */
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const CATALOG = path.join(ROOT, "tools", "fixtures", "blackmarket", "black-market-shadow-catalog.v1.json");
const OUT = path.join(ROOT, "launcher", "web", "modules", "minigames", "blackmarket", "visual", "visual-pool-manifest.js");

const HEADER = `/*
 * GENERATED FILE — 由 tools/bake-black-market-visual-pool.js 生成，禁止手改。
 * 黑市视觉池：全目录渲染资格 + 身份绑定清单。像素允许被认出（能猜、猜不准价）；
 * 名称/目录价只随揭晓/hover 释放；购买前快照零身份字段。注释全文（描述/属性/获取方式）
 * 不在此文件——运行时由 AS2 权威数据源经 blackmarketTooltip 提供。
 */
`;

function deriveEntries(catalog) {
    return catalog.entries
        .filter((e) => e && e.mechanicallyRenderable === true && typeof e.iconUri === "string"
            && /^icons\/[0-9a-f]+_\d+\.webp$/.test(e.iconUri)
            && fs.existsSync(path.join(ROOT, "launcher", "web", e.iconUri)))
        .sort((a, b) => (a.iconUri < b.iconUri ? -1 : 1))
        .map((e) => ({
            u: e.iconUri,
            h: typeof e.hiddenColorMode === "string" ? e.hiddenColorMode : "proxy",
            g: String(e.subclass || e.use || e.type || "?"),
            n: String(e.displayName || e.name || ""),
            t: String(e.type || ""),
            sc: String(e.subclass || e.use || ""),
            p: Number(e.price) || 0,
            s: Number(e.saleValue) || 0,
            at: String(e.actionType || ""),
            e: String(e.productionEligibility || "review"),
            k: String(e.name || ""),
        }));
}

function renderModule(entries) {
    for (const [i, entry] of entries.entries()) {
        for (const key of ["u", "h", "g", "n", "t", "sc", "p", "s", "at", "e", "k"]) {
            if (!(key in entry)) throw new Error(`entry ${i} missing key ${key}`);
        }
        if (!entry.n) throw new Error(`entry ${i} (${entry.u}) has empty display name`);
    }
    const body = JSON.stringify({
        schemaVersion: "black-market-visual-pool.v4",
        identityBoundary: "anonymous-synthetic-no-catalog.v2",
        note: "购买前快照零身份字段；揭晓/hover 释放是 2026-08-26 确认的测试版产品决策；注释全文走运行时 AS2 权威通道",
        entries,
    });
    return HEADER
        + `(function(root, factory) {
    if (typeof module === "object" && module.exports) module.exports = factory();
    else root.BlackMarketVisualPool = factory();
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";
    return ${body};
});
`;
}

function main() {
    const checkOnly = process.argv.includes("--check");
    const catalog = JSON.parse(fs.readFileSync(CATALOG, "utf8"));
    const entries = deriveEntries(catalog);
    if (entries.length < 100) throw new Error(`eligible entries suspiciously few: ${entries.length}`);
    const expected = renderModule(entries);

    if (checkOnly) {
        const onDisk = fs.existsSync(OUT) ? fs.readFileSync(OUT, "utf8") : "";
        if (onDisk !== expected) {
            throw new Error("visual-pool-manifest.js 与目录推导不一致，请重跑 bake-black-market-visual-pool.js");
        }
        console.log(`[black-market-visual-pool] check ok (${entries.length} entries)`);
        return;
    }

    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, expected, "utf8");
    console.log(`[black-market-visual-pool] manifest baked: ${entries.length} entries -> ${path.relative(ROOT, OUT)}`);
}

main();
