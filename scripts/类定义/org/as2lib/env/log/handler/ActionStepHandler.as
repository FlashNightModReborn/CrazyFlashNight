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

import org.as2lib.util.Stringifier;
import org.as2lib.env.log.LogHandler;
import org.as2lib.env.log.LogMessage;
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.level.AbstractLogLevel;
import org.as2lib.env.log.handler.AbstractLogHandler;

import org.actionstep.ASDebugger;

/**
 * {@code ActionStepHandler} uses the {@code org.actionstep.ASDebugger.trace} method to log
 * messages.
 * 
 * @author Simon Wacker
 * @see org.as2lib.env.log.logger.ActionStepLogger
 * @see <a href="http://actionstep.sourceforge.net">ActionStep</a>
 */
class org.as2lib.env.log.handler.ActionStepHandler extends AbstractLogHandler implements LogHandler {
	
	/** Holds a action step handler instance. */
	private static var actionStepHandler:ActionStepHandler;
	
	/**
	 * Returns an instance of this class.
	 *
	 * <p>This method always returns the same instance.
	 *
	 * <p>The {@code messageStringifier} argument is only recognized on first
	 * invocation of this method.
	 * 
	 * @param messageStringifier (optional) the log message stringifier to be used by
	 * the returned handler
	 * @return a action step handler
	 */
	public static function getInstance(messageStringifier:Stringifier):ActionStepHandler {
		if (!actionStepHandler) actionStepHandler = new ActionStepHandler(messageStringifier);
		return actionStepHandler;
	}
	
	/**	
	 * Constructs a new {@code ActionStepHandler} instance.
	 *
	 * <p>You can use one and the same instance for multiple loggers. So think about
	 * using the handler returned by the static {@link #getInstance} method. Using this
	 * instance prevents the instantiation of unnecessary trace handlers and saves
	 * storage.
	 * 
	 * @param messageStringifier (optional) the log message stringifier to use
	 */
	public function ActionStepHandler(messageStringifier:Stringifier) {
		super (messageStringifier);
	}
	
	/**
	 * Writes the passed-in {@code message} using the {@code org.actionstep.ASDebugger.trace}
	 * method.
	 *
	 * <p>The string representation of the {@code message} to log is obtained via
	 * the {@code convertMessage} method.
	 * 
	 * @param message the message to log
	 */
	public function write(message:LogMessage):Void {
		ASDebugger.trace(convertMessage(message), convertLevel(message.getLevel()));
	}
	
	/**
	 * Converts the As2lib {@code LogLevel} into a ActionStep level number.
	 * 
	 * @param level the As2lib log level to convert
	 * @return the equivalent ActionStep level
	 */
	private function convertLevel(level:LogLevel):Number {
		switch (level) {
			case AbstractLogLevel.DEBUG:
				return ASDebugger.DEBUG;
			case AbstractLogLevel.INFO:
				return ASDebugger.INFO;
			case AbstractLogLevel.WARNING:
				return ASDebugger.WARNING;
			case AbstractLogLevel.ERROR:
				return ASDebugger.ERROR;
			case AbstractLogLevel.FATAL:
				return ASDebugger.FATAL;
			default:
				return null;
		}
	}
	
}