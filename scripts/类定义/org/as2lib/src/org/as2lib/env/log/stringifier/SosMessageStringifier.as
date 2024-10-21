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
import org.as2lib.env.log.LogMessage;
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.level.AbstractLogLevel;
import org.as2lib.env.log.stringifier.PatternLogMessageStringifier;
import org.as2lib.env.log.handler.SosHandler;

/**
 * {@code SosMessageStringifier} stringifies {@link LogMessage} instances into SOS
 * compatible log output.
 * 
 * @author Christoph Atteneder
 * @see <a href="http://sos.powerflasher.com">SOS - SocketOutputServer</a>
 */
class org.as2lib.env.log.stringifier.SosMessageStringifier extends PatternLogMessageStringifier implements Stringifier {
	
	/**
	 * Constructs a new {@code SosMessageStringifier} instance.
	 */
	public function SosMessageStringifier(Void) {
		super(false, true);
	}
	
	/**
	 * Stringifies {@link LogMessage} instances.
	 * 
	 * @param target the {code LogMessage} instance to stringify
	 * @return the string representation of the given {@code target}
	 */
	public function execute(target):String {
		var message:LogMessage = target;
		var level:LogLevel = message.getLevel();
		var levelKey:String;
		switch(level){
			case AbstractLogLevel.DEBUG:
				levelKey = SosHandler.DEBUG_KEY;
				break;
			case AbstractLogLevel.ERROR:
				levelKey = SosHandler.ERROR_KEY;
				break;
			case AbstractLogLevel.INFO:
				levelKey = SosHandler.INFO_KEY;
				break;
			case AbstractLogLevel.WARNING:
				levelKey = SosHandler.WARNING_KEY;
				break;		
			case AbstractLogLevel.FATAL:
				levelKey = SosHandler.FATAL_KEY;
				break;
			default :
				levelKey = SosHandler.DEBUG_KEY; 
		};
		return "<showMessage key='" + levelKey + "'>" + super.execute(target) + "</showMessage>\n";
	}
	
}