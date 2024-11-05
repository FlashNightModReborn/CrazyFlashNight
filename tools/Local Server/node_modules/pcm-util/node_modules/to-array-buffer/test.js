var assert = require('assert');
var NDArray = require('ndarray');
var isBrowser = require('is-browser');
var AudioBuffer = require('audio-buffer');
var toAB = require('./');


assert(toAB() instanceof ArrayBuffer);
assert.equal(toAB().byteLength, 0);

assert.equal(toAB(new ArrayBuffer(2)).byteLength, 2);

assert.equal(toAB(new Float32Array(2)).byteLength, 8);

assert.equal(toAB(new Buffer(4)).byteLength, 4);

assert.equal(toAB([1,2,3]).byteLength, 3);

assert.equal(toAB(new AudioBuffer(new Float64Array([1,2,3,4]), {isWAA: false})).byteLength, 32);
assert.equal(toAB(new AudioBuffer(new Float32Array([.1,.2,.3,.4]), {isWAA: false})).byteLength, 16 )

assert.equal(toAB(new NDArray([1, 2, 3, 4])).byteLength, 4);


//clone
var ab = new ArrayBuffer(2);
assert.equal(toAB(ab), ab);
assert.notEqual(toAB(ab, true), ab);
