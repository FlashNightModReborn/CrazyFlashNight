let assert = require('assert');
let idx = require('./');

assert.equal(idx(null, 10), 0);
assert.equal(idx(undefined, 10), 0);
assert.equal(idx(-15, 10), 0);
assert.equal(idx(-10, 10), 0);
assert.equal(idx(-5, 10), 5);
assert.equal(idx(-0, 10), 10);
assert.equal(idx(0, 10), 0);
assert.equal(idx(5, 10), 5);
assert.equal(idx(10, 10), 10);
assert.equal(idx(15, 10), 10);
