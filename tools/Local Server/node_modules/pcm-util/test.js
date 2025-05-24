var pcm = require('./');
var assert = require('assert');
var AudioBiquad = require('audio-biquad');
var AudioBuffer = require('audio-buffer');
var test = require('tape')//.only();


test('Max/min limits', function (t) {
	var a = pcm.normalize({
		float: false,
		signed: true,
		bitDepth: 16
	});
	assert.equal(a.max, 32767);
	assert.equal(a.min, -32768);

	var a = pcm.normalize({
		float: false,
		signed: false,
		bitDepth: 16
	});
	assert.equal(a.max, 65535);
	assert.equal(a.min, 0);

	var a = pcm.normalize({
		float: false,
		signed: false,
		bitDepth: 8
	});
	assert.equal(a.max, 255);
	assert.equal(a.min, 0);

	var a = pcm.normalize({
		float: false,
		signed: true,
		bitDepth: 8
	});
	assert.equal(a.max, 127);
	assert.equal(a.min, -128);

	var a = pcm.normalize({
		float: true
	});
	assert.equal(a.max, 1);
	assert.equal(a.min, -1);

	t.end()
});

// test.skip('Parse/stringify', function () {
// 	var format = pcm.format(pcm.defaults);
// 	var formatId = pcm.stringifyFormat(format);
// 	var result = pcm.parseFormat(formatId);

// 	assert.deepEqual(format, result);
// });

test('Keep prototype values', function (t) {
	var A = function(){};
	A.prototype = Object.create({samplesPerFrame: 1});
	var a = new A();
	pcm.normalize(a);
	assert.equal(a.samplesPerFrame, 1);
	t.end()
});

test('Obtain format from the audio node', function (t) {
	var aStream = AudioBiquad();
	var aStreamFormat = pcm.format(aStream);
	var defaultFormat = pcm.format(pcm.defaults);

	assert.notEqual(aStream, aStreamFormat);
	assert.deepEqual(aStreamFormat, defaultFormat)
	t.end()
});

test('Do not return defaults', function (t) {
	assert.deepEqual(pcm.format(), {});
	t.end()
});

test('Normalize changed and normalized', function (t) {
	var floatFormat = pcm.normalize(pcm.format(pcm.defaults));
	floatFormat.float = true;
	var floatFormat = pcm.normalize(floatFormat);

	assert.deepEqual(pcm.normalize({float: true}), floatFormat);
	t.end()
});

// test.skip('Create typed array for the format', function () {
// 	assert(pcm.createArray() instanceof Int16Array);
// 	assert(pcm.createArray({float: true}) instanceof Float32Array);
// 	assert(pcm.createArray({float: false}) instanceof Int16Array);
// 	assert(pcm.createArray({float: false, bitDepth: 32}) instanceof Int32Array);
// 	// assert(pcm.createArray({float: false, bitDepth: 32, signed: false}) instanceof UInt32Array);
// 	assert(pcm.createArray({float: false, signed: false}) instanceof Uint16Array);
// });

test('Infer format from the typed array', function (t) {
	assert.deepEqual(pcm.format(new Float32Array), pcm.format({
		float: true,
		signed: false,
		bitDepth: 32
	}));
	assert.deepEqual(pcm.format(new Int16Array), pcm.format({
		float: false,
		signed: true,
		bitDepth: 16
	}));
	t.end()
});

test('FloatLE → Int16BE', function (t) {
	var buf = new Buffer(8);
	buf.writeFloatLE(1.0, 0);
	buf.writeFloatLE(-0.5, 4);

	var newBuf = pcm.convert(buf, { float: true }, { float: false, signed: true, bitDepth: 16, byteOrder: 'BE' });
	var val1 = newBuf.readInt16BE(0);
	var val2 = newBuf.readInt16BE(2);

	assert.equal(Math.pow(2, 15) - 1, val1);
	assert.equal(-Math.pow(2, 14), val2);
	t.end()
});

// test.skip('interleave', function () {

// });

// test.skip('deinterleave', function () {

// });

test('Buffer to AudioBuffer', function (t) {
	var b = Buffer(6*4);
	[0, 1, 0, -1, 0, 1].forEach(function (value, idx) {
		b.writeFloatLE(value, idx * 4);
	});

	var aBuf = pcm.toAudioBuffer(b, {
		float: true,
		channels: 3
	});

	assert.deepEqual(aBuf.getChannelData(0), [0, -1]);
	assert.deepEqual(aBuf.getChannelData(1), [1, 0]);
	assert.deepEqual(aBuf.getChannelData(2), [0, 1]);

	var aBuf = pcm.toAudioBuffer(b, {
		float: true,
		channels: 3,
		interleaved: false
	});

	assert.deepEqual(aBuf.getChannelData(0), [0, 1]);
	assert.deepEqual(aBuf.getChannelData(1), [0, -1]);
	assert.deepEqual(aBuf.getChannelData(2), [0, 1]);
	t.end()
});

test('AudioBuffer to Buffer', function (t) {
	var aBuffer = AudioBuffer([0, 1, 0, -1]);

	var buffer = pcm.toBuffer(aBuffer, {
		signed: true,
		float: false,
		interleaved: true
	});

	assert.equal(buffer.length, 8);
	assert.equal(buffer.readInt16LE(0), 0);
	assert.equal(buffer.readInt16LE(2), 0);
	assert.equal(buffer.readInt16LE(4), 32767);
	assert.equal(buffer.readInt16LE(6), -32768);
	t.end()
});

test('toBuffer detect channels', function (t) {
	var aBuffer = AudioBuffer(1, [0, 1, 0, -1]);

	var buffer = pcm.toBuffer(aBuffer, {
		signed: true,
		float: false,
		interleaved: true
	});

	assert.equal(buffer.length, 8);
	assert.equal(buffer.readInt16LE(0), 0);
	assert.equal(buffer.readInt16LE(4), 0);
	assert.equal(buffer.readInt16LE(2), 32767);
	assert.equal(buffer.readInt16LE(6), -32768);
	t.end()
});

test('AubioBuffer converting consistency', function (t) {
	//64 array
	var src = new AudioBuffer(pcm.defaults.samplesPerFrame, {floatArray: Float64Array, isWAA: false})
	var buf = pcm.toBuffer(src)
	assert.equal(buf.byteLength, pcm.defaults.samplesPerFrame * pcm.defaults.bitDepth * src.numberOfChannels / 8)

	var dst = pcm.toAudioBuffer(buf)
	assert.equal(src.length, dst.length)

	//32 array
	var src = new AudioBuffer(pcm.defaults.samplesPerFrame, {floatArray: Float32Array})
	var buf = pcm.toBuffer(src)
	assert.equal(buf.byteLength, pcm.defaults.samplesPerFrame * pcm.defaults.bitDepth * src.numberOfChannels / 8)

	var dst = pcm.toAudioBuffer(buf)
	assert.equal(src.length, dst.length)

	t.end()
})
