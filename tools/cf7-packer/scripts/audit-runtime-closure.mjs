#!/usr/bin/env node
/**
 * 每日包运行时闭包审计。
 *
 * 打包层多数是白名单，历史上漏过 launcher/data/world-lighting 与
 * launcher/web 的三个合成表面页面，导致装机后启动崩溃 / 转场卡死。
 * 本脚本在出 zip 之前核对：
 *   1. 关键运行时文件与 runtime manifest；
 *   2. launcher/web、launcher/data、fonts、launcher/agent-assets 与仓库的差异
 *      （只允许明确列出的开发产物缺失）；
 *   3. 页面 / CSS / JS 里能静态解析出的资源引用；
 *   4. 字体哈希链与转场图片目录清单；
 *   5. flashswf / sounds 的运行时扩展名对比、list.xml 注册项、BGM 曲目与关卡
 *      <Path> 交叉引用（仓库有而包内缺 = 失败；仓库本身也没有 = 告警）。
 *
 * 判定原则：只把「仓库里存在、包里没有」当成打包缺口；数据里引用了仓库
 * 也不存在的旧路径时只告警，避免把既有的数据陈旧问题算到打包头上。
 *
 * 用法：node scripts/audit-runtime-closure.mjs --payload <打包目录> [--repo <仓库根>]
 * 退出码：0 通过；1 有缺口；2 参数错误。
 */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const defaultRepo = path.resolve(here, "../../..");

function arg(name, fallback) {
    const i = process.argv.indexOf("--" + name);
    return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const repoRoot = path.resolve(arg("repo", defaultRepo));
const payloadArg = arg("payload", "");
if (!payloadArg) {
    console.error("用法: node scripts/audit-runtime-closure.mjs --payload <打包目录> [--repo <仓库根>]");
    process.exit(2);
}
const payloadRoot = path.resolve(payloadArg);
if (!fs.existsSync(payloadRoot)) {
    console.error("打包目录不存在: " + payloadRoot);
    process.exit(2);
}

const failures = new Map();
function fail(group, message) {
    if (!failures.has(group)) failures.set(group, []);
    failures.get(group).push(message);
}

const warnings = [];
function warn(group, message) {
    warnings.push(group + ": " + message);
}

function walk(root) {
    const out = [];
    if (!fs.existsSync(root)) return out;
    for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
        const full = path.join(root, entry.name);
        if (entry.isDirectory()) out.push(...walk(full));
        else if (entry.isFile()) out.push(full);
    }
    return out;
}

function relFrom(root, file) {
    return path.relative(root, file).split(path.sep).join("/");
}

