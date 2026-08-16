#!/usr/bin/env node
'use strict';

var childProcess = require('child_process');
var fs = require('fs');
var path = require('path');
var workbenchProfile = require('../../launcher/web/modules/workbench-profile.js');

var F0_BASELINE_COMMIT = 'c96f4c3d750561022b706c72a4d53050431e627d';

var VALID_PROFILES = workbenchProfile.validProfiles.slice();

var CSS_NAMED_COLOR_RE = new RegExp(
    '\\b(?:' + [
        'aliceblue', 'antiquewhite', 'aqua', 'aquamarine', 'azure', 'beige',
        'bisque', 'black', 'blanchedalmond', 'blue', 'blueviolet', 'brown',
        'burlywood', 'cadetblue', 'chartreuse', 'chocolate', 'coral',
        'cornflowerblue', 'cornsilk', 'crimson', 'cyan', 'darkblue', 'darkcyan',
        'darkgoldenrod', 'darkgray', 'darkgreen', 'darkgrey', 'darkkhaki',
        'darkmagenta', 'darkolivegreen', 'darkorange', 'darkorchid', 'darkred',
        'darksalmon', 'darkseagreen', 'darkslateblue', 'darkslategray',
        'darkslategrey', 'darkturquoise', 'darkviolet', 'deeppink', 'deepskyblue',
        'dimgray', 'dimgrey', 'dodgerblue', 'firebrick', 'floralwhite',
        'forestgreen', 'fuchsia', 'gainsboro', 'ghostwhite', 'gold', 'goldenrod',
        'gray', 'green', 'greenyellow', 'grey', 'honeydew', 'hotpink',
        'indianred', 'indigo', 'ivory', 'khaki', 'lavender', 'lavenderblush',
        'lawngreen', 'lemonchiffon', 'lightblue', 'lightcoral', 'lightcyan',
        'lightgoldenrodyellow', 'lightgray', 'lightgreen', 'lightgrey',
        'lightpink', 'lightsalmon', 'lightseagreen', 'lightskyblue',
        'lightslategray', 'lightslategrey', 'lightsteelblue', 'lightyellow',
        'lime', 'limegreen', 'linen', 'magenta', 'maroon', 'mediumaquamarine',
        'mediumblue', 'mediumorchid', 'mediumpurple', 'mediumseagreen',
        'mediumslateblue', 'mediumspringgreen', 'mediumturquoise',
        'mediumvioletred', 'midnightblue', 'mintcream', 'mistyrose', 'moccasin',
        'navajowhite', 'navy', 'oldlace', 'olive', 'olivedrab', 'orange',
        'orangered', 'orchid', 'palegoldenrod', 'palegreen', 'paleturquoise',
        'palevioletred', 'papayawhip', 'peachpuff', 'peru', 'pink', 'plum',
        'powderblue', 'purple', 'rebeccapurple', 'red', 'rosybrown', 'royalblue',
        'saddlebrown', 'salmon', 'sandybrown', 'seagreen', 'seashell', 'sienna',
        'silver', 'skyblue', 'slateblue', 'slategray', 'slategrey', 'snow',
        'springgreen', 'steelblue', 'tan', 'teal', 'thistle', 'tomato',
        'turquoise', 'violet', 'wheat', 'white', 'whitesmoke', 'yellow',
        'yellowgreen'
    ].join('|') + ')\\b',
    'i'
);

var DEBT_RULES = [
    'rawColor',
    'fontBelow9',
    'font9PlayerText',
    'rawDuration',
    'rawEasing',
    'transitionAll'
];

function normalizeRel(value) {
    return String(value || '').replace(/\\/g, '/').replace(/^\.\//, '');
}

function lineOf(text, index) {
    return text.slice(0, Math.max(0, index)).split(/\r?\n/).length;
}

function maskComments(source) {
    return String(source || '').replace(/\/\*[\s\S]*?\*\//g, function(comment) {
        return comment.replace(/[^\r\n]/g, ' ');
    });
}

function maskCssCommentsAndStrings(source) {
    var value = String(source || '');
    var output = value.split('');
    var quote = '';
    var escaped = false;
    var blockComment = false;
    for (var index = 0; index < value.length; index++) {
        var char = value[index];
        var next = value[index + 1];
        if (blockComment) {
            if (char === '*' && next === '/') {
                output[index] = ' ';
                output[index + 1] = ' ';
                blockComment = false;
                index++;
            } else if (char !== '\r' && char !== '\n') {
                output[index] = ' ';
            }
            continue;
        }
        if (quote) {
            if (escaped) {
                if (char !== '\r' && char !== '\n') output[index] = ' ';
                escaped = false;
                continue;
            }
            if (char === '\\') {
                output[index] = ' ';
                escaped = true;
                continue;
            }
            if (char === quote) {
                output[index] = ' ';
                quote = '';
            } else if (char !== '\r' && char !== '\n') {
                output[index] = ' ';
            }
            continue;
        }
        if (char === '/' && next === '*') {
            output[index] = ' ';
            output[index + 1] = ' ';
            blockComment = true;
            index++;
            continue;
        }
        if (char === '"' || char === "'") {
            output[index] = ' ';
            quote = char;
        }
    }
    return output.join('');
}

function scanImportantDeclarations(source, rel) {
    var clean = maskCssCommentsAndStrings(source);
    var findings = [];
    var importantRe = /!\s*important\b/gi;
    var match;
    while ((match = importantRe.exec(clean)) !== null) {
        findings.push({
            file:normalizeRel(rel),
            line:lineOf(clean, match.index)
        });
    }
    return findings;
}

function scanCssDeclarations(source, rel) {
    var clean = maskCssCommentsAndStrings(source);
    var declarations = [];
    var ruleRe = /([^{}]+)\{([^{}]*)\}/g;
    var rule;
    while ((rule = ruleRe.exec(clean)) !== null) {
        var selector = rule[1].trim();
        var body = rule[2];
        var bodyOffset = rule.index + rule[0].indexOf(body);
        var declarationRe = /(^|;)\s*([a-z-]+)\s*:\s*([^;{}]+)(?=;|$)/gi;
        var declaration;
        while ((declaration = declarationRe.exec(body)) !== null) {
            var propertyOffset = declaration.index + declaration[1].length
                + declaration[0].slice(declaration[1].length).search(/[a-z-]/i);
            declarations.push({
                file:normalizeRel(rel),
                line:lineOf(clean, bodyOffset + propertyOffset),
                selector:selector.replace(/\s+/g, ' ').trim().slice(0, 180),
                property:declaration[2].toLowerCase(),
                value:declaration[3].trim()
            });
        }
    }
    return declarations;
}

