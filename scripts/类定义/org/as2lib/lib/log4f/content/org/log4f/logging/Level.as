/*
   Copyright 2004 Ralf Siegel and Peter Armstrong

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
import org.log4f.logging.errors.IllegalArgumentError;
import org.log4f.logging.errors.InvalidLevelError;

/**
 * The Level class defines a set of standard logging levels that can be used to
 * control logging output. 
 * The logging Level objects are ordered and are specified by ordered integers. 
 * Enabling logging at a given level also enables logging at all higher levels. 
 *
 * Clients should normally use the predefined Level constants such as
 * Level.DEBUG. 
 *
 * Note that the constants have been changed to use the log4j constants from
 * the Sun-style constants.  This is to enable us to use the same constants
 * as log4j on the server side...
 *
 * @author Ralf Siegel
 * @author Peter Armstrong
 */
class org.log4f.logging.Level
{
	/**
	 * The ALL has the lowest possible rank and is intended to turn on all
	 * logging.  Note that -2147483648 (-2^31) is used, not Number.MIN_VALUE,
	 * since this is the smallest int possible in Java, and Log4J uses int codes.
	 *
	 * Note that this constant is identical to the value used by Log4J.
	 * The code on the server side relies on this fact--DO NOT CHANGE THIS VALUE!
	 */
	public static var ALL:Level = new Level("ALL", -2147483648);
	
	/**
	 * The DEBUG Level designates fine-grained informational events that are
	 * most useful to debug an application.
	 *
	 * Note that this constant is identical to the value used by Log4J.
	 * The code on the server side relies on this fact--DO NOT CHANGE THIS VALUE!
	 */
	public static var DEBUG:Level = new Level("DEBUG", 10000);

	/**
	 * The INFO level designates informational messages that highlight the
	 * progress of the application at coarse-grained level.
	 *
	 * Note that this constant is identical to the value used by Log4J.
	 * The code on the server side relies on this fact--DO NOT CHANGE THIS VALUE!
	 */
 	public static var INFO:Level = new Level("INFO", 20000);
	
	/**
	 * The WARN level designates potentially harmful situations.
	 *
	 * Note that this constant is identical to the value used by Log4J.
	 * The code on the server side relies on this fact--DO NOT CHANGE THIS VALUE!
	 */
	public static var WARN:Level = new Level("WARN", 30000);
	
	/**
	 * The ERROR level designates error events that might still allow the
	 * application to continue running.
	 *
	 * Note that this constant is identical to the value used by Log4J.
	 * The code on the server side relies on this fact--DO NOT CHANGE THIS VALUE!
	 */
	public static var ERROR:Level = new Level("ERROR", 40000);
	
	/**
	 * The FATAL level designates very severe error events that will presumably
	 * lead the application to abort.
	 *
	 * Note that this constant is identical to the value used by Log4J.
	 * The code on the server side relies on this fact--DO NOT CHANGE THIS VALUE!
	 */
	public static var FATAL:Level = new Level("FATAL", 50000);
	
	/**
	 * The OFF has the highest possible rank and is intended to turn off
	 * logging.  Note that 2147483647 (2^31 - 1) is used, not Number.MAX_VALUE,
	 * since this is the largest int possible in Java, and Log4J uses int codes.
	 *
	 * Note that this constant is identical to the value used by Log4J.
	 * The code on the server side relies on this fact--DO NOT CHANGE THIS VALUE!
	 */
	public static var OFF:Level = new Level("OFF", 2147483647);
	
	private var name:String;
	private var value:Number;
	
	/**
	*	Create a named Level with a given integer value.
	*/
	private function Level(name:String, value:Number)
	{
		this.name = name;
		this.value = value;
	}
	
	/**
	*	Returns the level object for the given level string
	*/
	public static function forName(level:String):Level
	{
		if(level == undefined || level == null) {
			throw new IllegalArgumentError("'" + level + "' is not allowed.");
		}	
		if (!(Level[level] instanceof Level)) {
			throw new InvalidLevelError(level);
		}
		return Level[level];
	}
	
	/**
	*	Get the name of this level
	*
	*	@return The name as string.
	*/
	public function getName():String
	{
		return this.name;
	}
	
	/**
	*	Get the integer value for this level
	*
	*	@return The name as string.
	*/
	public function valueOf():Object
	{
		return this.value;
	}
	
	/**
	*	@see Object.toString()
	*/
	public function toString():String
	{
		return "Level '" + this.getName() + "'";
	}
}
