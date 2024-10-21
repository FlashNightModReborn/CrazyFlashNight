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

import org.actionstep.ASDebugger;

/**
 * {@code ActionStepLogger} provides support for the ActionStep Debugger.
 * 
 * <p>The actual logging is always made using the {@code org.actionstep.ASDebugger.trace}
 * method. No other output devices are supported. Use the {@link SimpleLogger} to be
 * able to add log handlers as you please which allows you to log to every device you
 * want.
 * 
 * <p>Configure the ActionStep Debugger API as usually and just use this class in
 * your application to log messages or objects. This enables you to switch between
 * almost every available logging API without having to change the logs in your
 * application but just the underlying configuration on startup.
 * 
 * @author Simon Wacker
 * @see org.as2lib.env.log.handler.ActionStepHandler
 * @see <a href="http://actionstep.sourceforge.net">ActionStep</a>
 */
class org.as2lib.env.log.logger.ActionStepLogger extends BasicClass implements Logger {
	
	/** All level. */
	public static var ALL:Number = 5;
	
	/** ActionStep debug level. */
	public static var DEBUG:Number = 4;
	
	/** ActionStep info level. */
	public static var INFO:Number = 3;
	
	/** ActionStep warning level. */
	public static var WARNING:Number = 2;
	
	/** ActionStep error level. */
	public static var ERROR:Number = 1;
	
	/** ActionStep fatal level. */
	public static var FATAL:Number = 0;
	
	/** None level. */
	public static var NONE:Number = -1;
	
	/** The name of this logger. */
	private var name:String;
	
	/** The set level as number. */
	private var level:Number;
	
	/** {@code ASDebugger} class reference for fast access. */
	private var asDebugger:Function;
	
	/** ActionStep debug level. */
	private var debugLevel:Number;
	
	/** ActionStep info level. */
	private var infoLevel:Number;
	
	/** ActionStep warn level. */
	private var warningLevel:Number;
	
	/** ActionStep error level. */
	private var errorLevel:Number;
	
	/** ActionStep fatal level. */
	private var fatalLevel:Number;
	
	/**
	 * Constructs a new {@code ActionStepLogger} instance.
	 *
	 * <p>The default log level is {@code ALL}. This means all messages regardless of
	 * their level are logged.
	 *
	 * <p>The name is used as class name for the {@code ASDebugger.trace} method, if
	 * the passed class name is {@code null} or {@code undefined}.
	 *
	 * @param name (optional) the name of this logger
	 */
	public function ActionStepLogger(name:String) {
		this.name = name;
		this.level = ALL;
		this.asDebugger = ASDebugger;
		this.debugLevel = DEBUG;
		this.infoLevel = INFO;
		this.warningLevel = WARNING;
		this.errorLevel = ERROR;
		this.fatalLevel = FATAL;
	}
	
	/**
	 * Returns the name of this logger.
	 *
	 * <p>This method returns {@code null} if no name has been set via the
	 * {@link #setName} method nor on construction.
	 *
	 * @return the name of this logger
	 */
	public function getName(Void):String {
		return name;
	}
	