function scanVisibleImportantDisplayDeclarations(source, rel) {
    return scanCssDeclarations(source, rel).filter(function(declaration) {
        if (!/!\s*important\b/i.test(declaration.value)) return false;
        if (declaration.property === 'all') return true;
        if (declaration.property !== 'display') return false;
        return !/^none\s*!\s*important\s*$/i.test(declaration.value);
    });
}

function focusOutlineStateSelector(selector) {
    return /(?:\.workbench-drop-(?:active|rejected)\b|\.dragging\b|\.is-(?:blocked|busy|error|pending|ready|rejected)\b|\[data-state\s*=)/i
        .test(String(selector || ''));
}

function characterSlotFocusException(selector, rel) {
    if (normalizeRel(rel) !== 'launcher/web/css/workbench/character-build.css') return false;
    var normalized = String(selector || '').replace(/\s+/g, ' ').trim();
    return normalized === '.character-build-slot:focus-visible'
        || normalized === '.character-build-slot:focus-visible .character-build-slot-card';
}

function scanUnlayeredFocusOutlineOverrides(source, rel) {
    var value = String(source || '');
    var clean = maskCssCommentsAndStrings(value);
    var findings = [];

    function matchingBrace(openAt, end) {
        var depth = 1;
        for (var index = openAt + 1; index < end; index++) {
            if (clean[index] === '{') depth++;
            else if (clean[index] === '}' && --depth === 0) return index;
        }
        return end;
    }

    function scanRule(selector, bodyStart, bodyEnd, layered) {
        if (layered) return;
        var declarationRe = /(?:^|;)\s*(outline(?:-offset)?)\s*:\s*([^;}]+)/gi;
        var body = clean.slice(bodyStart, bodyEnd);
        var match;
        while ((match = declarationRe.exec(body)) !== null) {
            if (characterSlotFocusException(selector, rel)) continue;
            if (String(selector).indexOf(':focus') === -1
                    && focusOutlineStateSelector(selector)) continue;
            findings.push(finding(
                'unlayeredFocusOutline',
                rel,
                lineOf(clean, bodyStart + match.index),
                null,
                selector,
                match[1],
                value.slice(bodyStart + match.index, bodyStart + declarationRe.lastIndex)
            ));
        }
    }

    function walk(start, end, layered) {
        var statementStart = start;
        for (var index = start; index < end;) {
            var char = clean[index];
            if (char === ';') {
                statementStart = index + 1;
                index++;
                continue;
            }
            if (char !== '{') {
                index++;
                continue;
            }
            var header = clean.slice(statementStart, index).trim();
            var closeAt = matchingBrace(index, end);
            if (/^@layer\b/i.test(header)) {
                walk(index + 1, closeAt, true);
            } else if (/^@(?:media|supports|container|document)\b/i.test(header)) {
                walk(index + 1, closeAt, layered);
            } else if (!/^@(?:-webkit-)?keyframes\b/i.test(header)) {
                scanRule(header, index + 1, closeAt, layered);
            }
            index = closeAt + 1;
            statementStart = index;
        }
    }

    walk(0, clean.length, false);
    return findings;
}

function maskJavaScriptComments(source) {
    var value = String(source || '');
    var output = value.split('');
    var quote = '';
    var escaped = false;
    var lineComment = false;
    var blockComment = false;
    for (var index = 0; index < value.length; index++) {
        var char = value[index];
        var next = value[index + 1];
        if (lineComment) {
            if (char === '\n') {
                lineComment = false;
            } else if (char !== '\r') {
                output[index] = ' ';
            }
            continue;
        }
        if (blockComment) {
            if (char === '*' && next === '/') {
                output[index] = ' ';
                output[index + 1] = ' ';
                blockComment = false;
                index++;
            } else if (char !== '\r' && char !== '\n') {
                output[index] = ' ';
            }
            continue;
        }
        if (quote) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (char === '\\') {
                escaped = true;
                continue;
            }
            if (char === quote) quote = '';
            continue;
        }
        if (char === '/' && next === '/') {
            output[index] = ' ';
            output[index + 1] = ' ';
            lineComment = true;
            index++;
            continue;
        }
        if (char === '/' && next === '*') {
            output[index] = ' ';
            output[index + 1] = ' ';
            blockComment = true;
            index++;
            continue;
        }
        if (char === '"' || char === "'" || char === '`') quote = char;
    }
    return output.join('');
}

function maskPowerShellComments(source) {
    var value = String(source || '');
    var output = value.split('');
    var quote = '';
    var escaped = false;
    var lineComment = false;
    var blockComment = false;
    for (var index = 0; index < value.length; index++) {
        var char = value[index];
        var next = value[index + 1];
        if (lineComment) {
            if (char === '\n') {
                lineComment = false;
            } else if (char !== '\r') {
                output[index] = ' ';
            }
            continue;
        }
        if (blockComment) {
            if (char === '#' && next === '>') {
                output[index] = ' ';
                output[index + 1] = ' ';
                blockComment = false;
                index++;
            } else if (char !== '\r' && char !== '\n') {
                output[index] = ' ';
            }
            continue;
        }
        if (quote) {
            if (quote === '"' && escaped) {
                escaped = false;
                continue;
            }
            if (quote === '"' && char === '`') {
                escaped = true;
                continue;
            }
            if (char === quote) {
                if (quote === "'" && next === "'") {
                    index++;
                    continue;
                }
                quote = '';
            }
            continue;
        }
        if (char === '<' && next === '#') {
            output[index] = ' ';
            output[index + 1] = ' ';
            blockComment = true;
            index++;
            continue;
        }
        if (char === '#') {
            output[index] = ' ';
            lineComment = true;
            continue;
        }
        if (char === '"' || char === "'") quote = char;
    }
    return output.join('');
}

