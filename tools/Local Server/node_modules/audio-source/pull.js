/**
 * audio-source pull-stream
 *
 * @module  audio-source/pull
 */
'use strict';

const createSource = require('./direct');

module.exports = function (buffer, opts) {
	let read = createSource(buffer, opts);

	let ended = false;

	let stream = (end, cb) => {
		if (end || ended) {
			ended = true;
			return cb && cb(true);
		}

		let result = read();

		if (result === null) {
			return stream.abort(null, cb);
		}

		return cb(null, result);
	}

	stream.abort = (err, cb) => {
		if ('function' == typeof err) {
			cb = err; err = true;
		}
		ended = err || true;
		return stream(true, cb);
	}

	return stream;
}
