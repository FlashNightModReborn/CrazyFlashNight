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

import org.as2lib.core.BasicInterface;
import org.as2lib.test.speed.TestResult;

/**
 * {@code Test} is the core interface for standardized performance tests.
 *
 * @author Simon Wacker
 * @author Martin Heidegger
 */
interface org.as2lib.test.speed.Test extends BasicInterface {
	
	/**
	 * Runs this performance test.
	 */
	public function run(Void):Void;
	
	/**
	 * Returns the test result of this test.
	 * 
	 * @return this test's result	 */
	public function getResult(layout:Number):TestResult;
	
}