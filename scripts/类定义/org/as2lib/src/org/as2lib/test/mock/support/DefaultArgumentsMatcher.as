/**
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
import org.as2lib.test.mock.ArgumentsMatcher;

/**
 * {@code DefaultArgumentsMatcher} matches the expected arguments agains the actual
 * arguments. If an argument is itself an array the elements of this array are
 * matched, not the array as object itself.
 * 
 * @author Simon Wacker
 */
class org.as2lib.test.mock.support.DefaultArgumentsMatcher extends BasicClass implements ArgumentsMatcher {
	
	/**
	 * Constructs a new {@code DefaultArgumentsMatcher} instance.
	 */
	public function DefaultArgumentsMatcher(Void) {
	}
	
	/**
	 * Matches the passed-in {@code expectedArguments} against the
	 * {@code actualArguments}. Inner arrays are stepped through recursively.
	 *
	 * @param expectedArguments the expected arguments
	 * @param actualArguments the actual arguments
	 * @return {@code true} if the passed-in arguments match else {@code false}
	 */
	public function matchArguments(expectedArguments:Array, actualArguments:Array):Boolean {
		if (expectedArguments.length != actualArguments.length) return false;
		for (var i:Number = 0; i < expectedArguments.length; i++) {
			if (expectedArguments[i] !== actualArguments[i]) {
				if (expectedArguments[i] instanceof Array) {
					if (!matchArguments(expectedArguments[i], actualArguments[i])) {
						return false;
					}
				} else {
					if (expectedArguments[i].prototype == actualArguments[i].prototype) {
						return ( expectedArguments[i].valueOf() == actualArguments[i].valueOf());
					} else {
						return false;
					}
				}
			}
		}
		return true;
	}
	
}