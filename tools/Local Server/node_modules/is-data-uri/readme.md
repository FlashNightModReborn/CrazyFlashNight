# is-data-uri [![Build Status](https://travis-ci.org/ragingwind/is-data-uri.svg?branch=master)](https://travis-ci.org/ragingwind/is-data-uri)

> check data whether data-uri or not?


## Install

```
$ npm install --save is-data-uri
```


## Usage

```js
const isDataUri = require('is-data-uri');

isDataUri('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA==');
//=> true
```


## API

### isDataUri(data)

#### data

Type: `string`

String of data-uri which you want to test

## License

MIT © [ragingwind](http://ragingwind.me)
