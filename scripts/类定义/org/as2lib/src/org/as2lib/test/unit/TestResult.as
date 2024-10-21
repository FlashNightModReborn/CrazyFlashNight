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
import org.as2lib.data.holder.array.TypedArray;
import org.as2lib.data.type.Time;

/**
 * {@code TestResult} represents the infromations that got collected during the
 * execution of a related {@code Test}.
 * 
 * <p>A {@code Test} should not contain the informations about its execution.
 * {@code TestResult} represents the pool of all informations collected during
 * the execution of the {@code Test} by its {@code TestRunner}.
 * 
 * <p>Every {@code TestResult} depends to the state of the execution of the
 * related {@code Test}. Different informations changed during the execution.
 * 
 * @author Martin Heidegger
 * @version 1.0
 * @see org.as2lib.test.unit.TestRunner
 * @see org.as2lib.test.unit.Test
 */
interface org.as2lib.test.unit.TestResult extends BasicInterface {
	
	/**
	 * Returns the percentage ({@code 0}-{@code 100}) of the execution.
	 * 
	 * @return percentage of execution
	 */
	public function getPercentage(Void):Number;
	
	/**
	 * Returns {@code true} if the {@code TestCase} has been finished.
	 * 
	 * @return {@code true} if the {@code TestCase} has been finished.
	 */
	public function hasFinished(Void):Boolean;
	
	/**
	 * Returns {@code true} if the {@code TestCase} has been started.
	 * 
	 * @return {@code true} if the {@code TestCase} has been started
	 */
	public function hasStarted(Void):Boolean;
	
	/**
	 * Returns the name of the {@code TestResult}.
	 * 
	 * @return name of the {@code TestResult}
	 */
	public function getName(Void):String;
	
	/**
	 * Returns the total operation time for all methods executed for the
	 * related {@code Test}.
	 * 
	 * @return total operation time of the {@code Test}
	 */
	public function getOperationTime(Void):Time;
	
	/**
	 * Returns {@code true} if the errors occured during the execution of the
	 * related {@code Test}.
	 * 
	 * @return {@code true} if the errors occured during the execution of the
	 * 		   related {@code Test}.
	 */
	public function hasErrors(Void):Boolean;
	
	/**
	 * Returns all {@code TestResult}s for the {@code Test}s contained
	 * within the related {@code Test}.
	 * 
	 * <p>Since its possible to add more than one {@code Test} to a {@code TestSuite}
	 * its necessary to get the {@code TestResult}s to all added {@code Test}s.
	 *
	 * <p>It flattens out all {@code TestResults}, this means it concats all
	 * {@code getTestResults} of every added {@code Test}. 
	 * 
	 * @return all {@code TestResult}s to all contained {@code Test}s
	 */
	public function getTestResults(Void):TypedArray;
	
	/**
	 * Returns all {@code TestCaseResult}s for the {@code TestCase}s contained
	 * within the related {@code Test}.
	 * 
	 * <p>Since its possible to add more than one {@code Test} to a {@code TestSuite}
	 * its necessary to get the {@code TestResult}s to all added {@code Test}s.
	 * 
	 * <p>{@code TestCase} represents the lowest level of {@code Test} therefor
	 * its important to get all added {@code TestCaseResults} seperatly.
	 *
	 * <p>It flattens out all {@code TestResults}, this means it concats all
	 * {@code getTestCaseResults} of every added {@code Test}. 
	 * 
	 * @return all {@code TestResult}s to all contained {@code Test}s
	 */
	public function getTestCaseResults(Void):TypedArray;
}