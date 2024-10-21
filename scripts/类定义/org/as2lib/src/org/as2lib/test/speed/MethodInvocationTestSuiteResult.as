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
import org.as2lib.test.speed.MethodInvocationHolder;
import org.as2lib.test.speed.AbstractTestSuiteResult;
import org.as2lib.test.speed.TestResult;
import org.as2lib.test.speed.MethodInvocation;

/**
 * {@code MethodInvocationTestSuiteResult} holds multiple sub-test results and is based
 * on a method invocation.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.MethodInvocationTestSuiteResult extends AbstractTestSuiteResult implements ConfigurableTestSuiteResult, MethodInvocationHolder {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractTestSuiteResult;
	
	/** The wrapped method invocation. */
	private var methodInvocation:MethodInvocation;
	
	/**
	 * Constructs a new {@code MethodInvocationTestSuiteResult} instance.
	 * 
	 * @param methodInvocation the method invocation to wrap	 */
	public function MethodInvocationTestSuiteResult(methodInvocation:MethodInvocation) {
		this.methodInvocation = methodInvocation;
	}
	
	/**
	 * Returns the held method invocation.
	 * 
	 * @return the held method invocation	 */
	public function getMethodInvocation(Void):MethodInvocation {
		return this.methodInvocation;
	}
	
	/**
	 * Returns the name of this test result. This is the name of the wrapped method
	 * invocation.
	 * 
	 * @return the name of this test result	 */
	public function getName(Void):String {
		return this.methodInvocation.getName();
	}
	
	/**
	 * Returns the total invocation time in milliseconds.
	 * 
	 * @return the total invocation time in milliseconds
	 */
	public function getTime(Void):Number {
		return this.methodInvocation.getTime();
	}
	
	/**
	 * Returns the string representation of this test result. This includes the string
	 * representation of all sub-tests.
	 * 
	 * @param rootTestResult test result that holds the total values needed for
	 * percentage calculations
	 * @return the string representation of this test result
	 */
	public function toString():String {
		var rootTestResult:TestSuiteResult = TestSuiteResult(arguments[0]);
		if (!rootTestResult) rootTestResult = getThis();
		var result:String = getTimePercentage(rootTestResult.getTime()) + "%";
		result += ", " + getThis().getTime() + " ms";
		result += " - " + getMethodInvocationPercentage(rootTestResult.getMethodInvocationCount()) + "%";
		result += ", " + getMethodInvocationCount() + " inv.";
		result += " - " + getAverageTime() + " ms/inv.";
		result += " - " + getName();
		if (hasTestResults()) {
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