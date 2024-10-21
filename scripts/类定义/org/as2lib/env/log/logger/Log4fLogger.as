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

import org.log4f.logging.Level;
import org.log4f.logging.IFilter;
import org.log4f.logging.IPublisher;
import org.log4f.logging.util.List;

/**
 * {@code Log4fLogger} acts as a wrapper for a {@code org.log4f.logging.logger}
 * instance of the Log4F Framework from Peter Armstrong.
 * 
 * <p>Log4F (http://sourceforge.net/projects/log4f), by Peter Armstrong, is a
 * Log4j-style logging framework for Flex applications. It is based on Ralf Siegel's
 * public domain logging framework found at http://code.audiofarm.de/Logger and adds
 * useful Flex-specific enhancements including a debug console, instance inspector
 * etc.
 * 
 * <p>Configure the Log4F Framework as normally and just use this class in your
 * application to log messages. This enables you to switch between almost every
 * available Logging API without having to change the logs in your application but
 * just the underlying configuration on startup.
 * 
 * @author Simon Wacker
 * @see <a href="http://sourceforge.net/projects/log4f">Log4F</a>
 */
class org.as2lib.env.log.logger.Log4fLogger extends BasicClass implements Logger {
	
	/**
	 * Indicates that all messages shall be logged. This level is equivalent to the
	 * Log4F {@code ALL} level.
	 */
	public static var ALL:Level = Level.ALL;
	
	/**
	 * Indicates that all messages at debug and higher levels shall be logged. This
	 * level is equivalent to the Log4F {@code DEBUG} level.	 */
	public static var DEBUG:Level = Level.DEBUG;
	
	/**
	 * Indicates that all messages at info and higher levels shall be logged. This
	 * level is equivalent to the Log4F {@code INFO} level.
	 */
	public static var INFO:Level = Level.INFO;
	
	/**
	 * Indicates that all messages at warning and higher levels shall be logged. This
	 * level is equivalent to the Log4F {@code WARN} level.
	 */
	public static var WARNING:Level = Level.WARN;
	
	/**
	 * Indicates that all messages at error and higher levels shall be logged. This
	 * level is equivalent to the Log4F {@code ERROR} level.
	 */
	public static var ERROR:Level = Level.ERROR;
	
	/**
	 * Indicates that all messages at fatal and higher levels shall be logged. This
	 * level is equivalent to the Log4F {@code FATAL} level.
	 */
	public static var FATAL:Level = Level.FATAL;
	
	/**
	 * Indicates that no messages shall be logged; logging shall be turned off. This
	 * level is equivalent to the Log4F {@code OFF} level.
	 */
	public static var NONE:Level = Level.OFF;
	
	/** The {@code Logger} instance of Log4F every task is delegated to. */
	private var logger:org.log4f.logging.Logger;
	
	/** Debug level. */
	private var debugLevel:Level;
	
	/** Info level. */
	private var infoLevel:Level;
	
	/** Warning level. */
	private var warningLevel:Level;
	
	/** Error level. */
	private var errorLevel:Level;
	
	/** Fatal level. */
	private var fatalLevel:Level;
	
	/**
	 * Constructs a new {@code Log4fLogger} instance.
	 * 
	 * <p>Gets an Log4F {@code Logger} instance via the
	 * {@code org.log4f.logging.Logger.getLogger} method.
	 *
	 * @param name the name of this logger
	 */
	public function Log4fLogger(name:String) {
		this.logger = org.log4f.logging.Logger.getLogger(name);
		this.debugLevel = DEBUG;
		this.infoLevel = INFO;
		this.warningLevel = WARNING;
		this.errorLevel = ERROR;
		this.fatalLevel = FATAL;
	}
	
	/**
	 * Returns the name of this logger or {@code undefined} for anonymous loggers.
	 *
	 * @return the name of this logger
	 */
	public function getName(Void):String {
		return this.logger.getName();
	}
	
	/**
	 * Returns the parent of this logger.
	 * 
	 * <p>This method returns the nearest extant parent in the namespace. Thus if a
	 * logger is called "a.b.c.d", and a logger called "a.b" has been created but no
	 * logger "a.b.c" exists, then a call of {@code getParent} on the logger "a.b.c.d"
	 * will return the logger "a.b".
	 * 
	 * <p>The parent for the anonymous Logger is always the root (global) logger.
	 * 
	 * <p>The result will be {@code undefined} if it is called on the root (global)
	 * logger in the namespace.
	 * 
	 * @return the parent of this logger	 */
	public function getParent(Void):org.log4f.logging.Logger {
		return this.logger.getParent();
	}
	
