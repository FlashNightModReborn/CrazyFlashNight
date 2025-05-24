# audio-through [![Build Status](https://travis-ci.org/audiojs/audio-through.svg?branch=master)](https://travis-ci.org/audiojs/audio-through) [![stable](https://img.shields.io/badge/stability-stable-brightgreen.svg)](http://github.com/badges/stability-badges) [![Greenkeeper badge](https://badges.greenkeeper.io/audiojs/audio-through.svg)](https://greenkeeper.io/)

Through stream for audio processing.

* Compatible with PCM streams (node streams).
* Can be piped right to [speaker](https://npmjs.org/package/speaker).
* Shares _AudioBuffer_ between connected instances instead of copying _Buffer_, which is 0 performance hit / memory churn.
* Uses zero-watermarks to avoid output delays.
* Provides an easy way to control the flow pressure, e. g. to bind processing to real time, debug chunks, outsource processing to shaders/webworkers/audio-workers, etc.
* Provides debugging facilities.
* Provides simple audio data metrics.
* Can be used as a _Readable_, _Transform_ or _Writable_ stream.
* WIP: .plan method to schedule events by audio-time.


## Usage

[![npm install audio-through](https://nodei.co/npm/audio-through.png?mini=true)](https://npmjs.org/package/audio-through/)

```js
var Through = require('audio-through');
var util = require('audio-buffer-utils');
var Speaker = require('speaker');

var through = new Through(function (buffer) {
    if (this.time > 3) return this.end();

    //decrease volume
    var volume = 0.2;

    util.fill(buffer, function (sample) {
        return sample * volume;
    });
});

//Pipe to/from stream
through.pipe(Speaker());
```

## API

### `new Through(process, options?)`

Through constructor takes `process` function and `options` arguments.

Processor function receives `buffer` and optional `done` callback, and is expected to modify buffer or return a new one.

```js
var through = new Through(function (buffer, done) {
    //...process buffer

    done(null, buffer);
});
```

Argument `buffer` is an instance of _AudioBuffer_, used as input-output. It is expected to be modified in-place to avoid "memory churn". Still, if a new buffer is returned then it will be used instead of the `buffer`.

Callback argument can be omitted, in that case processor does not hold stream and releases data instantly, like a sink. (The pattern reminisce mocha tests.). If callback argument is present, stream will wait till callback’s invocation.
Callback receives two arguments — `done(error, data)`, default node callbacks convention.

### `options`

```js
{
    //act as a generator readable stream if connected outwards but not connected inwards
    generator: true,

    //act as a sink writable stream if not connected outwards but connected inwards
    sink: true,

    //pcm options, in case if connected to raw output stream
    sampleRate: 44100,
    channels: 2,
    samplesPerFrame: 1024
}
```

### `through.count`

Number of processed samples.

### `through.frame`

Number of processed frames (chunks).

### `through.time`

Time of the beginning of the next chunk, in seconds.

### `through.on(evt, function (buffer) {})`

Bind hook to processing event: `beforeProcess` or `afterProcess`. You can perform additional buffer modifications, if required.

### `through.end()`

End stream, can be called from within processing function or outside.

### `through.error(error|string)`

Throw error, not breaking the pipe.

### `through.log(string);`

Logging per-instance with timestamps.

### Connecting to Web Audio

If you need to output stream to web audio — use whether [web-audio-stream](https://github.com/audiojs/web-audio-stream) or [audio-speaker](https://github.com/audiojs/audio-speaker).

## Related

> [audio-generator](https://github.com/audiojs/audio-generator) — audio signal generator stream.<br/>
> [audio-speaker](https://github.com/audiojs/audio-speaker) — output audio stream in browser/node.<br/>
> [audio-shader](https://github.com/audiojs/audio-shader) — shader-based audio processing stream.<br/>
> [audio-buffer](https://github.com/audiojs/audio-buffer) — audio data holder.<br/>
> [audio-buffer-utils](https://npmjs.org/package/audio-buffer-utils) — set of utils for audio buffers processing.<br/>
> [pcm-util](https://npmjs.org/package/pcm-util) — utils for low-level pcm stream tasks.<br/>
> [web-audio-stream](https://github.com/audiojs/web-audio-stream) — output stream to web audio.</br>
