## Wishes

* node/WAA-compatible.
* Structure for worker, sync thread, shader, async processor.
* non-blocking stream, i. e. buffer is returned as only the new one is ready, but in not-blocking way.
* high-level API, user should not care about buffers


## Questions

* Why inputFormat/outputFormat, why not just options with format props?
	* If user needs converting - let him convert buffer manually.
* Should we use options object?
	* + useful for throttle
		* - throttle is better done by async callback expected
	* + useful for sink
		* - sink is detected from the type of the arguments in processing fn
	* + useful to define [ouput] format, if connected to some other real nodes
	* + ✔ natural convention `through what and how`
* audio-through cannot be a sink in sense it cannot release data without user’s control.
	* Otherwise, any node in-between(transformer), being disconnected, becomes a sink, non-regulated.
* So, what format of process is better: 1 audioProcessEvent, 2 inputBuffer or 3 node-like style?
	* 1 + it may contain various addiotional info like time of the event, so we should not guess on the environment
	* 1 + it might be conventional with worker
	* 1 - it is still not fully conventional, not with worker nor with node
	* 1 - it is slow as object containing data is worse than just data
	* 2 + it is simply obvious
	* 2 - confusing convention (there are no such one)
	* 3 + it is conventional, just a specific kind of a transform stream
	* 3 - time & count are kept in this., which is a guess of env, not obvious. How to pass them?
	* imagine yourself a user of some audio-stream. Which would you like it to be?
		* 1 + having an event passed with all the info needed is gentle and easy to intro. Just `Process(function (e) { e.channels, e.inputs, e.sampleRate, e.count, e.time, e.outputs, e. }).pipe(Process(function (e) {});`
		* 1 - this blocks async processing tho
			* 1 + is it needed at all?
				* 1 - in general yes, imagine we’re using some external processor
					* 1 + but isn’t it the same as aworker’s way - just provide the access to the output buffer, and render sound by the deadline?
						* 1 - we need also to stop eating input data till current chunk is processing
							* 1 + ow really? How do we stop oscillator?
								* 1 - just stop it, same as buffer source or whatever.
									* 1 + but as for online radio stream for example, there is no sense to block it
										* 1 - no but just stack the data during processing.
		* 3. So ideally I’d like to have something intuitive, not really novel (no promises). Like Process(function (input, format, cb) { cb(null, output)}).
			* 3 + it is transform, through-compatible
			* 3 - it does not handle multiple inputs/outputs
				* 3 + are they needed? probably no.
			* 3 - the convention is kind of questionable (this.push(data)? wut? whyy? callback(null, shit), wuut? why null? why error is more important than the usual case?)
				* 3 + but violating it creates more confusion: function (input, format, cb) { cb(data); }
					* 3 - does it mean we should not care of conventions? or we should care of not falling into conventions? or we should be like something in between them?
		* 2 + function (input) { return output } is the most obvious case.
			* 2 + And deferred handling is simply returned promise - obsious and simple.
			* 2 - where to keep the data like time, format, count, channels etc?
				* 2 + format should go with the buffer.
				* 2 + time/count is easily implemented by user, if he wants to, but it also works automatically
			* 2 ? what format of the input data should it be? ArrayBuffer or AudioBuffer?
				* + That is another question. But - audioBuffer ships format info.
			* 2 - it hides the output buffer, if it exists, forcing the data always to be whether new or the input. Both cases, that forces churning the memory.
				2 + actually in case of modifying the input buffer, it does not touch the memory.
					* 2 - But it makes it automatically incompatible with any idea of WAA.
						* 2 + And this is good, because processing is really different. scriptProcessorNode/worker-way is tightly bound to RT, but streams are not.
			* ✔ Ok, that seems the less controversial, ok?

* ✔ No promises. Handling is bound to realtime, if promise will block handling or streaming - it is prone to errors. If you need async handling -
	* Though we want to render later sometimes - like, slow shaders and stuff. Just let speaker wait.
