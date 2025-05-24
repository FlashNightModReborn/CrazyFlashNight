Convert negative index to positive starting from the end. Same way [Array.slice](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/slice) arguments work.

[![npm install negative-index](https://nodei.co/npm/negative-index.png?mini=true)](https://npmjs.org/package/negative-index/)

```js
let idx = require('negative-index');

idx(-5, 8); //3
idx(5, 8); //5
```

Works well for normalizing real numbers offset, like time etc:

```js
let normOffset = require('negative-index');

let time = -.15, duration = 2.45;

normOffset(time, duration); //2.3
```
