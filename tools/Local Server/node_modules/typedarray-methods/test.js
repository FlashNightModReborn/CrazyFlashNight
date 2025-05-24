require('./');

var assert = require('assert');

var a = new Float32Array(10);
a.fill(1);
a.reverse();
a.slice();

assert(a instanceof Float32Array);