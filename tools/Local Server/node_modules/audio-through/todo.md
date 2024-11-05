* check if format params of connected nodes fit each other and throw error.
* use waa-stream for connection to AudioNodes.
* send raw buffer only for target raw connections, do not force each output to receive raw value.
* Handle carefully returned by user buffer. He may want to return a webgl texture to shorten processing, so do not force it to be any type of buffer - just return as is.
* provide fadeout/fadein before end/start, optional
* pause on window focus leave/resume
* recursive connection
* multiple outputs
* multiple inputs sync - just wait for every input reached the time limit.
	* but if somes are not in time for RT - just mix regardless of them. So basically we need set up target time of a chunk.
* align output buffer size, if input buffer varies
* implement `plan(time, what)` method, to avoid external timeouts