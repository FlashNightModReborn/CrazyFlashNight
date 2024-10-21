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
import org.as2lib.data.holder.Map;

/**
 * {@code MapStringifier} stringifies instances of type {@link Map}.
 *
 * @author Simon Wacker
 */
class org.as2lib.data.holder.map.MapStringifier extends BasicClass implements Stringifier {
	
	/**
	 * Returns the string representation of the passed-in {@code target}.
	 *
	 * <p>The {@code target} must be an instance of type {@code Map}.
	 * 
	 * <p>The string representation is constructed as follows:
	 * <pre>
	 *   {myFirstKey=myFirstValue, mySecondKey=mySecondValue, ..}
	 * </pre>
	 *
	 * @param target the target map to stringify
	 * @return the string representation of the passed-in {@code target}
	 */
	public function execute(target):String {
		var map:Map = target;
		var result:String = "{";
		var values:Array = map.getValues();
		var keys:Array = map.getKeys();
		for (var i:Number = 0; i < keys.length; i++) {
			if (i > 0) {
				result += ", ";
			}
			result += keys[i].toString() + "=" + values[i].toString();
		}
		result += "}";
		return result;
	}
	
}