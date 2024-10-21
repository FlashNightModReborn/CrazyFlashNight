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
import org.as2lib.env.log.ConfigurableHierarchicalLogger;
import org.as2lib.env.log.HierarchicalLogger;
import org.as2lib.env.log.LogMessage;
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.logger.AbstractLogger;

/**
 * {@code SimpleHierarchicalLogger} is a simple implementation of the
 * {@code ConfigurableLogger} and {@code ConfigurableHierarchicalLogger}
 * interfaces.
 * 
 * <p>This logger is thus capable of functioning correctly in a hierarchy. It is
 * normally used with the {@code LoggerHierarchy} repository.
 *
 * <p>The basic methods to write log messages are {@link #log}, {@link #debug},
 * {@link #info}, {@link #warning} and {@link #fatal}.
 * 
 * <p>The first thing to note is that you can log messages at different levels.
 * These levels are {@code DEBUG}, {@code INFO}, {@code WARNING}, {@code ERROR} and
 * {@code FATAL}. Depending on what level has been set only messages at a given
 * level are logged. The levels are organized in a hierarchical manner. This means
 * if you set the log level to {@code ALL} every messages is logged. If you set it
 * to {@code ERROR} only messages at {@code ERROR} and {@code FATAL} level are
 * logged and so on. It is also possible to define your own set of levels. You can
 * therefor use the {@link #isEnabled} and {@link #log} methods. If you do not set
 * a log level the level of its parent is used to decide whether the message shall
 * be logged.
 *
 * <p>To do not waste unnecessary performance in constructing log messages that
 * are not logged you can use the {@link #isEnabled}, {@link #isDebugEnabled},
 * {@link #isInfoEnabled}, {@link #isWarningEnabled}, {@link #isErrorEnabled}
 * and {@link #isFatalEnabled} methods.
 * 
 * <p>Note that the message does in neither case have to be a string. That means
 * you can pass-in messages and let the actual handler or logger decide how to
 * produce a string representation of the message. That is in most cases done by
 * using the {@code toString} method of the specific message. You can use this
 * method to do not lose performance in cases where the message is not logged.
 *
 * <p>The actual logging is made by log handlers. To configure and access the
 * handlers of this logger you can use the methods {@link #addHandler},
 * {@link #removeHandler}, {@link #removeAllHandlers} and {@link #getAllHandlers}.
 * There are a few pre-defined handlers for different output devices. Take a look
 * at the {@code org.as2lib.env.log.handler} package for these. This logger does
 * not only use the handlers of itself but also the ones of its parents.
 * 
 * <p>Note that advantage of this class's hierarchical support is not taken in the
 * following example. Take a look at the class documentation of the
 * {@code LoggerHierarchy} for an example that uses this support.
 *
 * <code>
 *   var logger:SimpleHierarchicalLogger = new SimpleHierarchicalLogger("myLogger");
 *   logger.setLevel(SimpleHierarchicalLogger.ALL);
 *   logger.addHandler(new TraceHandler());
 *   if (logger.isInfoEnabled()) {
 *       logger.info("This is an information message.");
 *   }
 * </code>
 *
 * @author Simon Wacker
 * @see org.as2lib.env.log.repository.LoggerHierarchy
 */
class org.as2lib.env.log.logger.SimpleHierarchicalLogger extends AbstractLogger implements ConfigurableLogger, ConfigurableHierarchicalLogger {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractLogger;
	
	/** The actual level. */
	private var level:LogLevel;
	
	/** Says whether the handlers array already contains the parents' handlers. */
	private var addedParentHandlers:Boolean;
	
	/** Stores the parent. */
	private var parent:HierarchicalLogger;
	
	/** The name of this logger. */
	private var name:String;
	
	/** Distributor control that controls the distributor. */
	private var distributorControl:EventDistributorControl;
	
	/** Typed distributor that distributes messages to all log handlers. */
	private var distributor:LogHandler;
	
	/**
	 * Constructs a new {@code SimpleHierarchicalLogger} instance.
	 *
	 * @param name the name of this new logger
	 */
	public function SimpleHierarchicalLogger(name:String) {
		setName(name);
		distributorControl = new SimpleEventDistributorControl(LogHandler, false);
		distributor = distributorControl.getDistributor();
		addedParentHandlers = false;
	}
	
