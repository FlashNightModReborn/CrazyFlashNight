#!/usr/bin/env node
"use strict";

const fs = require("fs");
const http = require("http");
const path = require("path");

const projectRoot = path.resolve(__dirname, "..");
const webRoot = path.join(projectRoot, "launcher", "web");
const realWebRoot = fs.realpathSync(webRoot);
const playwrightPath = path.join(projectRoot, "launcher", "perf", "node_modules", "playwright");
const shippedMonoFont = path.join(webRoot, "assets", "fonts", "jetbrains-mono.woff2");
const systemFallbackFont = path.join(process.env.WINDIR || "C:\\Windows", "Fonts", "arial.ttf");

function parseArgs(argv) {
    const result = { caseId: "", headed: false };
    for (let i = 0; i < argv.length; i += 1) {
        if (argv[i] === "--case") {
            result.caseId = argv[i + 1] || "";
            i += 1;
        } else if (argv[i] === "--headed") {
            result.headed = true;
        } else {
            throw new Error("usage: node tools/run-lockbox-chest-s0-harness.js [--case W04|W05] [--headed]");
        }
    }
    if (result.caseId && result.caseId !== "W04" && result.caseId !== "W05") {
        throw new Error("--case must be W04 or W05");
    }
    return result;
}

function findEdge() {
    const candidates = [
        path.join(process.env["ProgramFiles(x86)"] || "C:\\Program Files (x86)", "Microsoft", "Edge", "Application", "msedge.exe"),
        path.join(process.env.ProgramFiles || "C:\\Program Files", "Microsoft", "Edge", "Application", "msedge.exe"),
        process.env.LOCALAPPDATA
            ? path.join(process.env.LOCALAPPDATA, "Microsoft", "Edge", "Application", "msedge.exe")
            : ""
    ];
    return candidates.find(candidate => candidate && fs.existsSync(candidate));
}

function mimeType(file) {
    const extension = path.extname(file).toLowerCase();
    if (extension === ".html") return "text/html; charset=utf-8";
    if (extension === ".css") return "text/css; charset=utf-8";
    if (extension === ".js") return "text/javascript; charset=utf-8";
    if (extension === ".json") return "application/json; charset=utf-8";
    if (extension === ".svg") return "image/svg+xml";
    if (extension === ".png") return "image/png";
    if (extension === ".webp") return "image/webp";
    if (extension === ".mp3") return "audio/mpeg";
    if (extension === ".ogg") return "audio/ogg";
    if (extension === ".ttf") return "font/ttf";
    if (extension === ".otf") return "font/otf";
    if (extension === ".woff") return "font/woff";
    if (extension === ".woff2") return "font/woff2";
    return "application/octet-stream";
}

function isWithinRoot(root, candidate) {
    const relative = path.relative(root, candidate);
    return relative === "" || (!relative.startsWith(".." + path.sep) && relative !== ".."
        && !path.isAbsolute(relative));
}

function resolveRequestFile(rawUrl) {
    let pathname;
    try {
        pathname = decodeURIComponent(new URL(rawUrl, "http://127.0.0.1/").pathname);
    } catch (error) {
        return { error: 400, detail: "malformed URI" };
    }
    if (pathname.indexOf("\0") >= 0) return { error: 400, detail: "NUL in path" };
    const relativePath = pathname.replace(/^[/\\]+/, "");
    const candidate = path.resolve(webRoot, relativePath);
    if (!isWithinRoot(webRoot, candidate)) return { error: 403, detail: "outside web root" };
    return { candidate };
}

function sendPlain(response, status, body) {
    const payload = Buffer.from(body || "", "utf8");
    response.writeHead(status, {
        "content-type": "text/plain; charset=utf-8",
        "content-length": payload.length,
        "cache-control": "no-store",
        "x-content-type-options": "nosniff"
    });
    response.end(payload);
}

function serveRequest(request, response) {
    if (request.method !== "GET" && request.method !== "HEAD") {
        sendPlain(response, 405, "method not allowed");
        return;
    }
    const resolved = resolveRequestFile(request.url || "/");
    if (resolved.error) {
        sendPlain(response, resolved.error, resolved.detail);
        return;
    }
    fs.realpath(resolved.candidate, (realPathError, realFile) => {
        if (realPathError) {
            sendPlain(response, 404, "not found");
            return;
        }
        if (!isWithinRoot(realWebRoot, realFile)) {
            sendPlain(response, 403, "outside real web root");
            return;
        }
        fs.stat(realFile, (statError, stat) => {
            if (statError || !stat.isFile()) {
                sendPlain(response, 404, "not found");
                return;
            }
            fs.readFile(realFile, (readError, data) => {
                if (readError) {
                    sendPlain(response, 404, "not found");
                    return;
                }
                response.writeHead(200, {
                    "content-type": mimeType(realFile),
                    "content-length": data.length,
                    "cache-control": "no-store",
                    "x-content-type-options": "nosniff"
                });
                if (request.method === "HEAD") response.end();
                else response.end(data);
            });
        });
    });
}

