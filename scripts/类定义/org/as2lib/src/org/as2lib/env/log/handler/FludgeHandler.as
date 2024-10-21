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
import org.as2lib.env.log.level.AbstractLogLevel;
import org.as2lib.env.log.handler.AbstractLogHandler;

/**
 * {@code FludgeHandler} logs messages with {@code Fludge.trace} method.
 * 
 * @author Simon Wacker
 * @see org.as2lib.env.log.logger.FludgeLogger
 * @see <a href="http://www.osflash.org/doku.php?id=fludge">Fludge</a>
 */
class org.as2lib.env.log.handler.FludgeHandler extends AbstractLogHandler implements LogHandler {
	
	/** Holds a fludge handler. */
	private static var fludgeHandler:FludgeHandler;
	
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
	 * @return a fludge handler
	 */
	public static function getInstance(messageStringifier:Stringifier):FludgeHandler {
		if (!fludgeHandler) fludgeHandler = new FludgeHandler(messageStringifier);
		return fludgeHandler;
	}
	
	/**	
	 * Constructs a new {@code FludgeHandler} instance.
	 *
	 * <p>You can use one and the same instance for multiple loggers. So think about
	 * using the handler returned by the static {@link #getInstance} method. Using this
	 * instance prevents the instantiation of unnecessary fludge handlers and
	 * saves storage.
	 * 
	 * @param messageStringifier (optional) the log message stringifier to use
	 */
	public function FludgeHandler(messageStringifier:Stringifier) {
		super (messageStringifier);
	}
	
	/**
	 * Writes log messages using {@code Fludge.trace}.
	 *
	 * <p>The string representation of the {@code message} to log is obtained via
	 * the {@code convertMessage} method.
	 *
	 * @param message the message to log
	 */
	public function write(message:LogMessage):Void {
		var m:String = convertMessage(message);
		switch (message.getLevel()) {
			case AbstractLogLevel.DEBUG:
				Fludge.trace(m, "debug");
				break;
			case AbstractLogLevel.INFO:
				Fludge.trace(m, "info");
				break;
			case AbstractLogLevel.WARNING:
				Fludge.trace(m, "warn");
				break;
			case AbstractLogLevel.ERROR:
				Fludge.trace(m, "error");
				break;
			case AbstractLogLevel.FATAL:
				Fludge.trace(m, "exception");
				break;
			default:
				Fludge.trace(m, "info");
				break;
		}
	}
	
}