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

import org.as2lib.core.BasicInterface;
import org.as2lib.test.mock.Behavior;
import org.as2lib.test.mock.MockControlState;

/**
 * {@code MockControlStateFactory} creates and returns configured mock control
 * states.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.test.mock.MockControlStateFactory extends BasicInterface {
	
	/**
	 * Returns a mock control state instance that is configured with the passed-in
	 * {@code behavior}.
	 *
	 * @param behavior to be used by the returned mock control state
	 * @return a configured mock control state
	 */
	public function getMockControlState(behavior:Behavior):MockControlState;
	
}