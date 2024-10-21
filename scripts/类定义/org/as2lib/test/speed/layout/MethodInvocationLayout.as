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
import org.as2lib.test.speed.TestResultLayout;
import org.as2lib.test.speed.TestSuiteResult;
import org.as2lib.test.speed.SimpleTestSuiteResult;
import org.as2lib.test.speed.MethodInvocation;

/**
 * {@code MethodInvocationLayout} lays test results out with method invocations as root
 * elements of the structure.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.layout.MethodInvocationLayout extends BasicClass implements TestResultLayout {
	
	/**
	 * Constructs a new {@code MethodInvocationLayout} instance.	 */
	public function MethodInvocationLayout(Void) {
	}
	
	/**
	 * Lays the passed-in {@code testSuiteResult} out with method invocations as root
	 * element of the structure and returns the new lay-outed test suite result.
	 * 
	 * @param testSuiteResult the test suite result to lay-out
	 * @return the lay-outed test suite result
	 */
	public function layOut(testSuiteResult:TestSuiteResult):TestSuiteResult {
		var result:SimpleTestSuiteResult = new SimpleTestSuiteResult(testSuiteResult.getName());
		var methodInvocations:Array = testSuiteResult.getAllMethodInvocations();
		for (var i:Number = 0; i < methodInvocations.length; i++) {
			var methodInvocation:MethodInvocation = MethodInvocation(methodInvocations[i]);
			if (methodInvocation) {
				result.addTestResult(methodInvocation);
			}
		}
		result.sort(SimpleTestSuiteResult.TIME, true);
		return result;
	}
	
}