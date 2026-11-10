#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const readline = require('readline');

const CATEGORY_ORDER = Object.freeze([
    'disconnected',
    'paused_or_inactive',
    'insufficient_evidence',
    'frame_pipeline_stalled',
    'transport_quiet_unknown',
    'render_policy_rejected',
    'source_sample_stale',
    'healthy'
]);

const SOURCE_SAMPLE_STALE_MS = 2000;
const RENDER_POLICY_MAX_SOURCE_RATE_PER_SECOND = 120;
const DEFAULT_THRESHOLDS = Object.freeze({
    transportFreshMs: 2000,
    frameIngressStaleMs: 2000,
    sourceSampleStaleMs: SOURCE_SAMPLE_STALE_MS
});
const REQUIRED_CURRENT_FIELDS = Object.freeze([
    'hostFrameOrdinal',
    'sourceSampleSequence',
    'acceptedSampleFrame',
    'connectionGeneration',
    'sourceScene',
    'transportAgeMs',
    'frameIngressAgeMs',
    'sampleAgeMs'
]);
const REQUIRED_PREVIOUS_FIELDS = Object.freeze([
    'hostFrameOrdinal',
    'sourceSampleSequence',
    'acceptedSampleFrame',
    'connectionGeneration',
    'sourceScene'
]);
let temporaryFileCounter = 0;

function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isSequence(value) {
    return Number.isSafeInteger(value) && value >= 0;
}

function isAge(value) {
    return Number.isFinite(value) && value >= 0;
}

function hasOwnField(record, field) {
    return isObject(record)
        && Object.prototype.hasOwnProperty.call(record, field)
        && record[field] !== undefined;
}

function isValidField(record, field) {
    if (!hasOwnField(record, field)) return false;
    if (field === 'acceptedSampleFrame') {
        return record[field] === null || isSequence(record[field]);
    }
    if (field.endsWith('AgeMs')) return isAge(record[field]);
    return isSequence(record[field]);
}

function positiveThreshold(value, fallback, name) {
    if (value === undefined) return fallback;
    if (!Number.isFinite(value) || value <= 0) {
        throw new TypeError(name + ' must be a positive finite number');
    }
    return value;
}

function resolveThresholds(options) {
    const supplied = isObject(options) && isObject(options.thresholds) ? options.thresholds : (options || {});
    if (supplied.sourceSampleStaleMs !== undefined && supplied.sourceSampleStaleMs !== SOURCE_SAMPLE_STALE_MS) {
        throw new TypeError('sourceSampleStaleMs is fixed at 2000ms');
    }
    return {
        transportFreshMs: positiveThreshold(
            supplied.transportFreshMs, DEFAULT_THRESHOLDS.transportFreshMs, 'transportFreshMs'),
        frameIngressStaleMs: positiveThreshold(
            supplied.frameIngressStaleMs, DEFAULT_THRESHOLDS.frameIngressStaleMs, 'frameIngressStaleMs'),
        sourceSampleStaleMs: SOURCE_SAMPLE_STALE_MS
    };
}

function numericEvidence(record, field) {
    return isObject(record) && typeof record[field] === 'number' && Number.isFinite(record[field])
        ? record[field]
        : null;
}

function sequenceEvidence(record, previous, field) {
    const currentValue = numericEvidence(record, field);
    const previousValue = numericEvidence(previous, field);
    let advanced = null;
    if (isSequence(currentValue) && isSequence(previousValue)) {
        advanced = currentValue > previousValue;
    } else if (field === 'acceptedSampleFrame'
        && isValidField(record, field)
        && isValidField(previous, field)) {
        advanced = previousValue === null && isSequence(currentValue);
    }
    return {
        previous: previousValue,
        current: currentValue,
        advanced
    };
}

function collectMissingFields(sample, previous) {
    const missing = REQUIRED_CURRENT_FIELDS.filter(field => !isValidField(sample, field));
    if (!isObject(previous)) {
        missing.push('previous_sample');
    } else {
        REQUIRED_PREVIOUS_FIELDS.forEach(field => {
            if (!isValidField(previous, field)) missing.push('previous.' + field);
        });
    }
    return missing;
}

function result(category, reasonCode, reason, evidence) {
    return { category, reasonCode, reason, evidence };
}

