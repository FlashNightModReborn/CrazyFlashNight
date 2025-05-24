# data-uri-regex [![Build Status](https://travis-ci.org/ragingwind/data-uri-regex.svg?branch=master)](https://travis-ci.org/ragingwind/data-uri-regex)

> Regexp for data-uri


## Install

```
$ npm install --save data-uri-regex
```


## Usage

```js
const dataUriRegex = require('data-uri-regex');

var png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg=='

png.match(dataUriRegex());
//=> true

dataUriRegex().test(png);
//=> true

dataUriRegex().exec(png)[1];
//=> 'data:'

dataUriRegex().exec(png)[2];
//=> 'image/png'

dataUriRegex().exec(png)[3];
//=> 'base64'

dataUriRegex().exec(png)[4];
//=> 'iVB'
```


## API

### dataUriRegex()

It will return the instance of RegExp() for match data-uri strings.

## License

MIT © [ragingwind](http://ragingwind.me)
