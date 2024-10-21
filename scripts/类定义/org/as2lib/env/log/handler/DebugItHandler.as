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

import com.interactiveAlchemy.utils.Debug;

/**
 * {@code DebugItHandler} uses {@code com.interactiveAlchemy.utils.Debug.write} of the
 * DebugIt Component from Robert Hoekman to log messages.
 * 
 * @author Simon Wacker
 * @see org.as2lib.env.log.logger.DebugItLogger
 * @see <a href="http://www.rhjr.net/blog/2005/03/debugit-10.html">DebugIt Component</a>
 */
class org.as2lib.env.log.handler.DebugItHandler extends AbstractLogHandler implements LogHandler {
	
	/** Holds a debugIt handler instance. */
	private static var debugItHandler:DebugItHandler;
	
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
	 * @return a debugIt handler
	 */
	public static function getInstance(messageStringifier:Stringifier):DebugItHandler {
		if (!debugItHandler) debugItHandler = new DebugItHandler(messageStringifier);
		return debugItHandler;
	}
	
	/**	
	 * Constructs a new {@code DebugItHandler} instance.
	 *
	 * <p>You can use one and the same instance for multiple loggers. So think about
	 * using the handler returned by the static {@link #getInstance} method. Using this
	 * instance prevents the instantiation of unnecessary debugIt handlers and saves
	 * storage.
	 * 
	 * @param messageStringifier (optional) the log message stringifier to use
	 */
	public function DebugItHandler(messageStringifier:Stringifier) {
		super (messageStringifier);
	}
	
	/**
	 * Writes the passed-in {@code message} using the {@code Debug.write} method.
	 *
	 * <p>The string representation of the {@code message} to log is obtained via
	 * the {@code convertMessage} method.
	 * 
	 * @param message the message to log
	 */
	public function write(message:LogMessage):Void {
		Debug.write(convertMessage(message));
	}
	
}