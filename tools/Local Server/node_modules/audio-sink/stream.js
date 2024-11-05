/**
 * @module  audio-generator
 */
'use strict';


var inherits = require('inherits');
var PassThrough = require('stream').PassThrough;
var createSink = require('./direct');

module.exports = Sink;

inherits(Sink, PassThrough);


function Sink (fn) {
	if (!(this instanceof Sink)) return new Sink(fn);

	this.sink = createSink(fn);

	PassThrough.call(this, {
		highWaterMark: 0,
		objectMode: true
	});
}


Sink.prototype._transform = function (chunk, enc, cb) {
	this.sink(chunk, () => {
		this.emit('data', chunk);
		cb();
	});
}


Sink.prototype._write = function (chunk, enc, cb) {
	if (!this._readableState.pipesCount) {
		this.sink(chunk, () => {
			this.emit('data', chunk);
			cb();
		});
	} else {
		PassThrough.prototype._write.call(this, chunk, enc, cb);
	}
};
