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
import org.as2lib.test.unit.TestRunner;

/**
 * {@code Test} is the definition for any test in a unit-testing context.
 * 
 * <p>To start a {@code Test} you simple have to execute {@code run}. It logs all
 * output by default to a {@code Logger}.
 *
 * @author Martin Heidegger
 * @version 2.0
 * @see TestRunner
 */
interface org.as2lib.test.unit.Test extends BasicInterface {
		
	/**
	 * Runs the test.
	 * 
	 * @return {@code TestRunner} that executes this test
	 */
	public function run(Void):TestRunner;
	
	/**
	 * Returns the {@code TestRunner} that executes this {@code Test}.
	 * 
	 * <p>Every {@code Test} is ment to have a {@code TestRunner} that knows
	 * how the informations of the {@code Test} have to be used to execute to
	 * evaluate the result.
	 * 
	 * @return {@code TestRunner} that executes this test
	 */
	public function getTestRunner(Void):TestRunner;
}