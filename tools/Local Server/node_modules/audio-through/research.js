var test = require('tst');
var audioCtx = require('audio-context');
var now = require('performance-now');
var AudioBuffer = require('audio-buffer');
var util = require('audio-buffer-utils');


test('scriptProcessorNode vs setInterval', function () {
	var sourceNode = audioCtx.createBufferSource();
	var scriptNode = audioCtx.createScriptProcessor(4096, 1, 1);
	var time = 0;

	//scriptProcessorNode counter
	var sppTimes = 0;
	scriptNode.onaudioprocess = function() {
		time && sppTimes++;
	}
	sourceNode.connect(scriptNode);
	scriptNode.connect(audioCtx.destination);
	sourceNode.start();

	//setIntervalCounter
	var iTimes = 0;
	var interval = setInterval(function () {
		time && iTimes++;
	});


	//Measure!
	time = -now();
	setTimeout(function () {
		time += now();
		console.log('scriptProcessorNode %s ops/s', sppTimes/time);
		console.log('setInterval %s ops/s', iTimes/time);

		clearInterval(interval);
		sourceNode.stop();
	}, 1000);

	//Results
	//Obviously scriptNode is slower, it has no need to fire nonstop, it is RT.
	//The question is whether the scriptNode is better than pooling transformers on AudioBufferSource?
});



test.skip('Transform redefined', function () {
	//research on a weird bug of infinite generation
	//that happened if destination is unconnected and prev note automatically becomes sink
	//solved by sink "virginity" flag - once node is not sink, it is never a sink

	var id = 0;

	function Through (opts) {
		if (!(this instanceof Through)) return new Through(opts);

		this._id = id++;

		var self = this;
		Stream.Transform.call(self, {
			highWaterMark: 0,
			objectMode: true
		});

		//manage input pipes number
		self.on('pipe', function (source) {
			self.inputsCount++;
		}).on('unpipe', function (source) {
			self.inputsCount--;
		});
	}
	Through.prototype.inputsCount = 0;
	Object.defineProperties(Through.prototype, {
		outputsCount: {
			get: function () {
				return this._readableState.pipesCount
			},
			set: function (value) {
				throw Error('outputsCount is read-only');
			}
		}
	});
	extend(Through.prototype, pcm.defaults);


	Through.prototype._transform = function (chunk, enc, cb) {
		console.log(this._id, 'through', chunk.count);
		cb(null, chunk);
	};

	Through.prototype._write = function (chunk, enc, cb) {
		var self = this;
		if (self.outputsCount) {
			return Stream.Transform.prototype._write.call(self, chunk, enc, cb);
		}

		console.log(self._id, 'received', chunk.count)
		// setTimeout(function () {
			self.emit('data', chunk);
			cb();
		// }, 1000);
	};

	Through.prototype._read = function (size) {
		if (this.inputsCount) {
			return Stream.Transform.prototype._read.call(this, size);
		}

		count++
		this.push({count: count});
		console.log(this._id, 'generated', count);
	};

	Through.prototype.isPaused = function () {
		return false;
	};

	inherits(Through, Stream.Transform);


	var count = 0;

	Through()
	.pipe(Through())
	.pipe(Through());
});