function classifyPerfSample(sample, previous, options) {
    const current = isObject(sample) ? sample : {};
    const thresholds = resolveThresholds(options);

    if (current.connected === false || current.connectionState === 'disconnected') {
        return result('disconnected', 'explicit_disconnect',
            'connected=false 或 connectionState=disconnected，报文明确证明断连。',
            { connected: current.connected, connectionState: current.connectionState });
    }

    if (current.paused === true || current.foreground === false || current.minimized === true) {
        const triggers = [];
        if (current.paused === true) triggers.push('paused=true');
        if (current.foreground === false) triggers.push('foreground=false');
        if (current.minimized === true) triggers.push('minimized=true');
        return result('paused_or_inactive', 'explicit_inactive',
            triggers.join('、') + '，采样处于暂停、后台或最小化状态。', { triggers });
    }

    const missingFields = collectMissingFields(current, previous);
    if (missingFields.length > 0) {
        return result('insufficient_evidence', 'missing_required_evidence',
            '缺少必要字段或前序基线：' + missingFields.join('、') + '；不作猜测。',
            { missingFields });
    }

    if (current.connectionGeneration !== previous.connectionGeneration) {
        return result('insufficient_evidence', 'generation_changed',
            'connectionGeneration 从 ' + previous.connectionGeneration + ' 变为 '
                + current.connectionGeneration + '；不跨连接代际比较序号。',
            {
                connectionGeneration: {
                    previous: previous.connectionGeneration,
                    current: current.connectionGeneration
                }
            });
    }

    if (current.sourceScene !== previous.sourceScene) {
        return result('insufficient_evidence', 'source_scene_changed',
            'sourceScene 从 ' + JSON.stringify(previous.sourceScene) + ' 变为 '
                + JSON.stringify(current.sourceScene) + '；不跨场景比较 sourceSampleSequence。',
            {
                sourceScene: {
                    previous: previous.sourceScene,
                    current: current.sourceScene
                }
            });
    }

    const evidence = {
        hostFrameOrdinal: sequenceEvidence(current, previous, 'hostFrameOrdinal'),
        sourceSampleSequence: sequenceEvidence(current, previous, 'sourceSampleSequence'),
        acceptedSampleFrame: sequenceEvidence(current, previous, 'acceptedSampleFrame'),
        transportAgeMs: current.transportAgeMs,
        frameIngressAgeMs: current.frameIngressAgeMs,
        sampleAgeMs: current.sampleAgeMs,
        sampleRejectReason: current.sampleRejectReason === undefined ? null : current.sampleRejectReason,
        thresholds
    };

    const transportFresh = current.transportAgeMs <= thresholds.transportFreshMs;
    const transportStale = current.transportAgeMs > thresholds.transportFreshMs;
    const frameStale = current.frameIngressAgeMs > thresholds.frameIngressStaleMs;

    if (!evidence.hostFrameOrdinal.advanced && transportFresh && frameStale) {
        return result('frame_pipeline_stalled', 'transport_fresh_frame_stale',
            'hostFrameOrdinal 未推进；transportAgeMs=' + current.transportAgeMs + 'ms 仍新鲜（<='
                + thresholds.transportFreshMs + 'ms），frameIngressAgeMs=' + current.frameIngressAgeMs
                + 'ms 超阈值（>' + thresholds.frameIngressStaleMs + 'ms）。',
            evidence);
    }

    if (!evidence.hostFrameOrdinal.advanced && transportStale && frameStale) {
        return result('transport_quiet_unknown', 'frame_and_transport_quiet',
            'hostFrameOrdinal 与 JSON 传输均超过新鲜度阈值，但没有明确断连证据；原因未知。',
            evidence);
    }

    if (evidence.sourceSampleSequence.advanced && !evidence.acceptedSampleFrame.advanced
        && current.sampleRejectReason === 'rate_out_of_policy') {
        return result('render_policy_rejected', 'source_advanced_accepted_sample_frame_stopped_by_policy',
            'sourceSampleSequence 推进而 acceptedSampleFrame 未推进，且 sampleRejectReason=rate_out_of_policy'
                + '（源频率 >' + RENDER_POLICY_MAX_SOURCE_RATE_PER_SECOND + '/s 时被策略拒绝）。',
            evidence);
    }

    if (evidence.hostFrameOrdinal.advanced && !evidence.sourceSampleSequence.advanced
        && current.sampleAgeMs > SOURCE_SAMPLE_STALE_MS) {
        return result('source_sample_stale', 'frame_advanced_source_stale',
            'hostFrameOrdinal 推进但 sourceSampleSequence 重复或停止，且 sampleAgeMs=' + current.sampleAgeMs
                + 'ms 超过固定阈值 2000ms。',
            evidence);
    }

    if (evidence.hostFrameOrdinal.advanced && evidence.sourceSampleSequence.advanced
        && evidence.acceptedSampleFrame.advanced) {
        return result('healthy', 'all_required_sequences_advanced',
            'hostFrameOrdinal、新 sourceSampleSequence 与 acceptedSampleFrame 均推进。', evidence);
    }

    return result('insufficient_evidence', 'no_rule_matched',
        '现有证据未满足任何后续分类规则；不作猜测。', evidence);
}

