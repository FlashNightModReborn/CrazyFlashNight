'use strict'

var Through = require('./');
var ctx = require('audio-context')();
var Sink = require('stream-sink');
var AudioBuffer = require('audio-buffer');
var util = require('audio-buffer-utils');
var pcm = require('pcm-util');
var Generator = require('audio-generator');
var isBrowser = require('is-browser');
var assert = require('assert');
var Stream = require('stream');
var inherits = require('inherits');
var extend = require('object-assign');
var Readable = require('stream').Readable;
var Writable = require('stream').Writable;
var t = require('tape');
var ASink = require('audio-sink');
var Speaker = require('audio-speaker/stream');
var WAAStream = require('web-audio-stream/stream');


Through.log = true;



t('PassThrough', function (t) {
	Through(function (input) {
		if (this.time > 0.1) {
			this.end();
		}
	})
	.on('end', t.end)
	.pipe(Through())
	.pipe(Through(function () {
		// this.end();
	}))
	.pipe(Through(function (input) {
		return input;
	}))
	.pipe(Sink(function (data) {
		// console.log(data.length)
	}));
});

t('Source', function (t) {
	//weird-saw wave generator
	Through(function (input) {
		var len = 1024;
		var count = this.count

		util.fill(input, function (value, idx, channel) {
			// if (channel === 1) {
			// 	return 1 - idx/len * 2;
			// }
			// return idx/len * 2 - 1;
			return Math.sin(Math.PI * 2 * (440 + (channel > 0 ? 1 : -1)) * (count + idx) / 44100)
		});

		if (this.time > .5) {
			this.end();
		}
		return input
	})
	.on('end', t.end)
	.pipe(Sink(function (data) {
		console.log('fin', data.length)
	}))
	// .pipe(WAAStream(ctx.destination))
	// .pipe(Speaker({context: ctx}))
});

t.skip('Processor', function () {

});

t.skip('Destination', function () {

});

t('Pressure regulation', function (t) {
	if (!isBrowser) return t.end();

	var buf, resume;

	//create sound renderer
	var sourceNode = ctx.createBufferSource();
	sourceNode.loop = true;
	sourceNode.buffer = new AudioBuffer(2, pcm.defaults.samplesPerFrame, {context: ctx});
	sourceNode.start();
	var scriptNode = ctx.createScriptProcessor(pcm.defaults.samplesPerFrame);
	scriptNode.onaudioprocess = function (e) {
		buf = e.outputBuffer;

		//release stream
		resume && resume();

		if (e.playbackTime > 0.15) {
			t.end();
			scriptNode.disconnect();
		}
	};
	sourceNode.connect(scriptNode);
	scriptNode.connect(ctx.destination);


	var buf;

	//create pipe of sound processing streams with regulated speed
	var stream = Through(util.noise)
	.pipe(Through(function (input, cb) {
		//place buffer to the output, if any
		if (buf) util.copy(input, buf);

		resume = cb;
	}));
});


t.skip('pause/resume', function (t) {
	//Use-case for this test is obsolete.
	//Use process function callback for that, redefining these methods is not a good idea

	// this.timeout(false);

	//create pipe of sound processing streams with regulated speed
	var stream = Through(function (input) {
		var self = this;

		input.time = self.time;
		self.log('generate', self.time);

		//NOTE: calling pause here means that chunk will not be sent
		// self.pause();
		// setTimeout(function () {
		// 	self.resume();
		// }, 1000);
	})
	.pipe(Through(function (input) {
		var self = this;
		self.log('receive', input.time)

		self.pause();
		setTimeout(function () {
			self.resume();
		}, 1000);
	}));
});


t('Connected to AudioNode', function (t) {
	if (!isBrowser) return t.end();

	var count = 0;

	//create pipe of sound processing streams with regulated speed
	//you should hear noise burst
	Through(util.noise, {context: ctx})
	.pipe(ASink(function (data, cb) {
		setTimeout(cb, 50);

		count++;
		if (count > 10) this.end();
	}))
	.pipe(WAAStream(ctx.destination))

	setTimeout(t.end, 1000);
});


t('Connected to simple node');
t('Connected from simple node');

t.skip('Errors in processing', function (t) {

});

t.skip('error', function (t) {

});

t('throttle source', function (t) {
	// this.timeout(false);

	var count = 0;

	var stream = Through(function (input, done) {
		// console.log('Generated', this.time);
		input.time = this.time;

		if (this.count > 3000) this.end();

		setTimeout(done, 50);
	})
	.on('end', function () {
		assert.equal(count, 3);
		t.end();
	})
	.pipe(Through(function (input) {
		// console.log('Received', input.time);
		count++;
	}));

});

