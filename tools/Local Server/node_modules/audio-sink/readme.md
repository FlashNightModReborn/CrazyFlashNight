# audio-sink [![Build Status](https://travis-ci.org/audiojs/audio-sink.svg?branch=master)](https://travis-ci.org/audiojs/audio-sink) [![stable](http://badges.github.io/stability-badges/dist/stable.svg)](http://github.com/badges/stability-badges)

Triggers an event for received audio chunk and releases the data. If piped to somewhere, it turns into a pass-throught stream. That way, it is [through2-sink](https://www.npmjs.com/package/through2-sink) and [tap-stream](https://www.npmjs.com/package/tap-stream) in one. Use as a fast replacement for [audio-speaker](https://npmjs.org/package/audio-speaker) or [audio-render](https://npmjs.org/package/audio-render).

Can function as a pressure controller. See example.

## Usage

[![npm install audio-sink](https://nodei.co/npm/audio-sink.png?mini=true)](https://npmjs.org/package/audio-sink/)

#### Direct

```js
const Sink = require('audio-sink/direct');

let sink = Sink((data, cb) => {
	console.log(data);
	setTimeout(cb, 100);
});

//log data and invoke cb after 100ms
sink(buffer, (err, buffer) => {

});
```

#### Pull-stream

```js
const pull = require('pull-stream/pull');
const sink = require('audio-sink/pull');
const generator = require('audio-generator/pull');

//stream generated data to sink with pressure control
pull(
	generator(time => Math.sin(time * Math.PI * 2 * 440)),
	sink((data, cb) => {
		//end stream if needed
		if (tooLate) return cb(true);

		console.log(data);
		setTimeout(cb, 100);
	});
);
```

#### Stream

```js
var Gen = require('audio-generator/stream');
var Sink = require('audio-sink/stream');

Gen(function (time) {
	return time ? 0 : 1;
})
.pipe(Sink(function (data, cb) {
	console.log('This sink is a pass-through with 10ms throttling ', data.length);

	setTimeout(cb, 10);
}))
.pipe(Sink(function (data) {
	console.log('This sink gets the data and releases it ', data.length);
}));
```

## Related

> [stream-sink](https://www.npmjs.com/package/stream-sink) — universal stream sink.<br/>
> [through2-sink](https://www.npmjs.com/package/through2-sink) — triggers an event for the data chunk, but does not pass data through.<br/>
> [tap-stream](https://www.npmjs.com/package/tap-stream) — triggers callback for the passed through data, but does not release data.
