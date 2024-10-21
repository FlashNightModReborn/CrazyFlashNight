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
 
import org.as2lib.data.holder.array.TypedArray;
import org.as2lib.app.exec.BatchProcess;
import org.as2lib.test.unit.Test;
import org.as2lib.test.unit.TestResult;
import org.as2lib.test.unit.TestRunner;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.test.unit.TestSuiteResult;
import org.as2lib.app.exec.Process;
import org.as2lib.test.unit.TestCaseResult;
import org.as2lib.test.unit.TestCaseMethodInfo;

/**
 * {@code TestSuite} is a composite implementation of {@link Test}.
 * 
 * <p>A {@code TestSuite} is a collection of {@code Test}s. A {@code TestSuite} 
 * does not contain any executable code but it may contain different {@code Test}s
 * that can be added with {@link #addTest}.
 * 
 * <p>In contrast to {@code TestCase} the {@code TestSuite} has no external
 * {@code TestRunner}. {@code TestSuite} is its own implementation of
 * {@code TestRunner}.
 * 
 * @author Martin Heidegger
 * @version 2.0
 * @see org.as2lib.test.unit.TestSuiteFactory
 */
class org.as2lib.test.unit.TestSuite extends BatchProcess implements Test, TestRunner {

	/** 
	 * Blocks the collection of 
	 * {@code org.as2lib.test.unit.TestSuiteFactory#collectAllTestCases}.
	 * 
	 * @return {@code true} to block the collection
	 */
	public static function blockCollecting(Void):Boolean {
		return true;
	}
	
	/** All test contained within the TestSuite. */
	private var tests:TypedArray;
	
	/** Name of the TestSuite. */
	private var name:String;
	
	/** Result for the execution of the TestSuite. */
	private var testResult:TestSuiteResult;

	/**
	 * Constructs a new {@code TestSuite}.
	 * 
	 * @param name name of the {@code TestSuite}
	 */
	public function TestSuite(name:String) {
		this.tests = new TypedArray(TestRunner);
		testResult = new TestSuiteResult(this);
		this.name = name;
	}
	
	/**
	 * Helper to validate if the added {@code Test} contains the current testsuite.
	 * 
	 * <p>Since its possible to add any {@code Test} to this suite it could be
	 * possible to add this {@code TestSuite} instance. That would result in a 
	 * endless recursion.
	 * 
	 * @param test test to be validated
	 * @throws IllegalArgumentException if the passed-in {@code Test} contains this
	 *         instance as child.
	 */
	private function checkRecursion(test:TestResult) {
		if (test === testResult) {
			throw new IllegalArgumentException(
				"The test "+test+" contains or is the current test",
				this, arguments);
		}
		var content:Array = test.getTestResults();
		for (var i=0; i<content.length; i++) {
			if (content[i] != test) {
				checkRecursion(content[i]);
			}
		}
	}
	
	/**
	 * Adds a process to the {@code TestSuite}.
	 * 
	 * <p>{@code TestSuite} does only allow {@code TestRunner} as sub processes.
	 * 
	 * <p>Overrides the implementation in {@link BatchProcess#addProcess}.
	 * 
	 * @param p {@code Process} to be added to the {@code TestSuite}
	 * @throws IllegalArgumentException if the passed-in {@code p} contains this
	 *         instance as child.
	 */
	public function addProcess(p:Process):Void {
		var eP:TestRunner = TestRunner(p);
		if (eP) {
			checkRecursion(eP.getTestResult());
			testResult.addTest(eP.getTestResult());
			tests.push(p);
			super.addProcess(p);
		} else {
			throw new IllegalArgumentException("Only Tests are allowed for processing", this, arguments);
		}
	}
	
	/**
	 * Adds a {@code Test} to the {@code TestSuite}.
	 * 
	 * @param test {@code Test} to be added
	 * @throws IllegalArgumentException if the passed-in {@code Test} contains this
	 *         instance as child.
	 */
	public function addTest(test:Test):Void {
		addProcess(test.getTestRunner());
	}
	
	/**
	 * Returns the name of the {@code TestSuite}.
	 * 
	 * @return name of the {@code TestSuite}.
	 */
	public function getName(Void):String {
		if(!name) {
			return "";	
		}
		return name;
	}
	
	/**
	 * Runs the {@code TestSuite}.
	 * 
	 * @return {@code TestRunner} that run this test
	 */
	public function run(Void):TestRunner {
		start();
		return this;
	}
	
	/**
	 * Returns the {@code TestRunner} that executes this {@code TestSuite}.
	 * 
	 * @return {@code TestRunner} that executes this {@code TestSuite}
	 */
	public function getTestRunner(Void):TestRunner {
		return this;
	}
	
	/**
	 * Returns all {@code Tests} contained within this {@code TestSuite}.
	 * 
	 * @return {@link TypedArray} that contains all {@code Test}s of this {@code TestSuite}.
	 */
	public function getTests(Void):TypedArray {
		return this.tests;
	}
	
	/**
	 * Event handling for a error during a proces.
	 * 
	 * @param process {@code Process} that throws the error
	 * @return {@code false} to stop further execution
	 */
	public function onProcessError(process:Process, error):Boolean {
		return false;
	}

	/** 
	 * Returns the {@code TestResult} to the {@code TestSuite}.
	 * 
	 * <p>The returned {@code TestResult} may not be complete. This is the case
	 * if the test has not been executed or has not finished yet.
	 * 
	 * @return {@link TestResult} for the {@code TestSuite} that contains all informations
	 */
	public function getTestResult(Void):TestResult {
		return testResult;
	}
	
	/**
	 * Returns the current executing {@code TestCaseResult}.
	 * 
	 * <p>It is necessary to get the {@code TestCaseResult} for the {@code TestCase}
	 * that just gets executed because there can be more than one {@code TestCase}
	 * available within a {@code TestResult}. 
	 * 
	 * @return {@code TestResult} to the current executing {@code TestCase}
	 */
	public function getCurrentTestCase(Void):TestCaseResult {
		return list[current].getCurrentTestCase();
	}
	
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
	public function getCurrentTestCaseMethodInfo(Void):TestCaseMethodInfo {
		return list[current].getCurrentTestCaseMethodInfo();
	}
}