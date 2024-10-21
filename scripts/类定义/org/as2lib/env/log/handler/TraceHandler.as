/*
 * Copyright the original author or authors.
 * 
 * Licensed under the MOZILLA PUBLIC LICENSE, Version 1.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.mozilla.org/MPL/MPL-1.1.html
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.util.Stringifier;
import org.as2lib.env.log.LogHandler;
import org.as2lib.env.log.LogMessage;
import org.as2lib.env.log.handler.AbstractLogHandler;

/**
 * {@code TraceHandler} uses {@code trace} to log messages.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.log.handler.TraceHandler extends AbstractLogHandler implements LogHandler {
	
	/** Holds a trace handler instance. */
	private static var traceHandler:TraceHandler;
	
	/**
	 * Returns an instance of this class.
	 *
	 * <p>This method always returns the same instance.
	 *
	 * <p>The {@code messageStringifier} argument is only recognized on first
	 * invocation of this method.
	 * 
	 * @param messageStringifier (optional) the log message stringifier to be used by
	 * the returned handler
	 * @return a trace handler
	 */
	public static function getInstance(messageStringifier:Stringifier):TraceHandler {
		if (!traceHandler) traceHandler = new TraceHandler(messageStringifier);
		return traceHandler;
	}
	
	/**	
	 * Constructs a new {@code TraceHandler} instance.
	 *
	 * <p>You can use one and the same instance for multiple loggers. So think about
	 * using the handler returned by the static {@link #getInstance} method. Using this
	 * instance prevents the instantiation of unnecessary trace handlers and saves
	 * storage.
	 * 
	 * @param messageStringifier (optional) the log message stringifier to use
	 */
	public function TraceHandler(messageStringifier:Stringifier) {
		super (messageStringifier);
	}
	
	/**
	 * Writes the passed-in {@code message} using {@code trace}.
	 *
	 * <p>The string representation of the {@code message} to log is obtained via
	 * the {@code convertMessage} method.
	 * 
	 * @param message the message to log
	 */
	public function write(message:LogMessage):Void {
		trace(convertMessage(message));
	}
	
}