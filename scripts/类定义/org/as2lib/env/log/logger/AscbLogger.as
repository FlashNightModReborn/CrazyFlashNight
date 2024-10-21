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

import ascb.util.logging.Level;

/**
 * {@code AscbLogger} acts as a wrapper for a {@code ascb.util.logging.Logger}
 * instance of the ASCB Logging API.
 * 
 * <p>Configure the ASCB Logging API as normally and just use this class in your
 * application to log messages. This enables you to switch between almost every
 * available Logging API without having to change the logs in your application but
 * just the underlying configuration on startup.
 *
 * <p>All functionalities that the ASCB Logging API offers are delegated to it.
 * Other functionalities are performed by this class directly.
 *
 * <p>The level functionalitiy of loggers is not supported by the ASCB Logging API.
 * This is thus provided by this class and not delegated. The ASCB Logging API
 * provides only level functionalitiy for handlers. If you want only the handler
 * level functionality to be enabled just do not set a level on this logger.
 * 
 * @author Simon Wacker
 * @see org.as2lib.env.log.handler.AscbHandler
 * @see <a href="http://www.person13.com/ascblibrary">ASCB Library</a>
 */
class org.as2lib.env.log.logger.AscbLogger extends AbstractLogger implements Logger {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractLogger;
	
	/** The {@code Logger} instance of ASCB every task is delegated to. */
	private var logger:ascb.util.logging.Logger;
	
	/** The set level. */
	private var level:LogLevel;
	
	/** The set level as number. */
	private var levelAsNumber:Number;
	
	/**
	 * Constructs a new {@code AscbLogger} instance.
	 *
	 * <p>Gets an ASCB {@code Logger} instance via the
	 * {code ascb.util.logging.Logger.getLogger} method.
	 *
	 * @param name the name of this logger
	 */
	public function AscbLogger(name:String) {
		this.logger = ascb.util.logging.Logger.getLogger(name);
		setLevel(null);
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
	 * Sets the new level.
	 *
	 * <p>If the passed-in {@code newLevel} is {@code null} or {@code undefined} the
	 * default level {@code ALL} is used instead.
	 *
	 * <p>The level determines which messages are logged and which are not.
	 *
	 * @param newLevel the new level
	 */
	public function setLevel(newLevel:LogLevel):Void {
		if (newLevel) {
			this.level = newLevel;
		} else {
			this.level = ALL;
		}
		this.levelAsNumber = this.level.toNumber();
	}
	
	/**
	 * Returns the set or default level.
	 *
	 * @return the set or default level
	 */
	public function getLevel(Void):LogLevel {
		return this.level;
	}
	
	/**
	 * Checks if this logger is enabled for debug level log messages.
	 *
	 * @return {@code true} if debug messages are logged
	 * @see #debug
	 */
	public function isDebugEnabled(Void):Boolean {
		return (levelAsNumber >= debugLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for info level log messages.
	 *
	 * @return {@code true} if info messages are logged
	 * @see #info
	 */
	public function isInfoEnabled(Void):Boolean {
		return (levelAsNumber >= infoLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for warning level log messages.
	 *
	 * @return {@code true} if warning messages are logged
	 * @see #warning
	 */
	public function isWarningEnabled(Void):Boolean {
		return (levelAsNumber >= warningLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for error level log messages.
	 *
	 * @return {@code true} if error messages are logged
	 * @see #error
	 */
	public function isErrorEnabled(Void):Boolean {
		return (levelAsNumber >= errorLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for fatal level log messages.
	 *
	 * @return {@code true} if fatal messages are logged
	 * @see #fatal
	 */
	public function isFatalEnabled(Void):Boolean {
		return (levelAsNumber >= fatalLevelAsNumber);
	}
	
	/**
	 * Logs the message object to ASCB {@code Logger} at debug level.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 */
	public function debug(message):Void {
		if (isDebugEnabled()) {
			logger.debug(message);
		}
	}
	
	/**
	 * Logs the message object to ASCB {@code Logger} at info level.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 */
	public function info(message):Void {
		if (isInfoEnabled()) {
			logger.info(message);
		}
	}
	
	/**
	 * Logs the message object to ASCB {@code Logger} at warning level.
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 */
	public function warning(message):Void {
		if (isWarningEnabled()) {
			logger.warning(message);
		}
	}
	
	/**
	 * Logs the message object to ASCB {@code Logger} at severe level.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 */
	public function error(message):Void {
		if (isErrorEnabled()) {
			logger.severe(message);
		}
	}
	
	/**
	 * Logs the message object to ASCB {@code Logger} at all level.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 */
	public function fatal(message):Void {
		if (isFatalEnabled()) {
			logger.log(Level.ALL, message);
		}
	}
	
}