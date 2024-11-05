/**
 * @module audio-source/direct
 */
'use strict';

const AudioBuffer = require('audio-buffer');
const isAudioBuffer = require('is-audio-buffer');


module.exports = function createSourceReader (source, options, cb) {
	if (options instanceof Function) {
		cb = options;
	}

	options = options || {};
	let frameSize = options.samplesPerFrame || 1024;
	let channels;
	let sampleRate;

	let count = 0;
	let ended = false;
	let loop = options.loop || false;

	let sourceBuffer;

	//detect source and params
	if (isAudioBuffer(source)) {
		sourceBuffer = source;
		sampleRate = sourceBuffer.sampleRate;
		channels = sourceBuffer.numberOfChannels;
	}

	else {
		channels = options.channels || 2;
		sampleRate = options.sampleRate || 44100;
		sourceBuffer = new AudioBuffer(channels, source, sampleRate);
	}

	read.end = () => {
		cb && cb();
		ended = true; return null;
	};

	return read;

	function read (outputBuffer) {
		if (ended) return null;
		// console.log(outputBuffer.numberOfChannels)

		if (!outputBuffer || outputBuffer.numberOfChannels !== channels) {
			outputBuffer = new AudioBuffer(channels, frameSize, sampleRate);
		}

		//bring data slice from source buffer to target buffer
		for (let i = 0; i < channels; i++) {
			outputBuffer.getChannelData(i).set(
				sourceBuffer.getChannelData(i).subarray(count, count + frameSize)
			);
		}

		count += frameSize;

		if (count > sourceBuffer.length) {
			if (loop) {
				let overflow = sourceBuffer.length % frameSize;

				//fill remainder of buffer with new content
				for (let i = 0; i < channels; i++) {
					outputBuffer.getChannelData(i).set(
						sourceBuffer.getChannelData(i).subarray(0, frameSize - overflow), overflow
					);
				}

				count = frameSize - overflow;
			}
			else {
				read.end();
			}
		}

		return outputBuffer;
	}
}
