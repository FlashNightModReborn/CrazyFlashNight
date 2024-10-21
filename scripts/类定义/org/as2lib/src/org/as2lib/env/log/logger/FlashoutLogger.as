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

import org.as2lib.env.log.Logger;
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.logger.AbstractLogger;

/**
 * {@code FlashoutLogger} delegates all log messages to the appropriate methods on
 * the {@code Flashout} class.
 * 
 * <p>Using this class instead of the {@code Flashout} class in your application
 * directly enables you to switch between almost every available Logging API without
 * having to change the logging calls, but just the underlying configuration on
 * startup.
 * 
 * <p>Note that if you are working with the Flashout 0.2.* you have to specify
 * Flashout's custom trace method as trace replacement when compiling your classes
 * with MTASC.
 * 
 * @author Simon Wacker
 * @see org.as2lib.env.log.handler.FlashoutHandler
 * @see <a href="http://www.potapenko.com/flashout">Flashout</a>
 */
class org.as2lib.env.log.logger.FlashoutLogger extends AbstractLogger implements Logger {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractLogger;
	
	/** The set level. */
	private var level:LogLevel;
	
	/** The set level as number. */
	private var levelAsNumber:Number;
	
	/**
	 * Constructs a new {@code FlashoutLogger} instance.
	 *
	 * <p>The default log level is {@code ALL}. This means all messages regardless of
	 * their level are logged.
	 */
	public function FlashoutLogger(Void) {
		level = ALL;
		levelAsNumber = level.toNumber();
	}
	
	/**
	 * Sets the log level.
	 *
	 * <p>The log level determines which messages are logged and which are not.
	 *
	 * <p>A level of value {@code null} or {@code undefined} os interpreted as level
	 * {@code ALL} which is also the default level.
	 *
	 * @param level the new log level
	 */
	public function setLevel(level:LogLevel):Void {
		if (level) {
			this.level = level;
			levelAsNumber = level.toNumber();
		} else {
			this.level = ALL;
			levelAsNumber = level.toNumber();
		}
	}
	
	/**
	 * Returns the set level.
	 *
	 * @return the set level
	 */
	public function getLevel(Void):LogLevel {
		return level;
	}
	
	/**
	 * Checks if this logger is enabled for debug level log messages.
	 *
	 * @return {@code true} if debug messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#DEBUG
	 * @see #debug
	 */
	public function isDebugEnabled(Void):Boolean {
		return (levelAsNumber >= debugLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for info level log messages.
	 *
	 * @return {@code true} if info messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#INFO
	 * @see #info
	 */
	public function isInfoEnabled(Void):Boolean {
		return (levelAsNumber >= infoLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for warning level log messages.
	 *
	 * @return {@code true} if warning messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#WARNING
	 * @see #warning
	 */
	public function isWarningEnabled(Void):Boolean {
		return (levelAsNumber >= warningLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for error level log messages.
	 *
	 * @return {@code true} if error messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#ERROR
	 * @see #error
	 */
	public function isErrorEnabled(Void):Boolean {
		return (levelAsNumber >= errorLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for fatal level log messages.
	 *
	 * @return {@code true} if fatal messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#FATAL
	 * @see #fatal
	 */
	public function isFatalEnabled(Void):Boolean {
		return (levelAsNumber >= fatalLevelAsNumber);
	}
	
	/**
	 * Logs the passed-in {@code message} at debug level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code DEBUG} or
	 * a level above.
	 *
	 * <p>The {@code message} is logged using the {@code Flashout.debug} method.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 */
	public function debug(message):Void {
		if (isDebugEnabled()) {
			Flashout.debug(message);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} object at info level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code INFO} or
	 * a level above.
	 *
	 * <p>The {@code message} is logged using the {@code Flashout.info} method.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 */
	public function info(message):Void {
		if (isInfoEnabled()) {
			Flashout.info(message);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} object at warning level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code WARNING}
	 * or a level above.
	 *
	 * <p>The {@code message} is logged using the {@code Flashout.warning} method.
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 */
	public function warning(message):Void {
		if (isWarningEnabled()) {
			Flashout.warning(message);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} object at error level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code ERROR} or
	 * a level above.
	 *
	 * <p>The {@code message} is logged using the {@code Flashout.error} method.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 */
	public function error(message):Void {
		if (isErrorEnabled()) {
			Flashout.error(message);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} object at fatal level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code FATAL} or
	 * a level above.
	 *
	 * <p>The {@code message} is logged using the {@code Flashout.error} method.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 */
	public function fatal(message):Void {
		if (isFatalEnabled()) {
			// old Flashout did not provide fatal level
			// wanted support to be compatible with both versions
			if (Flashout["fatal"]) {
				Flashout["fatal"](message);
			} else {
				Flashout.error(message);
			}
		}
	}
	
}