	/**
	 * Returns the parent of this logger.
	 *
	 * <p>This logger uses the parent to get the log level, if no one has been set to
	 * this logger manually and to get the handlers of its parents to log messages.
	 *
	 * @return the parent of this logger
	 */
	public function getParent(Void):HierarchicalLogger {
		return parent;
	}
	
	/**
	 * Sets the parent of this logger.
	 *
	 * <p>The parent is used to obtain needed configuration like handlers and levels.
	 *
	 * @param parent the parent of this logger
	 */
	public function setParent(parent:HierarchicalLogger):Void {
		this.parent = parent;
	}
	
	/**
	 * Returns the name of this logger.
	 *
	 * <p>The name is a fully qualified name and the different parts are separated by
	 * periods. The name could for example be {@code "org.as2lib.core.BasicClass"}.
	 *
	 * @return the name of this logger
	 */
	public function getName(Void):String {
		return name;
	}
	
	/**
	 * Sets the name of this logger.
	 *
	 * <p>The name must exist of the path as well as the actual identifier. That means
	 * it must be fully qualified.
	 * 
	 * <p>The {@link LoggerHierarchy} prescribes that the different parts of the name
	 * must be separated by periods.
	 *
	 * @param name the name of this logger
	 */
	public function setName(name:String):Void {
		this.name = name;
	}
	
	/**
	 * Sets the log level.
	 *
	 * <p>The {@code level} determines which messages to log and which not.
	 *
	 * <p>The {@code level} is allowed to be set to {@code null} or {@code undefined}.
	 * If you do so the {@link #getLevel} method returns the level of the parent.
	 *
	 * @param level the new level to control the logging of messages
	 * @see #getLevel
	 */
	public function setLevel(level:LogLevel):Void {
		this.level = level;
	}
	
	/**
	 * Returns the log level of this logger.
	 *
	 * <p>If the level has not been set, that means is {@code undefined}, the level of
	 * the parent will be returned.
	 *
	 * <p>{@code null} or {@code undefined} will only be returned if this level is not
	 * defined and the parent's {@code getLevel} method returns {@code null} or
	 * {@code undefined}.
	 *
	 * @return the log level of this logger
	 */
	public function getLevel(Void):LogLevel {
		if (level === undefined) return getParent().getLevel();
		return level;
	}
	
	/**
	 * Adds the new {@code handler}.
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
	 * Removes all occerrences of the passed-in {@code handler}.
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
	 * Returns all handlers this logger broadcasts to when logging a message.
	 *
	 * <p>These handlers are the once directly added to this logger and the once of
	 * its parents.
	 *
	 * <p>The handlers of the parents are obtained via the parents
	 * {@code getAllHandlers} method which is supposed to also return the handlers of
	 * its parent and so on.
	 *
	 * <p>This method never returns {@code null} but an empty array if there are no
	 * handlers added to this logger nor to its parents.
	 *
	 * <p>Note that this method stores the parents handlers itself if it once obtained
	 * them. That is when you first log a message. It then always works with the
	 * stored handlers. That means that handlers added to its parents after the
	 * handlers have once been stored are not recognized.
	 *
	 * @return all added log handlers and the ones of the parents
	 */
	public function getAllHandlers(Void):Array {
		if (!addedParentHandlers) addParentHandlers();
		return distributorControl.getAllListeners();
	}
	
	/**
	 * Adds the parent handlers to the distributor.
	 */
	private function addParentHandlers(Void):Void {
		var parentHandlers:Array = getParent().getAllHandlers();
		if (parentHandlers) {
			distributorControl.addAllListeners(parentHandlers);
		}
		addedParentHandlers = true;
	}
	
	/**
	 * Checks whether this logger is enabled for the passed-in {@code level}.
	 *
	 * {@code false} will be returned if:
	 * <ul>
	 *   <li>This logger is not enabled for the passed-in {@code level}.</li>
	 *   <li>The passed-in {@code level} is {@code null} or {@code undefined}.</li>
	 * </ul>
	 *
	 * <p>Using this method as shown in the class documentation may improve performance
	 * depending on how long the log message construction takes.
	 *
	 * @param level the level to make the check upon
	 * @return {@code true} if this logger is enabled for the given level else
	 * {@code false}
	 * @see #log
	 */
	public function isEnabled(level:LogLevel):Boolean {
		if (!level) return false;
		return (getLevel().toNumber() >= level.toNumber());
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
		return (getLevel().toNumber() >= debugLevelAsNumber);
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
		return (getLevel().toNumber() >= infoLevelAsNumber);
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
		return (getLevel().toNumber() >= warningLevelAsNumber);
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
		return (getLevel().toNumber() >= errorLevelAsNumber);
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
		return (getLevel().toNumber() >= fatalLevelAsNumber);
	}
	
