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
import org.as2lib.data.holder.array.TypedArray;
import org.as2lib.test.unit.TestResult;
import org.as2lib.test.unit.TestCaseResult;
import org.as2lib.test.unit.TestSuite;
import org.as2lib.util.StringUtil;
import org.as2lib.data.type.Time;

/**
 * {@code TestSuiteResult} contains all informations about the execution of a {@code TestSuite}.
 * 
 * <p>{@link TestSuite} contains all states of execution of the {@code TestSuite}
 * and {@code TestSuiteResult} contains all informations about the execution.
 * 
 * @author Martin Heidegger.
 * @version 1.0
 * @see TestSuite
 */
class org.as2lib.test.unit.TestSuiteResult extends BasicClass implements TestResult {

	/** Related {@code TestSuite}. */
	private var testSuite:TestSuite;
	
	/** {@code TestResults} to the {@code TestSuite}. */
	private var testResults:TypedArray;

	/**
	 * Constructs a new {@code TestSuiteResult}.
	 * 
	 * @param testSuite related {@code TestSuite}
	 */
	public function TestSuiteResult(testSuite:TestSuite) {
		this.testSuite = testSuite;
		testResults = new TypedArray(TestResult);
		
		var tests:Array = testSuite.getTests();
		for (var i:Number=0; i<tests.length; i++) {
			addTest(tests[i]);
		}
	}
	
	/**
	 * Adds a {@code TestResult} to the {@code TestSuiteResult}.
	 * 
	 * @param test {@code TestResult} to be added
	 */
	public function addTest(test:TestResult):Void {
		testResults.unshift(test);
	}
	
	/**
	 * Returns all {@code TestResult) in a {@link TypedArray} contained in the
	 * {@code TestSuite}.
	 * 
	 * @return list of all {@code TestResult}s
	 */
	public function getTests(Void):TypedArray {
		return this.testResults;
	}
	
	/**
	 * Returns the percentage ({@code 0}-{@code 100}) of the added {@code Test}s.
	 * 
	 * @return percentage of execution
	 */
	public function getPercentage(Void):Number {
		var result:Number = 0;
		var unit:Number = 100/this.testResults.length;
		for (var i:Number = this.testResults.length - 1; i >= 0; i--) {
			result += (unit/100*this.testResults[i].getPercentage());
		}
		return result;
	}
	
	/**
	 * Returns {@code true} if the {@code TestSuite} has been finished.
	 * 
	 * @return {@code true} if the {@code TestSuite} has been finished
	 */
	public function hasFinished(Void):Boolean {
		for (var i:Number = this.testResults.length - 1; i >= 0; i--) {
			if (!this.testResults[i].isFinished()) {
				return false;
			}
		}
		return true;
	}
	
	/**
	 * Returns {@code true} if the {@code TestSuite} has been started.
	 * 
	 * @return {@code true} if the {@code TestSuite} has been started
	 */
	public function hasStarted(Void):Boolean {
		for (var i:Number = this.testResults.length - 1; i >= 0; i--) {
			if (this.testResults[i].hasStarted()) {
				return true;
			}
		}
		return false;
	}
		
	/**
	 * Returns all {@code TestResult}s for the {@code Test}s contained
	 * within the related {@code TestSuite}.
	 * 
	 * <p>Since its possible to add more than one {@code Test} to a {@code TestSuite}
	 * its necessary to get the {@code TestResult}s to all added {@code Test}s.
	 *
	 * <p>It flattens out all {@code TestResults}, this means it concats all
	 * {@code getTestResults} of every added {@code Test}. 
	 * 
	 * @return all {@code TestResult}s to all contained {@code Test}s
	 */
	public function getTestResults(Void):TypedArray {
		var result:TypedArray = new TypedArray(TestResult);
		for (var i:Number=0; i<this.testResults.length; i++) {
			// TODO: Bug? Why can't i use .concat ???
			var testCases:Array = this.testResults[i].getTestResults();
			for (var j:Number=0; j<testCases.length; j++) {
				result.push(testCases[j]);
			}
		}
		return result;
	}
	
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
	public function getTestCaseResults(Void):TypedArray {
		var result:TypedArray = new TypedArray(TestCaseResult);
		for (var i:Number=0; i<this.testResults.length; i++) {
			// TODO: Bug? Why can't i use .concat ???
			var testCases:Array = this.testResults[i].getTestCaseResults();
			for (var j:Number=0; j<testCases.length; j++) {
				result.push(testCases[j]);
			}
		}
		return result;
	}
	
	/**
	 * Retuns the name of the {@code TestSuite}.
	 * 
	 * @return name of the {@code TestSuite}
	 */
	public function getName(Void):String {
		return this.getTestSuite().getName();
	}
	
	/**
	 * Returns the total operation time for all methods executed for the
	 * related {@code TestSuite}.
	 * 
	 * @return total operation time of the {@code Test}
	 */
	public function getOperationTime(Void):Time {
		var result:Number = 0;
		for (var i:Number = this.testResults.length - 1; i >= 0; i--) {
			result += this.testResults[i].getOperationTime();
		}
		return new Time(result);
	}
	
	
	/**
	 * Returns {@code true} if the errors occured during the execution of the
	 * related {@code Test}.
	 * 
	 * @return {@code true} if the errors occured during the execution of the
	 * 		   related {@code Test}.
	 */
	public function hasErrors(Void):Boolean {
		for (var i:Number = this.testResults.length - 1; i >= 0; i--) {
			if (this.testResults[i].hasErrors()) {
				return true;
			}
		}
		return false;
	}
	
	/**
	 * Returns the related {@coee TestSuite}.
	 * 
	 * @return related {@code TestSuite}
	 */
	public function getTestSuite(Void):TestSuite {
		return this.testSuite;
	}


	/**
	 * Extended .toString implementation.
	 * 
	 * @return {@code TestSuiteResult} as well formated {@code String}
	 */
	public function toString():String {
		var result:String;
		var titleLength:Number;
		result = "*** TestSuite "+getName()+" ("+testResults.length+" Tests) ["+getOperationTime()+"ms] ***";
		titleLength = result.length;
		for (var i:Number = 0; i < testResults.length; i++){
			result += "\n"+StringUtil.addSpaceIndent(this.testResults[i].toString(), 2);
		}
		result += "\n"+StringUtil.multiply("*", titleLength);
		return result;
	}
	
}