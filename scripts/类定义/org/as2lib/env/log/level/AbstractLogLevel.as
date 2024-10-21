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
import org.as2lib.env.except.IllegalArgumentException;

/**
 * {@code AbstractLogLevel} acts as a basic access point for the pre-defined levels
 * {@link #ALL}, {@link #DEBUG}, {@link #INFO}, {@link #WARNING}, {@link #ERROR},
 * {@link #FATAL} and {@link #NONE}.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.log.level.AbstractLogLevel extends BasicClass implements LogLevel {
	
	/** All log messages get logged. */
	public static var ALL:LogLevel = new AbstractLogLevel(60, "ALL");
	
	/** All log messages that are at a higher log level than debug get logged. */
	public static var DEBUG:LogLevel = new AbstractLogLevel(50, "DEBUG");
	
	/** All log messages that are at a higher log level than info get logged. */
	public static var INFO:LogLevel = new AbstractLogLevel(40, "INFO");
	
	/** All log messages that are at a higher log level than warning get logged. */
	public static var WARNING:LogLevel = new AbstractLogLevel(30, "WARNING");
	
	/** All log messages that are at a higher log level than error get logged. */
	public static var ERROR:LogLevel = new AbstractLogLevel(20, "ERROR");
	
	/** All log messages that are at a higher log level than fatal get logged. */
	public static var FATAL:LogLevel = new AbstractLogLevel(10, "FATAL");
	
	/** No log messages get logged. */
	public static var NONE:LogLevel = new AbstractLogLevel(0, "NONE");
	
	/**
	 * Returns the log level for the given {@code name}.
	 * 
	 * <p>If the given {@code name} is not registered to any logger, {@link INFO} is
	 * returned.
	 * 
	 * @param name the name of the log level to return
	 * @return the log level for the given {@code name}
	 */
	public static function forName(name:String):LogLevel {
		switch (name) {
			case "ALL":
				return ALL;
			case "DEBUG":
				return DEBUG;
			case "INFO":
				return INFO;
			case "WARNING":
				return WARNING;
			case "ERROR":
				return ERROR;
			case "FATAL":
				return FATAL;
			case "NONE":
				return NONE;
			default:
				return INFO;
		}
	}
	
	/** Stores the level in form of a number. */
	private var level:Number;
	
	/** The name of the level. */
	private var name:String;
	
	/**
	 * Constructs a new {@code AbstractLogLevel} instance.
	 *
	 * @param level the level represented by a number
	 * @param name the name of the level
	 * @throws IllegalArgumentException if passed-in {@code level} is {@code null} or
	 * {@code undefined}
	 */
	private function AbstractLogLevel(level:Number, name:String) {
		if (level == null) throw new IllegalArgumentException("Level is not allowed to be null or undefined.", this, arguments);
		this.level = level;
		this.name = name;
	}
	
	/**
	 * Compares the number representation of this level with the one of the passed-in
	 * {@code level} using the is greater or equal operator.
	 *
	 * <p>{@code true} will be returned if:
	 * <ul>
	 *   <li>This level is greater or equal than the passed-in {@code level}.</li>
	 *   <li>The passed-in {@code level} is {@code null} or {@code undefined}.</li>
	 * </ul>
	 *
	 * @param level the level to compare this level with
	 * @return {@code true} if this level is greater or equal than the passed-in
	 * {@code level} else {@code false}
	 */
	public function isGreaterOrEqual(level:LogLevel):Boolean {
		return (this.level >= level.toNumber());
	}
	
	/**
	 * Returns the number representation of this level.
	 *
	 * <p>The return value is never {@code null} or {@code undefined}.
	 *
	 * @return the number representation of this level
	 */
	public function toNumber(Void):Number {
		return level;
	}
	
	/**
	 * Returns the string representation of this level.
	 *
	 * @return the string representation of this level
	 */
	public function toString():String {
		return name;
	}
	
}