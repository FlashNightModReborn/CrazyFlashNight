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
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.level.AbstractLogLevel;

/**
 * {@code AbstractLogger} offers support for simple logger tasks.
 *
 * <p>Classes that extend this class are expected to / must implement the
 * {@link Logger} interface.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.log.logger.AbstractLogger extends BasicClass {
	
	/** All log messages get logged. */
	public static var ALL:LogLevel = AbstractLogLevel.ALL;
	
	/** All log messages that are at a lower log level than debug get logged. */
	public static var DEBUG:LogLevel = AbstractLogLevel.DEBUG;
	
	/** All log messages that are at a lower log level than info get logged. */
	public static var INFO:LogLevel = AbstractLogLevel.INFO;
	
	/** All log messages that are at a lower log level than warning get logged. */
	public static var WARNING:LogLevel = AbstractLogLevel.WARNING;
	
	/** All log messages that are at a lower log level than error get logged. */
	public static var ERROR:LogLevel = AbstractLogLevel.ERROR;
	
	/** All log messages that are at a lower log level than fatal get logged. */
	public static var FATAL:LogLevel = AbstractLogLevel.FATAL;
	
	/** No log messages get logged. */
	public static var NONE:LogLevel = AbstractLogLevel.NONE;
	
	/** The debug level. */
	private var debugLevel:LogLevel;
	
	/** The debug level as number. */
	private var debugLevelAsNumber:Number;
	
	/** The info level. */
	private var infoLevel:LogLevel;
	
	/** The info level as number. */
	private var infoLevelAsNumber:Number;
	
	/** The warning level. */
	private var warningLevel:LogLevel;
	
	/** The warning level as number. */
	private var warningLevelAsNumber:Number;
	
	/** The error level. */
	private var errorLevel:LogLevel;
	
	/** The error level as number. */
	private var errorLevelAsNumber:Number;
	
	/** The fatal level. */
	private var fatalLevel:LogLevel;
	
	/** The fatal level as number. */
	private var fatalLevelAsNumber:Number;
	
	/**
	 * Constructs a new {@code AbstractLogger} instance.
	 *
	 * <p>This class class cannot be instatiated directly. You must sub-class it first.
	 * 
	 * <p>This constructor initializes the level instance variables that can be used
	 * for fast access. Static access is relatively slow in comparison.
	 */
	private function AbstractLogger(Void) {
		debugLevel = DEBUG;
		debugLevelAsNumber = debugLevel.toNumber();
		infoLevel = INFO;
		infoLevelAsNumber = infoLevel.toNumber();
		warningLevel = WARNING;
		warningLevelAsNumber = warningLevel.toNumber();
		errorLevel = ERROR;
		errorLevelAsNumber = errorLevel.toNumber();
		fatalLevel = FATAL;
		fatalLevelAsNumber = fatalLevel.toNumber();
	}
	
}