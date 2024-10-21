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
import org.as2lib.env.log.Logger;

/**
 * {@code ZtorLog4fLogger} delegates all messages to the {@code Log4f.log} method of
 * the ZTOR Log4f project.
 * 
 * <p>Using this class instead of the {@code Log4f} class in your application
 * directly enables you to switch between almost every available Logging API without
 * having to change the logging calls in your application but just the configuration
 * on startup.
 *
 * <p>Every global configuration must be done via the static methods on the
 * {@code Log4f} class itself.
 *
 * @author Simon Wacker
 * @see org.as2lib.env.log.handler.ZtorLog4fHandler
 * @see <a href="http://www.ztor.com/index.php4?ln=&g=comp&d=log4f">ZTOR Log4f</a>
 */
class org.as2lib.env.log.logger.ZtorLog4fLogger extends BasicClass implements Logger {
	
	/** All level. */
	public static var ALL:Number = -1;
	
	/** ZTOR Log4f debug level. */
	public static var DEBUG:Number = Log4f.DEBUG;
	
	/** ZTOR Log4f info level. */
	public static var INFO:Number = Log4f.INFO;
	
	/** ZTOR Log4f warn level. */
	public static var WARN:Number = Log4f.WARN;
	
	/** ZTOR Log4f error level. */
	public static var ERROR:Number = Log4f.ERROR;
	
	/** ZTOR Log4f fatal level. */
	public static var FATAL:Number = Log4f.FATAL;
	
	/** ZTOR Log4f log4f level. */
	public static var LOG4F:Number = Log4f.LOG4F;
	
	/** None level. */
	public static var NONE:Number = 6;
	
	/** The current log level. */
	private var level:Number;
	
	/** ZTOR Log4f debug level. */
	private var debugLevel:Number;
	
	/** ZTOR Log4f info level. */
	private var infoLevel:Number;
	
	/** ZTOR Log4f warn level. */
	private var warnLevel:Number;
	
	/** ZTOR Log4f error level. */
	private var errorLevel:Number;
	
	/** ZTOR Log4f fatal level. */
	private var fatalLevel:Number;
	
	/**
	 * Constructs a new {@code ZtorLog4fLogger} instance.
	 * 
	 * <p>The level is by default set to {@link #ALL}. All messages regardless of
	 * their type are logged then.
	 * 
	 * @param level (optional) the level of this logger
	 */
	public function ZtorLog4fLogger(level:Number) {
		setLevel(level);
		this.debugLevel = DEBUG;
		this.infoLevel = INFO;
		this.warnLevel = WARN;
		this.errorLevel = ERROR;
		this.fatalLevel = FATAL;
	}
	
	/**
	 * Sets the log level.
	 *
	 * <p>The log level determines which messages are logged and which are not.
	 *
	 * <p>A level of value {@code null} or {@code undefined} is interpreted as level
	 * {@code ALL} which is also the default level.
	 * 
	 * @param level the new log level
	 */
	public function setLevel(level:Number):Void {
		if (level == null) {
			this.level = ALL;
		} else {
			this.level = level;
		}
	}
	
	/**
	 * Returns the set level.
	 *
	 * @return the set level
	 */
	public function getLevel(Void):Number {
		return this.level;
	}
	
	/**
	 * Checks if this logger is enabled for debug level messages.
	 *
	 * @return {@code true} if debug messages are logged
	 * @see #debug
	 */
	public function isDebugEnabled(Void):Boolean {
		return (this.level <= this.debugLevel);
	}
	
	/**
	 * Checks if this logger is enabled for info level messages.
	 *
	 * @return {@code true} if info messages are logged
	 * @see #info
	 */
	public function isInfoEnabled(Void):Boolean {
		return (this.level <= this.infoLevel);
	}
	
	/**
	 * Checks if this logger is enabled for warning level messages.
	 *
	 * @return {@code true} if warning messages are logged
	 * @see #warning
	 */
	public function isWarningEnabled(Void):Boolean {
		return (this.level <= this.warnLevel);
	}
	
	/**
	 * Checks if this logger is enabled for error level messages.
	 *
	 * @return {@code true} if error messages are logged
	 * @see #error
	 */
	public function isErrorEnabled(Void):Boolean {
		return (this.level <= this.errorLevel);
	}
	
	/**
	 * Checks if this logger is enabled for fatal level messages.
	 *
	 * @return {@code true} if fatal messages are logged
	 * @see #fatal
	 */
	public function isFatalEnabled(Void):Boolean {
		return (this.level <= this.fatalLevel);
	}
	
	/**
	 * Logs the passed-in {@code message} at debug level.
	 *
	 * <p>The {@code message} is only logged when the level is set to debug or a level
	 * above.
	 *
	 * <p>The {@code message} is logged using the {@code Log4f.log} method, passing
	 * the debug level number and the message as header.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 */
	public function debug(message):Void {
		if (isDebugEnabled()) {
			Log4f.log(this.debugLevel, message, "");
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at info level.
	 *
	 * <p>The {@code message} is only logged when the level is set to info or a level
	 * above.
	 *
	 * <p>The {@code message} is logged using the {@code Log4f.log} method, passing
	 * the info level number and the message as header.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 */
	public function info(message):Void {
		if (isInfoEnabled()) {
			Log4f.log(this.infoLevel, message, "");
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at warning level.
	 *
	 * <p>The {@code message} is only logged when the level is set to warning or a
	 * level above.
	 *
	 * <p>The {@code message} is logged using the {@code Log4f.log} method, passing
	 * the warn level number and the message as header.
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 */
	public function warning(message):Void {
		if (isWarningEnabled()) {
			Log4f.log(this.warnLevel, message, "");
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at error level.
	 *
	 * <p>The {@code message} is only logged when the level is set to error or a level
	 * above.
	 *
	 * <p>The {@code message} is logged using the {@code Log4f.log} method, passing
	 * the error level number and the message as header.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 */
	public function error(message):Void {
		if (isErrorEnabled()) {
			Log4f.log(this.errorLevel, message, "");
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at fatal level.
	 *
	 * <p>The {@code message} is only logged when the level is set to fatal or a level
	 * above.
	 *
	 * <p>The {@code message} is logged using the {@code Log4f.log} method, passing
	 * the fatal level number and the message as header.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 */
	public function fatal(message):Void {
		if (isFatalEnabled()) {
			Log4f.log(this.fatalLevel, message, "");
		}
	}
	
}