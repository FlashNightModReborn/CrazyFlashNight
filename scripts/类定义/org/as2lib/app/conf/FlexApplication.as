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

import main.Flex;
import main.Configuration;

/**
 * {@code FlexApplication} is the default access point for Flex applications.
 * 
 * <p>Use this class to configure your application with Macromedia Flex. It inits
 * your flex configuration in {@link main.Flex} and your configuration for all 
 * environments in {@link main.Configuration}.
 * 
 * <p>You must simply init your application something like this:
 * <code>
 *   <mx:Application xmlns:mx="http://www.macromedia.com/2003/mxml" initialize="initApp();">
 *     <mx:Script>
 *       <![CDATA[
 *         import org.as2lib.app.conf.FlexApplication;
 *         public function initApp(Void):Void {
 *           FlexApplication.init();
 *         }
 *       ]]>
 *     </mx:Script>
 *   </mx:Application>
 * </code>
 * 
 * @author Simon Wacker
 * @version 1.0 */
class org.as2lib.app.conf.FlexApplication {
	
	/**
	 * Executes the configuration for the Flex environment in {@link main.Flex} and the 
	 * configuration for all environments in {@link main.Configuration}. These are the
	 * {@link Flex#init} and {@link Configuration#init} methods.
	 * 
	 * <p>This method takes any amount of arguments and forwards them to both methods
	 * {@code main.Flex.init} and {@code main.Configuration.init}.
	 * 
	 * @param .. any amount of arguments of any type	 */
	public static function init():Void {
		Flex.init.apply(Flex, arguments);
		Configuration.init.apply(Configuration, arguments);
	}
	
}