t('pipe to non-object stream', function (t) {
	// this.timeout(false);

	var count = 0;

	var stream = Through(function (input) {
		// console.log('Generated', input.length);
		input.time = this.time;
	})
	.pipe(Stream.PassThrough({
		// objectMode: true,
		highWaterMark: 0
	}))
	.pipe(Through(function (input, done) {
		// console.log('Received', input.length);
		count++;

		if (this.count > 3000) {
			// console.log(this.count)
			this.end();
		}

		done();
	}))
	.on('end', function () {
		assert.equal(count, 4);
		t.end();
	});
})

t('throttle destination', function (t) {
	// this.timeout(false);

	var count = 0;

	Through(function (input) {
		// console.log('Generated', this.time);
		input.time = this.time;
	})
	.pipe(Through(
		function (input) {}
	))
	.pipe(Through(function (input, done) {
		// console.log('Received', input.time);
		count++;

		if (this.count > 3000) {
			this.end();
		}

		t.end();
		// setTimeout(t.end, 50);
	}))
	.on('end', function () {
		assert.equal(count, 4);
		t.end();
	});
});

t.skip('beforeProcess, afterProcess hooks', function () {

});

t('single stream does not start generating, only when piped');


t.skip('mute', function () {

});

t.skip('solo', function () {

});

t.skip('schedule', function () {

});

t.skip('Multiple inputs', function () {

});

t.skip('Multiple outputs', function () {

});

t.skip('pause/resume', function () {

});

t.skip('end', function () {

});

t.skip('timeDelta, frameCount and other inner vars', function (t) {
	// this.timeout(10e5);

	Through(function(chunk, done) {
		assert(this.timeDelta >= 0);
		assert(this.timeLapse >= 0);
		assert(this.frame >= 0);

		if (this.frame > 4) {
			//:( ☞ t.end(null, null);
		}

		setTimeout(t.end, 10);
	})
	.on('end', function () {
		t.end();
	})
	.pipe(Through());
});

t('sync/async turns', function (t) {
	// this.timeout(10e5);

	Through(function(chunk, done) {
		if (this.time > 0.1) {
			return null
		}

		setTimeout(t.end, 10);
	})
	.on('end', function () {
		t.end();
	})
	.pipe(Through());
});

t('returning null stops stream', function (t) {
	var count = 0;
	Through(function () {
		if ( count >= 2 ) return null;
	})
	.on('end', function () {
		assert.equal(count, 2);
		t.end();
	})
	.on('data', function () {
		count++;
	})
	.pipe(Sink());
});

t.skip('convert pcm format', function (t) {
	//that is the only use-case for the bad API with input/output format.
	//if user need transformations - he should use pcm-transform or alike.
	// this.timeout(Infinity);

	var n = 0;

	Readable({
		read: function (size) {
			var arr = new Float32Array(1024);
			arr.fill(1);
			var aBuf = new AudioBuffer(1, arr);

			var buf = pcm.toBuffer(aBuf, {
				float: true
			});

			if (n++ > 10) return this.push(null);
			this.push(buf);
		}
	})
	.on('end', t.end)
	.pipe(Through({
		channels: 1,
		float: true
	}, {
		channels: 1,
		float: false
	}))
	.pipe(Writable({
		write: function (chunk, enc, cb) {
			assert.equal(chunk.readInt16LE(0), 32767);
			cb();
			// setTimeout(cb, 1000);
		}
	}));
});


t('through-to-through', function (t) {
	Through(function () {
		if (this.time > 0.1) {
			return null;
		}
	})
	.pipe(Through(
		function (chunk) {
		}
	))
	.pipe(Writable({
		write: function (chunk, enc, cb) {
			setTimeout(cb, 0);
		}
	}))
	setTimeout(t.end, 100)
});


t('various frame size', function (t) {
	Through(function () {
		if (this.time > 0.2) {
			return null;
		}
	}, {
		samplesPerFrame: 512
	})
	.on('end', t.end)
	.pipe(Through(
		function (chunk) {
		}
	), {
		samplesPerFrame: 512
	})
	.pipe(Writable({
		write: function (chunk, enc, cb) {
			setTimeout(cb, 0);
		}
	}))
});

t('no autogenerator', function (t) {
	var count = 0;

	Through(function (buffer) {
		if (this.frame >= 2) this.end();
	}, {
		generator: false
	}).on('data', function () {count++}).pipe(Sink());

	setTimeout(function () {
		assert.equal(count, 0);
		t.end();
	}, 100);
});

t('sync error', t => {
	Through(b => {
		return Error(123)
	}).on('error', function (e) {
		assert(e.message == 123);
		this.end();
	}).pipe(Through());

	Through(b => {
		throw Error(123)
	}).on('error', function (e) {
		assert(e.message == 123);
		this.end();
	}).pipe(Through());

	setTimeout(t.end, 10)
});