	/**
	 * Logs the passed-in {@code message} at the given {@code level}.
	 *
	 * <p>The {@code message} is only logged when this logger is enabled for the
	 * passed-in {@code level}.
	 *
	 * <p>The {@code message} is broadcasted to all log handlers of this logger and to
	 * the ones of its parents or more specifically to the ones returned by the 
	 * parent's {@code getAllHandlers} method, that normally also returns the handlers
	 * of its parents and so on.
	 *
	 * <p>Note that the handlers of the parents are resloved only once, when the first
	 * message is logged. They are stored in this logger to reference them faster.
	 *
	 * @param message the message object to log
	 * @param level the specific level at which the {@code message} shall be logged
	 * @see #isEnabled
	 */
	public function log(message, level:LogLevel):Void {
		if (isEnabled(level)) {
			if (!addedParentHandlers) addParentHandlers();
			distributor.write(new LogMessage(message, level, name));
		}
	}
	
	/**
	 * Logs the passed-in {@code message} at debug level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code DEBUG} or
	 * a level above.
	 *
	 * <p>The {@code message} is broadcasted to all log handlers of this logger and to
	 * the ones of its parents or more specifically to the ones returned by the 
	 * parent's {@code getAllHandlers} method, that normally also returns the handlers
	 * of its parents and so on.
	 *
	 * <p>Note that the handlers of the parents are resloved only once, when the first
	 * message is logged. They are stored in this logger to reference them faster.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 */
	public function debug(message):Void {
		log(message, debugLevel);
	}
	
	/**
	 * Logs the passed-in {@code message} at info level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code INFO} or
	 * a level above.
	 *
	 * <p>The {@code message} is broadcasted to all log handlers of this logger and to
	 * the ones of its parents or more specifically to the ones returned by the 
	 * parent's {@code getAllHandlers} method, that normally also returns the handlers
	 * of its parents and so on.
	 *
	 * <p>Note that the handlers of the parents are resloved only once, when the first
	 * message is logged. They are stored in this logger to reference them faster.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 */
	public function info(message):Void {
		log(message, infoLevel);
	}
	
	/**
	 * Logs the passed-in {@code message} at warning level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code WARNING}
	 * or a level above.
	 *
	 * <p>The {@code message} is broadcasted to all log handlers of this logger and to
	 * the ones of its parents or more specifically to the ones returned by the 
	 * parent's {@code getAllHandlers} method, that normally also returns the handlers
	 * of its parents and so on.
	 *
	 * <p>Note that the handlers of the parents are resloved only once, when the first
	 * message is logged. They are stored in this logger to reference them faster.
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 */
	public function warning(message):Void {
		log(message, warningLevel);
	}
	
	/**
	 * Logs the passed-in {@code message} at error level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code ERROR} or
	 * a level above.
	 *
	 * <p>The {@code message} is broadcasted to all log handlers of this logger and to
	 * the ones of its parents or more specifically to the ones returned by the 
	 * parent's {@code getAllHandlers} method, that normally also returns the handlers
	 * of its parents and so on.
	 *
	 * <p>Note that the handlers of the parents are resloved only once, when the first
	 * message is logged. They are stored in this logger to reference them faster.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 */
	public function error(message):Void {
		log(message, errorLevel);
	}
	
	/**
	 * Logs the passed-in {@code message} at fatal level.
	 *
	 * <p>The {@code message} is only logged when the level is set to {@code FATAL} or
	 * a level above.
	 *
	 * <p>The {@code message} is broadcasted to all log handlers of this logger and to
	 * the ones of its parents or more specifically to the ones returned by the 
	 * parent's {@code getAllHandlers} method, that normally also returns the handlers
	 * of its parents and so on.
	 *
	 * <p>Note that the handlers of the parents are resloved only once, when the first
	 * message is logged. They are stored in this logger to reference them faster.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 */
	public function fatal(message):Void {
		log(message, fatalLevel);
	}
	
}