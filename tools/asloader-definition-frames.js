'use strict';

// Split definitions, never execution stages. The state machine starts only after
// every staged function has been installed on the same _root.__boot object.
// The source budget partitions complete functions; it is not a codeSize gate.
const SOURCE_BUDGET = 240000;
const OWNED_PREFIX = '// asLoader 定义分段（由 tools/assemble-collapsed-frame.js 生成，勿手改）';

function build(master, expectedNames, sourceBytes, symbolXml) {
    const matches = [...master.matchAll(/^_root\.__boot\.(f\d+(?:_\d+)?) = function\(\) \{/gm)];
    if (!matches.length || matches.map(match => match[1]).join('\n') !== expectedNames.join('\n'))
        throw new Error('Definition frames must contain every source function once, in original order');
    const wiringAt = master.indexOf('// === 由 BOOT_SOURCES 派生的纯装配 stage');
    if (wiringAt <= matches[matches.length - 1].index) throw new Error('Missing final stage wiring');
    const prefix = master.slice(0, matches[0].index), suffix = master.slice(wiringAt);
    if ((prefix.match(/^this\.stop\(\);$/gm) || []).length !== 1
            || (suffix.match(/^BootSequencer\.run\(this\);$/gm) || []).length !== 1)
        throw new Error('Definition frames require one host stop and one final state-machine entry');
    const groups = [];
    matches.forEach((match, index) => {
        const weight = sourceBytes[match[1]];
        if (!Number.isInteger(weight) || weight < 1) throw new Error('Missing source measure: ' + match[1]);
        const end = index + 1 < matches.length ? matches[index + 1].index : wiringAt;
        const body = master.slice(match.index, end);
        if (!groups.length || groups[groups.length - 1].sourceBytes + weight > SOURCE_BUDGET)
            groups.push({names: [], body: '', sourceBytes: 0});
        const group = groups[groups.length - 1];
        group.names.push(match[1]); group.body += body; group.sourceBytes += weight;
    });
    if (groups.map(group => group.body).join('') !== master.slice(matches[0].index, wiringAt))
        throw new Error('Definition partition changed executable source');
    const files = groups.map((group, index) => {
        const final = index === groups.length - 1;
        const file = '_definition_frame' + String(index).padStart(2, '0') + '.as';
        const framePrefix = final ? prefix : prefix.replace(/^this\.stop\(\);$/m, 'this.play();');
        return {file, names: group.names, sourceBytes: group.sourceBytes,
            text: OWNED_PREFIX + '\n' + framePrefix + group.body + (final ? suffix : '')};
    });
    // Only the existing, single boot layer is owned. Unrelated timeline edits
    // must be reconciled explicitly instead of being silently overwritten.
    if (!/^<DOMSymbolItem\b[^>]*\bname="asLoader"/.test(symbolXml)
            || (symbolXml.match(/<DOMLayer\b/g) || []).length !== 1
            || !/<DOMLayer\b[^>]*\bname="boot"/.test(symbolXml)
            || (symbolXml.match(/<frames>/g) || []).length !== 1)
        throw new Error('asLoader symbol is not the owned single boot layer');
    const frames = files.map((entry, index) => [
        '            <DOMFrame index="' + index + '" keyMode="9728">',
        '              <Actionscript>',
        '                <script><![CDATA[#include "../asLoaderManifest/' + entry.file + '"]]></script>',
        '              </Actionscript>',
        '              <elements/>',
        '            </DOMFrame>'
    ].join('\n')).join('\n');
    const xml = symbolXml.replace(/<frames>[\s\S]*?<\/frames>/,
        '<frames>\n' + frames + '\n          </frames>');
    return {files, xml, sourceBudget: SOURCE_BUDGET};
}

module.exports = {build, OWNED_PREFIX};
