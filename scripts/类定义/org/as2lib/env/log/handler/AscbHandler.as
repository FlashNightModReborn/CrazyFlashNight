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

import org.as2lib.core.BasicClass;
import org.as2lib.env.log.LogHandler;
import org.as2lib.env.log.LogMessage;
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.level.AbstractLogLevel;

import ascb.util.logging.LogManager;
import ascb.util.logging.Level;

/**
 * {@code AscbHandler} delegates the log message to the {@code LogManager.log}
 * method of the ASCB Logging API.
 * 
 * @author Simon Wacker
 * @see org.as2lib.env.log.logger.AscbLogger
 * @see <a href="http://www.person13.com/ascblibrary">ASCB Library</a>
 */
class org.as2lib.env.log.handler.AscbHandler extends BasicClass implements LogHandler {
	
	/** Holds a ascb handler. */
	private static var ascbHandler:AscbHandler;
	
	/**
	 * Returns an instance of this class.
	 *
	 * <p>This method always returns the same instance.
	 *
	 * @return a ascb handler
	 */
	public static function getInstance(Void):AscbHandler {
		if (!ascbHandler) ascbHandler = new AscbHandler();
		return ascbHandler;
	}
	
	/** The ASCB {@code LogManager} log messages are delegated to. */
	private var manager:LogManager;
	
	/**	
	 * Constructs a new {@code AscbHandler} instance.
	 * 
	 * <p>You can use one and the same instance for multiple loggers. So think about
	 * using the handler returned by the static {@link #getInstance} method. Using this
	 * instance prevents the instantiation of unnecessary ascb handlers and saves
	 * storage.
	 */
	public function AscbHandler(Void) {
		this.manager = LogManager.getLogManager();
	}
	
	/**
	 * Converts the passed-in {@code message} to a format that is expected formatters
	 * of the ASCB Logging API and passes the converted message to the
	 * {@code LogManager.log} method of the ASCB Logging API.
	 *
	 * <p>The converted object has the following variables:
	 * <dl>
	 *   <dt>level</dt>
	 *   <dd>
	 *     ASCB Logging API level number of the message. The former As2lib
	 *     {@code LogLevel} returned by {@code LogMessage.getLevel} was converted to
	 *     this level number by the {@link #convertLevel} method.
	 *   </dd>
	 *   <dt>message</dt>
	 *   <dd>
	 *     The actual message to log. That is the message returned by the
	 *     {@code LogMessage.getMessage} method.
	 *   </dd>
	 *   <dt>name</dt>
	 *   <dd>
	 *     The name of the logger returned by the {@code LogMessage.getLoggerName}
	 *     method.
	 *   </dd>
	 *   <dt>time</dt>
	 *   <dd>
	 *     The time when the logging took place. This is a {@code Date} instance
	 *     configured with the timestamp returned by the method 
	 *     {@code LogMessage.getTimeStamp}.
	 *   </dd>
	 *   <dt>logMessage</dt>
	 *   <dd>
	 *     The passed-in {@code message} instance. This variable may be used by your
	 *     own formatter if you want to take advantage of the stringifier of the
	 *     {@code LogMessage}.
	 *   </dd>
	 * </dl>
	 *
	 * @param message the message to log
	 */
	public function write(message:LogMessage):Void {
		var logRecord = new Object();
		logRecord.logMessage = message;
		logRecord.level = convertLevel(message.getLevel());
		logRecord.message = message.getMessage();
		logRecord.name = message.getLoggerName();
		logRecord.time = message.getTimeStamp();
		manager.log(logRecord);
	}
	
	/**
	 * Converts the As2lib {@code LogLevel} into a ASCB level.
	 *
	 * <dl>
	 *   <dt>ALL</dt>
	 *   <dd>Is converted to {@code Level.ALL}.</dd>
	 *   <dt>DEBUG</dt>
	 *   <dd>Is converted to {@code Level.DEBUG}.</dd>
	 *   <dt>INFO</dt>
	 *   <dd>Is converted to {@code Level.INFO}.</dd>
	 *   <dt>WARNING</dt>
	 *   <dd>Is converted to {@code Level.WARNING}.</dd>
	 *   <dt>ERROR</dt>
	 *   <dd>Is converted to {@code Level.SEVERE}.</dd>
	 *   <dt>FATAL</dt>
	 *   <dd>Is converted to {@code Level.ALL}.</dd>
	 *   <dt>NONE</dt>
	 *   <dd>Is converted to {@code Level.OFF}.</dd>
	 * </dl>
	 *
	 * <p>If the passed-in {@code level} is none of the above, {@code null} is returned.
	 *
	 * @param level the As2lib log level to convert
	 * @return the equivalent ASCB level number or {@code null}
	 */
	private function convertLevel(level:LogLevel):Number {
		switch (level) {
			case AbstractLogLevel.ALL:
				return Level.ALL;
			case AbstractLogLevel.DEBUG:
				return Level.DEBUG;
			case AbstractLogLevel.INFO:
				return Level.INFO;
			case AbstractLogLevel.WARNING:
				return Level.WARNING;
			case AbstractLogLevel.ERROR:
				return Level.SEVERE;
			case AbstractLogLevel.FATAL:
				return Level.ALL;
			case AbstractLogLevel.NONE:
				return Level.OFF;
			default:
				return null;
		}
	}
	
}