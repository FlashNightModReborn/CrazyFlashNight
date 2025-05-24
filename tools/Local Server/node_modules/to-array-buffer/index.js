/**
 * @module  to-array-buffer
 */

'use strict'

var str2ab = require('string-to-arraybuffer')
var flat = require('flatten-vertex-data')
// var isBlob = require('is-blob')


module.exports = function toArrayBuffer (arg) {
	//zero-length or undefined-like
	if (!arg) return new ArrayBuffer()

	//array buffer
	if (arg instanceof ArrayBuffer) return arg

	//try to decode data-uri
	if (typeof arg === 'string') {
		return str2ab(arg)
	}

	// File & Blob
	// if (isBlob(src) || (src instanceof global.File)) {
		// FIXME: we cannot use it here bc FileReader is async
	// }

	//array buffer view: TypedArray, DataView, Buffer etc
	if (ArrayBuffer.isView(arg)) {
		if (arg.byteOffset != null) return arg.buffer.slice(arg.byteOffset, arg.byteOffset + arg.byteLength)
		return arg.buffer
	}

	//buffer/data nested: NDArray, ImageData etc.
	//FIXME: NDArrays with custom data type may be invalid for this procedure
	if (arg.buffer || arg.data || arg._data) {
		var result = toArrayBuffer(arg.buffer || arg.data || arg._data)
		return result
	}

	// detect if flat
	if (arg.length != null) {
		for (var i = 0; i < arg.length; i++) {
			if (arg[i].length != null) {
				arg = flat(arg)
				break
			}
		}
	}

	//array-like or unknown
	//hope Uint8Array knows better how to treat the input
	return (new Uint8Array(arg.length != null ? arg : [arg])).buffer
}
