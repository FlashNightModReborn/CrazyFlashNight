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

import logging.IPublisher;
import logging.IFilter;
import logging.Level;
import logging.util.List;

/**
 * {@code AudiofarmLogger} acts as a wrapper for a {@code logging.Logger} instance
 * of the Logging Framework for ActionScript 2 (as2logger) from Ralf Siegel.
 * 
 * <p>Configure the as2logger API as normally and just use this class in your
 * application to log messages. This enables you to switch between almost every
 * available Logging API without having to change the logs in your application but
 * just the underlying configuration on startup.
 * 
 * @author Simon Wacker
 * @see <a href="http://code.audiofarm.de/Logger/">as2logger - Logging Framework for ActionScript 2</a>
 */
class org.as2lib.env.log.logger.AudiofarmLogger extends BasicClass implements Logger {
	
	/**
	 * Indicates that all messages shall be logged. This level is equivalent to the
	 * as2logger {@code ALL} level.
	 */
	public static var ALL:Level = Level.ALL;
	
	/**
	 * Indicates that all messages at debug and higher levels shall be logged. This
	 * level is equivalent to the as2logger {@code CONFIG} level.	 */
	public static var DEBUG:Level = Level.CONFIG;
	
	/**
	 * Indicates that all messages at info and higher levels shall be logged. This
	 * level is equivalent to the as2logger {@code INFO} level.
	 */
	public static var INFO:Level = Level.INFO;
	
	/**
	 * Indicates that all messages at warning and higher levels shall be logged. This
	 * level is equivalent to the as2logger {@code WARNING} level.
	 */
	public static var WARNING:Level = Level.WARNING;
	
	/**
	 * Indicates that all messages at error and higher levels shall be logged. This
	 * level is equivalent to the as2logger {@code SEVERE} level.
	 */
	public static var ERROR:Level = Level.SEVERE;
	
	/**
	 * Indicates that all messages at fatal and higher levels shall be logged. This
	 * level is equivalent to the as2logger {@code SEVERE} level.
	 */
	public static var FATAL:Level = Level.SEVERE;
	
	/**
	 * Indicates that no messages shall be logged; logging shall be turned off. This
	 * level is equivalent to the as2logger {@code OFF} level.
	 */
	public static var NONE:Level = Level.OFF;
	
	/** The {@code Logger} instance of as2logger every task is delegated to. */
	private var logger:logging.Logger;
	
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
	 * Constructs a new {@code AudiofarmLogger} instance.
	 * 
	 * <p>Gets an as2logger {@code Logger} instance via the
	 * {@code logging.Logger.getLogger} method.
	 *
	 * @param name the name of this logger
	 */
	public function AudiofarmLogger(name:String) {
		this.logger = logging.Logger.getLogger(name);
		this.debugLevel = DEBUG;
		this.infoLevel = INFO;
		this.warningLevel = WARNING;
		this.errorLevel = ERROR;
		this.fatalLevel = FATAL;
	}
	
	/**
	 * Returns the name of this logger.
	 *
	 * @return the name of this logger
	 */
	public function getName(Void):String {
		return this.logger.getName();
	}
	
	/**
	 * Returns the parent for this logger.
	 * 
	 * <p>This method returns the nearest extant parent in the namespace. Thus if a
	 * logger is called "a.b.c.d", and a logger called "a.b" has been created but no
	 * logger "a.b.c" exists, then a call of {@code getParent} on the logger "a.b.c.d"
	 * will return the logger "a.b".
	 * 
	 * <p>The parent for the anonymous logger is always the root (global) logger.
	 * 
	 * <p>The result will be {@code undefined} if it is called on the root (global) logger
	 * in the namespace.
	 * 
	 * @return the parent of this logger	 */
	public function getParent(Void):logging.Logger {
		return this.logger.getParent();
	}
	
	/**
	 * Returns a list with publishers associated with this logger.
	 * 
	 * @return a list with publishers that are associated with this logger	 */
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
	 * Returns the log level specified for this logger. The result may be undefined,
	 * which means that this logger's effective level will be inherited from its
	 * parent. 
	 * 
	 * @return this logger's level	 */
	public function getLevel(Void):Level {
		return this.logger.getLevel();
	}
	
	/**
	 * Set the log level specifying which messages at which levels will be logged by
	 * this logger.
	 * 
	 * <p>Message levels lower than this value will be discarded. The level
	 * value {@link OFF} can be used to turn off logging.
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
	 * @see AudiofarmLogger#DEBUG
	 */
	public function isDebugEnabled(Void):Boolean {
		return this.logger.isLoggable(this.debugLevel);
	}
	
	/**
	 * Checks if this logger is enabled for info level log messages.
	 *
	 * @return {@code true} if info messages are logged
	 * @see #info
	 * @see AudiofarmLogger#INFO
	 */
	public function isInfoEnabled(Void):Boolean {
		return this.logger.isLoggable(this.infoLevel);
	}
	
	/**
	 * Checks if this logger is enabled for warning level log messages.
	 *
	 * @return {@code true} if warning messages are logged
	 * @see #warning
	 * @see AudiofarmLogger#WARNING
	 */
	public function isWarningEnabled(Void):Boolean {
		return this.logger.isLoggable(this.warningLevel);
	}
	
	/**
	 * Checks if this logger is enabled for error level log messages.
	 *
	 * @return {@code true} if error messages are logged
	 * @see #error
	 * @see AudiofarmLogger#ERROR
	 */
	public function isErrorEnabled(Void):Boolean {
		return this.logger.isLoggable(this.errorLevel);
	}
	
	/**
	 * Checks if this logger is enabled for fatal level log messages.
	 *
	 * @return {@code true} if fatal messages are logged
	 * @see #fatal
	 * @see AudiofarmLogger#FATAL
	 */
	public function isFatalEnabled(Void):Boolean {
		return this.logger.isLoggable(this.fatalLevel);
	}
	
	/**
	 * Logs the message object to wrapped as2logger {@code Logger} at debug level.
	 * 
	 * <p>The debug level is equivalent to the fine level of as2logger.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 * @see AudiofarmLogger#DEBUG
	 */
	public function debug(message):Void {
		if (isDebugEnabled()) {
			this.logger.fine(message);
		}
	}
	
	/**
	 * Logs the message object to wrapped as2logger {@code Logger} at info level.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 * @see AudiofarmLogger#INFO
	 */
	public function info(message):Void {
		if (isInfoEnabled()) {
			this.logger.info(message);
		}
	}
	
	/**
	 * Logs the message object to wrapped as2logger {@code Logger} at warning level.
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 * @see AudiofarmLogger#WARNING
	 */
	public function warning(message):Void {
		if (isWarningEnabled()) {
			this.logger.warning(message);
		}
	}
	
	/**
	 * Logs the message object to wrapped as2logger {@code Logger} at error level.
	 * 
	 * <p>The error level is equivalent to the severe level of as2logger.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 * @see AudiofarmLogger#ERROR
	 */
	public function error(message):Void {
		if (isErrorEnabled()) {
			this.logger.severe(message);
		}
	}
	
	/**
	 * Logs the message object to wrapped as2logger {@code Logger} at fatal level.
	 * 
	 * <p>The fatal level is equivalent to the severe level of as2logger.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 * @see AudiofarmLogger#FATAL
	 */
	public function fatal(message):Void {
		if (isFatalEnabled()) {
			this.logger.severe(message);
		}
	}
	
}