# negative-zero [![Build Status](https://travis-ci.org/sindresorhus/negative-zero.svg?branch=master)](https://travis-ci.org/sindresorhus/negative-zero)

> Check if a number is [negative zero](http://en.wikipedia.org/wiki/Signed_zero)


## Install

```
$ npm install --save negative-zero
```


## Usage

```js
const negativeZero = require('negative-zero');

negativeZero(-0);
//=> true

negativeZero(0);
//=> false

negativeZero(+0);
//=> false
```


## Related

- [positive-zero](https://github.com/sindresorhus/positive-zero) - Check if a number is positive zero


## License

MIT © [Sindre Sorhus](https://sindresorhus.com)
