Turn a buffer-like to an ArrayBuffer:

* Buffer to ArrayBuffer
* ArrayBuffer view (TydedArray, FloatArray, DataView etc) to ArrayBuffer
* [AudioBuffer](http://github.com/audiojs/audio-buffer) to ArrayBuffer
* ImageData to ArrayBuffer
* [ndarray](https://github.com/scijs/ndarray) to ArrayBuffer
* String to ArrayBuffer
* Array to ArrayBuffer

[![npm install to-array-buffer](https://nodei.co/npm/to-array-buffer.png?mini=true)](https://npmjs.org/package/to-array-buffer/)

```js
var toArrayBuffer = require('to-array-buffer')
var context = require('audio-context')

//Get array buffer from any object.
ab = toArrayBuffer(new Buffer(100))
ab = toArrayBuffer(new Float32Array(12))
ab = toArrayBuffer(context.createBuffer(2, 200, 3000))
ab = toArrayBuffer([1, 2, 3])
ab = toArrayBuffer(imageData)
ab = toArrayBuffer(ndarray)
ab = toArrayBuffer(dataUri)

//Please note that for strings you may want to decode/encode etc.
ab = toArrayBuffer(encode('abc'))

//Pass `clone` as the second argument to ensure result is cloned.
refAb = toArrayBuffer(new ArrayBuffer(12), true)
refAb = toArrayBuffer(new Uint8Array([1, 2, 3]), true)
```

### Related

* [save-file](https://github.com/dfcreative/save-file) — save any input data to file in node/browser.
* [buffer-to-arraybuffer](https://npmjs.org/package/buffer-to-arraybuffer) — convert surely known Buffer datatype to ArrayBuffer.
