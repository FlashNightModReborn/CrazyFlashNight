/** @module audio-sink/pull */
'use strict';

const drain = require('pull-stream/sinks/drain');
const asyncMap = require('pull-stream/throughs/async-map');
const pull = require('pull-stream/pull')
const Sink = require('./direct');

module.exports = function PullSink (fn) {
	let sinkFn = Sink(fn);
	let d = drain();

	let sink = pull(asyncMap(sinkFn), d);

	sink.abort = d.abort;

	return sink;
}
