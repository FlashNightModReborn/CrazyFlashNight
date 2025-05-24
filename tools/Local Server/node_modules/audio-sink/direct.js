/**
 * @module  audio-sink
 */
'use strict';


module.exports = function Sink (fn) {
	//if fn logger/pressure control
	if (fn instanceof Function) {
		//async fn
		if (fn.length > 1) {
			return function (buffer, cb) {
				return fn.call(this, buffer, cb);
			}
		}
		//sync fn
		else {
			return function (buffer, cb) {
				let result = fn.call(this, buffer);
				if (cb) return cb(null, result);
				return result;
			}
		}
	}

	return function (buffer, cb) {
		//simple drain
		if (cb) {
			return cb(null, buffer);
		}

		return buffer;
	}
}