	/**
	 * Returns an array with publishers associated with this logger.
	 * 
	 * @return an array with publishers that are associated with this logger	 */
	public function getPublishers(Void):List {
		return this.logger.getPublishers();
	}
	
	/**
	 * Adds a new publisher to this logger.
	 * 
	 * @param publisher the publisher to add
	 * @return {@code true} if the {@code publisher} was added successfully else
	 * {@code false}	 */
	public function addPublisher(publisher:IPublisher):Boolean {
		return this.logger.addPublisher(publisher);
	}
	
	/**
	 * Removes the given {@code publisher} from this logger.
	 * 
	 * @param publisher the publisher to remove
	 * @return {@code true} if the {@code publisher} was removed successfully else
	 * {@code false}	 */
	public function removePublisher(publisher:IPublisher):Boolean {
		return this.logger.removePublisher(publisher);
	}
	
	/**
	 * Returns the current filter for this logger.
	 * 
	 * @return this logger's current filter or {@code undefined}	 */
	public function getFilter(Void):IFilter {
		return this.logger.getFilter();
	}
	
	/**
	 * Sets a new filter for this logger.
	 * 
	 * @param filter the new filter to set	 */
	public function setFilter(filter:IFilter):Void {
		this.logger.setFilter(filter);
	}
	
	/**
	 * Returns the log level specified for this logger.
	 * 
	 * <p>The result may be {@code undefined}, which means that this logger's effective
	 * level will be inherited from its parent. 
	 * 
	 * @return this logger's level	 */
	public function getLevel(Void):Level {
		return this.logger.getLevel();
	}
	
	/**
	 * Sets the log level specifying which messages at which levels will be logged by
	 * this logger.
	 * 
	 * <p>Message levels lower than this value will be discarded. The level value
	 * {@link OFF} can be used to turn off logging.
	 * 
	 * <p>If the new level is {@code undefined}, it means that this node should inherit
	 * its level from its nearest ancestor with a specific (non-undefined) level value.
	 * 
	 * @param level the new level	 */
	public function setLevel(level:Level):Void {
		this.logger.setLevel(level);
	}
	
	/**
	 * Checks if this logger is enabled for debug level log messages.
	 *
	 * @return {@code true} if debug messages are logged
	 * @see #debug
	 */
	public function isDebugEnabled(Void):Boolean {
		return this.logger.isLoggable(this.debugLevel);
	}
	
	/**
	 * Checks if this logger is enabled for info level log messages.
	 *
	 * @return {@code true} if info messages are logged
	 * @see #info
	 */
	public function isInfoEnabled(Void):Boolean {
		return this.logger.isLoggable(this.infoLevel);
	}
	
	/**
	 * Checks if this logger is enabled for warning level log messages.
	 *
	 * @return {@code true} if warning messages are logged
	 * @see #warning
	 */
	public function isWarningEnabled(Void):Boolean {
		return this.logger.isLoggable(this.warningLevel);
	}
	
	/**
	 * Checks if this logger is enabled for error level log messages.
	 *
	 * @return {@code true} if error messages are logged
	 * @see #error
	 */
	public function isErrorEnabled(Void):Boolean {
		return this.logger.isLoggable(this.errorLevel);
	}
	
	/**
	 * Checks if this logger is enabled for fatal level log messages.
	 *
	 * @return {@code true} if fatal messages are logged
	 * @see #fatal
	 */
	public function isFatalEnabled(Void):Boolean {
		return this.logger.isLoggable(this.fatalLevel);
	}
	
	/**
	 * Logs the message object to wrapped Log4F {@code Logger} at debug level.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 */
	public function debug(message):Void {
		if (isDebugEnabled()) {
			this.logger.debug(message);
		}
	}
	
	/**
	 * Logs the message object to wrapped Log4F {@code Logger} at info level.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 */
	public function info(message):Void {
		if (isInfoEnabled()) {
			this.logger.info(message);
		}
	}
	
	/**
	 * Logs the message object to wrapped Log4F {@code Logger} at warning level.
	 * 
	 * <p>The warning level is equivalent to the warn level of Log4F
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 */
	public function warning(message):Void {
		if (isWarningEnabled()) {
			this.logger.warn(message);
		}
	}
	
	/**
	 * Logs the message object to wrapped Log4F {@code Logger} at error level.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 */
	public function error(message):Void {
		if (isErrorEnabled()) {
			this.logger.error(message);
		}
	}
	
	/**
	 * Logs the message object to wrapped Log4F {@code Logger} at fatal level.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 */
	public function fatal(message):Void {
		if (isFatalEnabled()) {
			this.logger.fatal(message);
		}
	}
	
}