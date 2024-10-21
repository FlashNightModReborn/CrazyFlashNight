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

import org.as2lib.env.log.logger.RootLogger;
import org.as2lib.env.log.level.AbstractLogLevel;
import org.as2lib.env.log.handler.TraceHandler;
import org.as2lib.env.log.repository.LoggerHierarchy;
import org.as2lib.env.log.LogManager;

/**
 * {@code Flash} is intended for configuration of applications compiled with Flash.
 * 
 * <p>It allows you to define all Flash specific configurations similar to the
 * configuration in {@link main.Configuration}.
 * 
 * <p>The current code uses a common configuration. If you have additional configuration
 * you have to overwrite (not extend!) this class in your application directory. The
 * only method that must be declared to be compatible is {@link #init}.
 * 
 * @author Martin Heidegger
 * @version 1.0
 * @see main.Configuration
 */
class main.Flash {
	
	/**
	 * Initializes and starts the Flash configuration.
	 * 
	 * @see org.as2lib.app.conf.FlashApplication
	 */
	public static function init(Void):Void {
		// inits of logging setup
		setUpLogging();
	}
	
	/**
	 * Sets up common logging in the Flash environment that uses {@code trace}.
	 */
	private static function setUpLogging(Void):Void {
		// traces log messages
		var root:RootLogger = new RootLogger(AbstractLogLevel.ALL);
		root.addHandler(new TraceHandler());
		// sets the logger hierarchy as repository
		LogManager.setLoggerRepository(new LoggerHierarchy(root)); 
	}
	
}