﻿/*
 * Copyright the original author or authors.
 * 
 * Licensed under the Mozilla Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.mozilla.org/MPL/2.0/
 *
 * This file may be redistributed under the terms of the GNU General Public License,
 * version 3.0 (GPLv3), or any later version.
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.util.Stringifier;
import org.as2lib.env.log.LogHandler;
import org.as2lib.env.log.LogMessage;
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.level.AbstractLogLevel;
import org.as2lib.env.log.handler.AbstractLogHandler;

/**
 * {@code ZtorLog4fHandler} uses the {@code Log4f.log} method of the ZTOR Log4f
 * project to log messages.
 * 
 * @author Simon Wacker
 * @see org.as2lib.env.log.logger.ZtorLog4fLogger
 * @see <a href="http://www.ztor.com/index.php4?ln=&g=comp&d=log4f">ZTOR Log4f</a>
 */
class org.as2lib.env.log.handler.ZtorLog4fHandler extends AbstractLogHandler implements LogHandler {
	
	/** Holds a log4f handler instance. */
	private static var ztorLog4fHandler:ZtorLog4fHandler;
	
	/**
	 * Returns an instance of this class.
	 *
	 * <p>This method always returns the same instance.
	 *
	 * <p>The {@code messageStringifier} argument is only recognized on first
	 * invocation of this method.
	 * 
	 * @param messageStringifier (optional) the log message stringifier to be used by
	 * the returned handler
	 * @return a ztor log4f handler
	 */
	public static function getInstance(messageStringifier:Stringifier):ZtorLog4fHandler {
		if (!ztorLog4fHandler) ztorLog4fHandler = new ZtorLog4fHandler(messageStringifier);
		return ztorLog4fHandler;
	}
	
	/**	
	 * Constructs a new {@code ZtorLog4fHandler} instance.
	 *
	 * <p>You can use one and the same instance for multiple loggers. So think about
	 * using the handler returned by the static {@link #getInstance} method. Using this
	 * instance prevents the instantiation of unnecessary trace handlers and saves
	 * storage.
	 * 
	 * @param messageStringifier (optional) the log message stringifier to use
	 */
	public function ZtorLog4fHandler(messageStringifier:Stringifier) {
		super (messageStringifier);
	}
	
	/**
	 * Writes the passed-in {@code message} using the {@code Log4f.log} method.
	 *
	 * <p>The string representation of the {@code message} to log is obtained via
	 * the {@code convertMessage} method and passed as header to the {@code Log4f.log}
	 * method.
	 * 
	 * @param message the message to log
	 */
	public function write(message:LogMessage):Void {
		Log4f.log(convertLevel(message.getLevel()), convertMessage(message), "");
	}
	
	/**
	 * Converts the As2lib {@code LogLevel} into a ZTOR Log4f level number.
	 * 
	 * <p>The default level is {@code Log4f.LOG4F}. It is used if no match is found.
	 * 
	 * @param level the As2lib log level to convert
	 * @return the equivalent ZTOR Log4f level
	 */
	private function convertLevel(level:LogLevel):Number {
		switch (level) {
			case AbstractLogLevel.DEBUG:
				return Log4f.DEBUG;
			case AbstractLogLevel.INFO:
				return Log4f.INFO;
			case AbstractLogLevel.WARNING:
				return Log4f.WARN;
			case AbstractLogLevel.ERROR:
				return Log4f.ERROR;
			case AbstractLogLevel.FATAL:
				return Log4f.FATAL;
			default:
				return Log4f.LOG4F;
		}
	}
	
}