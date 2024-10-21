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
import org.as2lib.data.holder.List;

/**
 * {@code ListStringifier} is the default stringifier used to stringify {@link List}
 * instances.
 *
 * @author Christoph Atteneder
 * @author Simon Wacker
 */
class org.as2lib.data.holder.list.ListStringifier extends BasicClass implements Stringifier {
	
	/**
	 * Stringifies passed-in {@code target} that must be an instance of type
	 * {link List}.
	 * 
	 * <p>The string representation is constructed as follows:
	 * <pre>
	 *   [firstlyAddedValue, secondlyAddedValue, ...]
	 * </pre>
	 * 
	 * @param target the list target to stringify
	 * @return the string representation of the passed-in {@code target}
	 */
	public function execute(target):String {
		var list:List = target;
		var result:String = "[";
		var values:Array = list.toArray();
		for (var i:Number = 0; i < values.length; i++) {
			if (i > 0) {
				result += ", ";
			}
			result += values[i].toString();
		}
		result += "]";
		return result;
	}
	
}