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
import org.as2lib.data.holder.Stack;

/**
 * {@code StackStringifier} stringifies instances of type {@link Stack}.
 *
 * @author Simon Wacker
 */
class org.as2lib.data.holder.stack.StackStringifier extends BasicClass implements Stringifier {
	
	/**
	 * Returns the string representation of the passed-in {@code target} stack.
	 *
	 * <p>{@code target} must be an instance of type {@code Stack}.
	 * 
	 * <p>The string representation is constructed as follows:
	 * <pre>
	 *   [lastlyAddedValue, penultimatelyAddedValue, ...]
	 * </pre>
	 * 
	 * @param target the target stack to stringify
	 * @return the string representation of the passed-in {@code target} stack
	 */
	public function execute(target):String {
		var stack:Stack = target;
		var result:String = "[";
		var array:Array = stack.toArray();
		for (var i:Number = 0; i < array.length; i++) {
			result += array[i].toString();
			if (i < array.length-1) {
				result += ", ";
			}
		}
		result += "]";
		return result;
	}
	
}