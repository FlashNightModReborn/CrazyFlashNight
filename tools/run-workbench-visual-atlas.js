#!/usr/bin/env node
'use strict';

var fs = require('fs');
var http = require('http');
var path = require('path');
var url = require('url');

var ROOT = path.resolve(__dirname, '..');
var PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');

function argValue(name) {
    var prefix = '--' + name + '=';
    for (var i = 2; i < process.argv.length; i++) {
        if (process.argv[i].indexOf(prefix) === 0) return process.argv[i].slice(prefix.length);
    }
    return null;
}

function hasArg(name) {
    return process.argv.indexOf('--' + name) !== -1;
}

function edgePath() {
    var candidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : null
    ];
    for (var i = 0; i < candidates.length; i++) if (candidates[i] && fs.existsSync(candidates[i])) return candidates[i];
    return null;
}

function contentType(file) {
    var ext = path.extname(file).toLowerCase();
    if (ext === '.html') return 'text/html; charset=utf-8';
    if (ext === '.css') return 'text/css; charset=utf-8';
    if (ext === '.js') return 'text/javascript; charset=utf-8';
    if (ext === '.json') return 'application/json; charset=utf-8';
    if (ext === '.png') return 'image/png';
    if (ext === '.webp') return 'image/webp';
    if (ext === '.svg') return 'image/svg+xml';
    return 'application/octet-stream';
}

