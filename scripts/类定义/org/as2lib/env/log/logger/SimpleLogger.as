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

import org.as2lib.env.event.distributor.EventDistributorControl;
import org.as2lib.env.event.distributor.SimpleEventDistributorControl;
import org.as2lib.env.log.LogHandler;
import org.as2lib.env.log.ConfigurableLogger;
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.LogMessage;
import org.as2lib.env.log.logger.AbstractLogger;

/**
 * {@code SimpleLogger} is a simple implementation of the {@code ConfigurableLogger}
 * interface.
 * 
 * <p>The basic methods to write the log messages are {@link #log}, {@link #debug},
 * {@link #info}, {@link #warning} and {@link #fatal}.
 *
 * <p>The first thing to note is that you can log messages at different levels.
 * These levels are {@code DEBUG}, {@code INFO}, {@code WARNING}, {@code ERROR}
 * and {@code FATAL}. Depending on what level has been set only messages at a
 * given level are logged. The levels are organized in a hierarchical manner. That
 * means if you set the log level to {@code ALL} every messages is logged. If you
 * set it to {@code ERROR} only messages at {@code ERROR} and {@code FATAL} level
 * are logged and so on. It is also possible to define your own set of levels. You
 * can therefor use the {@link #isEnabled} and {@link #log} methods.
 *
 * <p>To do not waste unnecessary performance in constructing log messages that are
 * not logged you can use the methods {@link #isEnabled}, {@link #isDebugEnabled},
 * {@link #isInfoEnabled}, {@link #isWarningEnabled}, {@link #isErrorEnabled}
 * and {@link #isFatalEnabled}.
 * 
 * <p>Note that the message does in neither case have to be a string. That means
 * you can pass-in messages and let the actual log handler decide how to produce a
 * string representation of the message. This is in most cases done by using the
 * {@code toString} method of the specific message. You can use this method to do
 * not lose performance in cases where the message is not logged.
 *
 * <p>The actaul log output is made by log handlers. To configure and
 * access the handlers of this logger you can use the methods {@link #addHandler},
 * {@link #removeHandler}, {@link #removeAllHandlers} and {@link #getAllHandlers}.
 * There are a few pre-defined handlers for different output devices.
 * Take a look at the {@code org.as2lib.env.log.handler} package for these.
 *
 * <p>Example:
 * <code>
 *   var logger:SimpleLogger = new SimpleLogger("mySimpleLogger");
 *   // adds a trace handler that is responsible for making the output
 *   logger.addHandler(new TraceHandler());
 *   // checks if the output gets actually made
 *   if (logger.isInfoEnabled()) {
 *	     // log the message at the info level
 *       logger.info("This is an informative log message.");
 *   }
 * </code>
 *
 * <p>This logger cannot be used with the {@code LoggerHierarchy} because it does
 * not offer hierarchy support. If you want to use your logger in a hierarchy use
 * the {@link SimpleHierarchicalLogger} instead.
 * 
 * @author Simon Wacker
 * @see org.as2lib.env.log.repository.LoggerHierarchy
 */
class org.as2lib.env.log.logger.SimpleLogger extends AbstractLogger implements ConfigurableLogger {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractLogger;
	
	/** The set level. */
	private var level:LogLevel;
	
	/** The set level as number. */
	private var levelAsNumber:Number;
	
	/** Distributor control that controls the distributor. */
	private var distributorControl:EventDistributorControl;
	
	/** Typed distributor that distributes messages to all log handlers. */
	private var distributor:LogHandler;
	
	/** The name of this logger. */
	private var name:String;
	