function finding(rule, rel, line, endLine, selector, property, value) {
    return {
        rule:rule,
        file:normalizeRel(rel),
        line:line,
        endLine:endLine || line,
        selector:String(selector || '').replace(/\s+/g, ' ').trim().slice(0, 180),
        property:String(property || '').trim(),
        value:String(value || '').replace(/\s+/g, ' ').trim().slice(0, 180)
    };
}

function hasRawColor(value) {
    var source = String(value || '').replace(/url\([^)]*\)/gi, ' ');
    if (/#[0-9a-f]{3,8}\b/i.test(source)) return true;

    var colorFunction = /\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch)\(\s*([^)]*)\)/gi;
    var match;
    while ((match = colorFunction.exec(source)) !== null) {
        var body = match[1].trim();
        if (/^(?:from\s+)?var\(/i.test(body)) continue;
        return true;
    }

    var withoutVars = source.replace(/var\([^)]*\)/gi, ' ');
    return CSS_NAMED_COLOR_RE.test(withoutVars);
}

function fontPixelSizes(property, value) {
    var sizes = [];
    var match;
    if (property === 'font-size') {
        var directSizeRe = /([0-9]*\.?[0-9]+)px\b/gi;
        while ((match = directSizeRe.exec(value)) !== null) sizes.push(Number(match[1]));
        return sizes;
    }
    if (property !== 'font') return sizes;
    var sizeRe = /(?:^|[\s/])([0-9]*\.?[0-9]+)px(?=\s*\/|\/|\s|$)/gi;
    while ((match = sizeRe.exec(value)) !== null) sizes.push(Number(match[1]));
    return sizes;
}

function isNinePixelBadgeRole(selector) {
    var value = String(selector || '').toLowerCase();
    return /(?:badge|chip|tag|marker|ordinal|slot-index|slot-number|hotkey|keycap)/.test(value);
}

function isMotionProperty(property) {
    return /^(?:transition(?:-(?:property|duration|delay|timing-function))?|animation(?:-(?:duration|delay|timing-function))?)$/.test(property);
}

