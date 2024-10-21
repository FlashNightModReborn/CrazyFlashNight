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

import main.Flash;
import main.Configuration;

/**
 * Default access point for a application in Flash.
 * <p>Use this class for starting up your application with the Macromedia Flash compiler.
 * It will start your flash configuration in {@link main.Flash} and your configuration for all 
 * environments in {@link main.Configuration}.
 * 
 * <p>You have simply to add following code in the first frame action:
 * <code>
 *   org.as2lib.app.conf.FlashApplication.init();
 * </code>
 * 
 * @author Martin Heidegger
 * @version 1.0 */
class org.as2lib.app.conf.FlashApplication {
	
	/**
	 * Executes the configuration for the flash environment in {@link main.Flash} and the 
	 * configuration for all environments in {@link main.Configuration}. These are the
	 * {@link Flash#init} and {@link Configuration#init} methods.
	 * 
	 * <p>This method takes any amount of arguments and forwards them to both methods
	 * {@code main.Flash.init} and {@code main.Configuration.init}.
	 * 
	 * @param .. any amount of arguments of any type	 */
	public static function init():Void {
		Flash.init.apply(Flash, arguments);
		Configuration.init.apply(Configuration, arguments);
	}
	
}