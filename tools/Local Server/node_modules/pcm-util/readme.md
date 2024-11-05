# pcm-util [![Build Status](https://travis-ci.org/audiojs/pcm-util.svg?branch=master)](https://travis-ci.org/audiojs/pcm-util) [![stable](http://badges.github.io/stability-badges/dist/stable.svg)](http://github.com/badges/stability-badges)

Utils to tamper with PCM formats/buffers. In particular, converting _Buffer_ to _AudioBuffer_ or _AudioBuffer_ to _Buffer_.


[![npm install pcm-util](https://nodei.co/npm/pcm-util.png?mini=true)](https://npmjs.org/package/pcm-util/)


```js
var pcm = require('pcm-util')
```

### `pcm.defaults`

Default PCM format to use for any operations

```js
pcm.defaults === {
	channels: 2,
	sampleRate: 44100,
	interleaved: true,
	float: false,
	signed: true,
	bitDepth: 16,
	byteOrder: 'LE',
	max: 32767,
	min: -32768,
	samplesPerFrame: 1024,
	id: 'S_16_LE_2_44100_I'
}
```


### `pcm.normalize(format)`

Normalize passed format: ensure all the properties are present and do not contradict.


### `pcm.format(audioBuffer)`

Retrieve format-related properties from any object, return not normalized format.


### `pcm.equal(a, b)`

Compare whether two formats are equal to each other.


### `pcm.toAudioBuffer(buffer, format)`

Convert buffer of the `format` to audio buffer.


### `pcm.toBuffer(audioBuffer, format)`

Convert audio buffer to buffer of the `format`.


### `pcm.convert(buffer, fromFormat, toFormat)`

Convert buffer from one format to another.


### Related

> [audio-buffer](https://npmjs.org/package/audio-buffer) — high-level audio data container.<br/>
> [audio-buffer-utils](https://npmjs.org/package/audio-buffer-utils) — utils for audio buffers.<br/>
> [audio-pcm-format](https://npmjs.org/package/audio-pcm-format) — pcm format converter stream.<br/>
> [audio-node](https://npmjs.org/package/audio-node) — stream-based AudioNode implementation for node/browser.
