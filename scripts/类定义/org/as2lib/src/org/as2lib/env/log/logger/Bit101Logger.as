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
import org.as2lib.env.log.LogMessage;
import org.as2lib.env.log.logger.AbstractLogger;

/**
 * {@code Bit101Logger} delegates all log messages to the {@code Debug.trace}
 * method from Keith Peter's Debug Panel.
 * 
 * <p>Using this class instead of the {@code Debug} class in your application
 * directly enables you to switch between almost every available Logging API
 * without having to change the logging calls but just the underlying configuration
 * on startup.
 *
 * @author Simon Wacker
 * @see org.as2lib.env.log.handler.Bit101Handler
 * @see <a href="http://www.bit-101.com/DebugPanel">Flash Debug Panel Source</a>
 * @see <a href="http://www.bit-101.com/blog/archives/000119.html">Flash Debug Panel Article</a>
 */
class org.as2lib.env.log.logger.Bit101Logger extends AbstractLogger implements Logger {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractLogger;
	
	/** The set level. */
	private var level:LogLevel;
	
	/** The set level as number. */
	private var levelAsNumber:Number;
	
	/** Determines whether to trace objects recursively. */
	private var traceObject:Boolean;
	
	/** The number of recursions when tracing an object recursively. */
	private var recursionDepth:Number;
	
	/** The indentation number for recursively traced objects. */
	private var indentation:Number;
	
	/**
	 * Constructs a new {@code Bit101Logger} instance.
	 *
	 * <p>The default log level is {@code ALL}. This means all messages regardless of
	 * their level are logged.
	 *
	 * <p>{@code traceObject} is by default {@code false}. Refer to the {@code Debug}
	 * class for information on the default {@code recursionDepth} and
	 * {@code indentation}.
	 *
	 * @param traceObject (optional) determines whether to trace objects recursively
	 * or to use the result of their {@code toString} method
	 * @param recursionDepth (optional) determines the count of recursions for
	 * recursively traced objects
	 * @param indentation (optional) determines the indentation number for recursively
	 * traced objects
	 */
	public function Bit101Logger(traceObject:Boolean, recursionDepth:Number, indentation:Number) {
		this.traceObject = !traceObject ? false : true;
		this.recursionDepth = recursionDepth;
		this.indentation = indentation;
		level = ALL;
		levelAsNumber = level.toNumber();
	}
	
	/**
	 * Sets the log level.
	 *
	 * <p>The log level determines which messages are logged and which are not.
	 *
	 * <p>A level of value {@code null} or {@code undefined} is interpreted as level
	 * {@code ALL}, which is also the default level.
	 *
	 * @param level the new log level
	 */
	public function setLevel(level:LogLevel):Void {
		if (level) {
			this.level = level;
		} else {
			this.level = ALL;
		}
		this.levelAsNumber = this.level.toNumber();
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
	 * Checks if this logger is enabled for debug level messages.
	 *
	 * @return {@code true} if debug messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#DEBUG
	 * @see #debug
	 */
	public function isDebugEnabled(Void):Boolean {
		return (levelAsNumber >= debugLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for info level messages.
	 *
	 * @return {@code true} if info messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#INFO
	 * @see #info
	 */
	public function isInfoEnabled(Void):Boolean {
		return (levelAsNumber >= infoLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for warning level messages.
	 *
	 * @return {@code true} if warning messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#WARNING
	 * @see #warning
	 */
	public function isWarningEnabled(Void):Boolean {
		return (levelAsNumber >= warningLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for error level messages.
	 *
	 * @return {@code true} if error messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#ERROR
	 * @see #error
	 */
	public function isErrorEnabled(Void):Boolean {
		return (levelAsNumber >= errorLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for fatal level messages.
	 *
	 * @return {@code true} if fatal messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#FATAL
	 * @see #fatal
	 */
	public function isFatalEnabled(Void):Boolean {
		return (levelAsNumber >= fatalLevelAsNumber);
	}
	
	/**
	 * Logs the {@code message} using the {@code Debug.trace} method if
	 * {@code traceObject} is turned off or if the {@code message} is of type
	 * {@code "string"}, {@code "number"}, {@code "boolean"}, {@code "undefined"} or
	 * {@code "null"} and using the {@code Debug.traceObject} method if neither of the
	 * above cases holds {@code true}.
	 *
	 * @param message the message to log
	 */
	public function log(message):Void {
		if (this.traceObject) {
			var type:String = typeof(message);
			if (type == "string" || type == "number" || type == "boolean" || type == "undefined" || type == "null") {
				Debug.trace(message.toString());
			} else {
				Debug.traceObject(message, this.recursionDepth, this.indentation);
			}
		} else {
			Debug.trace(message.toString());
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at debug level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code DEBUG} or
	 * a level above.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 */
	public function debug(message):Void {
		if (isDebugEnabled()) {
			log(message);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} object at info level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code INFO} or
	 * a level above.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 */
	public function info(message):Void {
		if (isInfoEnabled()) {
			log(message);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} object at warning level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code WARNING}
	 * or a level above.
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 */
	public function warning(message):Void {
		if (isWarningEnabled()) {
			log(message);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} object at error level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code ERROR} or a
	 * level above.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 */
	public function error(message):Void {
		if (isErrorEnabled()) {
			log(message);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} object at fatal level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code FATAL} or
	 * a level above.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 */
	public function fatal(message):Void {
		if (isFatalEnabled()) {
			log(message);
		}
	}
	
}