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

/**
 * {@code Configuration} is intended for general configuration at startup, that
 * is the same for Flash, Flex and MTASC.
 * 
 * <p>{@code Configuration} is a central part of a configuration system. It should
 * contain only the not-plattform-specific configuration. If you want to use this
 * configuration take a look at {@link org.as2lib.app.conf.FlashoutApplication},
 * {@link org.as2lib.app.conf.MtascApplication} and {@link org.as2lib.app.conf.FlashApplication}.
 * 
 * <p>{@code Configuration} sould be overwritten. Other classes reference to it but
 * itself contains no code. If you want to overwrite it you can create the same class
 * in your application directory with your configuration code.
 * 
 * <p>Example:
 * <code>
 *   import com.domain.app.*;
 *   
 *   class main.Configuration {
 *       public static var app:MyApplication;
 *       
 *       public static function init(Void);Void {
 *           app = new MySuperApplication();
 *           app.start();
 *       }
 *   }
 * </code>
 * 
 * <p>It is important to have a static {@code init} method that does all the needed
 * configuration. This method must, as in the above example, be declared in a class
 * that has the same namespace ({@code main}) and name ({@code Configuration} as
 * this example class. Besides that you can declare any further method in the class
 * or extend any class and implement any interface you like.
 * 
 * <p>If you now want to use this class MTASC you must pay attention to the class
 * paths of the compiler to get it to run!
 * <br>The Macromedia Flash MX 2004 Compiler takes the topmost as most important so
 * you would have to set your classpaths like this:
 * <pre>
 *   D:\Projects\MyApplication\src\
 *   D:\Libraries\as2lib\main\src\
 * </pre>
 * <br>The MTASC compiler (http://www.mtasc.org) works the opposite way. The tompost
 * classpath is less important. So you would have to set your classpaths like this:
 * <pre>-cp "D:/Libraries/as2lib/main/src" -cp "D:/Projects/MyApplication/src/"</pre>
 * <br>If you work with the eclipse plugin (http://asdt.sf.net) that uses mtasc you
 * have to set the classpaths in your project directory in the same way (you can add
 * external folders by using alias folders).
 * 
 * @author Martin Heidegger
 * @version 1.0
 * @see org.as2lib.app.conf.FlashApplication
 * @see org.as2lib.app.conf.MtascApplication
 * @see org.as2lib.app.conf.FlashoutApplication
 */
class main.Configuration {
	
	/**
	 * This method is used by the {@code main} or {@code init} method of the classes
	 * {@link org.as2lib.app.conf.FlashoutApplication}, {@link org.as2lib.app.conf.FlashApplication}
	 * and {@link org.as2lib.app.conf.MtascApplication}.	 */
	public static function init(Void):Void {
	}
	
}