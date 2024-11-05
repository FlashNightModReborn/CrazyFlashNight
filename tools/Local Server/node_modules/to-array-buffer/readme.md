# to-array-buffer [![unstable](https://img.shields.io/badge/stability-unstable-orange.svg)](http://github.com/badges/stability-badges) [![Build Status](https://img.shields.io/travis/dy/to-array-buffer.svg)](https://travis-ci.org/dy/to-array-buffer)

Turn any binary data container into an _ArrayBuffer_ in sync way. Detected containers:

* Buffer
* TypedArray
* ArrayBufferView
* ArrayBuffer
* data-uri string
* base64 string
* plain string
* Array
* Array of Arrays
* etc.

It is not intended to cover any custom data types, like `ImageData`, `AudioBuffer` etc, but that is a good for fallback any-data detection.

[![npm install to-array-buffer](https://nodei.co/npm/to-array-buffer.png?mini=true)](https://npmjs.org/package/to-array-buffer/)

```js
var toArrayBuffer = require('to-array-buffer')
var context = require('audio-context')

//Get array buffer from any object.
ab = toArrayBuffer(new Buffer(100))
ab = toArrayBuffer(new Float32Array(12))
ab = toArrayBuffer(dataURIstr)
ab = toArrayBuffer(base64str)
ab = toArrayBuffer(ndarray)
```

### Related

* [to-arraybuffer](https://www.npmjs.com/package/to-arraybuffer) − convert Buffer to ArrayBuffer, fast implementation.
* [data-uri-to-buffer](https://npmjs.org/package/data-uri-to-buffer) − advanced data-uri decoder.
* [save-file](https://github.com/dy/save-file) — save any input data to file in node/browser.
* [buffer-to-arraybuffer](https://npmjs.org/package/buffer-to-arraybuffer) — convert surely known Buffer datatype to ArrayBuffer.

© Dmitry Yv 2018. MIT Licensed.
