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
import org.as2lib.test.speed.TestResult;

/**
 * {@code AbstractTestResult} provides implementations of methods needed by
 * implementations of the {@link TestResult} interface.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.AbstractTestResult extends BasicClass {
	
	/**
	 * Constructs a new {@code AbstractTestResult} instance.	 */
	private function AbstractTestResult(Void) {
	}
	
	/**
	 * Returns this instance with correct type. This is needed for proper compile-time
	 * checks.
	 * 
	 * @return this instance with its correct type	 */
	private function getThis(Void):TestResult {
		return TestResult(this);
	}
	
	/**
	 * Returns the invocation time as percentage in relation to the passed-in
	 * {@code totalTime}.
	 * 
	 * @param totalTime the total time to calculate the percentage with
	 * @return the invocation time as percentage
	 */
	public function getTimePercentage(totalTime:Number):Number {
		return (Math.round((getThis().getTime() / totalTime) * 10000) / 100);
	}
	
}