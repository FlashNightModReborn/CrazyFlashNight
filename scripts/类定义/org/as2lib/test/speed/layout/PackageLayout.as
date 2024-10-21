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
import org.as2lib.env.reflect.PackageInfo;
import org.as2lib.test.speed.TestResultLayout;
import org.as2lib.test.speed.TestSuiteResult;
import org.as2lib.test.speed.MethodInvocation;
import org.as2lib.test.speed.ConfigurableTestSuiteResult;
import org.as2lib.test.speed.SimpleTestSuiteResult;
import org.as2lib.test.speed.layout.ClassLayout;

/**
 * {@code PackageLayout} lays test suite results out with packages as root elements of
 * the structure.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.layout.PackageLayout extends BasicClass implements TestResultLayout {
	
	/** The result of the lay-outing of the current test suite result. */
	private var result:ConfigurableTestSuiteResult;
	
	/** All method invocations of the test suite result to lay-out. */
	private var methodInvocations:Array;
	
	/**
	 * Constructs a new {@code PackageLayout} instance.	 */
	public function PackageLayout(Void) {
	}
	
	/**
	 * Lays the passed-in {@code testSuiteResult} out with packages as root elements of
	 * the structure and returns the new lay-outed test suite result.
	 * 
	 * @param testSuiteResult the test suite result to lay-out
	 * @return the lay-outed test suite result
	 * @todo support multiple package layers, not just the one of the declaring type
	 */
	public function layOut(testSuiteResult:TestSuiteResult):TestSuiteResult {
		this.result = new SimpleTestSuiteResult(testSuiteResult.getName());
		this.methodInvocations = testSuiteResult.getAllMethodInvocations();
		for (var i:Number = 0; i < this.methodInvocations.length; i++) {
			var methodInvocation:MethodInvocation = this.methodInvocations[i];
			i -= addMethodInvocations(methodInvocation.getMethod().getDeclaringType().getPackage());
		}
		this.result.sort(SimpleTestSuiteResult.NAME);
		return this.result;
	}
	
	/**
	 * Adds all method invocations of methods of the passed-in {@code package} to the
	 * result and removes these invocations from the {@code methodInvocations} array.
	 * 
	 * @param package the package to add method invocations for
	 * @return the number of removed method invocations	 */
	private function addMethodInvocations(package:PackageInfo):Number {
		var count:Number = 0;
		var classResult:ConfigurableTestSuiteResult = new SimpleTestSuiteResult(package.getFullName());
		for (var i:Number = 0; i < this.methodInvocations.length; i++) {
			var methodInvocation:MethodInvocation = this.methodInvocations[i];
			if (methodInvocation.getMethod().getDeclaringType().getPackage() == package) {
				classResult.addTestResult(methodInvocation);
				this.methodInvocations.splice(i, 1);
				i--;
				count++;
			}
		}
		this.result.addTestResult((new ClassLayout()).layOut(classResult));
		return count;
	}
	
}