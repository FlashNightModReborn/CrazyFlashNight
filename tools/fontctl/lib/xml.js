'use strict';

class XmlSyntaxError extends Error {
    constructor(code, message, file, line, column) {
        super(message);
        this.name = 'XmlSyntaxError';
        this.code = code;
        this.file = file;
        this.line = line;
        this.column = column;
    }
}

function buildLineStarts(source) {
    const starts = [0];
    for (let index = 0; index < source.length; index += 1) {
        if (source.charCodeAt(index) === 10) starts.push(index + 1);
    }
    return starts;
}

function locate(lineStarts, index) {
    let low = 0;
    let high = lineStarts.length;
    while (low + 1 < high) {
        const middle = (low + high) >>> 1;
        if (lineStarts[middle] <= index) low = middle;
        else high = middle;
    }
    return { line: low + 1, column: index - lineStarts[low] + 1 };
}

function decodeEntities(value, fail) {
    return value.replace(/&([^;]+);/g, (match, entity) => {
        if (entity === 'amp') return '&';
        if (entity === 'lt') return '<';
        if (entity === 'gt') return '>';
        if (entity === 'quot') return '"';
        if (entity === 'apos') return "'";

        let codePoint = null;
        if (/^#\d+$/.test(entity)) codePoint = Number(entity.slice(1));
        if (/^#x[0-9a-f]+$/i.test(entity)) codePoint = Number.parseInt(entity.slice(2), 16);
        if (codePoint === null
            || !Number.isInteger(codePoint)
            || codePoint < 0
            || codePoint > 0x10ffff
            || (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
            fail('XML_ENTITY', `不支持或非法的 XML entity：&${entity};`);
        }
        return String.fromCodePoint(codePoint);
    });
}

function parseXml(sourceText, file) {
    const source = sourceText.charCodeAt(0) === 0xfeff ? sourceText.slice(1) : sourceText;
    const lineStarts = buildLineStarts(source);
    let index = 0;
    let root = null;
    let declarationSeen = false;
    const stack = [];

    function fail(code, message, at = index) {
        const position = locate(lineStarts, Math.min(at, source.length));
        throw new XmlSyntaxError(code, message, file, position.line, position.column);
    }

    function skipWhitespace() {
        while (index < source.length && /\s/.test(source[index])) index += 1;
    }

    function readName() {
        const start = index;
        if (index >= source.length || !/[A-Za-z_]/.test(source[index])) {
            fail('XML_NAME', 'XML 元素或属性名非法');
        }
        index += 1;
        while (index < source.length && /[A-Za-z0-9_.-]/.test(source[index])) index += 1;
        return source.slice(start, index);
    }

    function skipComment() {
        const end = source.indexOf('-->', index + 4);
        if (end < 0) fail('XML_COMMENT', 'XML 注释未闭合');
        if (source.slice(index + 4, end).includes('--')) {
            fail('XML_COMMENT', 'XML 注释内容不得包含 --');
        }
        index = end + 3;
    }

    function skipDeclaration() {
        const start = index;
        const end = source.indexOf('?>', index + 2);
        if (end < 0) fail('XML_DECLARATION', 'XML 声明未闭合');
        if (root || stack.length || declarationSeen || !/^<\?xml(?:\s|\?)/i.test(source.slice(start, end + 2))) {
            fail('XML_PROCESSING_INSTRUCTION', '只允许文档开头出现一次 XML declaration', start);
        }
        declarationSeen = true;
        index = end + 2;
    }

    while (index < source.length) {
        if (source.startsWith('<!--', index)) {
            skipComment();
            continue;
        }
        if (source.startsWith('<?', index)) {
            skipDeclaration();
            continue;
        }
        if (source.startsWith('<!DOCTYPE', index) || source.startsWith('<!ENTITY', index)) {
            fail('XML_DTD_FORBIDDEN', '字体目录禁止 DTD 与自定义 entity');
        }

        if (source[index] !== '<') {
            const next = source.indexOf('<', index);
            const end = next < 0 ? source.length : next;
            const textStart = index;
            const text = source.slice(index, end);
            if (text.trim()) {
                const parent = stack[stack.length - 1];
                if (!parent) fail('XML_TEXT', '根元素外存在文本', textStart);
                parent.text += decodeEntities(text, (code, message) => fail(code, message, textStart));
            }
            index = end;
            continue;
        }

        if (source.startsWith('</', index)) {
            const closeStart = index;
            index += 2;
            const name = readName();
            skipWhitespace();
            if (source[index] !== '>') fail('XML_CLOSE', `结束标签 </${name}> 非法`);
            index += 1;
            const current = stack.pop();
            if (!current || current.name !== name) {
                fail('XML_CLOSE_MISMATCH', `结束标签 </${name}> 与当前元素不匹配`, closeStart);
            }
            continue;
        }

        if (source.startsWith('<!', index)) {
            fail('XML_DECLARATION_FORBIDDEN', '字体目录不支持 CDATA 或其他声明');
        }

        const elementStart = index;
        index += 1;
        const name = readName();
        const position = locate(lineStarts, elementStart);
        const attributes = Object.create(null);
        const attributeMeta = Object.create(null);
        let selfClosing = false;

        while (index < source.length) {
            skipWhitespace();
            if (source.startsWith('/>', index)) {
                selfClosing = true;
                index += 2;
                break;
            }
            if (source[index] === '>') {
                index += 1;
                break;
            }

            const attributeStart = index;
            const attributeName = readName();
            if (Object.prototype.hasOwnProperty.call(attributes, attributeName)) {
                fail('XML_DUPLICATE_ATTRIBUTE', `重复属性：${attributeName}`, attributeStart);
            }
            skipWhitespace();
            if (source[index] !== '=') fail('XML_ATTRIBUTE', `属性 ${attributeName} 缺少 =`);
            index += 1;
            skipWhitespace();
            const quote = source[index];
            if (quote !== '"' && quote !== "'") {
                fail('XML_ATTRIBUTE', `属性 ${attributeName} 必须使用引号`);
            }
            index += 1;
            const valueStart = index;
            const valueEnd = source.indexOf(quote, index);
            if (valueEnd < 0) fail('XML_ATTRIBUTE', `属性 ${attributeName} 未闭合`, attributeStart);
            const rawValue = source.slice(valueStart, valueEnd);
            attributes[attributeName] = decodeEntities(
                rawValue,
                (code, message) => fail(code, message, valueStart),
            );
            const attributePosition = locate(lineStarts, attributeStart);
            attributeMeta[attributeName] = {
                line: attributePosition.line,
                column: attributePosition.column,
            };
            index = valueEnd + 1;
        }

        if (index > source.length) fail('XML_ELEMENT', `元素 <${name}> 未闭合`, elementStart);
        const parent = stack[stack.length - 1] || null;
        const node = {
            name,
            attributes,
            attributeMeta,
            children: [],
            text: '',
            parent,
            line: position.line,
            column: position.column,
        };
        if (parent) parent.children.push(node);
        else if (root) fail('XML_MULTIPLE_ROOTS', 'XML 只能包含一个根元素', elementStart);
        else root = node;
        if (!selfClosing) stack.push(node);
    }

    if (stack.length) {
        const current = stack[stack.length - 1];
        fail('XML_UNCLOSED_ELEMENT', `元素 <${current.name}> 未闭合`, source.length);
    }
    if (!root) fail('XML_ROOT', '缺少 XML 根元素', 0);
    return root;
}

module.exports = {
    XmlSyntaxError,
    parseXml,
};