function hasRawDuration(value) {
    return /(?:^|[\s,(])(?:[0-9]*\.)?[0-9]+(?:ms|s)\b/i.test(value);
}

function hasRawEasing(value) {
    var withoutVars = String(value || '').replace(/var\([^)]*\)/gi, ' ');
    return /(?:^|[\s,])(?:ease(?:-in|-out|-in-out)?|linear|step-start|step-end|cubic-bezier\(|steps\()/i.test(withoutVars);
}

function isShellGridSelector(selector) {
    return /(?:^|[\s,>+~])\.workbench-(?:shell|body)(?:\b|[.:[#])/i.test(String(selector || ''));
}

function hasProfileSelector(selector) {
    var match = /\[data-profile\s*=\s*(?:(['"])([^'"]+)\1|([a-z-]+))\]/i.exec(String(selector || ''));
    var value = match && (match[2] || match[3]);
    return !!(value && VALID_PROFILES.indexOf(value) !== -1);
}

function hasUnprofiledShellGridSelector(selector) {
    return splitTopLevelObject(String(selector || '')).some(function(branch) {
        return isShellGridSelector(branch) && !hasProfileSelector(branch);
    });
}

function scanCss(source, rel) {
    var clean = maskComments(source);
    var findings = [];
    var shellGrid = [];
    var ruleRe = /([^{}]+)\{([^{}]*)\}/g;
    var match;

    while ((match = ruleRe.exec(clean)) !== null) {
        var selector = match[1].trim();
        var body = match[2];
        var bodyOffset = match.index + match[0].indexOf(body);
        var declarationRe = /(^|;)\s*([a-z-]+)\s*:\s*([^;{}]+)(?=;|$)/gi;
        var declaration;

        while ((declaration = declarationRe.exec(body)) !== null) {
            var property = declaration[2].toLowerCase();
            var value = declaration[3].trim();
            var propertyOffset = declaration.index + declaration[1].length
                + declaration[0].slice(declaration[1].length).search(/[a-z-]/i);
            var line = lineOf(clean, bodyOffset + propertyOffset);
            var endLine = lineOf(clean, bodyOffset + declaration.index + declaration[0].length);

            var tokenDefinition = /(?:^|\/)tokens\.css$/i.test(normalizeRel(rel))
                && property.indexOf('--') === 0;
            if (!tokenDefinition && hasRawColor(value)) {
                findings.push(finding('rawColor', rel, line, endLine, selector, property, value));
            }

            var sizes = tokenDefinition ? [] : fontPixelSizes(property, value);
            sizes.forEach(function(size) {
                if (size < 9) {
                    findings.push(finding('fontBelow9', rel, line, endLine, selector, property, value));
                } else if (size === 9 && !isNinePixelBadgeRole(selector)) {
                    findings.push(finding('font9PlayerText', rel, line, endLine, selector, property, value));
                }
            });

            if (!tokenDefinition && isMotionProperty(property)) {
                if (hasRawDuration(value)) {
                    findings.push(finding('rawDuration', rel, line, endLine, selector, property, value));
                }
                if (hasRawEasing(value)) {
                    findings.push(finding('rawEasing', rel, line, endLine, selector, property, value));
                }
                if ((property === 'transition' || property === 'transition-property')
                        && /(?:^|[\s,])all(?:$|[\s,])/i.test(value)) {
                    findings.push(finding('transitionAll', rel, line, endLine, selector, property, value));
                }
            }

            if (/^grid-template-(?:columns|rows)$/.test(property)
                    && hasUnprofiledShellGridSelector(selector)) {
                shellGrid.push(finding('shellGridOverride', rel, line, endLine, selector, property, value));
            }
        }
    }

    return {findings:findings, shellGrid:shellGrid};
}

function countsByRule(findings) {
    var counts = {};
    DEBT_RULES.forEach(function(rule) { counts[rule] = 0; });
    (findings || []).forEach(function(item) {
        if (Object.prototype.hasOwnProperty.call(counts, item.rule)) counts[item.rule]++;
    });
    return counts;
}

function parseUnifiedZeroDiff(diff) {
    var touched = {};
    var currentFile = '';
    String(diff || '').split(/\r?\n/).forEach(function(line) {
        if (line.indexOf('+++ ') === 0) {
            currentFile = line.slice(4).trim();
            if (currentFile === '/dev/null') {
                currentFile = '';
                return;
            }
            if (currentFile.indexOf('b/') === 0) currentFile = currentFile.slice(2);
            currentFile = normalizeRel(currentFile);
            if (!touched[currentFile]) touched[currentFile] = {};
            return;
        }
        if (!currentFile || line.indexOf('@@ ') !== 0) return;
        var match = /\+([0-9]+)(?:,([0-9]+))?/.exec(line);
        if (!match) return;
        var start = Number(match[1]);
        var count = match[2] == null ? 1 : Number(match[2]);
        for (var index = 0; index < count; index++) touched[currentFile][start + index] = true;
    });
    return touched;
}

function git(root, args, options) {
    options = options || {};
    return childProcess.execFileSync('git', ['-C', root].concat(args), {
        encoding:'utf8',
        maxBuffer:16 * 1024 * 1024,
        stdio:options.quiet ? ['ignore', 'pipe', 'ignore'] : ['ignore', 'pipe', 'pipe']
    });
}

function readBaselineFile(root, commit, rel) {
    try {
        return git(root, ['show', commit + ':' + normalizeRel(rel)], {quiet:true});
    } catch (error) {
        return null;
    }
}

function previousCommittedFile(root, rel, currentSource) {
    var headSource = readBaselineFile(root, 'HEAD', rel);
    if (headSource == null) return null;
    var normalizedHead = headSource.replace(/\r\n?/g, '\n');
    var normalizedCurrent = String(currentSource || '').replace(/\r\n?/g, '\n');
    if (normalizedHead !== normalizedCurrent) return headSource;
    try {
        var commits = git(root, ['log', '--format=%H', '-2', '--', normalizeRel(rel)], {quiet:true})
            .split(/\r?\n/)
            .filter(Boolean);
        if (commits.length < 2) return null;
        return readBaselineFile(root, commits[1], rel);
    } catch (error) {
        return null;
    }
}

function baselineIsUsable(root, commit) {
    if (!/^[0-9a-f]{40}$/i.test(String(commit || ''))) return false;
    try {
        git(root, ['cat-file', '-e', commit + '^{commit}'], {quiet:true});
        git(root, ['merge-base', '--is-ancestor', commit, 'HEAD'], {quiet:true});
        return true;
    } catch (error) {
        return false;
    }
}

function evaluateDebtRatchet(baselineFindings, currentFindings, touchedLines) {
    var baselineCounts = countsByRule(baselineFindings);
    var currentCounts = countsByRule(currentFindings);
    var violations = [];

    DEBT_RULES.forEach(function(rule) {
        var touched = (currentFindings || []).filter(function(item) {
            if (item.rule !== rule || !touchedLines[item.file]) return false;
            for (var line = item.line; line <= (item.endLine || item.line); line++) {
                if (touchedLines[item.file][line]) return true;
            }
            return false;
        });
        if (currentCounts[rule] > baselineCounts[rule] || touched.length) {
            violations.push({
                rule:rule,
                baseline:baselineCounts[rule],
                current:currentCounts[rule],
                delta:currentCounts[rule] - baselineCounts[rule],
                touchedCount:touched.length,
                samples:touched.slice(0, 8)
            });
        }
    });

    return {
        baselineCounts:baselineCounts,
        currentCounts:currentCounts,
        violations:violations
    };
}

function auditCssDebt(options) {
    var root = options.root;
    var commit = options.baselineCommit;
    var files = (options.files || []).map(normalizeRel);
    if (!baselineIsUsable(root, commit)) {
        return {
            available:false,
            error:'baseline commit is missing or is not an ancestor of HEAD',
            baselineCommit:commit
        };
    }

    var baselineFindings = [];
    var currentFindings = [];
    var shellGrid = [];
    var baselineMissing = {};
    files.forEach(function(rel) {
        var currentSource = fs.readFileSync(path.join(root, rel), 'utf8');
        var baselineSource = readBaselineFile(root, commit, rel);
        var currentScan = scanCss(currentSource, rel);
        currentFindings = currentFindings.concat(currentScan.findings);
        shellGrid = shellGrid.concat(currentScan.shellGrid);
        if (baselineSource == null) {
            baselineMissing[rel] = true;
        } else {
            baselineFindings = baselineFindings.concat(scanCss(baselineSource, rel).findings);
        }
    });

    // --minimal：强制精确 Myers。默认 xdl 在编辑代价超预算时退化启发式，
    // 对「巨型中段删块」（如 stage-select 1255 行拆出 features.css）会产生数百碎片 hunk，
    // 让 hunk 新侧范围错位覆盖到未改动的相邻段落，造成 touched-line 误报（2026-08-16 P1-B 实证：
    // 同内容 diff 默认 350 hunks / --minimal 12 hunks）。
    var diff = git(root, ['diff', '--no-ext-diff', '--no-color', '--unified=0', '--minimal', commit, '--'].concat(files));
    var touched = parseUnifiedZeroDiff(diff);
    Object.keys(baselineMissing).forEach(function(rel) {
        var lineCount = fs.readFileSync(path.join(root, rel), 'utf8').split(/\r?\n/).length;
        if (!touched[rel]) touched[rel] = {};
        for (var line = 1; line <= lineCount; line++) touched[rel][line] = true;
    });

    var evaluation = evaluateDebtRatchet(baselineFindings, currentFindings, touched);
    return {
        available:true,
        baselineCommit:commit,
        files:files.length,
        baselineCounts:evaluation.baselineCounts,
        currentCounts:evaluation.currentCounts,
        violations:evaluation.violations,
        touchedFiles:Object.keys(touched).filter(function(rel) {
            return Object.keys(touched[rel]).length > 0;
        }).length,
        shellGrid:shellGrid
    };
}

function auditCurrentCssDebt(options) {
    var root = options.root;
    var files = (options.files || []).map(normalizeRel);
    var currentFindings = [];
    var shellGrid = [];
    files.forEach(function(rel) {
        var scan = scanCss(fs.readFileSync(path.join(root, rel), 'utf8'), rel);
        currentFindings = currentFindings.concat(scan.findings);
        shellGrid = shellGrid.concat(scan.shellGrid);
    });
    return {
        available:true,
        currentTreeOnly:true,
        files:files.length,
        currentCounts:countsByRule(currentFindings),
        violations:[],
        touchedFiles:0,
        shellGrid:shellGrid
    };
}

function findClosingBrace(source, openAt) {
    var depth = 0;
    var quote = '';
    var escaped = false;
    var lineComment = false;
    var blockComment = false;
    for (var index = openAt; index < source.length; index++) {
        var char = source[index];
        var next = source[index + 1];
        if (lineComment) {
            if (char === '\n') lineComment = false;
            continue;
        }
        if (blockComment) {
            if (char === '*' && next === '/') { blockComment = false; index++; }
            continue;
        }
        if (quote) {
            if (escaped) { escaped = false; continue; }
            if (char === '\\') { escaped = true; continue; }
            if (char === quote) quote = '';
            continue;
        }
        if (char === '/' && next === '/') { lineComment = true; index++; continue; }
        if (char === '/' && next === '*') { blockComment = true; index++; continue; }
        if (char === '"' || char === "'" || char === '`') { quote = char; continue; }
        if (char === '{') depth++;
        if (char === '}' && --depth === 0) return index;
    }
    return -1;
}

function splitTopLevelObject(body) {
    var parts = [];
    var start = 0;
    var depth = 0;
    var quote = '';
    var escaped = false;
    var lineComment = false;
    var blockComment = false;
    for (var index = 0; index < body.length; index++) {
        var char = body[index];
        var next = body[index + 1];
        if (lineComment) {
            if (char === '\n') lineComment = false;
            continue;
        }
        if (blockComment) {
            if (char === '*' && next === '/') { blockComment = false; index++; }
            continue;
        }
        if (quote) {
            if (escaped) { escaped = false; continue; }
            if (char === '\\') { escaped = true; continue; }
            if (char === quote) quote = '';
            continue;
        }
        if (char === '/' && next === '/') { lineComment = true; index++; continue; }
        if (char === '/' && next === '*') { blockComment = true; index++; continue; }
        if (char === '"' || char === "'" || char === '`') { quote = char; continue; }
        if (char === '{' || char === '[' || char === '(') { depth++; continue; }
        if (char === '}' || char === ']' || char === ')') { depth--; continue; }
        if (char === ',' && depth === 0) {
            parts.push(body.slice(start, index));
            start = index + 1;
        }
    }
    parts.push(body.slice(start));
    return parts;
}

function trimLeadingComments(segment) {
    var value = String(segment || '');
    var previous;
    do {
        previous = value;
        value = value.replace(/^\s*\/\*[\s\S]*?\*\//, '').replace(/^\s*\/\/[^\r\n]*(?:\r?\n|$)/, '');
    } while (value !== previous);
    return value.trim();
}

function canStartJavaScriptRegex(source, index) {
    var before = String(source || '').slice(0, index);
    var match = /(\S+)\s*$/.exec(before);
    if (!match) return true;
    var token = match[1];
    var last = token[token.length - 1];
    if (/[\(\[\{=,:;!?\|&+\-*%^~<>]/.test(last)) return true;
    var word = /([A-Za-z_$][\w$]*)$/.exec(token);
    return !!(word && /^(?:return|case|throw|typeof|instanceof|in|of|delete|void|new|yield|await)$/.test(word[1]));
}

function maskJavaScriptCode(source) {
    var value = String(source || '');
    var output = value.split('');
    var quote = '';
    var escaped = false;
    var lineComment = false;
    var blockComment = false;
    var regex = false;
    var regexClass = false;
    for (var index = 0; index < value.length; index++) {
        var char = value[index];
        var next = value[index + 1];
        if (lineComment) {
            if (char === '\n') {
                lineComment = false;
            } else if (char !== '\r') {
                output[index] = ' ';
            }
            continue;
        }
        if (blockComment) {
            if (char === '*' && next === '/') {
                output[index] = ' ';
                output[index + 1] = ' ';
                blockComment = false;
                index++;
            } else if (char !== '\r' && char !== '\n') {
                output[index] = ' ';
            }
            continue;
        }
        if (regex) {
            if (char !== '\r' && char !== '\n') output[index] = ' ';
            if (escaped) {
                escaped = false;
                continue;
            }
            if (char === '\\') {
                escaped = true;
                continue;
            }
            if (char === '[') {
                regexClass = true;
                continue;
            }
            if (char === ']' && regexClass) {
                regexClass = false;
                continue;
            }
            if (char === '/' && !regexClass) regex = false;
            continue;
        }
        if (quote) {
            if (char !== '\r' && char !== '\n') output[index] = ' ';
            if (escaped) {
                escaped = false;
                continue;
            }
            if (char === '\\') {
                escaped = true;
                continue;
            }
            if (char === quote) quote = '';
            continue;
        }
        if (char === '/' && next === '/') {
            output[index] = ' ';
            output[index + 1] = ' ';
            lineComment = true;
            index++;
            continue;
        }
        if (char === '/' && next === '*') {
            output[index] = ' ';
            output[index + 1] = ' ';
            blockComment = true;
            index++;
            continue;
        }
        if (char === '/' && canStartJavaScriptRegex(value, index)) {
            output[index] = ' ';
            regex = true;
            regexClass = false;
            continue;
        }
        if (char === '"' || char === "'" || char === '`') {
            output[index] = ' ';
            quote = char;
        }
    }
    return output.join('');
}

function matchingOuterParen(value) {
    var code = maskJavaScriptCode(value);
    var depth = 0;
    for (var index = 0; index < code.length; index++) {
        var char = code[index];
        if (char === '(') {
            depth++;
        } else if (char === ')' && --depth === 0) {
            return index;
        }
    }
    return -1;
}

function stripClosedExpressionParens(expression) {
    var value = maskJavaScriptComments(expression).trim();
    while (value[0] === '(') {
        var closeAt = matchingOuterParen(value);
        if (closeAt !== value.length - 1) break;
        value = value.slice(1, -1).trim();
    }
    return value;
}

function findTopLevelConditional(expression) {
    var code = maskJavaScriptCode(expression);
    var roundDepth = 0;
    var squareDepth = 0;
    var braceDepth = 0;
    var questionAt = -1;
    var nestedQuestions = 0;
    for (var index = 0; index < code.length; index++) {
        var char = code[index];
        if (char === '(') roundDepth++;
        else if (char === ')') roundDepth--;
        else if (char === '[') squareDepth++;
        else if (char === ']') squareDepth--;
        else if (char === '{') braceDepth++;
        else if (char === '}') braceDepth--;
        if (roundDepth !== 0 || squareDepth !== 0 || braceDepth !== 0) continue;
        if (char === '?') {
            if (code[index + 1] === '?' || code[index + 1] === '.') return null;
            if (questionAt < 0) questionAt = index;
            else nestedQuestions++;
        } else if (char === ':' && questionAt >= 0) {
            if (nestedQuestions > 0) {
                nestedQuestions--;
            } else {
                return {questionAt:questionAt, colonAt:index};
            }
        }
    }
    return null;
}

function findMatchingJavaScriptDelimiter(source, openAt, openChar, closeChar) {
    var code = maskJavaScriptCode(source);
    var depth = 0;
    for (var index = openAt; index < code.length; index++) {
        if (code[index] === openChar) {
            depth++;
        } else if (code[index] === closeChar && --depth === 0) {
            return index;
        }
    }
    return -1;
}

function analyzeClosedProfileExpression(expression) {
    var value = stripClosedExpressionParens(expression);
    var literal = /^(['"])([a-z-]+)\1$/.exec(value);
    if (literal) {
        return {
            valid:VALID_PROFILES.indexOf(literal[2]) !== -1,
            literalProfile:literal[2],
            profiles:[literal[2]]
        };
    }
    var conditional = findTopLevelConditional(value);
    if (!conditional) return {valid:false, literalProfile:null, profiles:[]};
    var conditionCode = maskJavaScriptCode(value.slice(0, conditional.questionAt)).trim();
    if (!conditionCode || /=>/.test(conditionCode)) {
        return {valid:false, literalProfile:null, profiles:[]};
    }
    var consequent = analyzeClosedProfileExpression(
        value.slice(conditional.questionAt + 1, conditional.colonAt)
    );
    var alternate = analyzeClosedProfileExpression(value.slice(conditional.colonAt + 1));
    return {
        valid:consequent.valid && alternate.valid,
        literalProfile:null,
        profiles:consequent.profiles.concat(alternate.profiles)
    };
}

function analyzeDualPaneOptions(argument) {
    var value = stripClosedExpressionParens(argument);
    var openAt = value.search(/\S/);
    if (openAt < 0 || value[openAt] !== '{') {
        return {hasProfile:false, profile:{valid:false, literalProfile:null, profiles:[]}};
    }
    var closeAt = findClosingBrace(value, openAt);
    if (closeAt < 0 || value.slice(closeAt + 1).trim()) {
        return {hasProfile:false, profile:{valid:false, literalProfile:null, profiles:[]}};
    }

    var entries = [];
    var unsafeOverride = false;
    splitTopLevelObject(value.slice(openAt + 1, closeAt)).forEach(function(segment) {
        var property = trimLeadingComments(segment);
        if (!property) return;
        if (/^\.\.\./.test(property) || /^\[/.test(property)
                || /^[^:,{]*\\[^:]*:/.test(property)) {
            unsafeOverride = true;
        }

        var direct = /^(?:profile|(['"])profile\1)(?:\s*:\s*([\s\S]+))?$/.exec(property);
        if (direct) {
            entries.push(direct[2] == null ? null : direct[2].trim());
            return;
        }
        if (/^(?:profile|(['"])profile\1)\b/.test(property)
                || /^(?:get|set|async)\s+(?:profile|(['"])profile\1)\b/.test(property)
                || /^\[\s*(['"])profile\1\s*\]/.test(property)) {
            entries.push(null);
            unsafeOverride = true;
        }
    });

    var expression = entries.length === 1 && entries[0] != null
        ? analyzeClosedProfileExpression(entries[0])
        : {valid:false, literalProfile:null, profiles:[]};
    expression.valid = expression.valid && !unsafeOverride && entries.length === 1;
    return {hasProfile:entries.length > 0, profile:expression};
}

function scanDualPaneCalls(source, rel) {
    var calls = [];
    var callRe = /new\s+(?:[A-Za-z_$][\w$]*\.)*DualPaneShell\s*\(/g;
    var code = maskJavaScriptCode(source);
    var match;
    while ((match = callRe.exec(code)) !== null) {
        var openAt = code.indexOf('(', match.index);
        var closeAt = findMatchingJavaScriptDelimiter(source, openAt, '(', ')');
        var analysis = closeAt < 0
            ? {hasProfile:false, profile:{valid:false, literalProfile:null, profiles:[]}}
            : analyzeDualPaneOptions(source.slice(openAt + 1, closeAt));
        var profile = analysis.profile;
        calls.push({
            file:normalizeRel(rel),
            line:lineOf(source, match.index),
            hasProfile:analysis.hasProfile,
            literalProfile:profile.literalProfile,
            closedProfiles:profile.profiles,
            valid:analysis.hasProfile && profile.valid
        });
        if (closeAt < 0) break;
        callRe.lastIndex = closeAt + 1;
    }
    return calls;
}

function scanUnexpectedDualPaneReferences(source, rel) {
    var code = maskJavaScriptCode(source);
    var direct = {};
    var directRe = /new\s+(?:[A-Za-z_$][\w$]*\.)*DualPaneShell\s*\(/g;
    var match;
    while ((match = directRe.exec(code)) !== null) {
        direct[code.indexOf('DualPaneShell', match.index)] = true;
    }

    var findings = [];
    var tokenRe = /\bDualPaneShell\b/g;
    while ((match = tokenRe.exec(code)) !== null) {
        if (direct[match.index]) continue;
        findings.push({
            file:normalizeRel(rel),
            line:lineOf(source, match.index),
            kind:'non-direct-reference'
        });
    }

    var commentsMasked = maskJavaScriptComments(source);
    var bracketRe = /\[\s*(['"])DualPaneShell\1\s*\]/g;
    while ((match = bracketRe.exec(commentsMasked)) !== null) {
        findings.push({
            file:normalizeRel(rel),
            line:lineOf(source, match.index),
            kind:'bracket-reference'
        });
    }
    return findings;
}

function findDualPaneConstructor(source) {
    var code = maskJavaScriptCode(source);
    var declarations = code.match(/\bfunction\s+DualPaneShell\s*\(/g) || [];
    if (declarations.length !== 1) return null;
    var constructor = /\bfunction\s+DualPaneShell\s*\(\s*options(?:\s*=\s*\{\s*\})?\s*\)\s*\{/
        .exec(code);
    if (!constructor) return null;
    var bodyOpenAt = constructor.index + constructor[0].lastIndexOf('{');
    var bodyCloseAt = findClosingBrace(source, bodyOpenAt);
    if (bodyCloseAt < 0) return null;
    return {
        body:source.slice(bodyOpenAt + 1, bodyCloseAt)
    };
}

function isDirectConstructorStatement(code, statementAt) {
    var roundDepth = 0;
    var squareDepth = 0;
    var braceDepth = 0;
    var statementStart = 0;
    for (var index = 0; index < statementAt; index++) {
        var char = code[index];
        if (char === '(') {
            roundDepth++;
        } else if (char === ')') {
            roundDepth = Math.max(0, roundDepth - 1);
        } else if (char === '[') {
            squareDepth++;
        } else if (char === ']') {
            squareDepth = Math.max(0, squareDepth - 1);
        } else if (char === '{') {
            braceDepth++;
        } else if (char === '}') {
            braceDepth = Math.max(0, braceDepth - 1);
            if (roundDepth === 0 && squareDepth === 0 && braceDepth === 0) {
                statementStart = index + 1;
            }
        } else if (char === ';'
                && roundDepth === 0
                && squareDepth === 0
                && braceDepth === 0) {
            statementStart = index + 1;
        }
    }
    if (roundDepth !== 0 || squareDepth !== 0 || braceDepth !== 0) return false;
    var prefix = code.slice(statementStart, statementAt);
    if (/^\s*$/.test(prefix)) return true;
    var newlineAt = Math.max(prefix.lastIndexOf('\n'), prefix.lastIndexOf('\r'));
    if (newlineAt < 0 || !/^\s*$/.test(prefix.slice(newlineAt + 1))) return false;
    var previous = prefix.slice(0, newlineAt).trim();
    if (!previous) return true;
    return !/(?:^|\s)(?:else|do|return|throw)\s*$/.test(previous)
        && !/(?:^|[;}])\s*(?:if|for|while|with)\s*\([^;{}]*\)\s*$/.test(previous)
        && !/[:.,?+\-*\/%=&|!<>]\s*$/.test(previous);
}

function findNestedScopeBodyOpen(code, startAt) {
    var roundDepth = 0;
    var squareDepth = 0;
    for (var index = startAt; index < code.length; index++) {
        var char = code[index];
        if (char === '(') roundDepth++;
        else if (char === ')') roundDepth = Math.max(0, roundDepth - 1);
        else if (char === '[') squareDepth++;
        else if (char === ']') squareDepth = Math.max(0, squareDepth - 1);
        else if (char === '{' && roundDepth === 0 && squareDepth === 0) return index;
        else if (char === ';' && roundDepth === 0 && squareDepth === 0) return -1;
    }
    return -1;
}

function maskNestedFunctionBodies(source) {
    var code = maskJavaScriptCode(source);
    var output = code.split('');
    var scopeRe = /\bfunction\b|=>/g;
    var scope;
    while ((scope = scopeRe.exec(code)) !== null) {
        if (/^\s+$/.test(output.slice(scope.index, scopeRe.lastIndex).join(''))) {
            continue;
        }
        var bodyOpenAt;
        if (scope[0] === '=>') {
            bodyOpenAt = scopeRe.lastIndex;
            while (bodyOpenAt < code.length && /\s/.test(code[bodyOpenAt])) {
                bodyOpenAt++;
            }
            if (code[bodyOpenAt] !== '{') continue;
        } else {
            bodyOpenAt = findNestedScopeBodyOpen(code, scopeRe.lastIndex);
            if (bodyOpenAt < 0) continue;
        }
        var bodyCloseAt = findClosingBrace(code, bodyOpenAt);
        if (bodyCloseAt < 0) continue;
        for (var index = scope.index; index <= bodyCloseAt; index++) {
            if (output[index] !== '\r' && output[index] !== '\n') output[index] = ' ';
        }
        scopeRe.lastIndex = bodyCloseAt + 1;
    }
    var methodRe = /\b(?:async\s+|get\s+|set\s+)?([A-Za-z_$][\w$]*)\s*\([^;{}]*\)\s*\{/g;
    var method;
    while ((method = methodRe.exec(code)) !== null) {
        if (/^(?:catch|for|if|switch|while|with)$/.test(method[1])
                || /^\s+$/.test(output.slice(method.index, methodRe.lastIndex).join(''))) {
            continue;
        }
        var methodOpenAt = code.lastIndexOf('{', methodRe.lastIndex - 1);
        var methodCloseAt = findClosingBrace(code, methodOpenAt);
        if (methodCloseAt < 0) continue;
        for (var methodIndex = method.index; methodIndex <= methodCloseAt; methodIndex++) {
            if (output[methodIndex] !== '\r' && output[methodIndex] !== '\n') {
                output[methodIndex] = ' ';
            }
        }
        methodRe.lastIndex = methodCloseAt + 1;
    }
    return output.join('');
}

function hasExplicitConstructorExit(source) {
    var code = maskNestedFunctionBodies(source);
    var returnRe = /\breturn\b/g;
    var token;
    while ((token = returnRe.exec(code)) !== null) {
        var before = code.slice(0, token.index).match(/\S\s*$/);
        var after = code.slice(returnRe.lastIndex).match(/^\s*\S/);
        if (!(before && before[0].trim() === '.')
                && !(after && after[0].trim() === ':')) {
            return true;
        }
    }
    var throwRe = /\bthrow\b/g;
    while ((token = throwRe.exec(code)) !== null) {
        if (isDirectConstructorStatement(code, token.index)) return true;
    }
    return false;
}

function hasExplicitRootInitialization(source) {
    return /\bthis\._root\s*=(?!=)/.test(maskNestedFunctionBodies(source));
}

function scanLiteralRootProfileWrites(body, validatedName) {
    var code = maskJavaScriptCode(body);
    var escapedName = validatedName.replace(/[$]/g, '\\$&');
    var writes = [];
    var setterRe = /\bthis\._root\.setAttribute\s*\(/g;
    var setter;
    while ((setter = setterRe.exec(code)) !== null) {
        var openAt = setterRe.lastIndex - 1;
        var closeAt = findMatchingJavaScriptDelimiter(body, openAt, '(', ')');
        if (closeAt < 0) continue;
        var args = splitTopLevelObject(body.slice(openAt + 1, closeAt))
            .map(function(arg) { return maskJavaScriptComments(arg).trim(); });
        if (args.length > 0 && /^(['"])data-profile\1$/.test(args[0])) {
            writes.push({
                index:setter.index,
                valid:args.length === 2
                    && new RegExp('^' + escapedName + '$').test(args[1])
            });
        }
        setterRe.lastIndex = closeAt + 1;
    }
    return writes;
}

function profileContractImplemented(workbenchSource) {
    var source = String(workbenchSource || '');
    var constructor = findDualPaneConstructor(source);
    if (!constructor) return false;
    var body = constructor.body;
    var bodyCode = maskJavaScriptCode(body);
    var profileOwnerTokens = bodyCode.match(/\bWorkbenchShellProfile\b/g) || [];
    if (profileOwnerTokens.length !== 1) return false;

    var validationRe = /\bconst\s+([A-Za-z_$][\w$]*)\s*=\s*(?:WorkbenchShellProfile\s*\.\s*requireProfile\s*\(\s*options\s*\.\s*profile\s*\)|\(\s*WorkbenchShellProfile\s*\.\s*requireProfile\s*\(\s*options\s*\.\s*profile\s*\)\s*\))[ \t]*(?:;|(?=\r?\n|$))/g;
    var validations = [];
    var validation;
    while ((validation = validationRe.exec(bodyCode)) !== null) validations.push(validation);
    if (validations.length !== 1) return false;
    validation = validations[0];
    if (!isDirectConstructorStatement(bodyCode, validation.index)) return false;
    var validatedName = validation[1];
    var escapedName = validatedName.replace(/[$]/g, '\\$&');
    var validationEnd = validation.index + validation[0].length;
    if (hasExplicitConstructorExit(body.slice(0, validation.index))
            || hasExplicitRootInitialization(body.slice(0, validation.index))) {
        return false;
    }

    var codeWithoutDeclaration = bodyCode.slice(0, validation.index)
        + bodyCode.slice(validation.index, validationEnd).replace(/[^\r\n]/g, ' ')
        + bodyCode.slice(validationEnd);
    var reassignment = new RegExp(
        '(?:^|[^\\w$\\.])' + escapedName
            + '\\s*(?:=(?!=)|\\+=|-=|\\*=|\\/=|%=|\\*\\*=|<<=|>>=|>>>=|&=|\\|=|\\^=|\\?\\?=|&&=|\\|\\|=|\\+\\+|--)'
            + '|(?:\\+\\+|--)\\s*' + escapedName + '\\b'
    ).test(codeWithoutDeclaration);
    var destructuringReassignment = new RegExp(
        '(?:\\[[^;]*\\b' + escapedName + '\\b[^;]*\\]'
            + '|\\{[^;]*\\b' + escapedName + '\\b[^;]*\\})\\s*='
    ).test(codeWithoutDeclaration);
    var loopReassignment = new RegExp(
        '\\bfor(?:\\s+await)?\\s*\\(\\s*(?:'
            + escapedName
            + '|\\[[^;)]*\\b' + escapedName + '\\b[^;)]*\\]'
            + '|\\{[^;)]*\\b' + escapedName + '\\b[^;)]*\\})'
            + '\\s+(?:in|of)\\b'
    ).test(codeWithoutDeclaration);
    if (reassignment || destructuringReassignment || loopReassignment) return false;

    var writes = scanLiteralRootProfileWrites(body, validatedName);
    if (writes.length !== 1
            || !writes[0].valid
            || writes[0].index < validationEnd
            || !isDirectConstructorStatement(bodyCode, writes[0].index)) {
        return false;
    }
    return !hasExplicitConstructorExit(body.slice(validationEnd, writes[0].index));
}

function evaluateProfileGate(configEnabled, structureReady) {
    var configured = configEnabled === true;
    var ready = structureReady === true;
    return {
        valid:configured === ready,
        enabled:configured && ready,
        configuredEnabled:configured,
        structureReady:ready,
        reason:configured === ready
            ? null
            : (configured
                ? 'profile gate flag is enabled before the shell contract is structurally ready'
                : 'profile shell contract appeared before the explicit E-batch gate was enabled')
    };
}

module.exports = {
    F0_BASELINE_COMMIT:F0_BASELINE_COMMIT,
    VALID_PROFILES:VALID_PROFILES,
    DEBT_RULES:DEBT_RULES,
    maskComments:maskComments,
    maskCssCommentsAndStrings:maskCssCommentsAndStrings,
    maskJavaScriptComments:maskJavaScriptComments,
    maskJavaScriptCode:maskJavaScriptCode,
    maskPowerShellComments:maskPowerShellComments,
    scanImportantDeclarations:scanImportantDeclarations,
    scanCssDeclarations:scanCssDeclarations,
    scanVisibleImportantDisplayDeclarations:scanVisibleImportantDisplayDeclarations,
    scanUnlayeredFocusOutlineOverrides:scanUnlayeredFocusOutlineOverrides,
    scanCss:scanCss,
    countsByRule:countsByRule,
    parseUnifiedZeroDiff:parseUnifiedZeroDiff,
    evaluateDebtRatchet:evaluateDebtRatchet,
    auditCssDebt:auditCssDebt,
    auditCurrentCssDebt:auditCurrentCssDebt,
    previousCommittedFile:previousCommittedFile,
    scanDualPaneCalls:scanDualPaneCalls,
    scanUnexpectedDualPaneReferences:scanUnexpectedDualPaneReferences,
    profileContractImplemented:profileContractImplemented,
    evaluateProfileGate:evaluateProfileGate
};
