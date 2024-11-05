/**
 * @module  audio-source/stream
 */

'use strict';

var AudioThrough = require('audio-through');
var Reader = require('./direct');

module.exports = function Source (source, opts) {
	//create sync map
	let fill = Reader(source, opts);

	//create through-instance
	let stream = new AudioThrough(fill, opts);

	stream.once('end', () => {
		fill.end();
	});

	return stream;
};