function startServer() {
    return new Promise((resolve, reject) => {
        const server = http.createServer((request, response) => {
            try {
                serveRequest(request, response);
            } catch (error) {
                sendPlain(response, 500, "internal harness server error");
            }
        });
        server.runtimeErrors = [];
        const onStartupError = error => reject(error);
        server.once("error", onStartupError);
        server.listen(0, "127.0.0.1", () => {
            server.removeListener("error", onStartupError);
            server.on("error", error => server.runtimeErrors.push(error.message || String(error)));
            resolve(server);
        });
    });
}

function closeServer(server) {
    if (!server || !server.listening) return Promise.resolve();
    return new Promise((resolve, reject) => {
        server.close(error => error ? reject(error) : resolve());
        if (typeof server.closeIdleConnections === "function") server.closeIdleConnections();
    });
}

function validateQa(result, expectedIds, shimEvidence) {
    const errors = [];
    if (!result || typeof result !== "object") return ["qa result is missing"];
    if (!Array.isArray(result.results)) errors.push("qa.results must be an array");
    if (result.total !== expectedIds.length) errors.push("qa.total must equal " + expectedIds.length);
    if (result.passed !== expectedIds.length) errors.push("qa.passed must equal " + expectedIds.length);
    if (result.failed !== 0) errors.push("qa.failed must be zero");
    if (Array.isArray(result.results)) {
        if (result.results.length !== expectedIds.length) {
            errors.push("qa.results length must equal " + expectedIds.length);
        }
        const seen = new Set();
        result.results.forEach((item, index) => {
            if (!item || typeof item !== "object") {
                errors.push("qa.results[" + index + "] is invalid");
                return;
            }
            if (item.pass !== true) errors.push("qa case did not pass: " + String(item.id));
            if (seen.has(item.id)) errors.push("duplicate qa id: " + String(item.id));
            seen.add(item.id);
            if (item.id !== expectedIds[index]) {
                errors.push("qa id/order mismatch at " + index + ": " + String(item.id));
            }
        });
        expectedIds.forEach(id => {
            if (!seen.has(id)) errors.push("missing qa id: " + id);
        });
    }
    if (!shimEvidence || shimEvidence.kind !== "browser-host-shim") {
        errors.push("browser-host-shim evidence is missing");
    } else {
        if (shimEvidence.actualCrossStack !== false) {
            errors.push("Browser harness must not claim actual cross-stack evidence");
        }
        if (shimEvidence.productionHost !== false) {
            errors.push("Browser harness must identify its non-production Host shim");
        }
        if (shimEvidence.usesProductionPanelsLazyRegistry !== true) {
            errors.push("production panels lazy-registry evidence is missing");
        }
    }
    return errors;
}

function validatePanelCommandLogs(lines) {
    const errors = [];
    const marker = "[Panels] panel_cmd received: ";
    const forbiddenFragments = [
        "__lockboxChestS0",
        "s0.browser.host.flow.",
        "s0.browser.host.panel.",
        "as2-chest-s0",
        "insurance-safe-s0-v1"
    ];
    if (!Array.isArray(lines) || lines.length === 0) {
        return ["S0 panel command log evidence is missing"];
    }
    lines.forEach((line, index) => {
        const markerIndex = line.indexOf(marker);
        if (markerIndex < 0) {
            errors.push("S0 panel command log marker is missing at " + index);
            return;
        }
        let payload = null;
        try {
            payload = JSON.parse(line.slice(markerIndex + marker.length));
        } catch (error) {
            errors.push("S0 panel command log is not valid JSON at " + index);
            return;
        }
        if (payload.panel !== "lockbox" || payload.cmd !== "open") {
            errors.push("unexpected S0 panel command log at " + index);
        }
        if (payload.initData !== "[redacted]") {
            errors.push("S0 panel command initData is not fully redacted at " + index);
        }
        forbiddenFragments.forEach(fragment => {
            if (line.indexOf(fragment) >= 0) {
                errors.push("S0 panel command log leaked " + fragment + " at " + index);
            }
        });
    });
    return errors;
}

