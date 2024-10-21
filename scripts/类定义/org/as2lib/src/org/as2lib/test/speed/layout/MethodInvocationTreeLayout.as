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
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.test.speed.TestResultLayout;
import org.as2lib.test.speed.TestSuiteResult;
import org.as2lib.test.speed.MethodInvocation;
import org.as2lib.test.speed.MethodInvocationTestSuiteResult;
import org.as2lib.test.speed.ConfigurableTestSuiteResult;
import org.as2lib.test.speed.SimpleTestSuiteResult;

/**
 * {@code MethodInvocationTreeLayout} lays test suite results out in a tree like
 * structure. The method invocations are ordered by their invocation succession and by
 * which-invocation-caused-which-other-invocation.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.layout.MethodInvocationTreeLayout extends BasicClass implements TestResultLayout {
	
	/** All method invocations of the test suite result to lay-out. */
	private var allMethodInvocations:Array;
	
	/**
	 * Constructs a new {@code MethodInvocationTreeLayout} instance.	 */
	public function MethodInvocationTreeLayout(Void) {
	}
	
	/**
	 * Lays the passed-in {@code testSuiteResult} out as method invocation tree and
	 * returns a new lay-outed test suite result.
	 * 
	 * @param testSuiteResult the test suite result to lay-out
	 * @return the lay-outed test suite result
	 */
	public function layOut(testSuiteResult:TestSuiteResult):TestSuiteResult {
		if (!testSuiteResult) throw new IllegalArgumentException("Argument 'testSuiteResult' [" + testSuiteResult + "] must not be 'null' nor 'undefined'.", this, arguments);
		var result:SimpleTestSuiteResult = new SimpleTestSuiteResult(testSuiteResult.getName());
		this.allMethodInvocations = testSuiteResult.getAllMethodInvocations();
		if (this.allMethodInvocations) {
			var rootMethodInvocations:Array = findRootMethodInvocations();
			buildMethodInvocationTree(result, rootMethodInvocations);
		}
		result.sort(SimpleTestSuiteResult.METHOD_INVOCATION_SUCCESSION);
		return result;
	}
	
	/**
	 * Returns an array that contains all root method invocations. Root method
	 * invocations are the ones that have no parent method invocation.
	 * 
	 * @return all root method invocations as {@link MethodInvocation} instances	 */
	private function findRootMethodInvocations(Void):Array {
		return findChildMethodInvocations(null);
	}
	
	/**
	 * Finds the child method invocations for the passed-in
	 * {@code parentMethodInvocation} and returns them as {@link MethodInvocation}
	 * instances.
	 * 
	 * @param parentMethodInvocations the method invocation to return the childs for
	 * @return the child method invocations of the parent method invocation	 */
	private function findChildMethodInvocations(parentMethodInvocation:MethodInvocation):Array {
		var result:Array = new Array();
		for (var i:Number = 0; i < this.allMethodInvocations.length; i++) {
			var methodInvocation:MethodInvocation = this.allMethodInvocations[i];
			if (methodInvocation.getCaller() == parentMethodInvocation) {
				result.push(methodInvocation);
			}
		}
		return result;
	}
	
	/**
	 * Builds the method invocation tree starting from the passed-in
	 * {@code methodInvocations} and adding all results to the passed-in
	 * {@code testSuiteResult}. This is done recursively.
	 * 
	 * @param testSuiteResult the result to add sub-results
	 * @param methodInvocations {@link MethodInvocation} instances to start at	 */
	private function buildMethodInvocationTree(testSuiteResult:ConfigurableTestSuiteResult, methodInvocations:Array):Void {
		if (testSuiteResult && methodInvocations) {
			for (var i:Number = 0; i < methodInvocations.length; i++) {
				var methodInvocation:MethodInvocation = methodInvocations[i];
				var p:MethodInvocationTestSuiteResult = new MethodInvocationTestSuiteResult(methodInvocation);
				testSuiteResult.addTestResult(p);
				var childMethodInvocations:Array = findChildMethodInvocations(methodInvocation);
				buildMethodInvocationTree(p, childMethodInvocations);
			}
		}
	}
	
}