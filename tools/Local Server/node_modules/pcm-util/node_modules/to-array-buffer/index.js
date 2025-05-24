/**
 * @module  to-array-buffer
 */

var isAudioBuffer = require('is-audio-buffer');
var isUri = require('is-data-uri')
var atob = require('atob-lite')

module.exports = function toArrayBuffer (arg, clone) {
	//zero-length or undefined-like
	if (!arg) return new ArrayBuffer();

	//array buffer
	if (arg instanceof ArrayBuffer) return clone ? arg.slice() : arg;

	//array buffer view: TypedArray, DataView, Buffer etc
	//FIXME: as only Buffer obtains the way to provide subArrayBuffer - use that
	if (ArrayBuffer.isView(arg)) {
		if (arg.byteOffset != null) return arg.buffer.slice(arg.byteOffset, arg.byteOffset + arg.byteLength);
		return clone ? arg.buffer.slice() : arg.buffer;
	}

	//audio-buffer - note that we simply merge data by channels
	//no encoding or cleverness involved
	if (isAudioBuffer(arg)) {
		var floatArray = arg.getChannelData(0).constructor;
		var data = new floatArray(arg.length * arg.numberOfChannels);

		for (var channel = 0; channel < arg.numberOfChannels; channel++) {
			data.set(arg.getChannelData(channel), channel * arg.length);
		}

		return data.buffer;
	}

	//buffer/data nested: NDArray, ImageData etc.
	//FIXME: NDArrays with custom data type may be invalid for this procedure
	if (arg.buffer || arg.data) {
		var result = toArrayBuffer(arg.buffer || arg.data);
		return clone ? result.slice() : result;
	}

	//try to decode data-uri, if any
	if (typeof arg === 'string') {
		//valid data uri
		if (isUri(arg)) {
			var binary = atob(arg.split(',')[1]), array = [];
			for(var i = 0; i < binary.length; i++) array.push(binary.charCodeAt(i));
			return new Uint8Array(array)
		}
		//plain string
		else {
			var buf = new ArrayBuffer(arg.length*2); // 2 bytes for each char
			var bufView = new Uint16Array(buf);
			for (var i=0, strLen=arg.length; i<strLen; i++) {
				bufView[i] = arg.charCodeAt(i);
			}
			return buf
		}
	}

	//array-like or unknown
	//hope Uint8Array knows better how to treat the input
	return (new Uint8Array(arg.length != null ? arg : [arg])).buffer;
}