async function runMain() {
    const args = parseArgs(process.argv.slice(2));
    if (!fs.existsSync(playwrightPath)) {
        throw new Error("Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts");
    }
    const edgePath = findEdge();
    if (!edgePath) throw new Error("Microsoft Edge not found");
    const { chromium } = require(playwrightPath);
    let server = null;
    let browser = null;
    let primaryError = null;
    let passed = false;
    try {
        server = await startServer();
        browser = await chromium.launch({ executablePath: edgePath, headless: !args.headed });
        const pageErrors = [];
        const failedRequests = [];
        const httpErrors = [];
        const consoleErrors = [];
        const consoleTail = [];
        const panelCommandLogs = [];
        const fontFixtures = [];
        const page = await browser.newPage({ viewport: { width: 1366, height: 768 } });
        page.on("pageerror", error => pageErrors.push(error.message || String(error)));
        page.on("requestfailed", request => {
            const failure = request.failure();
            failedRequests.push(request.url() + " :: " + (failure && failure.errorText || "failed"));
        });
        page.on("response", response => {
            if (response.status() >= 400) {
                httpErrors.push(response.status() + " " + response.url());
            }
        });
        page.on("console", message => {
            const line = message.type() + ": " + message.text();
            consoleTail.push(line);
            if (consoleTail.length > 40) consoleTail.shift();
            if (line.indexOf("[Panels] panel_cmd received:") >= 0) panelCommandLogs.push(line);
            if (message.type() === "error") consoleErrors.push(line);
        });
        if (!fs.existsSync(shippedMonoFont) || !fs.existsSync(systemFallbackFont)) {
            throw new Error("Browser harness font fixtures are unavailable");
        }
        await page.route("https://cfn-fonts.local/**", async route => {
            const requestUrl = route.request().url();
            const fontName = path.posix.basename(new URL(requestUrl).pathname).toLowerCase();
            const isWoff2 = fontName === "jetbrains-mono.woff2";
            const isFallbackTtf = fontName === "lxgw-wenkai-screen.ttf";
            if (!isWoff2 && !isFallbackTtf) {
                await route.fulfill({
                    status: 404,
                    contentType: "text/plain; charset=utf-8",
                    body: "font is not allow-listed by the standalone Browser harness"
                });
                return;
            }
            const fixture = isWoff2 ? shippedMonoFont : systemFallbackFont;
            fontFixtures.push({
                requestUrl,
                fixture: isWoff2 ? "shipped:jetbrains-mono.woff2" : "system:arial.ttf"
            });
            await route.fulfill({
                status: 200,
                contentType: isWoff2 ? "font/woff2" : "font/ttf",
                headers: {
                    "access-control-allow-origin": "*",
                    "cache-control": "no-store"
                },
                body: fs.readFileSync(fixture)
            });
        });

        const query = new URLSearchParams({ qa: "1" });
        if (args.caseId) query.set("case", args.caseId);
        const harnessUrl = "http://127.0.0.1:" + server.address().port
            + "/modules/minigames/lockbox/dev/s0-harness.html?" + query.toString();
        await page.goto(harnessUrl, { waitUntil: "load" });
        await page.waitForFunction(() => window.__qaResult && window.__qaResult.qa,
            null, { timeout: 30000 });
        await page.evaluate(async () => {
            if (document.fonts && document.fonts.ready) await document.fonts.ready;
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        });
        await page.waitForTimeout(250);

        const resultState = await page.evaluate(() => window.__qaResult);
        const result = resultState && resultState.qa;
        const shimEvidence = resultState && resultState.dumps
            ? resultState.dumps.s0Evidence : null;
        const expectedIds = args.caseId ? [args.caseId] : ["W04", "W05"];
        const expectedTotal = args.caseId ? 1 : 2;
        const validationErrors = validateQa(result, expectedIds, shimEvidence);
        validationErrors.push(...validatePanelCommandLogs(panelCommandLogs));
        const serverErrors = server.runtimeErrors.slice();
        const evidence = {
            harness: "lockbox-chest-s0-browser",
            executionMode: "browser-host-shim",
            actualCrossStack: false,
            url: harnessUrl,
            expectedIds,
            expectedTotal,
            qa: result,
            browserHostShim: shimEvidence,
            validationErrors,
            pageErrors,
            failedRequests,
            httpErrors,
            consoleErrors,
            serverErrors,
            fontFixtures,
            panelCommandLogs,
            consoleTail
        };
        process.stdout.write(JSON.stringify(evidence, null, 2) + "\n");
        passed = validationErrors.length === 0
            && pageErrors.length === 0
            && failedRequests.length === 0
            && httpErrors.length === 0
            && consoleErrors.length === 0
            && serverErrors.length === 0;
        if (passed) {
            console.log("[PASS] lockbox chest S0 browser-host-shim harness: "
                + result.passed + "/" + result.total + " cases (not actual cross-stack)");
        }
    } catch (error) {
        primaryError = error;
    } finally {
        const cleanupErrors = [];
        if (browser) {
            try { await browser.close(); }
            catch (error) { cleanupErrors.push("browser.close: " + (error.message || String(error))); }
        }
        if (server) {
            try { await closeServer(server); }
            catch (error) { cleanupErrors.push("server.close: " + (error.message || String(error))); }
        }
        if (cleanupErrors.length && !primaryError) primaryError = new Error(cleanupErrors.join("; "));
    }
    if (primaryError) throw primaryError;
    if (!passed) process.exitCode = 1;
}

runMain().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exitCode = 1;
});
