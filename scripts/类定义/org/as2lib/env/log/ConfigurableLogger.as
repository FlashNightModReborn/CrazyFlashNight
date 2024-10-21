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
import org.as2lib.env.log.LogHandler;

/**
 * {@code ConfigurableLogger} declares methods needed to configure most loggers.
 * 
 * <p>This is first the method to set the level {@link #setLevel} and second the
 * methods to add, remove and access handlers {@link #addHandler},
 * {@link #removeHandler}, {@link #removeAllHandlers} and {@link #getAllHandlers}.
 *
 * <p>Log handlers are responsible for making the actual output. There are a few
 * pre-defined handlers that can be used to log to different output devices. Take
 * a look at the {@code org.as2lib.env.log.handler} package for these.
 *
 * <p>Loggers are normally configured only once.
 *
 * @author Simon Wacker
 */
interface org.as2lib.env.log.ConfigurableLogger extends Logger {
	
	/**
	 * Returns the set level.
	 *
	 * @return the set level
	 * @see #setLevel
	 */
	public function getLevel(Void):LogLevel;
	
	/**
	 * Sets the log level.
	 *
	 * <p>The level determines which output to make and and which to make not.
	 * 
	 * @param level the new level to control the output
	 * @see #getLevel
	 */
	public function setLevel(level:LogLevel):Void;
	
	/**
	 * Adds the passed-in log {@code handler}.
	 *
	 * <p>Log handlers are used to actually log the messages. They determine what
	 * information to log and to which output device.
	 *
	 * @param handler the new log handler to log messages
	 */
	public function addHandler(handler:LogHandler):Void;
	
	/**
	 * Returns all handlers that were added to this logger.
	 *
	 * @return all added log handlers
	 */
	public function getAllHandlers(Void):Array;
	
	/**
	 * Removes all occerrences of the passed-in {@code handler}.
	 *
	 * @param handler the log handler to remove
	 */
	public function removeHandler(handler:LogHandler):Void;
	
	/**
	 * Removes all added log handlers.
	 */
	public function removeAllHandlers(Void):Void;
	
}