function emptyCounts() {
    const counts = {};
    CATEGORY_ORDER.forEach(category => { counts[category] = 0; });
    return counts;
}

function isPerfSample(record) {
    return record.type === 'perf_sample' || record.event === 'perf_sample' || record.kind === 'perf_sample';
}

async function analyzeLines(lines, options) {
    const settings = options || {};
    const report = {
        schema: 'cf7.perf-session-analysis.v1',
        inputPath: settings.inputPath || null,
        inputLineCount: 0,
        blankLineCount: 0,
        badLineCount: 0,
        perfSampleCount: 0,
        otherRecordCount: 0,
        thresholds: Object.assign({}, resolveThresholds(settings), {
            renderPolicyMaxSourceRatePerSecond: RENDER_POLICY_MAX_SOURCE_RATE_PER_SECOND
        }),
        classificationCounts: emptyCounts(),
        decisions: [],
        badLines: []
    };
    let previous = null;

    for await (const rawLine of lines) {
        report.inputLineCount += 1;
        const lineNumber = report.inputLineCount;
        let line = String(rawLine);
        if (lineNumber === 1 && line.charCodeAt(0) === 0xfeff) line = line.slice(1);
        if (line.trim() === '') {
            report.blankLineCount += 1;
            continue;
        }

        let record;
        try {
            record = JSON.parse(line);
            if (!isObject(record)) throw new TypeError('JSON line is not an object');
        } catch (error) {
            report.badLineCount += 1;
            report.badLines.push({ lineNumber, error: String(error.message || error).slice(0, 300) });
            continue;
        }

        if (!isPerfSample(record)) {
            report.otherRecordCount += 1;
            continue;
        }

        report.perfSampleCount += 1;
        const classification = classifyPerfSample(record, previous, settings);
        const decision = Object.assign({
            sampleIndex: report.perfSampleCount,
            lineNumber
        }, classification);
        if (record.timestamp !== undefined) decision.timestamp = record.timestamp;
        else if (record.timestampMs !== undefined) decision.timestampMs = record.timestampMs;
        report.classificationCounts[decision.category] += 1;
        report.decisions.push(decision);
        previous = record;
    }

    return report;
}

async function analyzePerfSession(filePath, options) {
    const input = fs.createReadStream(filePath, { encoding: 'utf8' });
    const lines = readline.createInterface({ input, crlfDelay: Infinity });
    try {
        return await analyzeLines(lines, Object.assign({}, options || {}, {
            inputPath: path.resolve(filePath)
        }));
    } finally {
        lines.close();
        input.destroy();
    }
}

function writeJsonAtomic(filePath, value) {
    const target = path.resolve(filePath);
    temporaryFileCounter += 1;
    const temporary = path.join(path.dirname(target), '.' + path.basename(target) + '.'
        + process.pid + '.' + Date.now() + '.' + temporaryFileCounter + '.tmp');
    let renamed = false;
    try {
        fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n', { encoding: 'utf8', flag: 'wx' });
        fs.renameSync(temporary, target);
        renamed = true;
    } catch (error) {
        throw new Error('无法原子写入 JSON 输出 ' + target + '：' + (error.message || String(error)));
    } finally {
        if (!renamed) {
            try { fs.unlinkSync(temporary); } catch (error) { /* 写入失败时保留原始错误。 */ }
        }
    }
}

function formatHumanSummary(report) {
    const lines = [
        'Perf session：' + (report.inputPath || '<memory>'),
        '输入 ' + report.inputLineCount + ' 行：perf_sample=' + report.perfSampleCount
            + '，其他记录=' + report.otherRecordCount + '，坏行=' + report.badLineCount
            + '，空行=' + report.blankLineCount + '。',
        '阈值：transport 新鲜 <= ' + report.thresholds.transportFreshMs
            + 'ms；frame ingress 停滞 > ' + report.thresholds.frameIngressStaleMs
            + 'ms；source 过期 > ' + report.thresholds.sourceSampleStaleMs + 'ms（固定）。',
        '分类：' + CATEGORY_ORDER.map(category => category + '=' + report.classificationCounts[category]).join('，')
    ];
    if (report.perfSampleCount === 0) lines.push('没有可分类的 perf_sample；不作分类推断。');
    if (report.badLineCount > 0) {
        lines.push('坏行位置：' + report.badLines.map(row => row.lineNumber).join('、') + '（详见 JSON）。');
    }
    return lines.join('\n');
}