* ✔ Seems that we need to have output buffer: if we change the input buffer, in other [piped out] nodes it will be also changed, as we send it by reference. So our output buffer should be different.
* Whether the scriptNode is better than pooling transformers on AudioBufferSource?
	* In the main thread there is only mixing should happen, mixing of N audio buffers. Each audioBuffer should be processed in a separate stream - AudioWorker, AudioShader, OfflineContext, main thread etc. Each that buffer should be formed by slices in a separate memory thread, and that is what AudioNode for. It takes input, processes it (in case of threads it is async), returns it changed, i. e. puts the result in provided (actual) buffer, if not too late. It does not block the stream therefore (piping).
	* So the node pipes just clone the last audioBuffer, when required (sync by speaker I suppose, etc).
	* The WAA does the same without copying, just sends the chunk.
	* [AudioWorker](http://www.w3.org/TR/webaudio/#AudioWorker) seems to have the same audioProcess event, but with multiple input/output buffers (per input/output nodes), so just use that pattern of two objects, passed by reference.
		* So seems that these 2 buffers are just rotating in term, and whether you meet deadlines or not is not it’s care.
			* Though the objects are transferable for audioWorker - what does that mean? What if worker is too late?
	* ✔ We can stick to the convention of audioprocessevent with inputs/outputs and if someone wants implementing specific handlers - welcome to do it in nested objects.
* Should we be able to create WAA-compatible AudioNodes _here_?
	* ✔ No, return scriptProcessorNode in general case
* How should we pass default format for piping?
	* .pipe(where, how)?
	* ✔ No, just pass format to options
* Merge multiple piped audio nodes to just a set of processing calls, without a backpressure mechanism. Provide convenience for streams, but nothing more. Share audiobuffer instance to process multiple audio-nodes once.
	* How to provide various outputs, if piped to multiples?
		* At least we can avoid single-pipe, ok?
* ✔ Deny extra-calculations (fft etc) if not required. Calc on demand only.
* Should it polyfill AudioNode in web-api, as AudioBuffer does?
	* + That seems to be a good practice (audio-buffer), it does not force environment.
	* - There are lots of shit in WebAudio I don’t like. E. g. audio-context, or audio events. That will force exact implementation, which is for node might be not suitable, or even more severely - not intuitive or difficult. Sooner or later we will have to create a custom easy way to style sound. So the question in other terms is - should AudioNode be useful by itself or rather low-level implementation for other high-level nodes?
		* + AudioProcessor and AudioGenerator seem to be easily build on top of polyfill. But they should be integrated into streams env...
	* - That blocks audio node being a simple stream, e. g. to be able to stream it to other guys
		* + Though we can use `node.stream.pipe()` as a low-level mechanism of `node.connect(node)`.
	* - That prevents the ability to build mixers - multiple inputs, multiple outputs.
	* + Same code works in browser at once
		* - Streams work in browser as well
			* + But web-api is a separate thread
				* - But we can make audio-nodes also to be a separate thread, or even a WebGL thread (research on that)
	* - Streams provide customizability, infinite range of possibilities. Polyfill would require exact following to webaudio, because we cannot simply connect to unconnectable nodes.
		* + For each custom node just can create scriptProcessorNode or other node, like it is done with audio-speaker. And if possible - WAAPI node, as it is cool. So you can natively use module in node/browser.
	* + Code is automatically documented and specified
		* - Which strains any future changes, e. g. extending AudioNodes is utterly impossible, we would have to rely on `audio-node-utils`
	* + Having that name in npm and delivering something other is weird
	* - Building infrastructure for audio-css requires custom features, like specific filters
		* + Which is better done in native API, eg speaker, oscillator etc.
			* - Which might be inextendible to outside processors
				* + scriptProcessorNode to the rescue
	* - WAAudioNodes are impossible to feedback
		* + Node streams are also not that easy, if possible at all
	* + WAA is the only solution for browser, no other ways to implement sound, so anyways you have to use it, whether implicit or not. The question is whether following the spec is good.
	* - Natural WAA elements are not customizable, eg we cannot do throttle, change buffer size, schedule events, mute/solo/volume/fft/etc. And there is no solution to that.
		* + We can only create prototypical/static stubs which work in node only and in browser if possible.
	* + It’s super-awesome - connecting WAA to our nodes naturally! That makes any existing WAA project able to work both in node/browser. Like audio-spectrogram - now it is shitty for WAA.
		* + Custom nodes just return custom scriptProcessorNodes? And if not accessible - AudioWorkerNodes?
	* - WAA is shitty in sense it does not allow connect(a).connect(b).connect(c)...
	* ✔ leave `.connect` for AudioBuffers, `.pipe` for Buffers, in WAA construct extended scriptProcessorNode, in node return full-featured class.
	* + I like that WAA API is simpler for AudioNodes than streams - we should care about streams only in processing fn, nowhere else.
* Maybe call this module audio-processor and leave audio-node WAA-compatible?
	* + noone audio-processor
	* + it was initial idea for him
	* - I will loose simplicity of processor function
		* + Noone, even me needs that
	* - More logical to base processor on audio-node than vice-versa
		* + And that is good, as it provides base class for scriptProcessorNode
			* - But then should it have pipe/connect interfaces or not?
	* - ✔ No, leave single package, but provide pure shim and then - extended class.
* Should we implement both stream and AudioNode interfaces in AudioNode?
	* + We can easily utilize both environments, e. g. connect WAA nodes, but pipe to streams.
	* + We are not bound to avoiding cool stuff, like scheduling etc.
	* - We do not return pure WAA nodes, we return wrappers. Which is bad because we can’t connect WAA nodes to them.
		* + ✔ We should return extended scriptProcessorNodes, which makes it compatible with WAA and node at the same time?
* WebGL: should we use this or not
	* + That seems to work amazingly in some shadertoys
	* - That is difficult in node
	* + Streaming audio to/from webshader would be just awwwww
	* - ✔ delegate to descendant, like `audio-shader`


## Doubts

* Regulate speed of processing (slow down it to see in steps whats happening)
* Itd be nice to provide replaceable _transform(chunk,enc,cb), where chunk is AudioBuffer indeed. But it is impossible, as this method is taken. so anyways you have to tackle buffers in that method through pcm-util.
	* But what if call it _process(buffer, cb), where buffer is an AudioBuffer with ready utils?
* reading web-audio-api is not necessary to be in every node. It is better to create reader-streams, converting web-audio-api to stream, and delegate rest to streams.
	* But single-thread streams seems to render serious latency, which is a way better solved in web-audio.
* It introduces some obscure behaviour in constructor, whereas with pure streams it is clear.
	* Like hiding extending of options? But look at audio-spectrum - it is done perfectly, and it is even easier not to care about that.
* Debugging/profiling routines? But they are transforms’, so monkeypatch them
	* Seems that there are not too many of ready packages for audio, and those who are not may just provide simple fallback interfaces for audio-stream.
* Counting data? not difficult to make manually.
	* But it is useful to have some minimal stats methods.
* Sending all the data to webworkers? Webworker mode.
* Implementing scheduling of events based on time, like on(1.23s, cb), which will change the behaviour.
	* Scheduling is a bad idea, actually, because inner time can be scaled, and
* Limiting overall buffersize (in all instances), or the pcm-format.
* Logging overall instances flow.
* Redistributing processor priorities over the instances.
* Providing ongo utils like convolve(filter), gain(volume),
* Providing ongo metrics like loudness, frequencyData, etc (audio-meter).
* Providing detached-stream interface, i. e. make able recursive connection etc.
* Works as universal read/write/transform stream
	* If there is no output but piped input data - it sinks
	* If there is no input but piped to output - it generates
	* If there is both input/output - it processes
* Provides mute/solo methods.
* Number of input/output channels?
	* Seems that mixer channels concept does not really differ from spatial channels, so we actually need synchroniser node, not the mixer, as the mixer is basically can be this our node.
* Prerender export buffer (lock), if there are no planned controller actions.


SO SEEMS THAT THIS PACKAGE HAS NOT ENOUGH REASONS TO EXIST.
	Now it is questionable.

So this is universal building audio unit with interface from anything to anyhing.
It is very generalized and unified way of descpirting and directing audio flow, not really touching the flow, delegating it to powerful outside sources.
Also it transforms the way we deal with audio to the way similar to color - domains (same as color-spaces), metrics (color-metrics), manipulations (color-manipulations).