function createServer() {
    return new Promise(function (resolve) {
        var server = http.createServer(function (request, response) {
            var pathname = decodeURIComponent(url.parse(request.url).pathname);
            var file = path.normalize(path.join(ROOT, pathname));
            var relative = path.relative(ROOT, file);
            if (relative.indexOf('..') === 0 || path.isAbsolute(relative)) {
                response.writeHead(403); response.end(); return;
            }
            fs.readFile(file, function (error, data) {
                if (error) { response.writeHead(404); response.end(); return; }
                response.writeHead(200, {'Content-Type':contentType(file)}); response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', function () { resolve(server); });
    });
}

function buildCases() {
    var viewports = [
        {id:'1024x576', width:1024, height:576},
        {id:'1366x768', width:1366, height:768},
        {id:'1920x1080', width:1920, height:1080}
    ];
    var densities = ['full', 'compact'];
    var booleans = [false, true];
    var cases = [];
    for (var v = 0; v < viewports.length; v++) {
        for (var d = 0; d < densities.length; d++) {
            for (var f = 0; f < booleans.length; f++) {
                for (var r = 0; r < booleans.length; r++) {
                    for (var s = 0; s < booleans.length; s++) {
                        var viewport = viewports[v];
                        var item = {
                            viewport:viewport,
                            density:densities[d],
                            focus:booleans[f],
                            reduced:booleans[r],
                            secondary:booleans[s]
                        };
                        item.id = [viewport.id, item.density, item.focus ? 'focus' : 'default', item.reduced ? 'reduce' : 'motion', item.secondary ? 'secondary' : 'main'].join('-');
                        cases.push(item);
                    }
                }
            }
        }
    }
    return cases;
}

function printText(report) {
    process.stdout.write('[workbench-atlas] cases=' + report.summary.totalCases
        + ' passed=' + report.summary.passedCases
        + ' errors=' + report.summary.errorCount
        + ' warnings=' + report.summary.warningCount + '\n');
    report.cases.forEach(function (item) {
        if (!item.errors.length && !item.warnings.length) return;
        process.stdout.write(' - ' + item.id + ': errors=' + item.errors.length + ' warnings=' + item.warnings.length + '\n');
        item.errors.forEach(function (entry) { process.stdout.write('   ERROR ' + entry.name + (entry.detail ? ' — ' + entry.detail : '') + '\n'); });
        item.warnings.forEach(function (entry) { process.stdout.write('   WARN  ' + entry.name + (entry.detail ? ' — ' + entry.detail : '') + '\n'); });
    });
}

(async function () {
    if (!fs.existsSync(PLAYWRIGHT)) throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    var executablePath = edgePath();
    if (!executablePath) throw new Error('Microsoft Edge executable not found');

    var shotDirArg = argValue('shot-dir');
    var shotDir = shotDirArg ? path.resolve(ROOT, shotDirArg) : null;
    var outputArg = argValue('output');
    var outputPath = outputArg ? path.resolve(ROOT, outputArg) : null;
    var strictWarnings = hasArg('strict-warnings');
    var textFormat = hasArg('text');
    if (shotDir) fs.mkdirSync(shotDir, {recursive:true});

    var chromium = require(PLAYWRIGHT).chromium;
    var server = await createServer();
    var browser = await chromium.launch({executablePath:executablePath, headless:true});
    var cases = buildCases();
    var results = [];
    try {
        var page = await browser.newPage({viewport:{width:1024, height:576}, deviceScaleFactor:1});
        var pageErrors = [];
        var failedRequests = [];
        page.on('pageerror', function (error) { pageErrors.push(error && error.message ? error.message : String(error)); });
        page.on('requestfailed', function (request) { failedRequests.push(request.url()); });

        for (var i = 0; i < cases.length; i++) {
            var scenario = cases[i];
            pageErrors = [];
            failedRequests = [];
            await page.setViewportSize({width:scenario.viewport.width, height:scenario.viewport.height});
            await page.emulateMedia({reducedMotion:scenario.reduced ? 'reduce' : 'no-preference'});
            var query = [
                'density=' + encodeURIComponent(scenario.density),
                'focus=' + (scenario.focus ? '1' : '0'),
                'reduced=' + (scenario.reduced ? '1' : '0'),
                'secondary=' + (scenario.secondary ? '1' : '0')
            ].join('&');
            await page.goto('http://127.0.0.1:' + server.address().port + '/tools/visual/workbench-atlas.html?' + query, {waitUntil:'load'});
            await page.waitForFunction(function () { return window.__qaDone === true; }, null, {timeout:20000});
            var result = await page.evaluate(function () { return window.__qaResult; });
            var errors = result && result.errors ? result.errors.slice() : [{name:'atlas returned no result', detail:''}];
            var warnings = result && result.warnings ? result.warnings.slice() : [];
            pageErrors.forEach(function (message) { errors.push({name:'pageerror', detail:message}); });
            failedRequests.forEach(function (requestUrl) { errors.push({name:'requestfailed', detail:requestUrl}); });
            if (shotDir) await page.screenshot({path:path.join(shotDir, scenario.id + '.png'), fullPage:true});
            results.push({
                id:scenario.id,
                viewport:[scenario.viewport.width, scenario.viewport.height],
                density:scenario.density,
                focus:scenario.focus,
                reducedMotion:scenario.reduced,
                secondaryPage:scenario.secondary,
                errors:errors,
                warnings:warnings,
                metrics:result ? result.metrics : null
            });
        }
    } finally {
        await browser.close();
        await new Promise(function (resolve) { server.close(resolve); });
    }

    var errorCount = results.reduce(function (sum, item) { return sum + item.errors.length; }, 0);
    var warningCount = results.reduce(function (sum, item) { return sum + item.warnings.length; }, 0);
    var passedCases = results.filter(function (item) { return item.errors.length === 0; }).length;
    var report = {
        schemaVersion:1,
        kind:'cf7-workbench-visual-atlas',
        browser:'edge',
        executablePath:executablePath,
        dimensions:{viewports:['1024x576','1366x768','1920x1080'], densities:['full','compact'], focus:[false,true], reducedMotion:[false,true], secondaryPage:[false,true]},
        summary:{totalCases:results.length, passedCases:passedCases, errorCount:errorCount, warningCount:warningCount, strictWarnings:strictWarnings},
        cases:results
    };
    var serialized = JSON.stringify(report, null, 2) + '\n';
    if (outputPath) {
        fs.mkdirSync(path.dirname(outputPath), {recursive:true});
        fs.writeFileSync(outputPath, serialized, 'utf8');
    }
    if (textFormat) printText(report); else process.stdout.write(serialized);
    if (errorCount || (strictWarnings && warningCount)) process.exitCode = 1;
})().catch(function (error) {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(2);
});