function parsePositiveOption(value, name) {
    if (value === undefined || value === '') throw new Error(name + ' 需要一个正数');
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed <= 0) throw new Error(name + ' 需要一个正数');
    return parsed;
}

function parseArgs(argv) {
    const parsed = { input: null, json: null, thresholds: {}, help: false };
    for (let index = 0; index < argv.length; index += 1) {
        const argument = argv[index];
        if (argument === '--help' || argument === '-h') {
            parsed.help = true;
        } else if (argument === '--json') {
            parsed.json = argv[index + 1];
            index += 1;
            if (!parsed.json) throw new Error('--json 需要输出文件路径');
        } else if (argument === '--transport-fresh-ms') {
            parsed.thresholds.transportFreshMs = parsePositiveOption(argv[index + 1], argument);
            index += 1;
        } else if (argument === '--frame-ingress-stale-ms') {
            parsed.thresholds.frameIngressStaleMs = parsePositiveOption(argv[index + 1], argument);
            index += 1;
        } else if (argument.startsWith('--')) {
            throw new Error('未知参数：' + argument);
        } else if (parsed.input === null) {
            parsed.input = argument;
        } else {
            throw new Error('只能指定一个输入 JSONL 文件');
        }
    }
    if (!parsed.help && (!parsed.input || !parsed.json)) {
        throw new Error('必须指定输入 JSONL 与 --json 输出文件');
    }
    return parsed;
}

function usage() {
    return '用法：node tools/analyze-perf-session.js <session.jsonl> --json <out.json>\n'
        + '可选：--transport-fresh-ms <ms> --frame-ingress-stale-ms <ms>';
}

function normalizePathForComparison(filePath, platform) {
    const resolved = path.resolve(String(filePath));
    return (platform || process.platform) === 'win32' ? resolved.toLowerCase() : resolved;
}

function isSameFilePath(inputPath, outputPath, platform) {
    const activePlatform = platform || process.platform;
    if (normalizePathForComparison(inputPath, activePlatform)
        === normalizePathForComparison(outputPath, activePlatform)) {
        return true;
    }
    try {
        const realpath = typeof fs.realpathSync.native === 'function'
            ? fs.realpathSync.native
            : fs.realpathSync;
        const realInput = realpath(inputPath);
        const realOutput = realpath(outputPath);
        if (normalizePathForComparison(realInput, activePlatform)
            === normalizePathForComparison(realOutput, activePlatform)) {
            return true;
        }
    } catch (error) {
        /* 任一路径尚不存在时继续后续检查。 */
    }
    try {
        const inputStat = fs.statSync(inputPath, { bigint: true });
        const outputStat = fs.statSync(outputPath, { bigint: true });
        if (inputStat.ino > 0n && inputStat.ino === outputStat.ino
            && inputStat.dev === outputStat.dev) {
            return true;
        }
    } catch (error) {
        /* 任一路径尚不存在时忽略文件索引比较。 */
    }
    return false;
}

async function main(argv) {
    const args = parseArgs(argv);
    if (args.help) {
        console.log(usage());
        return;
    }
    if (isSameFilePath(args.input, args.json)) {
        throw new Error('JSON 输出不能覆盖输入 JSONL');
    }
    const report = await analyzePerfSession(args.input, { thresholds: args.thresholds });
    writeJsonAtomic(args.json, report);
    console.log(formatHumanSummary(report));
    console.log('JSON 输出：' + path.resolve(args.json));
}

module.exports = {
    CATEGORY_ORDER,
    DEFAULT_THRESHOLDS,
    SOURCE_SAMPLE_STALE_MS,
    analyzeLines,
    analyzePerfSession,
    classifyPerfSample,
    classifySample: classifyPerfSample,
    formatHumanSummary,
    isSameFilePath,
    main,
    resolveThresholds,
    writeJsonAtomic
};

if (require.main === module) {
    main(process.argv.slice(2)).catch(error => {
        console.error('[analyze-perf-session] ' + (error.message || String(error)));
        console.error(usage());
        process.exitCode = 1;
    });
}
