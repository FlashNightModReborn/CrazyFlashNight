'use strict';

var Generator = require('audio-generator/stream');
var Sink = require('./direct');
var PullSink = require('./pull');
var StreamSink = require('./stream');
var Transform = require('stream').Transform;
var test = require('tst');
var assert = require('assert');
var pull = require('pull-stream');


test('Direct', (done) => {
	let count = 0;

	let sink = Sink((data, cb) => {
		setTimeout(() => {
			count++;
			cb(null, count);
		}, 10)
	});
	assert.equal(count, 0);
	sink(1, (err, data) => {
		assert.equal(err, null);
		assert.equal(data, 1);
	});
	assert.equal(count, 0);

	setTimeout(() => {
		assert.equal(count, 1);
		done();
	}, 20);
});


test('Pull-stream', (done) => {
	let count = 0;

	let sink = PullSink((data, cb) => {
		setTimeout(() => {
			count++;
			if (count >= 10) sink.abort();
			cb();
		}, 10);
	});

	pull(
		pull.infinite(),
		pull.take(10),
		sink
	);

	setTimeout(() => {
		assert.equal(count, 10);
		done();
	}, 200);
});


test('Pull-stream readme case', done => {
	const pull = require('pull-stream/pull');
	const sink = require('./pull');
	const generator = require('audio-generator/pull');

	let count = 0;
	let s = sink((data, cb) => {
		if (count++ >= 4) {
			cb(true);
			done();
			// s.abort();
			return;
		}
		setTimeout(cb, 100);
	});

	//stream generated data to sink with pressure control
	pull(
		generator(time => Math.sin(time * Math.PI * 2 * 440)),
		s
	);
});


test('Stream', (done) => {
	let count = 0;

	Generator(function (time) {
		return time ? 0 : 1;
	})
	.pipe(StreamSink(function (data) {
		console.log('Passed through chunk of data ', data.length);

		count++;
		if (count >= 3) this.end();
		// setTimeout(cb, 1000);
	}))
	.on('end', () => {
		assert.equal(count, 3);
	})
	.pipe(Transform({
		objectMode: true,
		transform: function (data, enc, cb) {
			cb(null, data)
		}
	}))
	.pipe(StreamSink(function (data, cb) {
		setTimeout(cb, 200);
		console.log('Got chunk of data ', data.length);
	}));

	setTimeout(() => {
		assert.equal(count, 3);
		done();
	}, 600);
});


//TODO: move to audio-slice test
// var Slice = require('../slice');
// Generator().pipe(Slice(2)).pipe(Sink(v => console.log(v)));