function sha256(file) {
    return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

function globToRegExp(pattern) {
    let re = "";
    for (let i = 0; i < pattern.length; i++) {
        const c = pattern[i];
        if (c === "*") {
            if (pattern[i + 1] === "*") {
                i++;
                if (pattern[i + 1] === "/") {
                    i++;
                    re += "(?:.*/)?";
                } else {
                    re += ".*";
                }
            } else {
                re += "[^/]*";
            }
        } else if (c === "?") {
            re += "[^/]";
        } else {
            re += c.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
    }
    return new RegExp("^" + re + "$");
}

function matchesAny(relative, patterns) {
    return patterns.some((p) => globToRegExp(p).test(relative));
}

const GLOBAL_JUNK = [
    "**/.DS_Store",
    "**/Thumbs.db",
    "**/*.bak",
    "**/__pycache__/**",
    "**/.vs/**",
    "**/*.log",
    "**/*.obj",
    "**/~$*",
];

function existsInPayload(relative) {
    return fs.existsSync(path.join(payloadRoot, relative.split("/").join(path.sep)));
}

// ── 1. 关键运行时文件 ───────────────────────────────────────────────

const REQUIRED = [
    "CRAZYFLASHER7MercenaryEmpire.exe",
    "CRAZYFLASHER7MercenaryEmpire.swf",
    "CRAZYFLASHER7MercenaryEmpire.bat",
    "Adobe Flash Player 20.exe",
    "config.toml",
    "config.xml",
    "crossdomain.xml",
    "hotkey_guard.exe",
    "launcher/web/bootstrap.html",
    "launcher/web/bootstrap-main.js",
    "launcher/web/overlay.html",
    "launcher/web/scene-transition.html",
    "launcher/web/composition-help.html",
    "launcher/web/composition-intelligence.html",
    "launcher/data/save_repair_dict.json",
    "launcher/data/save_schema.json",
    "launcher/data/guidance-catalog.json",
    "launcher/data/tutorial-journeys.json",
    "launcher/data/scene-transition/catalog.manifest.json",
    "launcher/data/world-lighting/preset.json",
    "launcher/data/world-lighting/render-schedule.json",
    "launcher/agent-assets/lore/public-companion.v1.json",
    "fonts/fonts.xml",
    "fonts/fonts.xsd",
    "sounds/bgm_list.xml",
    "flashswf/portraits/list.xml",
    "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll",
    "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe",
    "runtime/cf7-runtime-manifest.tsv",
];
for (const relative of REQUIRED) {
    if (!existsInPayload(relative)) fail("关键运行时文件缺失", relative);
}

// 运行时状态不得进包：这些文件由游戏/后端按玩家写入，打包会覆盖玩家自己的数据。
const FORBIDDEN = [
    "data/task/agent_tasks.json",
    "data/task/text/agent_text.json",
    "data/rag/npc_state_db.json",
    "data/rag/sync_state.json",
];
for (const relative of FORBIDDEN) {
    if (existsInPayload(relative)) fail("运行时状态不应进包", relative);
}
const ragDir = path.join(payloadRoot, "data", "rag");
if (fs.existsSync(ragDir) && walk(ragDir).length > 0) {
    fail("运行时状态不应进包", "data/rag/ 下仍有 " + walk(ragDir).length + " 个运行时文件");
}

// 动态文件族：新增文件名不需要改审计，但不能整个族为空
function requireNonEmpty(group, relativeDir, filter) {
    const dir = path.join(payloadRoot, relativeDir.split("/").join(path.sep));
    const files = walk(dir).filter((f) => !filter || filter(f));
    if (files.length === 0) fail(group, relativeDir + "/ 为空或不存在");
}
requireNonEmpty("关键运行时文件缺失", "launcher/scripts/dist", (f) => f.endsWith(".js"));
requireNonEmpty("关键运行时文件缺失", "tools/dotnet-runtime", (f) => f.toLowerCase().endsWith(".exe"));
for (const exe of ["pbrain-rapfi-windows-avx2.exe", "pbrain-rapfi-windows-sse.exe"]) {
    if (!existsInPayload("tools/rapfi/" + exe)) fail("关键运行时文件缺失", "tools/rapfi/" + exe);
}

// ── 2. runtime 目录与 manifest ─────────────────────────────────────

const manifestPath = path.join(payloadRoot, "runtime", "cf7-runtime-manifest.tsv");
if (fs.existsSync(manifestPath)) {
    const lines = fs.readFileSync(manifestPath, "utf8").split(/\r?\n/);
    for (const line of lines) {
        const fields = line.split("\t");
        if (fields[0] !== "file" && fields[0] !== "dir") continue;
        const relative = fields[1].replace(/\\/g, "/");
        if (!existsInPayload(relative)) fail("runtime manifest 缺口", relative);
    }
}

const repoRuntime = walk(path.join(repoRoot, "runtime")).map((f) => relFrom(repoRoot, f));
const payloadRuntime = walk(path.join(payloadRoot, "runtime")).map((f) => relFrom(payloadRoot, f));
for (const relative of repoRuntime) {
    if (!payloadRuntime.includes(relative)) fail("runtime 目录与仓库不一致", "缺 " + relative);
}
for (const relative of payloadRuntime) {
    if (!repoRuntime.includes(relative)) fail("runtime 目录与仓库不一致", "多 " + relative);
}

// ── 3. 整目录收的运行时目录：仓库 vs 包 ─────────────────────────────

const PARITY = [
    {
        root: "launcher/web",
        allowMissing: [
            "modules/help.js",
            "dev/**",
            "mockups/**",
            "modules/**/dev/**",
            "modules/**/reference/**",
            "modules/**/README.md",
            "assets/**/README.md",
            "assets/**/_copy_bg.py",
            "assets/**/report.json",
        ],
    },
    { root: "launcher/data", allowMissing: ["dialogue-portraits/**", "doll-portraits/**"] },
    { root: "fonts", allowMissing: ["temporary/**"] },
    { root: "launcher/agent-assets", allowMissing: ["lore/fixtures/**", "lore/*.schema.json"] },
];

for (const rule of PARITY) {
    const repoFiles = walk(path.join(repoRoot, rule.root)).map((f) => relFrom(path.join(repoRoot, rule.root), f));
    const payloadFiles = new Set(
        walk(path.join(payloadRoot, rule.root)).map((f) => relFrom(path.join(payloadRoot, rule.root), f))
    );
    for (const relative of repoFiles) {
        if (payloadFiles.has(relative)) continue;
        if (matchesAny(relative, GLOBAL_JUNK) || matchesAny(relative, rule.allowMissing)) continue;
        fail(rule.root + " 与仓库不一致", "缺 " + relative);
    }
}

// ── 4. 页面 / CSS / JS 资源引用 ─────────────────────────────────────

function resolveWebRef(baseDir, webRootDir, ref) {
    // 以 / 开头是相对 Web 虚拟主机根，而不是磁盘根。
    return ref.startsWith("/")
        ? path.resolve(webRootDir, ref.slice(1))
        : path.resolve(baseDir, ref);
}

const webRoot = path.join(payloadRoot, "launcher", "web");
const pages = walk(webRoot).filter(
    (f) => f.endsWith(".html") && path.dirname(f) === webRoot
);
for (const page of pages) {
    const html = fs.readFileSync(page, "utf8");
    const refs = [];
    for (const m of html.matchAll(/(?:src|href)\s*=\s*["']([^"']+)["']/g)) refs.push(m[1]);
    for (const ref of refs) {
        if (/^(?:[a-z]+:|\/\/|#|data:)/i.test(ref)) continue;
        const clean = ref.split("?")[0].split("#")[0];
        if (!clean) continue;
        const target = resolveWebRef(path.dirname(page), webRoot, clean);
        if (!fs.existsSync(target)) fail("页面引用缺失", relFrom(payloadRoot, page) + " -> " + ref);
    }
}

for (const css of walk(webRoot).filter((f) => f.endsWith(".css"))) {
    const text = fs.readFileSync(css, "utf8");
    for (const m of text.matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/g)) {
        const ref = m[1].trim();
        if (/^(?:[a-z]+:|\/\/|#|data:|%23)/i.test(ref)) continue;
        const clean = ref.split("?")[0].split("#")[0];
        if (!clean) continue;
        const target = resolveWebRef(path.dirname(css), webRoot, clean);
        if (!fs.existsSync(target)) fail("CSS 引用缺失", relFrom(payloadRoot, css) + " -> " + ref);
    }
}

const JS_PREFIXES = ["assets/", "content/", "generated/", "config/", "help/", "icons/", "lib/", "modules/"];
const JS_EXT = "json|md|js|css|png|webp|svg|html|xml|woff2?|ttf|otf|flv|swf|mp3|wav|ogg";
const jsRefRe = new RegExp("['\"]([^'\"\\s]{2,200}?\\.(?:" + JS_EXT + "))['\"]", "g");
for (const script of walk(webRoot).filter((f) => f.endsWith(".js"))) {
    const text = fs.readFileSync(script, "utf8");
    for (const m of text.matchAll(jsRefRe)) {
        const ref = m[1];
        if (!JS_PREFIXES.some((p) => ref.startsWith(p))) continue;
        if (ref.includes("${") || ref.includes("://")) continue;
        const clean = ref.split("?")[0].split("#")[0];
        const relativeToFile = resolveWebRef(path.dirname(script), webRoot, clean);
        const relativeToWeb = path.resolve(webRoot, clean);
        if (fs.existsSync(relativeToFile) || fs.existsSync(relativeToWeb)) continue;
        fail("JS 资源引用缺失", relFrom(payloadRoot, script) + " -> " + ref);
    }
}

// ── 5. 字体哈希链 ─────────────────────────────────────────────────

const repoFontsXml = path.join(repoRoot, "fonts", "fonts.xml");
const payloadFontsXml = path.join(payloadRoot, "fonts", "fonts.xml");
if (fs.existsSync(repoFontsXml) && fs.existsSync(payloadFontsXml)) {
    if (sha256(repoFontsXml) !== sha256(payloadFontsXml)) {
        fail("字体哈希链", "fonts/fonts.xml 与仓库字节不一致（压缩会破坏 sourceSha256 校验）");
    }
}
const projectionPath = path.join(payloadRoot, "launcher", "web", "generated", "font-catalog.json");
if (fs.existsSync(projectionPath) && fs.existsSync(payloadFontsXml)) {
    try {
        const projection = JSON.parse(fs.readFileSync(projectionPath, "utf8"));
        if (projection.sourceSha256 !== sha256(payloadFontsXml)) {
            fail("字体哈希链", "font-catalog.json 的 sourceSha256 与 fonts.xml 不一致");
        }
    } catch (error) {
        fail("字体哈希链", "font-catalog.json 解析失败: " + error.message);
    }
}

// ── 6. 转场图片目录清单 + world-lighting 引用 ──────────────────────

const transitionManifest = path.join(payloadRoot, "launcher", "data", "scene-transition", "catalog.manifest.json");
if (fs.existsSync(transitionManifest)) {
    try {
        const manifest = JSON.parse(fs.readFileSync(transitionManifest, "utf8"));
        for (const image of manifest.images || []) {
            if (!image.asset) continue;
            const target = path.join(webRoot, image.asset.split("/").join(path.sep));
            if (!fs.existsSync(target)) {
                fail("转场目录清单", "缺 " + image.asset);
            } else if (image.sha256 && sha256(target) !== image.sha256) {
                fail("转场目录清单", image.asset + " 的 sha256 与清单不一致");
            }
        }
    } catch (error) {
        fail("转场目录清单", "catalog.manifest.json 解析失败: " + error.message);
    }
}

const lightingPreset = path.join(payloadRoot, "launcher", "data", "world-lighting", "preset.json");
if (fs.existsSync(lightingPreset)) {
    try {
        const preset = JSON.parse(fs.readFileSync(lightingPreset, "utf8"));
        if (preset.file && !fs.existsSync(path.join(path.dirname(lightingPreset), preset.file))) {
            fail("world-lighting 引用", "preset.json 引用的 " + preset.file + " 不存在");
        }
    } catch (error) {
        fail("world-lighting 引用", "preset.json 解析失败: " + error.message);
    }
}

// ── 7. flashswf / sounds 与仓库的运行时对比 ─────────────────────────

function existsInRepo(relative) {
    return fs.existsSync(path.join(repoRoot, relative.split("/").join(path.sep)));
}

const FLASHSWF_DEV = [
    // XFL 源工程与源美术：运行时只认 .swf/.png/.flv/.html 与 portraits 的 xml
    "arts/new/**",
    "arts/things*/**",
    "arts/renew/**",
    "arts/AI草稿/**",
    "arts/原版素材库-子弹/**",
    "arts/新版人物文字信息/**",
    "arts/素材库-物品技能图标/**",
    "ComicTool/**",
    "miniGames/**",
    "unused/**",
    "**/LIBRARY/**",
    "**/META-INF/**",
    "**/bin/**",
    "**/*.xfl",
    "**/*.fla",
    "**/*.as",
    "**/*.md",
    "**/*.svg",
    "**/*.py",
    "**/*.txt",
    "**/*.jpg",
    "**/*.bin",
    "**/*.mp3",
    "**/*.psd",
    "**/*.xlsx",
    "**/DOMDocument.xml*",
    "**/MobileSettings.xml",
    "**/PublishSettings.xml",
    "**/mimetype",
    "**/*.bak-*",
    "**/*-备份.swf",
    "_ruffle/README.md",
    "_ruffle/LICENSE_*",
    "_ruffle/package.json",
    // 非运行时来源清单 / 生成溯源
    "movies/前线基地过场动画.mp4",
    "backgrounds/black-dragon-original/source-manifest.json",
    "portraits/postprocess.json",
    "portraits/profiles/generated-manifest.json",
    "portraits/前治安官（无线电）/postprocess-source.json",
];

const SOUNDS_DEV = ["**/LIBRARY/**", "**/META-INF/**", "**/bin/**", "**/DOMDocument.xml", "**/PublishSettings.xml", "**/MobileSettings.xml", "**/*.swf"];

for (const rule of [
    { root: "flashswf", allowMissing: FLASHSWF_DEV },
    { root: "sounds", allowMissing: SOUNDS_DEV },
]) {
    const repoFiles = walk(path.join(repoRoot, rule.root)).map((f) => relFrom(path.join(repoRoot, rule.root), f));
    const payloadFiles = new Set(
        walk(path.join(payloadRoot, rule.root)).map((f) => relFrom(path.join(payloadRoot, rule.root), f))
    );
    for (const relative of repoFiles) {
        if (payloadFiles.has(relative)) continue;
        if (matchesAny(relative, GLOBAL_JUNK) || matchesAny(relative, rule.allowMissing)) continue;
        fail(rule.root + " 与仓库不一致", "缺 " + relative);
    }
}

// ── 8. list.xml 注册项 ────────────────────────────────────────────

function stripXmlComments(text) {
    return text.replace(/<!--[\s\S]*?-->/g, "");
}

function resolveListEntry(baseDir, name, repoBaseDir) {
    const candidates = [name, name + ".xml", name + ".json", name + ".swf", name + ".txt"];
    for (const candidate of candidates) {
        if (fs.existsSync(path.join(baseDir, candidate.split("/").join(path.sep)))) return "payload";
    }
    for (const candidate of candidates) {
        if (fs.existsSync(path.join(repoBaseDir, candidate.split("/").join(path.sep)))) return "repo";
    }
    return "none";
}

// list.xml 中指向运行时状态的项：数据层已明确排除，加载器也支持文件缺失。
const INTENTIONALLY_ABSENT = new Set([
    "data/task/agent_tasks.json",
    "data/task/text/agent_text.json",
]);

for (const listFile of walk(payloadRoot).filter((f) => path.basename(f) === "list.xml")) {
    const rel = relFrom(payloadRoot, listFile);
    const text = stripXmlComments(fs.readFileSync(listFile, "utf8")).replace(/^\uFEFF/, "");
    for (const m of text.matchAll(/>([^<>]+)</g)) {
        const name = m[1].trim();
        if (!name || name.startsWith("<?") || name.includes("\n")) continue;
        const targetRel = path.posix.normalize(path.posix.join(path.posix.dirname(rel), name));
        if (INTENTIONALLY_ABSENT.has(targetRel)) continue;
        const where = resolveListEntry(path.dirname(listFile), name, path.join(repoRoot, path.dirname(rel)));
        if (where === "payload") continue;
        if (where === "repo") fail("list.xml 注册项缺失", rel + " -> " + name);
        else warn("list.xml 陈旧引用（仓库也没有）", rel + " -> " + name);
    }
}

// ── 9. BGM 曲目 ───────────────────────────────────────────────────

const bgmPath = path.join(payloadRoot, "sounds", "bgm_list.xml");
if (fs.existsSync(bgmPath)) {
    const text = stripXmlComments(fs.readFileSync(bgmPath, "utf8")).replace(/^\uFEFF/, "");
    for (const m of text.matchAll(/<url>([^<]+)<\/url>/g)) {
        const ref = m[1].trim();
        if (!ref || ref === "stop") continue;
        if (existsInPayload(ref)) continue;
        if (existsInRepo(ref)) fail("BGM 曲目缺失", ref);
        else warn("BGM 陈旧引用（仓库也没有）", ref);
    }
}

// ── 10. 关卡 <Path> 等仓库相对路径引用 ────────────────────────────

const DATA_REF_PREFIX = /^(flashswf|sounds|fonts|launcher|data|config)\//;
for (const xml of walk(path.join(payloadRoot, "data")).filter((f) => f.endsWith(".xml"))) {
    const text = fs.readFileSync(xml, "utf8");
    for (const m of text.matchAll(/<Path>([^<]+)<\/Path>/g)) {
        const ref = m[1].trim().replace(/\\/g, "/");
        if (!DATA_REF_PREFIX.test(ref)) continue;
        if (existsInPayload(ref)) continue;
        if (existsInRepo(ref)) fail("数据资源引用缺失", relFrom(payloadRoot, xml) + " -> " + ref);
        else warn("数据陈旧引用（仓库也没有）", relFrom(payloadRoot, xml) + " -> " + ref);
    }
}

// ── 汇总 ──────────────────────────────────────────────────────────

if (warnings.length > 0) {
    console.warn("[闭包审计] 告警（不影响出包）：");
    for (const item of warnings) console.warn("  - " + item);
}

if (failures.size === 0) {
    console.log("[闭包审计] 通过：" + payloadRoot);
    process.exit(0);
}

let total = 0;
console.error("[闭包审计] 发现缺口：" + payloadRoot);
for (const [group, items] of failures) {
    console.error("  " + group + "（" + items.length + "）");
    for (const item of items) console.error("    - " + item);
    total += items.length;
}
console.error("总计 " + total + " 项。先修打包配置，再重出包。");
process.exit(1);
