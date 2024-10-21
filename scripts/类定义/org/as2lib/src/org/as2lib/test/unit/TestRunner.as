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

import org.as2lib.app.exec.Process;
import org.as2lib.test.unit.TestResult;
import org.as2lib.test.unit.TestCaseResult;
import org.as2lib.test.unit.TestCaseMethodInfo;

/**
 * {@code TestRunner} is the definition for a process that executes a {@code Test}.
 * 
 * <p>It is the internal mechianism for the execution of a {@code Test}. Any
 * {@code Test} has to refer to its {@code TestRunner}.
 * 
 * <p>Since {@code TestRunner} extends {@link Process} it is possible to add
 * all listeners for {@code Process} to a {@code TestRunner}.
 * 
 * <p>Example for adding a Listener to the execution of a {@link TestCase}:
 * <code>
 *   var testCase:TestCase = new MyTestCase();
 *   var testRunner:TestRunner = testCase.getTestRunner();
 *   
 *   // add a listener to log the events of the test
 *   testRunner.addListener(new LoggerTestListener());
 *   
 *   // start the execution of the testcase
 *   testCase.run();
 * </code>
 * 
 * <p>{@code TestRunner} is part of the unit testing MVC construct. {@code TestRunner}
 * acts as controller, {@link TestResult} acts as model and all listeners act
 * as view. {@code TestResult} can be accessed by {@code #getTestResult}.
 * 
 * <p>The seperation of {@code Test} & {@code TestRunner} is to save the developer
 * of a {@code TestCase} that contains all its execution details (can lead to
 * many reserved fields that might be used by the unit-test developer. In this way
 * only two fields ((@link Test#getTestRunner} & {@link Test#run}) are reserved.
 * 
 * @author Martin Heidegger
 * @version 2.0
 */
interface org.as2lib.test.unit.TestRunner extends Process {
	
	/** 
	 * Returns the {@code TestResult} to the {@code Test} executed by the {@code TestRunner}.
	 * 
	 * <p>The returned {@code TestResult} may not be complete. This is the case
	 * if the test has not been executed or has not finished yet.
	 * 
	 * @return {@link TestResult} for the {@code Test} that contains all informations
	 */
	public function getTestResult(Void):TestResult;
	
	/**
	 * Returns the current executing {@code TestCaseResult}.
	 * 
	 * <p>It is necessary to get the {@code TestCaseResult} for the {@code TestCase}
	 * that just gets executed because there can be more than one {@code TestCase}
	 * available within a {@code TestResult}. 
	 * 
	 * @return {@code TestResult} to the current executing {@code TestCase}
	 */
	public function getCurrentTestCase(Void):TestCaseResult;
	
	/**
	 * Returns the current executing {@code TestCaseMethodInfo}.
	 * 
	 * <p>It is necessary to get the {@code TestCaseMethodInfo} for the method
	 * that just gets executed because there can be more than one methods available
	 * within a {@code TestCaseResult}.
	 * 
	 * @return informations about the current executing method
	 * @see #getCurrentTestCase
	 */
	public function getCurrentTestCaseMethodInfo(Void):TestCaseMethodInfo;
}