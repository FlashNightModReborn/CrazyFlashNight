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

/**
 * {@code TestResult} holds the result of a test's execution.
 * 
 * @author Simon Wacker */
interface org.as2lib.test.speed.TestResult extends BasicInterface {
	
	/**
	 * Returns the name of the test.
	 * 
	 * @return the test's name	 */
	public function getName(Void):String;
	
	/**
	 * Returns the total invocation time in milliseconds.
	 * 
	 * @return the total invocation time in milliseconds
	 */
	public function getTime(Void):Number;
	
	/**
	 * Returns the invocation time as percentage in relation to the passed-in
	 * {@code totalTime}.
	 * 
	 * @param totalTime the total time to calculate the percentage with
	 * @return the invocation time as percentage	 */
	public function getTimePercentage(totalTime:Number):Number;
	
}