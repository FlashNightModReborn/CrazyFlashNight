(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.ArenaCustomParameters = factory();
    }
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
    'use strict';

    function matchCodeCodec() {
        return typeof ArenaCustomMatchCode !== 'undefined' ? ArenaCustomMatchCode : null;
    }

    function has(value) {
        var codec = matchCodeCodec();
        if (codec && codec.hasParameters) return codec.hasParameters(value);
        return !!(value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length);
    }

    function clone(value) {
        if (!has(value)) return null;
        var codec = matchCodeCodec();
        if (codec && codec.cloneParameters) return codec.cloneParameters(value);
        return JSON.parse(JSON.stringify(value));
    }

    function text(value) {
        if (!has(value)) return '';
        var codec = matchCodeCodec();
        if (codec && codec.stableStringify) return codec.stableStringify(value);
        return JSON.stringify(value);
    }

    function equal(a, b) {
        return text(a) === text(b);
    }

    function formatJson(value) {
        if (!has(value)) return '';
        return JSON.stringify(clone(value), null, 2);
    }

    function parseJson(textValue) {
        textValue = String(textValue || '').trim();
        if (!textValue) return { ok: true, value: null };
        try {
            var value = JSON.parse(textValue);
            if (!has(value)) {
                return { ok: false, error: '参数必须是非空 JSON 对象' };
            }
            return { ok: true, value: value };
        } catch (err) {
            return { ok: false, error: 'JSON 参数格式错误' };
        }
    }

    function parseXml(textValue) {
        textValue = String(textValue || '').trim();
        if (!textValue) return { ok: true, value: null };
        try {
            var body = unwrapXmlRoot(textValue, 'Parameters');
            var value = parseXmlBody(body);
            if (!has(value)) {
                return { ok: false, error: 'XML 参数必须包含至少一个字段' };
            }
            return { ok: true, value: value };
        } catch (err) {
            return { ok: false, error: err && err.message ? err.message : 'XML 参数格式错误' };
        }
    }

    function parseDraft(mode, textValue) {
        return mode === 'xml' ? parseXml(textValue) : parseJson(textValue);
    }

    function unwrapXmlRoot(textValue, rootName) {
        var re = new RegExp('^<' + rootName + '(?:\\s[^>]*)?>\\s*([\\s\\S]*?)\\s*</' + rootName + '>\\s*$', 'i');
        var match = String(textValue || '').match(re);
        return match ? match[1].trim() : textValue;
    }

    function parseXmlBody(xml) {
        var textValue = String(xml == null ? '' : xml).trim();
        if (!textValue) return {};

        if (textValue.indexOf('<') < 0) {
            return parseStringParameters(textValue) || { value: parseScalar(textValue) };
        }

        var out = {};
        var childRe = /<([^\s/>]+)(?:\s[^>]*)?>\s*([\s\S]*?)\s*<\/\1>/g;
        var match;
        var count = 0;
        while ((match = childRe.exec(textValue))) {
            count++;
            var key = match[1];
            var body = match[2].trim();
            var value = body.indexOf('<') >= 0
                ? parseXmlBody(body)
                : parseScalar(decodeXmlText(body));
            addObjectValue(out, key, value);
        }

        if (count > 0) return out;
        if (textValue.indexOf('<') >= 0 || textValue.indexOf('>') >= 0) throw new Error('XML 参数标签未闭合或格式错误');
        return parseStringParameters(textValue) || { value: parseScalar(decodeXmlText(textValue)) };
    }

    function parseStringParameters(textValue) {
        var out = {};
        var parts = String(textValue || '').split(',');
        var parsed = 0;
        for (var i = 0; i < parts.length; i++) {
            var part = parts[i].trim();
            if (!part) continue;
            var idx = part.indexOf(':');
            if (idx <= 0) continue;
            var key = part.slice(0, idx).trim();
            var value = part.slice(idx + 1).trim();
            if (!key) continue;
            out[key] = parseScalar(value);
            parsed++;
        }
        return parsed > 0 ? out : null;
    }

    function parseScalar(value) {
        var textValue = String(value == null ? '' : value).trim();
        if (textValue === 'true') return true;
        if (textValue === 'false') return false;
        if (/^-?(?:\d+|\d+\.\d+)$/.test(textValue)) return Number(textValue);
        return textValue;
    }

    function addObjectValue(obj, key, value) {
        if (Object.prototype.hasOwnProperty.call(obj, key)) {
            if (!Array.isArray(obj[key])) obj[key] = [obj[key]];
            obj[key].push(value);
        } else {
            obj[key] = value;
        }
    }

    function decodeXmlText(textValue) {
        return String(textValue || '')
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>')
            .replace(/&quot;/g, '"')
            .replace(/&apos;/g, "'")
            .replace(/&amp;/g, '&');
    }

    function encodeXmlText(textValue) {
        return String(textValue == null ? '' : textValue)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&apos;');
    }

    function formatXml(parameters) {
        if (!has(parameters)) return '<Parameters>\n</Parameters>';
        var lines = ['<Parameters>'];
        appendXmlObject(lines, clone(parameters), 1);
        lines.push('</Parameters>');
        return lines.join('\n');
    }

    function appendXmlObject(lines, obj, depth) {
        var keys = Object.keys(obj || {}).sort();
        for (var i = 0; i < keys.length; i++) {
            appendXmlValue(lines, keys[i], obj[keys[i]], depth);
        }
    }

    function appendXmlValue(lines, key, value, depth) {
        if (!isXmlTagName(key)) throw new Error('字段名无法作为 XML 标签: ' + key);
        if (Array.isArray(value)) {
            for (var i = 0; i < value.length; i++) appendXmlValue(lines, key, value[i], depth);
            return;
        }
        var indent = repeatString('  ', depth);
        if (value && typeof value === 'object') {
            lines.push(indent + '<' + key + '>');
            appendXmlObject(lines, value, depth + 1);
            lines.push(indent + '</' + key + '>');
        } else {
            lines.push(indent + '<' + key + '>' + encodeXmlText(value) + '</' + key + '>');
        }
    }

    function isXmlTagName(key) {
        return /^[^\s<>&/="'?]+$/.test(String(key || ''));
    }

    function repeatString(textValue, count) {
        var out = '';
        for (var i = 0; i < count; i++) out += textValue;
        return out;
    }

    return {
        clone: clone,
        has: has,
        text: text,
        equal: equal,
        formatJson: formatJson,
        parseJson: parseJson,
        parseXml: parseXml,
        parseDraft: parseDraft,
        formatXml: formatXml
    };
});
