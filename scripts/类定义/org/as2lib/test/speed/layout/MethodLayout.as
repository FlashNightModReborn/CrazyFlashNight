﻿/*
 * Copyright the original author or authors.
 * 
 * Licensed under the Mozilla Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.mozilla.org/MPL/2.0/
 *
 * This file may be redistributed under the terms of the GNU General Public License,
 * version 3.0 (GPLv3), or any later version.
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.core.BasicClass;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.test.speed.TestResultLayout;
import org.as2lib.test.speed.TestSuiteResult;
import org.as2lib.test.speed.MethodInvocation;
import org.as2lib.test.speed.ConfigurableTestSuiteResult;
import org.as2lib.test.speed.SimpleTestSuiteResult;

/**
 * {@code MethodLayout} lays test results out with methods as root elements of the
 * structure.
 * 
 * @author Simon Wacker
 */
class org.as2lib.test.speed.layout.MethodLayout extends BasicClass implements TestResultLayout {
	
	/** The result of the lay-outing of the current test suite result. */
	private var result:ConfigurableTestSuiteResult;
	
	/** All method invocations of the test suite result to lay-out. */
	private var methodInvocations:Array;
	
	/**
	 * Constructs a new {@code MethodLayout} instance.
	 */
	public function MethodLayout(Void) {
	}
	
	/**
	 * Lays the passed-in {@code testSuiteResult} out with methods as root elements of
	 * the structure and returns a new lay-outed test suite result.
	 * 
	 * @param testSuiteResult the test suite result to lay-out
	 * @return the lay-outed test suite result
	 */
	public function layOut(testSuiteResult:TestSuiteResult):TestSuiteResult {
		this.result = new SimpleTestSuiteResult(testSuiteResult.getName());
		this.methodInvocations = testSuiteResult.getAllMethodInvocations();
		for (var i:Number = 0; i < this.methodInvocations.length; i++) {
			var methodInvocation:MethodInvocation = this.methodInvocations[i];
			i -= addMethodInvocations(methodInvocation.getMethod());
		}
		this.result.sort(SimpleTestSuiteResult.TIME, true);
		return this.result;
	}
	
	/**
	 * Adds all method invocations of the passed-in {@code method} to the result and
	 * removes the added invocations from the {@code methodInvocations} array.
	 * 
	 * @param method the method to add the invocations for
	 * @return the number of method invocations added
	 */
	private function addMethodInvocations(method:MethodInfo):Number {
		var count:Number = 0;
		var methodResult:ConfigurableTestSuiteResult = new SimpleTestSuiteResult(method.getFullName());
		for (var i:Number = 0; i < this.methodInvocations.length; i++) {
			var methodInvocation:MethodInvocation = this.methodInvocations[i];
			if (methodInvocation.getMethod() == method) {
				methodResult.addTestResult(methodInvocation);
				this.methodInvocations.splice(i, 1);
				i--;
				count++;
			}
		}
		this.result.addTestResult(methodResult);
		return count;
	}
	
}