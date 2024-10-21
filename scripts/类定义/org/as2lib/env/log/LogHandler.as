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

import org.as2lib.core.BasicInterface;
import org.as2lib.env.log.LogMessage;

/**
 * {@code LogHandler} is used to actually log messages.
 * 
 * <p>You need different handlers for different output targets. Output targets can
 * be everything, Flash's Output Panel, any type of file, a database, a custom
 * output console and so on.
 *
 * <p>The As2lib supports a hand full of different output formats. Take a look at
 * the {@code org.as2lib.env.log.handler} package to see which are supported.
 *
 * <p>A logger does not have to support the feature of adding custom handlers. It
 * is not prescribed by the {@code Logger} interface so it depends on specific
 * implementations. Mostly 'speed' loggers do not use this approach because it
 * slows the whole logging process a little bit down.
 *
 * @author Simon Wacker
 */
interface org.as2lib.env.log.LogHandler extends BasicInterface {
	
	/**
	 * Writes information obtained from the passed-in {@code message} as well as 
	 * additional information to the output target.
	 * 
	 * <p>It is not prescribed which information will be written. Hence it depends on
	 * the concrete handler.
	 *
	 * <p>Most handlers simply use the {@link LogMessage#toString} method to obtain
	 * the string representation to log.
	 *
	 * @param message the message containing the information to log
	 */
	public function write(message:LogMessage):Void;
	
}