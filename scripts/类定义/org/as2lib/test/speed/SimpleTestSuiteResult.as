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

import org.as2lib.util.StringUtil;
import org.as2lib.test.speed.TestSuiteResult;
import org.as2lib.test.speed.ConfigurableTestSuiteResult;
import org.as2lib.test.speed.AbstractTestSuiteResult;
import org.as2lib.test.speed.TestResult;
import org.as2lib.test.speed.MethodInvocationHolder;

/**
 * {@code SimpleTestSuiteResult} holds the results of all tests contained by a test suite.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.SimpleTestSuiteResult extends AbstractTestSuiteResult implements ConfigurableTestSuiteResult {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractTestSuiteResult;
	
	/** Name of this result. */
	private var name:String;
	
	/**
	 * Constructs a new {@code SimpleTestSuiteResult} instance.
	 * 
	 * @param name the name of this result	 */
	public function SimpleTestSuiteResult(name:String) {
		this.name = name;
	}
	
	/**
	 * Returns the name of this test result.
	 * 
	 * @return the name of this test result	 */
	public function getName(Void):String {
		return this.name;
	}
	
	/**
	 * Returns the total invocation time in milliseconds.
	 * 
	 * @return the total invocation time in milliseconds
	 */
	public function getTime(Void):Number {
		var result:Number = 0;
		for (var i:Number = 0; i < this.testResults.length; i++) {
			var testResult:TestResult = this.testResults[i];
			result += testResult.getTime();
		}
		return result;
	}
	
	/**
	 * Returns the string representation of this test suite result. This includes the
	 * string representation of all added test results.
	 * 
	 * @param rootTestResult test result that holds the total values needed for
	 * percentage calculations
	 * @return the string representation of this test suite result
	 */
	public function toString():String {
		var rootTestResult:TestSuiteResult = TestSuiteResult(arguments[0]);
		if (!rootTestResult) rootTestResult = getThis();
		var result:String = getTimePercentage(rootTestResult.getTime()) + "%";
		result += ", " + getThis().getTime() + " ms";
		result += " - " + getMethodInvocationPercentage(rootTestResult.getMethodInvocationCount()) + "%";
		result += ", " + getMethodInvocationCount() + " inv.";
		result += " - " + getAverageTime() + " ms/inv.";
		if (getTestResultCount() == 1 && !(this.testResults[0] instanceof TestSuiteResult)) {
			result += " - " + this.testResults[0].getName();
		} else if (getTestResultCount() == 1 && !TestSuiteResult(this.testResults[0]).hasMethodInvocations()) {
			result += " - " + this.testResults[0].getName();
		} else {
			result += " - " + getThis().getName();
			var totalTime:Number = getThis().getTime();
			for (var i:Number = 0; i < this.testResults.length; i++) {
				var testResult:TestResult = this.testResults[i];
				if (TestSuiteResult(testResult).hasMethodInvocations()
						|| !(testResult instanceof TestSuiteResult)
						|| testResult instanceof MethodInvocationHolder) {
					result += "\n";
					result += StringUtil.addSpaceIndent(testResult.toString(rootTestResult), 2);
				}
			}
		}
		return result;
	}
	
}