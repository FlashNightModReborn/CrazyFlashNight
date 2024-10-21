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
import org.as2lib.env.log.handler.FlashoutHandler;
import org.as2lib.env.log.repository.LoggerHierarchy;
import org.as2lib.env.log.LogManager;

/**
 * {@code Mtasc} is intended for configuration of applications compiled with MTASC.
 * 
 * <p>It allows you to define all MTASC specific configurations similar to the
 * configuration in {@link main.Configuration}.
 * 
 * <p>The current code contains an example that matches usual cases. If you have
 * additional configuration you have to overwrite (not extend!) this class in your
 * directory. All that must stay to be compatible is the {@link #init} method.
 * 
 * @see main.Configuration
 * @author Martin Heidegger
 * @version 1.0
 */
class main.Mtasc {
	
	/**
	 * Initializes and starts the MTASC configuration.
	 * 
	 * @param container the root movie-clip that is passed by MTASC to the main method
	 */
	public static function init(container:MovieClip):Void {
		// sets up logging
		setUpLogging();
	}
	
	/**
	 * Sets up MTASC specific logging. This configures the As2lib Logging API to log
	 * to Flashout.
	 */
	private static function setUpLogging(Void):Void {
		// creates a new root logger
		var root:RootLogger = new RootLogger(AbstractLogLevel.ALL);
		// TODO: Create a Mtasc - only working logger ...
		root.addHandler(new FlashoutHandler());
		// sets the logger hierarchy as repository
		LogManager.setLoggerRepository(new LoggerHierarchy(root)); 
	}
	
}