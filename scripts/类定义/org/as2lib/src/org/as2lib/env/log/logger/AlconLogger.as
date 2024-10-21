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

import net.hiddenresource.util.Debug;

/**
 * {@code AlconLogger} delegates all messages to the
 * {@code net.hiddenresource.util.Debug.trace} method.
 * 
 * <p>Using this class instead of the {@code Debug} class in your application
 * directly enables you to switch between almost every available Logging API without
 * having to change the logging calls but just the configuration on startup.
 *
 * <p>Every global configuration must be done via the static methods on the
 * {@code Debug} class itself.
 *
 * @author Simon Wacker
 * @see org.as2lib.env.log.handler.AlconHandler
 * @see <a href="http://hiddenresource.corewatch.net/index.php?itemid=17">Alcon</a>
 */
class org.as2lib.env.log.logger.AlconLogger extends BasicClass implements Logger {
	
	/** Alcon debug level. */
	public static var DEBUG:Number = 0;
	
	/** Alcon info level. */
	public static var INFO:Number = 1;
	
	/** Alcon warn level. */
	public static var WARN:Number = 2;
	
	/** Alcon error level. */
	public static var ERROR:Number = 3;
	
	/** Alcon fatal level. */
	public static var FATAL:Number = 4;
	
	/** Determines whether to trace recursively or not. */
	private var recursiveTracing:Boolean;
	
	/** Alcon debug level. */
	private var debugLevel:Number;
	
	/** Alcon info level. */
	private var infoLevel:Number;
	
	/** Alcon warn level. */
	private var warnLevel:Number;
	
	/** Alcon error level. */
	private var errorLevel:Number;
	
	/** Alcon fatal level. */
	private var fatalLevel:Number;
	
	/**
	 * Constructs a new {@code AlconLogger} instance.
	 *
	 * <p>The default value for {@code recursiveTracing} is {@code true}.
	 *
	 * @param recursiveTracing (optional) determines whether to trace messages
	 * recursively
	 */
	public function AlconLogger(recursiveTracing:Boolean) {
		this.recursiveTracing = recursiveTracing == null ? true : recursiveTracing;
		this.debugLevel = DEBUG;
		this.infoLevel = INFO;
		this.warnLevel = WARN;
		this.errorLevel = ERROR;
		this.fatalLevel = FATAL;
	}
	
	/**
	 * Checks if this logger is enabled for debug level messages.
	 *
	 * @return {@code true} if debug messages are logged
	 * @see #debug
	 */
	public function isDebugEnabled(Void):Boolean {
		return (Debug.getFilterLevel() <= this.debugLevel);
	}
	
	/**
	 * Checks if this logger is enabled for info level messages.
	 *
	 * @return {@code true} if info messages are logged
	 * @see #info
	 */
	public function isInfoEnabled(Void):Boolean {
		return (Debug.getFilterLevel() <= this.infoLevel);
	}
	
	/**
	 * Checks if this logger is enabled for warning level messages.
	 *
	 * @return {@code true} if warning messages are logged
	 * @see #warning
	 */
	public function isWarningEnabled(Void):Boolean {
		return (Debug.getFilterLevel() <= this.warnLevel);
	}
	
	/**
	 * Checks if this logger is enabled for error level messages.
	 *
	 * @return {@code true} if error messages are logged
	 * @see #error
	 */
	public function isErrorEnabled(Void):Boolean {
		return (Debug.getFilterLevel() <= this.errorLevel);
	}
	
	/**
	 * Checks if this logger is enabled for fatal level messages.
	 *
	 * @return {@code true} if fatal messages are logged
	 * @see #fatal
	 */
	public function isFatalEnabled(Void):Boolean {
		return (Debug.getFilterLevel() <= this.fatalLevel);
	}
	
	/**
	 * Logs the passed-in {@code message} at debug level.
	 *
	 * <p>The {@code message} is only logged when the level is set to debug or a level
	 * above.
	 *
	 * <p>The {@code message} is logged using the {@code Alcon.trace} method, passing
	 * the debug level number.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 */
	public function debug(message):Void {
		Debug.trace(message, this.debugLevel, this.recursiveTracing);
	}
	
	/**
	 * Logs the passed-in {@code message} at info level.
	 *
	 * <p>The {@code message} is only logged when the level is set to info or a level
	 * above.
	 *
	 * <p>The {@code message} is logged using the {@code Alcon.trace} method, passing
	 * the info level number.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 */
	public function info(message):Void {
		Debug.trace(message, this.infoLevel, this.recursiveTracing);
	}
	
	/**
	 * Logs the passed-in {@code message} at warning level.
	 *
	 * <p>The {@code message} is only logged when the level is set to warning or a
	 * level above.
	 *
	 * <p>The {@code message} is logged using the {@code Alcon.trace} method, passing
	 * the warn level number.
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 */
	public function warning(message):Void {
		Debug.trace(message, this.warnLevel, this.recursiveTracing);
	}
	
	/**
	 * Logs the passed-in {@code message} at error level.
	 *
	 * <p>The {@code message} is only logged when the level is set to error or a level
	 * above.
	 *
	 * <p>The {@code message} is logged using the {@code Alcon.trace} method, passing
	 * the error level number.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 */
	public function error(message):Void {
		Debug.trace(message, this.errorLevel, this.recursiveTracing);
	}
	
	/**
	 * Logs the passed-in {@code message} at fatal level.
	 *
	 * <p>The {@code message} is only logged when the level is set to fatal or a level
	 * above.
	 *
	 * <p>The {@code message} is logged using the {@code Alcon.trace} method, passing
	 * the fatal level number.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 */
	public function fatal(message):Void {
		Debug.trace(message, this.fatalLevel, this.recursiveTracing);
	}
	
}