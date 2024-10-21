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

import org.as2lib.test.speed.TestResult;

/**
 * {@code TestSuiteResult} holds the result of a test suite's execution.
 * 
 * @author Simon Wacker */
interface org.as2lib.test.speed.TestSuiteResult extends TestResult {
	
	/**
	 * Returns the time needed per method invocation.
	 * 
	 * @return the time needed per method invocation
	 */
	public function getAverageTime(Void):Number;
	
	/**
	 * Returns all profiled method invocations as {@link MethodInvocation} instances.
	 * 
	 * @return all profiled method invocations as {@code MethodInvocation} instances
	 */
	public function getAllMethodInvocations(Void):Array;
	
	/**
	 * Returns whether this result has any method invocations.
	 * 
	 * @return {@code true} if this result has method invocations else {@code false}
	 */
	public function hasMethodInvocations(Void):Boolean;
	
	/**
	 * Returns the total number of method invocations.
	 * 
	 * @return the total number of method invocations
	 */
	public function getMethodInvocationCount(Void):Number;
	
	/**
	 * Returns the percentage of method invocations in relation to the passed-in
	 * {@code totalMethodInvocationCount}.
	 * 
	 * @param totalMethodInvocationCount the total number of method invocations to
	 * calculate the percentage with
	 * @return the percentage of method invocations of this result
	 */
	public function getMethodInvocationPercentage(totalMethodInvocationCount:Number):Number;
	
	/**
	 * Returns all test results as {@link TestResult} instances directly of this test
	 * suite.
	 * 
	 * @return all test results of this test suite
	 */
	public function getTestResults(Void):Array;
	
	/**
	 * Returns whether this test suite result has sub-test results.
	 * 
	 * @return {@code true} if this test suite has sub-test results else {@code false}
	 */
	public function hasTestResults(Void):Boolean;
	
	/**
	 * Returns the number of sub-test results.
	 * 
	 * @return the number of sub-test results
	 */
	public function getTestResultCount(Void):Number;
	
	/**
	 * Sorts this test suite result and its sub-test results.
	 * 
	 * @param property the property to sort by
	 * @param descending determines whether to sort descending {@code true} or
	 * ascending {@code false}
	 */
	public function sort(property:Number, descending:Boolean):Void;
	
}