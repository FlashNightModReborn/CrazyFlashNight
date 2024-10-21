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

import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.log.LogHandler;
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.LogMessage;
import org.as2lib.env.log.level.AbstractLogLevel;

/**
 * {@code LevelFilterHandler} filters log messages depending on their level.
 * 
 * @author Simon Wacker */
class org.as2lib.env.log.handler.LevelFilterHandler implements LogHandler {
	
	/** All log messages get logged. */
	public static var ALL:LogLevel = AbstractLogLevel.ALL;
	
	/** All log messages that are at a lower log level than debug get logged. */
	public static var DEBUG:LogLevel = AbstractLogLevel.DEBUG;
	
	/** All log messages that are at a lower log level than info get logged. */
	public static var INFO:LogLevel = AbstractLogLevel.INFO;
	
	/** All log messages that are at a lower log level than warning get logged. */
	public static var WARNING:LogLevel = AbstractLogLevel.WARNING;
	
	/** All log messages that are at a lower log level than error get logged. */
	public static var ERROR:LogLevel = AbstractLogLevel.ERROR;
	
	/** All log messages that are at a lower log level than fatal get logged. */
	public static var FATAL:LogLevel = AbstractLogLevel.FATAL;
	
	/** No log messages get logged. */
	public static var NONE:LogLevel = AbstractLogLevel.NONE;
	
	/** The wrapped handler to forward not-filtered log messages to. */
	private var handler:LogHandler;
	
	/** The lowest level that is not filtered. */
	private var level:LogLevel;
	
	/** The lowest level as number that is not filtered. */
	private var levelAsNumber:Number;
	
	/**
	 * Constructs a new {@code LevelFilterHandler} instance.
	 * 
	 * <p>All log messages with a lower level than the passed-in {@code level} get
	 * filtered out.
	 * 
	 * <p>If {@code level} is not passed-in or is {@code null} or {@code undefined} all
	 * levels will be allowed, this means it will be set to
	 * {@link AbstractLogLevel#ALL}.
	 * 
	 * @param handler the handler to forward not-filtered log messages to
	 * @param (optional) level the log level determining which log messages to filter
	 * @throws IllegalArgumentException if the passed-in {@code handler} is
	 * {@code null} or {@code undefined}	 */
	public function LevelFilterHandler(handler:LogHandler, level:LogLevel) {
		if (!handler) throw new IllegalArgumentException("Argument 'handler' [" + handler + "] must not be 'null' nor 'undefined'.", this, arguments);
		this.handler = handler;
		this.level = level ? level : AbstractLogLevel.ALL;
		this.levelAsNumber = this.level.toNumber();
	}
	
	/**
	 * Returns the wrapped handler not-filtered log messages are fowarded to.
	 * 
	 * @return the wrapped handler	 */
	public function getHandler(Void):LogHandler {
		return this.handler;
	}
	
	/**
	 * Returns the lowest level messages can have that are not filtered. All messages
	 * at a lower level than the returned one are filtered.
	 * 
	 * @return the lowest level of messages that are not filtered	 */
	public function getLevel(Void):LogLevel {
		return this.level;
	}
	
	/**
	 * Forwards that passed-in {@code message} to the wrapped handler if the message
	 * has a higher or the same level than the specified one.
	 * 
	 * @param message the message to forward to the wrapped handler	 */
	public function write(message:LogMessage):Void {
		if (this.levelAsNumber >= message.getLevel().toNumber()) {
			this.handler.write(message);
		}
	}
	
}