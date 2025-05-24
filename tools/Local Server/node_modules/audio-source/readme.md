[![Build Status](https://travis-ci.org/audiojs/audio-source.svg?branch=master)](https://travis-ci.org/audiojs/audio-source) [![stable](http://badges.github.io/stability-badges/dist/stable.svg)](http://github.com/badges/stability-badges)

Create audio stream from _AudioBuffer_ or _ArrayBuffer_.

## Usage

[![npm install audio-source](https://nodei.co/npm/audio-source.png?mini=true)](https://npmjs.org/package/audio-source/)

#### As a function

Audio-source in functional style is a [sync source](https://github.com/audiojs/contributing/wiki/Streams-convention).

```js
const createSource = require('audio-source');
const createSpeaker = require('audio-speaker/direct');
const lena = require('audio-lena/buffer');

let read = Source(lena, {channels: 1});
let write = Speaker({channels: 1});

//create and start reading loop
(function again (err, buf) {
	//get next chunk
	buf = read(buf);

	//catch end
	if (!buf) return;

	//send chunk to speaker
	write(buf, again);
})();
```

#### As a pull-stream

[Pull-streams](https://github.com/pull-stream/pull-stream) are awesome and [faster than streams](https://github.com/dfcreative/stream-contest) (but slower than plain fn).

```js
const pull = require('pull-stream/pull');
const Source = require('audio-source/pull');
const Speaker = require('audio-speaker/pull');
const lena = require('audio-lena/buffer');

let source = Source(lena, {channels: 1});
let sink = Speaker({channels: 1});

pull(source, sink);
```

#### As a stream

Streams are concise:

```js
const Source = require('audio-source/stream');
const Speaker = require('audio-speaker/stream');
const lena = require('audio-lena/buffer');

Source(lena).pipe(Speaker());
```

### API

```js
const Source = require('audio-source');

//create source reader
let read = Source(audioBuffer, {channels: 2, loop: false}?, endCallback?);

//get next chunk of audio data
let chunk = read();

//dispose stream
read.end();
```

## Related

> [web-audio-stream](https://github.com/audio-lab/web-audio-stream) — connect WebAudio to audio-stream or audio-stream to WebAudio.
