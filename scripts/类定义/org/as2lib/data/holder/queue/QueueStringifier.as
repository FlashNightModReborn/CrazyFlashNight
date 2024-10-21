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
import org.as2lib.data.holder.Queue;

/**
 * {@code QueueStringifier} stringifies instances of type {@link Queue}.
 *
 * @author Simon Wacker
 */
class org.as2lib.data.holder.queue.QueueStringifier extends BasicClass implements Stringifier {
	
	/**
	 * Returns the string representation of the passed-in {@code target} queue.
	 *
	 * <p>{@code target} must be an instance of type {@code Queue}.
	 * 
	 * <p>The string representation is constructed as follows:
	 * <pre>
	 *   [firstlyAddedValue, secondlyAddedValue, ...]
	 * </pre>
	 *
	 * @param target the target queue to stringifiy
	 * @return the string representation of the passed-in {@code target} queue
	 */
	public function execute(target):String {
		var queue:Queue = target;
		var result:String = "[";
		var array:Array = queue.toArray();
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