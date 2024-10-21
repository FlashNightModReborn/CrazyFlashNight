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
import org.as2lib.env.log.LoggerRepository;
import org.as2lib.env.log.logger.AscbLogger;

/**
 * {@code AscbLoggerRepository} returns loggers of type {@link AscbLogger}.
 *
 * <p>Configuring your global registry, like {@code LogManager} with this repository,
 * enables you to work externally with the As2lib Logging API, which allows you to
 * change between different other Logging APIs, but internally with the ASCB Logging
 * API. You also configure the ASCB Logging API as if you would use it directly.
 * 
 * <p>Already received loggers are cached by name. Thus there exists only one logger
 * instance per logger name.
 *
 * @author Simon Wacker
 * @see org.as2lib.env.log.logger.AscbLogger
 */
class org.as2lib.env.log.repository.AscbLoggerRepository extends BasicClass implements LoggerRepository {
	
	/** Already received loggers. */
	private var loggers:Object;
	
	/**
	 * Constructs a new {@code AscbLoggerRepository} instance.
	 */
	public function AscbLoggerRepository(Void) {
		loggers = new Object();
	}
	
	/**
	 * Returns a pre-configured logger for the passed-in {@code name}.
	 *
	 * <p>A new logger is created for names to which no logger has been assigned yet.
	 * The new logger is configured with the {@code name}. The logger is then cached by
	 * name and returned for usage.
	 *
	 * @param name the name of the logger to return
	 * @return the logger corresponding to the passed-in {@code name}
	 */
	public function getLogger(name:String):Logger {
		if (loggers[name]) return loggers[name];
		var logger:Logger = new AscbLogger(name);
		loggers[name] = logger;
		return logger;
	}
	
}