	/**
	 * Constructs a new {@code SimpleLogger} instance.
	 *
	 * <p>The default log level is {@code ALL}. This means all messages regardless of
	 * their level are logged.
	 * 
	 * <p>The logger {@code name} is by default shown in the log message to identify
	 * where the message came from.
	 * 
	 * @param name (optional) the name of this logger
	 */
	public function SimpleLogger(name:String) {
		this.name = name;
		distributorControl = new SimpleEventDistributorControl(LogHandler, false);
		distributor = this.distributorControl.getDistributor();
		level = ALL;
		levelAsNumber = level.toNumber();
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
	 * <p>The name is by default shown in the log message.
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
	 * Adds a new log handler.
	 *
	 * <p>Log handlers are used to actually log the messages. They determine what
	 * information to log and to which output device.
	 *
	 * <p>This method simply does nothing if the passed-in handler is {@code null} or
	 * {@code undefined}.
	 *
	 * @param handler the new log handler to log messages
	 */
	public function addHandler(handler:LogHandler):Void {
		if (handler) {
			distributorControl.addListener(handler);
		}
	}
	
	/**
	 * Removes all occerrences of the passed-in log {@code handler}.
	 *
	 * <p>If the passed-in {@code handler} is {@code null} or {@code undefined} the
	 * method invocation is simply ignored.
	 *
	 * @param handler the log handler to remove
	 */
	public function removeHandler(handler:LogHandler):Void {
		if (handler) {
			distributorControl.removeListener(handler);
		}
	}
	
	/**
	 * Removes all added log handlers.
	 */
	public function removeAllHandlers(Void):Void {
		distributorControl.removeAllListeners();
	}
	
	/**
	 * Returns all handlers that were added to this logger.
	 *
	 * <p>If there are no added handlers an empty array is returned.
	 *
	 * @return all added log handlers
	 */
	public function getAllHandlers(Void):Array {
		return distributorControl.getAllListeners();
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
	 * <p>Using this method as shown in the class documentation may improve performance
	 * depending on how long the log message construction takes.
	 *
	 * @param level the level to make the check upon
	 * @return {@code true} if this logger is enabled for the given {@code level} else
	 * {@code false}
	 * @see #log
	 */
	public function isEnabled(level:LogLevel):Boolean {
		if (!level) return false;
		return (levelAsNumber >= level.toNumber());
	}
	
	/**
	 * Checks if this logger is enabled for debug level log messages.
	 *
	 * <p>Using this method as shown in the class documentation may improve performance
	 * depending on how long the log message construction takes.
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
	 * <p>Using this method as shown in the class documentation may improve performance
	 * depending on how long the log message construction takes.
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
	 * <p>Using this method as shown in the class documentation may improve performance
	 * depending on how long the log message construction takes.
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
	 * <p>Using this method as shown in the class documentation may improve performance
	 * depending on how long the log message construction takes.
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
	 * <p>Using this method as shown in the class documentation may improve performance
	 * depending on how long the log message construction takes.
	 *
	 * @return {@code true} if fatal messages are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#FATAL
	 * @see #fatal
	 */
	public function isFatalEnabled(Void):Boolean {
		return (levelAsNumber >= fatalLevelAsNumber);
	}
	
	/**
	 * Logs the {@code message} at the given {@code level}.
	 *
	 * <p>The {@code message} is only logged when this logger is enabled for the
	 * passed-in {@code level}.
	 *
	 * @param message the message object to log
	 * @param level the specific level at which the {@code message} shall be logged
	 * @see #isEnabled
	 */
	public function log(message, level:LogLevel):Void {
		if (isEnabled(level)) {
			distributor.write(new LogMessage(message, level, name));
		}
	}
	
	/**
	 * Logs the {@code message} object at debug level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code DEBUG} or
	 * a level above.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 */
	public function debug(message):Void {
		if (isDebugEnabled()) {
			distributor.write(new LogMessage(message, debugLevel, name));
		}
	}
	
	/**
	 * Logs the {@code message} object at info level.
	 *
	 * <p>The {@code message} gets only logged when the level is set to {@code INFO}
	 * or a level above.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 */
	public function info(message):Void {
		if (isInfoEnabled()) {
			distributor.write(new LogMessage(message, infoLevel, name));
		}
	}
	
	/**
	 * Logs the {@code message} object at warning level.
	 *
	 * <p>The {@code message} gets only logged when the level is set to {@code WARNING}
	 * or a level above.
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 */
	public function warning(message):Void {
		if (isWarningEnabled()) {
			distributor.write(new LogMessage(message, warningLevel, name));
		}
	}
	
	/**
	 * Logs the {@code message} object at error level.
	 *
	 * <p>The {@code message} gets only logged when the level is set to {@code ERROR}
	 * or a level above.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 */
	public function error(message):Void {
		if (isErrorEnabled()) {
			distributor.write(new LogMessage(message, errorLevel, name));
		}
	}
	
	/**
	 * Logs the {@code message} object at fatal level.
	 *
	 * <p>The {@code message} gets only logged when the level is set to {@code FATAL}
	 * or a level above.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 */
	public function fatal(message):Void {
		if (isFatalEnabled()) {
			distributor.write(new LogMessage(message, fatalLevel, name));
		}
	}
	
}