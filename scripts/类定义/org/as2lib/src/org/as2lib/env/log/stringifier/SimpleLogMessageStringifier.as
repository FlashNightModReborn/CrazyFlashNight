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
import org.as2lib.util.Stringifier;
import org.as2lib.env.log.LogMessage;

/**
 * {@code SimpleLogMessageStringifier} stringifies {@link LogMessage} instances in the
 * simplest and fastest way possible.
 * 
 * @author Simon Wacker
 * @author Martin Heidegger */
class org.as2lib.env.log.stringifier.SimpleLogMessageStringifier extends BasicClass implements Stringifier {
	
	/**
	 * Returns the string representation of the passed-in {@code target} that must be
	 * an instance of type {@link LogMessage}.
	 * 
	 * <p>The returned string representation is obtained via the {@code toString}
	 * method of the original message returned by the passed-in {@code target}'s
	 * {@code getMessage} method.
	 * 
	 * @param the {@code LogMessage} to stringify
	 * @return the string representation of the passed-in {@code target}	 */
	public function execute(target):String {
		var message:LogMessage = target;
		return message.getMessage().toString();
	}
	
}