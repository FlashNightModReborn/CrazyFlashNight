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

import org.as2lib.core.BasicInterface;

/**
 * {@code Logger} declares all methods needed to log messages in a well defined
 * and performant way.
 * 
 * <p>The basic methods to log messages are {@link #debug}, {@link #info},
 * {@link #warning} and {@link #fatal}.
 *
 * <p>The first thing to note is that you can log messages at different levels.
 * These levels are {@code DEBUG}, {@code INFO}, {@code WARNING}, {@code ERROR}
 * and {@code FATAL}. Depending on what level has been set only messages at a
 * given level are logged. The levels are organized in a hierarchical manner. That
 * means if you set the log level to {@code ALL} every messages is logged. If you
 * set it to {@code ERROR} only messages at {@code ERROR} and {@code FATAL} level
 * are logged and so on.
 *
 * <p>To do not waste unnecessary performance in constructing log messages that are
 * not logged you can use the {@link #isDebugEnabled}, {@link #isInfoEnabled},
 * {@link #isWarningEnabled}, {@link #isErrorEnabled} and {@link #isFatalEnabled}
 * methods.
 *
 * <p>Note that the message does in neither case have to be a string. That means
 * you can pass-in messages and let the actual handler or logger decide how to
 * produce a string representation of the message. That is in most cases done by
 * using the {@code toString} method of the specific message. You can use this
 * method to do not lose performance in cases where the message is not logged.
 *
 * <p>The basic workflow of using loggers is as follows:
 * <code>
 *   // MyLogger is an implementation of this interface
 *   var logger:Logger = new MyLogger();
 *   if (logger.isInfoEnabled()) {
 *       logger.info("This is an information message.");
 *   }
 * </code>
 *
 * <p>Note that we are in the above example not setting a log level. This depends
 * on what configuration methods the implementation of this interface offers.
 * 
 * <p>Note also that depending on the concrete implementation and the message it
 * may be faster to do not call any of the {@code is*Enabled} methods.
 *
 * @author Simon Wacker
 */
interface org.as2lib.env.log.Logger extends BasicInterface {
	
	/**
	 * Checks if this logger is enabled for debug level log messages.
	 * 
	 * <p>Using this method as shown in the class documentation may improve performance
	 * depending on how long the log message construction takes.
	 *
	 * @return {@code true} if debug messagess are logged
	 * @see org.as2lib.env.log.level.AbstractLogLevel#DEBUG
	 * @see #debug
	 */
	public function isDebugEnabled(Void):Boolean;
	
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
	public function isInfoEnabled(Void):Boolean;
	
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
	public function isWarningEnabled(Void):Boolean;
	
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
	public function isErrorEnabled(Void):Boolean;
	
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
	public function isFatalEnabled(Void):Boolean;
	
	/**
	 * Logs the passed-in {@code message} at debug level.
	 *
	 * <p>The message is only logged when the level is set to {@code DEBUG} or a level
	 * above.
	 *
	 * @param message the message object to log
	 * @see #isDebugEnabled
	 */
	public function debug(message):Void;
	
	/**
	 * Logs the passed-in {@code message} at info level.
	 *
	 * <p>The message is only logged when the level is set to {@code INFO} or a level
	 * above.
	 *
	 * @param message the message object to log
	 * @see #isInfoEnabled
	 */
	public function info(message):Void;
	
	/**
	 * Logs the passed-in {@code message} at warning level.
	 *
	 * <p>The message is only logged when the level is set to {@code WARNING} or a
	 * level above.
	 *
	 * @param message the message object to log
	 * @see #isWarningEnabled
	 */
	public function warning(message):Void;
	
	/**
	 * Logs the passed-in {@code message} at error level.
	 *
	 * <p>The message is only logged when the level is set to {@code ERROR} or a level
	 * above.
	 *
	 * @param message the message object to log
	 * @see #isErrorEnabled
	 */
	public function error(message):Void;
	
	/**
	 * Logs the passed-in {@code message} at fatal level.
	 *
	 * <p>The message is only logged when the level is set to {@code FATAL} or a level
	 * above.
	 *
	 * @param message the message object to log
	 * @see #isFatalEnabled
	 */
	public function fatal(message):Void;
	
}