	/**
	 * Sets the name of this logger.
	 *
	 * <p>The name is used as class name for the {@code ASDebugger.trace} method, if
	 * the passed class name is {@code null} or {@code undefined}.
	 *
	 * @param name the new name of this logger
	 */
	public function setName(name:String):Void {
		this.name = name;
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
	 * Checks whether this logger is enabled for the passed-in {@code level}.
	 *
	 * <p>{@code false} will be returned if:
	 * <ul>
	 *   <li>This logger is not enabled for the passed-in {@code level}.</li>
	 *   <li>The passed-in {@code level} is {@code null} or {@code undefined}.</li>
	 * </ul>
	 *
	 * @param level the level to make the check upon
	 * @return {@code true} if this logger is enabled for the given {@code level} else
	 * {@code false}
	 * @see #log
	 */
	public function isEnabled(level:Number):Boolean {
		if (!level) return false;
		return (this.level >= level);
	}
	
	/**
	 * Checks if this logger is enabled for debug level log messages.
	 *
	 * @return {@code true} if debug messages are logged
	 * @see #debug
	 */
	public function isDebugEnabled(Void):Boolean {
		return (this.level >= this.debugLevel);
	}
	
	/**
	 * Checks if this logger is enabled for info level log messages.
	 *
	 * @return {@code true} if info messages are logged
	 * @see #info
	 */
	public function isInfoEnabled(Void):Boolean {
		return (this.level >= this.infoLevel);
	}
	
	/**
	 * Checks if this logger is enabled for warning level log messages.
	 * 
	 * @return {@code true} if warning messages are logged
	 * @see #warning
	 */
	public function isWarningEnabled(Void):Boolean {
		return (this.level >= this.warningLevel);
	}
	
	/**
	 * Checks if this logger is enabled for error level log messages.
	 * 
	 * @return {@code true} if error messages are logged
	 * @see #error
	 */
	public function isErrorEnabled(Void):Boolean {
		return (this.level >= this.errorLevel);
	}
	
	/**
	 * Checks if this logger is enabled for fatal level log messages.
	 * 
	 * @return {@code true} if fatal messages are logged
	 * @see #fatal
	 */
	public function isFatalEnabled(Void):Boolean {
		return (this.level >= this.fatalLevel);
	}
	
	/**
	 * Logs the passed-in {@code message} at the given {@code level}.
	 *
	 * <p>The {@code message} is only logged when this logger is enabled for the
	 * passed-in {@code level}.
	 *
	 * <p>The {@code message} is always logged using {@code ASDebugger.trace} passing
	 * at least the arguments {@code message} and {@code level} and {@code className},
	 * {@code fileName} and {@code lineNumber} if specified.
	 * 
	 * <p>If {@code className} is {@code null} or {@code undefined}, the name of this
	 * logger is used instead.
	 *
	 * @param message the message object to log
	 * @param level the specific level at which the {@code message} shall be logged
	 * @param className (optional) the name of the class that logs the {@code message}
	 * @param fileName (optional) the name of the file that declares the class
	 * @param lineNumber (optional) the line number at which the logging call stands
	 * @see #isEnabled
	 */
	public function log(message, level:Number, className:String, fileName:String, lineNumber:Number):Void {
		if (isEnabled(level)) {
			if (className == null) className = this.name;
			asDebugger.trace(message, level, className, fileName, lineNumber);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at debug level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code DEBUG} or
	 * a level above.
	 *
	 * <p>The {@code message} is always logged using {@code ASDebugger.trace} passing
	 * at least the arguments {@code message}, the debug level and {@code className},
	 * {@code fileName} and {@code lineNumber} if specified.
	 * 
	 * <p>If {@code className} is {@code null} or {@code undefined}, the name of this
	 * logger is used instead.
	 *
	 * @param message the message object to log
	 * @param className (optional) the name of the class that logs the {@code message}
	 * @param fileName (optional) the name of the file that declares the class
	 * @param lineNumber (optional) the line number at which the logging call stands
	 * @see #isDebugEnabled
	 */
	public function debug(message, className:String, fileName:String, lineNumber:Number):Void {
		if (isDebugEnabled()) {
			if (className == null) className = this.name;
			asDebugger.trace(message, this.debugLevel, className, fileName, lineNumber);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at info level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code INFO} or
	 * a level above.
	 *
	 * <p>The {@code message} is always logged using {@code ASDebugger.trace} passing
	 * at least the arguments {@code message}, the info level and {@code className},
	 * {@code fileName} and {@code lineNumber} if specified.
	 * 
	 * <p>If {@code className} is {@code null} or {@code undefined}, the name of this
	 * logger is used instead.
	 *
	 * @param message the message object to log
	 * @param className (optional) the name of the class that logs the {@code message}
	 * @param fileName (optional) the name of the file that declares the class
	 * @param lineNumber (optional) the line number at which the logging call stands
	 * @see #isInfoEnabled
	 */
	public function info(message, className:String, fileName:String, lineNumber:Number):Void {
		if (isInfoEnabled()) {
			if (className == null) className = this.name;
			asDebugger.trace(message, this.infoLevel, className, fileName, lineNumber);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at warning level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code WARNING}
	 * or a level above.
	 *
	 * <p>The {@code message} is always logged using {@code ASDebugger.trace} passing
	 * at least the arguments {@code message}, the warning level and {@code className},
	 * {@code fileName} and {@code lineNumber} if specified.
	 * 
	 * <p>If {@code className} is {@code null} or {@code undefined}, the name of this
	 * logger is used instead.
	 *
	 * @param message the message object to log
	 * @param className (optional) the name of the class that logs the {@code message}
	 * @param fileName (optional) the name of the file that declares the class
	 * @param lineNumber (optional) the line number at which the logging call stands
	 * @see #isWarningEnabled
	 */
	public function warning(message, className:String, fileName:String, lineNumber:Number):Void {
		if (isWarningEnabled()) {
			if (className == null) className = this.name;
			asDebugger.trace(message, this.warningLevel, className, fileName, lineNumber);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at error level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code ERROR} or
	 * a level above.
	 *
	 * <p>The {@code message} is always logged using {@code ASDebugger.trace} passing
	 * at least the arguments {@code message}, the error level and {@code className},
	 * {@code fileName} and {@code lineNumber} if specified.
	 * 
	 * <p>If {@code className} is {@code null} or {@code undefined}, the name of this
	 * logger is used instead.
	 *
	 * @param message the message object to log
	 * @param className (optional) the name of the class that logs the {@code message}
	 * @param fileName (optional) the name of the file that declares the class
	 * @param lineNumber (optional) the line number at which the logging call stands
	 * @see #isErrorEnabled
	 */
	public function error(message, className:String, fileName:String, lineNumber:Number):Void {
		if (isErrorEnabled()) {
			if (className == null) className = this.name;
			asDebugger.trace(message, this.errorLevel, className, fileName, lineNumber);
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at fatal level.
	 * 
	 * <p>The {@code message} is only logged when the level is set to {@code FATAL} or
	 * a level above.
	 * 
	 * <p>The {@code message} is always logged using {@code ASDebugger.trace} passing
	 * at least the arguments {@code message}, the fatal level and {@code className},
	 * {@code fileName} and {@code lineNumber} if specified.
	 * 
	 * <p>If {@code className} is {@code null} or {@code undefined}, the name of this
	 * logger is used instead.
	 * 
	 * @param message the message object to log
	 * @param className (optional) the name of the class that logs the {@code message}
	 * @param fileName (optional) the name of the file that declares the class
	 * @param lineNumber (optional) the line number at which the logging call stands
	 * @see #isFatalEnabled
	 */
	public function fatal(message, className:String, fileName:String, lineNumber:Number):Void {
		if (isFatalEnabled()) {
			if (className == null) className = this.name;
			asDebugger.trace(message, this.fatalLevel, className, fileName, lineNumber);
		}
	}
	
}