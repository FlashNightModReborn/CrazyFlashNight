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

import LuminicBox.Log.Level;
import LuminicBox.Log.IPublisher;

/**
 * {@code LuminicBoxLogger} acts as a wrapper for a {@code Logger} instance of the
 * LuminicBox Logging API.
 * 
 * <p>Configure the LuminicBox Logging API as normally and just use this class in
 * your application to log messages or objects. This enables you to switch between
 * almost every available Logging API without having to change the logs in your
 * application but just the underlying configuration on startup.
 *
 * <p>All functionalities that the LuminicBox Logging API offers are delegated to
 * it. Other functionalities are performed by this class directly.
 * 
 * @author Simon Wacker
 * @author Christoph Atteneder
 * 
 * @see org.as2lib.env.log.handler.LuminicBoxHandler
 * @see <a href="http://www.luminicbox.com/dev/flash/log">LuminicBox Logging API</a>
 */
class org.as2lib.env.log.logger.LuminicBoxLogger extends BasicClass implements Logger {
	
	/** The Logger instance of LuminicBox every task is delegated to. */
	private var logger:LuminicBox.Log.Logger;
	
	/** The set level as number. */
	private var levelAsNumber:Number;
	
	/** Debug level as number. */
	private var debugLevelAsNumber:Number;
	
	/** Info level as number. */
	private var infoLevelAsNumber:Number;
	
	/** Warning level as number. */
	private var warningLevelAsNumber:Number;
	
	/** Error level as number. */
	private var errorLevelAsNumber:Number;
	
	/** Fatal level as number. */
	private var fatalLevelAsNumber:Number;
	
	/**
	 * Constructs a new {@code LuminicBoxLogger} instance.
	 *
	 * @param name (optional) the name of this logger
	 */
	public function LuminicBoxLogger(name:String) {
		this.logger = new LuminicBox.Log.Logger(name);
		this.levelAsNumber = getLevel().getValue();
		this.debugLevelAsNumber = Level.DEBUG.getValue();
		this.infoLevelAsNumber = Level.INFO.getValue();
		this.warningLevelAsNumber = Level.WARN.getValue();
		this.errorLevelAsNumber = Level.ERROR.getValue();
		this.fatalLevelAsNumber = Level.FATAL.getValue();
	}
	
	/**
	 * Returns the name of this logger.
	 *
	 * @return the name of this logger
	 */
	public function getName(Void):String {
		return this.logger.getId();
	}
	
	/**
	 * Sets the new level.
	 *
	 * <p>The level determines which messages are logged and which are not.
	 *
	 * @param newLevel the new level
	 */
	public function setLevel(newLevel:Level):Void {
		this.logger.setLevel(newLevel);
		this.levelAsNumber = newLevel.getValue();
	}
	
	/**
	 * Returns the set or default level.
	 *
	 * @return the set or default level
	 */
	public function getLevel(Void):Level {
		return this.logger.getLevel();
	}
	
	/**
	 * Adds the {@code publisher} to the wrapped LuminicBox {@code Logger}.
	 *
	 * @param publisher the publisher to add
	 */
	public function addPublisher(publisher:IPublisher):Void {
		logger.addPublisher(publisher);
	}
	
	/** 
	 * Removes the {@code publisher} from the wrapped LuminicBox {@code Logger}.
	 *
	 * @param publisher the publisher to remove
	 */
	public function removePublisher(publisher:IPublisher):Void {
		logger.removePublisher(publisher);
	}
	
	/**
	 * Returns the added publishers of type {@code IPublisher}.
	 *
	 * @return the added publishers
	 * @see #addPublisher
	 */
	public function getPublishers(Void):Object {
		return logger.getPublishers();
	}
	
	/**
	 * Checks if this logger is enabled for debug level log messages.
	 *
	 * @return {@code true} if debug messages are logged
	 * @see #debug
	 */
	public function isDebugEnabled(Void):Boolean {
		return (levelAsNumber <= debugLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for info level log messages.
	 *
	 * @return {@code true} if info messages are logged
	 * @see #info
	 */
	public function isInfoEnabled(Void):Boolean {
		return (levelAsNumber <= infoLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for warning level log messages.
	 *
	 * @return {@code true} if warning messages are logged
	 * @see #warning
	 */
	public function isWarningEnabled(Void):Boolean {
		return (levelAsNumber <= warningLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for error level log messages.
	 *
	 * @return {@code true} if error messages are logged
	 * @see #error
	 */
	public function isErrorEnabled(Void):Boolean {
		return (levelAsNumber <= errorLevelAsNumber);
	}
	
	/**
	 * Checks if this logger is enabled for fatal level log messages.
	 *
	 * @return {@code true} if fatal messages are logged
	 * @see #fatal
	 */
	public function isFatalEnabled(Void):Boolean {
		return (levelAsNumber <= fatalLevelAsNumber);
	}
	
	/**
	 * Logs the passed-in {@code message} to LuminicBox {@code Logger} at debug level.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 */
	public function debug(message):Void {
		logger.debug(message);
	}
	
	/**
	 * Logs the passed-in {@code message} to LuminicBox {@code Logger} at info level.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 */
	public function info(message):Void {
		logger.info(message);
	}
	
	/**
	 * Logs the passed-in {@code message} to LuminicBox {@code Logger} at warning
	 * level.
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 */
	public function warning(message):Void {
		logger.warn(message);
	}
	
	/**
	 * Logs the passed-in {@code message} to LuminicBox {@code Logger} at error level.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 */
	public function error(message):Void {
		logger.error(message);
	}
	
	/**
	 * Logs the passed-in {@code message} to LuminicBox {@code Logger} at fatal level.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 */
	public function fatal(message):Void {
		logger.fatal(message);
	}
	
}