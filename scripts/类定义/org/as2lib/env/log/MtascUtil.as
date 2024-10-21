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
import org.as2lib.env.overload.Overload;
import org.as2lib.env.log.Logger;
import org.as2lib.env.log.LogManager;

/**
 * {@code MtascUtil} offers support for MTASCs extraordinary trace functionality that
 * does not only allow for multiple arguments but also passes information like the
 * class name, the file name and even the line number.
 * 
 * <p>Usage:
 * <pre>
 *   mtasc -trace org.as2lib.env.log.MtascUtil.log Test.as (...)
 * </pre>
 * 
 * @author Simon Wacker
 * @see <a href="http://www.mtasc.org/#trace">MTASC - Tracing facilities</a> */
class org.as2lib.env.log.MtascUtil extends BasicClass {
	
	/** Debug level output. */
	public static var DEBUG:Number = 2;
	
	/** Info level output. */
	public static var INFO:Number = 3;
	
	/** Warning level output. */
	public static var WARNING:Number = 4;
	
	/** Error level output. */
	public static var ERROR:Number = 5;
	
	/** Fatal level output. */
	public static var FATAL:Number = 6;
	
	/**
	 * @overload #logByDefaultLevel
	 * @overload #logByLevel	 */
	public static function log():Void {
		var o:Overload = new Overload(eval("th" + "is"));
		o.addHandler([Object, String, String, Number], logByDefaultLevel);
		o.addHandler([Object, Number, String, String, Number], logByLevel);
		o.forward(arguments);
	}
	
	/**
	 * Logs the {@code message} at default level {@link #INFO}.
	 * 
	 * @param message the message to log
	 * @param className the name of the class that logs the {@code message}
	 * @param fileName the name of the file that declares the class
	 * @param lineNumber the line number at which the logging call stands
	 * @see #logByLevel	 */
	public static function logByDefaultLevel(message:Object, className:String, fileName:String, lineNumber:Number):Void {
		logByLevel(message, null, className, fileName, lineNumber);
	}
	
	/**
	 * Logs the {@code message} at the specified {@code level}.
	 * 
	 * <p>If this level is none of the declared ones, {@code #INFO} is used. This is
	 * also the case if {@code level} is {@code null} or {@code undefined}.
	 * 
	 * <p>The {@code message} is logged using a logger returned by the
	 * {@link LogManager#getLogger} method passing-in the given {@code className}. The
	 * extra information is passed to the specific log methods as further arguments.
	 * 
	 * @param message the message to log
	 * @param className the name of the class that logs the {@code message}
	 * @param fileName the name of the file that declares the class
	 * @param lineNumber the line number at which the logging call stands	 */
	public static function logByLevel(message:Object, level:Number, className:String, fileName:String, lineNumber:Number):Void {
		var logger:Logger = LogManager.getLogger(className);
		switch (level) {
			case DEBUG:
				logger.debug(message, className, fileName, lineNumber);
				break;
			case WARNING:
				logger.warning(message, className, fileName, lineNumber);
				break;
			case ERROR:
				logger.error(message, className, fileName, lineNumber);
				break;
			case FATAL:
				logger.fatal(message, className, fileName, lineNumber);
				break;
			default:
				logger.info(message, className, fileName, lineNumber);
				break;
		}
	}
	
	/**
	 * Private constructor.	 */
	private function MtascUtil(Void) {
	}
	
}