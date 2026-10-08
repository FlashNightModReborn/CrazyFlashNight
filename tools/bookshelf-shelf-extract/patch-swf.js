// Minimal SWF rewrite for offline art extraction: replace the first DoAction
// containing Stop (0x07) on frame 1 with gotoAndStop(frameIndex) so a patched
// copy of a UI SWF renders a chosen labeled frame without timeline scripting.
// The repository SWF is never modified; callers patch in-memory copies.
'use strict';
const zlib = require('zlib');

function walk(body, onTag) {
    const nbits = body[0] >> 3;
    let pos = Math.floor((5 + 4 * nbits + 7) / 8) + 4; // RECT + rate/count
    let frame = 1;
    while (pos + 2 <= body.length) {
        const head = pos;
        const codeLen = body.readUInt16LE(pos); pos += 2;
        const code = codeLen >> 6;
        let length = codeLen & 0x3f;
        if (length === 0x3f) { length = body.readUInt32LE(pos); pos += 4; }
        const payload = pos;
        pos += length;
        if (onTag(code, payload, length, head, frame) === false) return;
        if (code === 1) frame++;
        if (code === 0) return;
    }
}

// Returns a Buffer holding an uncompressed (FWS) copy of the movie whose
// frame-1 stop action is replaced by gotoAndStop(frameIndex) (0-based).
function patchGotoFrame(source, frameIndex) {
    if (!Number.isInteger(frameIndex) || frameIndex < 0 || frameIndex > 0xffff) throw new Error('bad frame index');
    const compressed = source.slice(0, 3).toString('latin1') === 'CWS';
    const version = source[3];
    const body = compressed ? zlib.inflateSync(source.slice(8)) : source.slice(8);
    let patched = null;
    walk(body, (code, at, length, head, frame) => {
        if (code === 12 && frame === 1 && body.slice(at, at + length).includes(0x07)) {
            patched = { head, at, length };
            return false;
        }
    });
    if (!patched) throw new Error('no stop action found on frame 1');
    // ActionGotoFrame (0x81), length 2, frame index UI16, then End (0x00).
    const action = Buffer.from([0x81, 0x02, 0x00, frameIndex & 0xff, frameIndex >> 8, 0x00]);
    const headLength = action.length >= 0x3f ? 6 : 2;
    const head = Buffer.alloc(headLength);
    if (action.length >= 0x3f) {
        head.writeUInt16LE((12 << 6) | 0x3f, 0); head.writeUInt32LE(action.length, 2);
    } else {
        head.writeUInt16LE((12 << 6) | action.length, 0);
    }
    const tagEnd = patched.at + patched.length;
    const next = Buffer.concat([body.slice(0, patched.head), head, action, body.slice(tagEnd)]);
    const out = Buffer.alloc(8);
    out.write('FWS', 'latin1'); out[3] = version; out.writeUInt32LE(8 + next.length, 4);
    return Buffer.concat([out, next]);
}

function frameLabels(source) {
    const compressed = source.slice(0, 3).toString('latin1') === 'CWS';
    const body = compressed ? zlib.inflateSync(source.slice(8)) : source.slice(8);
    const labels = [];
    walk(body, (code, at, length, head, frame) => {
        if (code === 43) labels.push({ frame, label: body.slice(at, at + length).toString('utf8').replace(/\0+$/, '') });
    });
    return labels;
}

module.exports = { patchGotoFrame, frameLabels };
